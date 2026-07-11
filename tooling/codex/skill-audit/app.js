const data = window.SKILL_AUDIT_DATA;
const storageKey = "skill-audit-decisions-v1";

const state = {
  search: "",
  action: "all",
  source: "all",
  duplicatesOnly: false,
  sort: "impact",
  selectedId: data.skills[0]?.id || null,
  decisions: loadDecisions(),
};

const actionOrder = {
  "disable-plugin": 0,
  archive: 1,
  review: 2,
  keep: 3,
};

const ui = {
  actions: {
    "": "未决定",
    keep: "保留",
    review: "复核",
    archive: "归档/删除",
    "disable-plugin": "禁用插件",
  },
  sources: {
    user: "用户技能",
    system: "系统技能",
    plugin: "插件技能",
    external: "外部路径",
  },
  families: {
    system: "系统",
    content: "内容",
    media: "媒体",
    frontend: "前端/设计",
    engineering: "工程",
    documents: "文档",
    templates: "模板",
    general: "通用",
    external: "外部",
  },
  duplicate: {
    exact: "内容重复",
    name: "同名",
    none: "无",
  },
};

const els = {
  generatedAt: document.getElementById("generatedAt"),
  summaryGrid: document.getElementById("summaryGrid"),
  searchInput: document.getElementById("searchInput"),
  actionFilter: document.getElementById("actionFilter"),
  sourceFilter: document.getElementById("sourceFilter"),
  duplicateFilter: document.getElementById("duplicateFilter"),
  sortSelect: document.getElementById("sortSelect"),
  rows: document.getElementById("skillRows"),
  visibleCount: document.getElementById("visibleCount"),
  detailEmpty: document.getElementById("detailEmpty"),
  detailContent: document.getElementById("detailContent"),
  strategyBand: document.getElementById("strategyBand"),
  pluginList: document.getElementById("pluginList"),
  snapshotLine: document.getElementById("snapshotLine"),
};

els.generatedAt.textContent = `生成时间 ${new Date(data.generatedAt).toLocaleString()}`;
els.snapshotLine.textContent = `当前 Codex prompt 输入中有 ${data.counts.total} 个技能。你的选择只保存在当前浏览器。`;

render();
bindEvents();

function bindEvents() {
  els.searchInput.addEventListener("input", (event) => {
    state.search = event.target.value.trim().toLowerCase();
    renderTable();
  });

  els.actionFilter.addEventListener("change", (event) => {
    state.action = event.target.value;
    renderTable();
  });

  els.sourceFilter.addEventListener("change", (event) => {
    state.source = event.target.value;
    renderTable();
  });

  els.duplicateFilter.addEventListener("change", (event) => {
    state.duplicatesOnly = event.target.checked;
    renderTable();
  });

  els.sortSelect.addEventListener("change", (event) => {
    state.sort = event.target.value;
    renderTable();
  });

  document.getElementById("acceptSuggested").addEventListener("click", () => {
    for (const skill of data.skills) {
      state.decisions[skill.id] ||= {};
      state.decisions[skill.id].decision = skill.recommendation.action;
    }
    saveDecisions();
    renderTable();
    renderDetail();
  });

  document.getElementById("clearDecisions").addEventListener("click", () => {
    state.decisions = {};
    saveDecisions();
    renderTable();
    renderDetail();
  });

  document.getElementById("exportJson").addEventListener("click", exportDecisions);
  document.getElementById("copyConfigHints").addEventListener("click", copyConfigHints);
  document.getElementById("copyDryRun").addEventListener("click", () => {
    copyTextOrPrompt(buildSuggestedCommand({ apply: false }), "预览命令已复制。");
  });
  document.getElementById("copyApplySuggested").addEventListener("click", () => {
    copyTextOrPrompt(buildSuggestedCommand({ apply: true }), "一键执行命令已复制。建议先运行预览命令。");
  });
  document.getElementById("archiveView").addEventListener("click", () => {
    els.searchInput.value = "";
    els.actionFilter.value = "archive";
    els.duplicateFilter.checked = false;
    state.search = "";
    state.action = "archive";
    state.source = "all";
    state.duplicatesOnly = false;
    els.sourceFilter.value = "all";
    renderTable();
  });
  document.getElementById("pluginView").addEventListener("click", () => {
    document.querySelector(".plugin-panel").scrollIntoView({ behavior: "smooth", block: "start" });
  });
}

