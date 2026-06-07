#!/usr/bin/env bash
set -euo pipefail

zshrc="${HOME}/.zshrc"
backup="${zshrc}.bak-$(date +%Y%m%d-%H%M%S)"

if [[ ! -f "$zshrc" ]]; then
  echo "[ERROR] 未找到 $zshrc"
  exit 1
fi

cp "$zshrc" "$backup"
echo "[OK] 已备份: $backup"

python3 - "$zshrc" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
pattern = re.compile(
    r"\n# ============ Universal Modern Shell Configuration ============\n"
    r".*?"
    r"# ============ End Universal Configuration ============\n?",
    re.S,
)
new_text, count = pattern.subn("\n", text)
if count == 0:
    print("[INFO] 未找到 Universal Modern Shell Configuration 块，无需修改")
else:
    path.write_text(new_text)
    print(f"[OK] 已从 {path} 移除 Universal Modern Shell Configuration 块")
PY

echo "[OK] 修复完成。请关闭当前终端窗口，重新打开一个新终端。"
echo "     如果还在当前窗口测试，可执行: exec zsh -l"
