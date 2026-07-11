import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const PLUGIN_AUTH_OPEN_MARKER = "/*codex-patch:plugin-auth-open*/";
const PLUGIN_ACCOUNT_FALLBACK_MARKER = "/*codex-patch:plugin-account-fallback*/";
const AUTH_ACCOUNT_FIELDS_MARKER = "/*codex-patch:auth-account-fields*/";
const AUTH_ACCOUNT_OUTPUT_MARKER = "/*codex-patch:auth-account-output*/";
const PLUGINS_HOOK_LOADING_MARKER = "/*codex-patch:plugins-loading*/";
const PLUGINS_PAGE_LOADING_MARKER = "/*codex-patch:plugins-page-loading*/";
const PLUGINS_CATALOG_ALL_MARKER = "/*codex-patch:plugins-catalog-all*/";
const WHAM_DESKTOP_AUTH_MARKER = "/*codex-patch:wham-desktop-auth*/";
const DESKTOP_FEATURE_AVAILABILITY_MARKER = "/*codex-patch:desktop-feature-availability*/";
const DESKTOP_AUTH_TOKEN_FALLBACK_MARKER = "/*codex-patch:desktop-auth-token-fallback*/";
const PROFILE_VISIBLE_WITH_CHATGPT_MARKER = "/*codex-patch:profile-visible-with-chatgpt*/";
const PROFILE_DROPDOWN_VISIBLE_MARKER = "/*codex-patch:profile-dropdown-visible*/";
const PREFER_LOCAL_CHATGPT_ACCOUNT_MARKER = "/*codex-patch:prefer-local-chatgpt-account*/";
const ACCOUNT_READ_FILE_METHODS_MARKER = "/*codex-patch:account-read-file-methods*/";
const USAGE_SETTINGS_VISIBLE_MARKER = "/*codex-patch:usage-settings-visible*/";
const LOCAL_DESKTOP_SETTINGS_VISIBLE_MARKER = "/*codex-patch:local-desktop-settings-visible*/";
const LOCAL_USAGE_SETTINGS_VISIBLE_MARKER = "/*codex-patch:local-usage-settings-visible*/";
const LOCKED_USE_SETTINGS_VISIBLE_MARKER = "/*codex-patch:locked-use-settings-visible*/";
const LOCKED_USE_DATA_FALLBACK_MARKER = "/*codex-patch:locked-use-data-fallback*/";
const COMPUTER_USE_MCP_ENABLED_MARKER = "/*codex-patch:computer-use-mcp-enabled*/";
const SPARKLE_UPDATES_DISABLED_MARKER = "/*codex-patch:disable-sparkle-updates*/";
const APPSHOT_AVAILABILITY_MARKER = "/*codex-patch:appshot-availability*/";

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
  const pluginsCatalogAll = patchPluginsCatalogAll(assetsDir);
  const whamDesktopAuth = patchWhamDesktopAuth(root);
  const desktopFeatureAvailability = patchDesktopFeatureAvailability(root);
  const desktopAuthTokenFallback = patchDesktopAuthTokenFallback(root);
  const profileVisibleWithChatgpt = patchProfileVisibleWithChatgpt(assetsDir);
  const usageSettingsVisible = patchUsageSettingsVisible(assetsDir);
  const localDesktopSettingsVisible = patchLocalDesktopSettingsVisible(assetsDir);
  const lockedUseSettingsVisible = patchLockedUseSettingsVisible(assetsDir);
  const appshotAvailability = patchAppshotAvailabilityGate(assetsDir);
  const computerUseMcpEnabled = patchComputerUseMcpEnabled(root);
  const sparkleUpdatesDisabled = patchSparkleUpdatesDisabled(root);
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
    pluginsCatalogAll: pluginsCatalogAll.status,
    pluginsCatalogAllPath: pluginsCatalogAll.path == null ? null : relative(root, pluginsCatalogAll.path),
    whamDesktopAuth: whamDesktopAuth.status,
    whamDesktopAuthPath: whamDesktopAuth.path == null ? null : relative(root, whamDesktopAuth.path),
    desktopFeatureAvailability: desktopFeatureAvailability.status,
    desktopFeatureAvailabilityPath:
      desktopFeatureAvailability.path == null ? null : relative(root, desktopFeatureAvailability.path),
    desktopAuthTokenFallback: desktopAuthTokenFallback.status,
    desktopAuthTokenFallbackPath:
      desktopAuthTokenFallback.path == null ? null : relative(root, desktopAuthTokenFallback.path),
    profileVisibleWithChatgpt: profileVisibleWithChatgpt.status,
    profileVisibleWithChatgptPath:
      profileVisibleWithChatgpt.path == null ? null : relative(root, profileVisibleWithChatgpt.path),
    usageSettingsVisible: usageSettingsVisible.status,
    usageSettingsVisiblePath:
      usageSettingsVisible.path == null ? null : relative(root, usageSettingsVisible.path),
    localDesktopSettingsVisible: localDesktopSettingsVisible.status,
    localDesktopSettingsVisiblePath:
      localDesktopSettingsVisible.path == null ? null : relative(root, localDesktopSettingsVisible.path),
    lockedUseSettingsVisible: lockedUseSettingsVisible.status,
    lockedUseSettingsVisiblePath:
      lockedUseSettingsVisible.path == null ? null : relative(root, lockedUseSettingsVisible.path),
    appshotAvailability: appshotAvailability.status,
    appshotAvailabilityPath: appshotAvailability.path == null ? null : relative(root, appshotAvailability.path),
    computerUseMcpEnabled: computerUseMcpEnabled.status,
    computerUseMcpEnabledPath:
      computerUseMcpEnabled.path == null ? null : relative(root, computerUseMcpEnabled.path),
    sparkleUpdatesDisabled: sparkleUpdatesDisabled.status,
    sparkleUpdatesDisabledPath:
      sparkleUpdatesDisabled.path == null ? null : relative(root, sparkleUpdatesDisabled.path),
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
      `async function codexPatchReadChatGptAuthFile(e,t){let n=\`\${t.replace(/[/]+$/,\`\`)}/auth.json\`;for(let r of[\`read-file\`,\`fs-read-file\`])try{let i=await ${requestBridgeFunction}(r,{hostId:e,path:n}),a=i?.contents??i?.content??i?.data??i?.text;if(typeof a===\`string\`)return a}catch{}return null}${ACCOUNT_READ_FILE_METHODS_MARKER}`,
      `async function codexPatchReadChatGptAccount(e){try{let t=await ${requestBridgeFunction}(\`codex-home\`,{hostId:e}),n=t?.codexHome;if(typeof n!==\`string\`||n.length===0)return null;let r=await codexPatchReadChatGptAuthFile(e,n),i=JSON.parse(r??\`\`);if(i?.auth_mode!==\`chatgpt\`)return null;let a=i.tokens??{},o=codexPatchDecodeJwtPayload(a.id_token??a.access_token),s=o?.[\`https://api.openai.com/auth\`]??{},c=o?.[\`https://api.openai.com/profile\`]??{},l=typeof c.email===\`string\`?c.email:typeof o?.email===\`string\`?o.email:\`\`,u=typeof s.chatgpt_account_id===\`string\`?s.chatgpt_account_id:typeof a.account_id===\`string\`?a.account_id:null,d=typeof s.chatgpt_user_id===\`string\`?s.chatgpt_user_id:null,f=typeof s.chatgpt_plan_type===\`string\`?s.chatgpt_plan_type:\`unknown\`;return l.length===0&&u==null&&d==null?null:{account:{type:\`chatgpt\`,email:l,planType:f,accountId:u,userId:d},requiresOpenaiAuth:!1}}catch{return null}}`,
      `async function codexPatchAccountForPlugins(e,t){let n=await t(),r=await codexPatchReadChatGptAccount(e);return r??n}${PREFER_LOCAL_CHATGPT_ACCOUNT_MARKER}`,
    ].join("") + PLUGIN_ACCOUNT_FALLBACK_MARKER
  );
}

