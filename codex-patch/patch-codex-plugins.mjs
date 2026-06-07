import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const PLUGIN_AUTH_OPEN_MARKER = "/*codex-patch:plugin-auth-open*/";
const PLUGIN_ACCOUNT_FALLBACK_MARKER = "/*codex-patch:plugin-account-fallback*/";
const AUTH_ACCOUNT_FIELDS_MARKER = "/*codex-patch:auth-account-fields*/";
const PLUGINS_HOOK_LOADING_MARKER = "/*codex-patch:plugins-loading*/";
const PLUGINS_PAGE_LOADING_MARKER = "/*codex-patch:plugins-page-loading*/";
const WHAM_DESKTOP_AUTH_MARKER = "/*codex-patch:wham-desktop-auth*/";

export function patchExtractedCodexApp(root) {
  const assetsDir = join(root, "webview", "assets");
  if (!existsSync(assetsDir)) {
    throw new Error(`Cannot find webview assets directory: ${assetsDir}`);
  }

  const pluginAuth = patchPluginAuthGate(assetsDir);
  const accountFallback = patchPluginAccountFallback(assetsDir);
  const useAuthAccountFields = patchUseAuthAccountFields(assetsDir);
  const pluginsHookLoading = patchPluginsHookLoadingGate(assetsDir);
  const pluginsPageLoading = patchPluginsPageLoadingGate(assetsDir);
  const whamDesktopAuth = patchWhamDesktopAuth(root);
  return {
    pluginAuth: pluginAuth.status,
    pluginAuthPath: pluginAuth.path == null ? null : relative(root, pluginAuth.path),
    accountFallback: accountFallback.status,
    accountFallbackPath: accountFallback.path == null ? null : relative(root, accountFallback.path),
    useAuthAccountFields: useAuthAccountFields.status,
    useAuthAccountFieldsPath: useAuthAccountFields.path == null ? null : relative(root, useAuthAccountFields.path),
    pluginsHookLoading: pluginsHookLoading.status,
    pluginsHookLoadingPath: pluginsHookLoading.path == null ? null : relative(root, pluginsHookLoading.path),
    pluginsPageLoading: pluginsPageLoading.status,
    pluginsPageLoadingPath: pluginsPageLoading.path == null ? null : relative(root, pluginsPageLoading.path),
    whamDesktopAuth: whamDesktopAuth.status,
    whamDesktopAuthPath: whamDesktopAuth.path == null ? null : relative(root, whamDesktopAuth.path),
  };
}

function patchPluginAuthGate(assetsDir) {
  const assetNames = readdirSync(assetsDir);
  const candidates = [
    ...assetNames.filter((name) => /^plugin-auth-.*\.js$/.test(name)),
    ...assetNames.filter((name) => /^gradient-.*\.js$/.test(name)),
  ].map((name) => join(assetsDir, name));

  if (candidates.length === 0) {
    return { path: null, status: "not-found" };
  }

  for (const path of candidates) {
    const data = readFileSync(path, "utf8");
    if (!isPluginAuthGateCandidate(path, data)) {
      continue;
    }

    const alreadyOpen = /function\s+([A-Za-z_$][\w$]*)\(([^)]*)\)\{return !1(?:\/\*codex-patch:plugin-auth-open\*\/)?\}export\{\1 as t\};?/.test(
      data,
    );
    if (alreadyOpen || data.includes(PLUGIN_AUTH_OPEN_MARKER)) {
      return { path, status: "already-patched" };
    }

    const patched = data.replace(
      /function\s+([A-Za-z_$][\w$]*)\(([^)]*)\)\{return \2!==`chatgpt`\}export\{\1 as t\};?/,
      (_match, functionName, argumentName) =>
        `function ${functionName}(${argumentName}){return !1${PLUGIN_AUTH_OPEN_MARKER}}export{${functionName} as t};`,
    );

    if (patched !== data) {
      writeFileSync(path, patched);
      return { path, status: "patched" };
    }

    const genericPatched = data.replace(
      /function\s+([A-Za-z_$][\w$]*)\(([^)]*)\)\{return \2!==`chatgpt`\}/,
      (_match, functionName, argumentName) =>
        `function ${functionName}(${argumentName}){return !1${PLUGIN_AUTH_OPEN_MARKER}}`,
    );

    if (genericPatched !== data) {
      writeFileSync(path, genericPatched);
      return { path, status: "patched" };
    }
  }

  return { path: candidates[0], status: "pattern-not-found" };
}

