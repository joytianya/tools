import { execFileSync } from "node:child_process";
import { existsSync, realpathSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const MARKER = "/*codex-patch:chrome-native-pipe-fallback*/";
const TARGET = "scripts/browser-client.mjs";
const CODEX_APP = process.env.CODEX_APP || "/Applications/Codex.app";

function appExecutable() {
  try {
    return execFileSync(
      "/usr/bin/plutil",
      ["-extract", "CFBundleExecutable", "raw", "-o", "-", join(CODEX_APP, "Contents/Info.plist")],
      { encoding: "utf8" },
    ).trim();
  } catch {
    return "";
  }
}

function chromePluginRoots() {
  const home = process.env.HOME;
  if (!home) {
    throw new Error("HOME is not set");
  }

  const roots = [];
  const chromeCache = join(home, ".codex/plugins/cache/openai-bundled/chrome");
  roots.push(join(chromeCache, "latest"));
  roots.push(join(home, ".codex/.tmp/bundled-marketplaces/openai-bundled/plugins/chrome"));

  roots.push(join(CODEX_APP, "Contents/Resources/plugins/openai-bundled/plugins/chrome"));
  return roots;
}

function uniqueExistingTargets() {
  const seen = new Set();
  const targets = [];

  for (const root of chromePluginRoots()) {
    const target = join(root, TARGET);
    if (!existsSync(target)) {
      continue;
    }
    const real = realpathSync(target);
    if (seen.has(real)) {
      continue;
    }
    seen.add(real);
    targets.push(real);
  }

  return targets;
}

function patchBrowserClient(path) {
  const source = readFileSync(path, "utf8");
  const fallback =
    'function codexPatchChromeNativePipeFallback(t){return new Promise((r,n)=>{let o=codexPatchChromeCreateConnection(t),i=!1;o.once("connect",()=>{i=!0,r(o)}),o.once("error",s=>{i||n(s)})})}';
  const patchedBlock = (errorFunctionName, bridgeFunctionName) =>
    `import{createConnection as codexPatchChromeCreateConnection}from"node:net";${fallback}` +
    `function ${errorFunctionName}(){return"privileged native pipe bridge is not available; browser-client native pipe fallback is active"}` +
    `function ${bridgeFunctionName}(){return{createConnection:codexPatchChromeNativePipeFallback}}` +
    MARKER;

  if (source.includes(MARKER)) {
    return "already-patched";
  }

  const needle =
    'function eh(){let e=sy();return e?`privileged native pipe bridge is not available; browser-client is not trusted. Load browser-client from the ${e} marketplace directory.`:"privileged native pipe bridge is not available; browser-client is not trusted"}function th(){let e=globalThis.nodeRepl?.nativePipe;return e==null||typeof e.createConnection!="function"?null:e}';
  const replacement =
    patchedBlock("eh", "th");

  if (!source.includes(needle)) {
    const genericNativePipeBridge =
      /function ([A-Za-z_$][\w$]*)\(\)\{let e="privileged native pipe bridge is not available; browser-client is not trusted";[\s\S]*?\}function ([A-Za-z_$][\w$]*)\(\)\{let e=globalThis\.nodeRepl\?\.nativePipe;return e==null\|\|typeof e\.createConnection!="function"\?null:e\}/;
    const match = source.match(genericNativePipeBridge);
    if (!match) {
      return "unsupported-shape-skipped";
    }
    const [, errorFunctionName, bridgeFunctionName] = match;
    writeFileSync(
      path,
      source.slice(0, match.index) +
        patchedBlock(errorFunctionName, bridgeFunctionName) +
        source.slice(match.index + match[0].length),
    );
    return "patched";
  }

  writeFileSync(path, source.replace(needle, replacement));
  return "patched";
}

const executable = appExecutable();
if (executable !== "Codex") {
  console.log(
    `[patch] Legacy Chrome browser-client patch requires CFBundleExecutable=Codex; found ${executable || "unknown"}. Leaving bundled plugins unchanged.`,
  );
  process.exit(0);
}

const targets = uniqueExistingTargets();
if (targets.length === 0) {
  throw new Error("Cannot find bundled Chrome browser-client.mjs");
}

for (const target of targets) {
  console.log(`[patch] Chrome Browser Use native pipe fallback: ${patchBrowserClient(target)} ${target}`);
}