function upgradePluginAccountFallbackHelper(data) {
  let patched = data.replace(
    "l=typeof c.email===`string`?c.email:null,u=",
    "l=typeof c.email===`string`?c.email:typeof o?.email===`string`?o.email:``,u=",
  );
  patched = patched.replace("return l==null?null:{account:", "return l.length===0&&u==null&&d==null?null:{account:");
  if (!patched.includes(PREFER_LOCAL_CHATGPT_ACCOUNT_MARKER)) {
    const preferLocalAccountHelper =
      `async function codexPatchAccountForPlugins(e,t){let n=await t(),r=await codexPatchReadChatGptAccount(e);return r??n}${PREFER_LOCAL_CHATGPT_ACCOUNT_MARKER}`;
    const upgraded = patched.replace(
      "async function codexPatchAccountForPlugins(e,t){let n=await t();if(n?.account!=null||n?.requiresOpenaiAuth!==!1)return n;return(await codexPatchReadChatGptAccount(e))??n}",
      preferLocalAccountHelper,
    );
    patched =
      upgraded !== patched
        ? upgraded
        : patched.replace(
            "async function codexPatchAccountForPlugins(e,t){let n=await t(),r=await codexPatchReadChatGptAccount(e);return r??n}",
            preferLocalAccountHelper,
          );
  }
  if (!patched.includes(ACCOUNT_READ_FILE_METHODS_MARKER)) {
    const requestBridge = patched.match(
      /function\s+([A-Za-z_$][\w$]*)\(e,t\)\{return [A-Za-z_$][\w$]*\.sendRequest\(e,t\)\}/,
    );
    if (requestBridge != null) {
      const [, requestBridgeFunction] = requestBridge;
      const readAuthFileHelper =
        `async function codexPatchReadChatGptAuthFile(e,t){let n=\`\${t.replace(/[/]+$/,\`\`)}/auth.json\`;for(let r of[\`read-file\`,\`fs-read-file\`])try{let i=await ${requestBridgeFunction}(r,{hostId:e,path:n}),a=i?.contents??i?.content??i?.data??i?.text;if(typeof a===\`string\`)return a}catch{}return null}${ACCOUNT_READ_FILE_METHODS_MARKER}`;
      patched = patched.replace(
        "async function codexPatchReadChatGptAccount",
        `${readAuthFileHelper}async function codexPatchReadChatGptAccount`,
      );
      const oldReadFileCall =
        `let r=await ${requestBridgeFunction}(\`read-file\`,{hostId:e,path:\`\${n.replace(/[/]+$/,\`\`)}/auth.json\`}),i=JSON.parse(r?.contents??\`\`);`;
      patched = patched.replace(oldReadFileCall, "let r=await codexPatchReadChatGptAuthFile(e,n),i=JSON.parse(r??``);");
    }
  }
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
    if (data.includes(AUTH_ACCOUNT_FIELDS_MARKER) && data.includes(AUTH_ACCOUNT_OUTPUT_MARKER)) {
      return { path, status: "already-patched" };
    }

    let patched = data;
    if (!patched.includes(AUTH_ACCOUNT_FIELDS_MARKER)) {
      patched = patched.replace(
        "planAtLogin:e.account?.type===`chatgpt`?e.account.planType:null}}",
        `planAtLogin:e.account?.type===\`chatgpt\`?e.account.planType:null,accountId:e.account?.type===\`chatgpt\`?e.account.accountId??null:null,userId:e.account?.type===\`chatgpt\`?e.account.userId??null:null${AUTH_ACCOUNT_FIELDS_MARKER}}}`,
      );
    }
    patched = patched.replace(
      /\{\.\.\.([A-Za-z_$][\w$]*),isLoading:([A-Za-z_$][\w$]*),isCopilotApiAvailable:([A-Za-z_$][\w$]*),accountId:null,userId:null(,computeResidency:[^,}]+)?,setAuthMethod:([A-Za-z_$][\w$]*)\}/,
      (_match, authStateVar, loadingVar, copilotVar, computeResidency, setAuthMethodVar) =>
        `{...${authStateVar},isLoading:${loadingVar},isCopilotApiAvailable:${copilotVar},accountId:${authStateVar}.accountId??null,userId:${authStateVar}.userId??null${AUTH_ACCOUNT_OUTPUT_MARKER}${computeResidency ?? ""},setAuthMethod:${setAuthMethodVar}}`,
    );
    if (!patched.includes(AUTH_ACCOUNT_OUTPUT_MARKER)) {
      patched = patched.replace(
        /accountId:([A-Za-z_$][\w$]*)\.accountId\?\?null,userId:\1\.userId\?\?null(,computeResidency:[^,}]+)?,setAuthMethod:([A-Za-z_$][\w$]*)/,
        (_match, authStateVar, computeResidency, setAuthMethodVar) =>
          `accountId:${authStateVar}.accountId??null,userId:${authStateVar}.userId??null${AUTH_ACCOUNT_OUTPUT_MARKER}${computeResidency ?? ""},setAuthMethod:${setAuthMethodVar}`,
      );
    }

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

