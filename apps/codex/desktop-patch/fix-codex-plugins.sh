#!/usr/bin/env bash
# fix-codex-plugins.sh
# Patches Codex.app so the plugin UI is not blocked by the active chat provider.
# Safe to re-run after app updates.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="/Applications/Codex.app"
ASAR="$APP/Contents/Resources/app.asar"
PLIST="$APP/Contents/Info.plist"
WORK="/tmp/codex_patch_$$"
SIGN_IDENTITY="${CODEX_PATCH_SIGN_IDENTITY:-Codex Local Patch Signing}"

log()  { echo "[patch] $*"; }
die()  { echo "[error] $*" >&2; exit 1; }

codex_app_process_pids() {
    ps -axo pid=,command= | awk -v app="$APP/Contents/" 'index($0, app) { print $1 }'
}

kill_codex_app_processes() {
    local pids

    pids="$(codex_app_process_pids || true)"
    [[ -n "$pids" ]] || return 0

    log "Terminating Codex.app helper processes..."
    while IFS= read -r pid; do
        [[ -n "$pid" ]] || continue
        kill -TERM "$pid" 2>/dev/null || true
    done <<< "$pids"

    for _ in {1..20}; do
        [[ -z "$(codex_app_process_pids || true)" ]] && return 0
        sleep 0.25
    done

    pids="$(codex_app_process_pids || true)"
    while IFS= read -r pid; do
        [[ -n "$pid" ]] || continue
        kill -KILL "$pid" 2>/dev/null || true
    done <<< "$pids"
}

quit_codex() {
    if pgrep -x Codex >/dev/null 2>&1; then
        log "Quitting Codex..."
        osascript -e 'quit app "Codex"' 2>/dev/null &
        local quit_pid=$!
        for _ in {1..20}; do
            pgrep -x Codex >/dev/null 2>&1 || break
            kill -0 "$quit_pid" 2>/dev/null || break
            sleep 0.1
        done
        kill "$quit_pid" 2>/dev/null || true
        sleep 2
        if pgrep -x Codex >/dev/null 2>&1; then
            pkill -TERM -x Codex 2>/dev/null || true
            sleep 2
        fi
        if pgrep -x Codex >/dev/null 2>&1; then
            pkill -KILL -x Codex 2>/dev/null || true
            sleep 1
        fi
    fi

    kill_codex_app_processes
}

# ── preflight ────────────────────────────────────────────────────────────────
[[ -d "$APP" ]]  || die "Codex.app not found at $APP"
[[ -f "$ASAR" ]] || die "app.asar not found"
command -v node  >/dev/null 2>&1 || die "node not found (install Node.js)"
command -v npx   >/dev/null 2>&1 || die "npx not found (install Node.js)"
command -v python3 >/dev/null 2>&1 || die "python3 not found"

patch_claude_installed_plugins() {
    local cache="$HOME/.codex/plugins/cache/claude-installed-local"
    [[ -d "$cache" ]] || return 0

    python3 - "$cache" <<'PYEOF'
import json
import pathlib
import sys

cache = pathlib.Path(sys.argv[1])

for name in ("ecc", "oh-my-claudecode"):
    for hooks in cache.glob(f"{name}/*/hooks/hooks.json"):
        try:
            data = json.loads(hooks.read_text())
        except Exception as exc:
            print(f"[warn]  Could not read {hooks}: {exc}")
            continue
        if data.get("hooks") == {}:
            continue
        data["hooks"] = {}
        hooks.write_text(json.dumps(data, indent=2) + "\n")
        print(f"[patch] Disabled Codex-incompatible hooks: {hooks}")

for mcp in cache.glob("oh-my-claudecode/*/.mcp.json"):
    try:
        data = json.loads(mcp.read_text())
    except Exception as exc:
        print(f"[warn]  Could not read {mcp}: {exc}")
        continue
    server = data.setdefault("mcpServers", {}).setdefault("t", {})
    target = str(mcp.parent / "bridge" / "mcp-server.cjs")
    changed = server.get("command") != "node" or server.get("args") != [target]
    server["command"] = "node"
    server["args"] = [target]
    if changed:
        mcp.write_text(json.dumps(data, indent=2) + "\n")
        print(f"[patch] Fixed OMC t MCP path: {mcp}")
PYEOF
}