function isPluginAuthGateCandidate(path, data) {
  if (/\/plugin-auth-[^/]+\.js$/.test(path)) {
    return true;
  }

  return (
    /\/gradient-[^/]+\.js$/.test(path) &&
    data.includes("new URL(`gradient-") &&
    /function\s+([A-Za-z_$][\w$]*)\(([^)]*)\)\{return \2!==`chatgpt`\}/.test(data)
  );
}

function patchPluginAccountFallback(assetsDir) {
  const candidates = readdirSync(assetsDir)
    .filter((name) => /^app-server-manager-signals-.*\.js$/.test(name))
    .map((name) => join(assetsDir, name));

  if (candidates.length === 0) {
    return { path: null, status: "not-found" };
  }

  for (const path of candidates) {
    const data = readFileSync(path, "utf8");
    if (data.includes(PLUGIN_ACCOUNT_FALLBACK_MARKER)) {
      const upgraded = upgradePluginAccountFallbackHelper(data);
      if (upgraded !== data) {
        writeFileSync(path, upgraded);
        return { path, status: "patched" };
      }
      return { path, status: "already-patched" };
    }

    if (!data.includes("async getAccount(){return this.sendRequest(`account/read`,{refreshToken:!1})}")) {
      continue;
    }

    const requestBridge = data.match(/function\s+([A-Za-z_$][\w$]*)\(e,t\)\{return [A-Za-z_$][\w$]*\.sendRequest\(e,t\)\}/);
    if (requestBridge == null) {
      continue;
    }

    const [, requestBridgeFunction] = requestBridge;
    const helperInserted = data.replace(requestBridge[0], (match) => `${match}${pluginAccountFallbackHelper(requestBridgeFunction)}`);
    const patched = helperInserted.replaceAll(
      "async getAccount(){return this.sendRequest(`account/read`,{refreshToken:!1})}",
      "async getAccount(){return codexPatchAccountForPlugins(this.hostId,()=>this.sendRequest(`account/read`,{refreshToken:!1}))}",
    );

    if (patched !== data) {
      writeFileSync(path, patched);
      return { path, status: "patched" };
    }
  }

  return { path: candidates[0], status: "pattern-not-found" };
}

function pluginAccountFallbackHelper(requestBridgeFunction) {
  return (
    [
      "async function codexPatchDecodeJwtPayload(e){try{let t=String(e??``).split(`.`)[1];if(t==null)return null;t=t.replaceAll(`-`,`+`).replaceAll(`_`,`/`);let n=(4-t.length%4)%4;return JSON.parse(globalThis.atob(`${t}${`=`.repeat(n)}`))}catch{return null}}",
      `async function codexPatchReadChatGptAccount(e){try{let t=await ${requestBridgeFunction}(\`codex-home\`,{hostId:e}),n=t?.codexHome;if(typeof n!==\`string\`||n.length===0)return null;let r=await ${requestBridgeFunction}(\`read-file\`,{hostId:e,path:\`\${n.replace(/[/]+$/,\`\`)}/auth.json\`}),i=JSON.parse(r?.contents??\`\`);if(i?.auth_mode!==\`chatgpt\`)return null;let a=i.tokens??{},o=codexPatchDecodeJwtPayload(a.id_token??a.access_token),s=o?.[\`https://api.openai.com/auth\`]??{},c=o?.[\`https://api.openai.com/profile\`]??{},l=typeof c.email===\`string\`?c.email:typeof o?.email===\`string\`?o.email:\`\`,u=typeof s.chatgpt_account_id===\`string\`?s.chatgpt_account_id:typeof a.account_id===\`string\`?a.account_id:null,d=typeof s.chatgpt_user_id===\`string\`?s.chatgpt_user_id:null,f=typeof s.chatgpt_plan_type===\`string\`?s.chatgpt_plan_type:\`unknown\`;return l.length===0&&u==null&&d==null?null:{account:{type:\`chatgpt\`,email:l,planType:f,accountId:u,userId:d},requiresOpenaiAuth:!1}}catch{return null}}`,
      "async function codexPatchAccountForPlugins(e,t){let n=await t();if(n?.account!=null||n?.requiresOpenaiAuth!==!1)return n;return(await codexPatchReadChatGptAccount(e))??n}",
    ].join("") + PLUGIN_ACCOUNT_FALLBACK_MARKER
  );
}

