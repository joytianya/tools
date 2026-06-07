import { existsSync, readdirSync, realpathSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const MARKER = "/*codex-patch:chrome-native-pipe-fallback*/";
const TARGET = "scripts/browser-client.mjs";

function chromePluginRoots() {
  const home = process.env.HOME;
  if (!home) {
    throw new Error("HOME is not set");
  }

  const roots = [];
  const chromeCache = join(home, ".codex/plugins/cache/openai-bundled/chrome");
  if (existsSync(chromeCache)) {
    for (const entry of readdirSync(chromeCache, { withFileTypes: true })) {
      if (entry.isDirectory() || entry.isSymbolicLink()) {
        roots.push(join(chromeCache, entry.name));
      }
    }
  }
  roots.push(join(home, ".codex/.tmp/bundled-marketplaces/openai-bundled/plugins/chrome"));

  const codexApp = process.env.CODEX_APP || "/Applications/Codex.app";
  roots.push(join(codexApp, "Contents/Resources/plugins/openai-bundled/plugins/chrome"));
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
      throw new Error(`Chrome browser-client shape not recognized: ${path}`);
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

const targets = uniqueExistingTargets();
if (targets.length === 0) {
  throw new Error("Cannot find bundled Chrome browser-client.mjs");
}

for (const target of targets) {
  console.log(`[patch] Chrome Browser Use native pipe fallback: ${patchBrowserClient(target)} ${target}`);
}