function render() {
  renderSummary();
  renderStrategy();
  renderTable();
  renderPluginList();
}

function renderSummary() {
  const byAction = data.counts.byAction;
  const items = [
    ["总数", data.counts.total],
    ["保留", byAction.keep || 0],
    ["复核", byAction.review || 0],
    ["归档/删除", byAction.archive || 0],
    ["禁用插件", byAction["disable-plugin"] || 0],
    ["插件数", data.pluginSummaries.filter((item) => item.source === "plugin").length],
  ];

  els.summaryGrid.innerHTML = items
    .map(([label, count]) => `<div class="metric"><strong>${count}</strong><span>${label}</span></div>`)
    .join("");
}

function renderStrategy() {
  els.strategyBand.innerHTML = data.strategy
    .map(
      (item) => `
        <article class="strategy-item">
          <strong>${escapeHtml(item.title)}</strong>
          <p>${escapeHtml(item.detail)}</p>
          ${item.command ? `<code>${escapeHtml(item.command)}</code>` : ""}
        </article>
      `,
    )
    .join("");
}

function filteredSkills() {
  const query = state.search;
  return data.skills
    .filter((skill) => state.action === "all" || skill.recommendation.action === state.action)
    .filter((skill) => state.source === "all" || skill.source === state.source)
    .filter((skill) => !state.duplicatesOnly || skill.duplicateHashCount > 1 || skill.duplicateSlugCount > 1)
    .filter((skill) => {
      if (!query) return true;
      const haystack = [skill.name, skill.description, skill.path, skill.pluginKey, skill.family]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();
      return haystack.includes(query);
    })
    .sort(sortSkills);
}

function sortSkills(a, b) {
  if (state.sort === "name") return a.name.localeCompare(b.name);
  if (state.sort === "source") {
    return a.source.localeCompare(b.source) || a.name.localeCompare(b.name);
  }
  if (state.sort === "modified") {
    return String(b.modifiedAt || "").localeCompare(String(a.modifiedAt || ""));
  }
  return (
    (actionOrder[a.recommendation.action] ?? 9) - (actionOrder[b.recommendation.action] ?? 9) ||
    b.recommendation.confidence - a.recommendation.confidence ||
    a.name.localeCompare(b.name)
  );
}

function renderTable() {
  const skills = filteredSkills();
  if (!skills.some((skill) => skill.id === state.selectedId)) state.selectedId = skills[0]?.id || null;
  els.visibleCount.textContent = `显示 ${skills.length} 项`;

  els.rows.innerHTML = skills
    .map((skill) => {
      const decision = state.decisions[skill.id]?.decision || "";
      const sourceDisplay = skill.pluginKey ? skill.pluginKey.split("@")[0] : skill.sourceLabel;
      const duplicate =
        skill.duplicateHashCount > 1
          ? ui.duplicate.exact
          : skill.duplicateSlugCount > 1
            ? ui.duplicate.name
            : ui.duplicate.none;
      return `
        <tr class="${skill.id === state.selectedId ? "selected" : ""}" data-id="${escapeHtml(skill.id)}">
          <td>
            <select class="decision-select" data-decision-id="${escapeHtml(skill.id)}">
              <option value="">未决定</option>
              <option value="keep" ${decision === "keep" ? "selected" : ""}>保留</option>
              <option value="review" ${decision === "review" ? "selected" : ""}>复核</option>
              <option value="archive" ${decision === "archive" ? "selected" : ""}>归档/删除</option>
              <option value="disable-plugin" ${decision === "disable-plugin" ? "selected" : ""}>禁用插件</option>
            </select>
          </td>
          <td>
            <span class="skill-name">${escapeHtml(skill.name)}</span>
            <span class="skill-desc">${escapeHtml(skill.description || "SKILL.md front matter 中没有描述。")}</span>
          </td>
          <td><span class="badge ${skill.recommendation.action}">${skill.recommendation.label}</span></td>
          <td>${escapeHtml(sourceDisplay)}</td>
          <td><span class="badge neutral">${escapeHtml(ui.families[skill.family] || skill.family)}</span></td>
          <td>${duplicate}</td>
          <td>${formatDate(skill.modifiedAt)}</td>
        </tr>
      `;
    })
    .join("");

  els.rows.querySelectorAll("tr").forEach((row) => {
    row.addEventListener("click", (event) => {
      if (event.target.matches("select")) return;
      state.selectedId = row.dataset.id;
      renderTable();
      renderDetail();
    });
  });

  els.rows.querySelectorAll("[data-decision-id]").forEach((select) => {
    select.addEventListener("change", (event) => {
      const id = event.target.dataset.decisionId;
      state.decisions[id] ||= {};
      state.decisions[id].decision = event.target.value;
      saveDecisions();
      renderDetail();
    });
  });

  renderDetail();
}

