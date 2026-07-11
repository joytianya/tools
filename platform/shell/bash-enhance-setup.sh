#!/usr/bin/env bash
#
# bash-enhance-setup.sh — 一键安装 bash 补全增强（ble.sh + bash-completion + fzf）
#
# 用法:
#   bash bash-enhance-setup.sh              # 交互式选择，直接回车默认全装
#   bash bash-enhance-setup.sh --all        # 全部安装
#   bash bash-enhance-setup.sh --suggest    # 只装 ble.sh (自动建议+语法高亮)
#   bash bash-enhance-setup.sh --complete   # 只装 bash-completion
#   bash bash-enhance-setup.sh --fzf        # 只装 fzf
#
# 支持 macOS (brew) 和 Linux (手动克隆/编译)
#

set -euo pipefail

# ── 颜色 ──────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── 检测环境 ──────────────────────────────────────────
OS="$(uname -s)"
BASHRC="${BASHRC:-$HOME/.bashrc}"
PLUG_DIR="$HOME/.bash-plugins"

has_cmd() { command -v "$1" &>/dev/null; }

if [[ "$OS" == "Darwin" ]]; then
    PKG_MGR="brew"
    HAS_BREW=true
else
    if has_cmd brew; then
        PKG_MGR="brew"
        HAS_BREW=true
    else
        PKG_MGR="manual"
        HAS_BREW=false
    fi
fi

# ── 解析参数 ──────────────────────────────────────────
INSTALL_SUGGEST=false
INSTALL_COMPLETE=false
INSTALL_FZF=false
INTERACTIVE=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)       INSTALL_SUGGEST=true; INSTALL_COMPLETE=true; INSTALL_FZF=true; INTERACTIVE=false ;;
        --suggest)   INSTALL_SUGGEST=true; INTERACTIVE=false ;;
        --complete)  INSTALL_COMPLETE=true; INTERACTIVE=false ;;
        --fzf)       INSTALL_FZF=true; INTERACTIVE=false ;;
        -h|--help)
            head -12 "$0" | tail -10; exit 0 ;;
        *) die "未知参数: $1" ;;
    esac
    shift
done

# ── 交互式选择 ────────────────────────────────────────
if $INTERACTIVE; then
    echo ""
    echo -e "${BOLD}${CYAN}  bash 增强补全 — 一键安装${NC}"
    echo -e "${CYAN}  ───────────────────────────${NC}"
    echo ""
    echo -e "  ${BOLD}1) ble.sh${NC} (Bash Line Editor)  — 输入时灰色提示历史命令 + 语法高亮"
    echo -e "  ${BOLD}2) bash-completion${NC}             — Tab 补全更多命令和参数"
    echo -e "  ${BOLD}3) fzf${NC}                         — 模糊搜索文件(Ctrl+T) / 历史(Ctrl+R)"
    echo ""
    echo -e "  输入要安装的编号，多选用空格分隔 (如: 1 2 3 或 a 全装)"
    echo -ne "  ${BOLD}你的选择 [a]:${NC} "

    read -r choice
    case "$choice" in
        ""|a|A|all)  INSTALL_SUGGEST=true; INSTALL_COMPLETE=true; INSTALL_FZF=true ;;
        *1*)      INSTALL_SUGGEST=true ;;
        *2*)      INSTALL_COMPLETE=true ;;
        *3*)      INSTALL_FZF=true ;;
        *)        die "无效选择: $choice" ;;
    esac

    if $INSTALL_SUGGEST && ! $INSTALL_COMPLETE; then
        echo -ne "  ${YELLOW}建议同时安装 bash-completion，是否加上? [Y/n]:${NC} "
        read -r ans
        [[ "$ans" != "n" && "$ans" != "N" ]] && INSTALL_COMPLETE=true
    fi
    if $INSTALL_COMPLETE && ! $INSTALL_SUGGEST; then
        echo -ne "  ${YELLOW}建议同时安装 ble.sh，是否加上? [Y/n]:${NC} "
        read -r ans
        [[ "$ans" != "n" && "$ans" != "N" ]] && INSTALL_SUGGEST=true
    fi
