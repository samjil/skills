// app.js
// agy-bridge 웹 뷰어. runtime/logs/data/ 를 서빙하는 serve-report.ps1을 통해
// index.json과 qa-*.jsonl을 fetch()로 직접 읽어와 렌더링합니다.
// (report-data.js 같은 script-tag 껍데기가 필요 없습니다 - HTTP 서버라 CORS 제약이 없습니다.)
(function () {
  "use strict";

  var PAGE_SIZE = 50;
  var AUTO_REFRESH_MS = 5000;

  var els = {
    cards:        document.getElementById("cards"),
    count:        document.getElementById("count"),
    updated:      document.getElementById("updated"),
    search:       document.getElementById("search"),
    modelFilter:  document.getElementById("modelfilter"),
    sessionFilter: document.getElementById("sessionfilter"),
    statusFilter: document.getElementById("statusfilter"),
    autoRefresh:  document.getElementById("autorefresh"),
    refreshBtn:   document.getElementById("refresh"),
    loadMoreBtn:  document.getElementById("loadmore"),

    // 탭 및 핸드오프 엘리먼트
    tabBtnQa:             document.getElementById("tab-btn-qa"),
    tabBtnHandoff:        document.getElementById("tab-btn-handoff"),
    qaControls:           document.getElementById("qa-controls"),
    handoffControls:      document.getElementById("handoff-controls"),
    qaView:               document.getElementById("qa-view"),
    handoffView:          document.getElementById("handoff-view"),
    handoffProjectSelect: document.getElementById("handoff-project-select"),
    handoffSearch:        document.getElementById("handoff-search"),
    handoffDirFilter:     document.getElementById("handoff-dir-filter"),
    handoffStatusFilter:  document.getElementById("handoff-status-filter"),
    handoffBriefCard:     document.getElementById("handoff-brief-card"),
    briefProjectName:     document.getElementById("brief-project-name"),
    handoffBriefContent:  document.getElementById("handoff-brief-content"),
    handoffCards:         document.getElementById("handoff-cards"),
  };

  var currentTab = "qa";
  var handoffProjects = [];
  var currentHandoffProject = "";
  var currentHandoffData = null;
  var handoffMessageCache = {};

  var allItems = [];      // 전체 기록, 최신순 정렬
  var filtered = [];      // 검색/필터 적용된 목록
  var shown = 0;          // 지금까지 화면에 그린 건수
  var knownShardKey = ""; // 데이터가 실제로 바뀌었는지 판단하는 키 (shard 파일명+크기)
  var refreshTimer = null;

  function fetchText(url) {
    return fetch(url, { cache: "no-store" }).then(function (res) {
      if (!res.ok) { throw new Error(url + " -> HTTP " + res.status); }
      return res.text();
    });
  }

  function fetchJson(url) {
    return fetchText(url).then(function (t) {
      if (!t) { return null; }
      if (t.charCodeAt(0) === 0xFEFF) { t = t.slice(1); }
      return JSON.parse(t);
    });
  }

  function parseJsonl(text) {
    if (text && text.charCodeAt(0) === 0xFEFF) { text = text.slice(1); }
    var out = [];
    var lines = text.split(/\r?\n/);
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim();
      if (!line) { continue; }
      try { out.push(JSON.parse(line)); } catch (e) { /* 손상된 줄은 건너뜁니다 */ }
    }
    return out;
  }

  function shardKeyOf(index) {
    if (!index || !index.shards) { return ""; }
    return index.shards.map(function (s) { return s.file + ":" + s.bytes; }).join(",");
  }

  // index.json에 나열된 모든 shard(qa-YYYY-MM[.pN].jsonl)를 읽어와 합칩니다.
  function loadAll(force) {
    if (force) { knownShardKey = ""; }
    return fetchJson("/data/index.json").then(function (index) {
      var key = shardKeyOf(index);
      var changed = (key !== knownShardKey);
      knownShardKey = key;

      if (!changed && !force && allItems.length > 0) {
        return { changed: false, index: index };
      }

      var shards = (index && index.shards) ? index.shards : [];
      var loaders = shards.map(function (s) {
        return fetchText("/data/" + encodeURIComponent(s.file))
          .then(parseJsonl)
          .catch(function () { return []; });
      });

      return Promise.all(loaders).then(function (chunks) {
        var items = [];
        chunks.forEach(function (c) { items = items.concat(c); });
        items.sort(function (a, b) {
          return String((b && b.timestamp) || "").localeCompare(String((a && a.timestamp) || ""));
        });
        allItems = items;
        return { changed: true, index: index };
      });
    });
  }

  function uniqueModels() {
    var set = {};
    allItems.forEach(function (r) { if (r.model) { set[r.model] = true; } });
    return Object.keys(set).sort();
  }

  function populateModelFilter() {
    var current = els.modelFilter.value;
    var models = uniqueModels();
    els.modelFilter.innerHTML = '<option value="">모든 모델</option>';
    models.forEach(function (m) {
      var o = document.createElement("option");
      o.value = m; o.textContent = m;
      els.modelFilter.appendChild(o);
    });
    if (models.indexOf(current) !== -1) { els.modelFilter.value = current; }
  }

  function uniqueSessions() {
    var set = {};
    allItems.forEach(function (r) { if (r.session) { set[r.session] = true; } });
    return Object.keys(set).sort();
  }

  function populateSessionFilter() {
    if (!els.sessionFilter) { return; }
    var current = els.sessionFilter.value;
    var sessions = uniqueSessions();
    els.sessionFilter.innerHTML = '<option value="">모든 세션</option><option value="__none__">(단발성 작업 - 세션 없음)</option>';
    sessions.forEach(function (s) {
      var o = document.createElement("option");
      o.value = s;
      o.textContent = "🧵 " + s;
      els.sessionFilter.appendChild(o);
    });
    if (current && (sessions.indexOf(current) !== -1 || current === "__none__")) {
      els.sessionFilter.value = current;
    }
  }

  function applyFilters() {
    var q = els.search.value.trim().toLowerCase();
    var model = els.modelFilter.value;
    var session = els.sessionFilter ? els.sessionFilter.value : "";
    var status = els.statusFilter.value;

    filtered = allItems.filter(function (r) {
      if (model && r.model !== model) { return false; }
      if (session === "__none__" && r.session) { return false; }
      if (session && session !== "__none__" && r.session !== session) { return false; }
      if (status) {
        var st = (r.status == null ? "" : String(r.status)).trim();
        if (status === "OK" && st !== "OK") { return false; }
        if (status === "ERROR" && st === "OK") { return false; }
      }
      if (q) {
        var hay = [r.model, r.computer_name, r.task_id, r.source, r.session, r.session_id, r.question, r.answer]
          .map(function (v) { return v == null ? "" : String(v); })
          .join(" ").toLowerCase();
        if (hay.indexOf(q) === -1) { return false; }
      }
      return true;
    });

    shown = 0;
    els.cards.innerHTML = "";
    renderMore();
  }

  // ==========================================================================
  // Image Thumbnail, Hover Zoom & Lightbox
  // ==========================================================================

  function initImagePopups() {
    if (!document.getElementById("image-hover-popup")) {
      var hp = document.createElement("div");
      hp.id = "image-hover-popup";
      hp.innerHTML = '<img src="" alt="미리보기"><div class="popup-caption"></div>';
      document.body.appendChild(hp);
    }

    if (!document.getElementById("image-lightbox")) {
      var lb = document.createElement("div");
      lb.id = "image-lightbox";
      lb.innerHTML = [
        '<div class="lightbox-header">',
        '  <span class="lightbox-title"></span>',
        '  <div class="lightbox-actions">',
        '    <a class="lightbox-btn lightbox-open-newtab" href="#" target="_blank" title="새 탭에서 원본 열기">새 탭 ↗</a>',
        '    <button class="lightbox-btn lightbox-close" type="button" title="닫기 (Esc)">✕ 닫기</button>',
        '  </div>',
        '</div>',
        '<div class="lightbox-img-wrap">',
        '  <img class="lightbox-img" src="" alt="확대 이미지">',
        '</div>'
      ].join("");

      lb.addEventListener("click", function (e) {
        if (e.target === lb || e.target.classList.contains("lightbox-img-wrap") || e.target.classList.contains("lightbox-close")) {
          closeLightbox();
        }
      });

      document.addEventListener("keydown", function (e) {
        if (e.key === "Escape") { closeLightbox(); }
      });

      document.body.appendChild(lb);
    }
  }

  function makeImageUrl(imgPath, cwd) {
    var url = "/image?path=" + encodeURIComponent(imgPath);
    if (cwd) {
      url += "&cwd=" + encodeURIComponent(cwd);
    }
    return url;
  }

  function showHoverPopup(e, imgUrl, label) {
    var popup = document.getElementById("image-hover-popup");
    if (!popup) { return; }
    var img = popup.querySelector("img");
    var cap = popup.querySelector(".popup-caption");
    if (img) { img.src = imgUrl; }
    if (cap) { cap.textContent = label || ""; }
    popup.style.display = "flex";

    var rect = e.currentTarget.getBoundingClientRect();
    var popupWidth = 460;
    var popupHeight = 360;

    var left = rect.right + 14;
    var top = rect.top - 10;

    if (left + popupWidth > window.innerWidth - 12) {
      left = rect.left - popupWidth - 14;
    }
    if (left < 12) {
      left = 12;
    }

    if (top + popupHeight > window.innerHeight - 12) {
      top = window.innerHeight - popupHeight - 12;
    }
    if (top < 12) {
      top = 12;
    }

    popup.style.left = Math.round(left) + "px";
    popup.style.top = Math.round(top) + "px";
  }

  function hideHoverPopup() {
    var popup = document.getElementById("image-hover-popup");
    if (popup) {
      popup.style.display = "none";
      var img = popup.querySelector("img");
      if (img) { img.src = ""; }
    }
  }

  function openLightbox(imgUrl, label) {
    var lb = document.getElementById("image-lightbox");
    if (!lb) { return; }
    var img = lb.querySelector(".lightbox-img");
    var title = lb.querySelector(".lightbox-title");
    var openBtn = lb.querySelector(".lightbox-open-newtab");
    if (img) { img.src = imgUrl; }
    if (title) { title.textContent = label || "이미지 원본 보기"; }
    if (openBtn) { openBtn.href = imgUrl; }
    lb.style.display = "flex";
    document.body.style.overflow = "hidden";
  }

  function closeLightbox() {
    var lb = document.getElementById("image-lightbox");
    if (!lb) { return; }
    lb.style.display = "none";
    var img = lb.querySelector(".lightbox-img");
    if (img) { img.src = ""; }
    document.body.style.overflow = "";
  }

  function extractImagesFromText(text) {
    if (!text) { return { cwd: "", images: [] }; }
    var cwdMatch = text.match(/@cwd:\s*([^\r\n]+)/i);
    var cwd = cwdMatch ? cwdMatch[1].trim() : "";

    var candidates = [];
    var seen = {};

    function add(path) {
      if (!path) { return; }
      path = path.trim().replace(/^[`"']+|[`"']+$/g, "").trim();
      if (!path) { return; }
      if (/\.(png|jpe?g|gif|webp|svg|bmp|ico)$/i.test(path)) {
        if (!seen[path]) {
          seen[path] = true;
          candidates.push(path);
        }
      }
    }

    // 1. Backtick code spans: `path/to/img.png`
    var btRegex = /`([^`\r\n]+\.(?:png|jpe?g|gif|webp|svg|bmp|ico))`\s*/gi;
    var m;
    while ((m = btRegex.exec(text)) !== null) { add(m[1]); }

    // 2. Markdown images/links: ![...](...) or [...](...)
    var mdRegex = /!?\[[^\]]*\]\(([^)\r\n]+\.(?:png|jpe?g|gif|webp|svg|bmp|ico))\)/gi;
    while ((m = mdRegex.exec(text)) !== null) { add(m[1]); }

    // 3. Absolute Windows paths: C:\...
    var absRegex = /\b([a-zA-Z]:\\[^\s<>"'`*?|]+\.(?:png|jpe?g|gif|webp|svg|bmp|ico))\b/gi;
    while ((m = absRegex.exec(text)) !== null) { add(m[1]); }

    // 4. Relative paths or filenames with Korean/alphanumeric characters: e.g. 시안/popup-guide-box.png
    var relRegex = /(?:^|[\s"'(<])((?:[a-zA-Z0-9_\-\.\uac00-\ud7a3]+\/|[a-zA-Z0-9_\-\.\uac00-\ud7a3]+\\)*[a-zA-Z0-9_\-\.\uac00-\ud7a3]+\.(?:png|jpe?g|gif|webp|svg|bmp|ico))(?=[\s"')>]|$)/gi;
    while ((m = relRegex.exec(text)) !== null) { add(m[1]); }

    return { cwd: cwd, images: candidates };
  }

  function createImageGallery(images, cwd) {
    if (!images || images.length === 0) { return null; }

    var gallery = document.createElement("div");
    gallery.className = "qa-image-gallery";
    gallery.innerHTML = '<div class="qa-image-gallery-title">🖼️ 참조 이미지 (' + images.length + '개) <span style="font-weight:normal;opacity:.7;font-size:11px;">(마우스 오버: 확대 / 클릭: 크게 보기)</span></div>';

    var grid = document.createElement("div");
    grid.className = "qa-image-gallery-grid";

    var validCount = images.length;

    images.forEach(function (imgPath) {
      var fullUrl = makeImageUrl(imgPath, cwd);
      var card = document.createElement("div");
      card.className = "image-thumb-card";
      card.title = imgPath + "\n(마우스 오버: 확대 미리보기 / 클릭: 크게 보기)";

      var img = document.createElement("img");
      img.className = "image-thumb-img";
      img.src = fullUrl;
      img.alt = imgPath;
      img.loading = "lazy";

      var label = document.createElement("div");
      label.className = "image-thumb-label";
      label.textContent = imgPath.replace(/^.*[\\\/]/, '');

      card.appendChild(img);
      card.appendChild(label);

      // 이미지가 로컬에 없거나 404면 카드 자동 숨김
      img.onerror = function () {
        card.remove();
        validCount--;
        if (validCount <= 0) {
          gallery.remove();
        } else {
          var titleEl = gallery.querySelector(".qa-image-gallery-title");
          if (titleEl) {
            titleEl.innerHTML = '🖼️ 참조 이미지 (' + validCount + '개) <span style="font-weight:normal;opacity:.7;font-size:11px;">(마우스 오버: 확대 / 클릭: 크게 보기)</span>';
          }
        }
      };

      card.addEventListener("mouseenter", function (e) {
        showHoverPopup(e, fullUrl, imgPath);
      });
      card.addEventListener("mouseleave", hideHoverPopup);
      card.addEventListener("click", function (e) {
        e.preventDefault();
        openLightbox(fullUrl, imgPath);
      });

      grid.appendChild(card);
    });

    gallery.appendChild(grid);
    return gallery;
  }

  // 질문/답변 내용은 사용자 파일이나 agy(LLM) 응답에서 그대로 온 것이라 신뢰할 수 없는
  // 입력으로 취급합니다. marked.js는 마크다운 안의 원문 HTML/<script>를 소독하지 않고
  // 그대로 통과시키므로, DOMPurify로 한 번 걸러내지 않고는 innerHTML에 넣지 않습니다.
  // DOMPurify를 못 불러온 경우(오프라인 등)는 안전하지 않은 HTML을 그냥 보여주는 대신,
  // marked를 못 불러왔을 때와 마찬가지로 원문 텍스트로 안전하게 대체합니다(fail-closed).
  function renderBody(container, text, cwd) {
    var canRenderMarkdown = window.marked && typeof window.marked.parse === "function" &&
      window.DOMPurify && typeof window.DOMPurify.sanitize === "function";
    if (canRenderMarkdown) {
      container.classList.add("md");
      container.innerHTML = window.DOMPurify.sanitize(window.marked.parse(text || ""));
    } else {
      var pre = document.createElement("pre");
      pre.textContent = text || "";
      container.appendChild(pre);
    }

    // 본문 안의 인라인 코드(`...`)가 이미지 파일명인 경우 호버 확대 및 클릭 보기 연결
    try {
      var codeEls = container.querySelectorAll("code");
      codeEls.forEach(function (code) {
        var str = (code.textContent || "").trim();
        if (/\.(png|jpe?g|gif|webp|svg|bmp|ico)$/i.test(str)) {
          var imgUrl = makeImageUrl(str, cwd);
          code.classList.add("inline-image-ref");
          code.title = str + " (클릭: 원본 보기 / 마우스 오버: 확대)";
          if (!code.querySelector(".img-icon")) {
            var icon = document.createElement("span");
            icon.className = "img-icon";
            icon.textContent = "🖼️ ";
            code.insertBefore(icon, code.firstChild);
          }
          code.addEventListener("mouseenter", function (e) {
            showHoverPopup(e, imgUrl, str);
          });
          code.addEventListener("mouseleave", hideHoverPopup);
          code.addEventListener("click", function (e) {
            e.preventDefault();
            e.stopPropagation();
            openLightbox(imgUrl, str);
          });
        }
      });
    } catch (err) {}
  }

  function badge(cls, text) {
    var s = document.createElement("span");
    s.className = "badge " + cls;
    s.textContent = text;
    return s;
  }

  function buildCard(r) {
    var st = (r.status == null ? "" : String(r.status)).trim();
    var isOk = (st === "OK");
    var isErr = (st !== "" && !isOk);

    var card = document.createElement("div");
    card.className = "card" + (isErr ? " err" : "");

    var meta = document.createElement("div");
    meta.className = "meta";
    var ts = document.createElement("span");
    ts.className = "ts";
    ts.textContent = r.timestamp || "";
    meta.appendChild(ts);

    if (st) {
      meta.appendChild(badge("status-" + (isOk ? "ok" : "err"), st));
    } else {
      meta.appendChild(badge("status-unknown", "상태 미기록"));
    }
    // source: "bridge"(inbox 파일 위임 -> watch-agy.ps1이 agy CLI 호출) 또는
    // "mcp"(Claude가 antigravity MCP를 직접 호출). source 필드가 생기기 전의 옛 기록은
    // 기본값으로 "bridge"를 보여줍니다 - 실제로 전부 그 경로였기 때문입니다.
    var src = r.source || "bridge";
    meta.appendChild(badge("source-" + src, src === "mcp" ? "🔗 MCP" : "📁 bridge"));
    // model: 실제 모델명을 표시합니다. "(session)"은 옛 워처 버전이 세션 이어가기 호출에서
    // 실제 모델을 못 채워넣고 남긴 자리표시자입니다(지금은 세션 레지스트리의 모델명을
    // 읽어와 정상 기록하도록 고쳤습니다). 특정 모델 이름으로 지어내지 않고 배지 자체를
    // 생략합니다 - 틀린 값을 확신 있게 보여주는 게, 모른다고 하는 것보다 더 나쁩니다.
    var modelName = (r.model && r.model !== "(session)") ? r.model : null;
    var isSession = Boolean(r.session || r.session_id || r.model === "(session)");
    if (modelName) { meta.appendChild(badge("model", String(modelName))); }

    if (r.attempts && Number(r.attempts) > 1) { meta.appendChild(badge("attempts", "시도 " + r.attempts + "회")); }
    if (r.total_tokens) { meta.appendChild(badge("tok", "토큰 " + r.total_tokens)); }
    if (r.input_tokens) { meta.appendChild(badge("tok-in", "입력 " + r.input_tokens)); }
    if (r.output_tokens) { meta.appendChild(badge("tok-out", "출력 " + r.output_tokens)); }
    if (r.thinking_tokens) { meta.appendChild(badge("think", "사고 " + r.thinking_tokens)); }
    if (r.elapsed_sec) { meta.appendChild(badge("time", r.elapsed_sec + "초")); }
    if (r.task_id) { meta.appendChild(badge("taskid", r.task_id)); }
    card.appendChild(meta);

    // 2번째 라인: 세션 정보 (세션으로 수행된 작업인 경우에만 2번째 라인에 별도 표시)
    if (isSession) {
      var sMeta = document.createElement("div");
      sMeta.className = "meta session-meta";

      sMeta.appendChild(badge("session-flag", "(session)"));
      if (r.session) {
        sMeta.appendChild(badge("session", "🧵 " + r.session));
      }
      if (r.session_id) {
        var sid = String(r.session_id);
        var shortSid = sid.length > 8 ? sid.substring(0, 8) : sid;
        var sidBadge = badge("session-id", "id:" + shortSid);
        sidBadge.title = "세션 ID: " + sid + " (클릭하면 복사)";
        sidBadge.style.cursor = "pointer";
        (function (fullId, el, label) {
          el.onclick = function () {
            if (navigator.clipboard) {
              navigator.clipboard.writeText(fullId).then(function () {
                el.textContent = "복사됨!";
                setTimeout(function () { el.textContent = label; }, 1200);
              });
            }
          };
        })(sid, sidBadge, "id:" + shortSid);
        sMeta.appendChild(sidBadge);
      }
      card.appendChild(sMeta);
    }

    var dq = document.createElement("details");
    dq.className = "qa q";
    dq.innerHTML = "<summary>질문</summary>";
    var qb = document.createElement("div");
    qb.className = "body";

    var qImgInfo = extractImagesFromText(r.question);
    var qGallery = createImageGallery(qImgInfo.images, qImgInfo.cwd);
    if (qGallery) {
      qb.appendChild(qGallery);
    }
    var qContent = document.createElement("div");
    qContent.className = "qa-content";
    renderBody(qContent, r.question, qImgInfo.cwd);
    qb.appendChild(qContent);

    dq.appendChild(qb);
    card.appendChild(dq);

    var da = document.createElement("details");
    da.className = "qa a";
    da.open = true;
    da.innerHTML = "<summary>답변</summary>";
    var ab = document.createElement("div");
    ab.className = "body";

    var aImgInfo = extractImagesFromText(r.answer);
    var aGallery = createImageGallery(aImgInfo.images, qImgInfo.cwd || aImgInfo.cwd);
    if (aGallery) {
      ab.appendChild(aGallery);
    }
    var aContent = document.createElement("div");
    aContent.className = "qa-content";
    renderBody(aContent, r.answer, qImgInfo.cwd || aImgInfo.cwd);
    ab.appendChild(aContent);

    da.appendChild(ab);
    card.appendChild(da);

    return card;
  }

  function renderMore() {
    if (filtered.length === 0) {
      els.cards.innerHTML = '<p class="empty">' +
        (allItems.length === 0
          ? "아직 처리된 작업이 없습니다. runtime\\inbox 폴더에 지시파일을 넣으면 여기에 나타납니다."
          : "검색/필터 조건에 맞는 기록이 없습니다.") +
        "</p>";
      els.loadMoreBtn.hidden = true;
      updateCount();
      return;
    }

    var next = filtered.slice(shown, shown + PAGE_SIZE);
    var frag = document.createDocumentFragment();
    next.forEach(function (r) { frag.appendChild(buildCard(r)); });
    els.cards.appendChild(frag);
    shown += next.length;

    els.loadMoreBtn.hidden = (shown >= filtered.length);
    updateCount();
  }

  function updateCount() {
    if (currentTab === "qa") {
      var text = "총 " + allItems.length + "건";
      if (filtered.length !== allItems.length) {
        text += " · 필터 결과 " + filtered.length + "건";
      }
      text += " · " + shown + "건 표시 중";
      els.count.textContent = text;
      els.updated.textContent = "갱신: " + new Date().toLocaleTimeString();
    } else if (currentTab === "handoff") {
      if (!currentHandoffData || !currentHandoffData.messages) {
        els.count.textContent = "프로젝트 미선택";
      } else {
        var total = currentHandoffData.messages.length;
        var visible = els.handoffCards.querySelectorAll(".handoff-card").length;
        var t = "메시지 총 " + total + "건";
        if (visible !== total) {
          t += " · 필터 결과 " + visible + "건";
        }
        els.count.textContent = t;
      }
      els.updated.textContent = "갱신: " + new Date().toLocaleTimeString();
    }
  }

  function switchTab(tabName) {
    if (currentTab === tabName) { return; }
    currentTab = tabName;

    if (tabName === "qa") {
      els.tabBtnQa.classList.add("active");
      els.tabBtnQa.setAttribute("aria-selected", "true");
      els.tabBtnHandoff.classList.remove("active");
      els.tabBtnHandoff.setAttribute("aria-selected", "false");

      els.qaControls.style.display = "";
      els.handoffControls.style.display = "none";
      els.qaView.style.display = "";
      els.handoffView.style.display = "none";
      updateCount();
    } else {
      els.tabBtnHandoff.classList.add("active");
      els.tabBtnHandoff.setAttribute("aria-selected", "true");
      els.tabBtnQa.classList.remove("active");
      els.tabBtnQa.setAttribute("aria-selected", "false");

      els.qaControls.style.display = "none";
      els.handoffControls.style.display = "flex";
      els.qaView.style.display = "none";
      els.handoffView.style.display = "block";

      if (handoffProjects.length === 0) {
        loadHandoffProjects(true);
      } else {
        updateCount();
      }
    }
  }

  function loadHandoffProjects(force) {
    return fetchJson("/api/handoff/projects").then(function (projects) {
      if (projects && !Array.isArray(projects)) {
        projects = [projects];
      }
      if (!Array.isArray(projects)) { projects = []; }
      handoffProjects = projects;

      var prevSelected = els.handoffProjectSelect.value || currentHandoffProject;
      els.handoffProjectSelect.innerHTML = "";

      if (projects.length === 0) {
        var opt = document.createElement("option");
        opt.value = "";
        opt.textContent = "프로젝트가 없습니다 (runtime/handoff)";
        els.handoffProjectSelect.appendChild(opt);
        els.handoffBriefCard.style.display = "none";
        els.handoffCards.innerHTML = "<p class=\"empty\">기록된 핸드오프 프로젝트가 없습니다.<br><code>runtime/handoff/&lt;프로젝트&gt;/</code> 폴더에 채널이 개설되면 여기에 표시됩니다.</p>";
        updateCount();
        return;
      }

      var matched = false;
      projects.forEach(function (p) {
        var opt = document.createElement("option");
        opt.value = p.name;
        opt.textContent = p.name + " (" + p.msgCount + "건)";
        if (p.name === prevSelected) {
          opt.selected = true;
          matched = true;
        }
        els.handoffProjectSelect.appendChild(opt);
      });

      var targetProject = matched ? prevSelected : projects[0].name;
      els.handoffProjectSelect.value = targetProject;
      currentHandoffProject = targetProject;
      return loadHandoffProject(targetProject);
    }).catch(function (err) {
      els.handoffCards.innerHTML = "<p class=\"empty\">프로젝트 목록 로드 실패: " + escapeHtml(err.message) + "</p>";
    });
  }

  function loadHandoffProject(projectName) {
    if (!projectName) { return Promise.resolve(); }
    currentHandoffProject = projectName;

    return fetchJson("/api/handoff/project?name=" + encodeURIComponent(projectName)).then(function (data) {
      if (data && data.messages && !Array.isArray(data.messages)) {
        data.messages = [data.messages];
      }
      if (data && data.files && !Array.isArray(data.files)) {
        data.files = [data.files];
      }
      currentHandoffData = data;
      // BRIEF 렌더링
      if (data && data.brief) {
        els.briefProjectName.textContent = projectName;
        try {
          var cleanHtml = DOMPurify.sanitize(marked.parse(data.brief));
          els.handoffBriefContent.innerHTML = cleanHtml;
        } catch (e) {
          els.handoffBriefContent.innerHTML = "<pre>" + escapeHtml(data.brief) + "</pre>";
        }
        els.handoffBriefCard.style.display = "block";
      } else {
        els.handoffBriefCard.style.display = "none";
      }

      renderHandoffMessages();
    }).catch(function (err) {
      els.handoffCards.innerHTML = "<p class=\"empty\">프로젝트 데이터 로드 실패: " + escapeHtml(err.message) + "</p>";
    });
  }

  function findHandoffFileForNum(num) {
    if (!currentHandoffData || !Array.isArray(currentHandoffData.files)) { return null; }
    var prefix = num + "-";
    for (var i = 0; i < currentHandoffData.files.length; i++) {
      if (currentHandoffData.files[i].indexOf(prefix) === 0) {
        return currentHandoffData.files[i];
      }
    }
    return null;
  }

  function toggleHandoffMessage(cardEl, num) {
    var bodyEl = cardEl.querySelector(".handoff-card-body");
    if (!bodyEl) { return; }

    var isOpen = (bodyEl.style.display !== "none");
    if (isOpen) {
      bodyEl.style.display = "none";
      return;
    }

    bodyEl.style.display = "block";
    if (bodyEl.dataset.loaded === "true") {
      return;
    }

    var fileName = findHandoffFileForNum(num);
    if (!fileName) {
      bodyEl.innerHTML = "<p class=\"empty\">해당 번호의 메시지 파일(msg/" + escapeHtml(num) + "-*.md)을 찾을 수 없습니다.</p>";
      bodyEl.dataset.loaded = "true";
      return;
    }

    var cacheKey = currentHandoffProject + "/" + fileName;
    if (handoffMessageCache[cacheKey]) {
      renderMarkdownBody(bodyEl, handoffMessageCache[cacheKey]);
      bodyEl.dataset.loaded = "true";
      return;
    }

    bodyEl.innerHTML = "<div class=\"handoff-card-body-loading\">메시지 본문을 불러오는 중...</div>";
    fetchText("/api/handoff/message?project=" + encodeURIComponent(currentHandoffProject) + "&file=" + encodeURIComponent(fileName))
      .then(function (markdown) {
        handoffMessageCache[cacheKey] = markdown;
        renderMarkdownBody(bodyEl, markdown);
        bodyEl.dataset.loaded = "true";
      })
      .catch(function (err) {
        bodyEl.innerHTML = "<p class=\"empty\">본문 로드 실패: " + escapeHtml(err.message) + "</p>";
      });
  }

  function renderMarkdownBody(targetEl, markdown) {
    try {
      var cleanHtml = DOMPurify.sanitize(marked.parse(markdown));
      targetEl.innerHTML = cleanHtml;
    } catch (e) {
      targetEl.innerHTML = "<pre>" + escapeHtml(markdown) + "</pre>";
    }
  }

  function renderHandoffMessages() {
    if (!currentHandoffData || !Array.isArray(currentHandoffData.messages)) {
      els.handoffCards.innerHTML = "<p class=\"empty\">표시할 메시지가 없습니다.</p>";
      updateCount();
      return;
    }

    var msgs = currentHandoffData.messages;
    var q = (els.handoffSearch.value || "").trim().toLowerCase();
    var dirFilter = els.handoffDirFilter.value;
    var statusFilter = els.handoffStatusFilter.value;

    var filteredMsgs = msgs.filter(function (m) {
      if (dirFilter && m.dir !== dirFilter) { return false; }
      if (statusFilter && m.status !== statusFilter) { return false; }
      if (q) {
        var match = (m.num && m.num.toLowerCase().indexOf(q) >= 0) ||
                    (m.title && m.title.toLowerCase().indexOf(q) >= 0) ||
                    (m.time && m.time.indexOf(q) >= 0) ||
                    (m.status && m.status.indexOf(q) >= 0);
        if (!match) { return false; }
      }
      return true;
    });

    // 최신 메시지가 위로 오도록 역순(내림차순) 복사
    var sortedMsgs = filteredMsgs.slice().reverse();

    if (sortedMsgs.length === 0) {
      els.handoffCards.innerHTML = "<p class=\"empty\">조건에 일치하는 핸드오프 메시지가 없습니다.</p>";
      updateCount();
      return;
    }

    var frag = document.createDocumentFragment();
    sortedMsgs.forEach(function (m) {
      var card = document.createElement("div");
      card.className = "handoff-card";

      var header = document.createElement("div");
      header.className = "handoff-card-header";

      var left = document.createElement("div");
      left.className = "handoff-card-header-left";

      var numSpan = document.createElement("span");
      numSpan.className = "handoff-num";
      numSpan.textContent = "#" + m.num;

      var dirBadge = document.createElement("span");
      dirBadge.className = "badge dir-" + (m.dir || "unknown");
      dirBadge.textContent = m.dir === "c2a" ? "Claude → agy" : (m.dir === "a2c" ? "agy → Claude" : m.dir);

      var titleSpan = document.createElement("span");
      titleSpan.className = "handoff-title";
      titleSpan.textContent = m.title;

      left.appendChild(numSpan);
      left.appendChild(dirBadge);
      left.appendChild(titleSpan);

      var right = document.createElement("div");
      right.className = "handoff-card-header-right";

      var timeSpan = document.createElement("span");
      timeSpan.className = "handoff-time";
      timeSpan.textContent = m.time;

      var statusBadge = document.createElement("span");
      statusBadge.className = "badge status-" + (m.status || "unknown");
      statusBadge.textContent = m.status;

      right.appendChild(timeSpan);
      right.appendChild(statusBadge);

      header.appendChild(left);
      header.appendChild(right);

      var body = document.createElement("div");
      body.className = "handoff-card-body markdown-body";
      body.style.display = "none";

      header.addEventListener("click", function () {
        toggleHandoffMessage(card, m.num);
      });

      card.appendChild(header);
      card.appendChild(body);
      frag.appendChild(card);
    });

    els.handoffCards.innerHTML = "";
    els.handoffCards.appendChild(frag);
    updateCount();
  }

  function refresh(force) {
    if (currentTab === "handoff") {
      return loadHandoffProjects(force);
    }
    return loadAll(force).then(function (r) {
      if (force || r.changed) {
        populateModelFilter();
        populateSessionFilter();
        applyFilters();
      }
    }).catch(function (err) {
      els.count.textContent = "불러오기 실패: " + err.message;
    });
  }

  function scheduleAutoRefresh() {
    if (refreshTimer) { clearInterval(refreshTimer); refreshTimer = null; }
    if (els.autoRefresh.checked) {
      refreshTimer = setInterval(function () { refresh(false); }, AUTO_REFRESH_MS);
    }
  }

  // 탭 전환 이벤트
  if (els.tabBtnQa) { els.tabBtnQa.addEventListener("click", function () { switchTab("qa"); }); }
  if (els.tabBtnHandoff) { els.tabBtnHandoff.addEventListener("click", function () { switchTab("handoff"); }); }

  // QA 이벤트
  els.search.addEventListener("input", applyFilters);
  els.modelFilter.addEventListener("change", applyFilters);
  if (els.sessionFilter) { els.sessionFilter.addEventListener("change", applyFilters); }
  els.statusFilter.addEventListener("change", applyFilters);
  els.loadMoreBtn.addEventListener("click", renderMore);
  els.refreshBtn.addEventListener("click", function () { refresh(true); });
  els.autoRefresh.addEventListener("change", scheduleAutoRefresh);

  // Handoff 이벤트
  if (els.handoffProjectSelect) {
    els.handoffProjectSelect.addEventListener("change", function () {
      loadHandoffProject(this.value);
    });
  }
  if (els.handoffSearch) { els.handoffSearch.addEventListener("input", renderHandoffMessages); }
  if (els.handoffDirFilter) { els.handoffDirFilter.addEventListener("change", renderHandoffMessages); }
  if (els.handoffStatusFilter) { els.handoffStatusFilter.addEventListener("change", renderHandoffMessages); }

  initImagePopups();
  refresh(true).then(scheduleAutoRefresh);
})();