patch_openai_bundled_computer_use_mcp() {
    python3 <<'PYEOF'
import json
import pathlib

home = pathlib.Path.home()
command = str(
    home
    / ".codex"
    / "computer-use"
    / "Codex Computer Use.app"
    / "Contents"
    / "SharedSupport"
    / "SkyComputerUseClient.app"
    / "Contents"
    / "MacOS"
    / "SkyComputerUseClient"
)
cwd = str(home / ".codex" / "computer-use")
server = {"command": command, "args": ["mcp"], "cwd": cwd, "enabled": True}

mcp_paths = [
    pathlib.Path("/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/.mcp.json"),
    home / ".codex/plugins/cache/openai-bundled/computer-use/1.0.809/.mcp.json",
    home / ".codex/.tmp/bundled-marketplaces/openai-bundled/plugins/computer-use/.mcp.json",
]

for path in mcp_paths:
    if not path.exists():
        continue
    try:
        data = json.loads(path.read_text())
    except Exception as exc:
        print(f"[warn]  Could not read {path}: {exc}")
        continue
    servers = data.setdefault("mcpServers", {})
    if servers.get("computer-use") == server:
        continue
    servers["computer-use"] = server
    path.write_text(json.dumps(data, indent=2) + "\n")
    print(f"[patch] Fixed Computer Use MCP metadata: {path}")

config = home / ".codex/config.toml"
if config.exists():
    lines = config.read_text().splitlines()
    stanza = [
        "[mcp_servers.computer-use]",
        f'command = "{command}"',
        'args = ["mcp"]',
        f'cwd = "{cwd}"',
        "enabled = true",
    ]
    start = next((i for i, line in enumerate(lines) if line.strip() == "[mcp_servers.computer-use]"), None)
    if start is None:
        insert = next((i for i, line in enumerate(lines) if line.startswith("[notice]")), len(lines))
        if insert > 0 and lines[insert - 1].strip() != "":
            stanza = ["", *stanza]
        if insert < len(lines):
            stanza = [*stanza, ""]
        new_lines = [*lines[:insert], *stanza, *lines[insert:]]
    else:
        end = start + 1
        while end < len(lines) and not (lines[end].startswith("[") and lines[end].strip().endswith("]")):
            end += 1
        replacement = [*stanza]
        if end < len(lines):
            replacement.append("")
        new_lines = [*lines[:start], *replacement, *lines[end:]]
    if new_lines != lines:
        config.write_text("\n".join(new_lines) + "\n")
        print(f"[patch] Fixed Computer Use MCP config: {config}")
PYEOF
}

app_bundle_patch_current() {
    local marker
    local required_markers=(
        'codex-patch:auth-account-fields'
        'codex-patch:auth-account-output'
        'codex-patch:plugins-loading'
        'codex-patch:plugins-page-loading'
        'codex-patch:plugins-catalog-all'
        'codex-patch:wham-desktop-auth'
        'codex-patch:desktop-feature-availability'
        'codex-patch:profile-visible-with-chatgpt'
        'codex-patch:profile-dropdown-visible'
        'codex-patch:usage-settings-visible'
        'codex-patch:locked-use-settings-visible'
        'codex-patch:locked-use-data-fallback'
        'codex-patch:appshot-availability'
        'codex-patch:computer-use-mcp-enabled'
    )

    for marker in "${required_markers[@]}"; do
        grep -a -q "$marker" "$ASAR" || return 1
    done

    local feature_flag
    local required_feature_flags=(
        'appshotsEnabled:!0'
        'browserPane:!0'
        'inAppBrowserUse:!0'
        'inAppBrowserUseAllowed:!0'
        'externalBrowserUse:!0'
        'externalBrowserUseAllowed:!0'
        'computerUse:!0'
        'computerUseNodeRepl:!0'
        'sites:!0'
        'control:!0'
        'multiBrowserTabs:!0'
        'recordAndReplay:!0'
    )

    for feature_flag in "${required_feature_flags[@]}"; do
        grep -a -q "$feature_flag" "$ASAR" || return 1
    done

    if grep -a -q '!==`chatgpt`}export' "$ASAR" &&
        ! grep -a -q 'codex-patch:plugin-auth-open' "$ASAR"; then
        return 1
    fi
    if grep -a -q '===`chatgpt`/\*codex-patch:profile-visible-with-chatgpt\*/' "$ASAR"; then
        return 1
    fi
    if grep -a -q 'a===`macOS`&&i.available&&n?(0,Q.jsx)(Ve,{})' "$ASAR"; then
        return 1
    fi
    if grep -a -q 'if(i.data?.enabled==null)return null' "$ASAR"; then
        return 1
    fi
    if grep -a -F -q 'command:`./Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient`,args:[`mcp`],cwd:`.`,enabled:!1' "$ASAR"; then
        return 1
    fi

    if npx @electron/fuses read --app "$APP" 2>/dev/null |
        grep 'EnableEmbeddedAsarIntegrityValidation' |
        grep -q 'Enabled'; then
        return 1
    fi

    codesign --verify --deep --strict "$APP" >/dev/null 2>&1 || return 1
}

