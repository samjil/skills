#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""sub-agent: agy(Google Antigravity CLI)와 opencode 를 한 인터페이스로 묶은 읽기 전용 서브 에이전트 호출기.

Claude 가 큰 파일·로그를 직접 읽지 않고 "파일 경로 + 질문"만 넘기면, 이 스크립트가 디스크에서 파일(과 줄 범위)을
읽어 서브 에이전트에게 주고, 핵심 결론만 압축한 답을 stdout 으로 돌려준다.

  python sub-agent.py -f "src/OrderService.java:100-250" -f logs/error.log -q "롤백이 안 되는 원인"
  python sub-agent.py --engine opencode -f app.py -q "버그 추적"
  python sub-agent.py --check                      # 설치·인증 상태 점검

표준 출력 = 답변만. 어떤 엔진을 썼는지·폴백 이유는 표준 오류에 한 줄로 낸다. 종료 코드: 0 성공 / 1 모든 엔진 실패 / 2 사용법 오류.
표준 라이브러리만 쓴다(Python 3.8+).
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import json

DEFAULT_AGY_MODELS = "gemini-3.8-flash-high,gemini-3.7-flash-high"
DEFAULT_OPENCODE_MODEL = "openrouter/qwen/qwen3-coder:free"
RATE_LIMIT_RE = re.compile(r"(?i)(quota|rate.?limit|\b429\b|resource.?exhausted|overloaded|unavailable|capacity|too many requests|exceeded|throttl)")
ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
GREETING_RE = re.compile(r"^\s*(안녕|네[,.!]|물론|좋습니다|알겠습니다|sure|certainly|of course|here is|here's|i'll|i will)", re.I)
CODE_EXT = {".py", ".java", ".kt", ".js", ".ts", ".tsx", ".jsx", ".go", ".rs", ".c", ".cc", ".cpp", ".h", ".hpp", ".cs", ".ps1", ".sql", ".sh", ".rb", ".php", ".swift", ".vue", ".xml", ".json", ".yml", ".yaml", ".html", ".css"}

SYSTEM_RULES = """당신은 메인 AI(Claude)를 돕는 읽기 전용 서브 에이전트다. 출력은 메인 AI 가 그대로 파싱해 쓴다.
규칙:
1. 인사말·서론·맺음말·사과·부연 설명을 쓰지 않는다. 질문에 대한 핵심 결론만 쓴다.
2. 개조식(짧은 불릿)으로 쓴다. 첫 줄은 "결론: ..." 한 줄. 이어서 근거를 "- 파일:줄번호 사실" 형식으로 쓴다. 줄 번호는 아래 파일 본문의 "NNNN|" 접두어를 그대로 쓴다.
3. 코드를 고치자면 변경이 필요한 줄과 바꿀 내용만 쓴다. 파일 전체를 다시 쓰지 않는다.
4. 확인하지 못한 것은 추측하지 말고 "확인 불가: 이유"로 적는다.
5. 파일을 수정·생성·삭제하거나 명령을 실행하지 않는다(읽기만 한다).
6. 전체 {max_lines}줄 이내. 답변 언어: {lang}.
"""


class EngineError(Exception):
    def __init__(self, message, retriable=True):
        super().__init__(message)
        self.retriable = retriable


# ------------------------------ 설정(.env) ------------------------------
def load_env_files(extra_path=None):
    """스크립트 옆 .env, ~/.sub-agent/.env, 현재 폴더 .env 를 읽는다(이미 설정된 환경변수는 덮어쓰지 않는다)."""
    cands = [os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"),
             os.path.join(os.path.expanduser("~"), ".sub-agent", ".env"), os.path.join(os.getcwd(), ".env")]
    if extra_path:
        cands.insert(0, extra_path)
    for p in cands:
        try:
            with open(p, "r", encoding="utf-8-sig") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#") or "=" not in line:
                        continue
                    k, v = line.split("=", 1)
                    k = k.strip()
                    if k.lower().startswith("export "):
                        k = k[7:].strip()
                    v = v.strip().strip('"').strip("'")
                    if k and k not in os.environ:
                        os.environ[k] = v
        except OSError:
            continue


# ------------------------------ 파일 주입 ------------------------------
_RANGE_RE = re.compile(r"^(?P<path>.+?):(?:(?P<a>\d*)-(?P<b>\d*)|(?P<n>\d+))$")


