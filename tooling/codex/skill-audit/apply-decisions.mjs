#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const home = os.homedir();
const dataPath = path.join(here, "generated", "skills-data.js");
const configPath = path.join(home, ".codex", "config.toml");
const args = process.argv.slice(2);

const options = {
  suggested: args.includes("--suggested"),
  dryRun: args.includes("--dry-run") || !args.includes("--apply"),
  apply: args.includes("--apply"),
  yes: args.includes("--yes"),
  decisionsPath: valueAfter("--decisions"),
};

if (args.includes("--help")) {
  printHelp();
  process.exit(0);
}

if (!options.suggested && !options.decisionsPath) {
  fail("请传入 --suggested，或使用 --decisions <导出的 JSON 文件>。");
}

if (options.apply && !options.yes) {
  fail("真正执行需要显式传入 --apply --yes。建议先运行 --dry-run。");
}

const data = loadData();
const decisions = options.suggested ? suggestedDecisions(data.skills) : exportedDecisions(options.decisionsPath, data.skills);
const plan = buildPlan(decisions);

printPlan(plan, options.dryRun);

if (options.dryRun) {
  console.log("\n这是预览模式，没有修改任何文件。真正执行请加 --apply --yes。");
  process.exit(0);
}

applyPlan(plan);
console.log("\n执行完成。建议重启 Codex 会话后重新生成审核数据。");

function valueAfter(flag) {
  const index = args.indexOf(flag);
  return index >= 0 ? args[index + 1] : null;
}

function printHelp() {
  console.log(`技能审核执行器

用法：
  node skill-audit/apply-decisions.mjs --suggested --dry-run
  node skill-audit/apply-decisions.mjs --suggested --apply --yes
  node skill-audit/apply-decisions.mjs --decisions ~/Downloads/skill-audit-decisions.json --dry-run

安全边界：
  - 保留：不操作
  - 复核：不操作
  - 归档/删除：移动到 ~/.agents/skills-archive/<时间>/，不永久删除
  - 禁用插件：修改 ~/.codex/config.toml，将插件 enabled 设为 false
`);
}

function loadData() {
  const source = fs.readFileSync(dataPath, "utf8");
  const prefix = "window.SKILL_AUDIT_DATA = ";
  if (!source.startsWith(prefix)) fail(`无法解析 ${dataPath}`);
  return JSON.parse(source.slice(prefix.length).replace(/;\s*$/, ""));
}

function suggestedDecisions(skills) {
  return skills.map((skill) => ({
    skill,
    decision: skill.recommendation.action,
  }));
}

function exportedDecisions(decisionsPath, skills) {
  if (!decisionsPath) fail("--decisions 后缺少 JSON 文件路径。");
  const absolute = path.resolve(decisionsPath.replace(/^~/, home));
  const exported = JSON.parse(fs.readFileSync(absolute, "utf8"));
  const byPath = new Map(skills.map((skill) => [skill.path, skill]));
  const byName = new Map(skills.map((skill) => [skill.name, skill]));

  return (exported.decisions || [])
    .map((item) => ({
      skill: byPath.get(item.path) || byName.get(item.name),
      decision: item.decision,
    }))
    .filter((item) => item.skill && item.decision);
}

function buildPlan(decisions) {
  const plugins = new Map();
  const archives = [];
  const skipped = [];

  for (const item of decisions) {
    const { skill, decision } = item;
    if (!decision || decision === "keep" || decision === "review") {
      skipped.push({ skill, reason: decision === "review" ? "复核项不自动执行" : "无需操作" });
      continue;
    }

    if (decision === "disable-plugin") {
      if (skill.pluginKey) {
        plugins.set(skill.pluginKey, { key: skill.pluginKey });
      } else {
        skipped.push({ skill, reason: "不是插件技能，无法禁用插件" });
      }
      continue;
    }

    if (decision === "archive") {
      const archiveCandidate = archiveCandidateFor(skill);
      if (archiveCandidate) {
        archives.push(archiveCandidate);
      } else {
        skipped.push({ skill, reason: "系统/插件缓存技能不自动归档" });
      }
      continue;
    }

    skipped.push({ skill, reason: `未知决策：${decision}` });
  }

  return {
    plugins: [...plugins.values()].sort((a, b) => a.key.localeCompare(b.key)),
    archives,
    skipped,
  };
}