function upgradePluginAccountFallbackHelper(data) {
  let patched = data.replace(
    "l=typeof c.email===`string`?c.email:null,u=",
    "l=typeof c.email===`string`?c.email:typeof o?.email===`string`?o.email:``,u=",
  );
  patched = patched.replace("return l==null?null:{account:", "return l.length===0&&u==null&&d==null?null:{account:");
  return patched;
}

function patchUseAuthAccountFields(assetsDir) {
  const candidates = readdirSync(assetsDir)
    .filter((name) => /^use-auth-.*\.js$/.test(name))
    .map((name) => join(assetsDir, name));

  if (candidates.length === 0) {
    return { path: null, status: "not-found" };
  }

  for (const path of candidates) {
    const data = readFileSync(path, "utf8");
    if (data.includes(AUTH_ACCOUNT_FIELDS_MARKER) && !data.includes("accountId:null,userId:null")) {
      return { path, status: "already-patched" };
    }

    let patched = data;
    if (!patched.includes(AUTH_ACCOUNT_FIELDS_MARKER)) {
      patched = patched.replace(
        "planAtLogin:e.account?.type===`chatgpt`?e.account.planType:null}}",
        `planAtLogin:e.account?.type===\`chatgpt\`?e.account.planType:null,accountId:e.account?.type===\`chatgpt\`?e.account.accountId??null:null,userId:e.account?.type===\`chatgpt\`?e.account.userId??null:null${AUTH_ACCOUNT_FIELDS_MARKER}}}`,
      );
    }
    patched = patched.replace(/accountId:null,userId:null(,computeResidency:[^,}]+)?,setAuthMethod:_/, (_match, computeResidency) => {
      return `accountId:y.accountId??null,userId:y.userId??null${computeResidency ?? ""},setAuthMethod:_`;
    });

    if (patched !== data) {
      writeFileSync(path, patched);
      return { path, status: "patched" };
    }
  }

  return { path: candidates[0], status: "pattern-not-found" };
}

function patchPluginsHookLoadingGate(assetsDir) {
  const candidates = readdirSync(assetsDir)
    .filter((name) => /\.js$/.test(name))
    .map((name) => join(assetsDir, name))
    .filter((path) => {
      const data = readFileSync(path, "utf8");
      return (
        data.includes(PLUGINS_HOOK_LOADING_MARKER) ||
        (data.includes("availablePlugins") && data.includes("list-plugins"))
      );
    });

  for (const path of candidates) {
    const data = readFileSync(path, "utf8");
    if (data.includes(PLUGINS_HOOK_LOADING_MARKER)) {
      return { path, status: "already-patched" };
    }

    const patched = data.replace(
      /([A-Za-z_$][\w$]*)=([A-Za-z_$][\w$]*)&&([A-Za-z_$][\w$]*)\.isLoading\|\|([A-Za-z_$][\w$]*)\.isLoading\|\|([A-Za-z_$][\w$]*)\.isLoading\|\|([A-Za-z_$][\w$]*)\.isLoading\|\|([A-Za-z_$][\w$]*)\.isLoading,([A-Za-z_$][\w$]*)=\2&&\3\.isFetching\|\|\4\.isFetching\|\|\7\.isFetching/,
      (_match, loadingVar, rootsFlag, rootsQuery, pluginsQuery, _availabilityA, _availabilityB, _availabilityC, fetchingVar) =>
        `${loadingVar}=${PLUGINS_HOOK_LOADING_MARKER}${rootsFlag}&&${rootsQuery}.isLoading||${pluginsQuery}.isLoading,${fetchingVar}=${rootsFlag}&&${rootsQuery}.isFetching||${pluginsQuery}.isFetching`,
    );

    if (patched !== data) {
      writeFileSync(path, patched);
      return { path, status: "patched" };
    }
  }

  return { path: candidates[0] ?? null, status: candidates.length === 0 ? "not-found" : "pattern-not-found" };
}

