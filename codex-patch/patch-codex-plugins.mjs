import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const PLUGIN_AUTH_OPEN_MARKER = "/*codex-patch:plugin-auth-open*/";
const PLUGIN_ACCOUNT_FALLBACK_MARKER = "/*codex-patch:plugin-account-fallback*/";
const AUTH_ACCOUNT_FIELDS_MARKER = "/*codex-patch:auth-account-fields*/";

export function patchExtractedCodexApp(root) {
  const assetsDir = join(root, "webview", "assets");
  if (!existsSync(assetsDir)) {
    throw new Error(`Cannot find webview assets directory: ${assetsDir}`);
  }

  const pluginAuth = patchPluginAuthGate(assetsDir);
  const accountFallback = patchPluginAccountFallback(assetsDir);
  const useAuthAccountFields = patchUseAuthAccountFields(assetsDir);
  return {
    pluginAuth: pluginAuth.status,
    pluginAuthPath: relative(root, pluginAuth.path),
    accountFallback: accountFallback.status,
    accountFallbackPath: accountFallback.path == null ? null : relative(root, accountFallback.path),
    useAuthAccountFields: useAuthAccountFields.status,
    useAuthAccountFieldsPath: useAuthAccountFields.path == null ? null : relative(root, useAuthAccountFields.path),
  };
}

function patchPluginAuthGate(assetsDir) {
  const assetNames = readdirSync(assetsDir);
  const candidates = [
    ...assetNames.filter((name) => /^plugin-auth-.*\.js$/.test(name)),
    ...assetNames.filter((name) => /^gradient-.*\.js$/.test(name)),
  ].map((name) => join(assetsDir, name));

  if (candidates.length === 0) {
    throw new Error("Cannot find plugin-auth JS file");
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

  throw new Error("plugin-auth JS file did not match a known auth gate shape");
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

function main() {
  const root = process.argv[2];
  if (!root) {
    throw new Error("Usage: node patch-codex-plugins.mjs <extracted-app-dir>");
  }

  const result = patchExtractedCodexApp(root);
  if (result.pluginAuth === "patched") {
    console.log("[patch] plugin-auth patched: plugin UI no longer follows app-server chat provider auth");
  } else {
    console.log("[patch] plugin-auth already patched - skipping");
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
}

if (process.argv[1] != null && fileURLToPath(import.meta.url) === process.argv[1]) {
  main();
}
