# -*- coding: utf-8 -*-
# sub-agent.py 시험. 가짜 agy/opencode 실행 파일을 PATH 앞에 두고 실제 프로세스로 돌린다.
#   python3 tests/sub-agent/sub-agent.tests.py
import json, os, stat, subprocess, sys, tempfile, textwrap

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRIPT = os.path.join(ROOT, "runtime", "sub-agent", "sub-agent.py")
passed = failed = 0


def ok(name, cond, detail=""):
    global passed, failed
    if cond:
        passed += 1
        print("  PASS  " + name)
    else:
        failed += 1
        print("  FAIL  %s %s" % (name, detail))


work = tempfile.mkdtemp(prefix="subagent-test-")
bindir = os.path.join(work, "bin")
os.makedirs(bindir)
state = os.path.join(work, "state")
os.makedirs(state)


def fake(name, body):
    p = os.path.join(bindir, name)
    with open(p, "w", encoding="utf-8") as f:
        f.write("#!%s\n" % sys.executable + textwrap.dedent(body))
    os.chmod(p, os.stat(p).st_mode | stat.S_IEXEC)


# agy: MODE 파일 내용대로 동작. 받은 인자와 요청 파일 내용을 state 에 남긴다.
fake("agy", """
import sys, os, json, re
st = %r
args = sys.argv[1:]
open(os.path.join(st, "agy.args"), "a", encoding="utf-8").write(json.dumps(args, ensure_ascii=False) + "\\n")
prompt = args[args.index("-p") + 1]
path = re.search(r"file (\\S+) and", prompt).group(1)
open(os.path.join(st, "agy.bundle"), "w", encoding="utf-8").write(open(path, encoding="utf-8").read())
mode = open(os.path.join(st, "agy.mode")).read().strip()
model = args[args.index("--model") + 1] if "--model" in args else ""
if mode == "ok":
    print(json.dumps({"status": "OK", "response": "안녕하세요!\\n결론: agy 가 답함 (%%s)" %% model}, ensure_ascii=False))
elif mode == "ratelimit":
    print(json.dumps({"status": "ERROR", "error": "429 Too Many Requests quota exceeded"}))
elif mode == "ratelimit-first":
    if model.startswith("gemini-3.8"):
        print(json.dumps({"status": "ERROR", "error": "RESOURCE_EXHAUSTED quota"}))
    else:
        print(json.dumps({"status": "OK", "response": "결론: 두 번째 모델 (%%s)" %% model}))
elif mode == "hang":
    import time; time.sleep(30)
elif mode == "fatal":
    print(json.dumps({"status": "ERROR", "error": "invalid prompt"}))
""" % state)

fake("opencode", """
import sys, os, json
st = %r
args = sys.argv[1:]
open(os.path.join(st, "oc.args"), "a", encoding="utf-8").write(json.dumps(args, ensure_ascii=False) + "\\n")
if args[:2] == ["auth", "list"]:
    print("openrouter  api"); sys.exit(0)
f = args[args.index("--file") + 1]
open(os.path.join(st, "oc.bundle"), "w", encoding="utf-8").write(open(f, encoding="utf-8").read())
mode = open(os.path.join(st, "oc.mode")).read().strip()
if mode == "ok":
    print("\\x1b[32m결론: opencode 가 답함\\x1b[0m")
elif mode == "fail":
    sys.stderr.write("auth error"); sys.exit(3)
""" % state)


def setmode(agy=None, oc=None):
    if agy is not None:
        open(os.path.join(state, "agy.mode"), "w").write(agy)
    if oc is not None:
        open(os.path.join(state, "oc.mode"), "w").write(oc)
    for n in ("agy.args", "oc.args"):
        try:
            os.remove(os.path.join(state, n))
        except OSError:
            pass


def run(*argv, env_extra=None, path_bins=True):
    env = os.environ.copy()
    env["PATH"] = (bindir + os.pathsep + env["PATH"]) if path_bins else os.path.dirname(sys.executable)
    env["HOME"] = work
    env["USERPROFILE"] = work
    env.pop("SUB_AGENT_AGY_MODELS", None)
    if env_extra:
        env.update(env_extra)
    p = subprocess.run([sys.executable, SCRIPT] + list(argv), capture_output=True, env=env, cwd=work)
    return p.returncode, p.stdout.decode("utf-8"), p.stderr.decode("utf-8")


