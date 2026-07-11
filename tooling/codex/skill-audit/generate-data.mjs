import { execFileSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { parseAvailableSkills, parseRoots } from "./parse-skills.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const home = os.homedir();
const repoRoot = path.resolve(here, "../../..");
const outputPath = path.join(here, "generated", "skills-data.js");
const configPath = path.join(home, ".codex", "config.toml");

function collectStrings(value, out = []) {
  if (typeof value === "string") {
    out.push(value);
  } else if (Array.isArray(value)) {
    for (const item of value) collectStrings(item, out);
  } else if (value && typeof value === "object") {
    for (const item of Object.values(value)) collectStrings(item, out);
  }
  return out;
}

function resolveFileRef(fileRef, roots) {
  if (fileRef.startsWith("/")) return fileRef;
  const slashIndex = fileRef.indexOf("/");
  if (slashIndex === -1) return fileRef;
  const rootKey = fileRef.slice(0, slashIndex);
  return roots[rootKey] ? path.join(roots[rootKey], fileRef.slice(slashIndex + 1)) : fileRef;
}

function parseFrontMatter(content) {
  if (!content.startsWith("---")) return {};
  const end = content.indexOf("\n---", 3);
  if (end === -1) return {};
  const meta = {};
  const block = content.slice(3, end).split("\n");
  for (const line of block) {
    const match = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (!match) continue;
    let value = match[2].trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    meta[match[1]] = value;
  }
  return meta;
}

function parsePluginConfig() {
  if (!fs.existsSync(configPath)) return {};
  const config = fs.readFileSync(configPath, "utf8");
  const plugins = {};
  let current = null;
  for (const line of config.split("\n")) {
    const header = line.match(/^\[plugins\."(.+)"\]$/);
    if (header) {
      current = header[1];
      plugins[current] = { enabled: null };
      continue;
    }
    const enabled = line.match(/^enabled\s*=\s*(true|false)$/);
    if (current && enabled) plugins[current].enabled = enabled[1] === "true";
  }
  return plugins;
}

function slugFromName(name) {
  return name.split(":").at(-1).toLowerCase();
}

function classifySkill(name, absolutePath) {
  if (absolutePath.startsWith(path.join(home, ".agents", "skills", ".system"))) {
    return { source: "system", sourceLabel: "系统技能", pluginKey: null, family: "system" };
  }

  if (absolutePath.startsWith(path.join(home, ".agents", "skills"))) {
    return { source: "user", sourceLabel: "用户技能", pluginKey: null, family: classifyFamily(name) };
  }

  if (absolutePath.includes("/.codex/plugins/cache/")) {
    const pluginKey = pluginKeyFromPath(name, absolutePath);
    return {
      source: "plugin",
      sourceLabel: "插件技能",
      pluginKey,
      family: classifyFamily(name),
    };
  }

  return { source: "external", sourceLabel: "外部路径", pluginKey: null, family: "external" };
}

function pluginKeyFromPath(name, absolutePath) {
  const prefix = name.includes(":") ? name.split(":")[0] : null;
  if (prefix) {
    const marketplace = absolutePath.includes("/openai-curated/")
      ? "openai-curated"
      : absolutePath.includes("/openai-bundled/")
        ? "openai-bundled"
        : absolutePath.includes("/openai-primary-runtime/")
          ? "openai-primary-runtime"
          : absolutePath.includes("/openai-codex/")
            ? "openai-codex"
            : absolutePath.includes("/claude-installed-local/")
              ? "claude-installed-local"
              : "plugin";
    return `${prefix}@${marketplace}`;
  }

  const cacheMarker = "/.codex/plugins/cache/";
  const afterCache = absolutePath.slice(absolutePath.indexOf(cacheMarker) + cacheMarker.length);
  const parts = afterCache.split("/");
  if (parts[0] === "claude-installed-local" && parts[1]) return `${parts[1]}@claude-installed-local`;
  if (parts[0] === "openai-curated" && parts[1]) return `${parts[1]}@openai-curated`;
  if (parts[0] === "openai-bundled" && parts[1]) return `${parts[1]}@openai-bundled`;
  if (parts[0] === "openai-primary-runtime" && parts[1]) return `${parts[1]}@openai-primary-runtime`;
  return parts.slice(0, 2).join("@");
}

function classifyFamily(name) {
  const slug = slugFromName(name);
  if (/^(baoyu|wechat|twitter|card-|copywriting|article|brand|marketing|news|social)/.test(slug)) return "content";
  if (/(video|audio|music|tts|asr|podcast|remotion|sora|seedance|fal|venice|replicate|imagen|image|photo|gif|screenshot|clipper|downloader|xunlei|xl720|cilixiong|youtube)/.test(slug)) return "media";
  if (/(frontend|web|ui|ux|design|figma|shadcn|threejs|gsap|canvas|d3|swiftui|appkit|ios|macos|flutter)/.test(slug)) return "frontend";
  if (/(cloudflare|supabase|github|mcp|codex|chrome|browser|agent|debug|test|review|python|rust|go|node|api|database|postgres|docker|deploy|security)/.test(slug)) return "engineering";
  if (/(doc|pdf|ppt|slide|deck|xlsx|spreadsheet|presentation|report)/.test(slug)) return "documents";
  if (/(template|frame|hero|poster|theme)/.test(slug)) return "templates";
  return "general";
}

function recommend(skill, context) {
  const slug = skill.slug;
  const plugin = skill.pluginKey || "";

  if (skill.source === "system") {
    return rec("keep", 98, "Codex 系统/运行时技能。除非你在调试运行时，否则建议保留。");
  }

  if (plugin === "ecc@claude-installed-local") {
    return rec("disable-plugin", 94, "当前最大的技能数量来源。除非你经常使用 ECC 的工程工作流，否则建议禁用整个插件。");
  }

  if (plugin === "oh-my-claudecode@claude-installed-local") {
    return rec("review", 72, "多 Agent 工作流插件。只有经常使用 OMC 时才保留，否则可以考虑禁用插件。");
  }

  if (/^(browser|chrome|computer-use)@/.test(plugin)) {
    return rec("keep", 95, "本地自动化核心插件，和你要求的默认 Chrome 验证流程直接相关，建议保留。");
  }

  if (/^(build-web-apps|codex)@/.test(plugin)) {
    return rec("keep", 86, "常用开发工作流插件，技能数量适中，建议保留。");
  }

  if (/^(build-ios-apps|build-macos-apps|cloudflare|figma|hugging-face|hyperframes|remotion|supabase)@/.test(plugin)) {
    return rec("review", 70, "领域型插件。最近不做这个方向时，可以禁用以减少上下文负担。");
  }

  if (/^(documents|presentations|spreadsheets|sites)@/.test(plugin)) {
    return rec("review", 66, "任务型插件。经常创建这类文档/站点/表格时保留，否则复核。");
  }

  if (skill.source === "external") {
    return rec("archive", 80, "不在统一的 ~/.agents/skills 根目录内。建议迁移到主目录或归档。");
  }

  if (context.hashDuplicates > 1) {
    return rec("review", 82, "存在内容完全相同的副本。建议只保留一个规范副本。");
  }

  if (context.slugDuplicates > 1) {
    return rec("review", 74, "同名能力出现在多个位置。建议保留维护最好的一份。");
  }

  if (/^(codex-|mcp-builder|playwright|webapp-testing|agent-browser|content-parser|doc-coauthoring)$/.test(slug)) {
    return rec("keep", 84, "本地工具/Codex 工作流相关技能，和当前使用方式匹配，建议保留。");
  }

  if (/(xunlei|xl720|cilixiong|youtube|media-downloader|video-downloader|asr|tts|wechat-publisher|baoyu-youtube|baoyu-url|baoyu-translate)/.test(slug)) {
    return rec("keep", 78, "自定义媒体/内容自动化技能。如果仍在你的活跃流程里，建议保留。");
  }

  if (/(template|frame-|card-|hero|poster|retro|quarterly|year-in-review)/.test(slug)) {
    return rec("archive", 72, "看起来像一次性创意模板技能。不常复用就归档/删除。");
  }

  if (/(fal-|venice-|replicate|imagen|seedance|sora|minimax|nanobanana|pixelbin)/.test(slug)) {
    return rec("review", 76, "特定供应商的媒体技能。只保留你实际使用的供应商。");
  }

  if (/(figma|swiftui|flutter|gsap|threejs|design-|ui-|frontend-)/.test(slug)) {
    return rec("review", 68, "设计/前端类技能。建议只留最常用、质量最高的几项，重叠项归档。");
  }

  if (/^(baoyu-|paseo|skilless)/.test(slug)) {
    return rec("review", 65, "个人/自定义技能族。保留活跃流程，旧实验归档。");
  }

  return rec("review", 58, "没有明显判断信号。按最近是否使用、描述是否仍有价值来决定。");
}

function rec(action, confidence, reason) {
  return { action, confidence, reason };
}

function actionLabel(action) {
  return {
    keep: "保留",
    review: "复核",
    archive: "归档/删除",
    "disable-plugin": "禁用插件",
  }[action] || action;
}

function countBy(items, key) {
  const counts = {};
  for (const item of items) counts[item[key]] = (counts[item[key]] || 0) + 1;
  return counts;
}

const raw = execFileSync("codex", ["debug", "prompt-input", "skill audit data snapshot"], {
  encoding: "utf8",
  maxBuffer: 32 * 1024 * 1024,
});
const promptInput = JSON.parse(raw);
const strings = collectStrings(promptInput);
const skillsText = strings.find((text) => text.includes("### Skill roots") && text.includes("### Available skills"));
if (!skillsText) throw new Error("Could not find skills block in codex debug prompt-input output.");

const roots = parseRoots(skillsText);
const pluginConfig = parsePluginConfig();
const parsed = parseAvailableSkills(skillsText);
const baseSkills = parsed.map((entry, index) => {
  const absolutePath = resolveFileRef(entry.fileRef, roots);
  let content = "";
  let stat = null;
  let hash = null;
  let frontMatter = {};

  if (fs.existsSync(absolutePath)) {
    content = fs.readFileSync(absolutePath, "utf8");
    stat = fs.statSync(absolutePath);
    hash = crypto.createHash("sha256").update(content).digest("hex");
    frontMatter = parseFrontMatter(content);
  }

  const classification = classifySkill(entry.name, absolutePath);
  const slug = slugFromName(entry.name);
  return {
    id: `${index + 1}-${entry.name}`,
    name: entry.name,
    slug,
    fileRef: entry.fileRef,
    path: absolutePath,
    description: frontMatter.description || "",
    frontMatterName: frontMatter.name || "",
    source: classification.source,
    sourceLabel: classification.sourceLabel,
    family: classification.family,
    pluginKey: classification.pluginKey,
    pluginEnabled: classification.pluginKey ? pluginConfig[classification.pluginKey]?.enabled ?? null : null,
    exists: fs.existsSync(absolutePath),
    hash,
    sizeBytes: stat?.size || 0,
    modifiedAt: stat ? stat.mtime.toISOString() : null,
  };
});

const hashCounts = countBy(baseSkills.filter((skill) => skill.hash), "hash");
const slugCounts = countBy(baseSkills, "slug");

const skills = baseSkills.map((skill) => {
  const context = {
    hashDuplicates: skill.hash ? hashCounts[skill.hash] || 0 : 0,
    slugDuplicates: slugCounts[skill.slug] || 0,
  };
  const recommendation = recommend(skill, context);
  return {
    ...skill,
    duplicateHashCount: context.hashDuplicates,
    duplicateSlugCount: context.slugDuplicates,
    recommendation: {
      ...recommendation,
      label: actionLabel(recommendation.action),
    },
  };
});

const pluginSummaries = Object.values(
  skills.reduce((groups, skill) => {
    const key = skill.pluginKey || (skill.source === "system" ? "system" : "user-skills");
    groups[key] ||= {
      key,
      source: skill.source,
      enabled: skill.pluginKey ? skill.pluginEnabled : true,
      count: 0,
      keep: 0,
      review: 0,
      archive: 0,
      disablePlugin: 0,
      families: {},
    };
    groups[key].count += 1;
    groups[key].families[skill.family] = (groups[key].families[skill.family] || 0) + 1;
    if (skill.recommendation.action === "keep") groups[key].keep += 1;
    if (skill.recommendation.action === "review") groups[key].review += 1;
    if (skill.recommendation.action === "archive") groups[key].archive += 1;
    if (skill.recommendation.action === "disable-plugin") groups[key].disablePlugin += 1;
    return groups;
  }, {})
).sort((a, b) => b.count - a.count || a.key.localeCompare(b.key));

const counts = {
  total: skills.length,
  bySource: countBy(skills, "source"),
  byFamily: countBy(skills, "family"),
  byAction: skills.reduce((counts, skill) => {
    const action = skill.recommendation.action;
    counts[action] = (counts[action] || 0) + 1;
    return counts;
  }, {}),
};

const data = {
  generatedAt: new Date().toISOString(),
  home,
  repoRoot,
  configPath,
  counts,
  roots,
  pluginSummaries,
  skills,
  strategy: [
    {
      title: "优先处理 ECC",
      detail: "如果你不主动使用 ECC 工作流，先禁用 ecc@claude-installed-local。它贡献的技能数量最多。",
      command: '[plugins."ecc@claude-installed-local"] enabled = false',
    },
    {
      title: "保留本地自动化核心",
      detail: "Chrome、Browser、Computer Use、Codex、Build Web Apps 支撑日常编码和默认 Chrome 验证，建议保留。",
      command: "",
    },
    {
      title: "归档低频本地模板",
      detail: "低频创意模板建议先移动到归档目录。确认不再需要后再删除，避免误删自定义工作流。",
      command: "mkdir -p ~/.agents/skills-archive/YYYYMMDD",
    },
  ],
};

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(
  outputPath,
  `window.SKILL_AUDIT_DATA = ${JSON.stringify(data, null, 2)};\n`,
  "utf8",
);

console.log(`Wrote ${outputPath}`);
console.log(`Skills: ${counts.total}`);
console.log(`Top source counts: ${JSON.stringify(counts.bySource)}`);
