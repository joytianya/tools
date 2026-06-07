# Codex Mobile Remote Tools

This document records the local scripts used to keep Codex Desktop, Codex mobile remote control, and SSH remote servers working together.

## Current Model

The phone does not SSH directly into remote servers.

Flow:

1. ChatGPT mobile shows remote environments registered by Codex.
2. Mac Codex Desktop stores SSH remote project entries and syncs them to the app config.
3. Each remote server runs a Codex `app-server daemon`.
4. The daemon connects back to ChatGPT remote-control service.
5. Model calls are configured to use the `gaccode` API provider through each machine's Codex config.

Current known remote hosts are listed in:

```bash
/Users/matrix/projects/dev/tools/codex-remote/codex-remote-hosts.txt
```

Current hosts:

```text
bwg-server-zxw
ali-server-zxw
```

## Add A New Remote Server

Use this when a new SSH server should appear in ChatGPT mobile/Codex remote control.

Prerequisites:

- The SSH alias already exists in `~/.ssh/config`.
- SSH key login works without a password prompt.
- Codex CLI is installed and configured on the remote server.
- The remote server can reach ChatGPT/gaccode directly or through proxy/tunnel.

Check SSH first:

```bash
ssh -o BatchMode=yes new-server-zxw 'hostname'
```

Add the server with its home directory only:

```bash
/Users/matrix/projects/dev/tools/codex-remote/codex-add-remote-server.sh new-server-zxw
```

Add the server with extra project paths:

```bash
/Users/matrix/projects/dev/tools/codex-remote/codex-add-remote-server.sh new-server-zxw \
  /home/zxw/project1 \
  /home/zxw/project2
```

Optional display name:

```bash
/Users/matrix/projects/dev/tools/codex-remote/codex-add-remote-server.sh --name "new-server-zxw" new-server-zxw
```

What this script does:

- Verifies the SSH alias.
- Copies `codex-remote-start-daemon.sh` to the remote as `~/start-codex-daemon.sh`.
- Restarts the remote Codex daemon.
- Adds the alias to `codex-remote-hosts.txt`.
- Writes Codex Desktop remote project state.
- Runs `codex-sync-remote-ssh-projects.mjs --apply`.
- Kicks the watchdog if it is loaded.

You do not have to manually add the server in Codex App first. If Codex App already has it, the script will merge with the existing state.

## Restart Daemons

Restart Mac, `bwg-server-zxw`, `ali-server-zxw`, and any hosts listed in `codex-remote-hosts.txt`:

```bash
/Users/matrix/projects/dev/tools/codex-remote/codex-restart-daemons.sh
```

Restart only remote hosts:

```bash
/Users/matrix/projects/dev/tools/codex-remote/codex-restart-daemons.sh --remote-only
```

Restart one remote host:

```bash
/Users/matrix/projects/dev/tools/codex-remote/codex-restart-daemons.sh --remote-only --hosts "bwg-server-zxw"
```

Restart only the Mac daemon and relaunch Codex Desktop:

```bash
/Users/matrix/projects/dev/tools/codex-remote/codex-restart-daemons.sh --local-only --relaunch-desktop
```

The default host list comes from:

```bash
/Users/matrix/projects/dev/tools/codex-remote/codex-remote-hosts.txt
```

## Remote Server Helper

Each remote server should have:

```bash
~/start-codex-daemon.sh
```

It is copied from:

```bash
/Users/matrix/projects/dev/tools/codex-remote/codex-remote-start-daemon.sh
```

Run on the remote server:

```bash
~/start-codex-daemon.sh
~/start-codex-daemon.sh restart
~/start-codex-daemon.sh status
~/start-codex-daemon.sh stop
```

The helper loads:

- `~/.codex/gaccode.env`, if present.
- `~/proxy_config.sh on`, if present.

This matters for hosts like `ali-server-zxw`, which may need the Mac proxy tunnel.

## Sync Remote Projects To Codex App

Sync saved SSH remote projects into Codex App config:

```bash
node /Users/matrix/projects/dev/tools/codex-remote/codex-sync-remote-ssh-projects.mjs --apply
```

Dry run:

```bash
node /Users/matrix/projects/dev/tools/codex-remote/codex-sync-remote-ssh-projects.mjs --dry-run
```

Outputs:

```bash
/Users/matrix/.codex/codex-app/config.json
```

The `--apply` option opens:

```text
codex://codex-app/apply-config
```

Use this when the phone list is missing SSH project entries even though the Mac config looks correct.

## Watchdog

The watchdog checks Mac and remote Codex daemons every 5 minutes. For remote hosts,
it now checks both the local daemon/TCP connection and the ChatGPT cloud `online`
state; if a host is locally connected but cloud-offline, it restarts that host's
daemon.

Script:

```bash
/Users/matrix/projects/dev/tools/codex-remote/codex-daemon-watchdog.sh
```

LaunchAgent:

```bash
/Users/matrix/Library/LaunchAgents/com.matrix.codex-daemon-watchdog.plist
```

Check launchd status:

```bash
launchctl print gui/$(id -u)/com.matrix.codex-daemon-watchdog
```

Run once manually:

```bash
/Users/matrix/projects/dev/tools/codex-remote/codex-daemon-watchdog.sh
```

Watch logs:

```bash
tail -f /Users/matrix/Library/Logs/codex-daemon-watchdog.log
tail -f /Users/matrix/Library/Logs/codex-daemon-watchdog.err
```

The watchdog reads the same host list:

```bash
/Users/matrix/projects/dev/tools/codex-remote/codex-remote-hosts.txt
```

## Update Codex Desktop And Plugins

Manual update/fix:

```bash
/Users/matrix/projects/dev/tools/codex-after-update-fix.sh --kill-stale-chrome-kernels
```

Common options:

```bash
/Users/matrix/projects/dev/tools/codex-after-update-fix.sh --skip-update
/Users/matrix/projects/dev/tools/codex-after-update-fix.sh --force-update
/Users/matrix/projects/dev/tools/codex-after-update-fix.sh --diagnose-only
/Users/matrix/projects/dev/tools/codex-after-update-fix.sh --no-launch
```

What it does:

- Checks the official Codex Desktop Sparkle appcast.
- Installs the latest Codex.app if needed.
- Reapplies local plugin patches.
- Optionally kills stale Chrome-plugin kernel processes.
- Runs Chrome plugin diagnostics.
- Launches Codex.app by default.

By default the script uses the stable local code-signing identity
`Codex Local Patch Signing` when it exists. Use `--ad-hoc-sign` only as a
fallback when the local signing identity is unavailable or broken.

## Daily Auto Update

LaunchAgent:

```bash
/Users/matrix/Library/LaunchAgents/com.matrix.update-ai-tools.plist
```

It runs every day at 03:00:

```bash
/opt/homebrew/bin/update-ai-tools.sh
```

Current steps:

- `npm update -g @anthropic-ai/claude-code`
- `codex update`
- `codex-after-update-fix.sh --kill-stale-chrome-kernels`
- `codex-restart-daemons.sh`
- Logs current versions

Watch logs:

```bash
tail -f /Users/matrix/Library/Logs/update-ai-tools.log
```

Run manually:

```bash
/opt/homebrew/bin/update-ai-tools.sh
```

## SSH Proxy Tunnel

Existing LaunchAgent:

```bash
/Users/matrix/Library/LaunchAgents/com.matrix.ssh-tunnel.plist
```

Script:

```bash
/Users/matrix/projects/dev/tools/net/ssh_tunnel.sh
```

Common commands:

```bash
/Users/matrix/projects/dev/tools/net/ssh_tunnel.sh status
/Users/matrix/projects/dev/tools/net/ssh_tunnel.sh restart
```

This is separate from the Codex daemon watchdog. The tunnel keeps proxy forwarding alive for hosts that need it, such as `ali-server-zxw`.

## Chrome Plugin Recovery

Manual plugin patch entry:

```bash
/Users/matrix/projects/dev/tools/fix-codex-plugins.sh
```

Lower-level patch folder:

```bash
/Users/matrix/projects/dev/tools/codex-patch/
```

Use the higher-level update script first:

```bash
/Users/matrix/projects/dev/tools/codex-after-update-fix.sh --skip-update --kill-stale-chrome-kernels
```

## Quick Troubleshooting

Check Mac daemon:

```bash
codex app-server daemon version
```

Check remote daemon:

```bash
ssh -o BatchMode=yes -o ClearAllForwardings=yes bwg-server-zxw '~/start-codex-daemon.sh status'
```

Check remote Codex TCP connection:

```bash
ssh -o BatchMode=yes -o ClearAllForwardings=yes bwg-server-zxw "ss -tnp 2>/dev/null | grep codex || true"
```

Expected healthy signs:

- Mac daemon status contains `"status":"running"`.
- Remote daemon status contains `"status":"running"`.
- `bwg-server-zxw` usually shows a `codex -> :443` connection.
- `ali-server-zxw` may show `codex -> 127.0.0.1:7890` because it uses proxy forwarding.

If the phone list is missing projects:

```bash
node /Users/matrix/projects/dev/tools/codex-remote/codex-sync-remote-ssh-projects.mjs --apply
```

Then refresh or reopen the phone's ChatGPT/Codex remote list after a short delay.

## Files Changed By These Tools

Local:

```bash
/Users/matrix/.codex/.codex-global-state.json
/Users/matrix/.codex/codex-app/config.json
/Users/matrix/projects/dev/tools/codex-remote/codex-remote-hosts.txt
```

Remote:

```bash
~/start-codex-daemon.sh
~/.codex/state_5.sqlite
~/.codex/config.toml
~/.codex/gaccode.env
```

LaunchAgents:

```bash
/Users/matrix/Library/LaunchAgents/com.matrix.codex-daemon-watchdog.plist
/Users/matrix/Library/LaunchAgents/com.matrix.update-ai-tools.plist
/Users/matrix/Library/LaunchAgents/com.matrix.ssh-tunnel.plist
```