def rd(n):
    return open(os.path.join(state, n), encoding="utf-8").read()


# 시험용 파일
src = os.path.join(work, "OrderService.java")
open(src, "w", encoding="utf-8").write("\n".join("line %d 내용" % i for i in range(1, 301)) + "\n")
log = os.path.join(work, "error.log")
open(log, "w", encoding="utf-8").write("\n".join("log %d" % i for i in range(1, 50001)) + "\n")

print("agy 정상 · 줄 범위 주입 · 출력 압축")
setmode("ok", "ok")
code, out, err = run("--engine", "agy", "-f", src + ":100-102", "-q", "롤백 원인")
ok("종료 코드 0", code == 0, err)
ok("인사말 줄이 걷힌다", out.strip().startswith("결론: agy 가 답함"), out)
ok("stdout 에는 답만(엔진 표시는 stderr)", "[agy/gemini-3.8-flash-high]" in err and "[agy" not in out)
b = rd("agy.bundle")
ok("요청 파일에 100~102 줄만 줄번호와 함께 들어간다", "0100|line 100 내용" in b and "0102|line 102 내용" in b and "0099|" not in b and "0103|" not in b, b[-300:])
ok("요청 파일에 질문과 압축 규칙이 있다", "롤백 원인" in b and "인사말" in b and "개조식" in b)
ok("agy 에 --add-dir(요청 폴더)과 --output-format json 을 준다", "--add-dir" in rd("agy.args") and "--output-format" in rd("agy.args"))
ok("--dangerously-skip-permissions 는 기본으로 주지 않는다", "dangerously" not in rd("agy.args"))
ok("요청 임시 폴더는 끝나면 지운다", not os.path.exists(json.loads(rd("agy.args").splitlines()[0])[json.loads(rd("agy.args").splitlines()[0]).index("--add-dir") + 1]))

print("파일 주입 방식")
setmode("ok", "ok")
code, out, err = run("--engine", "agy", "-f", src + ":280-", "-q", "q")
ok("'경로:280-' 은 끝까지", "0300|line 300" in rd("agy.bundle") and "0279|" not in rd("agy.bundle"))
code, out, err = run("--engine", "agy", "-f", src + ":-3", "-q", "q")
ok("'경로:-3' 은 처음부터 3줄", "0003|line 3" in rd("agy.bundle") and "0004|" not in rd("agy.bundle"))
code, out, err = run("--engine", "agy", "-f", src + ":7", "-q", "q")
ok("'경로:7' 은 한 줄", "0007|line 7" in rd("agy.bundle") and "0008|" not in rd("agy.bundle"))
code, out, err = run("--engine", "agy", "-f", log, "--max-file-bytes", "2000", "-q", "q")
b = rd("agy.bundle")
ok("큰 로그는 끝쪽만 주입하고 알린다", "50000|log 50000" in b and "00001|log 1\n" not in b and "끝" in b)
setmode("ok", "ok")
code, out, err = run("--engine", "agy", "-f", os.path.join(work, "없는파일.txt"), "-q", "q")
ok("없는 파일은 엔진을 부르지 않고 종료 코드 2", code == 2 and "파일이 없습니다" in err and not os.path.exists(os.path.join(state, "agy.args")))
code, out, err = run("--engine", "agy", "-f", src + ":900-950", "-q", "q")
ok("범위가 파일 밖이면 종료 코드 2", code == 2 and "줄 범위" in err)
code, out, err = run("--engine", "agy", "-f", work, "-q", "q")
ok("디렉터리는 --add-dir 로 넘기고 본문은 넣지 않는다", code == 0 and work in rd("agy.args") and "디렉터리" in rd("agy.bundle"))
cp = os.path.join(work, "cp949.txt")
open(cp, "wb").write("한글 로그\n".encode("cp949"))
run("--engine", "agy", "-f", cp, "-q", "q")
ok("cp949 파일도 읽는다", "한글 로그" in rd("agy.bundle"))