patch_claude_installed_plugins
patch_openai_bundled_computer_use_mcp

if [[ -f "$SCRIPT_DIR/patch-codex-chrome-browser-use.mjs" ]]; then
    node "$SCRIPT_DIR/patch-codex-chrome-browser-use.mjs"
fi

if app_bundle_patch_current; then
    log "Codex.app bundle patches already current – skipping app.asar repack and app re-sign."
    log "Done. Launch Codex – Plugins and Codex Mobile setup requests should now use the local ChatGPT login."
    exit 0
fi

# kill running Codex so we can write to the bundle
quit_codex

# ── extract ──────────────────────────────────────────────────────────────────
log "Extracting app.asar → $WORK"
rm -rf "$WORK"
npx --yes @electron/asar extract "$ASAR" "$WORK" 2>/dev/null

# ── patch 0: plugin auth gate – decouple plugins from chat provider auth ─────
node "$SCRIPT_DIR/patch-codex-plugins.mjs" "$WORK"

# ── patch 1: sidebar – replace disabled Plugins item with enabled one ────────
SIDEBAR=$(grep -rl 'defaultMessage:`Please sign in with ChatGPT to use plugins`' "$WORK/webview/assets/"*.js 2>/dev/null | head -1 || true)
if [[ -z "$SIDEBAR" ]]; then
    SIDEBAR=$(grep -rl 'sidebarElectron.pluginsDisabledTooltip' "$WORK/webview/assets/"*.js 2>/dev/null | xargs grep -l 'defaultMessage:' 2>/dev/null | head -1 || true)
fi
if [[ -z "$SIDEBAR" ]]; then
    if grep -rl 'pathname.startsWith(`/plugins`)' "$WORK/webview/assets/"*.js >/dev/null 2>&1; then
        SIDEBAR_REPAIR=$(grep -rl 'pathname.startsWith(`/plugins`)' "$WORK/webview/assets/"*.js 2>/dev/null | xargs grep -l 'sidebarElectron.pluginsRouteNavLink' 2>/dev/null | head -1 || true)
        if [[ -n "$SIDEBAR_REPAIR" ]]; then
            python3 - "$SIDEBAR_REPAIR" <<'PYEOF'
import sys

path = sys.argv[1]
data = open(path).read()
repaired = data

def remove_extra_plugins_nav(source):
    if 'sidebarElectron.skillsAppsRouteNavLink' not in source:
        return source, False
    marker = 'pathname.startsWith(`/plugins`)'
    idx = source.find(marker)
    if idx == -1:
        return source, False
    start = source.rfind(',(0,', 0, idx)
    if start == -1:
        return source, False

    quote = None
    escape = False
    paren = brace = bracket = 0
    entered = False
    for pos in range(start + 1, len(source)):
        ch = source[pos]
        if quote:
            if escape:
                escape = False
                continue
            if ch == '\\':
                escape = True
                continue
            if ch == quote:
                quote = None
            continue
        if ch in ('"', "'", '`'):
            quote = ch
            continue
        if ch == '(':
            paren += 1
            entered = True
        elif ch == ')':
            paren -= 1
        elif ch == '{':
            brace += 1
            entered = True
        elif ch == '}':
            brace -= 1
        elif ch == '[':
            bracket += 1
            entered = True
        elif ch == ']':
            bracket -= 1
        if entered and paren == 0 and brace == 0 and bracket == 0:
            if pos + 1 < len(source) and source[pos + 1] == '(':
                continue
            candidate = source[start:pos + 1]
            if 'sidebarElectron.pluginsRouteNavLink' not in candidate:
                return source, False
            return source[:start] + source[pos + 1:], True
    return source, False

