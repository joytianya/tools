import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import {
  lstatSync,
  readFileSync,
  readlinkSync,
  readdirSync,
  statSync,
} from "node:fs";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../../", import.meta.url));

const canonicalFiles = [
  "README.md",
  "docs/STRUCTURE.md",
  "docs/archive/2026-06-layout-reorg/migrate.sh",
  "docs/archive/2026-06-layout-reorg/reorg-proposal.md",
  "apps/codex/desktop-patch/codex-after-update-fix.sh",
  "apps/codex/desktop-patch/fix-codex-plugins.sh",
  "apps/codex/desktop-patch/patch-codex-plugins.mjs",
  "apps/codex/desktop-patch/patch-codex-chrome-browser-use.mjs",
  "apps/codex/desktop-patch/test-patch-codex-plugins.mjs",
  "apps/codex/desktop-patch/SKILL.md",
  "apps/codex/desktop-recovery/codex-restore-pinned-threads.sh",
  "apps/codex/remote-control/codex-daemon-watchdog.sh",
  "apps/codex/remote-control/codex-clean-code-sign-clones.sh",
  "apps/codex/remote-control/ssh_tunnel.sh",
  "apps/vibe-kanban/migrations/vibe-kanban-salvage.sh",
  "platform/shell/universal-installer.sh",
  "platform/network/proxy7980.py",
  "integrations/paseo/edge-tts/paseo-edge-tts-bridge.mjs",
  "tooling/codex/skill-audit/generate-data.mjs",
  "tooling/codex/skill-audit/apply-decisions.mjs",
  "tooling/codex/skill-audit/index.html",
];

const wrappers = {
  "bin/codex-after-update-fix.sh": "apps/codex/desktop-patch/codex-after-update-fix.sh",
  "bin/fix-codex-plugins.sh": "apps/codex/desktop-patch/fix-codex-plugins.sh",
  "bin/patch-codex-chrome-browser-use.sh": "apps/codex/desktop-patch/patch-codex-chrome-browser-use.mjs",
  "bin/codex-restore-pinned-threads.sh": "apps/codex/desktop-recovery/codex-restore-pinned-threads.sh",
  "bin/codex-add-remote-server.sh": "apps/codex/remote-control/codex-add-remote-server.sh",
  "bin/codex-remote-account-switch.sh": "apps/codex/remote-control/codex-remote-account-switch.sh",
  "bin/codex-restart-daemons.sh": "apps/codex/remote-control/codex-restart-daemons.sh",
  "bin/codex-daemon-watchdog.sh": "apps/codex/remote-control/codex-daemon-watchdog.sh",
  "bin/codex-gaccode-cli-wrapper.sh": "apps/codex/remote-control/codex-gaccode-cli-wrapper.sh",
  "bin/codex-gaccode-launch-env.sh": "apps/codex/remote-control/codex-gaccode-launch-env.sh",
  "bin/codex-sync-auth-to-remotes.sh": "apps/codex/remote-control/codex-sync-auth-to-remotes.sh",
  "bin/codex-sync-remote-ssh-projects.sh": "apps/codex/remote-control/codex-sync-remote-ssh-projects.mjs",
  "bin/ssh-tunnel.sh": "apps/codex/remote-control/ssh_tunnel.sh",
  "bin/proxy7980.sh": "platform/network/proxy7980.py",
  "bin/shell-setup.sh": "platform/shell/universal-installer.sh",
  "bin/paseo-edge-tts-bridge.sh": "integrations/paseo/edge-tts/paseo-edge-tts-bridge.mjs",
  "bin/vibe-kanban-salvage.sh": "apps/vibe-kanban/migrations/vibe-kanban-salvage.sh",
  "bin/skill-audit-generate.sh": "tooling/codex/skill-audit/generate-data.mjs",
  "bin/skill-audit-apply.sh": "tooling/codex/skill-audit/apply-decisions.mjs",
};

function activeMarkdownFiles(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) return activeMarkdownFiles(path);
    return entry.isFile() && entry.name.endsWith(".md") ? [path] : [];
  });
}

test("canonical modules exist in the hybrid taxonomy", () => {
  for (const path of canonicalFiles) {
    assert.doesNotThrow(() => statSync(join(root, path)), `missing ${path}`);
  }
});

test("stable bin wrappers are executable and target canonical implementations", () => {
  for (const [wrapper, target] of Object.entries(wrappers)) {
    const path = join(root, wrapper);
    const content = readFileSync(path, "utf8");
    assert.ok(statSync(path).mode & 0o111, `${wrapper} is not executable`);
    assert.match(content, /\bexec\b/, `${wrapper} must use exec`);
    assert.ok(content.includes(target), `${wrapper} does not target ${target}`);
  }
});

test("legacy Codex directory paths are temporary relative symlinks", () => {
  const expected = {
    "codex-patch": "apps/codex/desktop-patch",
    "codex-remote": "apps/codex/remote-control",
  };

  for (const [path, target] of Object.entries(expected)) {
    const absolute = join(root, path);
    assert.ok(lstatSync(absolute).isSymbolicLink(), `${path} is not a symlink`);
    assert.equal(readlinkSync(absolute), target);
  }
});

test("generated, runtime, bundle, and private files are not tracked", () => {
  const tracked = execFileSync("git", ["ls-files"], { cwd: root, encoding: "utf8" });
  for (const forbidden of [
    "codex-beszel-sg-ops-access-key.csv",
    "main-B6erVVHq.js",
    "profile-visibility-WAr1jsej.js",
    "skills-data.js",
    "server.log",
    "server.pid",
  ]) {
    assert.ok(!tracked.includes(forbidden), `${forbidden} must not be tracked`);
  }
});

test("active documentation uses stable bin paths instead of old absolute implementation paths", () => {
  const docs = [
    join(root, "README.md"),
    join(root, "apps/codex/desktop-patch/SKILL.md"),
    ...activeMarkdownFiles(join(root, "apps/codex/remote-control")),
  ];
  const oldPath = /(?:\/Users\/matrix\/projects\/dev\/tools|~\/projects\/dev\/tools)\/(?:codex-patch|codex-remote|net\/ssh_tunnel|tts|skill-audit|shell-setup|vibe-kanban)/;

  for (const path of docs) {
    assert.doesNotMatch(readFileSync(path, "utf8"), oldPath, path);
  }
});