print("라우팅")
setmode("ok", "ok")
code, out, err = run("-f", src + ":1-50", "-q", "q")
ok("자동: 코드 파일 소수 -> opencode 먼저", "[opencode/" in err, err)
code, out, err = run("-f", log, "-q", "q")
ok("자동: 큰 로그 -> agy 먼저", "[agy/" in err, err)
code, out, err = run("-q", "파일 없이 탐색")
ok("자동: 파일 없음 -> agy 먼저", "[agy/" in err, err)
code, out, err = run("--engine", "opencode", "-f", log, "-q", "q")
ok("--engine opencode 강제", "[opencode/" in err)
ok("opencode: --model, --file, ASCII 고정 문장을 넘긴다", all(x in rd("oc.args") for x in ["--model", "openrouter/qwen/qwen3-coder:free", "--file", "Follow the instructions"]))
ok("opencode 출력의 ANSI 색 코드가 걷힌다", "\x1b" not in out and out.strip() == "결론: opencode 가 답함", repr(out))

print("폴백")
setmode("ratelimit", "ok")
code, out, err = run("--engine", "agy", "-f", src, "-q", "q")
ok("agy 429 -> opencode 로 자동 전환", code == 0 and "opencode 가 답함" in out and "폴백" in err and "429" in err, err)
setmode("ok", "fail")
code, out, err = run("--engine", "opencode", "-f", src, "-q", "q")
ok("opencode 실패 -> agy 로 전환(대칭)", code == 0 and "agy 가 답함" in out and "폴백" in err, err)
setmode("ratelimit-first", "fail")
code, out, err = run("--engine", "agy", "-f", src, "-q", "q")
ok("agy 첫 모델 쿼터 초과 -> 같은 엔진의 다음 모델", code == 0 and "두 번째 모델 (gemini-3.7-flash-high)" in out and "opencode" not in err.split("]")[0], err)
setmode("hang", "ok")
code, out, err = run("--engine", "agy", "-f", src, "-q", "q", "--timeout", "2")
ok("agy 타임아웃 -> opencode 로 전환", code == 0 and "opencode 가 답함" in out and "타임아웃" in err, err)
setmode("fatal", "ok")
code, out, err = run("--engine", "agy", "-f", src, "-q", "q")
ok("모델을 바꿔도 같을 오류(프롬프트 문제 등)도 다음 엔진으로 넘어간다", code == 0 and "opencode 가 답함" in out, err)
setmode("ratelimit", "fail")
code, out, err = run("--engine", "agy", "-f", src, "-q", "q")
ok("모두 실패하면 종료 코드 1 과 이유 모음", code == 1 and out == "" and "agy:" in err and "opencode:" in err, err)
setmode("ratelimit", "ok")
code, out, err = run("--engine", "agy", "--no-fallback", "-f", src, "-q", "q")
ok("--no-fallback 이면 넘어가지 않는다", code == 1 and not os.path.exists(os.path.join(state, "oc.args")))
code, out, err = run("--engine", "agy", "-f", src, "-q", "q", path_bins=False)
ok("엔진이 하나도 없으면 설치 안내와 종료 코드 1", code == 1 and "설치돼 있지 않습니다" in err)

print("출력 상한")
setmode("ok", "ok")
code, out, err = run("--engine", "opencode", "-f", src, "-q", "q", "--max-chars", "10")
ok("--max-chars 로 자른다", len(out.strip().splitlines()[0]) <= 10 and "잘랐다" in out, out)

print(".env · 점검")
envf = os.path.join(work, "my.env")
open(envf, "w", encoding="utf-8").write("# 주석\nexport SUB_AGENT_OPENCODE_MODEL=openrouter/test/model:free\nOPENROUTER_API_KEY=\"sk-test\"\n")
setmode("ok", "ok")
run("--engine", "opencode", "-f", src, "-q", "q", "--env-file", envf)
ok(".env 의 모델이 opencode 에 전달된다", "openrouter/test/model:free" in rd("oc.args"))
code, out, err = run("--check", "--env-file", envf)
ok("--check: 설치 경로·인증 목록·키 유무를 보여 준다", code == 0 and "agy:" in out and "openrouter  api" in out and "OPENROUTER_API_KEY(환경변수·.env): 있음" in out, out)
code, out, err = run()
ok("질문이 없으면 사용법 오류(종료 코드 2)", code == 2)

print("\n통과 %d / 실패 %d" % (passed, failed))
sys.exit(1 if failed else 0)