def parse_file_spec(spec):
    """'경로', '경로:100-250', '경로:100-', '경로:-50', '경로:75' -> (경로, 시작, 끝). 줄은 1부터, 없으면 None."""
    m = _RANGE_RE.match(spec)
    if m and not os.path.exists(spec):
        if m.group("n"):
            n = int(m.group("n"))
            return m.group("path"), n, n
        a, b = m.group("a"), m.group("b")
        return m.group("path"), (int(a) if a else None), (int(b) if b else None)
    return spec, None, None


def read_text(path):
    with open(path, "rb") as f:
        data = f.read()
    for enc in ("utf-8-sig", "cp949"):
        try:
            return data.decode(enc)
        except UnicodeDecodeError:
            continue
    return data.decode("utf-8", errors="replace")


def render_file(spec, max_bytes):
    """파일(또는 줄 범위)을 '줄번호|내용' 으로 만든다. 돌려주는 값: (본문 텍스트, 바이트 수, 디렉터리 여부)."""
    path, a, b = parse_file_spec(spec)
    path = os.path.abspath(os.path.expanduser(path))
    if os.path.isdir(path):
        return "### 디렉터리: %s\n(내용을 미리 주입하지 않았다. 필요한 파일을 직접 찾아 읽어라.)\n" % path, 0, True
    if not os.path.isfile(path):
        raise EngineError("파일이 없습니다: %s" % path, retriable=False)
    lines = read_text(path).splitlines()
    total = len(lines)
    start = a if a else 1
    end = b if b else total
    if start < 1 or start > max(total, 1) or end < start:
        raise EngineError("줄 범위가 맞지 않습니다: %s (전체 %d줄)" % (spec, total), retriable=False)
    end = min(end, total)
    picked = lines[start - 1:end]
    width = max(4, len(str(end)))
    note = ""
    body = "\n".join("%s|%s" % (str(start + i).rjust(width, "0"), ln) for i, ln in enumerate(picked))
    if len(body.encode("utf-8")) > max_bytes:
        # 로그는 끝쪽이 중요하고, 나머지는 앞쪽이 중요하다.
        keep_tail = path.lower().endswith((".log", ".txt", ".out"))
        out, size = [], 0
        seq = range(len(picked) - 1, -1, -1) if keep_tail else range(len(picked))
        for i in seq:
            row = "%s|%s" % (str(start + i).rjust(width, "0"), picked[i])
            size += len(row.encode("utf-8")) + 1
            if size > max_bytes:
                break
            out.append(row)
        if keep_tail:
            out.reverse()
        body = "\n".join(out)
        note = "\n(파일이 커서 %s %d줄만 주입함 — 전체 %d줄. 줄 범위를 지정하면 더 볼 수 있다.)" % ("끝" if keep_tail else "앞", len(out), len(picked))
    header = "### 파일: %s  (줄 %d-%d / 전체 %d줄)\n" % (path, start, end, total)
    return header + body + note + "\n", len(body.encode("utf-8")), False


def build_bundle(query, specs, max_file_bytes, max_lines, lang):
    parts = [SYSTEM_RULES.format(max_lines=max_lines, lang=lang), "\n## 질문\n" + query.strip() + "\n"]
    total, dirs, count = 0, [], 0
    if specs:
        parts.append("\n## 파일 본문\n")
    for s in specs:
        text, size, is_dir = render_file(s, max_file_bytes)
        parts.append(text + "\n")
        total += size
        count += 1
        if is_dir:
            dirs.append(os.path.abspath(os.path.expanduser(parse_file_spec(s)[0])))
    return "\n".join(parts), {"bytes": total, "files": count, "dirs": dirs}


# ------------------------------ 프로세스 실행 ------------------------------
def kill_tree(proc):
    try:
        if os.name == "nt":
            subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"], capture_output=True)
        else:
            proc.kill()
    except Exception:
        pass


