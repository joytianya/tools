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
    assert.match(patchedManager, /codexPatchAccountForPlugins\(this\.hostId,\(\)=>this\.sendRequest\(`account\/read`,\{refreshToken:!1\}\)\)/);
    assert.match(patchedManager, /send-cli-request-for-host/);

    assert.equal(result.useAuthAccountFields, "patched");
    const patchedUseAuth = readFileSync(useAuth, "utf8");
    assert.match(patchedUseAuth, /accountId:e\.account\?\.type===`chatgpt`\?e\.account\.accountId\?\?null:null/);
    assert.match(patchedUseAuth, /accountId:y\.accountId\?\?null,userId:y\.userId\?\?null/);
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
    assert.match(patchedManager, /typeof o\?\.email===`string`\?o\.email/);
    assert.match(patchedManager, /codexPatchAccountForPlugins\(this\.hostId,\(\)=>this\.sendRequest\(`account\/read`,\{refreshToken:!1\}\)\)/);

    assert.equal(result.useAuthAccountFields, "patched");
    const patchedUseAuth = readFileSync(useAuth, "utf8");
    assert.match(patchedUseAuth, /accountId:y\.accountId\?\?null,userId:y\.userId\?\?null,computeResidency:null/);
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
        "async function codexPatchReadChatGptAccount(e){let o={},c=o?.[`https://api.openai.com/profile`]??{},l=typeof c.email===`string`?c.email:null,u=`acct`,d=`user`;return l==null?null:{account:{type:`chatgpt`,email:l,accountId:u,userId:d},requiresOpenaiAuth:!1}}" +
        "/*codex-patch:plugin-account-fallback*/" +
        "var br=class{constructor(e){this.hostId=e}async getAccount(){return codexPatchAccountForPlugins(this.hostId,()=>this.sendRequest(`account/read`,{refreshToken:!1}))}};\n",
    );

    const result = patchExtractedCodexApp(root);

    assert.equal(result.accountFallback, "patched");
    const patchedManager = readFileSync(manager, "utf8");
    assert.match(patchedManager, /typeof o\?\.email===`string`\?o\.email/);
    assert.match(patchedManager, /l\.length===0&&u==null&&d==null\?null/);
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
