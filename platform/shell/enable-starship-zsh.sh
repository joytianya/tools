#!/usr/bin/env bash
set -euo pipefail

zshrc="${HOME}/.zshrc"
backup="${zshrc}.bak-$(date +%Y%m%d-%H%M%S)"
start="# >>> starship-zsh >>>"
end="# <<< starship-zsh <<<"

if [[ ! -f "$zshrc" ]]; then
  echo "[ERROR] 未找到 $zshrc"
  exit 1
fi

if ! command -v starship >/dev/null 2>&1; then
  echo "[ERROR] 未找到 starship，请先安装: brew install starship"
  exit 1
fi

cp "$zshrc" "$backup"
echo "[OK] 已备份: $backup"

python3 - "$zshrc" "$start" "$end" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
start = sys.argv[2]
end = sys.argv[3]
text = path.read_text()

text = re.sub(
    rf"\n?{re.escape(start)}\n.*?\n{re.escape(end)}\n?",
    "\n",
    text,
    flags=re.S,
)

block = f"""
{start}
# Starship prompt. Keep this near the end so it overrides Oh My Zsh themes.
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi
{end}
"""

path.write_text(text.rstrip() + "\n" + block)
print("[OK] 已在 .zshrc 末尾启用 Starship")
PY

echo "[OK] 执行 exec zsh -l 或重新打开终端生效"
