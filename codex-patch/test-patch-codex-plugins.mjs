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
