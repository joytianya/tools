#!/usr/bin/env node

import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { homedir } from "node:os";

const HOME = homedir();
const CODEX_HOME = process.env.CODEX_HOME || join(HOME, ".codex");
const GLOBAL_STATE_PATH = join(CODEX_HOME, ".codex-global-state.json");
const CODEX_APP_CONFIG_PATH = join(CODEX_HOME, "codex-app", "config.json");
const APPLY_DEEPLINK = "codex://codex-app/apply-config";

const args = new Set(process.argv.slice(2));
const dryRun = args.has("--dry-run");
const apply = args.has("--apply");

if (args.has("-h") || args.has("--help")) {
  console.log(`Usage:
  $TOOLS_HOME/bin/codex-sync-remote-ssh-projects.sh [--apply] [--dry-run]

Reads Codex Desktop's saved SSH remote connections and writes:
  ${CODEX_APP_CONFIG_PATH}

Options:
  --apply    Ask a running Codex.app to apply the config via ${APPLY_DEEPLINK}
  --dry-run  Print the generated config without writing it
`);
  process.exit(0);
}

function readJson(path, fallback) {
  if (!existsSync(path)) return fallback;
  return JSON.parse(readFileSync(path, "utf8"));
}

function normalizePath(path) {
  return path.trim().replace(/\/+$/, "") || path.trim();
}

function sshUser(alias) {
  const result = spawnSync("ssh", ["-G", alias], {
    encoding: "utf8",
    timeout: 5000,
  });
  if (result.status !== 0) return null;
  const line = result.stdout
    .split(/\r?\n/)
    .find((entry) => entry.toLowerCase().startsWith("user "));
  const user = line?.slice(5).trim();
  return user || null;
}

function defaultHomePath(alias) {
  const user = sshUser(alias);
  if (!user) return null;
  return user === "root" ? "/root" : `/home/${user}`;
}

function projectKey(project) {
  return normalizePath(project.remotePath);
}

function addProject(projects, project) {
  const remotePath = normalizePath(project.remotePath);
  if (!remotePath) return;
  if (projects.some((item) => projectKey(item) === remotePath)) return;
  projects.push({
    remotePath,
    ...(project.label?.trim() ? { label: project.label.trim() } : {}),
  });
}

const globalState = readJson(GLOBAL_STATE_PATH, {});
const existingConfig = readJson(CODEX_APP_CONFIG_PATH, { version: 1 });
const managedConnections = globalState["codex-managed-remote-connections"] ?? [];
const remoteProjects = globalState["remote-projects"] ?? [];
const existingByAlias = new Map(
  (existingConfig.remoteConnections ?? []).map((connection) => [
    connection.sshAlias,
    connection,
  ]),
);

const generatedAliases = new Set();
const remoteConnections = [];

for (const connection of managedConnections) {
  const alias = connection.alias?.trim();
  if (!alias || generatedAliases.has(alias)) continue;

  generatedAliases.add(alias);
  const projects = [];
  const homePath = defaultHomePath(alias);
  if (homePath) {
    addProject(projects, {
      remotePath: homePath,
      label: connection.displayName?.trim() || alias,
    });
  }

  for (const project of existingByAlias.get(alias)?.projects ?? []) {
    addProject(projects, project);
  }

  for (const project of remoteProjects.filter(
    (project) => project.hostId === connection.hostId,
  )) {
    addProject(projects, {
      remotePath: project.remotePath,
      label: project.label,
    });
  }

  remoteConnections.push({ sshAlias: alias, projects });
}

for (const connection of existingConfig.remoteConnections ?? []) {
  if (!generatedAliases.has(connection.sshAlias)) {
    remoteConnections.push(connection);
  }
}

const nextConfig = {
  version: 1,
  ...(Number.isInteger(existingConfig.remoteConnectionMaxRetryAttempts)
    ? {
        remoteConnectionMaxRetryAttempts:
          existingConfig.remoteConnectionMaxRetryAttempts,
      }
    : {}),
  remoteConnections,
};

const json = `${JSON.stringify(nextConfig, null, 2)}\n`;

if (dryRun) {
  process.stdout.write(json);
  process.exit(0);
}

mkdirSync(dirname(CODEX_APP_CONFIG_PATH), { recursive: true });
writeFileSync(CODEX_APP_CONFIG_PATH, json);

console.log(`Wrote ${CODEX_APP_CONFIG_PATH}`);
console.log(
  `Synced ${remoteConnections.length} SSH remote connection(s): ${remoteConnections
    .map((connection) => connection.sshAlias)
    .join(", ")}`,
);

if (apply) {
  execFileSync("open", [APPLY_DEEPLINK], { stdio: "inherit" });
  console.log(`Requested Codex.app config apply via ${APPLY_DEEPLINK}`);
}