function patchPluginsPageLoadingGate(assetsDir) {
  const candidates = [
    ...readdirSync(assetsDir).filter((name) => /^plugins-page-.*\.js$/.test(name)),
    ...readdirSync(assetsDir).filter((name) => /\.js$/.test(name) && !/^plugins-page-.*\.js$/.test(name)),
  ]
    .map((name) => join(assetsDir, name))
    .filter((path) => {
      const data = readFileSync(path, "utf8");
      return data.includes(PLUGINS_PAGE_LOADING_MARKER) || data.includes("plugins.page.loading");
    });

  for (const path of candidates) {
    const data = readFileSync(path, "utf8");
    if (data.includes(PLUGINS_PAGE_LOADING_MARKER)) {
      const tightened = data.replace(
        /([A-Za-z_$][\w$]*)=\/\*codex-patch:plugins-page-loading\*\/([A-Za-z_$][\w$]*)(?:\|\|[^,]+)?,/,
        (_match, loadingVar, pluginLoadingVar) => `${loadingVar}=${PLUGINS_PAGE_LOADING_MARKER}${pluginLoadingVar},`,
      );
      if (tightened !== data) {
        writeFileSync(path, tightened);
        return { path, status: "patched" };
      }
      return { path, status: "already-patched" };
    }

    const pluginLoading = data.match(
      /\{errorMessage:[^,]+,featuredPluginIds:[^,]+,isLoading:([A-Za-z_$][\w$]*),isFetching:[^,]+,marketplaceLoadErrors:[^,]+,marketplaces:[^,]+,availablePlugins:[^,]+,installedPlugins:[^,]+,forceReload:[^,]+,refetch:[^}]+\}=[A-Za-z_$][\w$]*\([^)]*\)/,
    )?.[1];
    if (pluginLoading == null) {
      continue;
    }

    const currentShape = new RegExp(
      `([A-Za-z_$][\\w$]*)=${escapeRegExp(pluginLoading)}\\|\\|[^,]+,([A-Za-z_$][\\w$]*)=`,
    );
    const patched = data.replace(
      currentShape,
      (_match, pageLoadingVar, nextVar) => `${pageLoadingVar}=${PLUGINS_PAGE_LOADING_MARKER}${pluginLoading},${nextVar}=`,
    );

    if (patched !== data) {
      writeFileSync(path, patched);
      return { path, status: "patched" };
    }

    const legacyPatched = data.replace(
      /([A-Za-z_$][\w$]*)=([A-Za-z_$][\w$]*)\|\|([A-Za-z_$][\w$]*)===`loading`\|\|([A-Za-z_$][\w$]*)&&([A-Za-z_$][\w$]*),([A-Za-z_$][\w$]*)=/,
      (_match, loadingVar, queryLoading, _pageLoadingState, _importedLoading, _importedEnabled, nextVar) =>
        `${loadingVar}=${PLUGINS_PAGE_LOADING_MARKER}${queryLoading},${nextVar}=`,
    );

    if (legacyPatched !== data) {
      writeFileSync(path, legacyPatched);
      return { path, status: "patched" };
    }
  }

  return { path: candidates[0] ?? null, status: candidates.length === 0 ? "not-found" : "pattern-not-found" };
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function patchWhamDesktopAuth(root) {
  const buildDir = join(root, ".vite", "build");
  if (!existsSync(buildDir)) {
    return { path: null, status: "not-found" };
  }

  const candidates = readdirSync(buildDir)
    .filter((name) => /^main-.*\.js$/.test(name))
    .map((name) => join(buildDir, name));

  for (const path of candidates) {
    const data = readFileSync(path, "utf8");
    if (data.includes(WHAM_DESKTOP_AUTH_MARKER)) {
      return { path, status: "already-patched" };
    }
    if (!data.includes("function WJ()") || !data.includes("onBeforeSendHeaders")) {
      continue;
    }

    const helperAnchor = "var HJ=!1,UJ=new WeakSet;function WJ(){";
    if (!data.includes(helperAnchor)) {
      continue;
    }

    const helperInserted = data.replace(helperAnchor, `${whamDesktopAuthHelper()}${helperAnchor}`);
    const patched = helperInserted.replace(
      "let i=t.requestHeaders;r({requestHeaders:OJ({frame:t.frame,requestHeaders:i,url:t.url})?BJ(i,",
      "let i=codexPatchWhamDesktopAuthHeaders(t.url,t.requestHeaders);r({requestHeaders:OJ({frame:t.frame,requestHeaders:i,url:t.url})?BJ(i,",
    );

    if (patched !== data) {
      writeFileSync(path, patched);
      return { path, status: "patched" };
    }
  }

  return { path: candidates[0] ?? null, status: candidates.length === 0 ? "not-found" : "pattern-not-found" };
}