fi

echo ""
echo -e "${BOLD}将要安装:${NC}"
$INSTALL_SUGGEST  && echo "  - ble.sh (自动建议 + 语法高亮)"
$INSTALL_COMPLETE && echo "  - bash-completion (增强 Tab 补全)"
$INSTALL_FZF      && echo "  - fzf (模糊搜索)"
echo ""

# ── 安装函数 ──────────────────────────────────────────

# --- ble.sh ---
install_blesh_brew() {
    # ble.sh 不在 brew core，用 git 编译安装
    install_blesh_manual
}
install_blesh_manual() {
    local dest="$PLUG_DIR/ble.sh"
    if [[ -d "$dest" ]]; then
        info "ble.sh 已存在，拉取最新..."
        git -C "$dest" pull --ff-only -q 2>/dev/null || warn "更新失败，使用现有版本"
    else
        mkdir -p "$PLUG_DIR"
        git clone --recursive --depth 1 https://github.com/akinomyoga/ble.sh.git "$dest" -q
    fi
    # 编译
    if [[ ! -f "$dest/out/ble.sh" ]]; then
        info "编译 ble.sh..."
        (cd "$dest" && make -j"$(nproc 2>/dev/null || echo 1)" -s 2>/dev/null) \
            || warn "编译失败，将在启动时自动编译"
    fi
}

# --- bash-completion ---
install_completion_brew() {
    local formula conflict

    # Homebrew 的 bash-completion@2 需要 Bash 4.2+；macOS 自带 /bin/bash
    # 通常是 3.2，只能使用旧版 bash-completion。
    if (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 2) )); then
        formula="bash-completion@2"
        conflict="bash-completion"
    else
        formula="bash-completion"
        conflict="bash-completion@2"
    fi

    if brew list --versions "$formula" &>/dev/null; then
        info "${formula} 已安装，跳过 brew install"
        return
    fi

    if brew list --versions "$conflict" &>/dev/null; then
        warn "检测到已安装冲突版本 ${conflict}，将先执行 brew unlink ${conflict}"
        brew unlink "$conflict" >/dev/null
    fi

    brew install "$formula"
}
install_completion_manual() {
    if has_cmd bash-completion; then
        info "bash-completion 已安装 (系统包)"
        return
    fi
    # 尝试用系统包管理器装
    if has_cmd apt-get; then
        sudo apt-get update -qq && sudo apt-get install -y -qq bash-completion
    elif has_cmd yum; then
        sudo yum install -y -q bash-completion
    else
        # 手动安装
        local dest="$PLUG_DIR/bash-completion"
        if [[ -d "$dest" ]]; then
            info "bash-completion 已存在，拉取最新..."
            git -C "$dest" pull --ff-only -q 2>/dev/null || warn "更新失败，使用现有版本"
        else
            mkdir -p "$PLUG_DIR"
            git clone --depth 1 https://github.com/scop/bash-completion.git "$dest" -q
        fi
    fi
}

# --- fzf ---
install_fzf_brew() {
    brew install fzf
    local fzf_install
    fzf_install="$(brew --prefix)/opt/fzf/install"
    if [[ -x "$fzf_install" ]]; then
        info "运行 fzf 安装器 (自动接受键绑定和补全)..."
        yes | "$fzf_install" --all 2>/dev/null || true
    fi
}
install_fzf_manual() {
    local dest="$HOME/.fzf"
    if [[ -d "$dest" ]]; then
        info "fzf 已存在，拉取最新..."
        git -C "$dest" pull --ff-only -q 2>/dev/null || warn "更新失败，使用现有版本"
    else
        git clone --depth 1 https://github.com/junegunn/fzf.git "$dest" -q
    fi
    info "运行 fzf 安装器 (自动接受键绑定和补全)..."
    yes | "$dest/install" --all 2>/dev/null || true
}