function patchPluginsCatalogAll(assetsDir) {
  const candidates = [
    ...readdirSync(assetsDir).filter((name) => /^plugins-page-.*\.js$/.test(name)),
    ...readdirSync(assetsDir).filter((name) => /\.js$/.test(name) && !/^plugins-page-.*\.js$/.test(name)),
  ]
    .map((name) => join(assetsDir, name))
    .filter((path) => {
      const data = readFileSync(path, "utf8");
      return data.includes(PLUGINS_CATALOG_ALL_MARKER) || (data.includes("case`openai`") && data.includes("directoryTabs.openai"));
    });

  for (const path of candidates) {
    const data = readFileSync(path, "utf8");
    let patched = patchPluginsCatalogAllLabel(data);
    if (patched.includes(PLUGINS_CATALOG_ALL_MARKER)) {
      if (patched !== data) {
        writeFileSync(path, patched);
        return { path, status: "patched" };
      }
      return { path, status: "already-patched" };
    }

    const openaiCaseStart = patched.indexOf("case`openai`");
    const workspaceCaseStart = patched.indexOf("case`workspace`", openaiCaseStart);
    if (openaiCaseStart === -1 || workspaceCaseStart === -1) {
      continue;
    }

    const openaiCase = patched.slice(openaiCaseStart, workspaceCaseStart);
    const filterWindow = patched.slice(Math.max(0, openaiCaseStart - 1200), openaiCaseStart);
    const filterMatches = Array.from(
      filterWindow.matchAll(/([A-Za-z_$][\w$]*)=([A-Za-z_$][\w$]*)\.filter\(([A-Za-z_$][\w$]*)\)/g),
    );
    const filterMatch = filterMatches.at(-1);
    if (filterMatch == null) {
      continue;
    }

    const [, curatedVar, allPluginsVar] = filterMatch;
    const curatedPluginsPattern = new RegExp(`plugins:${escapeRegExp(curatedVar)},query:`);
    const patchedOpenaiCase = openaiCase.replace(
      curatedPluginsPattern,
      `plugins:${allPluginsVar}${PLUGINS_CATALOG_ALL_MARKER},query:`,
    );
    if (patchedOpenaiCase === openaiCase) {
      continue;
    }

    patched = patched.slice(0, openaiCaseStart) + patchedOpenaiCase + patched.slice(workspaceCaseStart);
    writeFileSync(path, patched);
    return { path, status: "patched" };
  }

  return { path: candidates[0] ?? null, status: candidates.length === 0 ? "not-found" : "pattern-not-found" };
}

function patchPluginsCatalogAllLabel(data) {
  return data.replace(
    "id:`skills.appsPage.directoryTabs.openai`,defaultMessage:`By OpenAI`,description:`Label for plugins built by OpenAI in the plugin directory`",
    "id:`skills.appsPage.directoryTabs.openai`,defaultMessage:`All`,description:`Label for all installable plugins in the plugin directory`",
  );
}