repaired, removed = remove_extra_plugins_nav(repaired)
if removed:
    open(path, 'w').write(repaired)
    print('[patch] Sidebar duplicate Plugins item removed – using native Skills/Apps entry')
    raise SystemExit

repaired = repaired.replace(
    'description:`Nav link that opens the plugins page`})}}),',
    'description:`Nav link that opens the plugins page`})}),',
)
if repaired != data:
    open(path, 'w').write(repaired)
    print('[patch] Sidebar Plugins item syntax repaired')
else:
    print('[patch] Sidebar Plugins item already patched – skipping')
PYEOF
        else
            log "Sidebar Plugins item already patched – skipping"
        fi
    elif grep -rl 'sidebarElectron.skillsAppsRouteNavLink' "$WORK/webview/assets/"*.js >/dev/null 2>&1; then
        log "Sidebar native Skills/Apps entry already handles Plugins – skipping"
    else
        die "Cannot find sidebar JS file"
    fi
else

python3 - "$SIDEBAR" <<'PYEOF'
import sys, re

path = sys.argv[1]
data = open(path).read()

if 'metadata:{item:`plugins`}' in data and 'pathname.startsWith(`/plugins`)' in data:
    print('[patch] Sidebar Plugins item already patched – skipping')
    raise SystemExit

def fail(msg):
    print(f'[warn]  {msg} – may need manual update')
    raise SystemExit

idx = data.find('sidebarElectron.pluginsDisabledTooltip')
if idx == -1:
    fail('Sidebar disabled plugins tooltip pattern not found')

func_start = data.rfind('function ', 0, idx)
func_end = data.find('function ', idx)
if func_start == -1:
    func_start = max(0, idx - 12000)
if func_end == -1:
    func_end = min(len(data), idx + 12000)
scope = data[func_start:func_end]
local_idx = idx - func_start

# Locate the complete conditional expression:
#   <gate>?(0,<jsx>.jsx)(<Tooltip>,{...pluginsDisabledTooltip...disabled:!0...}):null
start = scope.rfind('?', 0, local_idx)
while start > 0 and scope[start - 1] not in ',[({':
    start -= 1
end = scope.find('):null', local_idx)
if start == -1 or end == -1:
    fail('Sidebar disabled plugins conditional not found')
end += len('):null')
old = scope[start:end]

m = re.search(
    r'\(0,([A-Za-z_$][\w$]*)\.jsx\)\(([^,]+),\{tooltipContent:.*?children:\(0,\1\.jsx\)\(`div`,\{children:\(0,\1\.jsx\)\(([^,]+),\{icon:([^,}]+),onClick:\(\)=>\{\},disabled:!0,label:',
    old,
)
if not m:
    fail('Sidebar disabled plugins component shape not recognized')
jsx_ns, _tooltip_component, nav_component, icon_expr = m.groups()

label_match = re.search(r'label:(\(0,%s\.jsx\)\([^)]*?sidebarElectron\.pluginsRouteNavLink.*?\)\})' % re.escape(jsx_ns), old)
if not label_match:
    fail('Sidebar plugins label expression not found')
label_expr = label_match.group(1).replace(
    'description:`Disabled nav link shown to API-key users under Skills in the sidebar`',
    'description:`Nav link that opens the plugins page`',
)
if label_expr.endswith('}'):
    label_expr = label_expr[:-1]