# ── 执行安装 ──────────────────────────────────────────

if $INSTALL_SUGGEST; then
    info "安装 ble.sh..."
    if $HAS_BREW; then
        install_blesh_brew
    else
        install_blesh_manual
    fi
    ok "ble.sh 安装完成"
fi

if $INSTALL_COMPLETE; then
    info "安装 bash-completion..."
    if $HAS_BREW; then
        install_completion_brew
    else
        install_completion_manual
    fi
    ok "bash-completion 安装完成"
fi

if $INSTALL_FZF; then
    info "安装 fzf..."
    if $HAS_BREW; then
        install_fzf_brew
    else
        install_fzf_manual
    fi
    ok "fzf 安装完成"
fi

# ── 配置 .bashrc ─────────────────────────────────────
# 用标记块实现幂等：只插入一次，重复运行会更新

MARKER_START="# >>> bash-enhance-setup >>>"
MARKER_END="# <<< bash-enhance-setup <<<"

generate_config_block() {
    local lines=()
    lines+=("")
    lines+=("$MARKER_START")
    lines+=("# 由 bash-enhance-setup.sh 自动生成，勿手动修改标记行之间内容")

    # ble.sh（必须在最前面，它会接管 readline）
    if $INSTALL_SUGGEST; then
        lines+=("")
        lines+=("# ble.sh: 自动建议 + 语法高亮 (类似 fish/zsh-autosuggestions)")
        lines+=("if [[ \$- == *i* ]] && [[ -z \"\${BLE_VERSION-}\" ]]; then")
        lines+=("  source \"$PLUG_DIR/ble.sh/out/ble.sh\" --noattach")
        lines+=("fi")
        lines+=("")
        lines+=("# ble.sh 建议样式: 灰色提示，按 → 接受")
        lines+=("ble-face -s auto_complete fg=248")
        lines+=("# ble.sh 自动补全选项: 启用历史匹配")
        lines+=("bleopt complete_auto_complete=history")
    fi

    # bash-completion
    if $INSTALL_COMPLETE; then
        lines+=("")
        lines+=("# bash-completion: 增强 Tab 补全")
        # 检测不同安装位置的 bash-completion
        lines+=("if [[ -z \"\${BASH_COMPLETION_VERSINFO-}\" ]]; then")
        lines+=("  # 系统包管理器安装的")
        lines+=("  if [[ -f /etc/profile.d/bash_completion.sh ]]; then")
        lines+=("    source /etc/profile.d/bash_completion.sh")
        lines+=("  # brew 安装的")
        lines+=("  elif type brew &>/dev/null && [[ -f \"\$(brew --prefix)/etc/profile.d/bash_completion.sh\" ]]; then")
        lines+=("    source \"\$(brew --prefix)/etc/profile.d/bash_completion.sh\"")
        lines+=("  # 手动克隆的")
        lines+=("  elif [[ -f \"$PLUG_DIR/bash-completion/bash_completion\" ]]; then")
        lines+=("    source \"$PLUG_DIR/bash-completion/bash_completion\"")
        lines+=("  fi")
        lines+=("fi")
    fi

    # fzf
    if $INSTALL_FZF; then
        lines+=("")
        lines+=("# fzf: 模糊搜索  Ctrl+T 搜文件 / Ctrl+R 搜历史 / Alt+C 跳目录")
        if $HAS_BREW; then
            lines+=("if type brew &>/dev/null; then")
            lines+=("  source \"\$(brew --prefix)/opt/fzf/shell/key-bindings.bash\"")
            lines+=("  source \"\$(brew --prefix)/opt/fzf/shell/completion.bash\"")
            lines+=("fi")
        else
            lines+=("if [[ -f \"$HOME/.fzf/shell/key-bindings.bash\" ]]; then")
            lines+=("  source \"$HOME/.fzf/shell/key-bindings.bash\"")
            lines+=("  source \"$HOME/.fzf/shell/completion.bash\"")
            lines+=("fi")
        fi
        # fd 加速（如果有装）
        lines+=("if type fd &>/dev/null; then")
        lines+=("  export FZF_DEFAULT_OPTS=\"--layout=reverse --height=40%\"")
        lines+=("  export FZF_CTRL_T_COMMAND=\"fd --type f --hidden --follow --exclude .git\"")
        lines+=("  export FZF_ALT_C_COMMAND=\"fd --type d --hidden --follow --exclude .git\"")
        lines+=("fi")
    fi

    # ble.sh attach（必须在所有配置之后）
    if $INSTALL_SUGGEST; then
        lines+=("")
        lines+=("# ble.sh: 延迟 attach，确保上面配置都已加载")
        lines+=("if [[ \$- == *i* ]] && [[ -n \"\${BLE_VERSION-}\" ]]; then")
        lines+=("  ble-attach")
        lines+=("fi")
    fi

    lines+=("")
    lines+=("$MARKER_END")
    lines+=("")

    printf '%s\n' "${lines[@]}"
}