function whamDesktopAuthHelper() {
  return [
    `function codexPatchWhamDesktopAuthSetHeader(e,t,n){let r=Object.keys(e).find(e=>e.toLowerCase()===t.toLowerCase());r!=null&&r!==t&&delete e[r],e[t]=n}`,
    `let codexPatchWhamDesktopAuthCache=null,codexPatchWhamDesktopAuthCacheAt=0;function codexPatchWhamDesktopAuthRead(){let e=Date.now();if(e-codexPatchWhamDesktopAuthCacheAt<15e3)return codexPatchWhamDesktopAuthCache;codexPatchWhamDesktopAuthCacheAt=e;try{let e=require("fs"),t=require("path"),n=require("os"),r=process.env.CODEX_HOME||t.join(n.homedir(),".codex"),i=JSON.parse(e.readFileSync(t.join(r,"auth.json"),"utf8"));if(i?.auth_mode!==\`chatgpt\`)return codexPatchWhamDesktopAuthCache=null;let a=i.tokens?.access_token;if(typeof a!==\`string\`||a.length===0)return codexPatchWhamDesktopAuthCache=null;return codexPatchWhamDesktopAuthCache={token:a,accountId:codexPatchWhamDesktopAuthAccountId(a,i)}}catch{return codexPatchWhamDesktopAuthCache=null}}`,
    `function codexPatchWhamDesktopAuthAccountId(e,t){try{let n=JSON.parse(Buffer.from(String(e).split(".")[1]??"","base64url").toString("utf8")),r=n?.["https://api.openai.com/auth"]?.chatgpt_account_id;return typeof r===\`string\`?r:typeof t?.tokens?.account_id===\`string\`?t.tokens.account_id:null}catch{return typeof t?.tokens?.account_id===\`string\`?t.tokens.account_id:null}}`,
    `function codexPatchWhamDesktopAuthHeaders(e,t){try{let n=new URL(e);if(!((n.hostname===\`chatgpt.com\`||n.hostname===\`chat.openai.com\`)&&n.pathname.startsWith(\`/backend-api/wham/\`)))return t;let r=codexPatchWhamDesktopAuthRead();if(r==null)return t;let i={...t};return codexPatchWhamDesktopAuthSetHeader(i,\`Authorization\`,\`Bearer \${r.token}\`),r.accountId&&codexPatchWhamDesktopAuthSetHeader(i,\`ChatGPT-Account-Id\`,r.accountId),codexPatchWhamDesktopAuthSetHeader(i,\`originator\`,\`codex_desktop\`),i}catch{return t}}${WHAM_DESKTOP_AUTH_MARKER}`,
  ].join("");
}

function main() {
  const root = process.argv[2];
  if (!root) {
    throw new Error("Usage: node patch-codex-plugins.mjs <extracted-app-dir>");
  }

  const result = patchExtractedCodexApp(root);
  if (result.pluginAuth === "patched") {
    console.log("[patch] plugin-auth patched: plugin UI no longer follows app-server chat provider auth");
  } else {
    console.log(`[patch] plugin-auth ${result.pluginAuth} - skipping`);
  }
  if (result.accountFallback === "patched") {
    console.log("[patch] account fallback patched: plugin auth can use local ChatGPT login while chat keeps the configured provider");
  } else if (result.accountFallback === "already-patched") {
    console.log("[patch] account fallback already patched - skipping");
  }
  if (result.useAuthAccountFields === "patched") {
    console.log("[patch] use-auth patched: ChatGPT account id fields are preserved for plugin UI");
  } else if (result.useAuthAccountFields === "already-patched") {
    console.log("[patch] use-auth account fields already patched - skipping");
  }
  if (result.pluginsHookLoading === "patched") {
    console.log("[patch] plugins hook patched: availability probes no longer block list loading");
  } else if (result.pluginsHookLoading === "already-patched") {
    console.log("[patch] plugins hook loading gate already patched - skipping");
  }
  if (result.pluginsPageLoading === "patched") {
    console.log("[patch] plugins page patched: only plugin query loading masks plugin list");
  } else if (result.pluginsPageLoading === "already-patched") {
    console.log("[patch] plugins page loading gate already patched - skipping");
  }
  if (result.whamDesktopAuth === "patched") {
    console.log("[patch] WHAM desktop auth patched: ChatGPT mobile/setup requests reuse local login");
  } else if (result.whamDesktopAuth === "already-patched") {
    console.log("[patch] WHAM desktop auth already patched - skipping");
  }
}

if (process.argv[1] != null && fileURLToPath(import.meta.url) === process.argv[1]) {
  main();
}