def run_cli(cmd, cwd, timeout, env):
    try:
        proc = subprocess.Popen(cmd, cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError as e:
        raise EngineError("실행하지 못했습니다: %s" % e)
    try:
        out, err = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        kill_tree(proc)
        try:
            proc.communicate(timeout=5)
        except Exception:
            pass
        raise EngineError("타임아웃(%d초)" % timeout)
    dec = lambda b: b.decode("utf-8", errors="replace")
    return proc.returncode, dec(out), dec(err)


def clean_output(text, max_chars):
    text = ANSI_RE.sub("", text).replace("\r\n", "\n").strip()
    lines = text.split("\n")
    while lines and (not lines[0].strip() or GREETING_RE.match(lines[0])) and len(lines) > 1:
        lines.pop(0)
    text = "\n".join(lines).strip()
    if len(text) > max_chars:
        text = text[:max_chars].rstrip() + "\n(…출력이 길어 %d자에서 잘랐다)" % max_chars
    return text


# ------------------------------ 엔진 ------------------------------
def engine_agy(bundle_path, meta, args, env):
    exe = shutil.which("agy")
    if not exe:
        raise EngineError("agy 가 설치돼 있지 않습니다(PATH 에 없음)")
    models = [m.strip() for m in os.environ.get("SUB_AGENT_AGY_MODELS", DEFAULT_AGY_MODELS).split(",") if m.strip()]
    if args.agy_model:
        models = [args.agy_model]
    prompt = "Read the file %s and follow the instructions in it exactly. Output only the final answer." % bundle_path
    last = None
    for model in models or [None]:
        cmd = [exe, "-p", prompt, "--output-format", "json", "--add-dir", os.path.dirname(bundle_path)]
        for d in meta["dirs"]:
            cmd += ["--add-dir", d]
        if model:
            cmd += ["--model", model]
        if os.environ.get("SUB_AGENT_AGY_SKIP_PERMISSIONS") == "1":
            cmd.append("--dangerously-skip-permissions")
        try:
            code, out, err = run_cli(cmd, args.cwd, args.timeout, env)
        except EngineError as e:
            last = e
            if "타임아웃" in str(e):
                raise                      # 같은 엔진의 다른 모델로 또 기다리지 않고 바로 다음 엔진으로
            continue
        text = None
        try:
            obj = json.loads(out)
            if isinstance(obj, dict):
                if str(obj.get("status", "")).upper() == "ERROR" or not obj.get("response"):
                    detail = str(obj.get("error") or obj.get("message") or obj.get("response") or err or out)[:500]
                    last = EngineError("agy 오류(%s): %s" % (model, detail))
                    if RATE_LIMIT_RE.search(detail):
                        continue           # 쿼터 초과 -> 다음 모델
                    raise last
                text = str(obj["response"])
        except ValueError:
            pass
        if text is None:
            if code != 0:
                detail = (err or out)[:500]
                last = EngineError("agy 종료 코드 %s: %s" % (code, detail))
                if RATE_LIMIT_RE.search(detail):
                    continue
                raise last
            text = out
        return text, "agy" + ("/" + model if model else "")
    raise last or EngineError("agy 호출 실패")


def engine_opencode(bundle_path, meta, args, env):
    exe = shutil.which("opencode")
    if not exe:
        raise EngineError("opencode 가 설치돼 있지 않습니다(npm install -g opencode-ai)")
    model = args.opencode_model or os.environ.get("SUB_AGENT_OPENCODE_MODEL", DEFAULT_OPENCODE_MODEL)
    # 지시·질문·파일 본문은 모두 첨부 파일에 있다. 명령줄 인자는 ASCII 고정 문장만 쓴다(.cmd 셸 따옴표·코드페이지 문제 회피).
    cmd = [exe, "run", "--model", model, "--file", bundle_path, "Follow the instructions in the attached file exactly. Output only the final answer."]
    code, out, err = run_cli(cmd, meta["dirs"][0] if meta["dirs"] else args.cwd, args.timeout, env)
    text = ANSI_RE.sub("", out).strip()
    if code != 0 or not text:
        raise EngineError("opencode 종료 코드 %s: %s" % (code, (err or out or "빈 응답")[:500]))
    return text, "opencode/" + model


ENGINES = {"agy": engine_agy, "opencode": engine_opencode}


def choose_order(args, meta, specs):
    if args.engine in ENGINES:
        first = args.engine
    else:
        big = meta["bytes"] > args.big_bytes or meta["dirs"] or not specs
        exts = {os.path.splitext(parse_file_spec(s)[0])[1].lower() for s in specs}
        precise = specs and meta["files"] <= 3 and exts and exts <= CODE_EXT and not big
        first = "opencode" if precise else "agy"
    order = [first] + [e for e in ("agy", "opencode") if e != first]
    return order[:1] if args.no_fallback else order


# ------------------------------ 점검 ------------------------------
def do_check():
    print("python: %s" % sys.version.split()[0])
    for name in ("agy", "opencode"):
        p = shutil.which(name)
        print("%s: %s" % (name, p or "없음"))
    if shutil.which("opencode"):
        try:
            code, out, err = run_cli([shutil.which("opencode"), "auth", "list"], None, 20, os.environ.copy())
            print("opencode auth list:\n" + ANSI_RE.sub("", out or err).strip())
        except EngineError as e:
            print("opencode auth list 실패: %s" % e)
    print("OPENROUTER_API_KEY(환경변수·.env): %s" % ("있음" if os.environ.get("OPENROUTER_API_KEY") else "없음"))
    print("agy 모델 순서: %s" % os.environ.get("SUB_AGENT_AGY_MODELS", DEFAULT_AGY_MODELS))
    print("opencode 모델: %s" % os.environ.get("SUB_AGENT_OPENCODE_MODEL", DEFAULT_OPENCODE_MODEL))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description="agy · opencode 통합 서브 에이전트 (읽기 전용, 핵심 결론만 출력)")
    ap.add_argument("-q", "--query", help="서브 에이전트에게 할 질문")
    ap.add_argument("-f", "--file", action="append", default=[], help="분석할 파일. 경로[:시작-끝]. 여러 번 쓸 수 있다. 디렉터리도 가능(탐색용)")
    ap.add_argument("--engine", choices=["auto", "agy", "opencode"], default="auto", help="생략(auto) 시 작업 성격으로 고른다")
    ap.add_argument("--no-fallback", action="store_true", help="실패해도 다른 엔진으로 넘어가지 않는다")
    ap.add_argument("--cwd", default=None, help="서브 에이전트의 작업 폴더(기본: 현재 폴더)")
    ap.add_argument("--timeout", type=int, default=int(os.environ.get("SUB_AGENT_TIMEOUT", "300")), help="엔진당 제한 시간(초, 기본 300)")
    ap.add_argument("--max-lines", type=int, default=40, help="답변 줄 수 상한 안내(기본 40)")
    ap.add_argument("--max-chars", type=int, default=6000, help="출력 글자 수 상한(기본 6000). 넘으면 자른다")
    ap.add_argument("--max-file-bytes", type=int, default=400000, help="파일 하나당 주입 상한(기본 400000)")
    ap.add_argument("--big-bytes", type=int, default=200000, help="이보다 크면 agy 를 먼저 쓴다(기본 200000)")
    ap.add_argument("--lang", default="한국어")
    ap.add_argument("--agy-model", default=None)
    ap.add_argument("--opencode-model", default=None)
    ap.add_argument("--env-file", default=None)
    ap.add_argument("--keep-bundle", action="store_true", help="디버깅용: 임시 입력 파일을 지우지 않는다")
    ap.add_argument("--check", action="store_true", help="설치·인증 상태 점검")
    args = ap.parse_args(argv)

    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8")
        except Exception:
            pass
    load_env_files(args.env_file)
    if args.check:
        return do_check()
    if not args.query:
        ap.error("-q/--query 가 필요합니다")
    if args.cwd and not os.path.isdir(args.cwd):
        ap.error("--cwd 폴더가 없습니다: %s" % args.cwd)

    try:
        bundle, meta = build_bundle(args.query, args.file, args.max_file_bytes, args.max_lines, args.lang)
    except EngineError as e:
        sys.stderr.write("sub-agent: %s\n" % e)
        return 2

    tmpdir = tempfile.mkdtemp(prefix="sub-agent-")
    bundle_path = os.path.join(tmpdir, "request.md")
    with open(bundle_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(bundle)
    env = os.environ.copy()
    failures = []
    try:
        for name in choose_order(args, meta, args.file):
            try:
                text, used = ENGINES[name](bundle_path, meta, args, env)
            except EngineError as e:
                failures.append("%s: %s" % (name, e))
                continue
            text = clean_output(text, args.max_chars)
            if not text:
                failures.append("%s: 빈 응답" % name)
                continue
            if failures:
                sys.stderr.write("sub-agent: [%s] 폴백 — %s\n" % (used, " | ".join(failures)))
            else:
                sys.stderr.write("sub-agent: [%s]\n" % used)
            sys.stdout.write(text + "\n")
            return 0
        sys.stderr.write("sub-agent: 모든 엔진이 실패했습니다 — %s\n" % " | ".join(failures))
        return 1
    finally:
        if args.keep_bundle:
            sys.stderr.write("sub-agent: 입력 파일 %s\n" % bundle_path)
        else:
            shutil.rmtree(tmpdir, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