before = scope[:start]
nav_vars = None
for match in re.finditer(
    r'\(0,%s\.jsx\)\(%s,\{icon:[^{}]*?,onClick:\(\)=>\{[^{}]*?\(([^,()]+),([^(){}]+)\)\},isActive:([^,{}]+)\.pathname\.startsWith\(`/skills`\)' %
    (re.escape(jsx_ns), re.escape(nav_component)),
    before,
):
    nav_vars = match.groups()

if nav_vars:
    _state_arg, navigate_var, location_var = [x.strip() for x in nav_vars]
else:
    # Fall back to the common hook order in the sidebar component:
    #   n=..., a=<navigate hook>(), o=<location hook>()
    hook_match = re.search(r'let\s+[^;]*?=U\([^)]*\),[^;]*?,([^=,]+)=Jr\(\),([^=,]+)=ni\(\)', scope)
    if not hook_match:
        fail('Sidebar navigation variables not found')
    navigate_var, location_var = [x.strip() for x in hook_match.groups()]

new = (
    f'(0,{jsx_ns}.jsx)({nav_component},{{icon:{icon_expr},'
    f'onClick:()=>{{{navigate_var}(`/plugins`)}},'
    f'isActive:{location_var}.pathname.startsWith(`/plugins`),'
    f'label:{label_expr}}})'
)

patched_scope = scope[:start] + new + scope[end:]
data = data[:func_start] + patched_scope + data[func_end:]

# If the native Skills/Apps entry is also present, the replacement just created a
# duplicate "Plugins" item. Remove the one we just added and rely on the native entry.
def remove_extra_plugins_nav(source):
    if 'sidebarElectron.skillsAppsRouteNavLink' not in source:
        return source, False
    marker = 'pathname.startsWith(`/plugins`)'
    idx = source.find(marker)
    if idx == -1:
        return source, False
    start = source.rfind(',(0,', 0, idx)
    if start == -1:
        return source, False
    quote = None
    escape = False
    paren = brace = bracket = 0
    entered = False
    for pos in range(start + 1, len(source)):
        ch = source[pos]
        if quote:
            if escape:
                escape = False
                continue
            if ch == '\\':
                escape = True
                continue
            if ch == quote:
                quote = None
            continue
        if ch in ('"', "'", '`'):
            quote = ch
            continue
        if ch == '(':
            paren += 1
            entered = True
        elif ch == ')':
            paren -= 1
        elif ch == '{':
            brace += 1
            entered = True
        elif ch == '}':
            brace -= 1
        elif ch == '[':
            bracket += 1
            entered = True
        elif ch == ']':
            bracket -= 1
        if entered and paren == 0 and brace == 0 and bracket == 0:
            if pos + 1 < len(source) and source[pos + 1] == '(':
                continue
            candidate = source[start:pos + 1]
            if 'sidebarElectron.pluginsRouteNavLink' not in candidate:
                return source, False
            return source[:start] + source[pos + 1:], True
    return source, False

data, removed = remove_extra_plugins_nav(data)
if removed:
    open(path, 'w').write(data)
    print('[patch] Sidebar: native Skills/Apps entry already shows Plugins – removed duplicate')
else:
    open(path, 'w').write(data)
    print('[patch] Sidebar Plugins item replaced with enabled version')
PYEOF
fi

# ── patch 2: skills-page – allow API-key auth to show plugins marketplace ────
SKILLS_PAGE=$(grep -rl 'defaultMessage:`Sign in with ChatGPT to use plugins`' "$WORK/webview/assets/"*.js 2>/dev/null | head -1 || true)
if [[ -z "$SKILLS_PAGE" ]]; then
    SKILLS_PAGE=$(grep -rl 'skills.pluginsAuthBlockedToast.title' "$WORK/webview/assets/"*.js 2>/dev/null | xargs grep -l 'defaultMessage:' 2>/dev/null | head -1 || true)
fi
if [[ -z "$SKILLS_PAGE" ]]; then
    SKILLS_PAGE=$(grep -rl 'gradient-Dio5-IUz' "$WORK/webview/assets/"*.js 2>/dev/null | head -1 || true)
fi
if [[ -z "$SKILLS_PAGE" ]]; then
    log "[warn] skills-page auth gate not found – skipping skills-page patch"