function renderDetail() {
  const skill = data.skills.find((item) => item.id === state.selectedId);
  if (!skill) {
    els.detailEmpty.classList.remove("hidden");
    els.detailContent.classList.add("hidden");
    return;
  }

  const saved = state.decisions[skill.id] || {};
  els.detailEmpty.classList.add("hidden");
  els.detailContent.classList.remove("hidden");
  els.detailContent.innerHTML = `
    <div class="detail-title">
      <h3>${escapeHtml(skill.name)}</h3>
      <span class="badge ${skill.recommendation.action}">${skill.recommendation.label}</span>
    </div>
    <p class="reason">${escapeHtml(skill.recommendation.reason)}</p>
    <div class="detail-meta">
      <div><span>置信度</span><strong>${skill.recommendation.confidence}%</strong></div>
      <div><span>来源</span><strong>${escapeHtml(skill.sourceLabel)}</strong></div>
      <div><span>插件</span><strong>${escapeHtml(skill.pluginKey || "无")}</strong></div>
      <div><span>类别</span><strong>${escapeHtml(ui.families[skill.family] || skill.family)}</strong></div>
      <div><span>内容重复数</span><strong>${skill.duplicateHashCount}</strong></div>
      <div><span>同名重复数</span><strong>${skill.duplicateSlugCount}</strong></div>
      <div><span>文件大小</span><strong>${formatBytes(skill.sizeBytes)}</strong></div>
    </div>
    <p class="reason">${escapeHtml(skill.description || "SKILL.md front matter 中没有 description。")}</p>
    <div class="path">${escapeHtml(skill.path)}</div>
    <p class="reason">${escapeHtml(actionHint(skill))}</p>
    <label class="field note-field">
      <span>决策备注</span>
      <textarea id="decisionNote" placeholder="为什么保留、复核、归档或禁用？">${escapeHtml(saved.note || "")}</textarea>
    </label>
  `;

  document.getElementById("decisionNote").addEventListener("input", (event) => {
    state.decisions[skill.id] ||= {};
    state.decisions[skill.id].note = event.target.value;
    saveDecisions();
  });
}

