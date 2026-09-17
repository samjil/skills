(function () {
  "use strict";

  var els = {
    projectSelect: document.getElementById("handoff-project-select"),
    search:        document.getElementById("handoff-search"),
    dirFilter:     document.getElementById("handoff-dir-filter"),
    statusFilter:  document.getElementById("handoff-status-filter"),
    cards:         document.getElementById("handoff-cards"),
    briefCard:     document.getElementById("handoff-brief-card"),
    briefContent:  document.getElementById("handoff-brief-content"),
    briefName:     document.getElementById("brief-project-name"),
    refreshBtn:    document.getElementById("refresh"),
    autoRefresh:   document.getElementById("autorefresh"),
    count:         document.getElementById("count"),
    updated:       document.getElementById("updated")
  };

  var projects = [];
  var currentProject = "";
  var currentData = null;
  var messageCache = {};
  var pollTimer = null;

  function escapeHtml(str) {
    if (!str) return "";
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function fetchJson(url) {
    return fetch(url, { cache: "no-store" }).then(function (res) {
      if (!res.ok) { throw new Error("HTTP " + res.status + " " + res.statusText); }
      return res.json();
    });
  }

  function fetchText(url) {
    return fetch(url, { cache: "no-store" }).then(function (res) {
      if (!res.ok) { throw new Error("HTTP " + res.status + " " + res.statusText); }
      return res.text();
    });
  }

  function renderMarkdown(md) {
    if (window.marked && window.DOMPurify) {
      try {
        return DOMPurify.sanitize(marked.parse(md));
      } catch (e) {}
    }
    // 기본 폴백 렌더링
    return "<pre style=\"white-space:pre-wrap;\">" + escapeHtml(md) + "</pre>";
  }

  function loadProjects() {
    return fetchJson("/api/projects").then(function (list) {
      if (!Array.isArray(list)) { list = []; }
      projects = list;

      var prevSelected = els.projectSelect.value || currentProject;
      els.projectSelect.innerHTML = "";

      if (projects.length === 0) {
        var opt = document.createElement("option");
        opt.value = "";
        opt.textContent = "개설된 프로젝트가 없습니다 (~/.samjil/agent-handoff)";
        els.projectSelect.appendChild(opt);
        els.briefCard.style.display = "none";
        els.cards.innerHTML = "<p class=\"empty\">기록된 핸드오프 프로젝트가 없습니다.<br><code>~/.samjil/agent-handoff/&lt;프로젝트&gt;/</code> 폴더에 채널이 개설되면 여기에 표시됩니다.</p>";
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
        els.projectSelect.appendChild(opt);
      });

      var target = matched ? prevSelected : projects[0].name;
      els.projectSelect.value = target;
      currentProject = target;
      return loadProject(target);
    }).catch(function (err) {
      els.cards.innerHTML = "<p class=\"empty\">프로젝트 목록 로드 실패: " + escapeHtml(err.message) + "</p>";
    });
  }

  function loadProject(name) {
    if (!name) { return Promise.resolve(); }
    currentProject = name;

    return fetchJson("/api/project?name=" + encodeURIComponent(name)).then(function (data) {
      currentData = data;
      if (data && data.brief) {
        els.briefName.textContent = name;
        els.briefContent.innerHTML = renderMarkdown(data.brief);
        els.briefCard.style.display = "block";
      } else {
        els.briefCard.style.display = "none";
      }
      renderMessages();
      els.updated.textContent = "마지막 갱신: " + new Date().toLocaleTimeString();
    }).catch(function (err) {
      els.cards.innerHTML = "<p class=\"empty\">프로젝트 데이터 로드 실패: " + escapeHtml(err.message) + "</p>";
    });
  }

  function findFileForNum(num) {
    if (!currentData || !Array.isArray(currentData.files)) return null;
    var prefix = num + "-";
    for (var i = 0; i < currentData.files.length; i++) {
      if (currentData.files[i].indexOf(prefix) === 0) {
        return currentData.files[i];
      }
    }
    return null;
  }

  function toggleMessage(cardEl, num) {
    var bodyEl = cardEl.querySelector(".handoff-card-body");
    if (!bodyEl) return;

    var isOpen = (bodyEl.style.display !== "none");
    if (isOpen) {
      bodyEl.style.display = "none";
      return;
    }

    bodyEl.style.display = "block";
    if (bodyEl.dataset.loaded === "true") return;

    var fileName = findFileForNum(num);
    if (!fileName) {
      bodyEl.innerHTML = "<p class=\"empty\">해당 메시지 파일(msg/" + escapeHtml(num) + "-*.md)을 찾을 수 없습니다.</p>";
      bodyEl.dataset.loaded = "true";
      return;
    }

    var cacheKey = currentProject + "/" + fileName;
    if (messageCache[cacheKey]) {
      bodyEl.innerHTML = renderMarkdown(messageCache[cacheKey]);
      bodyEl.dataset.loaded = "true";
      return;
    }

    bodyEl.innerHTML = "<div class=\"handoff-card-body-loading\">메시지 본문 불러오는 중...</div>";
    fetchText("/api/message?project=" + encodeURIComponent(currentProject) + "&file=" + encodeURIComponent(fileName))
      .then(function (md) {
        messageCache[cacheKey] = md;
        bodyEl.innerHTML = renderMarkdown(md);
        bodyEl.dataset.loaded = "true";
      })
      .catch(function (err) {
        bodyEl.innerHTML = "<p class=\"empty\">본문 로드 실패: " + escapeHtml(err.message) + "</p>";
      });
  }

  function renderMessages() {
    if (!currentData || !Array.isArray(currentData.messages) || currentData.messages.length === 0) {
      els.cards.innerHTML = "<p class=\"empty\">등록된 메시지가 없습니다.</p>";
      updateCount();
      return;
    }

    var msgs = currentData.messages;
    var q = (els.search.value || "").trim().toLowerCase();
    var dir = els.dirFilter.value;
    var status = els.statusFilter.value;

    var filtered = msgs.filter(function (m) {
      if (dir && m.dir !== dir) return false;
      if (status && m.status !== status) return false;
      if (q) {
        var match = (m.num && m.num.toLowerCase().indexOf(q) >= 0) ||
                    (m.title && m.title.toLowerCase().indexOf(q) >= 0) ||
                    (m.time && m.time.indexOf(q) >= 0) ||
                    (m.status && m.status.indexOf(q) >= 0);
        if (!match) return false;
      }
      return true;
    });

    // 최신 메시지가 위로 오도록 내림차순 정렬
    var sorted = filtered.slice().reverse();

    if (sorted.length === 0) {
      els.cards.innerHTML = "<p class=\"empty\">조건에 맞는 메시지가 없습니다.</p>";
      updateCount();
      return;
    }

    var html = "";
    sorted.forEach(function (m) {
      var dirLabel = (m.dir === "c2a") ? "Claude → agy" : ((m.dir === "a2c") ? "agy → Claude" : m.dir);
      var dirClass = "dir-" + escapeHtml(m.dir);
      var statusClass = "status-" + escapeHtml(m.status);

      html += "<div class=\"handoff-card\" data-num=\"" + escapeHtml(m.num) + "\">";
      html += "  <div class=\"handoff-card-header\">";
      html += "    <div class=\"handoff-card-header-left\">";
      html += "      <span class=\"handoff-num\">#" + escapeHtml(m.num) + "</span>";
      html += "      <span class=\"badge " + dirClass + "\">" + escapeHtml(dirLabel) + "</span>";
      html += "      <span class=\"handoff-title\" title=\"" + escapeHtml(m.title) + "\">" + escapeHtml(m.title) + "</span>";
      html += "    </div>";
      html += "    <div class=\"handoff-card-header-right\">";
      html += "      <span class=\"badge " + statusClass + "\">" + escapeHtml(m.status) + "</span>";
      html += "      <span class=\"handoff-time\">" + escapeHtml(m.time) + "</span>";
      html += "    </div>";
      html += "  </div>";
      html += "  <div class=\"handoff-card-body markdown-body\" style=\"display: none;\"></div>";
      html += "</div>";
    });

    els.cards.innerHTML = html;

    // 클릭 이벤트 바인딩
    var cardElements = els.cards.querySelectorAll(".handoff-card");
    cardElements.forEach(function (card) {
      var num = card.getAttribute("data-num");
      var header = card.querySelector(".handoff-card-header");
      header.addEventListener("click", function () {
        toggleMessage(card, num);
      });
    });

    // 최신 메시지(맨 위 첫 번째 카드)는 자동으로 펼치기
    if (cardElements.length > 0 && !q && !dir && !status) {
      var firstCard = cardElements[0];
      toggleMessage(firstCard, firstCard.getAttribute("data-num"));
    }

    updateCount();
  }

  function updateCount() {
    if (!currentData || !currentData.messages) {
      els.count.textContent = "";
      return;
    }
    var total = currentData.messages.length;
    var visible = els.cards.querySelectorAll(".handoff-card").length;
    if (visible === total) {
      els.count.textContent = "총 " + total + "건의 메시지";
    } else {
      els.count.textContent = visible + "건 표시 중 (전체 " + total + "건)";
    }
  }

  // 이벤트 바인딩
  els.projectSelect.addEventListener("change", function () {
    loadProject(this.value);
  });

  els.search.addEventListener("input", renderMessages);
  els.dirFilter.addEventListener("change", renderMessages);
  els.statusFilter.addEventListener("change", renderMessages);

  els.refreshBtn.addEventListener("click", function () {
    loadProjects();
  });

  function startPolling() {
    if (pollTimer) clearInterval(pollTimer);
    pollTimer = setInterval(function () {
      if (els.autoRefresh.checked && currentProject) {
        loadProject(currentProject);
      }
    }, 3000);
  }

  els.autoRefresh.addEventListener("change", function () {
    if (this.checked) {
      startPolling();
    } else if (pollTimer) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
  });

  // 초기 로드
  loadProjects();
  startPolling();
})();
