# Fix Codex Plugins Page

Patches the Codex desktop app so the plugin UI is accessible when the active chat provider is a custom/API provider. Chat still uses the configured `codex app-server` provider flow from `~/.codex/config.toml`.

## Trigger phrases
- fix codex plugins
- codex plugins not showing
- codex plugins disabled
- codex plugins require login
- 修复codex插件
- codex插件看不到

## What this skill does

Runs `fix-codex-plugins.sh` which:
1. Extracts `Codex.app/Contents/Resources/app.asar`
2. Patches the central plugin auth gate so plugin UI does not depend on the active chat provider's auth method
3. Adds a plugin-only ChatGPT account fallback from local `~/.codex/auth.json`, while leaving chat requests on the configured app-server provider
4. Patches the sidebar and plugin loading gates for bundle compatibility
5. Disables Electron's asar integrity validation fuse
6. Repacks the asar, updates the Info.plist hash, and re-signs the app

## Usage

```bash
bash ~/projects/dev/tools/codex-patch/fix-codex-plugins.sh
```

Then relaunch Codex.

## When to re-run

- After any Codex app update (the asar gets replaced with the original)
- If the Plugins sidebar item disappears or shows "Please sign in with ChatGPT"
- If Codex keeps chat on a custom provider but hides Plugins as though ChatGPT auth is missing

## How to invoke

When the user asks to fix Codex plugins, run:

```bash
bash /Users/matrix/projects/dev/tools/codex-patch/fix-codex-plugins.sh
```

Check the output for any `[warn]` lines — those indicate a pattern changed after an app update and may need a manual patch update.