fi

if [[ -n "$SKILLS_PAGE" ]]; then
python3 - "$SKILLS_PAGE" <<'PYEOF'
import sys, re

path = sys.argv[1]
data = open(path).read()

# Pattern: the auth-gated branch that returns the plugins marketplace.
# Old bundles used `s&&!m){...Ce...}`; newer bundles still keep the same
# toast key but minifier names and JSX aliases change.
toast_idx = data.find('skills.pluginsAuthBlockedToast.title')
if toast_idx == -1:
    print('[warn]  skills-page auth toast pattern not found – may need manual update')
    raise SystemExit

window_start = max(0, toast_idx - 4000)
window_end = min(len(data), toast_idx + 4000)
window = data[window_start:window_end]

already = re.search(
    r'(?:if\(|,)([A-Za-z_$][\w$]*)\)\{let\s+[A-Za-z_$][\w$]*;return\s+[^{}]*Symbol\.for\(`react\.memo_cache_sentinel`\)',
    window,
)
if already:
    print('[patch] skills-page already patched to allow plugins marketplace – skipping')
    raise SystemExit

patched = False
patterns = [
    # if(s&&!m){let t;return e[8]===Symbol.for(...)?(t=(0,O.jsx)(be,{}),...):...}
    (r'if\((?P<availability>[A-Za-z_$][\w$]*)&&!([A-Za-z_$][\w$]*)\)\{(?P<body>let\s+[A-Za-z_$][\w$]*;return\s+[^{}]*Symbol\.for\(`react\.memo_cache_sentinel`\))', r'if(\g<availability>){\g<body>'),
    # Minified branch without explicit `if`: s&&!m){let t;return ...}
    (r'(?P<availability>[A-Za-z_$][\w$]*)&&!([A-Za-z_$][\w$]*)\)\{(?P<body>let\s+[A-Za-z_$][\w$]*;return\s+[^{}]*Symbol\.for\(`react\.memo_cache_sentinel`\))', r'\g<availability>){\g<body>'),
    # Very old manual patch variants.
    (r'!1\)\{(?P<body>let\s+[A-Za-z_$][\w$]*;return\s+[^{}]*Symbol\.for\(`react\.memo_cache_sentinel`\))', r'!0){\g<body>'),
]

for pattern, replacement in patterns:
    new_window, count = re.subn(pattern, replacement, window, count=1)
    if count:
        data = data[:window_start] + new_window + data[window_end:]
        open(path, 'w').write(data)
        print('[patch] skills-page patched: API-key auth can show plugins marketplace')
        patched = True
        break

if not patched:
    print('[warn]  skills-page pattern not found – may need manual update')
PYEOF
fi

# ── patch 3: plugins hook – don't block list rendering on availability probes ─
PLUGINS_HOOK=$(grep -rl 'cwdPluginsResponse' "$WORK/webview/assets/"*.js 2>/dev/null | head -1 || true)
if [[ -z "$PLUGINS_HOOK" ]]; then
    PLUGINS_HOOK=$(grep -rl 'availablePlugins' "$WORK/webview/assets/"*.js 2>/dev/null | xargs grep -l 'list-plugins' 2>/dev/null | head -1 || true)
fi
[[ -n "$PLUGINS_HOOK" ]] || die "Cannot find plugins hook JS file"

python3 - "$PLUGINS_HOOK" <<'PYEOF'
import sys, re

path = sys.argv[1]
data = open(path).read()

if '/*codex-patch:plugins-loading*/' in data:
    print('[patch] plugins hook loading gate already patched – skipping')
    raise SystemExit

manual = re.search(
    r'([A-Za-z_$][\w$]*)=([A-Za-z_$][\w$]*)&&([A-Za-z_$][\w$]*)\.isLoading\|\|([A-Za-z_$][\w$]*)\.isLoading\|\|([A-Za-z_$][\w$]*)\.isLoading\|\|([A-Za-z_$][\w$]*)\.isLoading\|\|([A-Za-z_$][\w$]*)\.isLoading,'
    r'([A-Za-z_$][\w$]*)=\2&&\3\.isFetching\|\|\4\.isFetching\|\|\7\.isFetching',
    data,
)