function renderPluginList() {
  const maxCount = Math.max(...data.pluginSummaries.map((item) => item.count), 1);
  els.pluginList.innerHTML = data.pluginSummaries
    .map((plugin) => {
      const total = plugin.count || 1;
      const parts = [
        ["keep", plugin.keep],
        ["review", plugin.review],
        ["archive", plugin.archive],
        ["disable-plugin", plugin.disablePlugin],
      ]
        .filter(([, count]) => count > 0)
        .map(([name, count]) => `<span class="${name}" style="width:${(count / total) * 100}%"></span>`)
        .join("");
      const impactWidth = Math.max(5, (plugin.count / maxCount) * 100);
      return `
        <div class="plugin-row">
          <div>
            <div class="plugin-key">${escapeHtml(plugin.key)}</div>
            <div class="plugin-meta">${plugin.enabled === false ? "已禁用" : "已启用或用户技能来源"}</div>
          </div>
          <strong>${plugin.count} 个技能</strong>
          <div>
            <div class="bar" title="建议分布">${parts}</div>
            <div class="plugin-meta" style="margin-top:6px">相对负载：${Math.round(impactWidth)}%</div>
          </div>
          <span class="badge ${plugin.disablePlugin > plugin.count / 2 ? "disable-plugin" : plugin.archive ? "archive" : "review"}">
            ${plugin.disablePlugin > plugin.count / 2 ? "禁用插件" : plugin.archive ? "复核归档" : "复核"}
          </span>
        </div>
      `;
    })
    .join("");
}

function exportDecisions() {
  const decisions = data.skills
    .map((skill) => ({
      name: skill.name,
      source: skill.source,
      pluginKey: skill.pluginKey,
      suggested: skill.recommendation.action,
      decision: state.decisions[skill.id]?.decision || "",
      note: state.decisions[skill.id]?.note || "",
      path: skill.path,
    }))
    .filter((item) => item.decision || item.note);

  const blob = new Blob([JSON.stringify({ generatedAt: new Date().toISOString(), decisions }, null, 2)], {
    type: "application/json",
  });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = "skill-audit-decisions.json";
  a.click();
  URL.revokeObjectURL(url);
}

async function copyConfigHints() {
  const hints = [
    "建议优先修改的配置：",
    "",
    `编辑 ${data.configPath}`,
    "",
    '[plugins."ecc@claude-installed-local"]',
    "enabled = false",
    "",
    "其他可复核目标：",
    ...data.pluginSummaries
      .filter((plugin) => plugin.source === "plugin" && plugin.key !== "ecc@claude-installed-local" && plugin.count >= 8)
      .map((plugin) => `- ${plugin.key}: ${plugin.count} 个技能`),
  ].join("\n");

  try {
    await navigator.clipboard.writeText(hints);
    alert("配置建议已复制。");
  } catch {
    window.prompt("复制配置建议", hints);
  }
}

function buildSuggestedCommand({ apply }) {
  const script = `${data.repoRoot}/bin/skill-audit-apply.sh`;
  const mode = apply ? "--apply --yes" : "--dry-run";
  return `"${script}" --suggested ${mode}`;
}

async function copyTextOrPrompt(text, message) {
  try {
    await navigator.clipboard.writeText(text);
    alert(message);
  } catch {
    window.prompt(message, text);
  }
}

function actionHint(skill) {
  if (skill.recommendation.action === "disable-plugin") {
    return `如何真正减少：这是插件技能。不要删除插件缓存文件，应该在 ${data.configPath} 中把 [plugins."${skill.pluginKey}"] 的 enabled 改成 false。`;
  }
  if (skill.recommendation.action === "archive") {
    return "如何真正删除：这是可归档/删除候选。建议先移动到 ~/.agents/skills-archive/，确认不再需要后再删除。";
  }
  if (skill.recommendation.action === "keep") {
    return "处理建议：保留，不需要操作。";
  }
  return "处理建议：先复核最近是否使用、是否和其他技能重复，再决定保留或归档。";
}

function loadDecisions() {
  try {
    return JSON.parse(localStorage.getItem(storageKey) || "{}");
  } catch {
    return {};
  }
}

function saveDecisions() {
  localStorage.setItem(storageKey, JSON.stringify(state.decisions));
}

function formatDate(value) {
  if (!value) return "n/a";
  return new Date(value).toLocaleDateString(undefined, { month: "short", day: "2-digit" });
}

function formatBytes(value) {
  if (!value) return "0 B";
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`;
  return `${(value / 1024 / 1024).toFixed(1)} MB`;
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}
