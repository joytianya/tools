#!/usr/bin/env bash
set -euo pipefail

config="${HOME}/.config/starship.toml"
backup="${config}.bak-$(date +%Y%m%d-%H%M%S)"

if [[ ! -f "$config" ]]; then
  echo "[ERROR] 未找到 $config"
  exit 1
fi

cp "$config" "$backup"
echo "[OK] 已备份: $backup"

python3 - "$config" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
new_format = '''format = """
[╭─](bold blue)$os$username[@](bold blue)$hostname[ in ](bold blue)$directory$git_branch$git_status$nodejs$python$rust$golang$java$docker_context$package$cmd_duration
[╰─](bold blue)$character"""'''

new_text, count = re.subn(r'^format\s*=\s*""".*?"""', new_format, text, count=1, flags=re.S | re.M)
if count == 0:
    print("[ERROR] 没找到 format 块")
    sys.exit(1)

path.write_text(new_text)
print("[OK] 已改为两行提示符 format")
PY

echo "[OK] 执行 exec zsh -l 或重新打开终端生效"
