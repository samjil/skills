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
    navBadgeQa:           document.getElementById("nav-badge-qa"),
    navBadgeHandoff:      document.getElementById("nav-badge-handoff"),

    // 2차 서브 패널
    subDashboard:         document.getElementById("sidebar-sub-dashboard"),
    subQa:                document.getElementById("sidebar-sub-qa"),
    subHandoff:           document.getElementById("sidebar-sub-handoff"),

    // 대시보드 미니 위젯
    miniTodayCount:       document.getElementById("mini-today-count"),
    miniPendingCount:     document.getElementById("mini-pending-count"),
    miniProjectsCount:    document.getElementById("mini-projects-count"),
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
    bannerStatusTitle:    document.getElementById("banner-status-title"),
    bannerStatusDesc:     document.getElementById("banner-status-desc"),
    bannerPortTag:        document.getElementById("banner-port-tag"),
    bannerWatcherTag:     document.getElementById("banner-watcher-tag"),
    kpiValQaTotal:        document.getElementById("kpi-val-qa-total"),
    kpiSubQaToday:        document.getElementById("kpi-sub-qa-today"),
    kpiValQaRate:         document.getElementById("kpi-val-qa-rate"),
    kpiSubQaCounts:       document.getElementById("kpi-sub-qa-counts"),
    kpiValHandoffProjects: document.getElementById("kpi-val-handoff-projects"),
    kpiSubHandoffMsgs:    document.getElementById("kpi-sub-handoff-msgs"),
    kpiValPendingTickets: document.getElementById("kpi-val-pending-tickets"),
    kpiSubPendingDetails: document.getElementById("kpi-sub-pending-details"),
    dashboardRecentQa:    document.getElementById("dashboard-recent-qa"),
    dashboardRecentHandoff: document.getElementById("dashboard-recent-handoff"),
    btnViewAllQa:         document.getElementById("btn-view-all-qa"),
    btnViewAllHandoff:    document.getElementById("btn-view-all-handoff"),
    modelStatsTotal:      document.getElementById("model-stats-total"),
    modelBarsContainer:   document.getElementById("model-bars-container"),

    // QA 메인 뷰 내부
    qaSessionIcon:        document.getElementById("qa-session-icon"),
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
    chipHandoffUpdated:   document.getElementById("chip-handoff-updated"),
    chipHandoffFilterDir: document.getElementById("chip-handoff-filter-dir"),
    chipHandoffFilterStatus: document.getElementById("chip-handoff-filter-status"),
    handoffBriefCard:     document.getElementById("handoff-brief-card"),
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
  var isServerOnline = false;

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
        els.topbarCurrent.textContent = "🧵 " + currentQaSession;
      }
    } else if (currentNav === "handoff") {
      els.topbarCategory.textContent = "에이전트 인수인계";
      els.topbarCurrent.textContent = currentHandoffProject ? "📁 " + currentHandoffProject : "프로젝트 선택";
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

    els.topbarUpdated.textContent = new Date().toLocaleTimeString();
  }

  // ==========================================================================
  // Data Loaders
  // ==========================================================================

  // 시스템 런타임 상태 로드 (/api/status)
  function loadSystemStatus() {
    return fetchJson("/api/status")
      .then(function (status) {
        isServerOnline = true;
        if (status) {
          var isWatcherAlive = Boolean(status.watcherAlive);
          if (els.watcherPulseDot) {
            els.watcherPulseDot.classList.toggle("offline", !isWatcherAlive);
          }
          if (els.watcherStatusText) {
            els.watcherStatusText.textContent = isWatcherAlive ? "agy 워처 가동 중" : "agy 워처 미실행";
          }
          if (els.bannerWatcherTag) {
            els.bannerWatcherTag.textContent = isWatcherAlive ? "워처 ONLINE" : "워처 OFFLINE";
            els.bannerWatcherTag.style.color = isWatcherAlive ? "#4ade80" : "#f87171";
          }
          if (els.bannerPortTag && status.port) {
            els.bannerPortTag.textContent = "PORT " + status.port;
          }
        }
        return status;
      })
      .catch(function () {
        if (els.watcherStatusText) {
          els.watcherStatusText.textContent = "서버 연결 대기 중...";
        }
        return null;
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
      if (r.model && r.model !== "(session)") {
        map[sKey].models[r.model] = true;
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
      '<span class="session-icon">⊙</span>',
      '<div class="session-info">',
      '  <span class="session-name">전체 세션 피드</span>',
      '  <span class="session-sub">모든 위임 작업 타임라인</span>',
      '</div>',
      '<span class="session-badge">' + (allItems.length + pendingItems.length) + '</span>'
    ].join("");
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
        '<span class="session-icon">🧵</span>',
        '<div class="session-info">',
        '  <span class="session-name" title="' + escapeHtml(s.name) + '">' + escapeHtml(s.name) + '</span>',
        '  <span class="session-sub">' + subText + (s.errors > 0 ? ' · ⚠️ 에러 ' + s.errors : '') + '</span>',
        '</div>',
        badgeHtml
      ].join("");

      item.onclick = function () { selectQaSession(s.name); };
      frag.appendChild(item);
    });

    // 3. [단발성 작업 - 세션 없음] 항목 (있을 경우)
    if (noneSessionObj && (!q || "단발성".indexOf(q) >= 0 || "세션 없음".indexOf(q) >= 0)) {
      var noneItem = document.createElement("div");
      noneItem.className = "session-item" + (currentQaSession === "__none__" ? " active" : "");
      noneItem.dataset.session = "__none__";
      noneItem.innerHTML = [
        '<span class="session-icon">📄</span>',
        '<div class="session-info">',
        '  <span class="session-name">단발성 작업 (세션 없음)</span>',
        '  <span class="session-sub">' + formatRelativeTime(noneSessionObj.latestTime) + '</span>',
        '</div>',
        '<span class="session-badge">' + (noneSessionObj.total + noneSessionObj.pending) + '</span>'
      ].join("");
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
        '<span class="project-icon">📁</span>',
        '<div class="project-info">',
        '  <span class="project-name" title="' + escapeHtml(p.name) + '">' + escapeHtml(p.name) + '</span>',
        '  <span class="project-sub">' + subText + '</span>',
        '</div>',
        '<span class="project-badge">' + (p.msgCount || 0) + '</span>'
      ].join("");

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
  // 1. 대시보드 뷰 렌더링 (Dashboard Rendering)
  // ==========================================================================

  function renderDashboard() {
    if (currentNav !== "dashboard") return;

    // 1. 통계 지표 산출
    var totalQa = allItems.length;
    var okCount = 0;
    var errCount = 0;
    var todayCount = 0;
    var totalElapsed = 0;
    var elapsedItemCount = 0;
    var todayStr = new Date().toISOString().slice(0, 10); // YYYY-MM-DD
    var modelUsage = {};

    allItems.forEach(function (r) {
      if (r.status === "OK") { okCount++; } else if (r.status) { errCount++; }
      if (r.timestamp && r.timestamp.slice(0, 10) === todayStr) { todayCount++; }
      if (r.elapsed_sec && !isNaN(Number(r.elapsed_sec))) {
        totalElapsed += Number(r.elapsed_sec);
        elapsedItemCount++;
      }
      var m = (r.model && r.model !== "(session)") ? r.model : "기타 모델";
      modelUsage[m] = (modelUsage[m] || 0) + 1;
    });

    var successRate = totalQa > 0 ? Math.round((okCount / (okCount + errCount || 1)) * 100) : 0;
    var avgSec = elapsedItemCount > 0 ? (totalElapsed / elapsedItemCount).toFixed(1) : "-";

    var totalHandoffProjects = handoffProjects.length;
    var totalHandoffMsgs = 0;
    var pendingHandoffCount = 0;

    handoffProjects.forEach(function (p) {
      totalHandoffMsgs += (p.msgCount || 0);
      if (p.latestMsg && (p.latestMsg.status === "보냄" || p.latestMsg.status === "읽음")) {
        pendingHandoffCount++;
      }
    });

    // 2. 미니 위젯 (사이드바 대시보드 서브패널)
    if (els.miniTodayCount) els.miniTodayCount.textContent = todayCount + "건";
    if (els.miniPendingCount) els.miniPendingCount.textContent = (pendingItems.length + pendingHandoffCount) + "건";
    if (els.miniProjectsCount) els.miniProjectsCount.textContent = totalHandoffProjects + "개";

    // 3. KPI 카드 갱신
    if (els.kpiValQaTotal) els.kpiValQaTotal.textContent = totalQa.toLocaleString() + "건";
    if (els.kpiSubQaToday) els.kpiSubQaToday.textContent = "오늘 " + todayCount + "건 실행";
    if (els.kpiValQaRate) els.kpiValQaRate.textContent = successRate + "%";
    if (els.kpiSubQaCounts) els.kpiSubQaCounts.textContent = "OK " + okCount + " / ERROR " + errCount + (avgSec !== "-" ? " · 평균 " + avgSec + "초" : "");
    if (els.kpiValHandoffProjects) els.kpiValHandoffProjects.textContent = totalHandoffProjects + "개";
    if (els.kpiSubHandoffMsgs) els.kpiSubHandoffMsgs.textContent = "총 " + totalHandoffMsgs + "개 메시지";
    if (els.kpiValPendingTickets) els.kpiValPendingTickets.textContent = (pendingItems.length + pendingHandoffCount) + "건";
    if (els.kpiSubPendingDetails) els.kpiSubPendingDetails.textContent = "inbox " + pendingItems.length + "건 / 미착수 " + pendingHandoffCount + "건";

    // 4. 최근 위임 실행 활동 리스트 (Top 5)
    renderDashboardRecentQa();

    // 5. 최근 인수인계 활동 리스트 (Top 5)
    renderDashboardRecentHandoff();

    // 6. 모델 사용 분포 렌더링
    renderDashboardModelStats(modelUsage, totalQa);

    // 7. 사이드바 빠른 활성 세션 링크 렌더링
    renderQuickSessions();
  }

  function renderQuickSessions() {
    if (!els.quickSessionsList) return;
    var sessions = groupQaSessions();
    if (sessions.length === 0) {
      els.quickSessionsList.innerHTML = '<span class="empty-hint">세션 기록 없음</span>';
      return;
    }
    var topSessions = sessions.slice(0, 4);
    var frag = document.createDocumentFragment();
    topSessions.forEach(function (s) {
      var item = document.createElement("div");
      item.className = "quick-link-item";
      var sDisplayName = s.name === "__none__" ? "단발성 작업" : ("🧵 " + s.name);
      item.innerHTML = [
        '<span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">' + escapeHtml(sDisplayName) + '</span>',
        '<span style="font-weight:600;font-size:11px;opacity:0.8;">' + (s.total + s.pending) + '건</span>'
      ].join("");
      item.onclick = function () {
        selectQaSession(s.name);
        switchNav("qa");
      };
      frag.appendChild(item);
    });
    els.quickSessionsList.innerHTML = "";
    els.quickSessionsList.appendChild(frag);
  }

  function renderDashboardRecentQa() {
    if (!els.dashboardRecentQa) return;
    var list = [];
    if (pendingItems.length > 0) {
      pendingItems.forEach(function (p) { list.push({ isPending: true, item: p }); });
    }
    allItems.slice(0, 5).forEach(function (r) {
      list.push({ isPending: false, item: r });
    });
    list = list.slice(0, 5);

    if (list.length === 0) {
      els.dashboardRecentQa.innerHTML = '<p class="empty-hint">위임 실행 기록이 없습니다.</p>';
      return;
    }

    var frag = document.createDocumentFragment();
    list.forEach(function (entry) {
      var it = entry.item;
      var el = document.createElement("div");
      el.className = "activity-item";

      var qTitle = extractQuestionKeyword(it.question) || "(질문 내용 없음)";
      var timeStr = formatRelativeTime(entry.isPending ? it.created : it.timestamp);
      var badgeCls = entry.isPending ? "status-pending-processing" : (it.status === "OK" ? "status-ok" : "status-err");
      var badgeText = entry.isPending ? "진행 중" : (it.status || "미기록");
      var sessionText = it.session ? ("🧵 " + it.session) : "단발성";

      el.innerHTML = [
        '<div class="activity-main">',
        '  <div class="activity-title" title="' + escapeHtml(qTitle) + '">' + escapeHtml(qTitle) + '</div>',
        '  <div class="activity-sub">',
        '    <span>' + escapeHtml(sessionText) + '</span>',
        '    <span>•</span>',
        '    <span>' + escapeHtml(it.model || "agy") + '</span>',
        '  </div>',
        '</div>',
        '<div class="activity-side">',
        '  <span class="badge ' + badgeCls + '">' + badgeText + '</span>',
        '  <span class="activity-time">' + timeStr + '</span>',
        '</div>'
      ].join("");

      el.onclick = function () {
        selectQaSession(it.session || "__none__");
        switchNav("qa");
      };
      frag.appendChild(el);
    });

    els.dashboardRecentQa.innerHTML = "";
    els.dashboardRecentQa.appendChild(frag);
  }

  function renderDashboardRecentHandoff() {
    if (!els.dashboardRecentHandoff) return;

    var recentMsgs = [];
    handoffProjects.forEach(function (p) {
      if (p.latestMsg) {
        recentMsgs.push({
          projectName: p.name,
          num: p.latestMsg.num,
          title: p.latestMsg.title,
          dir: p.latestMsg.dir,
          status: p.latestMsg.status,
          time: p.latestMsg.time || p.updated
        });
      }
    });

    recentMsgs.sort(function (a, b) {
      return String(b.time || "").localeCompare(String(a.time || ""));
    });
    recentMsgs = recentMsgs.slice(0, 5);

    if (recentMsgs.length === 0) {
      els.dashboardRecentHandoff.innerHTML = '<p class="empty-hint">인수인계 메시지가 없습니다.</p>';
      return;
    }

    var frag = document.createDocumentFragment();
    recentMsgs.forEach(function (m) {
      var el = document.createElement("div");
      el.className = "activity-item";

      var dirBadgeCls = m.dir === "c2a" ? "dir-c2a" : (m.dir === "a2c" ? "dir-a2c" : "");
      var dirText = m.dir === "c2a" ? "Claude → agy" : (m.dir === "a2c" ? "agy → Claude" : m.dir);
      var statusBadgeCls = "status-" + (m.status || "처리됨");

      el.innerHTML = [
        '<div class="activity-main">',
        '  <div class="activity-title" title="' + escapeHtml(m.title) + '">#' + m.num + ' ' + escapeHtml(m.title) + '</div>',
        '  <div class="activity-sub">',
        '    <span>📁 ' + escapeHtml(m.projectName) + '</span>',
        '    <span>•</span>',
        '    <span class="badge ' + dirBadgeCls + '" style="font-size:10.5px;padding:1px 5px;">' + dirText + '</span>',
        '  </div>',
        '</div>',
        '<div class="activity-side">',
        '  <span class="badge ' + statusBadgeCls + '">' + (m.status || "완료") + '</span>',
        '  <span class="activity-time">' + formatRelativeTime(m.time) + '</span>',
        '</div>'
      ].join("");

      el.onclick = function () {
        selectHandoffProject(m.projectName);
        switchNav("handoff");
      };
      frag.appendChild(el);
    });

    els.dashboardRecentHandoff.innerHTML = "";
    els.dashboardRecentHandoff.appendChild(frag);
  }

  function renderDashboardModelStats(modelUsage, totalCount) {
    if (!els.modelBarsContainer) return;
    var models = Object.keys(modelUsage).sort(function (a, b) {
      return modelUsage[b] - modelUsage[a];
    });

    if (els.modelStatsTotal) {
      els.modelStatsTotal.textContent = "총 " + totalCount + "건 호출";
    }

    if (models.length === 0) {
      els.modelBarsContainer.innerHTML = '<p class="empty-hint">모델 사용 기록이 없습니다.</p>';
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
        '<div class="model-bar-track">',
        '  <div class="model-bar-fill" style="width: ' + pct + '%;"></div>',
        '</div>',
        '<span class="model-bar-val">' + count + '회 (' + pct + '%)</span>'
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
    allItems.forEach(function (r) { if (r.model && r.model !== "(session)") { set[r.model] = true; } });
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

    // 세션 상세 헤더 갱신
    updateQaHeader(session);

    // 1. 이미 완료된 task_id 집합
    var finishedTaskIds = {};
    allItems.forEach(function (r) {
      if (r && r.task_id) { finishedTaskIds[r.task_id] = true; }
    });

    // 2. pending 목록 필터링
    if (model || status) {
      filteredPending = [];
    } else {
      filteredPending = pendingItems.filter(function (p) {
        if (!p || !p.task_id) return false;
        if (finishedTaskIds[p.task_id]) return false;
        if (session === "__none__" && p.session) return false;
        if (session && session !== "__none__" && p.session !== session) return false;
        if (q) {
          var qText = (p.question || "").toLowerCase();
          if (qText.indexOf(q) === -1) return false;
        }
        return true;
      });
    }

    // 3. 완료 레코드 필터링
    filteredQa = allItems.filter(function (r) {
      if (session === "__none__" && r.session) return false;
      if (session && session !== "__none__" && r.session !== session) return false;
      if (model && r.model !== model) return false;
      if (status) {
        var st = (r.status == null ? "" : String(r.status)).trim();
        if (status === "OK" && st !== "OK") return false;
        if (status === "ERROR" && st === "OK") return false;
      }
      if (q) {
        var hay = [r.model, r.computer_name, r.task_id, r.source, r.session, r.session_id, r.question, r.answer]
          .map(function (v) { return v == null ? "" : String(v); })
          .join(" ").toLowerCase();
        if (hay.indexOf(q) === -1) return false;
      }
      return true;
    });

    var openState = snapshotQaOpenState();
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
    restoreQaOpenState(openState);
    updateTopbarMeta();
  }

  // 자동 새로고침으로 카드를 다시 그려도 사용자가 열고 닫은 질문/답변 상태를 유지한다.
  function snapshotQaOpenState() {
    var state = {};
    if (!els.cards) return state;
    var items = els.cards.querySelectorAll(".card[data-key] > details.qa");
    for (var i = 0; i < items.length; i++) {
      var d = items[i];
      state[d.parentNode.getAttribute("data-key") + "|" + (d.classList.contains("q") ? "q" : "a")] = d.open;
    }
    return state;
  }

  function restoreQaOpenState(state) {
    if (!els.cards) return;
    var items = els.cards.querySelectorAll(".card[data-key] > details.qa");
    for (var i = 0; i < items.length; i++) {
      var d = items[i];
      var k = d.parentNode.getAttribute("data-key") + "|" + (d.classList.contains("q") ? "q" : "a");
      if (Object.prototype.hasOwnProperty.call(state, k)) d.open = state[k];
    }
  }

  function updateQaHeader(session) {
    if (!els.qaCurrentSessionTitle) return;

    if (!session) {
      els.qaSessionIcon.textContent = "⊙";
      els.qaCurrentSessionTitle.textContent = "전체 세션 피드";
    } else if (session === "__none__") {
      els.qaSessionIcon.textContent = "📄";
      els.qaCurrentSessionTitle.textContent = "단발성 작업 (세션 없음)";
    } else {
      els.qaSessionIcon.textContent = "🧵";
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
    gallery.innerHTML = '<div class="qa-image-gallery-title">🖼️ 참조 이미지 (' + images.length + '개) <span style="font-weight:normal;opacity:.7;font-size:11px;">(마우스 오버: 확대 / 클릭: 크게 보기)</span></div>';

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
            titleEl.innerHTML = '🖼️ 참조 이미지 (' + validCount + '개) <span style="font-weight:normal;opacity:.7;font-size:11px;">(마우스 오버: 확대 / 클릭: 크게 보기)</span>';
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
          code.title = str + " (클릭: 원본 보기 / 마우스 오버: 확대)";
          if (!code.querySelector(".img-icon")) {
            var icon = document.createElement("span");
            icon.className = "img-icon";
            icon.textContent = "🖼️ ";
            code.insertBefore(icon, code.firstChild);
          }
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

  function cleanTextForPreview(str) {
    if (!str) return "";
    return String(str)
      .replace(/^#+\s*/, "")
      .replace(/[*_`~]/g, "")
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
      if (t.indexOf("@cwd:") === 0 || t.indexOf("@session:") === 0) continue;
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

    var src = r.source || "bridge";
    meta.appendChild(badge("source-" + src, src === "mcp" ? "🔗 MCP" : "📁 bridge"));

    var modelName = (r.model && r.model !== "(session)") ? r.model : null;
    var isSession = Boolean(r.session || r.session_id || r.model === "(session)");
    if (modelName) { meta.appendChild(badge("model", String(modelName))); }

    if (r.attempts && Number(r.attempts) > 1) { meta.appendChild(badge("attempts", "시도 " + r.attempts + "회")); }
    if (r.total_tokens) { meta.appendChild(badge("tok", "토큰 " + r.total_tokens)); }
    if (r.elapsed_sec) { meta.appendChild(badge("time", r.elapsed_sec + "초")); }
    if (r.task_id) { meta.appendChild(badge("taskid", r.task_id)); }
    card.appendChild(meta);

    if (isSession) {
      var sMeta = document.createElement("div");
      sMeta.className = "meta session-meta";
      sMeta.appendChild(badge("session-flag", "(session)"));
      if (r.session) { sMeta.appendChild(badge("session", "🧵 " + r.session)); }
      if (r.session_id) {
        var sid = String(r.session_id);
        var shortSid = sid.length > 8 ? sid.substring(0, 8) : sid;
        var sidBadge = badge("session-id", "id:" + shortSid);
        sidBadge.title = "세션 ID: " + sid + " (클릭하면 복사)";
        sidBadge.style.cursor = "pointer";
        sidBadge.onclick = function () {
          if (navigator.clipboard) {
            navigator.clipboard.writeText(sid).then(function () {
              sidBadge.textContent = "복사됨!";
              setTimeout(function () { sidBadge.textContent = "id:" + shortSid; }, 1200);
            });
          }
        };
        sMeta.appendChild(sidBadge);
      }
      card.appendChild(sMeta);
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

    var da = document.createElement("details");
    da.className = "qa a";
    da.open = true;
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
      meta.appendChild(badge("status-pending-processing", "⚡ 진행 중"));
    } else {
      meta.appendChild(badge("status-pending-queued", "⏳ 대기 중"));
    }

    meta.appendChild(badge("source-bridge", "📁 bridge"));
    if (p.task_id) meta.appendChild(badge("taskid", p.task_id));
    card.appendChild(meta);

    if (p.session) {
      var sMeta = document.createElement("div");
      sMeta.className = "meta session-meta";
      sMeta.appendChild(badge("session-flag", "(session)"));
      sMeta.appendChild(badge("session", "🧵 " + p.session));
      card.appendChild(sMeta);
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

    var da = document.createElement("details");
    da.className = "qa a qa-pending-a";
    da.open = true;
    var sa = document.createElement("summary");
    var aBadge = document.createElement("span");
    aBadge.className = "qa-type-badge a-type";
    aBadge.textContent = "답변";
    sa.appendChild(aBadge);

    var aKwSpan = document.createElement("span");
    aKwSpan.className = "qa-preview-keyword";
    aKwSpan.textContent = isProcessing ? "생각 중…" : ("대기 중 (앞에 " + queueIndex + "건)");
    sa.appendChild(aKwSpan);
    da.appendChild(sa);

    var ab = document.createElement("div");
    ab.className = "body pending-body";
    ab.innerHTML = [
      '<div class="pending-status-wrap ' + p.state + '">',
      (isProcessing ? '  <span class="pending-spinner"></span><span>agy agent 가 질문을 분석하고 응답을 생성하고 있습니다...</span>' :
                      '  <span>앞 순서의 작업이 완료되면 자동으로 실행됩니다.</span>'),
      '</div>'
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
      els.handoffCurrentProjectCount.textContent = msgCount + " msgs";
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
    var isOpen = (bodyEl.style.display !== "none");
    if (isOpen) {
      bodyEl.style.display = "none";
      cardEl.classList.remove("is-open");
      delete openHandoffNums[num];
      return;
    }
    bodyEl.style.display = "block";
    cardEl.classList.add("is-open");
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
      var cleanHtml = DOMPurify.sanitize(marked.parse(markdown));
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
      card.className = "handoff-card";
      card.dataset.num = m.num;

      var header = document.createElement("div");
      header.className = "handoff-card-header";

      var left = document.createElement("div");
      left.className = "handoff-card-header-left";
      var numSpan = document.createElement("span");
      numSpan.className = "handoff-num";
      numSpan.textContent = "#" + m.num;

      var dirBadge = document.createElement("span");
      dirBadge.className = "badge dir-" + (m.dir || "unknown");
      dirBadge.textContent = m.dir === "c2a" ? "Claude → agy" : (m.dir === "a2c" ? "agy → Claude" : (m.dir || ""));

      var titleSpan = document.createElement("span");
      titleSpan.className = "handoff-title";
      titleSpan.textContent = m.title || "(제목 없음)";

      left.appendChild(numSpan);
      left.appendChild(dirBadge);
      left.appendChild(titleSpan);

      var right = document.createElement("div");
      right.className = "handoff-card-header-right";
      var timeSpan = document.createElement("span");
      timeSpan.className = "handoff-time";
      timeSpan.textContent = m.time || "";

      var statusBadge = document.createElement("span");
      statusBadge.className = "badge status-" + (m.status || "unknown");
      statusBadge.textContent = m.status || "";

      right.appendChild(timeSpan);
      right.appendChild(statusBadge);
      header.appendChild(left);
      header.appendChild(right);

      var body = document.createElement("div");
      body.className = "handoff-card-body markdown-body";

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
    if (els.autoRefresh) els.autoRefresh.addEventListener("change", scheduleAutoRefresh);

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