function patchProfileVisibleWithChatgpt(assetsDir) {
  const candidates = readdirSync(assetsDir)
    .filter((name) => /^profile-visibility-.*\.js$/.test(name))
    .map((name) => join(assetsDir, name));

  if (candidates.length === 0) {
    return { path: null, status: "not-found" };
  }

  for (const path of candidates) {
    const data = readFileSync(path, "utf8");
    if (data.includes(PROFILE_VISIBLE_WITH_CHATGPT_MARKER) && data.includes(PROFILE_DROPDOWN_VISIBLE_MARKER)) {
      const upgraded = upgradeProfileVisibilityPatch(data);
      if (upgraded !== data) {
        writeFileSync(path, upgraded);
        return { path, status: "patched" };
      }
      return { path, status: "already-patched" };
    }

    if (!data.includes("isProfileVisible") || !data.includes("show_dropdown_entry_point")) {
      continue;
    }

    let patched = data.replace(
      /,([A-Za-z_$][\w$]*)=([A-Za-z_$][\w$]*)===`chatgpt`&&([A-Za-z_$][\w$]*),([A-Za-z_$][\w$]*);return ([A-Za-z_$][\w$]*)\[0\]!==([A-Za-z_$][\w$]*)\|\|\5\[1\]!==\1\?\(/,
      (_match, visibleVar, authMethodVar, _gateVar, nextVar, cacheVar, loadingVar) =>
        `,${visibleVar}=!0${PROFILE_VISIBLE_WITH_CHATGPT_MARKER},${nextVar};return ${cacheVar}[0]!==${loadingVar}||${cacheVar}[1]!==${visibleVar}?(`,
    );

    patched = patched.replace(
      /if\(([A-Za-z_$][\w$]*)!==`chatgpt`\)return!1;let ([A-Za-z_$][\w$]*);return ([A-Za-z_$][\w$]*)\[0\]!==([A-Za-z_$][\w$]*)\|\|\3\[1\]!==([A-Za-z_$][\w$]*)\?\(\2=(([A-Za-z_$][\w$]*)&&\5\.get\(([A-Za-z_$][\w$]*),!1\)|!0(?:\/\*codex-patch:profile-dropdown-visible\*\/)?),/,
      (_match, _authMethodVar, entryVisibleVar, cacheVar, gateVar, configVar) =>
        `let ${entryVisibleVar};return ${cacheVar}[0]!==${gateVar}||${cacheVar}[1]!==${configVar}?(${entryVisibleVar}=!0${PROFILE_DROPDOWN_VISIBLE_MARKER},`,
    );
    patched = upgradeProfileVisibilityPatch(patched);

    if (
      patched !== data &&
      patched.includes(PROFILE_VISIBLE_WITH_CHATGPT_MARKER) &&
      patched.includes(PROFILE_DROPDOWN_VISIBLE_MARKER)
    ) {
      writeFileSync(path, patched);
      return { path, status: "patched" };
    }
  }

  return { path: candidates[0], status: "pattern-not-found" };
}

function upgradeProfileVisibilityPatch(data) {
  return data.replace(
    /=([A-Za-z_$][\w$]*)===`chatgpt`\/\*codex-patch:profile-visible-with-chatgpt\*\//g,
    `=!0${PROFILE_VISIBLE_WITH_CHATGPT_MARKER}`,
  );
}

function patchUsageSettingsVisible(assetsDir) {
  const candidates = readdirSync(assetsDir)
    .filter((name) => /^use-usage-settings-access-.*\.js$/.test(name))
    .map((name) => join(assetsDir, name));

  if (candidates.length === 0) {
    return { path: null, status: "not-found" };
  }

  for (const path of candidates) {
    const data = readFileSync(path, "utf8");
    if (data.includes(USAGE_SETTINGS_VISIBLE_MARKER)) {
      return { path, status: "already-patched" };
    }
    if (!data.includes("isUsageSettingsVisible") || !data.includes("canManageCreditSettings")) {
      continue;
    }

    const patched = data.replace(
      /return\{canManageCreditSettings:([A-Za-z_$][\w$]*),isUsageSettingsVisible:\1\|\|([A-Za-z_$][\w$]*)&&([A-Za-z_$][\w$]*)&&([A-Za-z_$][\w$]*)\|\|\2&&([A-Za-z_$][\w$]*)&&([A-Za-z_$][\w$]*)\}/,
      (_match, creditVisibleVar, isChatgptVar, freeGoPlanVar, freeGoGateVar, enterprisePlanVar, enterpriseGateVar) =>
        `return{canManageCreditSettings:${creditVisibleVar},isUsageSettingsVisible:${isChatgptVar}||${creditVisibleVar}||${isChatgptVar}&&${freeGoPlanVar}&&${freeGoGateVar}||${isChatgptVar}&&${enterprisePlanVar}&&${enterpriseGateVar}${USAGE_SETTINGS_VISIBLE_MARKER}}`,
    );

    if (patched !== data) {
      writeFileSync(path, patched);
      return { path, status: "patched" };
    }
  }

  return { path: candidates[0], status: "pattern-not-found" };
}

function patchLocalDesktopSettingsVisible(assetsDir) {
  const candidates = readdirSync(assetsDir)
    .filter((name) => /^settings-page-.*\.js$/.test(name))
    .map((name) => join(assetsDir, name));

  if (candidates.length === 0) {
    return { path: null, status: "not-found" };
  }

  for (const path of candidates) {
    const data = readFileSync(path, "utf8");
    if (data.includes(LOCAL_DESKTOP_SETTINGS_VISIBLE_MARKER)) {
      if (data.includes(LOCAL_USAGE_SETTINGS_VISIBLE_MARKER)) {
        return { path, status: "already-patched" };
      }
    }
    if (!data.includes("case`computer-use`") || !data.includes("case`browser-use`")) {
      continue;
    }

    const localHostVar = data.match(
      /function\s+[A-Za-z_$][\w$]*\(e,t,r\)\{let\b[\s\S]*?,[A-Za-z_$][\w$]*=e===void 0\?null:e,([A-Za-z_$][\w$]*)=t===void 0\?!0:t,/,
    )?.[1];
    if (localHostVar == null) {
      continue;
    }

    let patched = data.replace(
      /case`usage`:return [A-Za-z_$][\w$]*;/,
      `case\`usage\`:return ${localHostVar}${LOCAL_USAGE_SETTINGS_VISIBLE_MARKER};`,
    );

    patched = patched.replace(
      /case`computer-use`:return [A-Za-z_$][\w$]*;case`browser-use`:return [A-Za-z_$][\w$]*;/,
      `case\`computer-use\`:return ${localHostVar}${LOCAL_DESKTOP_SETTINGS_VISIBLE_MARKER};case\`browser-use\`:return ${localHostVar}${LOCAL_DESKTOP_SETTINGS_VISIBLE_MARKER};`,
    );

    if (
      patched !== data &&
      patched.includes(LOCAL_USAGE_SETTINGS_VISIBLE_MARKER) &&
      patched.includes(LOCAL_DESKTOP_SETTINGS_VISIBLE_MARKER)
    ) {
      writeFileSync(path, patched);
      return { path, status: "patched" };
    }
  }

  return { path: candidates[0], status: "pattern-not-found" };
}

function patchLockedUseSettingsVisible(assetsDir) {
  const candidates = readdirSync(assetsDir)
    .filter((name) => /^computer-use-settings-.*\.js$/.test(name))
    .map((name) => join(assetsDir, name));

  if (candidates.length === 0) {
    return { path: null, status: "not-found" };
  }

  for (const path of candidates) {
    const data = readFileSync(path, "utf8");
    if (data.includes(LOCKED_USE_SETTINGS_VISIBLE_MARKER) && data.includes(LOCKED_USE_DATA_FALLBACK_MARKER)) {
      return { path, status: "already-patched" };
    }
    if (!data.includes("settings.computerUse.backgroundAuth.label")) {
      continue;
    }

    const hostMatch = data.match(
      /\{selectedHostId:([A-Za-z_$][\w$]*)\}=[A-Za-z_$][\w$]*\(\),([A-Za-z_$][\w$]*)=[A-Za-z_$][\w$]*\([A-Za-z_$][\w$]*,\1\)/,
    );
    if (hostMatch == null) {
      continue;
    }
    const [, selectedHostVar, installGateVar] = hostMatch;

    let patched = data;
    if (!patched.includes(LOCKED_USE_SETTINGS_VISIBLE_MARKER)) {
      const parentGatePattern = new RegExp(
        `([A-Za-z_$][\\w$]*\\[\\d+\\])!==${escapeRegExp(installGateVar)}\\|\\|` +
          `([A-Za-z_$][\\w$]*\\[\\d+\\])!==([A-Za-z_$][\\w$]*)\\.available\\|\\|` +
          `([A-Za-z_$][\\w$]*\\[\\d+\\])!==([A-Za-z_$][\\w$]*)\\?\\(` +
          `([A-Za-z_$][\\w$]*)=\\5===\`macOS\`&&\\3\\.available&&${escapeRegExp(installGateVar)}\\?` +
          `\\(0,([A-Za-z_$][\\w$]*)\\.jsx\\)\\(([A-Za-z_$][\\w$]*),\\{\\}\\):null,` +
          `\\1=${escapeRegExp(installGateVar)},\\2=\\3\\.available,\\4=\\5,` +
          `([A-Za-z_$][\\w$]*\\[\\d+\\])=\\6\\):\\6=\\9`,
      );
      patched = patched.replace(
        parentGatePattern,
        (
          _match,
          installGateCache,
          availabilityCache,
          _availabilityVar,
          _platformCache,
          platformVar,
          rowVar,
          jsxNamespace,
          lockedUseComponent,
          rowCache,
        ) =>
          `${installGateCache}!==${selectedHostVar}||${availabilityCache}!==${platformVar}?(` +
          `${rowVar}=${platformVar}===\`macOS\`&&${selectedHostVar}===\`local\`?` +
          `(0,${jsxNamespace}.jsx)(${lockedUseComponent},{}):null${LOCKED_USE_SETTINGS_VISIBLE_MARKER},` +
          `${installGateCache}=${selectedHostVar},${availabilityCache}=${platformVar},${rowCache}=${rowVar}):${rowVar}=${rowCache}`,
      );
    }

    if (!patched.includes(LOCKED_USE_DATA_FALLBACK_MARKER)) {
      const dataFallbackPattern =
        /let ([A-Za-z_$][\w$]*)=([A-Za-z_$][\w$]*)\(([A-Za-z_$][\w$]*)\);if\(([A-Za-z_$][\w$]*)\.data\?\.enabled==null\)return null;let ([A-Za-z_$][\w$]*);/;
      let queryVar = null;
      patched = patched.replace(
        dataFallbackPattern,
        (_match, mutationVar, mutationHookVar, mutationOptionsVar, backgroundAuthQueryVar, nextVar) => {
          queryVar = backgroundAuthQueryVar;
          return (
            `let ${mutationVar}=${mutationHookVar}(${mutationOptionsVar}),` +
            `codexPatchLockedUseData=${backgroundAuthQueryVar}.data??` +
            `{enabled:!1,computerIconDataURL:null,lockIconDataURL:null}${LOCKED_USE_DATA_FALLBACK_MARKER};let ${nextVar};`
          );
        },
      );
      if (queryVar != null) {
        patched = patched.replaceAll(`${queryVar}.data.`, "codexPatchLockedUseData.");
      }
    }

    if (
      patched !== data &&
      patched.includes(LOCKED_USE_SETTINGS_VISIBLE_MARKER) &&
      patched.includes(LOCKED_USE_DATA_FALLBACK_MARKER)
    ) {
      writeFileSync(path, patched);
      return { path, status: "patched" };
    }
  }

  return { path: candidates[0], status: "pattern-not-found" };
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function patchAppshotAvailabilityGate(assetsDir) {
  const candidates = readdirSync(assetsDir)
    .filter((name) => /^appshot-availability-.*\.js$/.test(name))
    .map((name) => join(assetsDir, name));

  if (candidates.length === 0) {
    return { path: null, status: "not-found" };
  }

  for (const path of candidates) {
    const data = readFileSync(path, "utf8");
    if (data.includes(APPSHOT_AVAILABILITY_MARKER)) {
      return { path, status: "already-patched" };
    }
    if (!data.includes("allowAppshots") || !data.includes("1304276663")) {
      continue;
    }

    const patched = data.replace(
      /if\(([A-Za-z_$][\w$]*\([A-Za-z_$][\w$]*\))!==`macOS`\|\|![A-Za-z_$][\w$]*\([A-Za-z_$][\w$]*,`1304276663`\)\)return!1;/,
      (_match, platformCheck) => `if(${platformCheck}!==\`macOS\`)return!1${APPSHOT_AVAILABILITY_MARKER};`,
    );

    if (patched !== data) {
      writeFileSync(path, patched);
      return { path, status: "patched" };
    }
  }

  return { path: candidates[0], status: "pattern-not-found" };
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
    if (!data.includes("onBeforeSendHeaders")) {
      continue;
    }

    const helperAnchor = data.match(
      /var\s+[A-Za-z_$][\w$]*=!1,[A-Za-z_$][\w$]*=new WeakSet;function\s+[A-Za-z_$][\w$]*\(\)\{if\([A-Za-z_$][\w$]*\)return;let\s+[A-Za-z_$][\w$]*=`session`in[^;]+?defaultSession[^;]*;/,
    );
    if (helperAnchor == null) {
      continue;
    }

    const helperInserted = data.replace(helperAnchor[0], `${whamDesktopAuthHelper()}${helperAnchor[0]}`);
    const patched = helperInserted.replace(
      /let\s+([A-Za-z_$][\w$]*)=([A-Za-z_$][\w$]*)\.requestHeaders;([A-Za-z_$][\w$]*)\(\{requestHeaders:([A-Za-z_$][\w$]*)\(\{frame:\2\.frame,requestHeaders:\1,url:\2\.url\}\)\?([A-Za-z_$][\w$]*)\(\1,/,
      (_match, headersVar, detailsVar, callbackVar, shouldRewriteFn, rewriteHeadersFn) =>
        `let ${headersVar}=codexPatchWhamDesktopAuthHeaders(${detailsVar}.url,${detailsVar}.requestHeaders);${callbackVar}({requestHeaders:${shouldRewriteFn}({frame:${detailsVar}.frame,requestHeaders:${headersVar},url:${detailsVar}.url})?${rewriteHeadersFn}(${headersVar},`,
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

function patchDesktopFeatureAvailability(root) {
  const buildDir = join(root, ".vite", "build");
  if (!existsSync(buildDir)) {
    return { path: null, status: "not-found" };
  }

  const candidates = readdirSync(buildDir)
    .filter((name) => /^main-.*\.js$/.test(name))
    .map((name) => join(buildDir, name));

  for (const path of candidates) {
    const data = readFileSync(path, "utf8");
    if (data.includes(DESKTOP_FEATURE_AVAILABILITY_MARKER)) {
      const upgraded = upgradeDesktopFeatureAvailabilityPatch(data);
      if (upgraded !== data) {
        writeFileSync(path, upgraded);
        return { path, status: "patched" };
      }
      return { path, status: "already-patched" };
    }
    if (!data.includes("CODEX_ELECTRON_DESKTOP_FEATURE_OVERRIDES") || !data.includes("computerUseNodeRepl")) {
      continue;
    }

    const helperAnchor = data.match(/(var\s+[A-Za-z_$][\w$]*=\{[^}]*computerUseNodeRepl:[^}]+?\},[A-Za-z_$][\w$]*=Object\.keys\([^)]+\),[A-Za-z_$][\w$]*=\{[^}]+\},[A-Za-z_$][\w$]*=`CODEX_ELECTRON_DESKTOP_FEATURE_OVERRIDES`;)/);
    if (helperAnchor == null) {
      continue;
    }

    const returnPattern =
      /return ([A-Za-z_$][\w$]*)==null\?\{\.\.\.([A-Za-z_$][\w$]*),deviceAttestation:([A-Za-z_$][\w$]*)\(\{platform:([A-Za-z_$][\w$]*)\}\)\}:\{\.\.\.\2,\.\.\.\1,deviceAttestation:\3\(\{platform:\4\}\)\}/;
    if (!returnPattern.test(data)) {
      continue;
    }

    const withHelper = data.replace(helperAnchor[0], `${helperAnchor[0]}${desktopFeatureAvailabilityHelper()}`);
    const patched = withHelper.replace(
      returnPattern,
      (_match, overrideVar, baseVar, deviceAttestationFn, platformVar) =>
        `return codexPatchDesktopFeatureAvailability(${overrideVar}==null?{...${baseVar},deviceAttestation:${deviceAttestationFn}({platform:${platformVar}})}:{...${baseVar},...${overrideVar},deviceAttestation:${deviceAttestationFn}({platform:${platformVar}})})`,
    );

    if (patched !== data) {
      writeFileSync(path, patched);
      return { path, status: "patched" };
    }
  }

  return { path: candidates[0] ?? null, status: candidates.length === 0 ? "not-found" : "pattern-not-found" };
}

function desktopFeatureAvailabilityHelper() {
  return `function codexPatchDesktopFeatureAvailability(e){return{...e,appshotsEnabled:!0,browserPane:!0,inAppBrowserUse:!0,inAppBrowserUseAllowed:!0,externalBrowserUse:!0,externalBrowserUseAllowed:!0,computerUse:!0,computerUseNodeRepl:!0,sites:!0,control:!0,multiBrowserTabs:!0,recordAndReplay:!0${DESKTOP_FEATURE_AVAILABILITY_MARKER}}}`;
}

function upgradeDesktopFeatureAvailabilityPatch(data) {
  if (!data.includes(DESKTOP_FEATURE_AVAILABILITY_MARKER) || data.includes("recordAndReplay:!0")) {
    return data;
  }
  return data.replace(
    DESKTOP_FEATURE_AVAILABILITY_MARKER,
    `,recordAndReplay:!0${DESKTOP_FEATURE_AVAILABILITY_MARKER}`,
  );
}

function patchSparkleUpdatesDisabled(root) {
  const buildDir = join(root, ".vite", "build");
  if (!existsSync(buildDir)) {
    return { path: null, status: "not-found" };
  }

  const candidates = readdirSync(buildDir)
    .filter((name) => /\.js$/.test(name))
    .map((name) => join(buildDir, name));

  for (const path of candidates) {
    const data = readFileSync(path, "utf8");
    if (data.includes(SPARKLE_UPDATES_DISABLED_MARKER)) {
      return { path, status: "already-patched" };
    }
    if (!data.includes("async initializeMacSparkle()") || !data.includes("checkForUpdatesInBackground")) {
      continue;
    }

    const patched = data.replace(
      /async initializeMacSparkle\(\)\{if\(process\.platform!==`darwin`\)\{this\.lastUnavailableReason=`unsupported platform`;return\}/,
      `async initializeMacSparkle(){this.lastUnavailableReason=\`disabled by local patch\`;return${SPARKLE_UPDATES_DISABLED_MARKER};if(process.platform!==\`darwin\`){this.lastUnavailableReason=\`unsupported platform\`;return}`,
    );

    if (patched !== data) {
      writeFileSync(path, patched);
      return { path, status: "patched" };
    }
  }

  return { path: candidates[0] ?? null, status: candidates.length === 0 ? "not-found" : "pattern-not-found" };
}

function patchDesktopAuthTokenFallback(root) {
  const buildDir = join(root, ".vite", "build");
  if (!existsSync(buildDir)) {
    return { path: null, status: "not-found" };
  }

  const candidates = readdirSync(buildDir)
    .filter((name) => /^main-.*\.js$/.test(name))
    .map((name) => join(buildDir, name));

  for (const path of candidates) {
    const data = readFileSync(path, "utf8");
    if (data.includes(DESKTOP_AUTH_TOKEN_FALLBACK_MARKER)) {
      return { path, status: "already-patched" };
    }
    if (!data.includes("Sign in to ChatGPT in Codex Desktop") || !data.includes('"account-info"')) {
      continue;
    }

    const authHeadersPattern =
      /async function ([A-Za-z_$][\w$]*)\(\{action:([A-Za-z_$][\w$]*),appServerClient:([A-Za-z_$][\w$]*),desktopOriginator:([A-Za-z_$][\w$]*),headers:([A-Za-z_$][\w$]*)=\{\},refreshToken:([A-Za-z_$][\w$]*)=!1\}\)\{let ([A-Za-z_$][\w$]*)=await \3\.getAuthToken\(\{refreshToken:\6\}\);if\(!\7\)throw Error\(`Sign in to ChatGPT in Codex Desktop to \$\{\2\}\.`\);let ([A-Za-z_$][\w$]*)=\{\.\.\.\5\};return ([A-Za-z_$][\w$]*)\(\8,\7,\{desktopOriginator:\4\}\),\8\}/;
    if (!authHeadersPattern.test(data)) {
      continue;
    }

    let patched = data.replace(
      authHeadersPattern,
      (match, _functionName, _actionVar, clientVar, _desktopOriginatorVar, _headersVar, refreshTokenVar, tokenVar) => {
      return (
        desktopAuthTokenFallbackHelper() +
        match.replace(
          `let ${tokenVar}=await ${clientVar}.getAuthToken({refreshToken:${refreshTokenVar}});if(!${tokenVar})`,
          `let ${tokenVar}=await ${clientVar}.getAuthToken({refreshToken:${refreshTokenVar}});${tokenVar}||=codexPatchDesktopAuthTokenRead();if(!${tokenVar})`,
        )
      );
      },
    );

    const accountInfoPattern =
      /let ([A-Za-z_$][\w$]*)=await this\.appServerConnectionRegistry\.getConnection\(([A-Za-z_$][\w$]*)\)\.getAuthToken\(\{refreshToken:!1\}\);if\(!\1\)return\{accountId:null,userId:null,plan:null,email:null,computeResidency:null\};/;
    patched = patched.replace(
      accountInfoPattern,
      (_match, tokenVar, hostVar) =>
        `let ${tokenVar}=await this.appServerConnectionRegistry.getConnection(${hostVar}).getAuthToken({refreshToken:!1});${tokenVar}||=codexPatchDesktopAuthTokenRead();if(!${tokenVar})return{accountId:null,userId:null,plan:null,email:null,computeResidency:null};`,
    );

    if (patched !== data && patched.includes(DESKTOP_AUTH_TOKEN_FALLBACK_MARKER)) {
      writeFileSync(path, patched);
      return { path, status: "patched" };
    }
  }

  return { path: candidates[0] ?? null, status: candidates.length === 0 ? "not-found" : "pattern-not-found" };
}

function desktopAuthTokenFallbackHelper() {
  return `let codexPatchDesktopAuthTokenCache=null,codexPatchDesktopAuthTokenCacheAt=0;function codexPatchDesktopAuthTokenRead(){let e=Date.now();if(e-codexPatchDesktopAuthTokenCacheAt<15e3)return codexPatchDesktopAuthTokenCache;codexPatchDesktopAuthTokenCacheAt=e;try{let e=require("fs"),t=require("path"),n=require("os"),r=process.env.CODEX_HOME||t.join(n.homedir(),".codex"),i=JSON.parse(e.readFileSync(t.join(r,"auth.json"),"utf8"));if(i?.auth_mode!==\`chatgpt\`)return codexPatchDesktopAuthTokenCache=null;let a=i.tokens?.access_token;return typeof a===\`string\`&&a.length>0?codexPatchDesktopAuthTokenCache=a:codexPatchDesktopAuthTokenCache=null}catch{return codexPatchDesktopAuthTokenCache=null}}${DESKTOP_AUTH_TOKEN_FALLBACK_MARKER}`;
}

function patchComputerUseMcpEnabled(root) {
  const buildDir = join(root, ".vite", "build");
  if (!existsSync(buildDir)) {
    return { path: null, status: "not-found" };
  }

  const candidates = readdirSync(buildDir)
    .filter((name) => /^main-.*\.js$/.test(name))
    .map((name) => join(buildDir, name));

  for (const path of candidates) {
    const data = readFileSync(path, "utf8");
    if (data.includes(COMPUTER_USE_MCP_ENABLED_MARKER)) {
      return { path, status: "already-patched" };
    }
    if (!data.includes("Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient")) {
      continue;
    }

    const oldShape =
      /\{command:`\.\/Codex Computer Use\.app\/Contents\/SharedSupport\/SkyComputerUseClient\.app\/Contents\/MacOS\/SkyComputerUseClient`,args:\[`mcp`\],cwd:`\.`,enabled:!1\}/;
    const patched = data.replace(
      oldShape,
      `{command:(process.env.HOME??require(\`os\`).homedir())+\`/.codex/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient\`,args:[\`mcp\`],cwd:(process.env.HOME??require(\`os\`).homedir())+\`/.codex/computer-use\`,enabled:!0${COMPUTER_USE_MCP_ENABLED_MARKER}}`,
    );

    if (patched !== data) {
      writeFileSync(path, patched);
      return { path, status: "patched" };
    }
  }

  return { path: candidates[0] ?? null, status: candidates.length === 0 ? "not-found" : "pattern-not-found" };
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
  if (result.pluginsCatalogAll === "patched") {
    console.log("[patch] plugins catalog patched: default directory tab shows all installable marketplace plugins");
  } else if (result.pluginsCatalogAll === "already-patched") {
    console.log("[patch] plugins catalog already patched - skipping");
  }
  if (result.whamDesktopAuth === "patched") {
    console.log("[patch] WHAM desktop auth patched: ChatGPT mobile/setup requests reuse local login");
  } else if (result.whamDesktopAuth === "already-patched") {
    console.log("[patch] WHAM desktop auth already patched - skipping");
  }
  if (result.desktopFeatureAvailability === "patched") {
    console.log("[patch] desktop feature availability patched: Computer Use and browser capabilities stay enabled in packaged app");
  } else if (result.desktopFeatureAvailability === "already-patched") {
    console.log("[patch] desktop feature availability already patched - skipping");
  }
  if (result.desktopAuthTokenFallback === "patched") {
    console.log("[patch] desktop auth token fallback patched: remote control and account UI reuse local ChatGPT login");
  } else if (result.desktopAuthTokenFallback === "already-patched") {
    console.log("[patch] desktop auth token fallback already patched - skipping");
  }
  if (result.profileVisibleWithChatgpt === "patched") {
    console.log("[patch] profile visibility patched: ChatGPT account settings stay visible");
  } else if (result.profileVisibleWithChatgpt === "already-patched") {
    console.log("[patch] profile visibility already patched - skipping");
  }
  if (result.usageSettingsVisible === "patched") {
    console.log("[patch] usage settings patched: Usage stays visible for local ChatGPT login");
  } else if (result.usageSettingsVisible === "already-patched") {
    console.log("[patch] usage settings already patched - skipping");
  }
  if (result.localDesktopSettingsVisible === "patched") {
    console.log("[patch] local desktop settings patched: Computer Use and Browser Use stay visible locally");
  } else if (result.localDesktopSettingsVisible === "already-patched") {
    console.log("[patch] local desktop settings already patched - skipping");
  }
  if (result.lockedUseSettingsVisible === "patched") {
    console.log("[patch] Locked use settings patched: local macOS Locked use row stays visible");
  } else if (result.lockedUseSettingsVisible === "already-patched") {
    console.log("[patch] Locked use settings already patched - skipping");
  }
  if (result.computerUseMcpEnabled === "patched") {
    console.log("[patch] Computer Use MCP patched: desktop app keeps computer-use MCP enabled");
  } else if (result.computerUseMcpEnabled === "already-patched") {
    console.log("[patch] Computer Use MCP already patched - skipping");
  }
  if (result.sparkleUpdatesDisabled === "patched") {
    console.log("[patch] Sparkle updates disabled: desktop app will not start background update checks");
  } else if (result.sparkleUpdatesDisabled === "already-patched") {
    console.log("[patch] Sparkle updates already disabled - skipping");
  }
}

if (process.argv[1] != null && fileURLToPath(import.meta.url) === process.argv[1]) {
  main();
}
