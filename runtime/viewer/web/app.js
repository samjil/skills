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
    modelFilter:          document.getElementById("modelfilter"),
    statusFilter:         document.getElementById("statusfilter"),

    // Handoff 프로젝트 사이드바
    handoffProjectCount:  document.getElementById("handoff-project-count"),
    handoffProjectSearch: document.getElementById("handoff-project-search"),
    handoffProjectList:   document.getElementById("handoff-project-list"),
    handoffDirFilter:     document.getElementById("handoff-dir-filter"),
    handoffStatusFilter:  document.getElementById("handoff-status-filter"),

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
  var currentQaSession = "";    // ""(전체) | "__none__"(단발성) | 세션명
  var currentHandoffProject = "";

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
      return (p.task_id || "") + ":" + (p.state || "");
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
    var matchQa = hash.match(/^#\/qa(?:\?session=(.*))?$/);
    if (matchQa) {
      var sess = matchQa[1] ? decodeURIComponent(matchQa[1]) : "";
      return { nav: "qa", session: sess, project: "" };
    }
    var matchHandoff = hash.match(/^#\/handoff(?:\?project=(.*))?$/);
    if (matchHandoff) {
      var proj = matchHandoff[1] ? decodeURIComponent(matchHandoff[1]) : "";
      return { nav: "handoff", session: "", project: proj };
    }
    return { nav: "dashboard", session: "", project: "" };
  }

  function updateHash() {
    var newHash = "#/" + currentNav;
    if (currentNav === "qa" && currentQaSession) {
      newHash += "?session=" + encodeURIComponent(currentQaSession);
    } else if (currentNav === "handoff" && currentHandoffProject) {
      newHash += "?project=" + encodeURIComponent(currentHandoffProject);
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
      if (!currentHandoffProject && handoffProjects.length > 0) {
        selectHandoffProject(handoffProjects[0].name);
      } else {
        renderHandoffMessages();
      }
    }
  }

  function updateBreadcrumbs() {
    if (!els.topbarCategory || !els.topbarCurrent) return;

    if (currentNav === "dashboard") {
      els.topbarCategory.textContent = "홈";
      els.topbarCurrent.textContent = "대시보드";
    } else if (currentNav === "qa") {
      els.topbarCategory.textContent = "위임 실행 기록";
      if (!currentQaSession) {
        els.topbarCurrent.textContent = "전체 세션 피드";
      } else if (currentQaSession === "__none__") {
        els.topbarCurrent.textContent = "단발성 작업 (세션 없음)";
      } else {
        els.topbarCurrent.textContent = currentQaSession;
      }
    } else if (currentNav === "handoff") {
      els.topbarCategory.textContent = "에이전트 인수인계";
      els.topbarCurrent.textContent = currentHandoffProject || "프로젝트 선택";
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
      var msgs = (currentHandoffData && currentHandoffData.messages) ? currentHandoffData.messages.length : 0;
      els.topbarCount.textContent = currentHandoffProject ? (msgs + "개 메시지") : (handoffProjects.length + "개 프로젝트");
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
  function loadAllQa(force) {
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

  // 인수인계 프로젝트 목록 로드
  function loadHandoffProjects(force) {
    return fetchJson("/api/handoff/projects").then(function (projects) {
      if (!Array.isArray(projects)) { projects = []; }
      handoffProjects = projects;
      renderHandoffProjectList();
      if (!currentHandoffProject && projects.length > 0) {
        currentHandoffProject = projects[0].name;
      }
      if (currentHandoffProject) {
        loadHandoffProject(currentHandoffProject);
      }
      return projects;
    }).catch(function (err) {
      console.warn("Handoff projects load error:", err);
      return [];
    });
  }

  // 인수인계 특정 프로젝트 상세 로드
  function loadHandoffProject(projectName) {
    if (!projectName) { return Promise.resolve(null); }
    currentHandoffProject = projectName;
    updateBreadcrumbs();
    updateHash();

    return fetchJson("/api/handoff/project?name=" + encodeURIComponent(projectName))
      .then(function (data) {
        currentHandoffData = data;
        renderHandoffProjectList();
        renderHandoffView();
        return data;
      })
      .catch(function (err) {
        if (els.handoffCards) {
          els.handoffCards.innerHTML = '<p class="empty">프로젝트 로드 실패: ' + escapeHtml(err.message) + '</p>';
        }
        return null;
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

  function renderQaSessionList() {
    if (!els.qaSessionList) return;

    var sessions = groupQaSessions();
    var q = (els.qaSessionSearch.value || "").trim().toLowerCase();

    var filteredSessions = sessions.filter(function (s) {
      if (s.name === "__none__") return true;
      if (q && s.name.toLowerCase().indexOf(q) === -1) return false;
      return true;
    });

    if (els.qaSessionCount) {
      els.qaSessionCount.textContent = sessions.length;
    }

    var frag = document.createDocumentFragment();

    // 1. [전체 세션 피드] 항목
    var allItem = document.createElement("div");
    allItem.className = "session-item" + (currentQaSession === "" ? " active" : "");
    allItem.dataset.session = "";
    allItem.innerHTML = [
      '<span class="session-icon">' + icon("feed") + '</span>',
      '<div class="session-info">',
      '  <span class="session-name">전체 세션 피드</span>',
      '  <span class="session-sub">모든 위임을 시간순으로</span>',
      '</div>',
      '<span class="session-badge">' + (allItems.length + pendingItems.length) + '</span>'
    ].join("");
    makeActivatable(allItem);
    allItem.onclick = function () { selectQaSession(""); };
    frag.appendChild(allItem);

    // 2. 개별 세션 항목들
    var noneSessionObj = null;
    filteredSessions.forEach(function (s) {
      if (s.name === "__none__") {
        noneSessionObj = s;
        return;
      }

      var item = document.createElement("div");
      var isActive = (currentQaSession === s.name);
      item.className = "session-item" + (isActive ? " active" : "");
      item.dataset.session = s.name;

      var subText = formatRelativeTime(s.latestTime);
      var badgeHtml = '<span class="session-badge">' + (s.total + s.pending) + '</span>';
      if (s.pending > 0) {
        badgeHtml = '<span class="pending-pulse-dot" title="진행/대기 중 ' + s.pending + '건"></span> ' + badgeHtml;
      }

      item.innerHTML = [
        '<span class="session-icon">' + icon("thread") + '</span>',
        '<div class="session-info">',
        '  <span class="session-name" title="' + escapeHtml(s.name) + '">' + escapeHtml(s.name) + '</span>',
        '  <span class="session-sub">' + subText + (s.errors > 0 ? '  <span class="err-count">실패 ' + s.errors + '</span>' : '') + '</span>',
        '</div>',
        badgeHtml
      ].join("");

      makeActivatable(item);
      item.onclick = function () { selectQaSession(s.name); };
      frag.appendChild(item);
    });

    // 3. [단발성 작업 - 세션 없음] 항목 (있을 경우)
    if (noneSessionObj && (!q || "단발성".indexOf(q) >= 0 || "세션 없음".indexOf(q) >= 0)) {
      var noneItem = document.createElement("div");
      noneItem.className = "session-item" + (currentQaSession === "__none__" ? " active" : "");
      noneItem.dataset.session = "__none__";
      noneItem.innerHTML = [
        '<span class="session-icon">' + icon("single") + '</span>',
        '<div class="session-info">',
        '  <span class="session-name">단발성 작업 (세션 없음)</span>',
        '  <span class="session-sub">' + formatRelativeTime(noneSessionObj.latestTime) + '</span>',
        '</div>',
        '<span class="session-badge">' + (noneSessionObj.total + noneSessionObj.pending) + '</span>'
      ].join("");
      makeActivatable(noneItem);
      noneItem.onclick = function () { selectQaSession("__none__"); };
      frag.appendChild(noneItem);
    }

    els.qaSessionList.innerHTML = "";
    els.qaSessionList.appendChild(frag);
  }

  function selectQaSession(sessionName) {
    currentQaSession = sessionName || "";
    renderQaSessionList();
    updateBreadcrumbs();
    updateHash();
    applyQaFilters();
  }

  // ==========================================================================
  // Handoff Side-Panel List & Project Selection
  // ==========================================================================

  function renderHandoffProjectList() {
    if (!els.handoffProjectList) return;

    var q = (els.handoffProjectSearch.value || "").trim().toLowerCase();
    var filtered = handoffProjects.filter(function (p) {
      if (q && p.name.toLowerCase().indexOf(q) === -1) return false;
      return true;
    });

    if (els.handoffProjectCount) {
      els.handoffProjectCount.textContent = handoffProjects.length;
    }

    if (filtered.length === 0) {
      els.handoffProjectList.innerHTML = '<p class="empty-hint">조건에 맞는 프로젝트가 없습니다.</p>';
      return;
    }

    var frag = document.createDocumentFragment();
    filtered.forEach(function (p) {
      var item = document.createElement("div");
      var isActive = (currentHandoffProject === p.name);
      item.className = "project-item" + (isActive ? " active" : "");
      item.dataset.project = p.name;

      var subText = formatRelativeTime(p.updated);
      item.innerHTML = [
        '<span class="project-icon">' + icon("folder") + '</span>',
        '<div class="project-info">',
        '  <span class="project-name" title="' + escapeHtml(p.name) + '">' + escapeHtml(p.name) + '</span>',
        '  <span class="project-sub">' + subText + '</span>',
        '</div>',
        '<span class="project-badge">' + (p.msgCount || 0) + '</span>'
      ].join("");

      makeActivatable(item);
      item.onclick = function () { selectHandoffProject(p.name); };
      frag.appendChild(item);
    });

    els.handoffProjectList.innerHTML = "";
    els.handoffProjectList.appendChild(frag);
  }

  function selectHandoffProject(projectName) {
    if (currentHandoffProject === projectName && currentHandoffData) {
      renderHandoffProjectList();
      return;
    }
    loadHandoffProject(projectName);
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
      els2[i].textContent = formatDuration((Date.now() - Number(els2[i].getAttribute("data-start"))) / 1000);
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
    for (var i = 0; i < active.length; i++) {
      if (active[i].state === "processing") { running = active[i]; break; }
    }
    var queued = active.length - (running ? 1 : 0);

    var state, statusText, title;
    var aside = "";
    var meta = [];
    var clickSession = null;

    if (!isServerOnline) {
      state = "offline";
      statusText = "뷰어 서버에 연결할 수 없습니다";
      title = "serve-viewer.ps1이 실행 중인지 확인하세요";
      meta.push('<span><code>~/.samjil/viewer/serve-viewer.ps1</code>을 다시 실행하면 이 화면이 이어서 갱신됩니다.</span>');
    } else if (running) {
      state = "running";
      statusText = "agy가 작업 중";
      if (queued > 0) { aside = "뒤에 " + queued + "건 대기"; }
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
      clickSession = running.session || "__none__";
    } else if (systemStatus && systemStatus.watcherAlive) {
      state = "idle";
      statusText = "agy 워처 대기 중";
      var last = allItems[0];
      if (last) {
        title = "마지막 위임: " + (extractQuestionKeyword(last.question) || "(질문 내용 없음)");
        meta.push('<span>' + formatRelativeTime(last.timestamp) + '</span>');
        meta.push('<span>' + (isOkStatus(last) ? "성공" : (last.status ? "실패 (" + escapeHtml(last.status) + ")" : "상태 미기록")) + '</span>');
        if (recordModel(last)) { meta.push('<span><code>' + escapeHtml(recordModel(last)) + '</code></span>'); }
        clickSession = last.session || "__none__";
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

    els.nowTitle.classList.toggle("is-link", clickSession !== null);
    if (clickSession !== null) {
      makeActivatable(els.nowTitle);
      els.nowTitle.onclick = function () {
        selectQaSession(clickSession);
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

  function dirLabelHtml(dir) {
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

  function goQaSession(session) {
    return function () {
      selectQaSession(session || "__none__");
      switchNav("qa");
    };
  }

  function goHandoffProject(name) {
    return function () {
      selectHandoffProject(name);
      switchNav("handoff");
    };
  }

  function handoffRow(projectName, m, subPrefix) {
    var waitText = "";
    if (m.status === "보냄" || m.status === "읽음") {
      waitText = m.dir === "c2a" ? '<span class="who-agy">agy 처리 대기</span>' :
                 (m.dir === "a2c" ? '<span class="who-claude">Claude 처리 대기</span>' : "");
    }
    return buildRow({
      party: dirParty(m.dir),
      time: m.time,
      titleHtml: '<span class="num">#' + escapeHtml(m.num) + '</span>' + escapeHtml(m.title || "(제목 없음)"),
      subHtml: (subPrefix ? '<span>' + subPrefix + '</span>' : "") +
        '<span>' + escapeHtml(projectName) + '</span>' +
        (waitText || '<span>' + dirLabelHtml(m.dir) + '</span>'),
      sideHtml: stepsHtml(m.status),
      onClick: goHandoffProject(projectName)
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
            onClick: goQaSession(r.session)
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
            onClick: goQaSession(p.session)
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
            onClick: goQaSession(r.session)
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
        ["인수인계 프로젝트", handoffProjects.length + "개"],
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

  function applyQaFilters() {
    var q = (els.qaSearch ? els.qaSearch.value : "").trim().toLowerCase();
    var model = els.modelFilter ? els.modelFilter.value : "";
    var status = els.statusFilter ? els.statusFilter.value : "";
    var session = currentQaSession;

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
        // 모델 필터
        if (model && p.model !== model) return false;
        // 세션 필터
        if (session === "__none__" && p.session) return false;
        if (session && session !== "__none__" && p.session !== session) return false;
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
      if (session === "__none__" && r.session) return false;
      if (session && session !== "__none__" && r.session !== session) return false;
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

    // 헤더 건수는 filteredQa/filteredPending 을 읽으므로 반드시 필터 계산 뒤에 갱신한다.
    // (앞에서 부르면 직전 값이 표시되어, 대시보드에서 막 넘어왔을 때 "0건"으로 보였다.)
    updateQaHeader(session);

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
    updateTopbarMeta();
  }

  // 질문/과정/답변 구역의 펼침 상태.
  //   기본: 맨 위(가장 최근) 카드의 답변만 펼치고, 나머지는 질문·과정·답변 모두 접은 채로 시작한다.
  //   사용자가 직접 열거나 닫은 구역만 qaOpenOverrides 에 기억해서, 5초마다 카드를 다시 그려도 그대로 유지한다.
  //   (예전에는 그리기 직전의 "현재 상태"를 통째로 저장했는데, 그러면 기본으로 펼쳐졌던 카드도 사용자가 연 것으로
  //   기억돼 새 카드가 생겨도 이전 카드가 계속 펼쳐 있었다.)
  var qaOpenOverrides = {};   // "<카드 키>|q" / "|p" / "|a" -> true(열었음) / false(닫았음)

  function qaSectionKey(d) {
    var type = d.classList.contains("q") ? "q" : (d.classList.contains("p") ? "p" : "a");
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

  function updateQaHeader(session) {
    if (!els.qaCurrentSessionTitle) return;

    if (!session) {
      els.qaCurrentSessionTitle.textContent = "전체 세션 피드";
    } else if (session === "__none__") {
      els.qaCurrentSessionTitle.textContent = "단발성 작업 (세션 없음)";
    } else {
      els.qaCurrentSessionTitle.textContent = session;
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

  function extractImagesFromText(text) {
    if (!text) return { cwd: "", images: [] };
    var cwdMatch = text.match(/@cwd:\s*([^\r\n]+)/i);
    var cwd = cwdMatch ? cwdMatch[1].trim() : "";
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

    return { cwd: cwd, images: candidates };
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

    try {
      var codeEls = container.querySelectorAll("code");
      codeEls.forEach(function (code) {
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
    } catch (err) {}
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

  // 작업 폴더(@cwd) 아래 경로는 폴더 이름을 빼고 보인다. 예) C:\workpp\src.py -> src.py (폴더 자체는 ".")
  // 명령 안에 적힌 경로도 같은 규칙이다. work2 처럼 이름만 비슷한 폴더는 건드리지 않는다. 전체 경로는 마우스를 올리면 보인다.
  function shortenPathsForCwd(text, cwd) {
    var src = String(text == null ? "" : text);
    var base = String(cwd || "").trim().replace(/[\\/]+$/, "");
    if (!src || !base) return src;
    var esc = base.replace(/[.*+?^${}()|[\]\\\/]/g, function (ch) { return (ch === "\\" || ch === "/") ? "[\\\\/]" : "\\" + ch; });
    var re = new RegExp("(^|[\\s\"'(=])" + esc + "([\\\\/]+|(?=$|[\\s\"')]))", "gi");
    var out = src.replace(re, function (m, pre, sep) { return sep ? pre : pre + "."; });
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
      if (cwd && shown !== st.detail) tip.push("작업 폴더(@cwd): " + cwd + " — 목록에는 이 폴더 아래 경로만 줄여 보입니다");
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

  // opts: { steps: 배열|null, convId: 대화 id, live: 진행 중, waiting: 아직 시작 안 함, cwd: 작업 폴더(경로를 줄여 보이는 기준) }
  function buildProcessDetails(opts) {
    var d = document.createElement("details");
    d.className = "qa p";
    var sum = document.createElement("summary");
    var badgeEl = document.createElement("span");
    badgeEl.className = "qa-type-badge p-type";
    badgeEl.textContent = "과정";
    sum.appendChild(badgeEl);
    var kw = document.createElement("span");
    kw.className = "qa-preview-keyword";
    sum.appendChild(kw);
    d.appendChild(sum);
    var body = document.createElement("div");
    body.className = "body";
    d.appendChild(body);

    var steps = Array.isArray(opts.steps) ? opts.steps : null;
    var message = "";
    var fetchId = "";
    if (!steps) {
      if (opts.waiting) {
        message = "아직 시작하지 않았습니다";
      } else if (opts.convId) {
        var c = processFetchCache[opts.convId];
        if (c && c.state === "done" && c.found) { steps = c.steps; }
        else if (c && c.state === "done") { message = "agy 대화 기록이 남아 있지 않아 과정을 볼 수 없습니다"; }
        else if (c && c.state === "loading") { message = "agy 대화 기록에서 읽어 오는 중입니다"; }
        else if (c && c.state === "error") { message = "과정을 불러오지 못했습니다. 다시 펼치면 한 번 더 시도합니다"; fetchId = opts.convId; }
        else { message = "기록에 저장되지 않은 위임입니다. 펼치면 agy 대화 기록에서 읽어 옵니다"; fetchId = opts.convId; }
      } else {
        message = "과정이 기록되지 않았습니다";
      }
    }

    if (steps) {
      kw.textContent = summarizeProcess(steps, opts.live);
      kw.title = kw.textContent;
      if (steps.length) body.innerHTML = buildProcessRowsHtml(steps, opts.cwd);
      else body.innerHTML = '<p class="proc-empty">' + escapeHtml(kw.textContent) + '.</p>';
    } else {
      kw.textContent = message;
      kw.title = message;
      body.innerHTML = '<p class="proc-empty">' + escapeHtml(message) + '.</p>';
    }
    if (fetchId) {
      // 사용자가 요약을 눌러 펼칠 때만 불러온다(클릭은 열림 상태가 바뀌기 전에 오므로 !d.open 이 "지금 펼치는 중").
      // toggle 이벤트로 하면 펼친 채로 다시 그려질 때마다 재시도해서, 실패가 계속되면 요청이 연쇄한다.
      sum.addEventListener("click", function () { if (!d.open) loadProcessFor(fetchId); });
    }
    return d;
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
    if (r.elapsed_sec) { meta.appendChild(metaItem(formatDuration(Number(r.elapsed_sec)), "elapsed", r.elapsed_sec + "초")); }
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

    card.appendChild(buildProcessDetails({ steps: Array.isArray(r.process) ? r.process : null, convId: r.session_id || "", cwd: qImgInfo.cwd }));

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
    if (pg.detail) pieces.push('<span class="pg-detail">' + escapeHtml(shortenPathsForCwd(pg.detail, cwd || pg.cwd)) + '</span>');
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
    var startedAt = isProcessing ? parseLocalTime(p.created) : null;
    if (startedAt) {
      var live = metaItem(formatDuration((Date.now() - startedAt.getTime()) / 1000), "elapsed live-elapsed", "접수 후 경과 시간");
      live.setAttribute("data-start", String(startedAt.getTime()));
      meta.appendChild(live);
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
    var effectiveCwd = p.cwd || qImgInfo.cwd;
    var qGallery = createImageGallery(qImgInfo.images, effectiveCwd);
    if (qGallery) qb.appendChild(qGallery);
    var qContent = document.createElement("div");
    qContent.className = "qa-content";
    renderBody(qContent, p.question, effectiveCwd);
    qb.appendChild(qContent);
    dq.appendChild(qb);
    card.appendChild(dq);

    card.appendChild(buildProcessDetails({
      steps: (isProcessing && p.progress && Array.isArray(p.progress.steps)) ? p.progress.steps : null,
      live: isProcessing,
      waiting: !isProcessing,
      cwd: effectiveCwd
    }));

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
      aKwSpan.textContent = "앞에 " + queueIndex + "건이 끝나면 시작";
    }
    sa.appendChild(aKwSpan);
    da.appendChild(sa);

    var ab = document.createElement("div");
    ab.className = "body pending-body";
    var modelText = p.model ? " " + escapeHtml(p.model) + " 모델로" : "";
    ab.innerHTML = [
      '<div class="pending-status-wrap ' + escapeHtml(p.state) + '">',
      (isProcessing ? '  <span class="pending-spinner" aria-hidden="true"></span><span>agy가' + modelText + ' 응답을 만들고 있습니다. 끝나면 이 자리에 답변이 나옵니다.</span>' :
                      '  <span>앞 작업이 끝나면' + modelText + ' 자동으로 실행됩니다.</span>'),
      '</div>',
      (isProcessing ? buildProgressHtml(p.progress, effectiveCwd) : "")
    ].join("");
    da.appendChild(ab);
    card.appendChild(da);

    return card;
  }

  // ==========================================================================
  // 3. 에이전트 인수인계 메인 뷰 (Handoff Messages Thread Rendering)
  // ==========================================================================

  function renderHandoffView() {
    if (!currentHandoffData) {
      if (els.handoffCards) els.handoffCards.innerHTML = '<p class="empty">프로젝트를 선택해 주세요.</p>';
      return;
    }

    if (els.handoffCurrentProjectTitle) {
      els.handoffCurrentProjectTitle.textContent = currentHandoffData.name;
    }
    var msgCount = Array.isArray(currentHandoffData.messages) ? currentHandoffData.messages.length : 0;
    if (els.handoffCurrentProjectCount) {
      els.handoffCurrentProjectCount.textContent = "메시지 " + msgCount + "개";
    }

    // BRIEF.md 요약 아코디언 카드
    if (els.handoffBriefCard && els.briefProjectName && els.handoffBriefContent) {
      if (currentHandoffData.brief && currentHandoffData.brief.trim()) {
        els.briefProjectName.textContent = currentHandoffData.name;
        renderMarkdownBody(els.handoffBriefContent, currentHandoffData.brief);
        els.handoffBriefCard.style.display = "block";
      } else {
        els.handoffBriefCard.style.display = "none";
      }
    }

    renderHandoffMessages();
  }

  function findHandoffFileForNum(num) {
    if (!currentHandoffData || !Array.isArray(currentHandoffData.files)) return null;
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
    if (!bodyEl) return;
    var headerEl = cardEl.querySelector(".handoff-card-header");
    var isOpen = (bodyEl.style.display !== "none");
    if (isOpen) {
      bodyEl.style.display = "none";
      cardEl.classList.remove("is-open");
      if (headerEl) headerEl.setAttribute("aria-expanded", "false");
      delete openHandoffNums[num];
      return;
    }
    bodyEl.style.display = "block";
    cardEl.classList.add("is-open");
    if (headerEl) headerEl.setAttribute("aria-expanded", "true");
    openHandoffNums[num] = true;

    if (bodyEl.dataset.loaded === "true") return;

    var fileName = findHandoffFileForNum(num);
    if (!fileName) {
      bodyEl.innerHTML = '<p class="empty">메시지 파일(msg/' + escapeHtml(num) + '-*.md)을 찾을 수 없습니다.</p>';
      bodyEl.dataset.loaded = "true";
      return;
    }

    var cacheKey = currentHandoffProject + "/" + fileName;
    if (handoffMessageCache[cacheKey]) {
      renderMarkdownBody(bodyEl, handoffMessageCache[cacheKey]);
      bodyEl.dataset.loaded = "true";
      return;
    }

    bodyEl.innerHTML = '<div class="handoff-card-body-loading">메시지 본문을 불러오는 중...</div>';
    fetchText("/api/handoff/message?project=" + encodeURIComponent(currentHandoffProject) + "&file=" + encodeURIComponent(fileName))
      .then(function (markdown) {
        handoffMessageCache[cacheKey] = markdown;
        renderMarkdownBody(bodyEl, markdown);
        bodyEl.dataset.loaded = "true";
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
      var cleanHtml = DOMPurify.sanitize(marked.parse(body));
      targetEl.innerHTML = cleanHtml;
    } catch (e) {
      targetEl.innerHTML = "<pre>" + escapeHtml(markdown) + "</pre>";
    }
  }

  function renderHandoffMessages() {
    if (!els.handoffCards) return;
    if (!currentHandoffData || !Array.isArray(currentHandoffData.messages)) {
      els.handoffCards.innerHTML = '<p class="empty">표시할 메시지가 없습니다.</p>';
      return;
    }

    var msgs = currentHandoffData.messages;
    var q = (els.handoffSearch ? els.handoffSearch.value : "").trim().toLowerCase();
    var dirFilter = els.handoffDirFilter ? els.handoffDirFilter.value : "";
    var statusFilter = els.handoffStatusFilter ? els.handoffStatusFilter.value : "";

    var filteredMsgs = msgs.filter(function (m) {
      if (dirFilter && m.dir !== dirFilter) return false;
      if (statusFilter && m.status !== statusFilter) return false;
      if (q) {
        var match = (m.num && m.num.toLowerCase().indexOf(q) >= 0) ||
                    (m.title && m.title.toLowerCase().indexOf(q) >= 0) ||
                    (m.time && m.time.indexOf(q) >= 0) ||
                    (m.status && m.status.indexOf(q) >= 0);
        if (!match) return false;
      }
      return true;
    });

    var sortedMsgs = filteredMsgs.slice().reverse();

    if (sortedMsgs.length === 0) {
      els.handoffCards.innerHTML = '<p class="empty">조건에 일치하는 핸드오프 메시지가 없습니다.</p>';
      return;
    }

    var frag = document.createDocumentFragment();
    sortedMsgs.forEach(function (m) {
      var card = document.createElement("div");
      var party = dirParty(m.dir);
      card.className = "handoff-card" + (party ? " from-" + party : "");
      card.dataset.num = m.num;

      // [#번호][제목 / 보낸 쪽 → 받는 쪽][시각, 상태 진행 표시]
      var header = document.createElement("div");
      header.className = "handoff-card-header";
      header.innerHTML = [
        '<span class="handoff-num">#' + escapeHtml(m.num) + '</span>',
        '<div class="handoff-card-header-left">',
        '  <span class="handoff-title" title="' + escapeHtml(m.title || "") + '">' + escapeHtml(m.title || "(제목 없음)") + '</span>',
        '  <span class="handoff-dir">' + dirLabelHtml(m.dir) + '</span>',
        '</div>',
        '<div class="handoff-card-header-right">',
        '  <span class="handoff-time">' + escapeHtml(m.time || "") + '</span>',
        '  ' + stepsHtml(m.status),
        '</div>'
      ].join("");
      makeActivatable(header);
      header.setAttribute("aria-expanded", openHandoffNums[m.num] ? "true" : "false");

      var body = document.createElement("div");
      body.className = "handoff-card-body md";

      if (openHandoffNums[m.num]) {
        body.style.display = "block";
        card.classList.add("is-open");
        var fileName = findHandoffFileForNum(m.num);
        if (fileName) {
          var cacheKey = currentHandoffProject + "/" + fileName;
          if (handoffMessageCache[cacheKey]) {
            renderMarkdownBody(body, handoffMessageCache[cacheKey]);
            body.dataset.loaded = "true";
          } else {
            body.innerHTML = '<div class="handoff-card-body-loading">메시지 본문을 불러오는 중...</div>';
            fetchText("/api/handoff/message?project=" + encodeURIComponent(currentHandoffProject) + "&file=" + encodeURIComponent(fileName))
              .then(function (md) {
                handoffMessageCache[cacheKey] = md;
                if (openHandoffNums[m.num]) {
                  renderMarkdownBody(body, md);
                  body.dataset.loaded = "true";
                }
              })
              .catch(function (err) {
                body.innerHTML = '<p class="empty">본문 로드 실패: ' + escapeHtml(err.message) + '</p>';
              });
          }
        }
      } else {
        body.style.display = "none";
      }

      header.addEventListener("click", function () {
        toggleHandoffMessage(card, m.num);
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

  function refresh(force) {
    return Promise.all([
      loadSystemStatus(),
      loadAllQa(force),
      loadPending(),
      loadHandoffProjects(force)
    ]).then(function (results) {
      var qaRes = results[1];
      var pList = results[2];
      var pKey = pendingKeyOf(pList);
      var pChanged = (pKey !== lastPendingKey);
      lastPendingKey = pKey;
      pendingItems = pList;

      populateModelFilter();
      renderQaSessionList();
      renderHandoffProjectList();

      if (currentNav === "dashboard") {
        renderDashboard();
      } else if (currentNav === "qa") {
        applyQaFilters();
      } else if (currentNav === "handoff") {
        renderHandoffView();
      }
      updateTopbarMeta();
    }).catch(function (err) {
      console.warn("Refresh error:", err);
      if (els.topbarCount) {
        els.topbarCount.textContent = "갱신 실패: " + err.message;
      }
      // 서버가 내려가 있으면 "지금" 패널이 연결 끊김 상태를 보여 주게 한다.
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
        selectQaSession("");
        switchNav("qa");
      });
    }
    if (els.btnViewAllHandoff) {
      els.btnViewAllHandoff.addEventListener("click", function () {
        switchNav("handoff");
      });
    }

    // QA 세션 사이드바 검색 및 필터
    if (els.qaSessionSearch) els.qaSessionSearch.addEventListener("input", renderQaSessionList);
    if (els.modelFilter) els.modelFilter.addEventListener("change", applyQaFilters);
    if (els.statusFilter) els.statusFilter.addEventListener("change", applyQaFilters);
    if (els.qaSearch) els.qaSearch.addEventListener("input", applyQaFilters);
    if (els.loadMoreBtn) els.loadMoreBtn.addEventListener("click", renderMoreQa);

    // Handoff 사이드바 검색 및 필터
    if (els.handoffProjectSearch) els.handoffProjectSearch.addEventListener("input", renderHandoffProjectList);
    if (els.handoffDirFilter) els.handoffDirFilter.addEventListener("change", renderHandoffMessages);
    if (els.handoffStatusFilter) els.handoffStatusFilter.addEventListener("change", renderHandoffMessages);
    if (els.handoffSearch) els.handoffSearch.addEventListener("input", renderHandoffMessages);

    // 푸터 새로고침 & 자동 갱신
    if (els.refreshBtn) els.refreshBtn.addEventListener("click", function () { refresh(true); });
    if (els.cards) {
      els.cards.addEventListener("click", function (e) {
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
      if (parsed.nav === "qa" && parsed.session !== currentQaSession) {
        selectQaSession(parsed.session);
      } else if (parsed.nav === "handoff" && parsed.project && parsed.project !== currentHandoffProject) {
        selectHandoffProject(parsed.project);
      }
    });
  }

  // 초기화 실행
  initImagePopups();
  bindEvents();

  // 이전 사이드바 접힘 상태 복원
  try {
    if (localStorage.getItem("samjil_sidebar_collapsed") === "true" && els.appSidebar) {
      els.appSidebar.classList.add("collapsed");
    }
  } catch (e) {}

  // 초기 라우트 파싱
  var initialRoute = parseHash();
  if (initialRoute.session) { currentQaSession = initialRoute.session; }
  if (initialRoute.project) { currentHandoffProject = initialRoute.project; }

  // 최초 네비게이션 적용
  switchNav(initialRoute.nav, false);

  // 최초 데이터 로드 및 타이머 시작
  refresh(true).then(scheduleAutoRefresh);
})();