if not manual:
    print('[warn]  plugins hook loading gate pattern not found – may need manual update')
    raise SystemExit

loading_var, roots_flag, roots_query, plugins_query, avail_a, avail_b, avail_c, fetch_var = manual.groups()
old = manual.group(0)
new = (
    f'{loading_var}=/*codex-patch:plugins-loading*/{roots_flag}&&{roots_query}.isLoading||{plugins_query}.isLoading,'
    f'{fetch_var}={roots_flag}&&{roots_query}.isFetching||{plugins_query}.isFetching'
)
data = data[:manual.start()] + new + data[manual.end():]
open(path, 'w').write(data)
print('[patch] plugins hook patched: availability probes no longer block list loading')
PYEOF

# ── patch 4: plugins page – don't let availability init mask list forever ────
PLUGINS_PAGE=$(grep -rl 'plugins.page.loading' "$WORK/webview/assets/"*.js 2>/dev/null | xargs grep -l 'ge===`loading`' 2>/dev/null | head -1 || true)
if [[ -z "$PLUGINS_PAGE" ]]; then
    PLUGINS_PAGE=$(grep -rl 'availablePlugins' "$WORK/webview/assets/"*.js 2>/dev/null | xargs grep -l 'plugins.page.loading' 2>/dev/null | head -1 || true)
fi
[[ -n "$PLUGINS_PAGE" ]] || die "Cannot find plugins page JS file"

python3 - "$PLUGINS_PAGE" <<'PYEOF'
import sys, re

path = sys.argv[1]
data = open(path).read()

if '/*codex-patch:plugins-page-loading*/' in data:
    updated, count = re.subn(
        r'([A-Za-z_$][\w$]*)=/\*codex-patch:plugins-page-loading\*/([A-Za-z_$][\w$]*)(?:\|\|[A-Za-z_$][\w$]*&&[A-Za-z_$][\w$]*)?,',
        r'\1=/*codex-patch:plugins-page-loading*/\2,',
        data,
        count=1,
    )
    if count and updated != data:
        open(path, 'w').write(updated)
        print('[patch] plugins page loading gate tightened – imported connector probes no longer mask list')
    else:
        print('[patch] plugins page loading gate already patched – skipping')
    raise SystemExit

manual = re.search(
    r'([A-Za-z_$][\w$]*)=([A-Za-z_$][\w$]*)\|\|([A-Za-z_$][\w$]*)===`loading`\|\|([A-Za-z_$][\w$]*)&&([A-Za-z_$][\w$]*),'
    r'([A-Za-z_$][\w$]*)=',
    data,
)

if not manual:
    print('[warn]  plugins page loading gate pattern not found – may need manual update')
    raise SystemExit

loading_var, query_loading, page_loading_state, imported_loading, imported_enabled, next_var = manual.groups()
new = (
    f'{loading_var}=/*codex-patch:plugins-page-loading*/{query_loading},'
    f'{next_var}='
)
data = data[:manual.start()] + new + data[manual.end():]
open(path, 'w').write(data)
print('[patch] plugins page patched: only plugin query loading masks plugin list')
PYEOF

# ── patch 5: suppress EPIPE uncaught exception dialog ───────────────────────
BOOTSTRAP="$WORK/.vite/build/bootstrap.js"
if [[ -f "$BOOTSTRAP" ]]; then
    if ! grep -q 'EPIPE' "$BOOTSTRAP"; then
        log "Patching bootstrap.js to suppress EPIPE errors"
        sed -i '' "s/^const e=require/process.on(\`uncaughtException\`,e=>{if(e.code===\`EPIPE\`)return;throw e});const e=require/" "$BOOTSTRAP"
    else
        log "EPIPE suppression already patched – skipping"
    fi
else
    log "[warn] bootstrap.js not found – skipping EPIPE patch"
fi

