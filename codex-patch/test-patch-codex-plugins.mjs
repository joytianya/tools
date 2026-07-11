import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { patchExtractedCodexApp } from "./patch-codex-plugins.mjs";

test("patchExtractedCodexApp opens plugin UI without changing app-server provider flow", () => {
  withFixture((root) => {
    const assets = join(root, "webview", "assets");
    mkdirSync(assets, { recursive: true });

    const pluginAuth = join(assets, "plugin-auth-Drbk5jr_.js");
    writeFileSync(pluginAuth, "function e(e){return e!==`chatgpt`}export{e as t};\n");

    const appServerBridge = join(assets, "workspace-root-drop-handler-Bom6Z7sW.js");
    const originalBridge =
      "function Yd(){return[`app-server`,`--analytics-default-enabled`]}\n" +
      "const env={...process.env,LOG_FORMAT:`json`,RUST_LOG:`warn`};\n";
    writeFileSync(appServerBridge, originalBridge);

    const result = patchExtractedCodexApp(root);

    assert.equal(result.pluginAuth, "patched");
    assert.match(readFileSync(pluginAuth, "utf8"), /return !1/);
    assert.equal(readFileSync(appServerBridge, "utf8"), originalBridge);
  });
});

test("patchExtractedCodexApp opens the older gradient-hosted plugin auth gate", () => {
  withFixture((root) => {
    const assets = join(root, "webview", "assets");
    mkdirSync(assets, { recursive: true });

    const gradientAuth = join(assets, "gradient-eD-LOZ9X.js");
    writeFileSync(
      gradientAuth,
      "function e(e){return e!==`chatgpt`}var t=``+new URL(`gradient-DoN1ti1h.png`,import.meta.url).href;export{e as n,t};\n",
    );

    const result = patchExtractedCodexApp(root);

    assert.equal(result.pluginAuth, "patched");
    assert.match(readFileSync(gradientAuth, "utf8"), /codex-patch:plugin-auth-open/);
    assert.match(readFileSync(gradientAuth, "utf8"), /function e\(e\)\{return !1/);
  });
});

test("patchExtractedCodexApp skips plugin auth when current app has no auth gate", () => {
  withFixture((root) => {
    const assets = join(root, "webview", "assets");
    mkdirSync(assets, { recursive: true });

    const gradient = join(assets, "gradient-B8xrjm6E.js");
    const source = "var e=``+new URL(`gradient-DoN1ti1h.png`,import.meta.url).href;export{e as t};\n";
    writeFileSync(gradient, source);

    const result = patchExtractedCodexApp(root);

    assert.equal(result.pluginAuth, "pattern-not-found");
    assert.equal(readFileSync(gradient, "utf8"), source);
  });
});

test("patchExtractedCodexApp adds a plugin-only ChatGPT account fallback without changing request routing", () => {
  withFixture((root) => {
    const assets = join(root, "webview", "assets");
    mkdirSync(assets, { recursive: true });

    const pluginAuth = join(assets, "plugin-auth-Drbk5jr_.js");
    writeFileSync(pluginAuth, "function e(e){return e!==`chatgpt`}export{e as t};\n");

    const manager = join(assets, "app-server-manager-signals-C1h8B-R-.js");
    const managerFixture =
      "function Dy(e,t){return Ey.sendRequest(e,t)}\n" +
      "var sS=class{constructor(e){this.hostId=e}sendRequest(e,t,n){return Dy(`send-cli-request-for-host`,{hostId:this.hostId,method:e,params:t,timeoutMs:n?.timeoutMs})}async getAccount(){return this.sendRequest(`account/read`,{refreshToken:!1})}};\n" +
      "var Wp=class{constructor(){this.hostId=`local`}sendRequest(e,t,n){return Dy(`send-cli-request-for-host`,{hostId:this.hostId,method:e,params:t,timeoutMs:n?.timeoutMs})}async getAccount(){return this.sendRequest(`account/read`,{refreshToken:!1})}readConfig(e){return this.sendRequest(`config/read`,e)}};\n";
    writeFileSync(manager, managerFixture);

    const useAuth = join(assets, "use-auth-H5MOLGyl.js");
    writeFileSync(
      useAuth,
      "function D(e,t){let n=E(e.account),r=t.useCopilotAuthIfAvailable&&t.isCopilotApiAvailable?`copilot`:e.account?.type===`amazonBedrock`?`amazonBedrock`:n;return{openAIAuth:n,authMethod:r,requiresAuth:r===`copilot`||(e.requiresOpenaiAuth??!0),email:e.account?.type===`chatgpt`?e.account.email:null,planAtLogin:e.account?.type===`chatgpt`?e.account.planType:null}}\n" +
        "function A(){let y={accountId:`acct`,userId:`user`},g=!1,b=!1,_=()=>{};return{...y,isLoading:g,isCopilotApiAvailable:b,accountId:null,userId:null,setAuthMethod:_}}\n",
    );

    const result = patchExtractedCodexApp(root);

    assert.equal(result.accountFallback, "patched");
    const patchedManager = readFileSync(manager, "utf8");
    assert.match(patchedManager, /codex-patch:plugin-account-fallback/);
    assert.match(patchedManager, /codex-patch:prefer-local-chatgpt-account/);
    assert.match(patchedManager, /codex-patch:account-read-file-methods/);
    assert.match(patchedManager, /\[`read-file`,`fs-read-file`\]/);
    assert.match(
      patchedManager,
      /async function codexPatchAccountForPlugins\(e,t\)\{let n=await t\(\),r=await codexPatchReadChatGptAccount\(e\);return r\?\?n\}/,
    );
    assert.match(patchedManager, /codexPatchAccountForPlugins\(this\.hostId,\(\)=>this\.sendRequest\(`account\/read`,\{refreshToken:!1\}\)\)/);
    assert.match(patchedManager, /send-cli-request-for-host/);

    assert.equal(result.useAuthAccountFields, "patched");
    const patchedUseAuth = readFileSync(useAuth, "utf8");
    assert.match(patchedUseAuth, /accountId:e\.account\?\.type===`chatgpt`\?e\.account\.accountId\?\?null:null/);
    assert.match(patchedUseAuth, /accountId:y\.accountId\?\?null,userId:y\.userId\?\?null/);
    assert.match(patchedUseAuth, /codex-patch:auth-account-output/);
  });
});

test("patchExtractedCodexApp supports current hashed app-server and auth bundle shapes", () => {
  withFixture((root) => {
    const assets = join(root, "webview", "assets");
    mkdirSync(assets, { recursive: true });

    const pluginAuth = join(assets, "plugin-auth-Drbk5jr_.js");
    writeFileSync(pluginAuth, "function e(e){return e!==`chatgpt`}export{e as t};\n");

    const manager = join(assets, "app-server-manager-signals-Csopz8aM.js");
    const managerFixture =
      "var Ft={sendRequest:(e,t)=>globalThis.__requests.push([e,t])};function It(e,t){return Ft.sendRequest(e,t)}\n" +
      "var br=class{constructor(e){this.hostId=e}sendRequest(e,t,n){return It(`send-cli-request-for-host`,{hostId:this.hostId,method:e,params:t,timeoutMs:n?.timeoutMs})}async getAccount(){return this.sendRequest(`account/read`,{refreshToken:!1})}readConfig(e){return this.sendRequest(`config/read`,e)}};\n";
    writeFileSync(manager, managerFixture);

    const useAuth = join(assets, "use-auth-BI4R_D9h.js");
    writeFileSync(
      useAuth,
      "function D(e,t){let n=E(e.account),r=t.useCopilotAuthIfAvailable&&t.isCopilotApiAvailable?`copilot`:e.account?.type===`amazonBedrock`?`amazonBedrock`:n;return{openAIAuth:n,authMethod:r,requiresAuth:r===`copilot`||(e.requiresOpenaiAuth??!0),email:e.account?.type===`chatgpt`?e.account.email:null,planAtLogin:e.account?.type===`chatgpt`?e.account.planType:null}}\n" +
        "function A(){let y={accountId:`acct`,userId:`user`},g=!1,b=!1,_=()=>{};return{...y,isLoading:g,isCopilotApiAvailable:b,accountId:null,userId:null,computeResidency:null,setAuthMethod:_}}\n",
    );

    const result = patchExtractedCodexApp(root);

    assert.equal(result.accountFallback, "patched");
    const patchedManager = readFileSync(manager, "utf8");
    assert.match(patchedManager, /function It\(e,t\)\{return Ft\.sendRequest\(e,t\)\}async function codexPatchDecodeJwtPayload/);
    assert.match(patchedManager, /let t=await It\(`codex-home`,\{hostId:e\}\)/);
    assert.match(patchedManager, /codexPatchReadChatGptAuthFile\(e,n\)/);
    assert.match(patchedManager, /codex-patch:account-read-file-methods/);
    assert.match(patchedManager, /typeof o\?\.email===`string`\?o\.email/);
    assert.match(patchedManager, /codex-patch:prefer-local-chatgpt-account/);
    assert.match(
      patchedManager,
      /async function codexPatchAccountForPlugins\(e,t\)\{let n=await t\(\),r=await codexPatchReadChatGptAccount\(e\);return r\?\?n\}/,
    );
    assert.match(patchedManager, /codexPatchAccountForPlugins\(this\.hostId,\(\)=>this\.sendRequest\(`account\/read`,\{refreshToken:!1\}\)\)/);

    assert.equal(result.useAuthAccountFields, "patched");
    const patchedUseAuth = readFileSync(useAuth, "utf8");
    assert.match(patchedUseAuth, /accountId:y\.accountId\?\?null,userId:y\.userId\?\?null\/\*codex-patch:auth-account-output\*\/,computeResidency:null/);
    assert.match(patchedUseAuth, /codex-patch:auth-account-output/);
  });
});

test("patchExtractedCodexApp preserves account fields in current use-auth output shape", () => {
  withFixture((root) => {
    const assets = join(root, "webview", "assets");
    mkdirSync(assets, { recursive: true });

    const useAuth = join(assets, "use-auth-6-yLHLKj.js");
    writeFileSync(
      useAuth,
      "function y(e,t){return{openAIAuth:`chatgpt`,authMethod:`chatgpt`,requiresAuth:!0,email:e.account.email,planAtLogin:e.account.planType,accountId:e.account.accountId??null,userId:e.account.userId??null/*codex-patch:auth-account-fields*/}}\n" +
        "function S(e){let g={accountId:`acct`,userId:`user`},_=!1,v=()=>{},x=!1,y;y=g;let b=y,S;return S={...b,isLoading:_,isCopilotApiAvailable:x,accountId:null,userId:null,computeResidency:null,setAuthMethod:v}}\n",
    );

    const result = patchExtractedCodexApp(root);

    assert.equal(result.useAuthAccountFields, "patched");
    const patchedUseAuth = readFileSync(useAuth, "utf8");
    assert.match(patchedUseAuth, /accountId:b\.accountId\?\?null,userId:b\.userId\?\?null\/\*codex-patch:auth-account-output\*\/,computeResidency:null,setAuthMethod:v/);
    assert.match(patchedUseAuth, /codex-patch:auth-account-output/);
    assert.doesNotMatch(patchedUseAuth, /accountId:null,userId:null/);
  });
});

test("patchExtractedCodexApp supports current plugin hook loading gate shape", () => {
  withFixture((root) => {
    const assets = join(root, "webview", "assets");
    mkdirSync(assets, { recursive: true });

    const pluginAuth = join(assets, "plugin-auth-Drbk5jr_.js");
    writeFileSync(pluginAuth, "function e(e){return e!==`chatgpt`}export{e as t};\n");

    const usePlugins = join(assets, "use-plugins-C8ZDLcLG.js");
    writeFileSync(
      usePlugins,
      "async function q(){await p(`list-plugins`,{})}\n" +
        "function usePlugins(){let z={isLoading:false,isFetching:false},m={isLoading:false,isFetching:false},w={isLoading:false},A={isLoading:false},S={isLoading:false};" +
        "let availablePlugins=[],X=j&&m.isLoading||z.isLoading||w.isLoading||A.isLoading||S.isLoading,Z=j&&m.isFetching||z.isFetching||S.isFetching;" +
        "return{availablePlugins,isLoading:X,isFetching:Z}}\n",
    );

    const result = patchExtractedCodexApp(root);

    assert.equal(result.pluginsHookLoading, "patched");
    const patched = readFileSync(usePlugins, "utf8");
    assert.match(patched, /X=\/\*codex-patch:plugins-loading\*\/j&&m\.isLoading\|\|z\.isLoading/);
    assert.match(patched, /Z=j&&m\.isFetching\|\|z\.isFetching/);
    assert.doesNotMatch(patched, /w\.isLoading\|\|A\.isLoading\|\|S\.isLoading/);
  });
});

test("patchExtractedCodexApp supports current plugins page loading gate shape", () => {
  withFixture((root) => {
    const assets = join(root, "webview", "assets");
    mkdirSync(assets, { recursive: true });

    const pluginAuth = join(assets, "plugin-auth-Drbk5jr_.js");
    writeFileSync(pluginAuth, "function e(e){return e!==`chatgpt`}export{e as t};\n");

    const pluginsPage = join(assets, "plugins-page-D2hN-W-s.js");
    writeFileSync(
      pluginsPage,
      "var Z={loading:{id:`plugins.page.loading`,defaultMessage:`Loading plugins…`}};" +
        "function Or(){let {errorMessage:cn,featuredPluginIds:un,isLoading:dn,isFetching:mn,marketplaceLoadErrors:hn,marketplaces:gn,availablePlugins:_n,installedPlugins:vn,forceReload:yn,refetch:Y}=pe(I,K);" +
        "let Ea=dn||X&&Ue||X&&ai&&Q===`plugins`&&Dn||we===`loading`||(bi?Dn||kn:zi&&Dn||Ri===Tr&&kn),Da=z||dn||mn;" +
        "return {isLoading:Ea,isRetrying:Da}}\n",
    );

    const result = patchExtractedCodexApp(root);

    assert.equal(result.pluginsPageLoading, "patched");
    const patched = readFileSync(pluginsPage, "utf8");
    assert.match(patched, /Ea=\/\*codex-patch:plugins-page-loading\*\/dn,Da=/);
    assert.doesNotMatch(patched, /we===`loading`/);
  });
});

test("patchExtractedCodexApp shows all marketplace plugins in the default plugin directory tab", () => {
  withFixture((root) => {
    const assets = join(root, "webview", "assets");
    mkdirSync(assets, { recursive: true });

    const pluginsPage = join(assets, "plugins-page-DBgyZZKr.js");
    writeFileSync(
      pluginsPage,
      "function page(){let Ni=$e(Fn),ea=Ni.filter(rt),aa;" +
        "switch(W){case`openai`:aa=ot({connectedPlugins:ia,featuredPluginIds:$?void 0:jn,plugins:it({plugins:ea,query:Bi})});break;case`workspace`:aa=ot({connectedPlugins:ia,plugins:it({plugins:Ii??[],query:Bi})});break}" +
        "return a.formatMessage({id:`skills.appsPage.directoryTabs.openai`,defaultMessage:`By OpenAI`,description:`Label for plugins built by OpenAI in the plugin directory`})}\n",
    );

    const result = patchExtractedCodexApp(root);

    assert.equal(result.pluginsCatalogAll, "patched");
    const patched = readFileSync(pluginsPage, "utf8");
    assert.match(patched, /plugins:Ni\/\*codex-patch:plugins-catalog-all\*\/,query:Bi/);
    assert.doesNotMatch(patched, /plugins:ea,query:Bi/);
    assert.match(patched, /defaultMessage:`All`/);
    assert.match(patched, /Label for all installable plugins/);
  });
});

test("patchExtractedCodexApp adds desktop auth headers to WHAM requests", () => {
  withFixture((root) => {
    const assets = join(root, "webview", "assets");
    mkdirSync(assets, { recursive: true });

    const pluginAuth = join(assets, "plugin-auth-Drbk5jr_.js");
    writeFileSync(pluginAuth, "function e(e){return e!==`chatgpt`}export{e as t};\n");

    const build = join(root, ".vite", "build");
    mkdirSync(build, { recursive: true });
    const main = join(build, "main-BS7yenMI.js");
    writeFileSync(
      main,
      "var HJ=!1,UJ=new WeakSet;function WJ(){if(HJ)return;let e=`session`in n?n.session?.defaultSession:void 0;e?.webRequest!=null&&(HJ=!0,e.webRequest.onBeforeSendHeaders((t,r)=>{let i=t.requestHeaders;r({requestHeaders:OJ({frame:t.frame,requestHeaders:i,url:t.url})?BJ(i,{acceptLanguage:KJ(),excludedUserAgentProducts:[`Electron`,n.app.getName()],userAgent:e.getUserAgent()}):i})}))}\n",
    );

    const result = patchExtractedCodexApp(root);

    assert.equal(result.whamDesktopAuth, "patched");
    const patched = readFileSync(main, "utf8");
    assert.match(patched, /codex-patch:wham-desktop-auth/);
    assert.match(patched, /codexPatchWhamDesktopAuthHeaders\(t\.url,t\.requestHeaders\)/);
    assert.match(patched, /\/backend-api\/wham\//);
  });
});

test("patchExtractedCodexApp adds desktop auth headers to current WHAM request hook shape", () => {
  withFixture((root) => {
    const assets = join(root, "webview", "assets");
    mkdirSync(assets, { recursive: true });

    const build = join(root, ".vite", "build");
    mkdirSync(build, { recursive: true });
    const main = join(build, "main-B6dx2gAb.js");
    writeFileSync(
      main,
      "var A0=!1,j0=new WeakSet;function M0(){if(A0)return;let e=`session`in a?a.session?.defaultSession:void 0;e?.webRequest!=null&&(A0=!0,e.webRequest.onBeforeSendHeaders((t,n)=>{let r=t.requestHeaders;n({requestHeaders:g0({frame:t.frame,requestHeaders:r,url:t.url})?O0(r,{acceptLanguage:P0(),excludedUserAgentProducts:[`Electron`,a.app.getName()],userAgent:e.getUserAgent()}):r})}))}\n",
    );

    const result = patchExtractedCodexApp(root);

    assert.equal(result.whamDesktopAuth, "patched");
    const patched = readFileSync(main, "utf8");
    assert.match(patched, /codex-patch:wham-desktop-auth/);
    assert.match(patched, /codexPatchWhamDesktopAuthHeaders\(t\.url,t\.requestHeaders\)/);
  });
});

test("patchExtractedCodexApp forces packaged desktop feature availability for Computer Use", () => {
  withFixture((root) => {
    const assets = join(root, "webview", "assets");
    mkdirSync(assets, { recursive: true });

    const build = join(root, ".vite", "build");
    mkdirSync(build, { recursive: true });
    const main = join(build, "main-B6dx2gAb.js");
    writeFileSync(
      main,
      "var Ie={ambientSuggestions:!1,appshotsEnabled:!1,browserPane:!1,inAppBrowserUse:!1,inAppBrowserUseAllowed:!1,externalBrowserUse:!1,externalBrowserUseAllowed:!1,computerUse:!1,computerUseNodeRepl:!1,sites:!1,control:!1,deviceAttestation:xe(),dil:!1,multiBrowserTabs:!1,multiWindow:!1,processManager:!1},Le=Object.keys(Ie),Re={...Ie},ze=`CODEX_ELECTRON_DESKTOP_FEATURE_OVERRIDES`;function Be(){return Re}function Ve(e){return Le.every(t=>typeof e[t]==`boolean`)}function He(e,t){return Le.some(n=>e[n]!==t[n])}function Ue(e){let t={...Re,...e,deviceAttestation:xe()};return Le.every(e=>t[e]===Re[e])?!1:(Re=t,!0)}function We(e,{buildFlavor:t=r.N.resolve(),env:n=h.default.env,platform:i=h.default.platform}={}){let a=i===`win32`&&n.CODEX_ELECTRON_ENABLE_WINDOWS_COMPUTER_USE===`1`?{...e,computerUse:!0,computerUseNodeRepl:!0}:e,o=t===r.N.Dev?Ge(n):null;return o==null?{...a,deviceAttestation:xe({platform:i})}:{...a,...o,deviceAttestation:xe({platform:i})}}function Ge(e){return null}\n",
    );

    const result = patchExtractedCodexApp(root);

    assert.equal(result.desktopFeatureAvailability, "patched");
    const patched = readFileSync(main, "utf8");
    assert.match(patched, /codex-patch:desktop-feature-availability/);
    assert.match(patched, /function codexPatchDesktopFeatureAvailability\(e\)\{return\{\.\.\.e,appshotsEnabled:!0/);
    assert.match(patched, /computerUse:!0,computerUseNodeRepl:!0/);
    assert.match(patched, /recordAndReplay:!0/);
    assert.match(patched, /return codexPatchDesktopFeatureAvailability\(o==null\?\{\.\.\.a,deviceAttestation:xe\(\{platform:i\}\)\}:\{\.\.\.a,\.\.\.o,deviceAttestation:xe\(\{platform:i\}\)\}\)/);
  });
});

test("patchExtractedCodexApp upgrades desktop feature availability to include Record & Replay", () => {
  withFixture((root) => {
    const assets = join(root, "webview", "assets");
    mkdirSync(assets, { recursive: true });

    const build = join(root, ".vite", "build");
    mkdirSync(build, { recursive: true });
    const main = join(build, "main-B6dx2gAb.js");
    writeFileSync(
      main,
      "function codexPatchDesktopFeatureAvailability(e){return{...e,appshotsEnabled:!0,browserPane:!0,inAppBrowserUse:!0,inAppBrowserUseAllowed:!0,externalBrowserUse:!0,externalBrowserUseAllowed:!0,computerUse:!0,computerUseNodeRepl:!0,sites:!0,control:!0,multiBrowserTabs:!0/*codex-patch:desktop-feature-availability*/}}\n",
    );

    const result = patchExtractedCodexApp(root);

    assert.equal(result.desktopFeatureAvailability, "patched");
    const patched = readFileSync(main, "utf8");
    assert.match(patched, /recordAndReplay:!0\/\*codex-patch:desktop-feature-availability\*\//);
  });
});

test("patchExtractedCodexApp disables Sparkle background updates", () => {
  withFixture((root) => {
    const assets = join(root, "webview", "assets");
    mkdirSync(assets, { recursive: true });

    const build = join(root, ".vite", "build");
    mkdirSync(build, { recursive: true });
    const updater = join(build, "workspace-root-drop-handler.js");
    writeFileSync(
      updater,
      "class YB{async initializeMacSparkle(){if(process.platform!==`darwin`){this.lastUnavailableReason=`unsupported platform`;return}let d=()=>{c.checkForUpdatesInBackground()};let f=JB();f>0&&setInterval(d,f).unref(),d()}}\n",
    );

    const result = patchExtractedCodexApp(root);

    assert.equal(result.sparkleUpdatesDisabled, "patched");
    const patched = readFileSync(updater, "utf8");
    assert.match(patched, /codex-patch:disable-sparkle-updates/);
    assert.match(patched, /this\.lastUnavailableReason=`disabled by local patch`;return\/\*codex-patch:disable-sparkle-updates\*\//);
  });
});

test("patchExtractedCodexApp lets desktop auth paths reuse the local ChatGPT token", () => {
  withFixture((root) => {
    const assets = join(root, "webview", "assets");
    mkdirSync(assets, { recursive: true });

    const build = join(root, ".vite", "build");
    mkdirSync(build, { recursive: true });
    const main = join(build, "main-B6dx2gAb.js");
    writeFileSync(
      main,
      "async function Im({action:e,appServerClient:t,desktopOriginator:n,headers:r={},refreshToken:i=!1}){let a=await t.getAuthToken({refreshToken:i});if(!a)throw Error(`Sign in to ChatGPT in Codex Desktop to ${e}.`);let o={...r};return Lm(o,a,{desktopOriginator:n}),o}\n" +
        'var handlers={"account-info":async()=>{try{let e=await this.appServerConnectionRegistry.getConnection(I).getAuthToken({refreshToken:!1});if(!e)return{accountId:null,userId:null,plan:null,email:null,computeResidency:null};let[,t]=e.split(`.`);return{accountId:t,userId:null,plan:null,email:null,computeResidency:null}}catch(e){return{accountId:null,userId:null,plan:null,email:null,computeResidency:null}}}};\n',
    );

    const result = patchExtractedCodexApp(root);

    assert.equal(result.desktopAuthTokenFallback, "patched");
    const patched = readFileSync(main, "utf8");
    assert.match(patched, /codex-patch:desktop-auth-token-fallback/);
    assert.match(patched, /a\|\|=codexPatchDesktopAuthTokenRead\(\);if\(!a\)throw Error/);
    assert.match(patched, /e\|\|=codexPatchDesktopAuthTokenRead\(\);if\(!e\)return\{accountId:null/);
  });
});

test("patchExtractedCodexApp shows profile settings for local ChatGPT login", () => {
  withFixture((root) => {
    const assets = join(root, "webview", "assets");
    mkdirSync(assets, { recursive: true });

    const profileVisibility = join(assets, "profile-visibility-WAr1jsej.js");
    writeFileSync(
      profileVisibility,
      "var c=`show_dropdown_entry_point`;\n" +
        "function l(){let e=(0,a.c)(3),{authMethod:r,isLoading:s}=i(),c=t(),l=n(o),u=s||r===`chatgpt`&&c,d=r===`chatgpt`&&l,f;return e[0]!==u||e[1]!==d?(f={isProfileVisibilityLoading:u,isProfileVisible:d},e[0]=u,e[1]=d,e[2]=f):f=e[2],f}\n" +
        "function u(){let e=(0,a.c)(3),{authMethod:t}=i(),l=n(o),u=r(s);if(t!==`chatgpt`)return!1;let d;return e[0]!==l||e[1]!==u?(d=l&&u.get(c,!1),e[0]=l,e[1]=u,e[2]=d):d=e[2],d}\n",
    );

    const result = patchExtractedCodexApp(root);

    assert.equal(result.profileVisibleWithChatgpt, "patched");
    const patched = readFileSync(profileVisibility, "utf8");
    assert.match(patched, /codex-patch:profile-visible-with-chatgpt/);
    assert.match(patched, /codex-patch:profile-dropdown-visible/);
    assert.match(patched, /d=!0\/\*codex-patch:profile-visible-with-chatgpt\*\//);
    assert.match(patched, /let d;return e\[0\]!==l\|\|e\[1\]!==u\?\(d=!0\/\*codex-patch:profile-dropdown-visible\*\//);
    assert.doesNotMatch(patched, /d=r===`chatgpt`&&l/);
    assert.doesNotMatch(patched, /d=r===`chatgpt`\/\*codex-patch:profile-visible-with-chatgpt\*\//);
    assert.doesNotMatch(patched, /if\(t!==`chatgpt`\)return!1/);
    assert.doesNotMatch(patched, /d=l&&u\.get\(c,!1\)/);
  });
});

test("patchExtractedCodexApp upgrades an older profile visibility patch", () => {
  withFixture((root) => {
    const assets = join(root, "webview", "assets");
    mkdirSync(assets, { recursive: true });

    const profileVisibility = join(assets, "profile-visibility-WAr1jsej.js");
    writeFileSync(
      profileVisibility,
      "var c=`show_dropdown_entry_point`;\n" +
        "function l(){let e=(0,a.c)(3),{authMethod:r,isLoading:s}=i(),c=t(),l=n(o),u=s||r===`chatgpt`&&c,d=r===`chatgpt`/*codex-patch:profile-visible-with-chatgpt*/,f;return e[0]!==u||e[1]!==d?(f={isProfileVisibilityLoading:u,isProfileVisible:d},e[0]=u,e[1]=d,e[2]=f):f=e[2],f}\n" +
        "function u(){let e=(0,a.c)(3),{authMethod:t}=i(),l=n(o),u=r(s);if(t!==`chatgpt`)return!1;let d;return e[0]!==l||e[1]!==u?(d=!0,e[0]=l,e[1]=u,e[2]=d):d=e[2],d}\n",
    );

    const result = patchExtractedCodexApp(root);

    assert.equal(result.profileVisibleWithChatgpt, "patched");
    const patched = readFileSync(profileVisibility, "utf8");
    assert.match(patched, /codex-patch:profile-visible-with-chatgpt/);
    assert.match(patched, /codex-patch:profile-dropdown-visible/);
    assert.match(patched, /d=!0\/\*codex-patch:profile-visible-with-chatgpt\*\//);
    assert.doesNotMatch(patched, /d=r===`chatgpt`\/\*codex-patch:profile-visible-with-chatgpt\*\//);
    assert.doesNotMatch(patched, /if\(t!==`chatgpt`\)return!1/);
  });
});

test("patchExtractedCodexApp upgrades a fully marked profile visibility patch that still checks ChatGPT auth", () => {
  withFixture((root) => {
    const assets = join(root, "webview", "assets");
    mkdirSync(assets, { recursive: true });

    const profileVisibility = join(assets, "profile-visibility-WAr1jsej.js");
    writeFileSync(
      profileVisibility,
      "var c=`show_dropdown_entry_point`;\n" +
        "function l(){let e=(0,a.c)(3),{authMethod:r,isLoading:s}=i(),c=t(),l=n(o),u=s||r===`chatgpt`&&c,d=r===`chatgpt`/*codex-patch:profile-visible-with-chatgpt*/,f;return e[0]!==u||e[1]!==d?(f={isProfileVisibilityLoading:u,isProfileVisible:d},e[0]=u,e[1]=d,e[2]=f):f=e[2],f}\n" +
        "function u(){let e=(0,a.c)(3),{authMethod:t}=i(),l=n(o),u=r(s);let d;return e[0]!==l||e[1]!==u?(d=!0/*codex-patch:profile-dropdown-visible*/,e[0]=l,e[1]=u,e[2]=d):d=e[2],d}\n",
    );

    const result = patchExtractedCodexApp(root);

    assert.equal(result.profileVisibleWithChatgpt, "patched");
    const patched = readFileSync(profileVisibility, "utf8");
    assert.match(patched, /d=!0\/\*codex-patch:profile-visible-with-chatgpt\*\//);
    assert.doesNotMatch(patched, /d=r===`chatgpt`\/\*codex-patch:profile-visible-with-chatgpt\*\//);
  });
});

test("patchExtractedCodexApp upgrades an older account fallback helper in place", () => {
  withFixture((root) => {
    const assets = join(root, "webview", "assets");
    mkdirSync(assets, { recursive: true });

    const pluginAuth = join(assets, "plugin-auth-Drbk5jr_.js");
    writeFileSync(pluginAuth, "function e(e){return !1/*codex-patch:plugin-auth-open*/}export{e as t};\n");

    const manager = join(assets, "app-server-manager-signals-Csopz8aM.js");
    writeFileSync(
      manager,
      "function It(e,t){return Ft.sendRequest(e,t)}" +
        "async function codexPatchReadChatGptAccount(e){let t=await It(`codex-home`,{hostId:e}),n=t?.codexHome;if(typeof n!==`string`||n.length===0)return null;let r=await It(`read-file`,{hostId:e,path:`${n.replace(/[/]+$/,``)}/auth.json`}),i=JSON.parse(r?.contents??``);if(i?.auth_mode!==`chatgpt`)return null;let a=i.tokens??{},o={},c=o?.[`https://api.openai.com/profile`]??{},l=typeof c.email===`string`?c.email:null,u=`acct`,d=`user`;return l==null?null:{account:{type:`chatgpt`,email:l,accountId:u,userId:d},requiresOpenaiAuth:!1}}" +
        "async function codexPatchAccountForPlugins(e,t){let n=await t();if(n?.account!=null||n?.requiresOpenaiAuth!==!1)return n;return(await codexPatchReadChatGptAccount(e))??n}" +
        "/*codex-patch:plugin-account-fallback*/" +
        "var br=class{constructor(e){this.hostId=e}async getAccount(){return codexPatchAccountForPlugins(this.hostId,()=>this.sendRequest(`account/read`,{refreshToken:!1}))}};\n",
    );

    const result = patchExtractedCodexApp(root);

    assert.equal(result.accountFallback, "patched");
    const patchedManager = readFileSync(manager, "utf8");
    assert.match(patchedManager, /typeof o\?\.email===`string`\?o\.email/);
    assert.match(patchedManager, /l\.length===0&&u==null&&d==null\?null/);
    assert.match(patchedManager, /codex-patch:account-read-file-methods/);
    assert.match(patchedManager, /codexPatchReadChatGptAuthFile\(e,n\)/);
    assert.match(patchedManager, /\[`read-file`,`fs-read-file`\]/);
    assert.match(patchedManager, /codex-patch:prefer-local-chatgpt-account/);
    assert.match(
      patchedManager,
      /async function codexPatchAccountForPlugins\(e,t\)\{let n=await t\(\),r=await codexPatchReadChatGptAccount\(e\);return r\?\?n\}/,
    );
  });
});

test("patchExtractedCodexApp shows Usage settings for local ChatGPT login", () => {
  withFixture((root) => {
    const assets = join(root, "webview", "assets");
    mkdirSync(assets, { recursive: true });

    const usageAccess = join(assets, "use-usage-settings-access-BOSFYGOE.js");
    writeFileSync(
      usageAccess,
      "function m({authMethod:e,plan:t,isFreeGoUsageSettingsEnabled:n,isEnterpriseUsageSettingsEnabled:r=!1}){let i=e===`chatgpt`,a=i&&h(t),o=g(t),s=c(t);return{canManageCreditSettings:a,isUsageSettingsVisible:a||i&&o&&n||i&&s&&r}}export{p as t};\n",
    );

    const result = patchExtractedCodexApp(root);

    assert.equal(result.usageSettingsVisible, "patched");
    const patched = readFileSync(usageAccess, "utf8");
    assert.match(patched, /codex-patch:usage-settings-visible/);
    assert.match(patched, /isUsageSettingsVisible:i\|\|a\|\|i&&o&&n\|\|i&&s&&r/);
  });
});

test("patchExtractedCodexApp shows local Computer Use and Browser Use settings", () => {
  withFixture((root) => {
    const assets = join(root, "webview", "assets");
    mkdirSync(assets, { recursive: true });

    const settingsPage = join(assets, "settings-page-CzYYqdVO.js");
    writeFileSync(
      settingsPage,
      "function ht(e,t,r){let i=(0,He.c)(46),a=e===void 0?null:e,o=t===void 0?!0:t,s=r===void 0?n:r,l;let y=!1,E=!1,D=!1,te=!0;let e2=e=>{switch(e.slug){case`usage`:return y;case`profile`:return te;case`computer-use`:return E;case`browser-use`:return D;case`general-settings`:return!0}};return e2}\n",
    );

    const result = patchExtractedCodexApp(root);

    assert.equal(result.localDesktopSettingsVisible, "patched");
    const patched = readFileSync(settingsPage, "utf8");
    assert.match(patched, /codex-patch:local-desktop-settings-visible/);
    assert.match(patched, /codex-patch:local-usage-settings-visible/);
    assert.match(patched, /case`usage`:return o\/\*codex-patch:local-usage-settings-visible\*\//);
    assert.match(patched, /case`computer-use`:return o\/\*codex-patch:local-desktop-settings-visible\*\//);
    assert.match(patched, /case`browser-use`:return o\/\*codex-patch:local-desktop-settings-visible\*\//);
  });
});

test("patchExtractedCodexApp shows Locked use locally even when plugin availability gates are unavailable", () => {
  withFixture((root) => {
    const assets = join(root, "webview", "assets");
    mkdirSync(assets, { recursive: true });

    const computerUseSettings = join(assets, "computer-use-settings-BrS9tSXk.js");
    writeFileSync(
      computerUseSettings,
      "function Me(){let e=(0,Z.c)(20),{selectedHostId:t}=de(),n=l(R,t),r;e[0]===t?r=e[1]:(r={hostId:t},e[0]=t,e[1]=r);let i=N(r),{platform:a}=M();let d;e[8]!==n||e[9]!==i.available||e[10]!==a?(d=a===`macOS`&&i.available&&n?(0,Q.jsx)(Ve,{}):null,e[8]=n,e[9]=i.available,e[10]=a,e[11]=d):d=e[11];return d}\n" +
        "function Ve(){let e=(0,Z.c)(25),n=g(),r=o(),i=c(oe),a=e=>{};let d={mutationFn:ae,onSuccess:a,onError:()=>{}};let p=u(d);if(i.data?.enabled==null)return null;let m;e[8]!==i.data.computerIconDataURL||e[9]!==i.data.lockIconDataURL?(m=i.data.computerIconDataURL!=null&&i.data.lockIconDataURL!=null?i.data.computerIconDataURL:null,e[8]=i.data.computerIconDataURL,e[9]=i.data.lockIconDataURL,e[10]=m):m=e[10];let C;e[17]!==i.data.enabled?(C=i.data.enabled,e[17]=i.data.enabled,e[21]=C):C=e[21];return C}\n" +
        "var label=`settings.computerUse.backgroundAuth.label`;\n",
    );

    const result = patchExtractedCodexApp(root);

    assert.equal(result.lockedUseSettingsVisible, "patched");
    const patched = readFileSync(computerUseSettings, "utf8");
    assert.match(patched, /codex-patch:locked-use-settings-visible/);
    assert.match(patched, /codex-patch:locked-use-data-fallback/);
    assert.match(patched, /d=a===`macOS`&&t===`local`\?\(0,Q\.jsx\)\(Ve,\{\}\):null/);
    assert.match(patched, /codexPatchLockedUseData=i\.data\?\?\{enabled:!1,computerIconDataURL:null,lockIconDataURL:null\}/);
    assert.match(patched, /checked:codexPatchLockedUseData\.enabled|C=codexPatchLockedUseData\.enabled/);
    assert.doesNotMatch(patched, /&&i\.available&&n\?/);
    assert.doesNotMatch(patched, /if\(i\.data\?\.enabled==null\)return null/);
    assert.doesNotMatch(patched, /i\.data\./);
  });
});

test("patchExtractedCodexApp shows Locked use for the current computer-use settings bundle shape", () => {
  withFixture((root) => {
    const assets = join(root, "webview", "assets");
    mkdirSync(assets, { recursive: true });

    const computerUseSettings = join(assets, "computer-use-settings-DiwUx96C.js");
    writeFileSync(
      computerUseSettings,
      "function je(){let e=(0,X.c)(20),{selectedHostId:t}=G(),n=i(z,t),r;e[0]===t?r=e[1]:(r={hostId:t},e[0]=t,e[1]=r);let a=F(r),{platform:o}=P();let d;e[8]!==n||e[9]!==a.available||e[10]!==o?(d=o===`macOS`&&a.available&&n?(0,Z.jsx)(Be,{}):null,e[8]=n,e[9]=a.available,e[10]=o,e[11]=d):d=e[11];return d}\n" +
        "function Be(){let e=(0,X.c)(25),t=a(s),n=h(),r=u(),i=o(de),c;c=e[2];let d;e[3]===t?d=e[4]:(d=()=>{},e[3]=t,e[4]=d);let p;e[5]!==c||e[6]!==d?(p={mutationFn:ue,onSuccess:c,onError:d},e[5]=c,e[6]=d,e[7]=p):p=e[7];let m=l(p);if(i.data?.enabled==null)return null;let _;e[8]!==i.data.computerIconDataURL||e[9]!==i.data.lockIconDataURL?(_=i.data.computerIconDataURL!=null&&i.data.lockIconDataURL!=null?i.data.computerIconDataURL:null,e[8]=i.data.computerIconDataURL,e[9]=i.data.lockIconDataURL,e[10]=_):_=e[10];let C;e[17]!==i.data.enabled?(C=i.data.enabled,e[17]=i.data.enabled,e[21]=C):C=e[21];return C}\n" +
        "var label=`settings.computerUse.backgroundAuth.label`;\n",
    );

    const result = patchExtractedCodexApp(root);

    assert.equal(result.lockedUseSettingsVisible, "patched");
    const patched = readFileSync(computerUseSettings, "utf8");
    assert.match(patched, /codex-patch:locked-use-settings-visible/);
    assert.match(patched, /codex-patch:locked-use-data-fallback/);
    assert.match(patched, /d=o===`macOS`&&t===`local`\?\(0,Z\.jsx\)\(Be,\{\}\):null/);
    assert.match(patched, /codexPatchLockedUseData=i\.data\?\?\{enabled:!1,computerIconDataURL:null,lockIconDataURL:null\}/);
    assert.match(patched, /C=codexPatchLockedUseData\.enabled/);
    assert.doesNotMatch(patched, /&&a\.available&&n\?/);
    assert.doesNotMatch(patched, /if\(i\.data\?\.enabled==null\)return null/);
    assert.doesNotMatch(patched, /i\.data\./);
  });
});

test("patchExtractedCodexApp bypasses the Appshot Statsig gate", () => {
  withFixture((root) => {
    const assets = join(root, "webview", "assets");
    mkdirSync(assets, { recursive: true });

    const appshotAvailability = join(assets, "appshot-availability-Brs8mSNt.js");
    writeFileSync(
      appshotAvailability,
      "import{c as e,l as t,t as n}from\"./app-scope.js\";import{M as r}from\"./thread-context-inputs.js\";import{f as i}from\"./statsig.js\";import{n as a}from\"./platform.js\";import{c as o}from\"./config-queries.js\";var s=t(n,(e,{get:t})=>{if(t(a)!==`macOS`||!t(i,`1304276663`))return!1;let{data:n}=t(o,{hostId:e});return n!=null&&n.requirements?.allowAppshots!==!1}),c=e(n,({get:e})=>e(s,e(r)));export{s as n,c as t};\n",
    );

    const result = patchExtractedCodexApp(root);

    assert.equal(result.appshotAvailability, "patched");
    const patched = readFileSync(appshotAvailability, "utf8");
    assert.match(patched, /codex-patch:appshot-availability/);
    assert.match(patched, /if\(t\(a\)!==`macOS`\)return!1\/\*codex-patch:appshot-availability\*\//);
    assert.match(patched, /allowAppshots/);
    assert.doesNotMatch(patched, /1304276663/);
  });
});

test("patchExtractedCodexApp enables the bundled Computer Use MCP default", () => {
  withFixture((root) => {
    const assets = join(root, "webview", "assets");
    mkdirSync(assets, { recursive: true });

    const build = join(root, ".vite", "build");
    mkdirSync(build, { recursive: true });

    const main = join(build, "main-CIL4OHS5.js");
    writeFileSync(
      main,
      "var It=`computer-use`;var Gn={[It]:{command:`./Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient`,args:[`mcp`],cwd:`.`,enabled:!1}};\n",
    );

    const result = patchExtractedCodexApp(root);

    assert.equal(result.computerUseMcpEnabled, "patched");
    const patched = readFileSync(main, "utf8");
    assert.match(patched, /codex-patch:computer-use-mcp-enabled/);
    assert.match(patched, /enabled:!0/);
    assert.match(patched, /process\.env\.HOME/);
    assert.match(patched, /\/\.codex\/computer-use\/Codex Computer Use\.app/);
    assert.doesNotMatch(patched, /enabled:!1/);
    assert.doesNotMatch(patched, /command:`\.\/Codex Computer Use\.app/);
  });
});

test("patchExtractedCodexApp is idempotent for an already-open plugin auth gate", () => {
  withFixture((root) => {
    const assets = join(root, "webview", "assets");
    mkdirSync(assets, { recursive: true });

    const pluginAuth = join(assets, "plugin-auth-Drbk5jr_.js");
    const alreadyPatched = "function e(e){return !1}export{e as t};\n";
    writeFileSync(pluginAuth, alreadyPatched);

    const result = patchExtractedCodexApp(root);

    assert.equal(result.pluginAuth, "already-patched");
    assert.equal(readFileSync(pluginAuth, "utf8"), alreadyPatched);
  });
});

function withFixture(fn) {
  const root = mkdtempSync(join(tmpdir(), "codex-plugin-patch-test-"));
  try {
    fn(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}
