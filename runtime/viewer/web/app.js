// app.js
// samjil 에이전트 통합 대시보드 & 뷰어
// 2단 사이드바 레이아웃: 대시보드(Home), 세션별 위임 실행 기록(QA), 프로젝트별 인수인계(Handoff)
(function () {
  "use strict";

  var PAGE_SIZE = 50;
  var AUTO_REFRESH_MS = 5000;

  // DOM 엘리먼트 참조
  var els = {
    appContainer:         document.getElementById("app-container"),
    appSidebar:           document.getElementById("app-sidebar"),
    sidebarBrand:         document.getElementById("sidebar-brand"),
    sidebarCollapseBtn:   document.getElementById("sidebar-collapse-btn"),
    topbarMenuToggle:     document.getElementById("topbar-menu-toggle"),

    // 1차 네비게이션
    navBtnDashboard:      document.getElementById("nav-btn-dashboard"),
    navBtnQa:             document.getElementById("nav-btn-qa"),
    navBtnHandoff:        document.getElementById("nav-btn-handoff"),

    // 2차 서브 패널
    subDashboard:         document.getElementById("sidebar-sub-dashboard"),
    subQa:                document.getElementById("sidebar-sub-qa"),
    subHandoff:           document.getElementById("sidebar-sub-handoff"),

    // 대시보드 서브 패널: 최근 세션 바로가기
    quickSessionsList:    document.getElementById("quick-sessions-list"),

    // QA 세션 사이드바
    qaSessionCount:       document.getElementById("qa-session-count"),
    qaSessionSearch:      document.getElementById("qa-session-search"),
    qaSessionList:        document.getElementById("qa-session-list"),
    qaTreeSort:           document.getElementById("qa-tree-sort"),
    modelFilter:          document.getElementById("modelfilter"),
    statusFilter:         document.getElementById("statusfilter"),

    // Handoff 프로젝트 사이드바
    handoffProjectCount:  document.getElementById("handoff-project-count"),
    handoffProjectSearch: document.getElementById("handoff-project-search"),
    handoffProjectList:   document.getElementById("handoff-project-list"),
    handoffTreeSort:      document.getElementById("handoff-tree-sort"),
    handoffDirFilter:     document.getElementById("handoff-dir-filter"),
    handoffStatusFilter:  document.getElementById("handoff-status-filter"),
    handoffLegendClaude:  document.getElementById("handoff-legend-claude"),
    handoffLegendAgy:     document.getElementById("handoff-legend-agy"),
    handoffAutoBar:       document.getElementById("handoff-auto-bar"),
    handoffAutoState:     document.getElementById("handoff-auto-state"),
    handoffAutoDetail:    document.getElementById("handoff-auto-detail"),
    handoffAutoToggle:    document.getElementById("handoff-auto-toggle"),
    handoffAutoReset:     document.getElementById("handoff-auto-reset"),

    // 사이드바 푸터 & 컨트롤
    watcherPulseDot:      document.getElementById("watcher-pulse-dot"),
    watcherStatusText:    document.getElementById("watcher-status-text"),
    watcherStartBtn:      document.getElementById("watcher-start"),
    watcherStartMsg:      document.getElementById("watcher-start-msg"),
    autoRefresh:          document.getElementById("autorefresh"),
    refreshBtn:           document.getElementById("refresh"),

    // 상단 탑바
    topbarCategory:       document.getElementById("topbar-category"),
    topbarCurrent:        document.getElementById("topbar-current"),
    topbarCount:          document.getElementById("topbar-count"),
    topbarUpdated:        document.getElementById("topbar-updated"),

    // 메인 뷰 패널들
    viewDashboard:        document.getElementById("view-dashboard"),
    viewQa:               document.getElementById("view-qa"),
    viewHandoff:          document.getElementById("view-handoff"),
    mainScroll:           document.getElementById("main-content-scroll"),

    // 대시보드 내부 엘리먼트
    dashNow:              document.getElementById("dash-now"),
    nowStatusText:        document.getElementById("now-status-text"),
    nowAside:             document.getElementById("now-aside"),
    nowTitle:             document.getElementById("now-title"),
    nowMeta:              document.getElementById("now-meta"),
    outcomeStrip:         document.getElementById("outcome-strip"),
    dashAttention:        document.getElementById("dash-attention"),
    dashAttentionCount:   document.getElementById("dash-attention-count"),
    dashTimeline:         document.getElementById("dash-timeline"),
    dashStats:            document.getElementById("dash-stats"),
    btnViewAllQa:         document.getElementById("btn-view-all-qa"),
    btnViewAllHandoff:    document.getElementById("btn-view-all-handoff"),
    modelBarsContainer:   document.getElementById("model-bars-container"),

    // QA 메인 뷰 내부
    qaCurrentSessionTitle: document.getElementById("qa-current-session-title"),
    qaCurrentSessionCount: document.getElementById("qa-current-session-count"),
    qaSearch:             document.getElementById("search"),
    qaSessionChips:       document.getElementById("qa-session-chips"),
    chipQaModels:         document.getElementById("chip-qa-models"),
    chipQaStatus:         document.getElementById("chip-qa-status"),
    chipQaTime:           document.getElementById("chip-qa-time"),
    cards:                document.getElementById("cards"),
    loadMoreBtn:          document.getElementById("loadmore"),

    // Handoff 메인 뷰 내부
    handoffCurrentProjectTitle: document.getElementById("handoff-current-project-title"),
    handoffCurrentProjectCount: document.getElementById("handoff-current-project-count"),
    handoffSearch:        document.getElementById("handoff-search"),
    handoffBriefCard:    document.getElementById("handoff-brief-card"),
    briefProjectName:     document.getElementById("brief-project-name"),
    handoffBriefContent:  document.getElementById("handoff-brief-content"),
    handoffCards:         document.getElementById("handoff-cards"),
  };

  // 애플리케이션 상태
  var currentNav = "dashboard"; // "dashboard" | "qa" | "handoff"
  var currentQaSession = "";    // ""(프로젝트 전체) | 세션 노드 id
  var currentQaProject = "";    // ""(전체 프로젝트) | 프로젝트 노드 id
  var currentQaAgy = "";        // ""(범위 안의 모든 agy 세션) | "__none__"(@session 없는 단발성) | agy 세션 이름
  var claudeTree = null;        // 마지막으로 받은 /api/claude/tree 응답
  var currentHandoffProject = ""; // ""(전체 프로젝트) | 프로젝트 노드 id
  var currentHandoffSession = ""; // ""(프로젝트 전체) | 세션 노드 id
  var handoffChannels = {};     // 채널 이름 -> /api/handoff/project 응답 ({name, brief, files, messages})

  var allItems = [];            // 전체 완료 QA 레코드
  var pendingItems = [];        // inbox 대기/진행 작업
  var handoffProjects = [];     // 인수인계 프로젝트 목록
  var currentHandoffData = null;// 선택된 프로젝트 상세
  var handoffMessageCache = {}; // 메시지 본문 캐시
  var openHandoffNums = {};     // 열려 있는 메시지 번호

  var filteredQa = [];          // 필터 적용된 완료 QA
  var filteredPending = [];     // 필터 적용된 pending
  var shownQaCount = 0;         // 현재 렌더링된 카드 수
  var knownShardKey = "";       // QA 데이터 변경 감지 키
  var lastPendingKey = "";      // pending 변경 감지 키
  var refreshTimer = null;
  var watcherStarting = false;   // 켜기 요청 후 켜질 때까지 true
  var isServerOnline = false;
  var systemStatus = null;      // 마지막 /api/status 응답
  var nowTicker = null;         // "지금" 패널 경과 시간 1초 갱신 타이머

  // ==========================================================================
  // HTTP Fetch & Utility
  // ==========================================================================

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
      try { out.push(JSON.parse(line)); } catch (e) { /* skip */ }
    }
    return out;
  }

  function escapeHtml(str) {
    if (!str) return "";
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  // index.html 의 <symbol id="i-..."> 아이콘을 참조하는 SVG 마크업
  function icon(name) {
    return '<svg class="icon" aria-hidden="true"><use href="#i-' + name + '"/></svg>';
  }

  // 클릭으로만 동작하던 div 항목을 키보드(Tab, Enter, Space)로도 쓸 수 있게 한다.
  function makeActivatable(el, label) {
    el.tabIndex = 0;
    el.setAttribute("role", "button");
    if (label) el.setAttribute("aria-label", label);
  }

  function parseLocalTime(dateStr) {
    if (!dateStr) return null;
    var d = new Date(String(dateStr).replace(/-/g, "/"));
    return isNaN(d.getTime()) ? null : d;
  }

  function pad2(n) { return (n < 10 ? "0" : "") + n; }

  // 오늘이면 "14:05", 아니면 "09-22"
  function formatClock(dateStr) {
    var d = parseLocalTime(dateStr);
    if (!d) return "";
    var now = new Date();
    if (d.toDateString() === now.toDateString()) {
      return pad2(d.getHours()) + ":" + pad2(d.getMinutes());
    }
    return pad2(d.getMonth() + 1) + "-" + pad2(d.getDate());
  }

  function formatDuration(sec) {
    sec = Math.max(0, Math.floor(sec));
    if (sec < 60) return sec + "초";
    var m = Math.floor(sec / 60);
    var s = sec % 60;
    if (m < 60) return m + "분 " + pad2(s) + "초";
    return Math.floor(m / 60) + "시간 " + pad2(m % 60) + "분";
  }

  function localDateKey(d) {
    return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate());
  }

  // 기록의 모델명. 실패 기록은 model 이 빈 문자열이라, 시도한 모델(tried_models)로 대신한다.
  function recordModel(r) {
    if (!r) return "";
    var m = r.model ? String(r.model).trim() : "";
    if (m && m !== "(session)") return m;
    return r.tried_models ? String(r.tried_models).trim() : "";
  }

  function isOkStatus(r) {
    if (!r || r.status == null) return false;
    return String(r.status).trim() === "OK";
  }

  function shardKeyOf(index) {
    if (!index || !index.shards) { return ""; }
    return index.shards.map(function (s) { return s.file + ":" + s.bytes; }).join(",");
  }

  function pendingKeyOf(list) {
    if (!list || !list.length) { return ""; }
    return list.map(function (p) {
      var pg = p.progress || {};
      var tok = (pg.tokens && pg.tokens.total) ? pg.tokens.total : 0;
      return [
        p.task_id || "",
        p.state || "",
        p.model || "",
        p.started_at || "",
        pg.step != null ? pg.step : "",
        pg.last_activity_ms || "",
        tok
      ].join(":");
    }).join(",");
  }

  function formatRelativeTime(dateStr) {
    if (!dateStr) return "-";
    try {
      var d = new Date(dateStr.replace(/-/g, "/"));
      if (isNaN(d.getTime())) return dateStr;
      var now = new Date();
      var diffSec = Math.floor((now.getTime() - d.getTime()) / 1000);
      if (diffSec < 60) return "방금 전";
      if (diffSec < 3600) return Math.floor(diffSec / 60) + "분 전";
      if (diffSec < 86400) return Math.floor(diffSec / 3600) + "시간 전";
      return Math.floor(diffSec / 86400) + "일 전";
    } catch (e) {
      return dateStr;
    }
  }

  // ==========================================================================
  // Router & Navigation Logic
  // ==========================================================================

  function parseHash() {
    var hash = window.location.hash || "#/dashboard";
    var qIdx = hash.indexOf("?");
    var path = qIdx >= 0 ? hash.slice(0, qIdx) : hash;
    var qs = qIdx >= 0 ? hash.slice(qIdx + 1) : "";
    var params = {};
    if (qs) {
      qs.split("&").forEach(function (part) {
        if (!part) return;
        var eqIdx = part.indexOf("=");
        var k = eqIdx >= 0 ? part.slice(0, eqIdx) : part;
        var v = eqIdx >= 0 ? part.slice(eqIdx + 1) : "";
        try {
          params[decodeURIComponent(k)] = decodeURIComponent(v);
        } catch (e) {
          params[k] = v;
        }
      });
    }

    if (path === "#/qa") {
      return { nav: "qa", session: params.session || "", project: params.project || "", agy: params.agy || "" };
    }
    var matchHandoff = path.match(/^#\/handoff$/);
    if (matchHandoff) {
      return { nav: "handoff", session: params.session || "", project: params.project || "" };
    }
    return { nav: "dashboard", session: "", project: "" };
  }

  function updateHash() {
    var newHash = "#/" + currentNav;
    if (currentNav === "qa") {
      var parts = [];
      if (currentQaProject) {
        parts.push("project=" + encodeURIComponent(currentQaProject));
      }
      if (currentQaSession) {
        parts.push("session=" + encodeURIComponent(currentQaSession));
      }
      if (currentQaAgy) {
        parts.push("agy=" + encodeURIComponent(currentQaAgy));
      }
      if (parts.length > 0) {
        newHash += "?" + parts.join("&");
      }
    } else if (currentNav === "handoff") {
      var hParts = [];
      if (currentHandoffProject) {
        hParts.push("project=" + encodeURIComponent(currentHandoffProject));
      }
      if (currentHandoffSession) {
        hParts.push("session=" + encodeURIComponent(currentHandoffSession));
      }
      if (hParts.length > 0) {
        newHash += "?" + hParts.join("&");
      }
    }
    if (window.location.hash !== newHash) {
      history.replaceState(null, "", newHash);
    }
  }

  function switchNav(nav, updateUrl) {
    if (nav !== "dashboard" && nav !== "qa" && nav !== "handoff") {
      nav = "dashboard";
    }
    currentNav = nav;

    // 1차 네비게이션 버튼 활성화
    [els.navBtnDashboard, els.navBtnQa, els.navBtnHandoff].forEach(function (btn) {
      if (btn) {
        var isActive = (btn.dataset.nav === nav);
        btn.classList.toggle("active", isActive);
        btn.setAttribute("aria-selected", isActive ? "true" : "false");
      }
    });

    // 2차 서브 패널 전환
    if (els.subDashboard) els.subDashboard.style.display = (nav === "dashboard" ? "flex" : "none");
    if (els.subQa) els.subQa.style.display = (nav === "qa" ? "flex" : "none");
    if (els.subHandoff) els.subHandoff.style.display = (nav === "handoff" ? "flex" : "none");

    // 메인 뷰 전환
    if (els.viewDashboard) els.viewDashboard.style.display = (nav === "dashboard" ? "block" : "none");
    if (els.viewQa) els.viewQa.style.display = (nav === "qa" ? "block" : "none");
    if (els.viewHandoff) els.viewHandoff.style.display = (nav === "handoff" ? "block" : "none");

    // 상단 브레드크럼 및 상태 갱신
    updateBreadcrumbs();
    updateTopbarMeta();

    if (updateUrl !== false) {
      updateHash();
    }

    try {
      localStorage.setItem("samjil_active_nav", nav);
    } catch (e) {}

    // 모바일에서 메뉴 선택 시 사이드바 닫기
    if (window.innerWidth <= 768 && els.appSidebar) {
      els.appSidebar.classList.remove("open");
    }

    // 뷰 전환에 따른 렌더링 호출
    if (nav !== "dashboard") { stopNowTicker(); }
    if (nav === "dashboard") {
      renderDashboard();
    } else if (nav === "qa") {
      applyQaFilters();
    } else if (nav === "handoff") {
      renderHandoffView();
    }
  }

  function updateBreadcrumbs() {
    if (!els.topbarCategory || !els.topbarCurrent) return;

    if (currentNav === "dashboard") {
      els.topbarCategory.textContent = "홈";
      els.topbarCurrent.textContent = "대시보드";
    } else if (currentNav === "qa") {
      els.topbarCategory.textContent = "위임 실행 기록";
      if (!currentQaProject) {
        els.topbarCurrent.textContent = "전체 프로젝트 피드";
      } else {
        var tree = buildQaTree(allItems, pendingItems, claudeTree);
        var titles = findQaNodeTitles(tree, currentQaProject, currentQaSession);
        if (!currentQaSession) {
          els.topbarCurrent.textContent = titles.projectName;
        } else {
          els.topbarCurrent.textContent = titles.projectName + " / " + titles.sessionTitle;
        }
      }
    } else if (currentNav === "handoff") {
      els.topbarCategory.textContent = "에이전트 인수인계";
      if (!currentHandoffProject) {
        els.topbarCurrent.textContent = "전체 프로젝트";
      } else {
        var hTree = buildHandoffTree(handoffChannels, claudeTree);
        var hTitles = findHandoffNodeTitles(hTree, currentHandoffProject, currentHandoffSession);
        if (!currentHandoffSession) {
          els.topbarCurrent.textContent = hTitles.projectName;
        } else {
          els.topbarCurrent.textContent = hTitles.projectName + " / " + hTitles.sessionTitle;
        }
      }
    }
  }

  function updateTopbarMeta() {
    if (!els.topbarCount || !els.topbarUpdated) return;

    if (currentNav === "dashboard") {
      els.topbarCount.textContent = "총 " + allItems.length + "건 위임 / " + handoffProjects.length + "개 프로젝트";
    } else if (currentNav === "qa") {
      var count = filteredQa.length + filteredPending.length;
      els.topbarCount.textContent = count + "건 표시 중 (전체 " + allItems.length + "건)";
    } else if (currentNav === "handoff") {
      var hMsgs = handoffMessagesOf(handoffChannels, claudeTree, currentHandoffProject, currentHandoffSession);
      els.topbarCount.textContent = hMsgs.length + "개 메시지";
    }

    var t = new Date();
    els.topbarUpdated.textContent = pad2(t.getHours()) + ":" + pad2(t.getMinutes()) + ":" + pad2(t.getSeconds()) + " 갱신";
  }

  // ==========================================================================
  // Data Loaders
  // ==========================================================================

  // 시스템 런타임 상태 로드 (/api/status)
  function loadSystemStatus() {
    return fetchJson("/api/status")
      .then(function (status) {
        isServerOnline = true;
        systemStatus = status;
        if (status) {
          var isWatcherAlive = Boolean(status.watcherAlive);
          if (els.watcherPulseDot) {
            els.watcherPulseDot.classList.toggle("offline", !isWatcherAlive);
          }
          if (els.watcherStatusText) {
            els.watcherStatusText.textContent = isWatcherAlive
              ? "agy 워처 켜짐"
              : (status.manualStop ? "agy 워처 꺼짐 (수동 정지)" : "agy 워처 꺼짐");
          }
        }
        updateWatcherStartButton(status);
        return status;
      })
      .catch(function () {
        isServerOnline = false;
        systemStatus = null;
        if (els.watcherPulseDot) els.watcherPulseDot.classList.add("offline");
        if (els.watcherStatusText) {
          els.watcherStatusText.textContent = "뷰어 서버 연결 끊김";
        }
        updateWatcherStartButton(null);
        return null;
      });
  }

  // 켜기 버튼: 워처가 꺼져 있고 서버가 켜 줄 수 있을 때만 보인다. 켜는 중에는 켜질 때까지 남겨 둔다.
  function updateWatcherStartButton(status) {
    if (!els.watcherStartBtn) return;
    var canShow = Boolean(status) && !status.watcherAlive && status.canStart === true;
    els.watcherStartBtn.hidden = !(canShow || watcherStarting);
  }

  function showWatcherStartMsg(text, isError) {
    if (!els.watcherStartMsg) return;
    els.watcherStartMsg.textContent = text || "";
    els.watcherStartMsg.classList.toggle("is-error", Boolean(isError));
    els.watcherStartMsg.hidden = !text;
  }

  function finishWatcherStart() {
    watcherStarting = false;
    if (els.watcherStartBtn) {
      els.watcherStartBtn.disabled = false;
      els.watcherStartBtn.textContent = "켜기";
      els.watcherStartBtn.removeAttribute("aria-busy");
    }
    updateWatcherStartButton(systemStatus);
  }

  // 켜졌는지 2초마다 확인한다. 워처가 PID 잠금 파일을 쓰기까지 몇 초 걸린다.
  function waitForWatcherAlive() {
    var deadline = Date.now() + 30000;
    return new Promise(function (resolve) {
      (function poll() {
        loadSystemStatus().then(function (st) {
          if (st && st.watcherAlive) { finishWatcherStart(); refresh(false); resolve(); return; }
          if (Date.now() > deadline) {
            showWatcherStartMsg("30초 안에 켜지지 않았습니다. runtime/logs/watcher.log를 확인하세요.", true);
            finishWatcherStart();
            resolve();
            return;
          }
          setTimeout(poll, 2000);
        });
      })();
    });
  }

  function startWatcher() {
    if (watcherStarting) return;
    watcherStarting = true;
    showWatcherStartMsg("", false);
    if (els.watcherStartBtn) {
      els.watcherStartBtn.disabled = true;
      els.watcherStartBtn.textContent = "켜는 중…";
      els.watcherStartBtn.setAttribute("aria-busy", "true");
    }
    // 전용 헤더가 있어야 서버가 받는다(다른 웹 페이지의 몰래 요청 차단)
    fetch("/api/watcher/start", { method: "POST", headers: { "X-Samjil-Viewer": "1" } })
      .then(function (r) {
        return r.json().then(function (body) { return { ok: r.ok, body: body }; });
      })
      .then(function (res) {
        if (!res.ok || !res.body) { throw new Error("서버가 요청을 받지 않았습니다"); }
        var result = res.body.result;
        if (result === "no-script" || result === "failed") {
          showWatcherStartMsg(res.body.message, true);
          finishWatcherStart();
          return null;
        }
        if (result === "already-running") { finishWatcherStart(); refresh(false); return null; }
        return waitForWatcherAlive();   // started, busy
      })
      .catch(function (err) {
        showWatcherStartMsg("켜지 못했습니다: " + err.message, true);
        finishWatcherStart();
      });
  }

  // 위임 inbox 대기열 목록 로드
  function loadPending() {
    return fetchJson("/api/delegate/pending")
      .then(function (data) {
        return Array.isArray(data) ? data : [];
      })
      .catch(function () {
        return [];
      });
  }

  // 위임 완료 레코드 전체 로드
  var shardDataCache = {};

  function loadAllQa(force) {
    if (force) {
      knownShardKey = "";
      shardDataCache = {};
    }
    return fetchJson("/data/index.json").then(function (index) {
      var key = shardKeyOf(index);
      var changed = (key !== knownShardKey);
      knownShardKey = key;

      if (!changed && !force && allItems.length > 0) {
        return { changed: false, index: index };
      }

      var shards = (index && index.shards) ? index.shards : [];
      var activeFiles = {};
      var loaders = shards.map(function (s) {
        activeFiles[s.file] = true;
        var cached = shardDataCache[s.file];
        if (!force && cached && cached.bytes === s.bytes) {
          return Promise.resolve(cached.items);
        }
        return fetchText("/data/" + encodeURIComponent(s.file))
          .then(parseJsonl)
          .then(function (parsed) {
            shardDataCache[s.file] = { bytes: s.bytes, items: parsed };
            return parsed;
          })
          .catch(function () { return cached ? cached.items : []; });
      });

      Object.keys(shardDataCache).forEach(function (f) {
        if (!activeFiles[f]) { delete shardDataCache[f]; }
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

  // 인수인계 채널 목록 및 모든 채널 상세 로드
  function loadHandoffProjects(force) {
    return fetchJson("/api/handoff/projects").then(function (projects) {
      if (!Array.isArray(projects)) { projects = []; }
      handoffProjects = projects;

      var loaders = projects.map(function (p) {
        var cName = p.name;
        var cached = handoffChannels[cName];
        if (!force && cached && cached.updated === p.updated && Array.isArray(cached.messages) && cached.messages.length === (p.msgCount || 0)) {
          return Promise.resolve(cached);
        }
        return fetchJson("/api/handoff/project?name=" + encodeURIComponent(cName))
          .then(function (data) {
            if (data && typeof data === "object") {
              handoffChannels[cName] = data;
              return data;
            }
            return cached || { name: cName, brief: "", files: [], messages: [] };
          })
          .catch(function (err) {
            console.warn("Handoff channel load error (" + cName + "):", err);
            return cached || { name: cName, brief: "", files: [], messages: [] };
          });
      });

      return Promise.all(loaders).then(function () {
        var validMap = {};
        projects.forEach(function (p) { validMap[p.name] = true; });
        for (var k in handoffChannels) {
          if (!validMap[k]) delete handoffChannels[k];
        }
        if (currentHandoffProject && !currentHandoffSession && handoffChannels[currentHandoffProject]) {
          var treeCheck = buildHandoffTree(handoffChannels, claudeTree);
          var matchProj = treeCheck.some(function (p) { return p.id === currentHandoffProject; });
          if (!matchProj) {
            currentHandoffSession = "c:" + currentHandoffProject;
            currentHandoffProject = QA_UNLINKED;
          }
        }

        renderHandoffTree();
        if (currentNav === "handoff") {
          renderHandoffView();
        }
        return projects;
      });
    }).catch(function (err) {
      console.warn("Handoff projects load error:", err);
      return [];
    });
  }

  // ==========================================================================
  // Session Grouping & QA Side-Panel List
  // ==========================================================================

  function groupQaSessions() {
    var map = {};
    // 1. pending 목록 집계
    pendingItems.forEach(function (p) {
      var sKey = p.session || "__none__";
      if (!map[sKey]) {
        map[sKey] = { name: sKey, total: 0, pending: 0, errors: 0, latestTime: p.created || "", models: {} };
      }
      map[sKey].pending++;
      if (p.created && (!map[sKey].latestTime || p.created > map[sKey].latestTime)) {
        map[sKey].latestTime = p.created;
      }
    });

    // 2. 완료 기록 집계
    allItems.forEach(function (r) {
      var sKey = r.session || "__none__";
      if (!map[sKey]) {
        map[sKey] = { name: sKey, total: 0, pending: 0, errors: 0, latestTime: r.timestamp || "", models: {} };
      }
      map[sKey].total++;
      if (r.status && String(r.status).trim() !== "OK") {
        map[sKey].errors++;
      }
      if (recordModel(r)) {
        map[sKey].models[recordModel(r)] = true;
      }
      if (r.timestamp && (!map[sKey].latestTime || r.timestamp > map[sKey].latestTime)) {
        map[sKey].latestTime = r.timestamp;
      }
    });

    var list = Object.keys(map).map(function (k) { return map[k]; });
    // 최신 시간순 정렬
    list.sort(function (a, b) {
      return String(b.latestTime || "").localeCompare(String(a.latestTime || ""));
    });

    return list;
  }

  var QA_UNGROUPED = "__ungrouped__";
  var QA_UNLINKED = "__unlinked__";

  // 폴더 경로 비교용 키(대소문자·슬래시 방향·끝의 구분자 무시)
  function qaCwdKey(p) {
    return String(p == null ? "" : p).trim().replace(/\//g, "\\").replace(/\\+$/, "").toLowerCase();
  }

  // 아직 대화 기록에 작업 ID 가 남지 않은 대기·진행 중 작업의 세션을 작업 폴더로 짐작한다.
  // (Claude 가 위임을 보내고 같은 명령 안에서 결과를 기다리면, 그 명령이 끝날 때까지 작업 ID 가 대화 기록에 안 남아서 연결할 수 없다.)
  // 작업 폴더(@cwd)가 Desktop 세션의 폴더와 같은 세션 중 가장 최근에 쓴 보관 안 된 세션을 고른다. 없으면 null.
  function qaGuessSessionByCwd(item, tree) {
    if (!item || !tree) return null;
    var raw = item.cwd;
    var cwds = Array.isArray(raw) ? raw : (raw ? [raw] : []);
    var keys = {};
    var any = false;
    for (var i = 0; i < cwds.length; i++) {
      var k = qaCwdKey(cwds[i]);
      if (k) { keys[k] = true; any = true; }
    }
    if (!any) return null;
    var best = null;
    function consider(sess, projectId, projectName) {
      if (!sess || sess.archived || !keys[qaCwdKey(sess.cwd)]) return;
      if (!best || String(sess.lastActivity || "") > String(best.sess.lastActivity || "")) {
        best = { sess: sess, projectId: projectId, projectName: projectName };
      }
    }
    var projects = Array.isArray(tree.projects) ? tree.projects : [];
    for (var a = 0; a < projects.length; a++) {
      var sessions = projects[a] && Array.isArray(projects[a].sessions) ? projects[a].sessions : [];
      for (var b = 0; b < sessions.length; b++) { consider(sessions[b], projects[a].id, projects[a].name); }
    }
    var ungrouped = Array.isArray(tree.ungrouped) ? tree.ungrouped : [];
    for (var c = 0; c < ungrouped.length; c++) { consider(ungrouped[c], QA_UNGROUPED, "그룹 없음"); }
    if (!best) return null;
    return {
      projectId: best.projectId,
      projectName: best.projectName,
      sessionId: best.sess.id,
      sessionTitle: best.sess.title ? best.sess.title : String(best.sess.id).slice(0, 8)
    };
  }

  function qaNodeOf(item, tree) {
    var link = (tree && tree.taskLinks && item && item.task_id) ? tree.taskLinks[item.task_id] : null;
    if (link) {
      if (tree && Array.isArray(tree.projects)) {
        for (var i = 0; i < tree.projects.length; i++) {
          var p = tree.projects[i];
          if (p && Array.isArray(p.sessions)) {
            for (var j = 0; j < p.sessions.length; j++) {
              var s = p.sessions[j];
              if (s && s.id === link) {
                return {
                  projectId: p.id,
                  projectName: p.name,
                  sessionId: link,
                  sessionTitle: s.title ? s.title : link.slice(0, 8)
                };
              }
            }
          }
        }
      }
      if (tree && Array.isArray(tree.ungrouped)) {
        for (var k = 0; k < tree.ungrouped.length; k++) {
          var us = tree.ungrouped[k];
          if (us && us.id === link) {
            return {
              projectId: QA_UNGROUPED,
              projectName: "그룹 없음",
              sessionId: link,
              sessionTitle: us.title ? us.title : link.slice(0, 8)
            };
          }
        }
      }
    }
    // 대기·진행 중인 작업(완료 기록과 달리 timestamp 가 없고 state 가 있다)은 작업 폴더로 세션을 짐작해 본다
    if (item && item.state && !item.timestamp) {
      var guessed = qaGuessSessionByCwd(item, tree);
      if (guessed) return guessed;
    }
    var sName = (item && item.session != null && String(item.session).trim() !== "") ? String(item.session) : "";
    return {
      projectId: QA_UNLINKED,
      projectName: "연결 안 됨",
      sessionId: "u:" + (sName ? sName : "__none__"),
      sessionTitle: sName ? sName : "단발성 (세션 없음)"
    };
  }

  function buildQaTree(records, pendings, tree) {
    var recs = Array.isArray(records) ? records : [];
    var pends = Array.isArray(pendings) ? pendings : [];

    var projectList = [];
    var sessionLookup = {};

    if (tree && Array.isArray(tree.projects)) {
      for (var i = 0; i < tree.projects.length; i++) {
        var p = tree.projects[i];
        if (!p) continue;
        var pNode = {
          id: p.id,
          name: p.name || "",
          total: 0,
          pending: 0,
          errors: 0,
          latestTime: "",
          sessions: []
        };
        if (Array.isArray(p.sessions)) {
          for (var j = 0; j < p.sessions.length; j++) {
            var s = p.sessions[j];
            if (!s) continue;
            var sNode = {
              id: s.id,
              title: s.title ? s.title : String(s.id || "").slice(0, 8),
              cwd: s.cwd || "",
              total: 0,
              pending: 0,
              errors: 0,
              latestTime: "",
              archived: Boolean(s.archived),
              lastActivity: s.lastActivity || ""
            };
            pNode.sessions.push(sNode);
            sessionLookup[s.id] = sNode;
          }
        }
        projectList.push(pNode);
      }
    }

    var ungroupedNode = null;
    if (tree && Array.isArray(tree.ungrouped) && tree.ungrouped.length > 0) {
      ungroupedNode = {
        id: QA_UNGROUPED,
        name: "그룹 없음",
        total: 0,
        pending: 0,
        errors: 0,
        latestTime: "",
        sessions: []
      };
      for (var u = 0; u < tree.ungrouped.length; u++) {
        var us = tree.ungrouped[u];
        if (!us) continue;
        var usNode = {
          id: us.id,
          title: us.title ? us.title : String(us.id || "").slice(0, 8),
          cwd: us.cwd || "",
          total: 0,
          pending: 0,
          errors: 0,
          latestTime: "",
          archived: Boolean(us.archived),
          lastActivity: us.lastActivity || ""
        };
        ungroupedNode.sessions.push(usNode);
        sessionLookup[us.id] = usNode;
      }
    }

    var unlinkedNode = {
      id: QA_UNLINKED,
      name: "연결 안 됨",
      total: 0,
      pending: 0,
      errors: 0,
      latestTime: "",
      sessions: []
    };
    var unlinkedSessionMap = {};

    function processItem(item, isPending) {
      if (!item || typeof item !== "object") return;
      var nodeInfo = qaNodeOf(item, tree);
      var time = isPending ? (item.created || "") : (item.timestamp || "");
      var isErr = !isPending && item.status && String(item.status).trim() !== "OK";

      var targetSession = null;
      if (nodeInfo.projectId === QA_UNLINKED) {
        targetSession = unlinkedSessionMap[nodeInfo.sessionId];
        if (!targetSession) {
          targetSession = {
            id: nodeInfo.sessionId,
            title: nodeInfo.sessionTitle,
            cwd: "",
            total: 0,
            pending: 0,
            errors: 0,
            latestTime: "",
            archived: false,
            lastActivity: ""
          };
          unlinkedSessionMap[nodeInfo.sessionId] = targetSession;
          unlinkedNode.sessions.push(targetSession);
        }
      } else {
        targetSession = sessionLookup[nodeInfo.sessionId];
      }

      if (targetSession) {
        if (isPending) {
          targetSession.pending++;
        } else {
          targetSession.total++;
          if (isErr) {
            targetSession.errors++;
          }
        }
        if (time && (!targetSession.latestTime || time > targetSession.latestTime)) {
          targetSession.latestTime = time;
        }
        // 완료 시각: 끝난 기록의 시각만(진행·대기 중인 작업은 뺀다). 사이드바 행에 보이는 시간이다.
        if (!isPending && time && (!targetSession.latestDone || time > targetSession.latestDone)) {
          targetSession.latestDone = time;
        }
      }
    }

    for (var rIdx = 0; rIdx < recs.length; rIdx++) {
      processItem(recs[rIdx], false);
    }
    for (var pIdx = 0; pIdx < pends.length; pIdx++) {
      processItem(pends[pIdx], true);
    }

    function finalizeProject(p) {
      var validSessions = [];
      for (var i = 0; i < p.sessions.length; i++) {
        var s = p.sessions[i];
        if (s.archived && (s.total + s.pending === 0)) {
          continue;
        }
        validSessions.push(s);
      }

      validSessions.sort(function (a, b) {
        var aTime = a.latestTime || "";
        if (a.lastActivity && (!aTime || a.lastActivity > aTime)) {
          aTime = a.lastActivity;
        }
        var bTime = b.latestTime || "";
        if (b.lastActivity && (!bTime || b.lastActivity > bTime)) {
          bTime = b.lastActivity;
        }
        if (bTime !== aTime) {
          return bTime > aTime ? 1 : -1;
        }
        return (a.title || "").localeCompare(b.title || "");
      });

      var pTotal = 0;
      var pPending = 0;
      var pErrors = 0;
      var pLatest = "";
      var pDone = "";

      for (var j = 0; j < validSessions.length; j++) {
        var vs = validSessions[j];
        pTotal += vs.total;
        pPending += vs.pending;
        pErrors += vs.errors;
        if (vs.latestTime && (!pLatest || vs.latestTime > pLatest)) {
          pLatest = vs.latestTime;
        }
        if (vs.latestDone && (!pDone || vs.latestDone > pDone)) {
          pDone = vs.latestDone;
        }
      }

      p.sessions = validSessions;
      p.total = pTotal;
      p.pending = pPending;
      p.errors = pErrors;
      p.latestTime = pLatest;
      p.latestDone = pDone;
    }

    var result = [];

    for (var pI = 0; pI < projectList.length; pI++) {
      finalizeProject(projectList[pI]);
      result.push(projectList[pI]);
    }

    if (ungroupedNode) {
      finalizeProject(ungroupedNode);
      if (ungroupedNode.sessions.length > 0) {
        result.push(ungroupedNode);
      }
    }

    finalizeProject(unlinkedNode);
    if (unlinkedNode.sessions.length > 0 && (unlinkedNode.total + unlinkedNode.pending > 0)) {
      result.push(unlinkedNode);
    }

    return result;
  }

  function qaFilterTree(nodes, query) {
    if (!Array.isArray(nodes)) return [];
    var q = (query == null ? "" : String(query)).trim().toLowerCase();
    if (!q) {
      return nodes.slice();
    }
    var result = [];
    for (var i = 0; i < nodes.length; i++) {
      var p = nodes[i];
      if (!p) continue;
      var pName = (p.name || "").toLowerCase();
      if (pName.indexOf(q) !== -1) {
        result.push({
          id: p.id,
          name: p.name,
          total: p.total,
          pending: p.pending,
          errors: p.errors,
          latestTime: p.latestTime,
          sessions: Array.isArray(p.sessions) ? p.sessions.slice() : []
        });
      } else {
        var matchingSessions = [];
        if (Array.isArray(p.sessions)) {
          for (var j = 0; j < p.sessions.length; j++) {
            var s = p.sessions[j];
            if (s && (s.title || "").toLowerCase().indexOf(q) !== -1) {
              matchingSessions.push(s);
            }
          }
        }
        if (matchingSessions.length > 0) {
          result.push({
            id: p.id,
            name: p.name,
            total: p.total,
            pending: p.pending,
            errors: p.errors,
            latestTime: p.latestTime,
            sessions: matchingSessions
          });
        }
      }
    }
    return result;
  }

  function qaItemMatchesSelection(item, tree, projectId, sessionId) {
    if (!projectId) return true;
    var node = qaNodeOf(item, tree);
    if (node.projectId !== projectId) return false;
    if (sessionId && node.sessionId !== sessionId) return false;
    return true;
  }

  function qaItemMatchesAgy(item, agy) {
    if (!agy) return true;
    var s = (item && item.session != null) ? String(item.session).trim() : "";
    if (agy === "__none__") {
      return s === "";
    }
    return s === agy;
  }

  function qaAgySessionsOf(records, pendings, tree, projectId, sessionId) {
    var recs = Array.isArray(records) ? records : [];
    var pends = Array.isArray(pendings) ? pendings : [];
    var map = {};

    function processItem(item, isPending) {
      if (!item || typeof item !== "object") return;
      if (!qaItemMatchesSelection(item, tree, projectId, sessionId)) return;

      var rawS = (item.session != null) ? String(item.session).trim() : "";
      var sKey = rawS ? rawS : "__none__";

      if (!map[sKey]) {
        map[sKey] = {
          name: sKey,
          total: 0,
          pending: 0,
          errors: 0,
          latestTime: ""
        };
      }

      var entry = map[sKey];
      var time = isPending ? (item.created || "") : (item.timestamp || "");
      if (isPending) {
        entry.pending++;
      } else {
        entry.total++;
        if (item.status && String(item.status).trim() !== "OK") {
          entry.errors++;
        }
      }
      if (time && (!entry.latestTime || time > entry.latestTime)) {
        entry.latestTime = time;
      }
    }

    for (var r = 0; r < recs.length; r++) {
      processItem(recs[r], false);
    }
    for (var p = 0; p < pends.length; p++) {
      processItem(pends[p], true);
    }

    var list = [];
    for (var k in map) {
      if (Object.prototype.hasOwnProperty.call(map, k)) {
        list.push(map[k]);
      }
    }

    list.sort(function (a, b) {
      var tA = a.latestTime || "";
      var tB = b.latestTime || "";
      if (tA !== tB) {
        return tB > tA ? 1 : -1;
      }
      if (a.name !== b.name) {
        return a.name < b.name ? -1 : 1;
      }
      return 0;
    });

    return list;
  }

  var TREE_SORT_MODES = [{"value":"recent-desc","label":"날짜 최신순"},{"value":"recent-asc","label":"날짜 오래된순"},{"value":"name-asc","label":"이름순 (가나다)"},{"value":"name-desc","label":"이름 역순"},{"value":"desktop","label":"Desktop 순서"}];
  var TREE_SORT_DEFAULT = "recent-desc";

  function normalizeTreeSortMode(v) {
    if (!v || typeof v !== "string") return TREE_SORT_DEFAULT;
    for (var i = 0; i < TREE_SORT_MODES.length; i++) {
      if (TREE_SORT_MODES[i].value === v) return v;
    }
    return TREE_SORT_DEFAULT;
  }

  // 프로젝트 행의 부제에 보일 "최근 시각": 기록의 최근 시각과 Desktop 세션의 최근 활동 중 늦은 것(기록이 없는 프로젝트도 "-" 대신 시각이 보인다)
  function treeNodeLatest(node) {
    var best = String((node && node.latestTime) || "");
    var list = (node && Array.isArray(node.sessions)) ? node.sessions : [];
    for (var i = 0; i < list.length; i++) {
      var t = String(list[i].latestTime || "");
      var a = String(list[i].lastActivity || "");
      if (t > best) { best = t; }
      if (a > best) { best = a; }
    }
    return best;
  }

  // opts.dateSource === "records" 이면 날짜 정렬이 위임 기록(agy 작업)의 최근 완료 시각만 본다(Desktop 세션의 최근 활동은 무시하고,
  // 시각이 같거나 기록이 없을 때만 보조 기준으로 쓴다). 기본은 기록과 Desktop 활동 중 늦은 쪽.
  function sortTreeNodes(nodes, mode, opts) {
    if (!Array.isArray(nodes)) return [];
    var sortMode = normalizeTreeSortMode(mode);
    var recordsOnly = Boolean(opts && opts.dateSource === "records");

    function maxTime(t1, t2) {
      var s1 = t1 || "";
      var s2 = t2 || "";
      if (!s1) return s2;
      if (!s2) return s1;
      return s1 > s2 ? s1 : s2;
    }

    // records 모드의 기록 시각: 완료 시각(latestDone)이 있으면 그것, 없으면(옛 데이터) latestTime
    function recordTimeOf(x) {
      if (!x) return "";
      return (x.latestDone != null ? x.latestDone : x.latestTime) || "";
    }

    function sessionDateKey(s) {
      if (!s) return "";
      return recordsOnly ? recordTimeOf(s) : maxTime(s.latestTime, s.lastActivity);
    }

    // 보조 기준(records 모드): Desktop 에서 마지막으로 쓴 시각
    function sessionActivityKey(s) {
      return (s && s.lastActivity) ? String(s.lastActivity) : "";
    }
    function projectActivityKey(p) {
      var best = "";
      if (p && Array.isArray(p.sessions)) {
        for (var i = 0; i < p.sessions.length; i++) { best = maxTime(best, sessionActivityKey(p.sessions[i])); }
      }
      return best;
    }

    function projectDateKey(p) {
      if (!p) return "";
      var maxT = recordsOnly ? recordTimeOf(p) : (p.latestTime || "");
      if (Array.isArray(p.sessions)) {
        for (var i = 0; i < p.sessions.length; i++) {
          var s = p.sessions[i];
          if (!s) continue;
          maxT = maxTime(maxT, recordsOnly ? recordTimeOf(s) : s.latestTime);
          if (!recordsOnly) { maxT = maxTime(maxT, s.lastActivity); }
        }
      }
      return maxT;
    }

    function compareDates(tA, tB, isDesc) {
      var sA = tA || "";
      var sB = tB || "";
      if (sA === sB) return 0;
      if (!sA) return isDesc ? 1 : -1;
      if (!sB) return isDesc ? -1 : 1;
      if (isDesc) {
        return sB > sA ? 1 : -1;
      } else {
        return sA > sB ? 1 : -1;
      }
    }

    function sortSessions(sessions, sm) {
      if (!Array.isArray(sessions)) return [];
      var sMode = (sm === "desktop") ? "recent-desc" : sm;
      var list = sessions.map(function (s, idx) {
        return { s: s, idx: idx };
      });

      list.sort(function (itemA, itemB) {
        var a = itemA.s;
        var b = itemB.s;
        if (sMode === "recent-desc" || sMode === "recent-asc") {
          var isDesc = (sMode === "recent-desc");
          var tA = sessionDateKey(a);
          var tB = sessionDateKey(b);
          var dDiff = compareDates(tA, tB, isDesc);
          if (dDiff !== 0) return dDiff;
          if (recordsOnly) {
            var aDiffS = compareDates(sessionActivityKey(a), sessionActivityKey(b), isDesc);
            if (aDiffS !== 0) return aDiffS;
          }
          var titleA = (a && a.title != null) ? String(a.title) : "";
          var titleB = (b && b.title != null) ? String(b.title) : "";
          var nameDiff = titleA.localeCompare(titleB, "ko", { numeric: true, sensitivity: "base" });
          if (nameDiff !== 0) return nameDiff;
          var idA = (a && a.id != null) ? String(a.id) : "";
          var idB = (b && b.id != null) ? String(b.id) : "";
          if (idA !== idB) return idA < idB ? -1 : 1;
          return itemA.idx - itemB.idx;
        } else if (sMode === "name-asc") {
          var tA1 = (a && a.title != null) ? String(a.title) : "";
          var tB1 = (b && b.title != null) ? String(b.title) : "";
          var diff1 = tA1.localeCompare(tB1, "ko", { numeric: true, sensitivity: "base" });
          if (diff1 !== 0) return diff1;
          var idA1 = (a && a.id != null) ? String(a.id) : "";
          var idB1 = (b && b.id != null) ? String(b.id) : "";
          if (idA1 !== idB1) return idA1 < idB1 ? -1 : 1;
          return itemA.idx - itemB.idx;
        } else if (sMode === "name-desc") {
          var tA2 = (a && a.title != null) ? String(a.title) : "";
          var tB2 = (b && b.title != null) ? String(b.title) : "";
          var diff2 = tB2.localeCompare(tA2, "ko", { numeric: true, sensitivity: "base" });
          if (diff2 !== 0) return diff2;
          var idA2 = (a && a.id != null) ? String(a.id) : "";
          var idB2 = (b && b.id != null) ? String(b.id) : "";
          if (idA2 !== idB2) return idA2 < idB2 ? -1 : 1;
          return itemA.idx - itemB.idx;
        }
        return itemA.idx - itemB.idx;
      });

      return list.map(function (it) {
        var copy = {};
        for (var k in it.s) {
          if (Object.prototype.hasOwnProperty.call(it.s, k)) {
            copy[k] = it.s[k];
          }
        }
        return copy;
      });
    }

    function cloneNode(p, sm) {
      if (!p) return p;
      var copy = {};
      for (var k in p) {
        if (Object.prototype.hasOwnProperty.call(p, k)) {
          copy[k] = p[k];
        }
      }
      copy.sessions = sortSessions(p.sessions, sm);
      return copy;
    }

    var normalList = [];
    var ungroupedNode = null;
    var unlinkedNode = null;

    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i];
      if (!node) continue;
      if (node.id === QA_UNGROUPED) {
        ungroupedNode = node;
      } else if (node.id === QA_UNLINKED) {
        unlinkedNode = node;
      } else {
        normalList.push({ node: node, idx: i });
      }
    }

    if (sortMode !== "desktop") {
      normalList.sort(function (itemA, itemB) {
        var a = itemA.node;
        var b = itemB.node;
        if (sortMode === "recent-desc" || sortMode === "recent-asc") {
          var isDesc = (sortMode === "recent-desc");
          var tA = projectDateKey(a);
          var tB = projectDateKey(b);
          var dDiff = compareDates(tA, tB, isDesc);
          if (dDiff !== 0) return dDiff;
          if (recordsOnly) {
            var aDiffP = compareDates(projectActivityKey(a), projectActivityKey(b), isDesc);
            if (aDiffP !== 0) return aDiffP;
          }
          var nameA = (a && a.name != null) ? String(a.name) : "";
          var nameB = (b && b.name != null) ? String(b.name) : "";
          var nDiff = nameA.localeCompare(nameB, "ko", { numeric: true, sensitivity: "base" });
          if (nDiff !== 0) return nDiff;
          var idA = (a && a.id != null) ? String(a.id) : "";
          var idB = (b && b.id != null) ? String(b.id) : "";
          if (idA !== idB) return idA < idB ? -1 : 1;
          return itemA.idx - itemB.idx;
        } else if (sortMode === "name-asc") {
          var nA1 = (a && a.name != null) ? String(a.name) : "";
          var nB1 = (b && b.name != null) ? String(b.name) : "";
          var diff1 = nA1.localeCompare(nB1, "ko", { numeric: true, sensitivity: "base" });
          if (diff1 !== 0) return diff1;
          var idA1 = (a && a.id != null) ? String(a.id) : "";
          var idB1 = (b && b.id != null) ? String(b.id) : "";
          if (idA1 !== idB1) return idA1 < idB1 ? -1 : 1;
          return itemA.idx - itemB.idx;
        } else if (sortMode === "name-desc") {
          var nA2 = (a && a.name != null) ? String(a.name) : "";
          var nB2 = (b && b.name != null) ? String(b.name) : "";
          var diff2 = nB2.localeCompare(nA2, "ko", { numeric: true, sensitivity: "base" });
          if (diff2 !== 0) return diff2;
          var idA2 = (a && a.id != null) ? String(a.id) : "";
          var idB2 = (b && b.id != null) ? String(b.id) : "";
          if (idA2 !== idB2) return idA2 < idB2 ? -1 : 1;
          return itemA.idx - itemB.idx;
        }
        return itemA.idx - itemB.idx;
      });
    }

    var result = [];
    for (var j = 0; j < normalList.length; j++) {
      result.push(cloneNode(normalList[j].node, sortMode));
    }
    if (ungroupedNode) {
      result.push(cloneNode(ungroupedNode, sortMode));
    }
    if (unlinkedNode) {
      result.push(cloneNode(unlinkedNode, sortMode));
    }

    return result;
  }

  function findQaNodeTitles(treeNodes, projectId, sessionId) {
    var pName = "";
    var sTitle = "";
    if (!projectId) return { projectName: "", sessionTitle: "" };
    var list = Array.isArray(treeNodes) ? treeNodes : [];
    for (var i = 0; i < list.length; i++) {
      var p = list[i];
      if (p && p.id === projectId) {
        pName = p.name;
        if (sessionId && Array.isArray(p.sessions)) {
          for (var j = 0; j < p.sessions.length; j++) {
            if (p.sessions[j] && p.sessions[j].id === sessionId) {
              sTitle = p.sessions[j].title;
              break;
            }
          }
        }
        break;
      }
    }
    return {
      projectName: pName || projectId,
      sessionTitle: sTitle || sessionId
    };
  }

  function handoffMsgFileOf(msg, channelData) {
    if (!msg || msg.num == null || !channelData || !Array.isArray(channelData.files)) {
      return "";
    }
    var prefix = String(msg.num) + "-";
    for (var i = 0; i < channelData.files.length; i++) {
      var f = channelData.files[i];
      if (typeof f === "string" && f.indexOf(prefix) === 0) {
        return f;
      }
    }
    return "";
  }

  function handoffNodeOf(channelName, msg, channelData, tree) {
    var file = handoffMsgFileOf(msg, channelData);
    var link = (tree && tree.handoffLinks && file && tree.handoffLinks[file]) ? tree.handoffLinks[file] : null;
    if (link) {
      if (tree && Array.isArray(tree.projects)) {
        for (var i = 0; i < tree.projects.length; i++) {
          var p = tree.projects[i];
          if (p && Array.isArray(p.sessions)) {
            for (var j = 0; j < p.sessions.length; j++) {
              var s = p.sessions[j];
              if (s && s.id === link) {
                return {
                  projectId: p.id,
                  projectName: p.name,
                  sessionId: link,
                  sessionTitle: s.title ? s.title : link.slice(0, 8)
                };
              }
            }
          }
        }
      }
      if (tree && Array.isArray(tree.ungrouped)) {
        for (var k = 0; k < tree.ungrouped.length; k++) {
          var us = tree.ungrouped[k];
          if (us && us.id === link) {
            return {
              projectId: QA_UNGROUPED,
              projectName: "그룹 없음",
              sessionId: link,
              sessionTitle: us.title ? us.title : link.slice(0, 8)
            };
          }
        }
      }
    }
    var cName = (channelName != null && String(channelName).trim() !== "") ? String(channelName) : "";
    return {
      projectId: QA_UNLINKED,
      projectName: "연결 안 됨",
      sessionId: "c:" + cName,
      sessionTitle: cName
    };
  }

  function buildHandoffTree(channels, tree) {
    var projectList = [];
    var sessionLookup = {};

    if (tree && Array.isArray(tree.projects)) {
      for (var i = 0; i < tree.projects.length; i++) {
        var p = tree.projects[i];
        if (!p) continue;
        var pNode = {
          id: p.id,
          name: p.name || "",
          total: 0,
          waiting: 0,
          latestTime: "",
          sessions: []
        };
        if (Array.isArray(p.sessions)) {
          for (var j = 0; j < p.sessions.length; j++) {
            var s = p.sessions[j];
            if (!s) continue;
            var sNode = {
              id: s.id,
              title: s.title ? s.title : String(s.id || "").slice(0, 8),
              cwd: s.cwd || "",
              total: 0,
              waiting: 0,
              latestTime: "",
              archived: Boolean(s.archived),
              lastActivity: s.lastActivity || ""
            };
            pNode.sessions.push(sNode);
            sessionLookup[s.id] = sNode;
          }
        }
        projectList.push(pNode);
      }
    }

    var ungroupedNode = null;
    if (tree && Array.isArray(tree.ungrouped) && tree.ungrouped.length > 0) {
      ungroupedNode = {
        id: QA_UNGROUPED,
        name: "그룹 없음",
        total: 0,
        waiting: 0,
        latestTime: "",
        sessions: []
      };
      for (var u = 0; u < tree.ungrouped.length; u++) {
        var us = tree.ungrouped[u];
        if (!us) continue;
        var usNode = {
          id: us.id,
          title: us.title ? us.title : String(us.id || "").slice(0, 8),
          cwd: us.cwd || "",
          total: 0,
          waiting: 0,
          latestTime: "",
          archived: Boolean(us.archived),
          lastActivity: us.lastActivity || ""
        };
        ungroupedNode.sessions.push(usNode);
        sessionLookup[us.id] = usNode;
      }
    }

    var unlinkedNode = {
      id: QA_UNLINKED,
      name: "연결 안 됨",
      total: 0,
      waiting: 0,
      latestTime: "",
      sessions: []
    };
    var unlinkedSessionMap = {};

    if (channels && typeof channels === "object") {
      var channelNames = Object.keys(channels);
      for (var cI = 0; cI < channelNames.length; cI++) {
        var cName = channelNames[cI];
        var cData = channels[cName];
        if (!cData || !Array.isArray(cData.messages)) continue;

        for (var mI = 0; mI < cData.messages.length; mI++) {
          var msg = cData.messages[mI];
          if (!msg || typeof msg !== "object") continue;

          var nodeInfo = handoffNodeOf(cName, msg, cData, tree);
          var time = msg.time || "";
          var isWaiting = (msg.status === "보냄" || msg.status === "읽음");

          var targetSession = null;
          if (nodeInfo.projectId === QA_UNLINKED) {
            targetSession = unlinkedSessionMap[nodeInfo.sessionId];
            if (!targetSession) {
              targetSession = {
                id: nodeInfo.sessionId,
                title: nodeInfo.sessionTitle,
                cwd: "",
                total: 0,
                waiting: 0,
                latestTime: "",
                archived: false,
                lastActivity: ""
              };
              unlinkedSessionMap[nodeInfo.sessionId] = targetSession;
              unlinkedNode.sessions.push(targetSession);
            }
          } else {
            targetSession = sessionLookup[nodeInfo.sessionId];
          }

          if (targetSession) {
            targetSession.total++;
            if (isWaiting) {
              targetSession.waiting++;
            }
            if (time && (!targetSession.latestTime || time > targetSession.latestTime)) {
              targetSession.latestTime = time;
            }
          }
        }
      }
    }

    function finalizeProject(p) {
      var validSessions = [];
      for (var i = 0; i < p.sessions.length; i++) {
        var s = p.sessions[i];
        if (s.archived && s.total === 0) {
          continue;
        }
        validSessions.push(s);
      }

      validSessions.sort(function (a, b) {
        var aTime = a.latestTime || "";
        if (a.lastActivity && (!aTime || a.lastActivity > aTime)) {
          aTime = a.lastActivity;
        }
        var bTime = b.latestTime || "";
        if (b.lastActivity && (!bTime || b.lastActivity > bTime)) {
          bTime = b.lastActivity;
        }
        if (bTime !== aTime) {
          return bTime > aTime ? 1 : -1;
        }
        return (a.title || "").localeCompare(b.title || "");
      });

      var pTotal = 0;
      var pWaiting = 0;
      var pLatest = "";

      for (var j = 0; j < validSessions.length; j++) {
        var vs = validSessions[j];
        pTotal += vs.total;
        pWaiting += vs.waiting;
        if (vs.latestTime && (!pLatest || vs.latestTime > pLatest)) {
          pLatest = vs.latestTime;
        }
      }

      p.sessions = validSessions;
      p.total = pTotal;
      p.waiting = pWaiting;
      p.latestTime = pLatest;
    }

    var result = [];

    for (var pIdx = 0; pIdx < projectList.length; pIdx++) {
      finalizeProject(projectList[pIdx]);
      result.push(projectList[pIdx]);
    }

    if (ungroupedNode) {
      finalizeProject(ungroupedNode);
      if (ungroupedNode.sessions.length > 0) {
        result.push(ungroupedNode);
      }
    }

    finalizeProject(unlinkedNode);
    if (unlinkedNode.sessions.length > 0 && unlinkedNode.total > 0) {
      result.push(unlinkedNode);
    }

    return result;
  }

  function handoffFilterTree(nodes, query) {
    if (!Array.isArray(nodes)) return [];
    var q = (query == null ? "" : String(query)).trim().toLowerCase();
    if (!q) {
      return nodes.slice();
    }
    var result = [];
    for (var i = 0; i < nodes.length; i++) {
      var p = nodes[i];
      if (!p) continue;
      var pName = (p.name || "").toLowerCase();
      if (pName.indexOf(q) !== -1) {
        result.push({
          id: p.id,
          name: p.name,
          total: p.total,
          waiting: p.waiting,
          latestTime: p.latestTime,
          sessions: Array.isArray(p.sessions) ? p.sessions.slice() : []
        });
      } else {
        var matchingSessions = [];
        if (Array.isArray(p.sessions)) {
          for (var j = 0; j < p.sessions.length; j++) {
            var s = p.sessions[j];
            if (s && (s.title || "").toLowerCase().indexOf(q) !== -1) {
              matchingSessions.push(s);
            }
          }
        }
        if (matchingSessions.length > 0) {
          result.push({
            id: p.id,
            name: p.name,
            total: p.total,
            waiting: p.waiting,
            latestTime: p.latestTime,
            sessions: matchingSessions
          });
        }
      }
    }
    return result;
  }

  function handoffMessagesOf(channels, tree, projectId, sessionId) {
    if (!channels || typeof channels !== "object") return [];

    var list = [];
    var channelMap = {};
    var channelCount = 0;

    var cNames = Object.keys(channels);
    for (var i = 0; i < cNames.length; i++) {
      var cName = cNames[i];
      var cData = channels[cName];
      if (!cData || !Array.isArray(cData.messages)) continue;

      for (var j = 0; j < cData.messages.length; j++) {
        var msg = cData.messages[j];
        if (!msg) continue;
        var node = handoffNodeOf(cName, msg, cData, tree);
        if (projectId && node.projectId !== projectId) continue;
        if (sessionId && node.sessionId !== sessionId) continue;

        var file = handoffMsgFileOf(msg, cData);
        if (!channelMap[cName]) {
          channelMap[cName] = true;
          channelCount++;
        }
        list.push({
          msg: msg,
          channel: cName,
          file: file,
          _seq: list.length
        });
      }
    }

    if (channelCount > 1) {
      list.sort(function (a, b) {
        var tA = (a.msg && a.msg.time) || "";
        var tB = (b.msg && b.msg.time) || "";
        if (tA !== tB) {
          return tA > tB ? 1 : -1;
        }
        return a._seq - b._seq;
      });
    }

    return list.map(function (it) {
      return {
        msg: it.msg,
        channel: it.channel,
        file: it.file
      };
    });
  }

  function findHandoffNodeTitles(treeNodes, projectId, sessionId) {
    var pName = "";
    var sTitle = "";
    if (!projectId) return { projectName: "", sessionTitle: "" };
    var list = Array.isArray(treeNodes) ? treeNodes : [];
    for (var i = 0; i < list.length; i++) {
      var p = list[i];
      if (p && p.id === projectId) {
        pName = p.name;
        if (sessionId && Array.isArray(p.sessions)) {
          for (var j = 0; j < p.sessions.length; j++) {
            if (p.sessions[j] && p.sessions[j].id === sessionId) {
              sTitle = p.sessions[j].title;
              break;
            }
          }
        }
        break;
      }
    }
    return {
      projectName: pName || projectId,
      sessionTitle: sTitle || sessionId
    };
  }

  function getQaTreeSortMode() {
    try {
      return normalizeTreeSortMode(localStorage.getItem("samjil.treeSort.qa.v1"));
    } catch (e) {
      return TREE_SORT_DEFAULT;
    }
  }

  function setQaTreeSortMode(mode) {
    try {
      localStorage.setItem("samjil.treeSort.qa.v1", normalizeTreeSortMode(mode));
    } catch (e) {}
  }

  function getHandoffTreeSortMode() {
    try {
      return normalizeTreeSortMode(localStorage.getItem("samjil.treeSort.handoff.v1"));
    } catch (e) {
      return TREE_SORT_DEFAULT;
    }
  }

  function setHandoffTreeSortMode(mode) {
    try {
      localStorage.setItem("samjil.treeSort.handoff.v1", normalizeTreeSortMode(mode));
    } catch (e) {}
  }

  // 사이드바 행(프로젝트·세션)에는 시각을 두 개 보인다.
  //   세션: Claude Desktop 세션의 마지막 활동. 프로젝트 행은 그 안의 세션들 중 가장 최근 활동.
  //   위임(위임 실행 기록) / 인수인계(에이전트 인수인계): agy 쪽 기록의 시각.
  function treeSessionTime(node) {
    if (!node) return "";
    if (node.lastActivity) return String(node.lastActivity);
    var best = "";
    var list = Array.isArray(node.sessions) ? node.sessions : [];
    for (var i = 0; i < list.length; i++) {
      var t = String(list[i].lastActivity || "");
      if (t > best) { best = t; }
    }
    return best;
  }

  // 위임 쪽 값: 마지막으로 끝난 agy 작업의 완료 시각. 끝난 것이 없으면 진행 중인지, 위임이 아예 없는지 보인다.
  function qaDelegationValue(node) {
    if (node && node.latestDone) return formatRelativeTime(node.latestDone);
    if (node && node.pending > 0) return "진행 중";
    return "없음";
  }

  // 시각 두 개를 한 줄에 보인다: "세션 시각 / agy 쪽 시각". 색으로 구분한다 - 세션은 Claude 색, 위임·인수인계는 agy 색.
  // 사이드바 위의 범례와, 각 시각에 마우스를 올릴 때 뜨는 설명(이름 + 정확한 날짜·시각)이 뜻을 알려 준다.
  function treeTimePairHtml(cls, sessNode, agyLabel, agyText, agyAbs, extraHtml) {
    var st = treeSessionTime(sessNode);
    var sText = st ? formatRelativeTime(st) : "-";
    var sTitle = "세션 " + (st || "정보 없음");
    var aTitle = agyLabel + " " + (agyAbs || agyText);
    return '<span class="' + cls + ' tree-times">' +
      '<span class="tt tt-session' + (st ? "" : " is-empty") + '" title="' + escapeHtml(sTitle) + '">' + escapeHtml(sText) + '</span>' +
      '<span class="tt-sep">/</span>' +
      '<span class="tt tt-agy' + (agyAbs ? "" : " is-empty") + '" title="' + escapeHtml(aTitle) + '">' + escapeHtml(agyText) + '</span>' +
      (extraHtml || "") + '</span>';
  }

  // 위임 실행 기록 화면의 날짜 정렬은 agy 작업(위임 기록) 시각 기준이라 라벨도 그렇게 보인다
  function qaSortLabel(m) {
    if (m.value === "recent-desc") return "agy 최근 작업순";
    if (m.value === "recent-asc") return "agy 오래된 작업순";
    return m.label;
  }

  function initTreeSortSelects() {
    if (els.qaTreeSort) {
      els.qaTreeSort.innerHTML = "";
      TREE_SORT_MODES.forEach(function (m) {
        var opt = document.createElement("option");
        opt.value = m.value;
        opt.textContent = qaSortLabel(m);
        els.qaTreeSort.appendChild(opt);
      });
      els.qaTreeSort.value = getQaTreeSortMode();
      els.qaTreeSort.addEventListener("change", function () {
        setQaTreeSortMode(this.value);
        renderQaTree();
      });
    }
    if (els.handoffTreeSort) {
      els.handoffTreeSort.innerHTML = "";
      TREE_SORT_MODES.forEach(function (m) {
        var opt = document.createElement("option");
        opt.value = m.value;
        opt.textContent = m.label;
        els.handoffTreeSort.appendChild(opt);
      });
      els.handoffTreeSort.value = getHandoffTreeSortMode();
      els.handoffTreeSort.addEventListener("change", function () {
        setHandoffTreeSortMode(this.value);
        renderHandoffTree();
      });
    }
  }

  var QA_TREE_OPEN_KEY = "samjil.qaTreeOpen.v1";

  function getQaTreeOpenMap() {
    try {
      var raw = localStorage.getItem(QA_TREE_OPEN_KEY);
      if (raw) {
        var parsed = JSON.parse(raw);
        if (parsed && typeof parsed === "object") return parsed;
      }
    } catch (e) {}
    return {};
  }

  function setQaTreeOpen(projectId, isOpen) {
    if (!projectId) return;
    try {
      var map = getQaTreeOpenMap();
      map[projectId] = Boolean(isOpen);
      localStorage.setItem(QA_TREE_OPEN_KEY, JSON.stringify(map));
    } catch (e) {}
  }

  function isQaProjectOpen(projectId, hasSearchQuery) {
    if (hasSearchQuery) return true;
    var map = getQaTreeOpenMap();
    if (Object.prototype.hasOwnProperty.call(map, projectId)) {
      return Boolean(map[projectId]);
    }
    if (currentQaProject === projectId) return true;
    return false;
  }

  function renderQaTree() {
    if (!els.qaSessionList) return;

    var allNodes = buildQaTree(allItems, pendingItems, claudeTree);
    if (els.qaSessionCount) {
      els.qaSessionCount.textContent = allNodes.length;
    }

    var q = (els.qaSessionSearch && els.qaSessionSearch.value || "").trim().toLowerCase();
    var filtered = qaFilterTree(allNodes, q);
    var sorted = sortTreeNodes(filtered, getQaTreeSortMode(), { dateSource: "records" });
    var hasQuery = Boolean(q);

    var frag = document.createDocumentFragment();

    // 1. [전체 프로젝트 피드] 항목
    var allItem = document.createElement("div");
    var isFeedActive = (currentQaProject === "" && currentQaSession === "");
    allItem.className = "project-item" + (isFeedActive ? " active" : "");
    allItem.dataset.project = "";
    allItem.innerHTML = [
      '<span class="project-icon">' + icon("feed") + '</span>',
      '<div class="project-info">',
      '  <span class="project-name">전체 프로젝트 피드</span>',
      '  <span class="project-sub session-sub">모든 위임을 시간순으로</span>',
      '</div>',
      '<span class="project-badge">' + (allItems.length + pendingItems.length) + '</span>'
    ].join("");
    makeActivatable(allItem);
    allItem.onclick = function () { selectQaProject(""); };
    frag.appendChild(allItem);

    // 2. 프로젝트 트리 목록
    sorted.forEach(function (p) {
      var isOpen = isQaProjectOpen(p.id, hasQuery);
      var isProjectActive = (currentQaProject === p.id && currentQaSession === "");

      var pItem = document.createElement("div");
      var pClass = "project-item tree-project" + (isProjectActive ? " active" : "") + (isOpen ? " open" : "");
      pItem.className = pClass;
      pItem.dataset.project = p.id;
      pItem.setAttribute("role", "treeitem");
      pItem.setAttribute("aria-expanded", isOpen ? "true" : "false");

      var sessCount = p.sessions ? p.sessions.length : 0;
      // 시각 두 줄: 세션(Desktop 세션의 마지막 활동, 세션 개수 포함) / 위임(agy 작업의 완료 시각)
      var subHtml = treeTimePairHtml("project-sub session-sub", p, "위임", qaDelegationValue(p), p.latestDone, '<span class="tree-time-count">' + sessCount + '개</span>');

      var badgeHtml = '<span class="project-badge">' + (p.total + p.pending) + '</span>';
      if (p.pending > 0) {
        badgeHtml = '<span class="pending-pulse-dot" title="진행/대기 중 ' + p.pending + '건"></span> ' + badgeHtml;
      }

      pItem.innerHTML = [
        '<span class="tree-chevron" aria-hidden="true"></span>',
        '<span class="project-icon">' + icon("folder") + '</span>',
        '<div class="project-info">',
        '  <span class="project-name" title="' + escapeHtml(p.name) + '">' + escapeHtml(p.name) + '</span>',
        '  ' + subHtml,
        '</div>',
        badgeHtml
      ].join("");

      makeActivatable(pItem);

      var chevron = pItem.querySelector(".tree-chevron");
      if (chevron) {
        chevron.onclick = function (e) {
          e.stopPropagation();
          var nextState = !isOpen;
          setQaTreeOpen(p.id, nextState);
          renderQaTree();
        };
      }

      pItem.onclick = function () {
        // 스마트 토글: 이미 이 프로젝트의 전체 목록이 활성화된 상태에서 다시 누를 때만 접기/펼치기 토글
        // 하위 세션이 선택되어 있거나 다른 프로젝트에서 진입 시에는 항상 목록을 펼친 상태(open)로 유지
        var isAlreadyProjectActive = (currentQaProject === p.id && !currentQaSession);
        var nextOpen = isAlreadyProjectActive ? !isOpen : true;
        currentQaProject = p.id;
        currentQaSession = "";
        setQaTreeOpen(p.id, nextOpen);
        renderQaTree();
        updateBreadcrumbs();
        updateHash();
        applyQaFilters();
      };

      frag.appendChild(pItem);

      // 세션 목록
      if (isOpen && p.sessions && p.sessions.length > 0) {
        var groupDiv = document.createElement("div");
        groupDiv.className = "tree-children";
        groupDiv.setAttribute("role", "group");

        p.sessions.forEach(function (s) {
          var isSessionActive = (currentQaProject === p.id && currentQaSession === s.id);
          var sItem = document.createElement("div");
          sItem.className = "session-item tree-session" + (isSessionActive ? " active" : "");
          sItem.dataset.session = s.id;
          sItem.setAttribute("role", "treeitem");

          var sSubHtml = treeTimePairHtml("session-sub", s, "위임", qaDelegationValue(s), s.latestDone, "");

          var sBadgeHtml = '<span class="session-badge">' + (s.total + s.pending) + '</span>';
          if (s.pending > 0) {
            sBadgeHtml = '<span class="pending-pulse-dot" title="진행/대기 중 ' + s.pending + '건"></span> ' + sBadgeHtml;
          }

          var archivedHtml = s.archived ? '<span class="tree-archived">(보관됨)</span>' : '';

          sItem.innerHTML = [
            '<span class="session-icon">' + icon("thread") + '</span>',
            '<div class="session-info">',
            '  <span class="session-name" title="' + escapeHtml(s.title) + '">' + escapeHtml(s.title) + archivedHtml + '</span>',
            '  ' + sSubHtml,
            '</div>',
            sBadgeHtml
          ].join("");

          makeActivatable(sItem);
          sItem.onclick = function () {
            selectQaSession(s.id, p.id);
          };

          groupDiv.appendChild(sItem);
        });

        frag.appendChild(groupDiv);
      }
    });

    var prevScroll = els.qaSessionList.scrollTop;
    els.qaSessionList.innerHTML = "";
    els.qaSessionList.appendChild(frag);
    els.qaSessionList.scrollTop = prevScroll;
  }

  function selectQaAgy(agy) {
    currentQaAgy = agy || "";
    renderQaAgyChips();
    updateHash();
    applyQaFilters();
  }

  function selectQaProject(id, forceOpen) {
    currentQaAgy = "";
    currentQaProject = id || "";
    currentQaSession = "";
    if (currentQaProject && forceOpen !== false) {
      setQaTreeOpen(currentQaProject, true);
    }
    renderQaTree();
    updateBreadcrumbs();
    updateHash();
    applyQaFilters();
  }

  function selectQaSession(sessionId, projectId) {
    currentQaAgy = "";
    currentQaSession = sessionId || "";
    if (projectId !== undefined) {
      currentQaProject = projectId || "";
    } else {
      if (sessionId) {
        var tree = buildQaTree(allItems, pendingItems, claudeTree);
        var foundProject = null;
        for (var i = 0; i < tree.length; i++) {
          var p = tree[i];
          if (p && p.sessions) {
            for (var j = 0; j < p.sessions.length; j++) {
              if (p.sessions[j] && p.sessions[j].id === sessionId) {
                foundProject = p.id;
                break;
              }
            }
          }
          if (foundProject !== null) break;
        }
        if (foundProject !== null) {
          currentQaProject = foundProject;
        } else {
          currentQaSession = "";
          currentQaProject = "";
        }
      } else {
        currentQaProject = "";
      }
    }
    if (currentQaProject) {
      setQaTreeOpen(currentQaProject, true);
    }
    renderQaTree();
    updateBreadcrumbs();
    updateHash();
    applyQaFilters();
  }

  function findRepresentativeItemBySessionName(sName) {
    var pends = Array.isArray(pendingItems) ? pendingItems : [];
    for (var i = 0; i < pends.length; i++) {
      var p = pends[i];
      var s = (p && p.session != null && String(p.session).trim() !== "") ? String(p.session) : "__none__";
      if (s === sName) return p;
    }
    var recs = Array.isArray(allItems) ? allItems : [];
    for (var j = 0; j < recs.length; j++) {
      var r = recs[j];
      var s2 = (r && r.session != null && String(r.session).trim() !== "") ? String(r.session) : "__none__";
      if (s2 === sName) return r;
    }
    return null;
  }

  // ==========================================================================
  // Handoff Tree & Selection Management
  // ==========================================================================

  var HANDOFF_TREE_OPEN_KEY = "samjil.handoffTreeOpen.v1";

  function getHandoffTreeOpenMap() {
    try {
      var raw = localStorage.getItem(HANDOFF_TREE_OPEN_KEY);
      if (raw) {
        var parsed = JSON.parse(raw);
        if (parsed && typeof parsed === "object") return parsed;
      }
    } catch (e) {}
    return {};
  }

  function setHandoffTreeOpen(projectId, isOpen) {
    if (!projectId) return;
    try {
      var map = getHandoffTreeOpenMap();
      map[projectId] = Boolean(isOpen);
      localStorage.setItem(HANDOFF_TREE_OPEN_KEY, JSON.stringify(map));
    } catch (e) {}
  }

  function isHandoffProjectOpen(projectId, hasSearchQuery) {
    if (hasSearchQuery) return true;
    var map = getHandoffTreeOpenMap();
    if (Object.prototype.hasOwnProperty.call(map, projectId)) {
      return Boolean(map[projectId]);
    }
    if (currentHandoffProject === projectId) return true;
    return false;
  }

  function renderHandoffTree() {
    if (!els.handoffProjectList) return;

    var allNodes = buildHandoffTree(handoffChannels, claudeTree);
    if (els.handoffProjectCount) {
      els.handoffProjectCount.textContent = allNodes.length;
    }

    var q = (els.handoffProjectSearch && els.handoffProjectSearch.value || "").trim().toLowerCase();
    var filtered = handoffFilterTree(allNodes, q);
    var sorted = sortTreeNodes(filtered, getHandoffTreeSortMode());
    var hasQuery = Boolean(q);

    // 전체 메시지 수 계산
    var totalAllMsgs = 0;
    if (handoffChannels && typeof handoffChannels === "object") {
      for (var cKey in handoffChannels) {
        var cVal = handoffChannels[cKey];
        if (cVal && Array.isArray(cVal.messages)) {
          totalAllMsgs += cVal.messages.length;
        }
      }
    }

    var frag = document.createDocumentFragment();

    // 1. [전체 프로젝트] 항목
    var allItem = document.createElement("div");
    var isFeedActive = (currentHandoffProject === "" && currentHandoffSession === "");
    allItem.className = "project-item" + (isFeedActive ? " active" : "");
    allItem.dataset.project = "";
    allItem.innerHTML = [
      '<span class="project-icon">' + icon("feed") + '</span>',
      '<div class="project-info">',
      '  <span class="project-name">전체 프로젝트</span>',
      '  <span class="project-sub session-sub">모든 인수인계를 시간순으로</span>',
      '</div>',
      '<span class="project-badge">' + totalAllMsgs + '</span>'
    ].join("");
    makeActivatable(allItem);
    allItem.onclick = function () { selectHandoffProject(""); };
    frag.appendChild(allItem);

    // 2. 프로젝트 트리 목록
    sorted.forEach(function (p) {
      var isOpen = isHandoffProjectOpen(p.id, hasQuery);
      var isProjectActive = (currentHandoffProject === p.id && currentHandoffSession === "");

      var pItem = document.createElement("div");
      var pClass = "project-item tree-project" + (isProjectActive ? " active" : "") + (isOpen ? " open" : "");
      pItem.className = pClass;
      pItem.dataset.project = p.id;
      pItem.setAttribute("role", "treeitem");
      pItem.setAttribute("aria-expanded", isOpen ? "true" : "false");

      var sessCount = p.sessions ? p.sessions.length : 0;
      var waitHtml = p.waiting > 0 ? '<span class="tree-time-count who-agy">대기 중 ' + p.waiting + '</span>' : '';
      // 시각 두 줄: 세션(Desktop 세션의 마지막 활동, 세션 개수 포함) / 인수인계(마지막 메시지 시각)
      var subHtml = treeTimePairHtml("project-sub session-sub", p, "인수인계", p.latestTime ? formatRelativeTime(p.latestTime) : "없음", p.latestTime, '<span class="tree-time-count">' + sessCount + '개</span>' + waitHtml);

      var badgeHtml = '<span class="project-badge">' + p.total + '</span>';
      if (p.waiting > 0) {
        badgeHtml = '<span class="pending-pulse-dot" title="대기 중 ' + p.waiting + '건"></span> ' + badgeHtml;
      }

      pItem.innerHTML = [
        '<span class="tree-chevron" aria-hidden="true"></span>',
        '<span class="project-icon">' + icon("folder") + '</span>',
        '<div class="project-info">',
        '  <span class="project-name" title="' + escapeHtml(p.name) + '">' + escapeHtml(p.name) + '</span>',
        '  ' + subHtml,
        '</div>',
        badgeHtml
      ].join("");

      makeActivatable(pItem);

      var chevron = pItem.querySelector(".tree-chevron");
      if (chevron) {
        chevron.onclick = function (e) {
          e.stopPropagation();
          var nextState = !isOpen;
          setHandoffTreeOpen(p.id, nextState);
          renderHandoffTree();
        };
      }

      pItem.onclick = function () {
        // 스마트 토글: 이미 이 프로젝트의 전체 목록이 활성화된 상태에서 다시 누를 때만 접기/펼치기 토글
        // 하위 세션이 선택되어 있거나 다른 프로젝트에서 진입 시에는 항상 목록을 펼친 상태(open)로 유지
        var isAlreadyProjectActive = (currentHandoffProject === p.id && !currentHandoffSession);
        var nextOpen = isAlreadyProjectActive ? !isOpen : true;
        currentHandoffProject = p.id;
        currentHandoffSession = "";
        setHandoffTreeOpen(p.id, nextOpen);
        renderHandoffTree();
        updateBreadcrumbs();
        updateHash();
        renderHandoffView();
      };

      frag.appendChild(pItem);

      // 세션 목록
      if (isOpen && p.sessions && p.sessions.length > 0) {
        var groupDiv = document.createElement("div");
        groupDiv.className = "tree-children";
        groupDiv.setAttribute("role", "group");

        p.sessions.forEach(function (s) {
          var isSessionActive = (currentHandoffProject === p.id && currentHandoffSession === s.id);
          var sItem = document.createElement("div");
          sItem.className = "session-item tree-session" + (isSessionActive ? " active" : "");
          sItem.dataset.session = s.id;
          sItem.setAttribute("role", "treeitem");

          var sWaitHtml = s.waiting > 0 ? '<span class="tree-time-count who-agy">대기 중 ' + s.waiting + '</span>' : '';
          var sSubHtml = treeTimePairHtml("session-sub", s, "인수인계", s.latestTime ? formatRelativeTime(s.latestTime) : "없음", s.latestTime, sWaitHtml);

          var sBadgeHtml = '<span class="session-badge">' + s.total + '</span>';
          if (s.waiting > 0) {
            sBadgeHtml = '<span class="pending-pulse-dot" title="대기 중 ' + s.waiting + '건"></span> ' + sBadgeHtml;
          }

          var archivedHtml = s.archived ? '<span class="tree-archived">(보관됨)</span>' : '';

          sItem.innerHTML = [
            '<span class="session-icon">' + icon("thread") + '</span>',
            '<div class="session-info">',
            '  <span class="session-name" title="' + escapeHtml(s.title) + '">' + escapeHtml(s.title) + archivedHtml + '</span>',
            '  ' + sSubHtml,
            '</div>',
            sBadgeHtml
          ].join("");

          makeActivatable(sItem);
          sItem.onclick = function () {
            selectHandoffSession(s.id, p.id);
          };

          groupDiv.appendChild(sItem);
        });

        frag.appendChild(groupDiv);
      }
    });

    var prevScroll = els.handoffProjectList.scrollTop;
    els.handoffProjectList.innerHTML = "";
    els.handoffProjectList.appendChild(frag);
    els.handoffProjectList.scrollTop = prevScroll;
  }

  function selectHandoffProject(id, forceOpen) {
    if (id && handoffChannels && handoffChannels[id]) {
      var tree = buildHandoffTree(handoffChannels, claudeTree);
      var isRealProject = false;
      for (var pi = 0; pi < tree.length; pi++) {
        if (tree[pi] && tree[pi].id === id) {
          isRealProject = true;
          break;
        }
      }
      if (!isRealProject) {
        selectHandoffSession("c:" + id, QA_UNLINKED);
        return;
      }
    }
    currentHandoffProject = id || "";
    currentHandoffSession = "";
    if (currentHandoffProject && forceOpen !== false) {
      setHandoffTreeOpen(currentHandoffProject, true);
    }
    renderHandoffTree();
    updateBreadcrumbs();
    updateHash();
    renderHandoffView();
  }

  function selectHandoffSession(sessionId, projectId) {
    currentHandoffSession = sessionId || "";
    if (projectId !== undefined) {
      currentHandoffProject = projectId || "";
    } else {
      if (sessionId) {
        var tree = buildHandoffTree(handoffChannels, claudeTree);
        var foundProject = null;
        for (var i = 0; i < tree.length; i++) {
          var p = tree[i];
          if (p && p.sessions) {
            for (var j = 0; j < p.sessions.length; j++) {
              if (p.sessions[j] && p.sessions[j].id === sessionId) {
                foundProject = p.id;
                break;
              }
            }
          }
          if (foundProject !== null) break;
        }
        if (foundProject !== null) {
          currentHandoffProject = foundProject;
        } else {
          currentHandoffSession = "";
          currentHandoffProject = "";
        }
      } else {
        currentHandoffProject = "";
      }
    }
    if (currentHandoffProject) {
      setHandoffTreeOpen(currentHandoffProject, true);
    }
    renderHandoffTree();
    updateBreadcrumbs();
    updateHash();
    renderHandoffView();
  }

  // ==========================================================================
  // 1. 대시보드 뷰 렌더링: 지금 / 확인 필요 / 최근 활동 / 누적
  // ==========================================================================

  var STATUS_STEPS = { "보냄": 1, "읽음": 2, "처리됨": 3, "확인함": 4 };

  function renderDashboard() {
    if (currentNav !== "dashboard") return;
    renderNow();
    renderAttention();
    renderTimeline();
    renderStats();
    renderQuickSessions();
  }

  // 아직 완료 기록이 없는 inbox 작업만 남기고, 그중 processing 상태인 한 건을 고른다.
  function activePending() {
    var finished = {};
    allItems.forEach(function (r) { if (r && r.task_id) { finished[r.task_id] = true; } });
    return pendingItems.filter(function (p) { return p && p.task_id && !finished[p.task_id]; });
  }

  // 진행 중인 위임 카드의 경과 시간을 1초마다 갱신한다. 카드는 새로고침 때 다시 그려지므로 DOM을 매번 훑는다.
  setInterval(function () {
    var els2 = document.querySelectorAll(".live-elapsed[data-start]");
    for (var i = 0; i < els2.length; i++) {
      var pfx = els2[i].getAttribute("data-label-prefix") || "";
      els2[i].textContent = pfx + formatDuration((Date.now() - Number(els2[i].getAttribute("data-start"))) / 1000);
    }
    var idles = document.querySelectorAll(".pg-idle[data-ms]");
    for (var j = 0; j < idles.length; j++) {
      var idleSec = (Date.now() - Number(idles[j].getAttribute("data-ms"))) / 1000;
      idles[j].textContent = formatDuration(idleSec) + " 전 활동";
      idles[j].classList.toggle("quiet", idleSec >= PROGRESS_QUIET_SEC);
    }
  }, 1000);

  function stopNowTicker() {
    if (nowTicker) { clearInterval(nowTicker); nowTicker = null; }
  }

  function renderNow() {
    if (!els.dashNow) return;
    stopNowTicker();

    var active = activePending();
    var running = null;
    var runningCount = 0;    // 워처가 작업을 동시에 여러 개 돌릴 수 있다
    for (var i = 0; i < active.length; i++) {
      if (active[i].state === "processing") { runningCount++; if (!running) { running = active[i]; } }
    }
    var queued = active.length - runningCount;

    var state, statusText, title;
    var aside = "";
    var meta = [];
    var clickItem = null;

    if (!isServerOnline) {
      state = "offline";
      statusText = "뷰어 서버에 연결할 수 없습니다";
      title = "serve-viewer.ps1이 실행 중인지 확인하세요";
      meta.push('<span><code>~/.samjil/viewer/serve-viewer.ps1</code>을 다시 실행하면 이 화면이 이어서 갱신됩니다.</span>');
    } else if (running) {
      state = "running";
      statusText = runningCount > 1 ? "agy가 " + runningCount + "건을 동시에 작업 중" : "agy가 작업 중";
      if (queued > 0) { aside = "대기 " + queued + "건"; }
      title = extractQuestionKeyword(running.question) || "(질문 내용 없음)";
      if (running.model) { meta.push('<span>모델 <code>' + escapeHtml(running.model) + '</code></span>'); }
      meta.push('<span>' + (running.session ? "세션 " + escapeHtml(running.session) : "단발성 작업") + '</span>');
      var created = parseLocalTime(running.created);
      if (created) {
        meta.push('<span>접수 후 <span class="elapsed" id="now-elapsed">' +
          formatDuration((Date.now() - created.getTime()) / 1000) + '</span></span>');
        nowTicker = setInterval(function () {
          var el = document.getElementById("now-elapsed");
          if (!el) { stopNowTicker(); return; }
          el.textContent = formatDuration((Date.now() - created.getTime()) / 1000);
        }, 1000);
      }
      clickItem = running;
    } else if (systemStatus && systemStatus.watcherAlive) {
      state = "idle";
      statusText = "agy 워처 대기 중";
      var last = allItems[0];
      if (last) {
        title = "마지막 위임: " + (extractQuestionKeyword(last.question) || "(질문 내용 없음)");
        meta.push('<span>' + formatRelativeTime(last.timestamp) + '</span>');
        meta.push('<span>' + (isOkStatus(last) ? "성공" : (last.status ? "실패 (" + escapeHtml(last.status) + ")" : "상태 미기록")) + '</span>');
        if (recordModel(last)) { meta.push('<span><code>' + escapeHtml(recordModel(last)) + '</code></span>'); }
        clickItem = last;
      } else {
        title = "아직 위임 기록이 없습니다";
      }
    } else {
      state = "stopped";
      statusText = "agy 워처가 꺼져 있습니다";
      var autoRestart = systemStatus && systemStatus.autoRestart;
      if (systemStatus && systemStatus.manualStop) {
        title = "stop-agy로 끈 상태라 자동으로 켜지 않습니다";
        meta.push('<span><code>~/.samjil/delegate-agy/scripts/start-agy.ps1</code>로 켤 수 있습니다.</span>');
      } else if (autoRestart && autoRestart.enabled) {
        title = "다음 점검 때 뷰어가 자동으로 다시 켭니다";
        meta.push('<span>뷰어가 ' + (autoRestart.intervalSeconds >= 60 ? Math.round(autoRestart.intervalSeconds / 60) + '분' : autoRestart.intervalSeconds + '초') + '마다 점검합니다.</span>');
        meta.push('<span>지금 바로 켜려면 <code>~/.samjil/delegate-agy/scripts/start-agy.ps1</code></span>');
        if (autoRestart.lastLaunch) { meta.push('<span>마지막 자동 재시작 ' + formatRelativeTime(autoRestart.lastLaunch) + '</span>'); }
      } else {
        title = "위임하려면 워처를 먼저 켜세요";
        meta.push('<span><code>~/.samjil/delegate-agy/scripts/start-agy.ps1</code>로 켤 수 있습니다.</span>');
      }
      if (queued > 0) { meta.push('<span>inbox에서 ' + queued + '건이 처리를 기다리고 있습니다.</span>'); }
    }

    if (state !== "offline" && state !== "running" && systemStatus && systemStatus.lastHeartbeat) {
      aside = "마지막 하트비트 " + formatRelativeTime(systemStatus.lastHeartbeat);
    }

    els.dashNow.setAttribute("data-state", state);
    els.nowStatusText.textContent = statusText;
    els.nowAside.textContent = aside;
    els.nowTitle.textContent = title;
    els.nowMeta.innerHTML = meta.join("");

    els.nowTitle.classList.toggle("is-link", clickItem !== null);
    if (clickItem !== null) {
      makeActivatable(els.nowTitle);
      els.nowTitle.onclick = function () {
        var node = qaNodeOf(clickItem, claudeTree);
        selectQaSession(node.sessionId, node.projectId);
        switchNav("qa");
      };
    } else {
      els.nowTitle.removeAttribute("tabindex");
      els.nowTitle.removeAttribute("role");
      els.nowTitle.onclick = null;
    }

    renderOutcomeStrip();
  }

  // 최근 위임 결과를 한 칸에 한 건씩, 오래된 것부터 왼쪽에 놓는다.
  function renderOutcomeStrip() {
    if (!els.outcomeStrip) return;
    var recent = allItems.filter(function (r) { return r && r.status; }).slice(0, 30).reverse();
    if (recent.length === 0) {
      els.outcomeStrip.innerHTML = "";
      return;
    }
    var errs = 0;
    var html = recent.map(function (r) {
      var ok = isOkStatus(r);
      if (!ok) { errs++; }
      var tip = (r.timestamp || "") + "  " + (ok ? "성공" : "실패") + (recordModel(r) ? "  " + recordModel(r) : "");
      return '<span class="tick ' + (ok ? "ok" : "err") + '" title="' + escapeHtml(tip) + '"></span>';
    }).join("");
    var label = "최근 " + recent.length + "건 " + (errs === 0 ? "모두 성공" : "중 실패 " + errs + "건");
    els.outcomeStrip.innerHTML = html + '<span class="strip-label">' + label + '</span>';
    els.outcomeStrip.setAttribute("aria-label", label);
  }

  function stepsHtml(status) {
    var step = STATUS_STEPS[status] || 0;
    var hold = (status === "보류");
    return '<span class="steps' + (hold ? " on-hold" : "") + '" data-step="' + step + '" title="보냄 → 읽음 → 처리됨 → 확인함">' +
      '<span class="steps-track" aria-hidden="true"><i></i><i></i><i></i><i></i></span>' +
      '<span class="steps-label">' + escapeHtml(status || "상태 없음") + '</span></span>';
  }

  function dirParty(dir) {
    return dir === "c2a" ? "claude" : (dir === "a2c" ? "agy" : null);
  }

  // 모델 ID -> 사람이 읽는 이름. 모르는 모양이면 추측하지 않고 그대로 돌려준다.
  //   claude-opus-4-5-20251101 -> Claude Opus 4.5 · claude-sonnet-5-5 -> Claude Sonnet 5.5 · claude-3-5-sonnet-20241022 -> Claude 3.5 Sonnet
  //   gemini-3.8-flash-high -> Gemini 3.8 Flash (High) · "Claude Opus 5.5" 처럼 이미 사람이 쓴 이름(공백·대문자)은 그대로
  function formatModelName(raw) {
    var s = String(raw == null ? "" : raw).trim();
    if (!s) return "";
    if (/[\sA-Z]/.test(s)) return s;
    s = s.replace(/\[[^\]]*\]$/, "");
    var cap = function (w) { return w.charAt(0).toUpperCase() + w.slice(1); };
    var m = s.match(/^claude-(opus|sonnet|haiku|fable)-(\d+)(?:-(\d{1,2}))?(?:-\d{8})?$/);
    if (m) return "Claude " + cap(m[1]) + " " + m[2] + (m[3] ? "." + m[3] : "");
    m = s.match(/^claude-(\d+)(?:-(\d+))?-(opus|sonnet|haiku)(?:-\d{8})?$/);
    if (m) return "Claude " + m[1] + (m[2] ? "." + m[2] : "") + " " + cap(m[3]);
    m = s.match(/^gemini-(\d+(?:\.\d+)?)-(flash|pro|ultra|nano|lite)(?:-(low|medium|high))?$/);
    if (m) return "Gemini " + m[1] + " " + cap(m[2]) + (m[3] ? " (" + cap(m[3]) + ")" : "");
    return s;
  }

  // 메시지 목록(번호 오름차순)에서 두 쪽이 가장 최근에 쓴 모델(메시지 머리말의 `모델:` 기준). 없으면 빈 문자열.
  function handoffLatestModels(messages) {
    var out = { claude: "", agy: "" };
    var list = Array.isArray(messages) ? messages : [];
    for (var i = list.length - 1; i >= 0; i--) {
      var m = list[i];
      if (!m || !m.model) continue;
      var p = dirParty(m.dir);
      if (p && !out[p]) out[p] = m.model;
      if (out.claude && out.agy) break;
    }
    return out;
  }

  // 메시지 하나의 "보낸 쪽 → 받는 쪽" 이름.
  //   보낸 쪽: 그 메시지 머리말의 모델(없는 옛 메시지는 Claude/agy 라고만).
  //   받는 쪽: 그 메시지에 답한 메시지(답장대상이 이 번호)의 모델이 있으면 그것(실제로 받은 쪽). 아직 답이 없으면 그 쪽이 가장 최근에 쓴 모델
  //            (inferred=true 로 표시해 "추정"임을 밝힌다). 그것도 없으면 Claude/agy 라고만.
  function handoffLabelParts(m, messages) {
    var senderParty = m ? dirParty(m.dir) : null;
    if (!senderParty) return null;
    var receiverParty = senderParty === "claude" ? "agy" : "claude";
    var generic = { claude: "Claude", agy: "agy" };
    var list = Array.isArray(messages) ? messages : [];
    var full = m;
    if (m.model === undefined) {
      for (var k = 0; k < list.length; k++) { if (list[k] && String(list[k].num) === String(m.num)) { full = list[k]; break; } }
    }
    var sender = formatModelName(full.model) || generic[senderParty];
    var receiver = "";
    var inferred = false;
    for (var i = 0; i < list.length; i++) {
      var r = list[i];
      if (r && r.model && r.replyTo && String(r.replyTo) === String(m.num) && dirParty(r.dir) === receiverParty) {
        receiver = formatModelName(r.model);
        break;
      }
    }
    if (!receiver) {
      var latest = handoffLatestModels(list)[receiverParty];
      if (latest) { receiver = formatModelName(latest); inferred = true; }
    }
    if (!receiver) receiver = generic[receiverParty];
    return { senderParty: senderParty, sender: sender, receiverParty: receiverParty, receiver: receiver, inferred: inferred };
  }

  // 방향 표시: 모델명으로 "Claude Opus 5.5 → Gemini 3.8 Flash (High)". 채널 정보가 없으면 예전처럼 Claude/agy.
  function dirLabelHtml(dir, m, channelName) {
    var data = (m && channelName && handoffChannels[channelName]) ? handoffChannels[channelName] : null;
    var parts = m ? handoffLabelParts(m, data ? data.messages : null) : null;
    if (parts) {
      var tip = parts.inferred ? ' title="이 메시지에 답한 기록이 아직 없어, 그 쪽이 가장 최근에 쓴 모델로 표시했습니다"' : "";
      return '<span class="who-' + parts.senderParty + '">' + escapeHtml(parts.sender) + '</span> → <span' + tip + '>' + escapeHtml(parts.receiver) + '</span>';
    }
    if (dir === "c2a") return '<span class="who-claude">Claude</span> → agy';
    if (dir === "a2c") return '<span class="who-agy">agy</span> → Claude';
    return escapeHtml(dir || "");
  }

  function qaStatusBadge(r) {
    if (!r.status) return '<span class="badge status-unknown">상태 미기록</span>';
    return isOkStatus(r)
      ? '<span class="badge status-ok">OK</span>'
      : '<span class="badge status-err">' + escapeHtml(String(r.status)) + '</span>';
  }

  // 대시보드 한 줄 항목: [색 막대][시각][제목/부제][상태]
  function buildRow(o) {
    var li = document.createElement("li");
    var row = document.createElement("div");
    row.className = "row" + (o.party ? " from-" + o.party : "") + (o.isErr ? " is-err" : "");
    row.innerHTML = [
      '<span class="row-bar" aria-hidden="true"></span>',
      '<span class="row-when">' + escapeHtml(formatClock(o.time)) + '</span>',
      '<div class="row-main">',
      '  <div class="row-title">' + o.titleHtml + '</div>',
      '  <div class="row-sub">' + o.subHtml + '</div>',
      '</div>',
      '<div class="row-side">' + (o.sideHtml || "") + '</div>'
    ].join("");
    if (o.time) { row.title = o.time; }
    makeActivatable(row);
    row.onclick = o.onClick;
    li.appendChild(row);
    return li;
  }

  function goQaSession(arg) {
    return function () {
      if (arg && typeof arg === "object") {
        var node = qaNodeOf(arg, claudeTree);
        selectQaSession(node.sessionId, node.projectId);
      } else if (typeof arg === "string" && arg) {
        var rep = findRepresentativeItemBySessionName(arg);
        if (rep) {
          var node2 = qaNodeOf(rep, claudeTree);
          selectQaSession(node2.sessionId, node2.projectId);
        } else {
          selectQaSession(arg);
        }
      } else {
        selectQaProject("");
      }
      switchNav("qa");
    };
  }

  function goHandoffProject(name, m) {
    return function () {
      if (m && handoffChannels[name]) {
        var node = handoffNodeOf(name, m, handoffChannels[name], claudeTree);
        selectHandoffSession(node.sessionId, node.projectId);
      } else if (name && handoffChannels[name]) {
        selectHandoffSession("c:" + name, QA_UNLINKED);
      } else {
        selectHandoffProject("");
      }
      switchNav("handoff");
    };
  }

  function handoffRow(projectName, m, subPrefix) {
    var waitText = "";
    if (m.status === "보냄" || m.status === "읽음") {
      var waitParts = handoffLabelParts(m, handoffChannels[projectName] ? handoffChannels[projectName].messages : null);
      if (waitParts) waitText = '<span class="who-' + waitParts.receiverParty + '">' + escapeHtml(waitParts.receiver) + ' 처리 대기</span>';
    }
    return buildRow({
      party: dirParty(m.dir),
      time: m.time,
      titleHtml: '<span class="num">#' + escapeHtml(m.num) + '</span>' + escapeHtml(m.title || "(제목 없음)"),
      subHtml: (subPrefix ? '<span>' + subPrefix + '</span>' : "") +
        '<span>' + escapeHtml(projectName) + '</span>' +
        (waitText || '<span>' + dirLabelHtml(m.dir, m, projectName) + '</span>'),
      sideHtml: stepsHtml(m.status),
      onClick: goHandoffProject(projectName, m)
    });
  }

  function renderAttention() {
    if (!els.dashAttention) return;
    var items = [];

    handoffProjects.forEach(function (p) {
      var m = p.latestMsg;
      if (m && (m.status === "보냄" || m.status === "읽음")) {
        items.push({ time: m.time || p.updated || "", node: function () { return handoffRow(p.name, m); } });
      }
    });

    var dayAgo = Date.now() - 86400000;
    allItems.forEach(function (r) {
      if (!r || !r.status || isOkStatus(r)) return;
      var d = parseLocalTime(r.timestamp);
      if (!d || d.getTime() < dayAgo) return;
      items.push({
        time: r.timestamp,
        node: function () {
          return buildRow({
            isErr: true,
            time: r.timestamp,
            titleHtml: escapeHtml(extractQuestionKeyword(r.question) || "(질문 내용 없음)"),
            subHtml: '<span>위임 실패</span>' +
              (recordModel(r) ? '<span>' + escapeHtml(recordModel(r)) + '</span>' : "") +
              '<span>' + escapeHtml(r.session || "단발성") + '</span>',
            sideHtml: qaStatusBadge(r),
            onClick: goQaSession(r)
          });
        }
      });
    });

    items.sort(function (a, b) { return String(b.time).localeCompare(String(a.time)); });

    if (els.dashAttentionCount) {
      els.dashAttentionCount.textContent = items.length > 0 ? items.length + "건" : "";
    }

    els.dashAttention.innerHTML = "";
    if (items.length === 0) {
      els.dashAttention.innerHTML = '<li class="row-empty">확인할 항목이 없습니다. 처리를 기다리는 인수인계 메시지나 최근 24시간 안에 실패한 위임이 생기면 여기에 나옵니다.</li>';
      return;
    }
    var frag = document.createDocumentFragment();
    items.forEach(function (it) { frag.appendChild(it.node()); });
    els.dashAttention.appendChild(frag);
  }

  function renderTimeline() {
    if (!els.dashTimeline) return;
    var entries = [];

    activePending().forEach(function (p) {
      entries.push({
        time: p.created || "",
        node: function () {
          var processing = (p.state === "processing");
          return buildRow({
            party: "agy",
            time: p.created,
            titleHtml: escapeHtml(extractQuestionKeyword(p.question) || "(질문 내용 없음)"),
            subHtml: '<span>위임</span>' + (p.model ? '<span>' + escapeHtml(p.model) + '</span>' : "") +
              '<span>' + escapeHtml(p.session || "단발성") + '</span>',
            sideHtml: processing ? '<span class="badge status-pending-processing">진행 중</span>'
                                 : '<span class="badge status-pending-queued">대기 중</span>',
            onClick: goQaSession(p)
          });
        }
      });
    });

    allItems.slice(0, 10).forEach(function (r) {
      entries.push({
        time: r.timestamp || "",
        node: function () {
          return buildRow({
            party: "agy",
            isErr: Boolean(r.status) && !isOkStatus(r),
            time: r.timestamp,
            titleHtml: escapeHtml(extractQuestionKeyword(r.question) || "(질문 내용 없음)"),
            subHtml: '<span>위임</span>' +
              (recordModel(r) ? '<span>' + escapeHtml(recordModel(r)) + '</span>' : "") +
              '<span>' + escapeHtml(r.session || "단발성") + '</span>',
            sideHtml: qaStatusBadge(r),
            onClick: goQaSession(r)
          });
        }
      });
    });

    handoffProjects.forEach(function (p) {
      var m = p.latestMsg;
      if (!m) return;
      entries.push({ time: m.time || p.updated || "", node: function () { return handoffRow(p.name, m, "인수인계"); } });
    });

    entries.sort(function (a, b) { return String(b.time).localeCompare(String(a.time)); });
    entries = entries.slice(0, 10);

    els.dashTimeline.innerHTML = "";
    if (entries.length === 0) {
      els.dashTimeline.innerHTML = '<li class="row-empty">아직 기록이 없습니다. Claude가 agy에 작업을 위임하거나 인수인계 메시지를 보내면 여기에 쌓입니다.</li>';
      return;
    }
    var frag = document.createDocumentFragment();
    entries.forEach(function (e) { frag.appendChild(e.node()); });
    els.dashTimeline.appendChild(frag);
  }

  function renderStats() {
    var totalQa = allItems.length;
    var okCount = 0;
    var errCount = 0;
    var todayCount = 0;
    var totalElapsed = 0;
    var elapsedItemCount = 0;
    var todayKey = localDateKey(new Date());
    var modelUsage = {};

    allItems.forEach(function (r) {
      if (isOkStatus(r)) { okCount++; } else if (r.status) { errCount++; }
      if (r.timestamp && String(r.timestamp).slice(0, 10) === todayKey) { todayCount++; }
      if (r.elapsed_sec && !isNaN(Number(r.elapsed_sec))) {
        totalElapsed += Number(r.elapsed_sec);
        elapsedItemCount++;
      }
      var m = recordModel(r) || "기타";
      modelUsage[m] = (modelUsage[m] || 0) + 1;
    });

    var decided = okCount + errCount;
    var successRate = decided > 0 ? Math.round((okCount / decided) * 100) + "%" : "-";
    var avgSec = elapsedItemCount > 0 ? formatDuration(totalElapsed / elapsedItemCount) : "-";

    var totalHandoffMsgs = 0;
    handoffProjects.forEach(function (p) { totalHandoffMsgs += (p.msgCount || 0); });

    if (els.dashStats) {
      var stats = [
        ["누적 위임", totalQa.toLocaleString() + "건"],
        ["오늘", todayCount + "건"],
        ["성공률", successRate],
        ["평균 소요", avgSec],
        ["인수인계 채널", handoffProjects.length + "개"],
        ["메시지", totalHandoffMsgs.toLocaleString() + "개"]
      ];
      els.dashStats.innerHTML = stats.map(function (s) {
        return '<div><dt>' + s[0] + '</dt><dd>' + escapeHtml(s[1]) + '</dd></div>';
      }).join("");
    }

    renderDashboardModelStats(modelUsage, totalQa);
  }

  function renderQuickSessions() {
    if (!els.quickSessionsList) return;
    var sessions = groupQaSessions();
    if (sessions.length === 0) {
      els.quickSessionsList.innerHTML = '<span class="empty-hint">세션 기록이 없습니다.</span>';
      return;
    }
    var frag = document.createDocumentFragment();
    sessions.slice(0, 6).forEach(function (s) {
      var item = document.createElement("div");
      item.className = "quick-link-item";
      var isNone = (s.name === "__none__");
      var displayName = isNone ? "단발성 작업" : s.name;
      item.innerHTML = [
        '<span class="session-icon">' + icon(isNone ? "single" : "thread") + '</span>',
        '<span class="quick-link-name" title="' + escapeHtml(displayName) + '">' + escapeHtml(displayName) + '</span>',
        (s.pending > 0 ? '<span class="pending-pulse-dot" title="진행/대기 중 ' + s.pending + '건"></span>' : ''),
        '<span class="quick-link-count">' + (s.total + s.pending) + '</span>'
      ].join("");
      makeActivatable(item);
      item.onclick = goQaSession(s.name);
      frag.appendChild(item);
    });
    els.quickSessionsList.innerHTML = "";
    els.quickSessionsList.appendChild(frag);
  }

  function renderDashboardModelStats(modelUsage, totalCount) {
    if (!els.modelBarsContainer) return;
    var models = Object.keys(modelUsage).sort(function (a, b) {
      return modelUsage[b] - modelUsage[a];
    });

    if (models.length === 0) {
      els.modelBarsContainer.innerHTML = "";
      return;
    }

    var frag = document.createDocumentFragment();
    models.forEach(function (m) {
      var count = modelUsage[m];
      var pct = totalCount > 0 ? Math.round((count / totalCount) * 100) : 0;

      var row = document.createElement("div");
      row.className = "model-bar-row";
      row.innerHTML = [
        '<span class="model-bar-name" title="' + escapeHtml(m) + '">' + escapeHtml(m) + '</span>',
        '<div class="model-bar-track" aria-hidden="true">',
        '  <div class="model-bar-fill" style="width: ' + pct + '%;"></div>',
        '</div>',
        '<span class="model-bar-val">' + count + '건 ' + pct + '%</span>'
      ].join("");
      frag.appendChild(row);
    });

    els.modelBarsContainer.innerHTML = "";
    els.modelBarsContainer.appendChild(frag);
  }

  // ==========================================================================
  // 2. 위임 실행 기록 메인 뷰 (QA Cards & Session Thread Rendering)
  // ==========================================================================

  function uniqueModels() {
    var set = {};
    allItems.forEach(function (r) { if (recordModel(r)) { set[recordModel(r)] = true; } });
    pendingItems.forEach(function (p) { if (p.model) { set[p.model] = true; } });
    return Object.keys(set).sort();
  }

  function populateModelFilter() {
    if (!els.modelFilter) return;
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

  function renderQaAgyChips() {
    if (!els.qaSessionChips) return;

    var agySessions = qaAgySessionsOf(allItems, pendingItems, claudeTree, currentQaProject, currentQaSession);
    var hasNamed = agySessions.some(function (s) { return s.name !== "__none__"; });

    if (!hasNamed) {
      els.qaSessionChips.hidden = true;
      els.qaSessionChips.innerHTML = "";
      currentQaAgy = "";
      return;
    }

    els.qaSessionChips.hidden = false;

    var totalCount = 0;
    var totalPending = 0;
    var totalErrors = 0;
    var namedSessions = [];
    var noneSession = null;

    for (var i = 0; i < agySessions.length; i++) {
      var s = agySessions[i];
      totalCount += (s.total + s.pending);
      totalPending += s.pending;
      totalErrors += s.errors;
      if (s.name === "__none__") {
        noneSession = s;
      } else {
        namedSessions.push(s);
      }
    }

    var validAgys = { "": true };
    for (var n = 0; n < namedSessions.length; n++) {
      validAgys[namedSessions[n].name] = true;
    }
    if (noneSession) {
      validAgys["__none__"] = true;
    }

    if (currentQaAgy && !validAgys[currentQaAgy]) {
      currentQaAgy = "";
    }

    function buildChipHtml(agyVal, displayName, count, pending, errors) {
      var isActive = (currentQaAgy === agyVal);
      var dotHtml = (pending > 0) ? '<span class="pending-pulse-dot"></span>' : '';
      var errHtml = (errors > 0) ? '<span class="qa-chip-err">실패 ' + errors + '</span>' : '';
      return [
        '<button type="button" class="qa-chip' + (isActive ? ' active' : '') + '" data-agy="' + escapeHtml(agyVal) + '">',
        dotHtml,
        '<span class="qa-chip-name">' + escapeHtml(displayName) + '</span>',
        '<span class="qa-chip-count">' + count + '</span>',
        errHtml,
        '</button>'
      ].join("");
    }

    var htmlParts = [];
    htmlParts.push(buildChipHtml("", "전체", totalCount, totalPending, totalErrors));
    for (var sIdx = 0; sIdx < namedSessions.length; sIdx++) {
      var ns = namedSessions[sIdx];
      htmlParts.push(buildChipHtml(ns.name, ns.name, ns.total + ns.pending, ns.pending, ns.errors));
    }
    if (noneSession) {
      htmlParts.push(buildChipHtml("__none__", "단발성", noneSession.total + noneSession.pending, noneSession.pending, noneSession.errors));
    }

    els.qaSessionChips.innerHTML = htmlParts.join("");

    els.qaSessionChips.onclick = function (e) {
      var btn = e.target && e.target.closest ? e.target.closest(".qa-chip") : null;
      if (!btn) return;
      var agy = btn.getAttribute("data-agy") || "";
      selectQaAgy(agy);
    };
  }

  function applyQaFilters() {
    var q = (els.qaSearch ? els.qaSearch.value : "").trim().toLowerCase();
    var model = els.modelFilter ? els.modelFilter.value : "";
    var status = els.statusFilter ? els.statusFilter.value : "";

    // 1. 이미 완료된 task_id 집합
    var finishedTaskIds = {};
    allItems.forEach(function (r) {
      if (r && r.task_id) { finishedTaskIds[r.task_id] = true; }
    });

    // 2. pending 목록 필터링
    if (status) {
      filteredPending = [];
    } else {
      filteredPending = pendingItems.filter(function (p) {
        if (!p || !p.task_id) return false;
        if (finishedTaskIds[p.task_id]) return false;
        if (!qaItemMatchesSelection(p, claudeTree, currentQaProject, currentQaSession)) return false;
        if (!qaItemMatchesAgy(p, currentQaAgy)) return false;
        if (model && p.model !== model) return false;
        if (q) {
          var qText = (p.question || "").toLowerCase();
          var mText = (p.model || "").toLowerCase();
          var tText = (p.task_id || "").toLowerCase();
          if (qText.indexOf(q) === -1 && mText.indexOf(q) === -1 && tText.indexOf(q) === -1) return false;
        }
        return true;
      });
    }

    // 3. 완료 레코드 필터링
    filteredQa = allItems.filter(function (r) {
      if (!qaItemMatchesSelection(r, claudeTree, currentQaProject, currentQaSession)) return false;
      if (!qaItemMatchesAgy(r, currentQaAgy)) return false;
      if (model && recordModel(r) !== model) return false;
      if (status) {
        var st = (r.status == null ? "" : String(r.status)).trim();
        if (status === "OK" && st !== "OK") return false;
        if (status === "ERROR" && st === "OK") return false;
      }
      if (q) {
        var hay = [recordModel(r), r.computer_name, r.task_id, r.source, r.session, r.session_id, r.question, r.answer]
          .map(function (v) { return v == null ? "" : String(v); })
          .join(" ").toLowerCase();
        if (hay.indexOf(q) === -1) return false;
      }
      return true;
    });

    renderQaAgyChips();

    // 헤더 건수는 filteredQa/filteredPending 을 읽으므로 반드시 필터 계산 뒤에 갱신한다.
    // (앞에서 부르면 직전 값이 표시되어, 대시보드에서 막 넘어왔을 때 "0건"으로 보였다.)
    updateQaHeader();

    shownQaCount = 0;
    if (els.cards) {
      els.cards.innerHTML = "";

      // pending 카드를 목록 상단에 렌더링
      if (filteredPending.length > 0) {
        var pFrag = document.createDocumentFragment();
        filteredPending.forEach(function (p) {
          var qIdx = pendingItems.indexOf(p);
          if (qIdx < 0) qIdx = 0;
          pFrag.appendChild(buildPendingCard(p, qIdx));
        });
        els.cards.appendChild(pFrag);
      }
    }

    renderMoreQa();
    renderProcessDialog();
    updateTopbarMeta();
  }

  // 질문/답변 구역의 펼침 상태(과정은 카드 맨 윗줄의 버튼으로 창을 연다).
  //   기본: 맨 위(가장 최근) 카드의 답변만 펼치고, 나머지는 질문·과정·답변 모두 접은 채로 시작한다.
  //   사용자가 직접 열거나 닫은 구역만 qaOpenOverrides 에 기억해서, 5초마다 카드를 다시 그려도 그대로 유지한다.
  //   (예전에는 그리기 직전의 "현재 상태"를 통째로 저장했는데, 그러면 기본으로 펼쳐졌던 카드도 사용자가 연 것으로
  //   기억돼 새 카드가 생겨도 이전 카드가 계속 펼쳐 있었다.)
  var qaOpenOverrides = {};   // "<카드 키>|q" / "|a" -> true(열었음) / false(닫았음)

  function qaSectionKey(d) {
    var type = d.classList.contains("q") ? "q" : "a";
    return d.parentNode.getAttribute("data-key") + "|" + type;
  }

  function applyQaOpenDefaults() {
    if (!els.cards) return;
    var first = els.cards.querySelector(".card[data-key]");
    var items = els.cards.querySelectorAll(".card[data-key] > details.qa");
    for (var i = 0; i < items.length; i++) {
      var d = items[i];
      var k = qaSectionKey(d);
      d.open = Object.prototype.hasOwnProperty.call(qaOpenOverrides, k)
        ? qaOpenOverrides[k]
        : (d.parentNode === first && d.classList.contains("a"));
    }
  }

  function updateQaHeader() {
    if (!els.qaCurrentSessionTitle) return;

    if (!currentQaProject) {
      els.qaCurrentSessionTitle.textContent = "전체 프로젝트 피드";
    } else {
      var tree = buildQaTree(allItems, pendingItems, claudeTree);
      var titles = findQaNodeTitles(tree, currentQaProject, currentQaSession);
      if (!currentQaSession) {
        els.qaCurrentSessionTitle.textContent = titles.projectName;
      } else {
        els.qaCurrentSessionTitle.textContent = titles.sessionTitle;
      }
    }

    var totalInSession = filteredQa.length + filteredPending.length;
    if (els.qaCurrentSessionCount) {
      els.qaCurrentSessionCount.textContent = totalInSession + "건";
    }

    var latestItem = filteredPending[0] || filteredQa[0];
    if (els.chipQaTime) {
      els.chipQaTime.textContent = "최근 작업: " + (latestItem ? (latestItem.timestamp || latestItem.created || "-") : "-");
    }
    if (els.chipQaModels) {
      var mVal = els.modelFilter ? els.modelFilter.value : "";
      els.chipQaModels.textContent = "모델: " + (mVal || "전체");
    }
    if (els.chipQaStatus) {
      var sVal = els.statusFilter ? els.statusFilter.value : "";
      els.chipQaStatus.textContent = "상태: " + (sVal || "전체");
    }
  }

  function renderMoreQa() {
    if (!els.cards) return;
    var next = filteredQa.slice(shownQaCount, shownQaCount + PAGE_SIZE);
    var frag = document.createDocumentFragment();
    next.forEach(function (r) {
      frag.appendChild(buildCard(r));
    });
    els.cards.appendChild(frag);
    shownQaCount += next.length;

    if (els.loadMoreBtn) {
      els.loadMoreBtn.hidden = (shownQaCount >= filteredQa.length);
    }

    if (shownQaCount === 0 && filteredPending.length === 0) {
      els.cards.innerHTML = '<p class="empty">해당 세션 또는 조건에 일치하는 위임 기록이 없습니다.</p>';
    }
    applyQaOpenDefaults();
  }

  // ==========================================================================
  // Image & Lightbox Logic
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
        '    <a class="lightbox-btn lightbox-open-newtab" href="#" target="_blank" rel="noopener" title="새 탭에서 원본 열기">새 탭에서 열기</a>',
        '    <button class="lightbox-btn lightbox-close" type="button" title="닫기 (Esc)">닫기</button>',
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
    if (cwd) { url += "&cwd=" + encodeURIComponent(cwd); }
    return url;
  }

  function showHoverPopup(e, imgUrl, label) {
    var hp = document.getElementById("image-hover-popup");
    if (!hp) return;
    var img = hp.querySelector("img");
    var caption = hp.querySelector(".popup-caption");
    if (img) img.src = imgUrl;
    if (caption) caption.textContent = label || imgUrl;
    hp.style.display = "flex";

    var x = e.clientX + 16;
    var y = e.clientY + 16;
    var vw = window.innerWidth;
    var vh = window.innerHeight;
    if (x + 520 > vw) x = Math.max(10, e.clientX - 530);
    if (y + 420 > vh) y = Math.max(10, vh - 430);
    hp.style.left = x + "px";
    hp.style.top = y + "px";
  }

  function hideHoverPopup() {
    var hp = document.getElementById("image-hover-popup");
    if (hp) hp.style.display = "none";
  }

  function openLightbox(imgUrl, label) {
    hideHoverPopup();
    var lb = document.getElementById("image-lightbox");
    if (!lb) return;
    var img = lb.querySelector(".lightbox-img");
    var title = lb.querySelector(".lightbox-title");
    var openBtn = lb.querySelector(".lightbox-open-newtab");
    if (img) img.src = imgUrl;
    if (title) title.textContent = label || "이미지 원본 보기";
    if (openBtn) openBtn.href = imgUrl;
    lb.style.display = "flex";
    document.body.style.overflow = "hidden";
  }

  function closeLightbox() {
    var lb = document.getElementById("image-lightbox");
    if (!lb) return;
    lb.style.display = "none";
    var img = lb.querySelector(".lightbox-img");
    if (img) img.src = "";
    document.body.style.overflow = "";
  }

  // @cwd 값(문자열 하나, 폴더 배열, 없음)을 폴더 문자열 배열로 만든다. 빈 값과 중복(대소문자, 끝의 \ 또는 / 무시)은 뺀다.
  // 서버가 예전에는 문자열 하나를, 지금은 폴더 배열을 주므로 둘 다 받는다(예전 기록·옛 서버도 그대로 보인다).
  function cwdListOf(value) {
    var src = Array.isArray(value) ? value : (value == null ? [] : [value]);
    var out = [], seen = {};
    for (var i = 0; i < src.length; i++) {
      var s = String(src[i] == null ? "" : src[i]).trim();
      if (!s) continue;
      var key = s.replace(/[\\/]+$/, "").toLowerCase() || s.toLowerCase();
      if (seen[key]) continue;
      seen[key] = true;
      out.push(s);
    }
    return out;
  }

  // 질문 맨 위의 @cwd 줄들. 워처와 같은 규칙이다: 맨 위의 지시어 줄(@cwd/@session/@model)만 보고, 줄 순서대로 모은다.
  function leadingCwds(text) {
    var out = [];
    var lines = String(text == null ? "" : text).split(/\r?\n/);
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (/^\s*$/.test(line)) continue;
      var m = line.match(/^\ufeff?@cwd:\s*(.+)$/i);
      if (m) { out.push(m[1].trim()); continue; }
      if (/^\ufeff?@(session|model):/i.test(line)) continue;
      break;
    }
    return cwdListOf(out);
  }

  function extractImagesFromText(text) {
    if (!text) return { cwd: "", cwds: [], images: [] };
    // @cwd 는 여러 줄일 수 있다. cwds 가 폴더 목록이고, cwd 는 그 첫 번째다(상대 경로 이미지는 첫 폴더 기준으로 찾는다).
    var cwds = leadingCwds(text);
    if (!cwds.length) {
      // 예전 동작: 맨 위가 아니라 본문 중간에 있는 @cwd 한 줄도 읽는다
      var cwdMatch = text.match(/@cwd:\s*([^\r\n]+)/i);
      if (cwdMatch) cwds = cwdListOf(cwdMatch[1]);
    }
    var cwd = cwds[0] || "";
    var candidates = [];
    var seen = {};

    function add(path) {
      if (!path) return;
      path = path.trim().replace(/^[`"']+|[`"']+$/g, "").trim();
      if (!path) return;
      if (/\.(png|jpe?g|gif|webp|svg|bmp|ico)$/i.test(path)) {
        if (!seen[path]) {
          seen[path] = true;
          candidates.push(path);
        }
      }
    }

    var btRegex = /`([^`\r\n]+\.(?:png|jpe?g|gif|webp|svg|bmp|ico))`\s*/gi;
    var m;
    while ((m = btRegex.exec(text)) !== null) { add(m[1]); }

    var mdRegex = /!?\[[^\]]*\]\(([^)\r\n]+\.(?:png|jpe?g|gif|webp|svg|bmp|ico))\)/gi;
    while ((m = mdRegex.exec(text)) !== null) { add(m[1]); }

    var absRegex = /\b([a-zA-Z]:\\[^\s<>"'`*?|]+\.(?:png|jpe?g|gif|webp|svg|bmp|ico))\b/gi;
    while ((m = absRegex.exec(text)) !== null) { add(m[1]); }

    var relRegex = /(?:^|[\s"'(<])((?:[a-zA-Z0-9_\-\.\uac00-\ud7a3]+\/|[a-zA-Z0-9_\-\.\uac00-\ud7a3]+\\)*[a-zA-Z0-9_\-\.\uac00-\ud7a3]+\.(?:png|jpe?g|gif|webp|svg|bmp|ico))(?=[\s"')>]|$)/gi;
    while ((m = relRegex.exec(text)) !== null) { add(m[1]); }

    return { cwd: cwd, cwds: cwds, images: candidates };
  }

  function createImageGallery(images, cwd) {
    if (!images || images.length === 0) return null;
    var gallery = document.createElement("div");
    gallery.className = "qa-image-gallery";
    gallery.innerHTML = '<div class="qa-image-gallery-title">참조 이미지 ' + images.length + '개 (올려 두면 미리보기, 클릭하면 크게 보기)</div>';

    var grid = document.createElement("div");
    grid.className = "qa-image-gallery-grid";
    var validCount = images.length;

    images.forEach(function (imgPath) {
      var fullUrl = makeImageUrl(imgPath, cwd);
      var card = document.createElement("div");
      card.className = "image-thumb-card";
      card.title = imgPath + "\n(마우스 오버: 확대 / 클릭: 크게 보기)";

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

      img.onerror = function () {
        card.remove();
        validCount--;
        if (validCount <= 0) {
          gallery.remove();
        } else {
          var titleEl = gallery.querySelector(".qa-image-gallery-title");
          if (titleEl) {
            titleEl.textContent = '참조 이미지 ' + validCount + '개 (올려 두면 미리보기, 클릭하면 크게 보기)';
          }
        }
      };

      card.addEventListener("mouseenter", function (e) { showHoverPopup(e, fullUrl, imgPath); });
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

  // ==========================================================================
  // 마크다운, KaTeX, 구문 강조, Mermaid, GFM 콜아웃 공통 렌더링 헬퍼
  // ==========================================================================
  var mermaidInitialized = false;
  var mermaidCounter = 0;

  function ensureMermaidInit() {
    if (mermaidInitialized) return;
    if (window.mermaid && typeof window.mermaid.initialize === "function") {
      try {
        window.mermaid.initialize({
          startOnLoad: false,
          theme: "dark",
          securityLevel: "loose",
          fontFamily: "IBM Plex Sans KR, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif"
        });
        mermaidInitialized = true;
      } catch (e) {}
    }
  }

  var ALERT_TYPES = {
    note: {
      label: "Note",
      icon: '<svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor"><path d="M0 8a8 8 0 1 1 16 0A8 8 0 0 1 0 8Zm8-6.5a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13ZM6.5 7.75A.75.75 0 0 1 7.25 7h1a.75.75 0 0 1 .75.75v2.75h.25a.75.75 0 0 1 0 1.5h-2a.75.75 0 0 1 0-1.5h.25v-2h-.25a.75.75 0 0 1-.75-.75ZM8 6a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z"/></svg>'
    },
    tip: {
      label: "Tip",
      icon: '<svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor"><path d="M8 1.5c-2.363 0-4 1.69-4 3.75 0 .984.424 1.625.984 2.304l.214.253c.223.264.47.556.673.848.284.411.537.896.621 1.49a.75.75 0 0 1-1.484.211c-.04-.282-.163-.547-.37-.847a8.456 8.456 0 0 0-.542-.68c-.619-.747-1.346-1.633-1.346-3.279C2.75 2.568 5.12 0 8 0s5.25 2.568 5.25 5.25c0 1.646-.727 2.532-1.346 3.28-.168.202-.35.419-.541.679-.208.3-.332.565-.372.847a.751.751 0 0 1-1.485-.21c.084-.595.338-1.08.621-1.49.204-.292.45-.584.673-.848.075-.088.147-.173.213-.253.561-.679.985-1.32.985-2.304 0-2.06-1.637-3.75-4-3.75ZM5.75 12h4.5a.75.75 0 0 1 0 1.5h-4.5a.75.75 0 0 1 0-1.5Zm1 3h2.5a.75.75 0 0 1 0 1.5h-2.5a.75.75 0 0 1 0-1.5Z"/></svg>'
    },
    important: {
      label: "Important",
      icon: '<svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor"><path d="M0 1.75C0 .784.784 0 1.75 0h12.5C15.216 0 16 .784 16 1.75v9.5A1.75 1.75 0 0 1 14.25 13H9.06l-2.573 2.573A1.458 1.458 0 0 1 4 14.543V13H1.75A1.75 1.75 0 0 1 0 11.25Zm1.75-.25a.25.25 0 0 0-.25.25v9.5c0 .138.112.25.25.25h3a.75.75 0 0 1 .75.75v2.19l2.72-2.72a.749.749 0 0 1 .53-.22h5.5a.25.25 0 0 0 .25-.25v-9.5a.25.25 0 0 0-.25-.25Zm6.47 2.97a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0v-3.5a.75.75 0 0 1 .75-.75Zm0 7.03a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z"/></svg>'
    },
    warning: {
      label: "Warning",
      icon: '<svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor"><path d="M6.457 1.047c.659-1.234 2.427-1.234 3.086 0l6.082 11.378A1.75 1.75 0 0 1 14.082 15H1.918a1.75 1.75 0 0 1-1.543-2.575Zm1.763.707a.25.25 0 0 0-.44 0L1.698 13.132a.25.25 0 0 0 .22.368h12.164a.25.25 0 0 0 .22-.368Zm.53 3.996v2.5a.75.75 0 0 1-1.5 0v-2.5a.75.75 0 0 1 1.5 0ZM9 11a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z"/></svg>'
    },
    caution: {
      label: "Caution",
      icon: '<svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor"><path d="M4.47.22A.749.749 0 0 1 5 0h6c.199 0 .389.079.53.22l4.25 4.25c.141.14.22.331.22.53v6c0 .199-.079.389-.22.53l-4.25 4.25a.749.749 0 0 1-.53.22H5a.749.749 0 0 1-.53-.22L.22 11.75A.749.749 0 0 1 0 11.22V5.25c0-.199.079-.389.22-.53Zm.84 1.28L1.5 5.31v5.38l3.81 3.81h5.38l3.81-3.81V5.31L10.69 1.5ZM8 4a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0v-3.5A.75.75 0 0 1 8 4Zm0 8a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z"/></svg>'
    }
  };

  var COPY_ICON_SVG = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>';
  var COPIED_ICON_SVG = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="20 6 9 17 4 12"></polyline></svg>';

  function renderMarkdownWithMath(text) {
    if (!text) return "";
    var hasMarked = window.marked && typeof window.marked.parse === "function";
    if (!hasMarked) return escapeHtml(text);

    var hasKatex = window.katex && typeof window.katex.renderToString === "function";
    if (!hasKatex) {
      var rawHtml = window.marked.parse(text);
      return window.DOMPurify && typeof window.DOMPurify.sanitize === "function" ?
        window.DOMPurify.sanitize(rawHtml, { ADD_TAGS: ["input"], ADD_ATTR: ["type", "checked", "disabled"] }) : rawHtml;
    }

    var mathList = [];

    // 1. 코드 블록(```...```) 및 인라인 코드(`...`) 임시 보호
    var codeBlocks = [];
    var s = String(text).replace(/(```[\s\S]*?```|`[^`\n]*?`)/g, function (match) {
      var ph = "%%%CBLOCK_" + codeBlocks.length + "%%%";
      codeBlocks.push(match);
      return ph;
    });

    // 2. 블록 수식 ($$...$$ 또는 \[...\]) 보호
    s = s.replace(/(?:\$\$([\s\S]*?)\$\$|\\\[([\s\S]*?)\\\])/g, function (match, m1, m2) {
      var math = (m1 || m2 || "").trim();
      var ph = "%%%MATH_B_" + mathList.length + "%%%";
      mathList.push({ type: "block", math: math });
      return "\n\n" + ph + "\n\n";
    });

    // 3. 인라인 수식 ($...$ 또는 \(...\)) 보호
    // 절충: PowerShell 변수($env:..., $PSScriptRoot)나 가격($5 ~ $10), 일반 한글 문장이 수식으로
    // 깨지는 오탐을 막기 위해, $...$ 안에 한글이나 $식별자가 들어 있으면 수식으로 보지 않는다.
    // (수식 안에 한글이 꼭 필요하면 \( \text{정답} \) 또는 $$ 블록 수식을 쓴다.)
    s = s.replace(/(?:(?<!\\|\w)\$(?!\s)([^\$\n]+?)(?<!\s)\$(?![A-Za-z0-9_:])|\\\(([\s\S]*?)\\\))/g, function (match, m1, m2) {
      var math = (m1 || m2 || "").trim();
      if (!math) return match;
      if (m1 && (/[\uAC00-\uD7A3]/.test(math) || /(?:^|\s)\$[A-Za-z_]/.test(math))) {
        return match;
      }
      var ph = "%%%MATH_I_" + mathList.length + "%%%";
      mathList.push({ type: "inline", math: math });
      return ph;
    });

    // 4. 코드 블록 복원
    codeBlocks.forEach(function (code, i) {
      s = s.replace("%%%CBLOCK_" + i + "%%%", function () { return code; });
    });

    // 5. 마크다운 변환
    var html = window.marked.parse(s);

    // 6. DOMPurify 정제 (수식 플레이스홀더 및 task-list 체크박스 보존)
    if (window.DOMPurify && typeof window.DOMPurify.sanitize === "function") {
      html = window.DOMPurify.sanitize(html, { ADD_TAGS: ["input"], ADD_ATTR: ["type", "checked", "disabled"] });
    }

    // 7. KaTeX 수식 HTML 치환
    mathList.forEach(function (item, i) {
      var rendered = "";
      try {
        rendered = window.katex.renderToString(item.math, {
          displayMode: item.type === "block",
          throwOnError: false
        });
      } catch (err) {
        rendered = '<span class="katex-error" title="' + escapeHtml(err.message) + '">' + escapeHtml(item.math) + '</span>';
      }

      var target = item.type === "block" ? "%%%MATH_B_" + i + "%%%" : "%%%MATH_I_" + i + "%%%";
      if (item.type === "block") {
        var pWrapped = new RegExp("<p>\\s*" + target + "\\s*<\\/p>", "g");
        if (pWrapped.test(html)) {
          html = html.replace(pWrapped, function () { return '<div class="katex-display-wrapper">' + rendered + '</div>'; });
        } else {
          html = html.replace(target, function () { return rendered; });
        }
      } else {
        html = html.replace(target, function () { return rendered; });
      }
    });

    return html;
  }

  function postProcessMarkdownElements(container, cwd) {
    if (!container) return;

    ensureMermaidInit();

    // 1. GFM Alerts (> [!NOTE], > [!TIP], > [!IMPORTANT], > [!WARNING], > [!CAUTION])
    var bqs = container.querySelectorAll("blockquote");
    bqs.forEach(function (bq) {
      if (bq.classList.contains("markdown-alert")) return;
      var firstP = bq.querySelector("p");
      if (!firstP) return;
      var rawHtml = firstP.innerHTML;
      var match = rawHtml.match(/^\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\](\s*<br\s*\/?>)?/i);
      if (match) {
        var type = match[1].toLowerCase();
        var alertInfo = ALERT_TYPES[type];
        if (alertInfo) {
          bq.classList.add("markdown-alert", "markdown-alert-" + type);
          var remaining = rawHtml.slice(match[0].length).trim();
          if (remaining) {
            firstP.innerHTML = remaining;
          } else {
            firstP.remove();
          }
          var titleEl = document.createElement("div");
          titleEl.className = "markdown-alert-title";
          titleEl.innerHTML = alertInfo.icon + "<span>" + alertInfo.label + "</span>";
          bq.insertBefore(titleEl, bq.firstChild);
        }
      }
    });

    // 2. Code blocks (Mermaid / Highlight.js / Copy button)
    var pres = container.querySelectorAll("pre");
    pres.forEach(function (pre) {
      if (pre.parentElement && pre.parentElement.classList.contains("code-block-wrapper")) return;
      if (pre.classList.contains("code-handled")) return;

      var code = pre.querySelector("code");
      if (!code) return;

      var lang = "";
      var classNames = code.className ? String(code.className).split(/\s+/) : [];
      for (var i = 0; i < classNames.length; i++) {
        var cls = classNames[i];
        if (cls.indexOf("language-") === 0) {
          lang = cls.replace("language-", "").trim().toLowerCase();
          break;
        }
      }

      // 2-1. Mermaid 다이어그램
      if (lang === "mermaid") {
        pre.classList.add("code-handled");
        var graphCode = (code.textContent || "").trim();
        var mBlock = document.createElement("div");
        mBlock.className = "mermaid-block";
        var mId = "mermaid-svg-" + Date.now() + "-" + (++mermaidCounter);

        if (window.mermaid && typeof window.mermaid.render === "function") {
          try {
            window.mermaid.render(mId, graphCode).then(function (res) {
              mBlock.innerHTML = res.svg;
            }).catch(function (err) {
              mBlock.innerHTML = '<div class="mermaid-error">Mermaid 렌더링 실패: ' + escapeHtml(err.message || String(err)) + '</div>';
            });
          } catch (err) {
            mBlock.innerHTML = '<div class="mermaid-error">Mermaid 에러: ' + escapeHtml(err.message || String(err)) + '</div>';
          }
        } else {
          mBlock.innerHTML = '<pre>' + escapeHtml(graphCode) + '</pre>';
        }

        if (pre.parentNode) {
          pre.parentNode.replaceChild(mBlock, pre);
        }
        return;
      }

      // 2-2. Syntax highlighting (highlight.js)
      if (window.hljs && typeof window.hljs.highlightElement === "function") {
        try {
          window.hljs.highlightElement(code);
        } catch (e) {}
      }

      // 2-3. Code block wrapper + 헤더 + 복사 버튼
      var wrapper = document.createElement("div");
      wrapper.className = "code-block-wrapper";

      var header = document.createElement("div");
      header.className = "code-block-header";

      var langSpan = document.createElement("span");
      langSpan.className = "code-block-lang";
      langSpan.textContent = lang || "CODE";

      var copyBtn = document.createElement("button");
      copyBtn.className = "code-copy-btn";
      copyBtn.type = "button";
      copyBtn.title = "코드 클립보드에 복사";
      copyBtn.innerHTML = COPY_ICON_SVG + "<span>복사</span>";

      copyBtn.addEventListener("click", function (e) {
        e.stopPropagation();
        var codeText = code.innerText || code.textContent || "";
        if (navigator.clipboard && typeof navigator.clipboard.writeText === "function") {
          navigator.clipboard.writeText(codeText).then(function () {
            copyBtn.classList.add("copied");
            copyBtn.innerHTML = COPIED_ICON_SVG + "<span>복사됨!</span>";
            setTimeout(function () {
              copyBtn.classList.remove("copied");
              copyBtn.innerHTML = COPY_ICON_SVG + "<span>복사</span>";
            }, 2000);
          }).catch(function () {
            copyBtn.querySelector("span").textContent = "실패";
          });
        }
      });

      header.appendChild(langSpan);
      header.appendChild(copyBtn);

      if (pre.parentNode) {
        pre.parentNode.insertBefore(wrapper, pre);
        wrapper.appendChild(header);
        wrapper.appendChild(pre);
      }
      pre.classList.add("code-handled");
    });

    // 3. 인라인 이미지 참조 (pre 바깥에 있는 code)
    var inlineCodes = container.querySelectorAll("code");
    inlineCodes.forEach(function (code) {
      if (code.closest("pre")) return;
      var str = (code.textContent || "").trim();
      if (/\.(png|jpe?g|gif|webp|svg|bmp|ico)$/i.test(str)) {
        var imgUrl = makeImageUrl(str, cwd);
        code.classList.add("inline-image-ref");
        code.title = str + " (올려 두면 미리보기, 클릭하면 원본 보기)";
        code.addEventListener("mouseenter", function (e) { showHoverPopup(e, imgUrl, str); });
        code.addEventListener("mouseleave", hideHoverPopup);
        code.addEventListener("click", function (e) {
          e.preventDefault();
          e.stopPropagation();
          openLightbox(imgUrl, str);
        });
      }
    });

    // 4. 테이블 반응형 스크롤 래퍼
    var tables = container.querySelectorAll("table");
    tables.forEach(function (table) {
      if (table.parentElement && table.parentElement.classList.contains("table-wrapper")) return;
      var wrap = document.createElement("div");
      wrap.className = "table-wrapper";
      if (table.parentNode) {
        table.parentNode.insertBefore(wrap, table);
        wrap.appendChild(table);
      }
    });

    // 5. 외부 링크 새 탭 열기
    var links = container.querySelectorAll("a");
    links.forEach(function (link) {
      var href = link.getAttribute("href") || "";
      if (/^https?:\/\//i.test(href)) {
        link.setAttribute("target", "_blank");
        link.setAttribute("rel", "noopener noreferrer");
      }
    });
  }

  function renderBody(container, text, cwd) {
    var canRenderMarkdown = window.marked && typeof window.marked.parse === "function";
    if (canRenderMarkdown) {
      container.classList.add("md");
      container.innerHTML = renderMarkdownWithMath(text || "");
      postProcessMarkdownElements(container, cwd);
    } else {
      var pre = document.createElement("pre");
      pre.textContent = text || "";
      container.appendChild(pre);
    }
  }

  function badge(cls, text) {
    var s = document.createElement("span");
    s.className = "badge " + cls;
    s.textContent = text;
    return s;
  }

  // 색 없는 메타 항목. 색은 상태 배지에만 쓴다.
  function metaItem(text, cls, title) {
    var s = document.createElement("span");
    s.className = "meta-item" + (cls ? " " + cls : "");
    s.textContent = text;
    if (title) s.title = title;
    return s;
  }

  // 위임 한 건의 토큰 줄(총 토큰 + 입력/출력/사고). 기록에 값이 있는 항목만 보여 주고, 하나도 없으면 줄 자체를 만들지 않는다.
  function buildTokenMeta(r) {
    var parts = [
      ["총 토큰", r.total_tokens, "총 토큰"],
      ["입력", r.input_tokens, "입력 토큰"],
      ["출력", r.output_tokens, "출력 토큰"],
      ["사고", r.thinking_tokens, "사고(thinking) 토큰"]
    ];
    var row = document.createElement("div");
    row.className = "meta token-meta";
    parts.forEach(function (p) {
      var n = Number(p[1]);
      if (!p[1] || isNaN(n)) return;
      row.appendChild(metaItem(p[0] + " " + n.toLocaleString(), "mono", p[2]));
    });
    return row.childNodes.length ? row : null;
  }

  // 세션 이름과, 클릭하면 전체 세션 ID를 복사하는 짧은 ID
  function buildSessionMeta(sessionName, sessionId) {
    var sMeta = document.createElement("div");
    sMeta.className = "meta session-meta";
    sMeta.appendChild(metaItem(sessionName ? "세션 " + sessionName : "세션 작업"));
    if (sessionId) {
      var sid = String(sessionId);
      var label = "id " + (sid.length > 8 ? sid.substring(0, 8) : sid);
      var sidEl = metaItem(label, "mono copyable", "세션 ID " + sid + " (클릭하면 복사)");
      makeActivatable(sidEl, "세션 ID 복사");
      sidEl.onclick = function () {
        if (navigator.clipboard) {
          navigator.clipboard.writeText(sid).then(function () {
            sidEl.textContent = "복사했습니다";
            setTimeout(function () { sidEl.textContent = label; }, 1200);
          });
        }
      };
      sMeta.appendChild(sidEl);
    }
    return sMeta;
  }

  // 미리보기용으로 마크다운 "표시"를 걷어 낸다. 글자로 쓰인 _ * ~ 는 지우지 않는다:
  //   merge_intervals, __init__.py, ~/.samjil, src/*.ts, 2 * 3 은 그대로 남기고,
  //   **굵게**, *기울임*, _기울임_, ~~취소~~ 처럼 짝이 맞는 강조 표시만 벗긴다.
  // (예전에는 [*_`~] 를 전부 지워서 merge_intervals 가 mergeintervals 로, ~/.samjil 이 /.samjil 로 보였다.)
  function stripEmphasis(s) {
    return s
      .replace(/(^|[\s(\["'])\*\*(?=\S)([\s\S]*?\S)\*\*/g, "$1$2")
      .replace(/(^|[\s(\["'])\*(?=\S)([^*\n]*?\S)\*/g, "$1$2")
      .replace(/(^|[\s(\["'])~~(?=\S)([\s\S]*?\S)~~/g, "$1$2")
      // _기울임_ 은 단어 사이의 밑줄(snake_case)이 아닐 때만. __init__ 같은 이중 밑줄은 식별자로 보고 둔다.
      .replace(/(^|[^A-Za-z0-9_가-힣])_(?=\S)([^_\n]*?\S)_(?![A-Za-z0-9_가-힣])/g, "$1$2");
  }

  function cleanTextForPreview(str) {
    if (!str) return "";
    // `인라인 코드` 안은 마크다운이 아니므로 그대로 두고(백틱만 벗김), 바깥만 강조 표시를 벗긴다.
    var parts = String(str).replace(/^#+\s*/, "").split(/(`+[^`]*`+)/);
    for (var i = 0; i < parts.length; i++) {
      parts[i] = (i % 2 === 1) ? parts[i].replace(/^`+|`+$/g, "") : stripEmphasis(parts[i]);
    }
    return parts.join("")
      .replace(/`/g, "")
      .replace(/\[(.*?)\]\(.*?\)/g, "$1")
      .replace(/<[^>]*>/g, " ")
      .replace(/\s+/g, " ")
      .trim();
  }

  function extractQuestionKeyword(text) {
    if (!text) return "";
    var lines = String(text).split("\n");
    var valid = [];

    for (var i = 0; i < lines.length; i++) {
      var t = lines[i].trim();
      if (!t) continue;
      // 워처 지시어 줄(@cwd / @session / @model)은 질문 내용이 아니다
      if (/^\ufeff?@(cwd|session|model):/i.test(t)) continue;
      if (t.indexOf("**읽기") === 0 || t.indexOf("**[읽기") === 0 || t.indexOf("<!--") === 0) continue;
      if (t.indexOf("```") === 0) continue;
      if (t.indexOf("|") === 0 && t.lastIndexOf("|") === t.length - 1) continue;

      var cleaned = cleanTextForPreview(t);
      if (cleaned) {
        valid.push(cleaned);
        if (valid.join(" ").length >= 60 || valid.length >= 2) break;
      }
    }

    if (valid.length > 0) return valid.join(" ");

    for (var j = 0; j < lines.length; j++) {
      var lt = lines[j].trim();
      if (lt.indexOf("|") === 0 && lt.lastIndexOf("|") === lt.length - 1) {
        var cols = lt.split("|").map(function (c) { return cleanTextForPreview(c); }).filter(Boolean);
        if (cols.length > 0 && cols[0] !== "항목" && cols[0].indexOf("---") === -1) {
          return cols[0];
        }
      }
    }

    return cleanTextForPreview(text).substring(0, 100);
  }

  function extractAnswerKeyword(text) {
    if (!text) return "";
    var lines = String(text).split("\n");
    var tableRows = [];
    for (var i = 0; i < lines.length; i++) {
      var t = lines[i].trim();
      if (t.indexOf("|") === 0 && t.lastIndexOf("|") === t.length - 1) {
        var cols = t.split("|").map(function (c) { return cleanTextForPreview(c); }).filter(Boolean);
        if (cols.length >= 2 && cols[0] !== "항목" && cols[0] !== "구분" && cols[0].indexOf("---") === -1) {
          var key = cols[0];
          var val = cols[1];
          if (key && val) tableRows.push(key + ": " + val);
        }
      }
    }
    if (tableRows.length > 0) return tableRows.slice(0, 2).join(" · ");

    var valid = [];
    for (var j = 0; j < lines.length; j++) {
      var lt = lines[j].trim();
      if (!lt || lt.indexOf("```") === 0 || lt.indexOf("---") === 0 || lt.indexOf("===") === 0 || lt.indexOf("<!--") === 0) continue;
      var cleaned = cleanTextForPreview(lt);
      if (cleaned) {
        valid.push(cleaned);
        if (valid.join(" ").length >= 60 || valid.length >= 2) break;
      }
    }
    if (valid.length > 0) return valid.join(" ");
    return cleanTextForPreview(text).substring(0, 100);
  }

  // ==========================================================================
  // 과정: agy 가 질문과 답변 사이에 한 일(부른 도구 목록). 기록(r.process)에서 읽고,
  // 기록에 없는 옛 위임은 펼칠 때 agy 대화 기록에서 읽어 온다(/api/delegate/process).
  // ==========================================================================

  // 한 줄 요약. 예) 도구 호출 23번 · 명령 실행 9 · 파일 읽기 6 · 파일 쓰기 3 외 1종
  function summarizeProcess(steps, live) {
    if (!steps || !steps.length) return live ? "아직 도구를 부르지 않았습니다" : "도구를 쓰지 않고 바로 답했습니다";
    var counts = {}, order = [];
    steps.forEach(function (st) {
      var k = progressToolLabel(st.tool) || "기타";
      if (!Object.prototype.hasOwnProperty.call(counts, k)) { counts[k] = 0; order.push(k); }
      counts[k]++;
    });
    order.sort(function (x, y) { return counts[y] - counts[x]; });
    var parts = order.slice(0, 3).map(function (k) { return k + " " + counts[k]; });
    return "도구 호출 " + steps.length + "번 · " + parts.join(" · ") + (order.length > 3 ? " 외 " + (order.length - 3) + "종" : "");
  }

  // 작업 폴더(@cwd) 아래 경로는 폴더 이름을 빼고 보인다. 예) C:\workpp\src.py -> src.py (폴더 자체는 ".")
  // 폴더가 여러 개면 어느 폴더의 파일인지 알 수 있게 폴더 이름부터 보인다. 예) 폴더 C:\a\repo, D:\b\docs -> repo\src.py, docs\x.md (폴더 자체는 "repo")
  // 명령 안에 적힌 경로도 같은 규칙이다. work2 처럼 이름만 비슷한 폴더는 건드리지 않는다. 전체 경로는 마우스를 올리면 보인다.
  // cwd 는 폴더 문자열 하나나 폴더 배열이다.
  function shortenPathsForCwd(text, cwd) {
    var src = String(text == null ? "" : text);
    var bases = cwdListOf(cwd).map(function (c) { return c.replace(/[\\/]+$/, ""); }).filter(Boolean);
    if (!src || !bases.length) return src;
    var multi = bases.length > 1;
    // 한 폴더가 다른 폴더 안에 있으면 더 구체적인(긴) 폴더 기준으로 먼저 줄인다
    bases.sort(function (a, b) { return b.length - a.length; });
    var out = src;
    bases.forEach(function (base) {
      var esc = base.replace(/[.*+?^${}()|[\]\\\/]/g, function (ch) { return (ch === "\\" || ch === "/") ? "[\\\\/]" : "\\" + ch; });
      var re = new RegExp("(^|[\\s\"'(=])" + esc + "([\\\\/]+|(?=$|[\\s\"')]))", "gi");
      var name = multi ? base.split(/[\\/]/).pop() : "";
      out = out.replace(re, function (m, pre, sep) {
        if (!sep) return pre + (name || ".");
        return pre + (name ? name + sep : "");
      });
    });
    return out === "" ? "." : out;
  }

  // agy 가 그 단계에서 적은 말. say 는 도구를 부르며 알린 진행 설명, think 는 agy 의 생각(영어 원문)이다.
  // 클래스 접두어는 과정 목록 "proc", 진행 중 카드 "pg". 둘 다 없으면 빈 글.
  function buildNarrationHtml(prefix, say, think) {
    var out = "";
    if (say) out += '<span class="' + prefix + '-say"><b>설명</b> ' + escapeHtml(say) + '</span>';
    if (think) out += '<span class="' + prefix + '-think"><b>생각</b> ' + escapeHtml(think) + '</span>';
    return out;
  }

  // 과정 목록(<ol>). 단계 번호 · 시각 · 한글 도구 설명 · 실제 대상 · 영어 라벨. 마우스를 올리면 생각까지 보인다.
  function buildProcessRowsHtml(steps, cwd) {
    var rows = steps.map(function (st) {
      var tool = progressToolLabel(st.tool) || "기타";
      var shown = shortenPathsForCwd(st.detail, cwd);
      var tip = [];
      if (st.tool) tip.push("도구: " + st.tool);
      if (st.detail) tip.push("대상: " + st.detail);
      if (shown !== st.detail && cwdListOf(cwd).length) {
        var tipCwds = cwdListOf(cwd);
        tip.push("작업 폴더(@cwd): " + tipCwds.join(", ") + (tipCwds.length > 1 ? " — 여러 폴더라 목록에는 폴더 이름부터 줄여 보입니다" : " — 목록에는 이 폴더 아래 경로만 줄여 보입니다"));
      }
      if (st.label) tip.push("agy 가 붙인 설명: " + st.label);
      return '<li class="proc-row"' + (tip.length ? ' title="' + escapeHtml(tip.join("\n")) + '"' : '') + '>' +
        '<span class="proc-n">' + escapeHtml(String(st.n)) + '</span>' +
        '<span class="proc-at">' + escapeHtml(st.at || "") + '</span>' +
        '<span class="proc-tool">' + escapeHtml(tool) + (st.bg ? ' (백그라운드)' : '') + '</span>' +
        '<span class="proc-text">' +
          (st.detail ? '<span class="proc-detail">' + escapeHtml(shown) + '</span>' : '') +
          (st.label ? ' <span class="proc-label">' + (st.detail ? '· ' : '') + escapeHtml(st.label) + '</span>' : '') +
          buildNarrationHtml("proc", st.say, st.think) +
        '</span></li>';
    });
    var note = steps.length >= 400 ? '<p class="proc-note">기록은 처음 400번까지만 남깁니다.</p>' : "";
    return '<ol class="proc-list">' + rows.join("") + '</ol>' + note;
  }

  // 기록에 과정이 없는 옛 위임: 대화 id 별로 한 번만 읽어 와서 기억해 둔다(카드를 다시 그려도 다시 읽지 않는다).
  var processFetchCache = {};   // 대화 id -> { state: "loading" | "done" | "error", found, steps }

  function loadProcessFor(convId) {
    var c = processFetchCache[convId];
    if (c && c.state !== "error") return;
    processFetchCache[convId] = { state: "loading" };
    fetchJson("/api/delegate/process?id=" + encodeURIComponent(convId))
      .then(function (res) {
        processFetchCache[convId] = { state: "done", found: Boolean(res && res.found), steps: (res && Array.isArray(res.steps)) ? res.steps : [] };
      })
      .catch(function () { processFetchCache[convId] = { state: "error" }; })
      .then(function () { applyQaFilters(); });
  }

  // 카드의 "과정" 줄과 그것을 눌러 여는 창이 함께 쓰는 상태 계산. 단계 목록 자체는 여기서 그리지 않는다.
  // opts: { steps: 배열|null, convId: 대화 id, live: 진행 중, waiting: 아직 시작 안 함, cwd: 작업 폴더(경로를 줄여 보이는 기준) }
  // 반환: { steps: 배열|null, message, fetchId(창을 열 때 읽어 와야 하는 대화 id), error, summary(한 줄 요약),
  //         count(단계 수, 아직 모르면 null), openable(버튼을 눌러 볼 내용이 있거나 곧 생길 수 있는지) }
  function resolveProcessState(opts) {
    var steps = Array.isArray(opts.steps) ? opts.steps : null;
    var out = { steps: null, message: "", fetchId: "", error: false, summary: "", count: null, openable: true };
    if (!steps) {
      if (opts.waiting) {
        out.message = "아직 시작하지 않았습니다";
        out.openable = false;
      } else if (opts.convId) {
        var c = processFetchCache[opts.convId];
        if (c && c.state === "done" && c.found) { steps = c.steps; }
        else if (c && c.state === "done") { out.message = "agy 대화 기록이 남아 있지 않아 과정을 볼 수 없습니다"; out.openable = false; }
        else if (c && c.state === "loading") { out.message = "agy 대화 기록에서 읽어 오는 중입니다"; }
        else if (c && c.state === "error") { out.message = "과정을 불러오지 못했습니다"; out.fetchId = opts.convId; out.error = true; }
        else { out.message = "기록에 저장되지 않은 위임입니다. 누르면 agy 대화 기록에서 읽어 옵니다"; out.fetchId = opts.convId; }
      } else {
        out.message = "과정이 기록되지 않았습니다";
        out.openable = false;
      }
    }
    if (steps) {
      out.steps = steps;
      out.count = steps.length;
      out.summary = summarizeProcess(steps, opts.live);
      out.openable = steps.length > 0 || Boolean(opts.live);   // 도구를 안 쓴 완료 작업은 볼 것이 없다
    }
    else { out.summary = out.message; }
    return out;
  }

  // 완료 기록 / 대기·진행 작업에서 과정 창에 넘길 옵션을 만든다. 창이 열려 있는 동안 최신 데이터로 다시 만들 때도 쓴다.
  function recordProcessOpts(r, cwd) {
    return { steps: Array.isArray(r.process) ? r.process : null, convId: r.session_id || "", cwd: cwd != null ? cwd : extractImagesFromText(r.question).cwds };
  }
  function pendingProcessOpts(p, cwd) {
    var isProcessing = (p.state === "processing");
    return {
      steps: (isProcessing && p.progress && Array.isArray(p.progress.steps)) ? p.progress.steps : null,
      live: isProcessing,
      waiting: !isProcessing,
      convId: (isProcessing && p.progress && p.progress.conversation_id) ? String(p.progress.conversation_id) : "",
      cwd: cwd != null ? cwd : (cwdListOf(p.cwd).length ? cwdListOf(p.cwd) : extractImagesFromText(p.question).cwds)
    };
  }

  // 카드 키(data-key)로 지금 가진 데이터에서 원본을 찾는다. 진행 중이던 작업이 끝나 기록으로 옮겨 갔으면 그쪽을 찾아 준다.
  function findProcessSource(key) {
    var i, id;
    if (key.indexOf("p:") === 0) {
      id = key.slice(2);
      for (i = 0; i < pendingItems.length; i++) {
        if (pendingItems[i] && pendingItems[i].task_id === id) return { key: key, taskId: id, opts: pendingProcessOpts(pendingItems[i]) };
      }
      key = "r:" + id;   // 끝났으면 완료 기록에서
    }
    for (i = 0; i < allItems.length; i++) {
      var r = allItems[i];
      if (r && ("r:" + (r.task_id || r.timestamp || "")) === key) return { key: key, taskId: r.task_id || "", opts: recordProcessOpts(r) };
    }
    return null;
  }

  // 카드 맨 윗줄 오른쪽의 "과정" 버튼. 질문/답변 줄과 달리 카드 안에 내용을 펼치지 않고, 누르면 창에서 단계 목록을 그린다.
  // 단계 수를 옆에 작게 보이고, 요약과 이유(볼 내용이 없을 때)는 마우스를 올리면 나온다.
  function buildProcessButton(key, opts) {
    var st = resolveProcessState(opts);
    var b = document.createElement("button");
    b.type = "button";
    b.className = "proc-open";
    b.setAttribute("data-proc-key", key);
    b.setAttribute("aria-haspopup", "dialog");
    b.title = st.summary;
    b.setAttribute("aria-label", "과정 보기: " + st.summary);
    b.disabled = !st.openable;
    var label = document.createElement("span");
    label.textContent = "과정";
    b.appendChild(label);
    if (st.count != null) {
      var cnt = document.createElement("span");
      cnt.className = "proc-open-count";
      cnt.textContent = String(st.count);
      b.appendChild(cnt);
    }
    return b;
  }

  // ---- 과정 번역("한글로 번역"). agy 의 생각·설명·라벨은 영어로 나올 때가 많다. 창에서 버튼을 눌렀을 때만 서버
  // (/api/delegate/translate)가 agy(gemini-3.8-flash-low)로 옮기고, 결과는 서버에 캐시돼서 다음부터는 바로 보인다.
  var procTr = {};        // 대화 id -> { state: running|done|none|error|unavailable, message, items(단계 순번 -> label/think/say), model }
  var procTrView = {};    // 대화 id -> "orig" | "agy" | "browser": 사용자가 고른 보기(고르지 않았으면 있는 번역본)
  var procTrTimer = null;
  var procDialogConv = "";  // 지금 창에 보이는 과정의 대화 id

  function hasHangul(s) { return /[\uAC00-\uD7A3]/.test(String(s == null ? "" : s)); }

  // 인용한 말: `코드`, "큰따옴표", “둥근 큰따옴표”, '작은따옴표'(don't 같은 아포스트로피는 제외). 인용문은 고정된 말이라
  // 한글이든 영어든 번역하지 않고 그대로 두고, "이미 한글인 글인가" 를 가를 때도 세지 않는다.
  var QUOTED_SPAN_SRC = "`[^`\\n]+`|\"[^\"\\n]+\"|\u201C[^\u201D\\n]+\u201D|(?<![A-Za-z0-9])'[^'\\n]+'(?![A-Za-z0-9])";
  function quotedSpanRe() { return new RegExp(QUOTED_SPAN_SRC, "g"); }

  // 인용문을 뺀 나머지 글
  function withoutQuotedSpans(s) { return String(s == null ? "" : s).replace(quotedSpanRe(), " "); }

  // 번역해야 하는 글인가: 인용문 밖에 한글이 없고, 인용문 밖에 번역할 영어(알파벳)가 있어야 한다.
  // 예) 영어 문장 안의 `04_문진 이벤트.sql` 은 한글이 있어도 번역 대상이고, 한글 문장은 아니다.
  function needsTranslationText(s) {
    var rest = withoutQuotedSpans(s);
    return !hasHangul(rest) && /[A-Za-z]/.test(rest);
  }

  // 번역할 글(한글이 아닌 라벨·생각·설명)이 하나라도 있는지. items 를 주면 그 안에 이미 번역된 칸은 뺀다.
  function needsTranslation(steps, items) {
    if (!steps) return false;
    var names = ["label", "think", "say"];
    for (var i = 0; i < steps.length; i++) {
      var have = items ? items[String(i)] : null;
      for (var k = 0; k < names.length; k++) {
        var v = steps[i][names[k]];
        if (v && needsTranslationText(v) && !(have && have[names[k]])) return true;
      }
    }
    return false;
  }


  // 번역해 둔 라벨·생각·설명으로 단계 목록의 글을 바꾼 사본을 돌려준다(원본은 건드리지 않는다). 순번은 단계 목록의 위치다.
  function applyProcessTranslation(steps, items) {
    if (!items) return steps;
    return steps.map(function (st, i) {
      var ko = items[String(i)];
      if (!ko) return st;
      var c = {};
      for (var k in st) { if (Object.prototype.hasOwnProperty.call(st, k)) c[k] = st[k]; }
      if (ko.label) c.label = ko.label;
      if (ko.think) c.think = ko.think;
      if (ko.say) c.say = ko.say;
      return c;
    });
  }

  function procItemCount(items) { return items ? Object.keys(items).length : 0; }

  // 지금 보는 글: "orig"(원문) | "agy"(agy 번역) | "browser"(브라우저 번역). 고르지 않았으면 있는 번역본(agy 우선), 없으면 원문.
  function procTrViewOf(convId) {
    var nA = procItemCount(procTr[convId] && procTr[convId].items);
    var nB = procItemCount(procTrB[convId] && procTrB[convId].items);
    var v = procTrView[convId];
    if (v === "orig") return "orig";
    if (v === "agy" && nA) return "agy";
    if (v === "browser" && nB) return "browser";
    return nA ? "agy" : (nB ? "browser" : "orig");
  }

  function procTrItemsFor(convId, view) {
    if (view === "agy") return (procTr[convId] && procTr[convId].items) || null;
    if (view === "browser") return (procTrB[convId] && procTrB[convId].items) || null;
    return null;
  }

  // 창 위쪽의 번역 줄: 보기 전환(원문 / agy 번역 / 브라우저 번역)과 번역 실행 버튼 두 개(agy, 브라우저)와 안내.
  // 번역할 글이 없고 번역해 둔 것도 없으면 빈 글(줄을 숨긴다).
  function buildTranslateToolsHtml(convId, steps) {
    if (!convId || !steps || !steps.length) return "";
    var agy = procTr[convId] || null;
    var br = procTrB[convId] || null;
    var nA = procItemCount(agy && agy.items);
    var nB = procItemCount(br && br.items);
    var needA = needsTranslation(steps, agy && agy.items);
    var needB = needsTranslation(steps, br && br.items);
    if (!needsTranslation(steps) && !nA && !nB) return "";
    var view = procTrViewOf(convId);
    var out = [];

    // 보기 전환: 번역본이 하나라도 있을 때만
    if (nA || nB) {
      var views = [["orig", "원문"]];
      if (nA) views.push(["agy", "agy 번역"]);
      if (nB) views.push(["browser", "브라우저 번역"]);
      out.push('<span class="proc-tr-views" role="group" aria-label="보기">' + views.map(function (v) {
        return '<button type="button" class="proc-tr-btn proc-tr-view" data-act="view" data-view="' + v[0] + '" aria-pressed="' + (view === v[0] ? "true" : "false") + '">' + v[1] + '</button>';
      }).join("") + '</span>');
    }

    // agy 로 번역
    var aState = agy ? agy.state : "";
    if (aState === "running") {
      out.push('<button type="button" class="proc-tr-btn" disabled>agy 번역 중… (30초~1분)</button>');
    } else if (aState !== "unavailable" && aState !== "done" && needA) {
      out.push('<button type="button" class="proc-tr-btn" data-act="translate" title="agy(gemini-3.8-flash-low)가 번역합니다. 30초~1분 걸리고 agy 사용량을 씁니다. 결과는 서버에 저장됩니다.">' +
        (nA > 0 ? "agy로 새 단계 번역" : (aState === "error" ? "agy로 다시 시도" : "agy로 번역")) + '</button>');
    }

    // 브라우저로 번역
    var bState = br ? br.state : "";
    if (browserTranslatorSupported()) {
      if (bState === "running") {
        var pg = br.progress || {};
        out.push('<button type="button" class="proc-tr-btn" disabled>' +
          (pg.download >= 0 ? "언어 팩 내려받는 중 " + pg.download + "%" : "브라우저 번역 중… " + (pg.total ? pg.done + "/" + pg.total : "")) + '</button>');
      } else if (needB) {
        out.push('<button type="button" class="proc-tr-btn" data-act="translate-browser" title="이 브라우저의 내장 번역을 씁니다. 무료이고 빠르지만 품질이 낮을 수 있습니다. 처음에는 언어 팩을 내려받을 수 있습니다.">' +
          (nB > 0 ? "브라우저로 이어서 번역" : (bState === "error" ? "브라우저로 다시 시도" : "브라우저로 번역")) + '</button>');
      }
    }

    // 안내
    if (aState === "unavailable") out.push('<span class="proc-tr-note">' + escapeHtml((agy && agy.message) || "agy 로는 번역할 수 없습니다") + '.</span>');
    if (aState === "error" && agy.message) out.push('<span class="proc-tr-note">agy 번역 실패: ' + escapeHtml(agy.message) + '</span>');
    if (bState === "error" && br.message) out.push('<span class="proc-tr-note">브라우저 번역 실패: ' + escapeHtml(br.message) + '</span>');
    if (bState === "done" && br.message) out.push('<span class="proc-tr-note">' + escapeHtml(br.message) + '.</span>');
    if (view === "agy") out.push('<span class="proc-tr-note">AI(' + escapeHtml((agy && agy.model) || "agy") + ')가 번역한 글입니다.</span>');
    if (view === "browser") out.push('<span class="proc-tr-note">브라우저 내장 번역 결과입니다. 틀릴 수 있습니다.</span>');
    return out.join("");
  }

  function setProcessTranslation(convId, res, fallbackMessage) {
    var prev = procTr[convId] || {};
    if (res && typeof res === "object") {
      procTr[convId] = { state: res.state || "none", message: res.message || "", items: res.items || {}, model: res.model || prev.model || "" };
    } else {
      procTr[convId] = { state: "error", message: fallbackMessage || "", items: prev.items || {}, model: prev.model || "" };
    }
  }

  // 번역 중이면 3초마다 상태를 다시 읽는다(창이 이 대화를 보여 주는 동안만).
  function afterProcessTranslationChange(convId) {
    renderProcessDialog();
    if (procTrTimer) { clearTimeout(procTrTimer); procTrTimer = null; }
    var t = procTr[convId];
    var dlg = document.getElementById("process-dialog");
    if (t && t.state === "running" && dlg && dlg.open && procDialogConv === convId) {
      procTrTimer = setTimeout(function () { loadProcessTranslation(convId); }, 3000);
    }
  }

  function loadProcessTranslation(convId) {
    fetchJson("/api/delegate/translate?id=" + encodeURIComponent(convId))
      .then(function (res) { setProcessTranslation(convId, res, "번역 상태를 읽지 못했습니다"); })
      .catch(function () { setProcessTranslation(convId, null, "번역 상태를 읽지 못했습니다"); })
      .then(function () { afterProcessTranslationChange(convId); });
  }

  function startProcessTranslation(convId) {
    var prev = procTr[convId] || {};
    procTr[convId] = { state: "running", message: "", items: prev.items || {}, model: prev.model || "" };
    renderProcessDialog();
    fetch("/api/delegate/translate?id=" + encodeURIComponent(convId), { method: "POST", headers: { "X-Samjil-Viewer": "1" } })
      .then(function (r) { return r.text(); })
      .then(function (t) {
        if (t && t.charCodeAt(0) === 0xFEFF) { t = t.slice(1); }
        setProcessTranslation(convId, JSON.parse(t), "번역을 시작하지 못했습니다");
      })
      .catch(function () { setProcessTranslation(convId, null, "번역을 시작하지 못했습니다"); })
      .then(function () { afterProcessTranslationChange(convId); });
  }

  // ---- 브라우저 내장 번역(Translator API). 서버·agy 를 거치지 않고 이 화면이 직접 영어->한국어로 옮긴다. 무료이고 빠르지만
  // 품질이 낮을 수 있고, 지시("코드는 번역하지 마")를 줄 수 없어서 백틱 안의 코드는 번역 전에 자리표시자로 빼 두었다가 되돌린다.
  // 되돌리지 못한 글(자리표시자가 사라지거나 늘어남)은 번역본으로 쓰지 않고 원문을 둔다. 결과는 이 브라우저(localStorage)에만 남는다.
  var procTrB = {};   // 대화 id -> { state: running|done|error, message, items, progress: { done, total, download } }
  var BROWSER_TR_STORE = "samjil.processTranslation.browser.v1";
  var BROWSER_TR_KEEP = 40;   // 최근 대화 몇 개까지 기억할지

  // 인용문(백틱·따옴표로 감싼 코드/이름/말)을 XQ1X, XQ2X … 로 바꿔 둔다.
  function protectCodeSpans(text) {
    var codes = [];
    var out = String(text == null ? "" : text).replace(quotedSpanRe(), function (m) { codes.push(m); return "XQ" + codes.length + "X"; });
    return { text: out, codes: codes };
  }

  // 번역된 글의 자리표시자를 원래 코드로 되돌린다. 모델이 대소문자나 공백을 흐트러뜨려도(xq 1 x) 받아 준다.
  // 하나라도 없거나, 만든 적 없는 자리표시자가 있으면 null(쓰지 않는다).
  function restoreCodeSpans(text, codes) {
    var s = String(text == null ? "" : text);
    for (var i = 0; i < codes.length; i++) {
      var re = new RegExp("XQ\\s*" + (i + 1) + "\\s*X", "gi");
      if (!re.test(s)) return null;
      re.lastIndex = 0;
      (function (code) { s = s.replace(re, function () { return code; }); })(codes[i]);
    }
    return /XQ\s*\d+\s*X/i.test(s) ? null : s;
  }

  // 인용문(`top_words` 같은 코드 표기, 따옴표로 감싼 말)들. 번역 뒤에 이것들이 그대로 남아 있어야 번역을 쓴다.
  function codeSpansOf(text) { return String(text == null ? "" : text).match(quotedSpanRe()) || []; }

  // 번역기가 백틱만 떼고 이름은 그대로 둔 경우(top_words)도 코드가 남은 것으로 본다.
  function codesSurvive(src, out) {
    var codes = codeSpansOf(src);
    for (var i = 0; i < codes.length; i++) {
      var inner = codes[i].slice(1, -1);
      if (String(out).indexOf(codes[i]) < 0 && String(out).indexOf(inner) < 0) return false;
    }
    return true;
  }

  // 글을 문장 단위로 나눈다(마침표·물음표·느낌표 뒤의 공백). 한 문장이면 길이 1.
  function splitSentences(text) {
    return String(text == null ? "" : text).split(/(?<=[.!?])\s+/).filter(function (p) { return p.trim(); });
  }

  // 한 덩어리를 번역하고 코드 표기를 지킨다. 두 가지를 차례로 시도한다.
  //   1) 글을 그대로 번역한다. 모델이 백틱 안의 코드를 그대로 두는 일이 많아서, 코드 표기가 모두 남아 있으면 그것을 쓴다.
  //   2) 안 남았으면 코드를 자리표시자(XQ1X)로 바꿔 번역한 뒤 되돌린다(자리표시자가 흐트러지면 쓰지 않는다).
  // 반환: Promise<{ text: 번역 또는 null, reason: "" | "code"(코드 표기가 사라짐) | "empty"(빈 번역) | "error", message, sample }>
  function translateChunkKeepingCode(translator, text) {
    var raw = String(text);
    var sample = "";
    return Promise.resolve().then(function () { return translator.translate(raw); }).then(function (ko) {
      ko = String(ko == null ? "" : ko).trim();
      sample = ko;
      if (ko && codesSurvive(raw, ko)) return { text: ko, reason: "" };
      var pr = protectCodeSpans(raw);
      if (!pr.codes.length) return { text: null, reason: ko ? "code" : "empty", sample: sample };
      return Promise.resolve(translator.translate(pr.text)).then(function (ko2) {
        var restored = restoreCodeSpans(ko2, pr.codes);
        if (restored && restored.trim()) return { text: restored.trim(), reason: "" };
        return { text: null, reason: "code", sample: String(ko2 == null ? "" : ko2).trim() || sample };
      });
    }).catch(function (err) {
      return { text: null, reason: "error", message: (err && err.message) ? err.message : String(err), sample: sample };
    });
  }

  // 한 칸의 글을 번역한다. 통째로 안 되면 문장별로 나눠 되는 문장만 번역하고 나머지 문장은 원문으로 둔다(칸 하나에 한글과 영어가 섞인다).
  function translateTextWithBrowser(translator, text) {
    return translateChunkKeepingCode(translator, text).then(function (r) {
      if (r.text) return r;
      var parts = splitSentences(text);
      if (parts.length < 2) return r;
      var out = [], got = 0, chain = Promise.resolve();
      parts.forEach(function (p) {
        chain = chain.then(function () {
          return translateChunkKeepingCode(translator, p).then(function (q) {
            if (q.text) { got++; out.push(q.text); } else { out.push(p); }
          });
        });
      });
      return chain.then(function () { return got ? { text: out.join(" "), reason: "", partial: true } : r; });
    });
  }

  // 번역기(translator.translate(글) -> Promise<글>)로 단계 목록의 한글 아닌 칸을 번역한다. existing 에 이미 있는 칸은 건너뛴다.
  // 반환: Promise<{ items, failed, total, partial(문장 일부만 번역한 칸 수), reasons: { code, empty, error }, firstError, sample }>.
  // 한 칸이 실패해도 나머지는 계속한다.
  function translateStepsWithBrowser(steps, existing, translator, onProgress) {
    var jobs = [];
    var fields = ["label", "think", "say"];
    steps.forEach(function (st, i) {
      fields.forEach(function (f) {
        var v = st[f];
        var have = existing && existing[String(i)] && existing[String(i)][f];
        if (v && needsTranslationText(v) && !have) jobs.push({ i: String(i), f: f, text: String(v) });
      });
    });
    var items = {};
    Object.keys(existing || {}).forEach(function (k) { items[k] = {}; Object.keys(existing[k]).forEach(function (f) { items[k][f] = existing[k][f]; }); });
    var res = { items: items, failed: 0, total: jobs.length, partial: 0, reasons: { code: 0, empty: 0, error: 0 }, firstError: "", sample: "" };
    var done = 0;
    var chain = Promise.resolve();
    jobs.forEach(function (j) {
      chain = chain.then(function () {
        return translateTextWithBrowser(translator, j.text).then(function (r) {
          if (r.text) {
            if (!items[j.i]) items[j.i] = {};
            items[j.i][j.f] = r.text;
            if (r.partial) res.partial++;
          } else {
            res.failed++;
            res.reasons[r.reason] = (res.reasons[r.reason] || 0) + 1;
            if (r.reason === "error" && !res.firstError) res.firstError = r.message || "";
            if (r.reason === "code" && !res.sample) res.sample = (r.sample || "").slice(0, 80);
          }
        }).then(function () {
          done++;
          if (onProgress) onProgress(done, jobs.length);
        });
      });
    });
    return chain.then(function () { return res; });
  }

  // 번역이 끝난 뒤 사용자에게 보일 안내(실패한 칸이 있을 때 이유를 함께). 실패한 칸이 없으면 빈 글.
  function browserTranslationMessage(res) {
    var bits = [];
    if (res.reasons.code) bits.push("번역에서 코드 표기가 사라진 칸 " + res.reasons.code + (res.sample ? " (번역기가 돌려준 글 예: \"" + res.sample + "\")" : ""));
    if (res.reasons.empty) bits.push("빈 번역 " + res.reasons.empty);
    if (res.reasons.error) bits.push("번역기 오류 " + res.reasons.error + (res.firstError ? " (" + res.firstError + ")" : ""));
    var detail = bits.length ? " — " + bits.join(", ") : "";
    if (res.total > 0 && res.failed === res.total) return "브라우저 번역이 모든 글에서 실패했습니다" + detail;
    if (res.failed) return res.failed + "칸은 번역을 쓸 수 없어 원문으로 두었습니다" + detail;
    if (res.partial) return res.partial + "칸은 일부 문장만 번역했습니다";
    return "";
  }

  function withTimeout(promise, ms, message) {
    return new Promise(function (resolve, reject) {
      var t = setTimeout(function () { reject(new Error(message)); }, ms);
      Promise.resolve(promise).then(function (v) { clearTimeout(t); resolve(v); }, function (e) { clearTimeout(t); reject(e); });
    });
  }

  function browserTranslatorSupported() { return typeof Translator !== "undefined"; }

  // 번역기를 만든다. 언어 팩이 없으면 내려받는다(진행률은 onDownload). 이 브라우저가 못 하면 이유를 담아 reject.
  function createBrowserTranslator(onDownload) {
    if (!browserTranslatorSupported()) return Promise.reject(new Error("이 브라우저는 내장 번역(Translator API)을 지원하지 않습니다"));
    var opts = { sourceLanguage: "en", targetLanguage: "ko" };
    return withTimeout(Translator.availability(opts), 10000, "브라우저가 번역 가능 여부에 답하지 않습니다. 이 브라우저에서는 쓸 수 없는 것 같습니다")
      .then(function (av) {
        if (av === "unavailable") throw new Error("이 브라우저는 영어→한국어 번역을 지원하지 않습니다");
        var create = Translator.create({
          sourceLanguage: opts.sourceLanguage, targetLanguage: opts.targetLanguage,
          monitor: function (m) { m.addEventListener("downloadprogress", function (e) { if (onDownload) onDownload(Math.round((e.loaded || 0) * 100)); }); }
        });
        return withTimeout(create, 180000, "번역 모델 준비가 끝나지 않았습니다. 다시 눌러 주세요");
      });
  }

  function loadBrowserTranslations() {
    try {
      var raw = window.localStorage.getItem(BROWSER_TR_STORE);
      var obj = raw ? JSON.parse(raw) : {};
      return (obj && typeof obj === "object") ? obj : {};
    } catch (e) { return {}; }
  }

  function saveBrowserTranslation(convId, items) {
    try {
      var all = loadBrowserTranslations();
      all[convId] = { t: Date.now(), items: items };
      var ids = Object.keys(all).sort(function (a, b) { return (all[b].t || 0) - (all[a].t || 0); });
      ids.slice(BROWSER_TR_KEEP).forEach(function (id) { delete all[id]; });
      window.localStorage.setItem(BROWSER_TR_STORE, JSON.stringify(all));
    } catch (e) { /* 저장을 못 해도(비공개 창 등) 이번 화면에서는 번역본이 보인다 */ }
  }

  // 창을 열 때 이 브라우저에 저장해 둔 번역이 있으면 불러온다.
  function restoreBrowserTranslation(convId) {
    if (procTrB[convId] && procTrB[convId].items) return;
    var saved = loadBrowserTranslations()[convId];
    if (saved && saved.items && Object.keys(saved.items).length) procTrB[convId] = { state: "done", message: "", items: saved.items, progress: null };
  }

  function startBrowserTranslation(convId, steps) {
    var prev = procTrB[convId] || {};
    var existing = prev.items || {};
    procTrB[convId] = { state: "running", message: "", items: existing, progress: { done: 0, total: 0, download: -1 } };
    renderProcessDialog();
    var token = procTrB[convId];
    function progress(p) { if (procTrB[convId] === token) { token.progress = p; renderProcessDialog(); } }
    createBrowserTranslator(function (pct) { progress({ done: 0, total: 0, download: pct }); })
      .then(function (translator) {
        return translateStepsWithBrowser(steps, existing, translator, function (d, t) { progress({ done: d, total: t, download: -1 }); })
          .then(function (res) { try { if (translator.destroy) translator.destroy(); } catch (e) {} return res; });
      })
      .then(function (res) {
        var allFailed = res.total > 0 && res.failed === res.total;
        procTrB[convId] = { state: allFailed ? "error" : "done", message: browserTranslationMessage(res), items: res.items, progress: null };
        if (!allFailed) saveBrowserTranslation(convId, res.items);
      })
      .catch(function (err) {
        procTrB[convId] = { state: "error", message: (err && err.message) ? err.message : "브라우저 번역에 실패했습니다", items: existing, progress: null };
      })
      .then(function () { renderProcessDialog(); });
  }

  var procDialogKey = "";   // 지금 열려 있는 과정 창의 카드 키("" 이면 닫힘)
  var procDialogSteps = null;  // 지금 창에 보이는 단계 목록(브라우저 번역 버튼이 쓴다)
  var procDialogLast = "";  // 마지막으로 그린 내용(같으면 다시 그리지 않아 스크롤과 선택이 유지된다)

  function ensureProcessDialog() {
    var dlg = document.getElementById("process-dialog");
    if (dlg) return dlg;
    dlg = document.createElement("dialog");
    dlg.id = "process-dialog";
    dlg.setAttribute("aria-labelledby", "process-dialog-title");
    dlg.innerHTML = [
      '<div class="proc-dlg">',
      '  <header class="proc-dlg-head">',
      '    <div class="proc-dlg-heading">',
      '      <h2 id="process-dialog-title" class="proc-dlg-title">과정</h2>',
      '      <span class="proc-dlg-task"></span>',
      '    </div>',
      '    <button type="button" class="proc-dlg-close" title="닫기 (Esc)">닫기</button>',
      '  </header>',
      '  <p class="proc-dlg-sum"></p>',
      '  <p class="proc-dlg-cwd"></p>',
      '  <div class="proc-dlg-tools" hidden></div>',
      '  <div class="proc-dlg-body"></div>',
      '</div>'
    ].join("");
    dlg.addEventListener("click", function (e) {
      if (e.target === dlg || (e.target.classList && e.target.classList.contains("proc-dlg-close"))) { dlg.close(); return; }
      var retry = e.target.closest ? e.target.closest(".proc-retry") : null;
      if (retry) { loadProcessFor(retry.getAttribute("data-conv")); return; }
      var trBtn = e.target.closest ? e.target.closest(".proc-tr-btn") : null;
      if (trBtn && procDialogConv) {
        var act = trBtn.getAttribute("data-act");
        if (act === "translate") { startProcessTranslation(procDialogConv); }
        else if (act === "translate-browser") { startBrowserTranslation(procDialogConv, procDialogSteps || []); }
        else if (act === "view") { procTrView[procDialogConv] = trBtn.getAttribute("data-view"); renderProcessDialog(); }
      }
    });
    dlg.addEventListener("close", function () {
      procDialogKey = ""; procDialogLast = ""; procDialogConv = "";
      if (procTrTimer) { clearTimeout(procTrTimer); procTrTimer = null; }
    });
    document.body.appendChild(dlg);
    return dlg;
  }

  // 창 내용을 지금 데이터로 그린다. 진행 중인 작업은 5초마다 새로 고칠 때 새 단계가 이어서 붙는다.
  function renderProcessDialog() {
    if (!procDialogKey) return;
    var dlg = document.getElementById("process-dialog");
    if (!dlg || !dlg.open) return;
    var src = findProcessSource(procDialogKey);
    if (!src) { dlg.close(); return; }
    procDialogKey = src.key;
    var st = resolveProcessState(src.opts);

    var convId = src.opts.convId || "";
    procDialogConv = convId;
    var html;
    if (st.steps && st.steps.length) {
      procDialogSteps = st.steps;
      var viewItems = procTrItemsFor(convId, procTrViewOf(convId));
      html = buildProcessRowsHtml(viewItems ? applyProcessTranslation(st.steps, viewItems) : st.steps, src.opts.cwd);
    } else if (st.steps) {
      html = '<p class="proc-empty">' + escapeHtml(st.summary) + '.</p>';
    } else {
      html = '<p class="proc-empty">' + escapeHtml(st.message) + '.</p>' +
        (st.error ? '<button type="button" class="proc-retry" data-conv="' + escapeHtml(st.fetchId) + '">다시 시도</button>' : "");
    }
    var toolsHtml = buildTranslateToolsHtml(convId, st.steps);
    var head = [src.taskId, st.summary, src.opts.live ? "live" : "", cwdListOf(src.opts.cwd).join("|"), toolsHtml].join("\u0001");
    if (procDialogLast === head + "\u0002" + html) return;
    procDialogLast = head + "\u0002" + html;

    dlg.querySelector(".proc-dlg-task").textContent = src.taskId;
    dlg.querySelector(".proc-dlg-sum").textContent = st.summary + (src.opts.live && st.steps ? " · 진행 중이라 새 단계가 생기면 자동으로 이어 붙습니다" : "");
    var cwdEl = dlg.querySelector(".proc-dlg-cwd");
    var dlgCwds = cwdListOf(src.opts.cwd);
    cwdEl.textContent = (dlgCwds.length && st.steps && st.steps.length)
      ? (dlgCwds.length === 1
        ? "작업 폴더 " + dlgCwds[0] + " 아래 경로는 폴더 이름을 빼고 보입니다."
        : "작업 폴더 " + dlgCwds.length + "개: " + dlgCwds.join(", ") + " — 이 폴더들 아래 경로는 폴더 이름부터 보입니다.")
      : "";
    cwdEl.hidden = !cwdEl.textContent;
    var toolsEl = dlg.querySelector(".proc-dlg-tools");
    toolsEl.innerHTML = toolsHtml;
    toolsEl.hidden = !toolsHtml;
    var body = dlg.querySelector(".proc-dlg-body");
    var top = body.scrollTop;
    body.innerHTML = html;
    body.scrollTop = top;
  }

  function openProcessDialog(key) {
    var src = findProcessSource(key);
    if (!src) return;
    var dlg = ensureProcessDialog();
    procDialogKey = src.key;
    procDialogLast = "";
    // 기록에 과정이 없는 옛 위임만, 창을 여는 지금 한 번 읽어 온다(카드를 그릴 때는 읽지 않는다)
    var st = resolveProcessState(src.opts);
    if (st.fetchId) loadProcessFor(st.fetchId);
    if (src.opts.convId) restoreBrowserTranslation(src.opts.convId);
    if (!dlg.open) dlg.showModal();
    renderProcessDialog();
    // 번역해 둔 것이 있는지 서버에서 한 번 읽는다(작은 응답). 번역을 시작하는 것은 사용자가 버튼을 눌렀을 때뿐이다.
    if (src.opts.convId) loadProcessTranslation(src.opts.convId);
  }

  function buildCard(r) {
    var st = (r.status == null ? "" : String(r.status)).trim();
    var isOk = (st === "OK");
    var isErr = (st !== "" && !isOk);

    var card = document.createElement("div");
    card.className = "card" + (isErr ? " err" : "");
    card.setAttribute("data-key", "r:" + (r.task_id || r.timestamp || ""));

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

    var modelName = recordModel(r) || null;
    var isSession = Boolean(r.session || r.session_id || r.model === "(session)");
    if (modelName) { meta.appendChild(metaItem(String(modelName), "model")); }
    if (r.elapsed_sec) {
      var elSec = Number(r.elapsed_sec);
      var elText = formatDuration(elSec);
      var tip = "실제 실행 시간: " + r.elapsed_sec + "초";
      if (r.wait_sec && Number(r.wait_sec) >= 5) {
        var wSec = Number(r.wait_sec);
        elText += " (대기 " + formatDuration(wSec) + ")";
        tip += " / 큐 대기 시간: " + r.wait_sec + "초";
      }
      meta.appendChild(metaItem(elText, "elapsed", tip));
    }
    if (r.attempts && Number(r.attempts) > 1) { meta.appendChild(metaItem("시도 " + r.attempts + "회")); }
    meta.appendChild(metaItem((r.source || "bridge") === "mcp" ? "MCP" : "bridge", "", "위임 경로"));
    if (r.task_id) { meta.appendChild(metaItem(r.task_id, "mono", "작업 ID")); }
    card.appendChild(meta);

    var tokenMeta = buildTokenMeta(r);
    if (tokenMeta) card.appendChild(tokenMeta);

    if (isSession) {
      card.appendChild(buildSessionMeta(r.session, r.session_id));
    }

    var dq = document.createElement("details");
    dq.className = "qa q";
    var sq = document.createElement("summary");
    var qBadge = document.createElement("span");
    qBadge.className = "qa-type-badge q-type";
    qBadge.textContent = "질문";
    sq.appendChild(qBadge);

    var qKw = extractQuestionKeyword(r.question);
    if (qKw) {
      var qKwSpan = document.createElement("span");
      qKwSpan.className = "qa-preview-keyword";
      qKwSpan.textContent = qKw;
      qKwSpan.title = qKw;
      sq.appendChild(qKwSpan);
    }
    dq.appendChild(sq);

    var qb = document.createElement("div");
    qb.className = "body";
    var qImgInfo = extractImagesFromText(r.question);
    var qGallery = createImageGallery(qImgInfo.images, qImgInfo.cwd);
    if (qGallery) qb.appendChild(qGallery);
    var qContent = document.createElement("div");
    qContent.className = "qa-content";
    renderBody(qContent, r.question, qImgInfo.cwd);
    qb.appendChild(qContent);
    dq.appendChild(qb);
    card.appendChild(dq);

    meta.appendChild(buildProcessButton(card.getAttribute("data-key"), recordProcessOpts(r, qImgInfo.cwds)));

    var da = document.createElement("details");
    da.className = "qa a";
    var sa = document.createElement("summary");
    var aBadge = document.createElement("span");
    aBadge.className = "qa-type-badge a-type";
    aBadge.textContent = "답변";
    sa.appendChild(aBadge);

    var aKw = extractAnswerKeyword(r.answer);
    if (aKw) {
      var aKwSpan = document.createElement("span");
      aKwSpan.className = "qa-preview-keyword";
      aKwSpan.textContent = aKw;
      aKwSpan.title = aKw;
      sa.appendChild(aKwSpan);
    }
    da.appendChild(sa);

    var ab = document.createElement("div");
    ab.className = "body";
    var aImgInfo = extractImagesFromText(r.answer);
    var aGallery = createImageGallery(aImgInfo.images, qImgInfo.cwd || aImgInfo.cwd);
    if (aGallery) ab.appendChild(aGallery);
    var aContent = document.createElement("div");
    aContent.className = "qa-content";
    renderBody(aContent, r.answer, qImgInfo.cwd || aImgInfo.cwd);
    ab.appendChild(aContent);
    da.appendChild(ab);
    card.appendChild(da);

    return card;
  }

  // 마지막 활동이 이 시간(초) 이상 없으면 "조용함" 표시로 바꾼다. 워처의 멈춤 판정(300초)보다 먼저 눈치챌 수 있게 짧게 둔다.
  var PROGRESS_QUIET_SEC = 120;

  // 진행 중인 위임의 진행 상황 줄. 서버가 agy 대화 기록에서 읽은 단계/최근 동작/마지막 활동 시각을 보여 준다.
  // agy 도구 이름 -> 한글 설명. 영어 라벨(Checking target directory 등)만으로는 무슨 일을 하는지 알 수 없어서 덧붙인다.
  // agy 대화 기록 131개, 도구 호출 2,287건에서 나온 12종이다. 모르는 도구는 이름을 그대로 보인다.
  function progressToolLabel(name) {
    var m = {
      run_command: "명령 실행",
      view_file: "파일 읽기",
      write_to_file: "파일 쓰기",
      replace_file_content: "파일 일부 수정",
      list_dir: "폴더 목록 보기",
      find_by_name: "파일 이름 찾기",
      grep_search: "파일 내용 검색",
      search_web: "웹 검색",
      read_url_content: "웹 페이지 읽기",
      manage_task: "작업 관리",
      schedule: "잠시 대기",
      generate_image: "이미지 생성"
    };
    if (!name) return "";
    return Object.prototype.hasOwnProperty.call(m, name) ? m[name] : name;
  }

  // "지금:" 줄. 한글 도구 설명 + 실제 대상(명령, 파일, 폴더) + agy 가 붙인 영어 라벨 순서로 보여 준다.
  // 예) 지금: 명령 실행 Get-Location · Checking target directory
  // 서버가 tool/detail 을 주지 않는 옛 서버면 영어 라벨만 보인다(기존 동작).
  function buildProgressActionHtml(pg, cwd) {
    var tool = progressToolLabel(pg.tool);
    if (!tool && !pg.detail && !pg.action && !pg.say && !pg.thinking) return "";
    var pieces = [];
    if (tool) pieces.push('<span class="pg-tool">' + escapeHtml(tool) + (pg.background ? ' (백그라운드)' : '') + '</span>');
    if (pg.detail) pieces.push('<span class="pg-detail">' + escapeHtml(shortenPathsForCwd(pg.detail, cwdListOf(cwd).length ? cwd : pg.cwd)) + '</span>');
    if (pg.action) pieces.push('<span class="pg-label">' + ((tool || pg.detail) ? '· ' : '') + escapeHtml(pg.action) + '</span>');
    var html = '지금: ' + pieces.join(' ');
    // 줄이 길어 잘리면 마우스를 올려 전체를 본다
    var tip = [];
    if (pg.tool) tip.push("도구: " + pg.tool);
    if (pg.detail) tip.push("대상: " + pg.detail);
    if (pg.cwd) tip.push("실행 폴더: " + pg.cwd);
    if (pg.action) tip.push("agy 가 붙인 설명: " + pg.action);
    return '<div class="pg-action" title="' + escapeHtml(tip.join("\n")) + '">' + html + '</div>' +
      buildNarrationHtml("pg", pg.say, pg.thinking);
  }

  function buildProgressHtml(pg, cwd) {
    if (!pg) return "";
    var parts = [];
    if (pg.step != null) {
      parts.push('<span class="pg-step" title="' +
        escapeHtml("agy 대화 기록의 번호입니다. 도구를 부르는 것과 그 결과가 각각 한 단계로 세어져서, 실제로 한 일의 수보다 큽니다.") +
        '">' + escapeHtml(String(pg.step)) + '단계 진행</span>');
    }
    if (pg.last_activity_ms) {
      parts.push('<span class="pg-idle" data-ms="' + escapeHtml(String(pg.last_activity_ms)) + '">' +
        formatDuration((Date.now() - pg.last_activity_ms) / 1000) + ' 전 활동</span>');
    }
    if (pg.tokens && pg.tokens.total > 0) {
      var tot = Number(pg.tokens.total);
      var inTok = Number(pg.tokens.input || 0);
      var outTok = Number(pg.tokens.output || 0);
      var tokText = (tot >= 10000 ? (tot / 10000).toFixed(1) + '만' : tot.toLocaleString()) + ' 토큰';
      parts.push('<span class="pg-tokens" style="color: var(--ink); font-weight: 500;" title="실시간 누적 토큰: ' + tot.toLocaleString() + ' (입력 ' + inTok.toLocaleString() + ' / 출력 ' + outTok.toLocaleString() + ')">⚡ 실시간 ' + tokText + '</span>');
    }
    var action = buildProgressActionHtml(pg, cwd);
    return '<div class="pending-progress">' + (parts.length ? '<div class="pg-line">' + parts.join('<span class="pg-sep">·</span>') + '</div>' : "") + action + '</div>';
  }

  function buildPendingCard(p, queueIndex) {
    var isProcessing = (p.state === "processing");
    var card = document.createElement("div");
    card.className = "card pending-card" + (isProcessing ? " processing" : " queued");
    card.setAttribute("data-key", "p:" + (p.task_id || ""));

    var meta = document.createElement("div");
    meta.className = "meta";
    var ts = document.createElement("span");
    ts.className = "ts";
    ts.textContent = p.created || "";
    meta.appendChild(ts);

    if (isProcessing) {
      meta.appendChild(badge("status-pending-processing", "진행 중"));
    } else {
      meta.appendChild(badge("status-pending-queued", "대기 중"));
    }

    if (p.model) { meta.appendChild(metaItem(String(p.model), "model")); }

    if (isProcessing) {
      var createdTime = parseLocalTime(p.created);
      var actualStartTime = p.started_at ? parseLocalTime(p.started_at) : createdTime;
      var startTime = actualStartTime || createdTime;

      // 1. 실제 실행 시간 라이브 배지 (1초마다 자동 갱신)
      if (startTime) {
        var elapsedSec = Math.max(0, (Date.now() - startTime.getTime()) / 1000);
        var live = metaItem("실행 " + formatDuration(elapsedSec), "elapsed live-elapsed", "실제 실행 경과 시간 (실행 시작: " + (p.started_at || p.created || "") + ")");
        live.setAttribute("data-start", String(startTime.getTime()));
        live.setAttribute("data-label-prefix", "실행 ");
        meta.appendChild(live);
      }

      // 2. 대기 시간 배지 (5초 이상 대기열에 있었던 경우 함께 표시)
      if (createdTime && actualStartTime) {
        var waitSec = Math.max(0, Math.floor((actualStartTime.getTime() - createdTime.getTime()) / 1000));
        if (waitSec >= 5) {
          var totalSec = Math.floor((Date.now() - createdTime.getTime()) / 1000);
          var waitBadge = metaItem("대기 " + formatDuration(waitSec), "wait-time", "대기열 대기: " + formatDuration(waitSec) + " (접수: " + (p.created || "") + " / 실행 시작: " + (p.started_at || "") + " / 총 경과: " + formatDuration(totalSec) + ")");
          meta.appendChild(waitBadge);
        }
      }

      // 3. 실시간 토큰 사용량 배지 (진행 중일 때 토큰 정보가 있으면 상단 메타에 표시)
      if (p.progress && p.progress.tokens && p.progress.tokens.total > 0) {
        var pTot = Number(p.progress.tokens.total);
        var pIn = Number(p.progress.tokens.input || 0);
        var pOut = Number(p.progress.tokens.output || 0);
        var tokLabel = "⚡ " + (pTot >= 10000 ? (pTot / 10000).toFixed(1) + "만 토큰" : pTot.toLocaleString() + " 토큰");
        meta.appendChild(metaItem(tokLabel, "live-tokens", "실시간 누적 토큰: " + pTot.toLocaleString() + " (입력 " + pIn.toLocaleString() + " / 출력 " + pOut.toLocaleString() + ")"));
      }
    } else {
      // 대기 중인 카드는 대기 경과 시간 표시
      var cTime = parseLocalTime(p.created);
      if (cTime) {
        var waitSec = Math.max(0, Math.floor((Date.now() - cTime.getTime()) / 1000));
        var waitLive = metaItem("대기 중 " + formatDuration(waitSec), "elapsed live-elapsed", "대기열 대기 시간 (접수: " + (p.created || "") + ")");
        waitLive.setAttribute("data-start", String(cTime.getTime()));
        waitLive.setAttribute("data-label-prefix", "대기 중 ");
        meta.appendChild(waitLive);
      }
    }

    meta.appendChild(metaItem("bridge", "", "위임 경로"));
    if (p.task_id) { meta.appendChild(metaItem(p.task_id, "mono", "작업 ID")); }
    card.appendChild(meta);

    if (p.session) {
      card.appendChild(buildSessionMeta(p.session, p.session_id));
    }

    var dq = document.createElement("details");
    dq.className = "qa q";
    var sq = document.createElement("summary");
    var qBadge = document.createElement("span");
    qBadge.className = "qa-type-badge q-type";
    qBadge.textContent = "질문";
    sq.appendChild(qBadge);

    var qKw = extractQuestionKeyword(p.question);
    if (qKw) {
      var qKwSpan = document.createElement("span");
      qKwSpan.className = "qa-preview-keyword";
      qKwSpan.textContent = qKw;
      sq.appendChild(qKwSpan);
    }
    dq.appendChild(sq);

    var qb = document.createElement("div");
    qb.className = "body";
    var qImgInfo = extractImagesFromText(p.question);
    var effCwds = cwdListOf(p.cwd);              // 서버가 준 폴더 목록(옛 서버는 문자열 하나)
    if (!effCwds.length) effCwds = qImgInfo.cwds;   // 없으면 질문 맨 위의 @cwd 줄들
    var effectiveCwd = effCwds[0] || "";            // 상대 경로 이미지는 첫 번째 폴더 기준으로 찾는다
    var qGallery = createImageGallery(qImgInfo.images, effectiveCwd);
    if (qGallery) qb.appendChild(qGallery);
    var qContent = document.createElement("div");
    qContent.className = "qa-content";
    renderBody(qContent, p.question, effectiveCwd);
    qb.appendChild(qContent);
    dq.appendChild(qb);
    card.appendChild(dq);

    meta.appendChild(buildProcessButton(card.getAttribute("data-key"), pendingProcessOpts(p, effCwds)));

    var da = document.createElement("details");
    da.className = "qa a qa-pending-a";
    var sa = document.createElement("summary");
    var aBadge = document.createElement("span");
    aBadge.className = "qa-type-badge a-type";
    aBadge.textContent = "답변";
    sa.appendChild(aBadge);

    var aKwSpan = document.createElement("span");
    aKwSpan.className = "qa-preview-keyword";
    if (isProcessing) {
      aKwSpan.textContent = "응답을 만드는 중";
    } else {
      aKwSpan.textContent = "차례를 기다리는 중";
    }
    sa.appendChild(aKwSpan);
    da.appendChild(sa);

    var ab = document.createElement("div");
    ab.className = "body pending-body";
    var modelText = p.model ? " " + escapeHtml(p.model) + " 모델로" : "";
    ab.innerHTML = [
      '<div class="pending-status-wrap ' + escapeHtml(p.state) + '">',
      (isProcessing ? '  <span class="pending-spinner" aria-hidden="true"></span><span>agy가' + modelText + ' 응답을 만들고 있습니다. 끝나면 이 자리에 답변이 나옵니다.</span>' :
                      '  <span>동시에 돌릴 수 있는 수(기본 3개)를 넘었거나, 같은 세션·폴더의 앞 작업이 있어 기다리고 있습니다. 조건이 풀리면' + modelText + ' 자동으로 실행됩니다.</span>'),
      '</div>',
      (isProcessing ? buildProgressHtml(p.progress, effCwds) : "")
    ].join("");
    da.appendChild(ab);
    card.appendChild(da);

    return card;
  }

  // ==========================================================================
  // 3. 에이전트 인수인계 메인 뷰 (Handoff Messages Thread Rendering)
  // ==========================================================================

  function renderHandoffView() {
    var tree = buildHandoffTree(handoffChannels, claudeTree);
    var titles = findHandoffNodeTitles(tree, currentHandoffProject, currentHandoffSession);

    var displayTitle = "전체 프로젝트";
    if (currentHandoffProject) {
      if (currentHandoffSession) {
        displayTitle = titles.sessionTitle;
      } else {
        displayTitle = titles.projectName;
      }
    }
    if (els.handoffCurrentProjectTitle) {
      els.handoffCurrentProjectTitle.textContent = displayTitle;
    }

    // BRIEF.md 요약 아코디언 카드: 연결 안 됨 아래의 채널 세션(c:<채널>)을 골랐을 때만 그 채널의 brief를 보인다.
    if (els.handoffBriefCard && els.briefProjectName && els.handoffBriefContent) {
      var isChannelSession = (currentHandoffProject === QA_UNLINKED && currentHandoffSession && currentHandoffSession.indexOf("c:") === 0);
      var briefChannelName = isChannelSession ? currentHandoffSession.slice(2) : "";
      var briefChannelData = briefChannelName ? handoffChannels[briefChannelName] : null;

      if (briefChannelData && briefChannelData.brief && briefChannelData.brief.trim()) {
        els.briefProjectName.textContent = briefChannelData.name || briefChannelName;
        renderMarkdownBody(els.handoffBriefContent, briefChannelData.brief);
        els.handoffBriefCard.style.display = "block";
      } else {
        els.handoffBriefCard.style.display = "none";
      }
    }

    renderHandoffMessages();
  }

  function toggleHandoffMessage(cardEl, channel, msg, fileName) {
    var bodyEl = cardEl.querySelector(".handoff-card-body");
    if (!bodyEl) return;
    var headerEl = cardEl.querySelector(".handoff-card-header");
    var num = msg && msg.num != null ? msg.num : "";
    var openKey = channel + "/" + num;
    var isOpen = (bodyEl.style.display !== "none");
    if (isOpen) {
      bodyEl.style.display = "none";
      cardEl.classList.remove("is-open");
      if (headerEl) headerEl.setAttribute("aria-expanded", "false");
      delete openHandoffNums[openKey];
      return;
    }
    bodyEl.style.display = "block";
    cardEl.classList.add("is-open");
    if (headerEl) headerEl.setAttribute("aria-expanded", "true");
    openHandoffNums[openKey] = true;

    if (bodyEl.dataset.loaded === "true") return;

    if (!fileName) {
      fileName = handoffMsgFileOf(msg, handoffChannels[channel]);
    }
    if (!fileName) {
      bodyEl.innerHTML = '<p class="empty">메시지 파일(msg/' + escapeHtml(num) + '-*.md)을 찾을 수 없습니다.</p>';
      bodyEl.dataset.loaded = "true";
      return;
    }

    var cacheKey = channel + "/" + fileName;
    if (handoffMessageCache[cacheKey]) {
      renderMarkdownBody(bodyEl, handoffMessageCache[cacheKey]);
      bodyEl.dataset.loaded = "true";
      return;
    }

    bodyEl.innerHTML = '<div class="handoff-card-body-loading">메시지 본문을 불러오는 중...</div>';
    fetchText("/api/handoff/message?project=" + encodeURIComponent(channel) + "&file=" + encodeURIComponent(fileName))
      .then(function (markdown) {
        handoffMessageCache[cacheKey] = markdown;
        if (openHandoffNums[openKey]) {
          renderMarkdownBody(bodyEl, markdown);
          bodyEl.dataset.loaded = "true";
        }
      })
      .catch(function (err) {
        bodyEl.innerHTML = '<p class="empty">본문 로드 실패: ' + escapeHtml(err.message) + '</p>';
      });
  }

  function renderMarkdownBody(targetEl, markdown) {
    try {
      // 메시지 머리말(--- 번호/방향/시각/제목 ---)은 카드 머리에 이미 표시하므로 본문에서 뺀다.
      // 그대로 두면 marked 가 구분선과 큰 제목으로 그려 버린다.
      var body = String(markdown || "").replace(/^﻿?---\r?\n[\s\S]*?\r?\n---\r?\n/, "");
      targetEl.innerHTML = renderMarkdownWithMath(body);
      postProcessMarkdownElements(targetEl);
    } catch (e) {
      targetEl.innerHTML = "<pre>" + escapeHtml(markdown) + "</pre>";
    }
  }

  // 머리 범례와 방향 필터의 이름을 지금 보는 메시지들의 최근 모델로(없으면 Claude/agy).
  function updateHandoffPartyLabels(items) {
    var latest = handoffLatestModels((items || []).map(function (it) { return it.msg; }));
    var claudeName = formatModelName(latest.claude) || "Claude";
    var agyName = formatModelName(latest.agy) || "agy";
    if (els.handoffLegendClaude) els.handoffLegendClaude.textContent = claudeName + " 보냄";
    if (els.handoffLegendAgy) els.handoffLegendAgy.textContent = agyName + " 보냄";
    if (els.handoffDirFilter) {
      for (var i = 0; i < els.handoffDirFilter.options.length; i++) {
        var o = els.handoffDirFilter.options[i];
        if (o.value === "c2a") o.textContent = claudeName + " → " + agyName;
        else if (o.value === "a2c") o.textContent = agyName + " → " + claudeName;
      }
    }
  }

  // 자동 이어가기 상태 줄: 지금 보는 메시지가 채널 하나의 것일 때만 보인다. 상태는 /api/handoff/project 의 auto.
  function handoffAutoText(auto, nowMs) {
    if (!auto) return null;
    if (!auto.enabled) return { state: "꺼짐", detail: "이 채널은 agy 가 자동으로 답하지 않습니다.", kind: "off" };
    if (auto.halted) return { state: "멈춤 · 사용자 확인 필요", detail: auto.haltedReason || "자동 왕복 한도에 도달했습니다.", kind: "halted" };
    var flight = Array.isArray(auto.inFlight) && auto.inFlight.length ? auto.inFlight[0] : null;
    if (flight) {
      var started = Date.parse(String(flight.at || "").replace(" ", "T"));
      var mins = isNaN(started) ? null : Math.max(0, Math.round(((nowMs || Date.now()) - started) / 60000));
      return { state: "켜짐 · agy 처리 중", detail: "#" + flight.num + (mins == null ? "" : " · " + mins + "분 경과") + " · 왕복 " + auto.rounds + "/" + auto.maxRounds, kind: "busy" };
    }
    return { state: "켜짐", detail: "왕복 " + auto.rounds + "/" + auto.maxRounds + " (최근 " + auto.windowMinutes + "분) · Claude 메시지에 agy 가 자동으로 답합니다.", kind: "on" };
  }

  function renderHandoffAutoBar(items) {
    if (!els.handoffAutoBar) return;
    var channels = {};
    var count = 0;
    (items || []).forEach(function (it) { if (it.channel && !channels[it.channel]) { channels[it.channel] = true; count++; } });
    var channel = count === 1 ? Object.keys(channels)[0] : "";
    var data = channel ? handoffChannels[channel] : null;
    var txt = data ? handoffAutoText(data.auto, Date.now()) : null;
    if (!txt) { els.handoffAutoBar.style.display = "none"; els.handoffAutoBar.removeAttribute("data-channel"); return; }
    els.handoffAutoBar.style.display = "flex";
    els.handoffAutoBar.setAttribute("data-channel", channel);
    els.handoffAutoBar.setAttribute("data-kind", txt.kind);
    if (els.handoffAutoState) els.handoffAutoState.textContent = "자동 이어가기 · " + txt.state;
    if (els.handoffAutoDetail) els.handoffAutoDetail.textContent = txt.detail;
    if (els.handoffAutoToggle) {
      els.handoffAutoToggle.textContent = data.auto.enabled ? "끄기" : "켜기";
      els.handoffAutoToggle.setAttribute("data-action", data.auto.enabled ? "off" : "on");
    }
    if (els.handoffAutoReset) els.handoffAutoReset.style.display = txt.kind === "halted" ? "" : "none";
  }

  function postHandoffAuto(action) {
    var channel = els.handoffAutoBar ? els.handoffAutoBar.getAttribute("data-channel") : "";
    if (!channel) return;
    fetch("/api/handoff/auto?name=" + encodeURIComponent(channel) + "&action=" + encodeURIComponent(action), { method: "POST", headers: { "X-Samjil-Viewer": "1" } })
      .then(function (res) {
        if (!res.ok) throw new Error("HTTP " + res.status);
        return loadHandoffProjects(true);
      })
      .catch(function (err) {
        if (els.handoffAutoDetail) els.handoffAutoDetail.textContent = "요청에 실패했습니다: " + err.message;
      });
  }

  function renderHandoffMessages() {
    if (!els.handoffCards) return;

    var items = handoffMessagesOf(handoffChannels, claudeTree, currentHandoffProject, currentHandoffSession);
    updateHandoffPartyLabels(items);
    renderHandoffAutoBar(items);

    var q = (els.handoffSearch ? els.handoffSearch.value : "").trim().toLowerCase();
    var dirFilter = els.handoffDirFilter ? els.handoffDirFilter.value : "";
    var statusFilter = els.handoffStatusFilter ? els.handoffStatusFilter.value : "";

    var filteredItems = items.filter(function (it) {
      var m = it.msg;
      if (!m) return false;
      if (dirFilter && m.dir !== dirFilter) return false;
      if (statusFilter && m.status !== statusFilter) return false;
      if (q) {
        var match = (m.num && String(m.num).toLowerCase().indexOf(q) >= 0) ||
                    (m.title && m.title.toLowerCase().indexOf(q) >= 0) ||
                    (m.time && m.time.indexOf(q) >= 0) ||
                    (m.status && m.status.indexOf(q) >= 0);
        if (!match) return false;
      }
      return true;
    });

    if (els.handoffCurrentProjectCount) {
      els.handoffCurrentProjectCount.textContent = "메시지 " + filteredItems.length + "개";
    }

    var sortedItems = filteredItems.slice().reverse();

    if (sortedItems.length === 0) {
      if (items.length === 0) {
        els.handoffCards.innerHTML = '<p class="empty">표시할 메시지가 없습니다.</p>';
      } else {
        els.handoffCards.innerHTML = '<p class="empty">조건에 일치하는 핸드오프 메시지가 없습니다.</p>';
      }
      updateTopbarMeta();
      return;
    }

    var frag = document.createDocumentFragment();
    sortedItems.forEach(function (it) {
      var m = it.msg;
      var channel = it.channel;
      var fileName = it.file;
      var openKey = channel + "/" + m.num;

      var card = document.createElement("div");
      var party = dirParty(m.dir);
      card.className = "handoff-card" + (party ? " from-" + party : "");
      card.dataset.num = m.num;
      card.dataset.channel = channel;

      // [#번호][제목 / 보낸 쪽 → 받는 쪽][시각, 상태 진행 표시]
      var header = document.createElement("div");
      header.className = "handoff-card-header";
      header.innerHTML = [
        '<span class="handoff-num">#' + escapeHtml(m.num) + '</span>',
        '<div class="handoff-card-header-left">',
        '  <span class="handoff-title" title="' + escapeHtml(m.title || "") + '"><span class="handoff-channel">' + escapeHtml(channel) + '</span>' + escapeHtml(m.title || "(제목 없음)") + '</span>',
        '  <span class="handoff-dir">' + dirLabelHtml(m.dir, m, channel) + '</span>',
        '</div>',
        '<div class="handoff-card-header-right">',
        '  <span class="handoff-time">' + escapeHtml(m.time || "") + '</span>',
        '  ' + stepsHtml(m.status),
        '</div>'
      ].join("");
      makeActivatable(header);
      header.setAttribute("aria-expanded", openHandoffNums[openKey] ? "true" : "false");

      var body = document.createElement("div");
      body.className = "handoff-card-body md";

      if (openHandoffNums[openKey]) {
        body.style.display = "block";
        card.classList.add("is-open");
        if (fileName) {
          var cacheKey = channel + "/" + fileName;
          if (handoffMessageCache[cacheKey]) {
            renderMarkdownBody(body, handoffMessageCache[cacheKey]);
            body.dataset.loaded = "true";
          } else {
            body.innerHTML = '<div class="handoff-card-body-loading">메시지 본문을 불러오는 중...</div>';
            fetchText("/api/handoff/message?project=" + encodeURIComponent(channel) + "&file=" + encodeURIComponent(fileName))
              .then(function (md) {
                handoffMessageCache[cacheKey] = md;
                if (openHandoffNums[openKey]) {
                  renderMarkdownBody(body, md);
                  body.dataset.loaded = "true";
                }
              })
              .catch(function (err) {
                body.innerHTML = '<p class="empty">본문 로드 실패: ' + escapeHtml(err.message) + '</p>';
              });
          }
        } else {
          body.innerHTML = '<p class="empty">메시지 파일(msg/' + escapeHtml(m.num) + '-*.md)을 찾을 수 없습니다.</p>';
          body.dataset.loaded = "true";
        }
      } else {
        body.style.display = "none";
      }

      header.addEventListener("click", function () {
        toggleHandoffMessage(card, channel, m, fileName);
      });

      card.appendChild(header);
      card.appendChild(body);
      frag.appendChild(card);
    });

    els.handoffCards.innerHTML = "";
    els.handoffCards.appendChild(frag);
    updateTopbarMeta();
  }

  // ==========================================================================
  // Full Refresh Cycle
  // ==========================================================================

  var lastClaudeTreeKey = "";

  function claudeTreeKeyOf(data) {
    if (!data || typeof data !== "object") return "";
    var pParts = [];
    var projects = Array.isArray(data.projects) ? data.projects : [];
    for (var i = 0; i < projects.length; i++) {
      var p = projects[i] || {};
      var sParts = [];
      var sessions = Array.isArray(p.sessions) ? p.sessions : [];
      for (var j = 0; j < sessions.length; j++) {
        var s = sessions[j] || {};
        sParts.push([s.id || "", s.title || "", s.cwd || "", s.lastActivity || "", s.archived ? 1 : 0].join("~"));
      }
      pParts.push((p.id || "") + ":" + (p.name || "") + "[" + sParts.join(",") + "]");
    }
    var uParts = [];
    var ungrouped = Array.isArray(data.ungrouped) ? data.ungrouped : [];
    for (var u = 0; u < ungrouped.length; u++) {
      var us = ungrouped[u] || {};
      uParts.push([us.id || "", us.title || "", us.cwd || "", us.lastActivity || "", us.archived ? 1 : 0].join("~"));
    }
    var tl = data.taskLinks || {};
    var tlKeys = Object.keys(tl).sort();
    var tlParts = [];
    for (var t = 0; t < tlKeys.length; t++) { tlParts.push(tlKeys[t] + "=" + tl[tlKeys[t]]); }

    var hl = data.handoffLinks || {};
    var hlKeys = Object.keys(hl).sort();
    var hlParts = [];
    for (var h = 0; h < hlKeys.length; h++) { hlParts.push(hlKeys[h] + "=" + hl[hlKeys[h]]); }

    return [pParts.join("|"), uParts.join("|"), tlParts.join(","), hlParts.join(",")].join("#");
  }

  function loadClaudeTree() {
    return fetchJson("/api/claude/tree").then(function (data) {
      if (data && typeof data === "object") {
        var newKey = claudeTreeKeyOf(data);
        var changed = (newKey !== lastClaudeTreeKey);
        lastClaudeTreeKey = newKey;
        claudeTree = data;
        return { tree: claudeTree, changed: changed };
      }
      return { tree: claudeTree, changed: false };
    }).catch(function () {
      return { tree: claudeTree, changed: false };
    });
  }

  function refresh(force) {
    return Promise.all([
      loadSystemStatus(),
      loadAllQa(force),
      loadPending(),
      loadHandoffProjects(force),
      loadClaudeTree()
    ]).then(function (results) {
      var qaRes = results[1] || { changed: false };
      var pList = results[2] || [];
      var treeRes = results[4] || { changed: false };

      var pKey = pendingKeyOf(pList);
      var pChanged = (pKey !== lastPendingKey);
      lastPendingKey = pKey;
      pendingItems = pList;

      var qaNeedsRender = Boolean(force || qaRes.changed || pChanged || treeRes.changed);

      if (qaNeedsRender) {
        populateModelFilter();
      }
      // 사이드바 트리는 스크롤을 보존하며 상대 시간("3분 전" 등)을 매번 최신으로 갱신한다
      renderQaTree();
      renderHandoffTree();

      if (currentNav === "dashboard") {
        renderDashboard();
      } else if (currentNav === "qa") {
        if (qaNeedsRender) {
          applyQaFilters();
        } else {
          updateQaHeader();
          renderProcessDialog();
        }
      } else if (currentNav === "handoff") {
        if (force || treeRes.changed) {
          renderHandoffView();
        }
      }
      updateTopbarMeta();
    }).catch(function (err) {
      console.warn("Refresh error:", err);
      if (els.topbarCount) {
        els.topbarCount.textContent = "갱신 실패: " + err.message;
      }
      if (currentNav === "dashboard") { renderNow(); }
    });
  }

  function scheduleAutoRefresh() {
    if (refreshTimer) { clearInterval(refreshTimer); refreshTimer = null; }
    if (els.autoRefresh && els.autoRefresh.checked) {
      refreshTimer = setInterval(function () { refresh(false); }, AUTO_REFRESH_MS);
    }
  }

  // ==========================================================================
  // Event Bindings & Initializers
  // ==========================================================================

  function bindEvents() {
    // 사이드바 브랜드/로고 클릭 시 루트(대시보드) 이동
    if (els.sidebarBrand) {
      els.sidebarBrand.addEventListener("click", function (e) {
        if (e.ctrlKey || e.metaKey || e.shiftKey || e.button === 1) {
          return;
        }
        e.preventDefault();
        if (currentNav === "dashboard") {
          if (els.viewDashboard) els.viewDashboard.scrollTo({ top: 0, behavior: "smooth" });
          window.scrollTo({ top: 0, behavior: "smooth" });
          return;
        }
        switchNav("dashboard");
        if (els.viewDashboard) els.viewDashboard.scrollTo({ top: 0 });
        window.scrollTo({ top: 0 });
      });
    }

    // 1차 네비게이션 버튼
    if (els.navBtnDashboard) els.navBtnDashboard.addEventListener("click", function () { switchNav("dashboard"); });
    if (els.navBtnQa) els.navBtnQa.addEventListener("click", function () { switchNav("qa"); });
    if (els.navBtnHandoff) els.navBtnHandoff.addEventListener("click", function () { switchNav("handoff"); });

    // 사이드바 토글 버튼 (데스크톱 접기 / 모바일 햄버거)
    if (els.sidebarCollapseBtn) {
      els.sidebarCollapseBtn.addEventListener("click", function () {
        if (els.appSidebar) {
          var isCollapsed = els.appSidebar.classList.toggle("collapsed");
          try { localStorage.setItem("samjil_sidebar_collapsed", isCollapsed ? "true" : "false"); } catch (e) {}
        }
      });
    }

    if (els.topbarMenuToggle) {
      els.topbarMenuToggle.addEventListener("click", function () {
        if (els.appSidebar) els.appSidebar.classList.toggle("open");
      });
    }

    // 대시보드 내 "모두 보기" 링크
    if (els.btnViewAllQa) {
      els.btnViewAllQa.addEventListener("click", function () {
        selectQaProject("");
        switchNav("qa");
      });
    }
    if (els.btnViewAllHandoff) {
      els.btnViewAllHandoff.addEventListener("click", function () {
        switchNav("handoff");
      });
    }

    // QA 세션 사이드바 검색 및 필터
    if (els.qaSessionSearch) els.qaSessionSearch.addEventListener("input", renderQaTree);
    if (els.modelFilter) els.modelFilter.addEventListener("change", applyQaFilters);
    if (els.statusFilter) els.statusFilter.addEventListener("change", applyQaFilters);
    if (els.qaSearch) els.qaSearch.addEventListener("input", applyQaFilters);
    if (els.loadMoreBtn) els.loadMoreBtn.addEventListener("click", renderMoreQa);

    // Handoff 사이드바 검색 및 필터
    if (els.handoffProjectSearch) els.handoffProjectSearch.addEventListener("input", renderHandoffTree);
    if (els.handoffDirFilter) els.handoffDirFilter.addEventListener("change", renderHandoffMessages);
    if (els.handoffAutoToggle) els.handoffAutoToggle.addEventListener("click", function () { postHandoffAuto(els.handoffAutoToggle.getAttribute("data-action") || "off"); });
    if (els.handoffAutoReset) els.handoffAutoReset.addEventListener("click", function () { postHandoffAuto("reset"); });
    if (els.handoffStatusFilter) els.handoffStatusFilter.addEventListener("change", renderHandoffMessages);
    if (els.handoffSearch) els.handoffSearch.addEventListener("input", renderHandoffMessages);

    // 푸터 새로고침 & 자동 갱신
    if (els.refreshBtn) els.refreshBtn.addEventListener("click", function () { refresh(true); });
    if (els.cards) {
      els.cards.addEventListener("click", function (e) {
        var procBtn = e.target && e.target.closest ? e.target.closest(".proc-open") : null;
        if (procBtn) { openProcessDialog(procBtn.getAttribute("data-proc-key")); return; }
        var sumEl = e.target && e.target.closest ? e.target.closest("summary") : null;
        var d = sumEl ? sumEl.parentNode : null;
        if (!d || !d.classList || !d.classList.contains("qa") || !d.parentNode || !d.parentNode.getAttribute("data-key")) return;
        qaOpenOverrides[qaSectionKey(d)] = !d.open;
      });
    }
    if (els.watcherStartBtn) els.watcherStartBtn.addEventListener("click", startWatcher);
    if (els.autoRefresh) els.autoRefresh.addEventListener("change", scheduleAutoRefresh);

    // role="button" 으로 표시한 div 항목은 Enter/Space 로도 누를 수 있게 한다.
    document.addEventListener("keydown", function (e) {
      if (e.key !== "Enter" && e.key !== " ") return;
      var t = e.target;
      if (!t || t.tagName === "BUTTON" || t.tagName === "INPUT" || t.tagName === "SELECT" || t.tagName === "TEXTAREA") return;
      if (t.getAttribute && t.getAttribute("role") === "button") {
        e.preventDefault();
        t.click();
      }
    });

    // 브라우저 해시 변경 감지 (뒤로가기/앞으로가기)
    window.addEventListener("hashchange", function () {
      var parsed = parseHash();
      if (parsed.nav !== currentNav) {
        switchNav(parsed.nav, false);
      }
      if (parsed.nav === "qa") {
        var projChanged = (parsed.project !== currentQaProject);
        var sessChanged = (parsed.session !== currentQaSession);
        var agyChanged = (parsed.agy !== currentQaAgy);
        if (projChanged || sessChanged || agyChanged) {
          if (projChanged || sessChanged) {
            selectQaSession(parsed.session, parsed.project);
          }
          currentQaAgy = parsed.agy || "";
          renderQaAgyChips();
          applyQaFilters();
        }
      } else if (parsed.nav === "handoff" && (parsed.project !== currentHandoffProject || parsed.session !== currentHandoffSession)) {
        selectHandoffSession(parsed.session, parsed.project);
      }
    });
  }

  // 초기화 실행
  initImagePopups();
  initTreeSortSelects();
  bindEvents();

  // 이전 사이드바 접힘 상태 복원
  try {
    if (localStorage.getItem("samjil_sidebar_collapsed") === "true" && els.appSidebar) {
      els.appSidebar.classList.add("collapsed");
    }
  } catch (e) {}

  // 초기 라우트 파싱
  var initialRoute = parseHash();
  if (initialRoute.nav === "qa") {
    if (initialRoute.session) { currentQaSession = initialRoute.session; }
    if (initialRoute.project) { currentQaProject = initialRoute.project; }
    if (initialRoute.agy) { currentQaAgy = initialRoute.agy; }
  } else if (initialRoute.nav === "handoff") {
    if (initialRoute.session) { currentHandoffSession = initialRoute.session; }
    if (initialRoute.project) { currentHandoffProject = initialRoute.project; }
  }

  // 최초 네비게이션 적용
  switchNav(initialRoute.nav, false);

  // 최초 데이터 로드 및 타이머 시작
  refresh(true).then(scheduleAutoRefresh);
})();