# ── validation: fail before repacking if a patched module is invalid ─────────
CORE_PATCHED_MODULES=$(grep -rlE 'codex-patch:plugin-auth-open|codex-patch:plugin-account-fallback|codex-patch:auth-account-fields|codex-patch:usage-settings-visible|codex-patch:local-usage-settings-visible|codex-patch:local-desktop-settings-visible|codex-patch:locked-use-settings-visible|codex-patch:locked-use-data-fallback|codex-patch:appshot-availability|codex-patch:plugins-catalog-all' "$WORK/webview/assets/"*.js 2>/dev/null || true)
if [[ -n "$CORE_PATCHED_MODULES" ]]; then
    log "Validating patched auth/provider modules syntax"
    while IFS= read -r module; do
        [[ -n "$module" ]] || continue
        node --input-type=module --check < "$module" >/dev/null
    done <<< "$CORE_PATCHED_MODULES"
fi

MAIN_PATCHED_MODULE=$(grep -rlE 'codex-patch:wham-desktop-auth|codex-patch:desktop-feature-availability|codex-patch:desktop-auth-token-fallback|codex-patch:computer-use-mcp-enabled' "$WORK/.vite/build/"main-*.js 2>/dev/null | head -1 || true)
if [[ -n "$MAIN_PATCHED_MODULE" ]]; then
    log "Validating patched main module syntax"
    node --check "$MAIN_PATCHED_MODULE" >/dev/null
fi

APP_MAIN=$(grep -rl 'sidebarElectron.pluginsRouteNavLink' "$WORK/webview/assets/"*.js 2>/dev/null | xargs grep -l 'pathname.startsWith(`/plugins`)' 2>/dev/null | head -1 || true)
if [[ -n "$APP_MAIN" ]]; then
    log "Validating patched app-main module syntax"
    node --input-type=module --check < "$APP_MAIN" >/dev/null
fi
if [[ -n "${PLUGINS_HOOK:-}" ]]; then
    log "Validating patched plugins hook module syntax"
    node --input-type=module --check < "$PLUGINS_HOOK" >/dev/null
fi
if [[ -n "${PLUGINS_PAGE:-}" ]]; then
    log "Validating patched plugins page module syntax"
    node --input-type=module --check < "$PLUGINS_PAGE" >/dev/null
fi

# ── repack ───────────────────────────────────────────────────────────────────
log "Repacking app.asar"
npx @electron/asar pack "$WORK" "$ASAR" 2>/dev/null

# ── update integrity hash in Info.plist ──────────────────────────────────────
NEW_HASH=$(shasum -a 256 "$ASAR" | awk '{print $1}')
log "Updating Info.plist integrity hash → $NEW_HASH"
/usr/libexec/PlistBuddy -c "Set :ElectronAsarIntegrity:Resources/app.asar:hash $NEW_HASH" "$PLIST"

# ── disable Electron asar integrity fuse ─────────────────────────────────────
FUSE_STATE=$(npx @electron/fuses read --app "$APP" 2>/dev/null | grep 'EnableEmbeddedAsarIntegrityValidation' || true)
if echo "$FUSE_STATE" | grep -q 'Enabled'; then
    log "Disabling EnableEmbeddedAsarIntegrityValidation fuse"
    npx @electron/fuses write --app "$APP" EnableEmbeddedAsarIntegrityValidation=off 2>/dev/null
else
    log "Integrity fuse already disabled – skipping"
fi

# ── re-sign with a stable local identity when available ──────────────────────
# Ad-hoc signatures change identity whenever the bundle changes, which can make
# macOS Keychain ask again for access. A persistent local signing identity keeps
# the designated requirement stable across repacks.
if [[ -n "$SIGN_IDENTITY" ]] && security find-identity -v -p codesigning | grep -F "\"$SIGN_IDENTITY\"" >/dev/null 2>&1; then
    log "Re-signing app with local identity: $SIGN_IDENTITY"
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP" 2>/dev/null
else
    log "Re-signing app (ad-hoc; set CODEX_PATCH_SIGN_IDENTITY to reduce repeated Keychain prompts)"
    codesign --force --deep --sign - "$APP" 2>/dev/null
fi

# ── cleanup ──────────────────────────────────────────────────────────────────
rm -rf "$WORK"

log "Done. Launch Codex – Plugins and Codex Mobile setup requests should now use the local ChatGPT login."