function archiveCandidateFor(skill) {
  if (!skill.path || !skill.path.endsWith("/SKILL.md")) return null;
  if (skill.source === "system" || skill.source === "plugin") return null;

  const root = path.dirname(skill.path);
  const allowedRoots = [
    path.join(home, ".agents", "skills"),
    path.join(home, ".agents", ".agents", "skills"),
    path.join(home, ".claude", "skills"),
  ];

  if (!allowedRoots.some((allowed) => root.startsWith(`${allowed}${path.sep}`))) return null;
  if (root.includes(`${path.sep}.system${path.sep}`)) return null;

  return {
    name: skill.name,
    source: root,
  };
}

function printPlan(plan, dryRun) {
  console.log(dryRun ? "执行计划预览：" : "即将执行：");
  console.log(`- 禁用插件：${plan.plugins.length} 个`);
  for (const plugin of plan.plugins) console.log(`  - ${plugin.key}`);

  console.log(`- 归档技能目录：${plan.archives.length} 个`);
  for (const item of plan.archives) console.log(`  - ${item.name}: ${item.source}`);

  const skippedReview = plan.skipped.filter((item) => item.reason === "复核项不自动执行").length;
  console.log(`- 跳过复核项：${skippedReview} 个`);
}

function applyPlan(plan) {
  if (plan.plugins.length) disablePlugins(plan.plugins.map((plugin) => plugin.key));
  if (plan.archives.length) archiveSkills(plan.archives);
}

function disablePlugins(pluginKeys) {
  if (!fs.existsSync(configPath)) fail(`找不到配置文件：${configPath}`);
  const timestamp = timestampForPath();
  const backupPath = `${configPath}.backup-before-skill-audit-${timestamp}`;
  let config = fs.readFileSync(configPath, "utf8");
  fs.copyFileSync(configPath, backupPath);

  for (const key of pluginKeys) {
    config = setPluginEnabledFalse(config, key);
  }

  fs.writeFileSync(configPath, config, "utf8");
  console.log(`已备份配置：${backupPath}`);
}

function setPluginEnabledFalse(config, key) {
  const header = `[plugins."${key}"]`;
  const lines = config.split("\n");
  const start = lines.findIndex((line) => line.trim() === header);

  if (start === -1) {
    lines.push("", header, "enabled = false");
    return lines.join("\n");
  }

  let end = lines.length;
  for (let index = start + 1; index < lines.length; index += 1) {
    if (/^\[.+\]$/.test(lines[index].trim())) {
      end = index;
      break;
    }
  }

  let enabledIndex = -1;
  for (let index = start + 1; index < end; index += 1) {
    if (/^enabled\s*=/.test(lines[index].trim())) {
      enabledIndex = index;
      break;
    }
  }

  if (enabledIndex === -1) {
    lines.splice(start + 1, 0, "enabled = false");
  } else {
    lines[enabledIndex] = "enabled = false";
  }

  return lines.join("\n");
}

function archiveSkills(items) {
  const archiveRoot = path.join(home, ".agents", "skills-archive", timestampForPath());
  fs.mkdirSync(archiveRoot, { recursive: true });

  for (const item of items) {
    if (!fs.existsSync(item.source)) {
      console.log(`跳过不存在目录：${item.source}`);
      continue;
    }

    const dest = uniqueDestination(archiveRoot, path.basename(item.source));
    fs.renameSync(item.source, dest);
    console.log(`已归档：${item.source} -> ${dest}`);
  }
}

function uniqueDestination(root, basename) {
  let candidate = path.join(root, basename);
  let suffix = 2;
  while (fs.existsSync(candidate)) {
    candidate = path.join(root, `${basename}-${suffix}`);
    suffix += 1;
  }
  return candidate;
}

function timestampForPath() {
  const date = new Date();
  const pad = (value) => String(value).padStart(2, "0");
  return [
    date.getFullYear(),
    pad(date.getMonth() + 1),
    pad(date.getDate()),
    "-",
    pad(date.getHours()),
    pad(date.getMinutes()),
    pad(date.getSeconds()),
  ].join("");
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