# 移除旧的标记块（如果存在），再追加新的
update_bashrc() {
    local block
    block="$(generate_config_block)"

    # 确保 .bashrc 存在
    [[ -f "$BASHRC" ]] || touch "$BASHRC"

    # 删除旧的标记块
    if grep -q "$MARKER_START" "$BASHRC"; then
        info "更新 .bashrc 中已有的配置块..."
        awk -v start="$MARKER_START" -v end="$MARKER_END" '
            $0 == start { skip=1; next }
            $0 == end   { skip=0; next }
            !skip { print }
        ' "$BASHRC" > "${BASHRC}.tmp" && mv "${BASHRC}.tmp" "$BASHRC"
    else
        info "向 .bashrc 追加配置..."
    fi

    # 追加新块
    echo "$block" >> "$BASHRC"
    ok ".bashrc 配置完成"
}

update_bashrc

# ── 清理 fzf install 写入的重复行 ────────────────────
if $INSTALL_FZF; then
    if grep -q 'source.*fzf/shell/key-bindings.bash' "$BASHRC"; then
        local_count="$(grep -c 'source.*fzf/shell/key-bindings.bash' "$BASHRC" || true)"
        if [[ "$local_count" -gt 1 ]]; then
            info "清理 fzf 产生的重复 source 行..."
            awk -v start="$MARKER_START" -v end="$MARKER_END" '
                $0 == start { inside=1 }
                $0 == end   { inside=0; print; next }
                !inside && /source.*fzf\/shell\// { next }
                { print }
            ' "$BASHRC" > "${BASHRC}.tmp" && mv "${BASHRC}.tmp" "$BASHRC"
            ok "重复行已清理"
        fi
    fi
fi

# ── 完成 ─────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}  全部完成!${NC}"
echo ""
echo -e "  执行以下命令生效:"
echo -e "  ${CYAN}source ~/.bashrc${NC}"
echo ""
echo -e "${BOLD}  快捷键速查:${NC}"
$INSTALL_SUGGEST  && echo -e "  ${BOLD}→${NC} (右方向键)    接受灰色建议"
$INSTALL_SUGGEST  && echo -e "  ${BOLD}Ctrl+E${NC}          接受整条建议"
$INSTALL_COMPLETE && echo -e "  ${BOLD}Tab${NC}             触发补全菜单"
$INSTALL_FZF      && echo -e "  ${BOLD}Ctrl+T${NC}          模糊搜索文件"
$INSTALL_FZF      && echo -e "  ${BOLD}Ctrl+R${NC}          模糊搜索历史命令"
$INSTALL_FZF      && echo -e "  ${BOLD}Alt+C${NC}           模糊跳转目录"
echo ""
