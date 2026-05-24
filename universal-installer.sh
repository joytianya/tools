#!/bin/bash

# Universal Modern Shell Configuration Installer
# 跨平台现代化 Shell 配置一键安装脚本
# 支持: Linux (Ubuntu/Debian, CentOS/RHEL, Arch) 和 macOS
# Author: zxw
# Version: 2.0.0 (Universal)

set -e

# 配置变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.config_backup_$(date +%Y%m%d_%H%M%S)"
CONFIG_DIR="$HOME/.config/shell"
INSTALL_LOG="$HOME/bash_installer_universal.log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 系统变量
OS=""
PACKAGE_MANAGER=""
MAC_ARCH=""

# 日志函数
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$INSTALL_LOG"
}

info() {
    log "${BLUE}[INFO]${NC} $1"
}

success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

error() {
    log "${RED}[ERROR]${NC} $1"
}

# 系统检测函数
detect_system() {
    info "检测系统环境..."

    # 检查操作系统
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"

        # 检测 Linux 发行版和包管理器
        if command -v apt &> /dev/null; then
            PACKAGE_MANAGER="apt"
            info "检测到基于 Debian 的系统 (Ubuntu/Debian)"
        elif command -v yum &> /dev/null; then
            PACKAGE_MANAGER="yum"
            info "检测到基于 RHEL 的系统 (CentOS/RHEL/Fedora)"
        elif command -v dnf &> /dev/null; then
            PACKAGE_MANAGER="dnf"
            info "检测到 Fedora/新版 RHEL 系统"
        elif command -v pacman &> /dev/null; then
            PACKAGE_MANAGER="pacman"
            info "检测到 Arch Linux 系统"
        elif command -v zypper &> /dev/null; then
            PACKAGE_MANAGER="zypper"
            info "检测到 openSUSE 系统"
        else
            warning "未识别的包管理器，某些功能可能无法自动安装"
            PACKAGE_MANAGER="unknown"
        fi

    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"

        # 检测 Mac 架构
        if [[ $(uname -m) == 'arm64' ]]; then
            MAC_ARCH="apple_silicon"
            info "检测到 Apple Silicon Mac"
        else
            MAC_ARCH="intel"
            info "检测到 Intel Mac"
        fi

        # 检查 Homebrew
        if command -v brew &> /dev/null; then
            PACKAGE_MANAGER="brew"
            info "Homebrew 已安装"
        else
            warning "未检测到 Homebrew，将自动安装"
            PACKAGE_MANAGER="brew_install"
        fi

    else
        error "不支持的操作系统: $OSTYPE"
        exit 1
    fi

    # 显示检测结果
    success "系统检测完成: $OS ($PACKAGE_MANAGER)"
}

# 设置hostname为外网IP
setup_hostname_as_ip() {
    info "检测外网IP并设置为hostname..."

    # 获取外网IP
    EXTERNAL_IP=""
    if command -v curl >/dev/null 2>&1; then
        EXTERNAL_IP=$(curl -s --connect-timeout 10 ifconfig.me 2>/dev/null || curl -s --connect-timeout 10 ipinfo.io/ip 2>/dev/null)
    elif command -v wget >/dev/null 2>&1; then
        EXTERNAL_IP=$(wget -qO- --timeout=10 ifconfig.me 2>/dev/null || wget -qO- --timeout=10 ipinfo.io/ip 2>/dev/null)
    fi

    if [[ -n "$EXTERNAL_IP" && "$EXTERNAL_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        info "检测到外网IP: $EXTERNAL_IP"

        # 询问用户是否要设置hostname为IP
        echo -e "${YELLOW}是否将hostname设置为外网IP ($EXTERNAL_IP)? (y/N)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            if [[ "$OS" == "macos" ]]; then
                sudo scutil --set HostName "$EXTERNAL_IP"
                sudo scutil --set LocalHostName "$EXTERNAL_IP"
                sudo scutil --set ComputerName "$EXTERNAL_IP"
                success "macOS hostname已设置为: $EXTERNAL_IP"
            else
                # Linux系统
                if sudo hostnamectl set-hostname "$EXTERNAL_IP" 2>/dev/null; then
                    # 更新/etc/hosts文件
                    if ! grep -q "127.0.0.1 $EXTERNAL_IP" /etc/hosts 2>/dev/null; then
                        echo "127.0.0.1 $EXTERNAL_IP" | sudo tee -a /etc/hosts >/dev/null
                    fi
                    success "Linux hostname已设置为: $EXTERNAL_IP"
                else
                    warning "无法设置hostname，可能需要管理员权限"
                fi
            fi
        else
            info "跳过hostname设置"
        fi
    else
        warning "无法获取有效的外网IP地址，跳过hostname设置"
    fi
}

# 安装 Homebrew (仅 macOS)
install_homebrew() {
    if [[ "$OS" != "macos" ]]; then
        return 0
    fi

    info "正在安装 Homebrew..."
    if /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
        success "Homebrew 安装成功"

        # 设置 Homebrew 环境
        if [[ "$MAC_ARCH" == "apple_silicon" ]]; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.bash_profile
            eval "$(/opt/homebrew/bin/brew shellenv)"
        else
            echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.bash_profile
            eval "$(/usr/local/bin/brew shellenv)"
        fi

        source ~/.bash_profile 2>/dev/null || true
        PACKAGE_MANAGER="brew"
    else
        error "Homebrew 安装失败"
        exit 1
    fi
}

# 检查用户权限
check_sudo_privileges() {
    if [[ $EUID -eq 0 ]]; then
        # 以root身份运行
        return 0
    fi
    
    # 检查sudo权限
    if ! sudo -n true 2>/dev/null; then
        warning "检测到没有sudo权限，将使用用户模式安装"
        info "某些功能可能需要手动安装，或者您可以重新以sudo权限运行此脚本"
        return 1
    fi
    
    return 0
}

# 检查系统依赖
check_dependencies() {
    info "检查系统依赖..."

    case "$OS" in
        "macos")
            # 检查 Xcode Command Line Tools
            if ! xcode-select -p &> /dev/null; then
                warning "未检测到 Xcode Command Line Tools，开始安装..."
                xcode-select --install
                info "请按照提示完成 Xcode Command Line Tools 安装，然后重新运行此脚本"
                exit 1
            else
                info "Xcode Command Line Tools 已安装"
            fi

            # 安装 Homebrew (如果需要)
            if [[ "$PACKAGE_MANAGER" == "brew_install" ]]; then
                install_homebrew
            fi
            ;;
        "linux")
            # 检查sudo权限
            if check_sudo_privileges; then
                # 有sudo权限时更新包索引
                if [[ "$PACKAGE_MANAGER" == "apt" ]]; then
                    info "更新 APT 包索引..."
                    if ! sudo apt update 2>/dev/null; then
                        warning "包索引更新失败，将尝试用户模式安装"
                    fi
                elif [[ "$PACKAGE_MANAGER" == "yum" ]]; then
                    info "更新 YUM 包索引..."
                    sudo yum check-update 2>/dev/null || true
                elif [[ "$PACKAGE_MANAGER" == "dnf" ]]; then
                    info "更新 DNF 包索引..."
                    sudo dnf check-update 2>/dev/null || true
                fi
            else
                warning "没有sudo权限，跳过系统包索引更新"
                info "将优先使用用户空间安装方式"
            fi
            ;;
    esac
}

# 创建备份
create_backup() {
    info "创建配置备份到 $BACKUP_DIR..."
    mkdir -p "$BACKUP_DIR"

    # 备份配置文件
    local files_to_backup
    if [[ "$OS_TYPE" == "macos" ]]; then
        files_to_backup=(".bashrc" ".bash_aliases" ".bash_profile" ".profile" ".inputrc" ".dircolors" ".zshrc")
    else
        files_to_backup=(".bashrc" ".bash_aliases" ".bash_profile" ".profile" ".inputrc" ".dircolors")
    fi

    for file in "${files_to_backup[@]}"; do
        if [[ -f "$HOME/$file" ]]; then
            cp "$HOME/$file" "$BACKUP_DIR/"
            info "备份 $file"
        fi
    done

    success "配置备份完成"
}

# 通用工具安装函数
install_universal_tools() {
    info "安装现代化 Shell 工具..."

    # 定义通用工具列表
    local basic_tools=(
        "curl:网络下载工具"
        "git:版本控制"
        "tmux:终端多路复用器"
        "vim:文本编辑器"
    )

    local modern_tools=(
        "fzf:模糊搜索"
        "zoxide:智能目录跳转"
        "bat:现代化 cat"
        "ripgrep:现代化 grep"
        "fd:现代化 find"
    )

    # macOS 额外工具
    local mac_tools=(
        "htop:系统监控"
        "tree:目录树显示"
        "wget:文件下载工具"
        "jq:JSON 处理工具"
        "tldr:简化版 man 页面"
        "ncdu:磁盘使用分析"
        "procs:现代化 ps"
        "dust:现代化 du"
    )

    case "$PACKAGE_MANAGER" in
        "apt")
            install_with_apt
            ;;
        "yum"|"dnf")
            install_with_yum_dnf
            ;;
        "pacman")
            install_with_pacman
            ;;
        "zypper")
            install_with_zypper
            ;;
        "brew")
            install_with_brew
            ;;
        *)
            warning "无法自动安装依赖，请手动安装工具"
            show_manual_install_instructions
            ;;
    esac

    # 安装跨平台工具
    install_cross_platform_tools
    normalize_linux_tool_names
}

# Debian/Ubuntu 上部分工具的二进制名和通用命令名不同。
normalize_linux_tool_names() {
    [[ "$OS_TYPE" == "linux" ]] || return 0

    mkdir -p "$HOME/.local/bin"

    if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
        ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
        success "已创建 bat -> batcat 兼容链接"
    fi

    if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
        ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
        success "已创建 fd -> fdfind 兼容链接"
    fi
}

# APT 安装 (Ubuntu/Debian)
install_with_apt() {
    info "使用 APT 安装工具..."

    # 基础工具
    local tools_to_install=""
    for tool in curl git tmux vim unzip; do
        if ! command -v $tool &> /dev/null; then
            tools_to_install="$tools_to_install $tool"
        fi
    done

    # 现代化工具
    for tool in fzf zoxide bat ripgrep fd-find; do
        if ! command -v ${tool%%-*} &> /dev/null; then
            tools_to_install="$tools_to_install $tool"
        fi
    done

    # 检查 exa/eza
    if ! command -v exa &> /dev/null && ! command -v eza &> /dev/null; then
        tools_to_install="$tools_to_install exa"
    fi

    if [ -n "$tools_to_install" ]; then
        # 检查sudo权限
        if check_sudo_privileges; then
            info "安装工具: $tools_to_install"
            if ! sudo apt install -y $tools_to_install 2>/dev/null; then
                warning "部分工具通过APT安装失败，将使用手动安装方式"
                install_manual_tools_linux
            fi
        else
            warning "没有sudo权限，无法使用APT安装，将使用手动安装方式"
            install_manual_tools_linux
        fi
    fi
}

# YUM/DNF 安装 (CentOS/RHEL/Fedora)
install_with_yum_dnf() {
    local cmd="$PACKAGE_MANAGER"
    info "使用 $cmd 安装工具..."

    # 检查sudo权限
    if check_sudo_privileges; then
        # 安装 EPEL (如果是 RHEL/CentOS)
        if [[ "$PACKAGE_MANAGER" == "yum" ]]; then
            sudo yum install -y epel-release 2>/dev/null || true
        fi

        # 基础工具
        local basic_tools=""
        for tool in curl git tmux vim unzip tar; do
            if ! command -v $tool &> /dev/null; then
                basic_tools="$basic_tools $tool"
            fi
        done

        if [ -n "$basic_tools" ]; then
            if ! sudo $cmd install -y $basic_tools 2>/dev/null; then
                warning "部分基础工具安装失败"
            fi
        fi

        # 安装可用的现代化工具
        if ! command -v fzf &> /dev/null; then
            sudo $cmd install -y fzf 2>/dev/null || warning "fzf 需要手动安装"
        fi
    else
        warning "没有sudo权限，无法使用 $cmd 安装，将使用手动安装方式"
    fi

    # 其他工具需要手动安装
    install_manual_tools_linux
}

# Pacman 安装 (Arch Linux)
install_with_pacman() {
    info "使用 Pacman 安装工具..."

    local tools_to_install=""
    for tool in curl git fzf zoxide exa bat ripgrep fd tmux vim; do
        if ! command -v $tool &> /dev/null; then
            tools_to_install="$tools_to_install $tool"
        fi
    done

    if [ -n "$tools_to_install" ]; then
        if check_sudo_privileges; then
            if ! sudo pacman -S --noconfirm $tools_to_install 2>/dev/null; then
                warning "部分工具通过Pacman安装失败，将使用手动安装方式"
                install_manual_tools_linux
            fi
        else
            warning "没有sudo权限，无法使用Pacman安装，将使用手动安装方式"
            install_manual_tools_linux
        fi
    fi
}

# Zypper 安装 (openSUSE)
install_with_zypper() {
    info "使用 Zypper 安装工具..."

    local tools_to_install=""
    for tool in curl git fzf tmux vim; do
        if ! command -v $tool &> /dev/null; then
            tools_to_install="$tools_to_install $tool"
        fi
    done

    if [ -n "$tools_to_install" ]; then
        if check_sudo_privileges; then
            if ! sudo zypper install -y $tools_to_install 2>/dev/null; then
                warning "部分工具通过Zypper安装失败，将使用手动安装方式"
            fi
        else
            warning "没有sudo权限，无法使用Zypper安装，将使用手动安装方式"
        fi
    fi

    # 其他工具需要手动安装
    install_manual_tools_linux
}

# Homebrew 安装 (macOS)
install_with_brew() {
    info "使用 Homebrew 安装工具..."

    # 更新 Homebrew
    brew update

    # 安装所有工具
    local all_tools=(
        "git" "fzf" "zoxide" "eza" "bat" "ripgrep" "fd" "tmux" "vim"
        "htop" "tree" "wget" "jq" "tldr" "ncdu" "procs" "dust"
    )

    local tools_to_install=""
    for tool in "${all_tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            tools_to_install="$tools_to_install $tool"
        fi
    done

    if [ -n "$tools_to_install" ]; then
        info "安装工具: $tools_to_install"
        brew install $tools_to_install
    fi

    # 安装字体
    info "安装 Nerd 字体..."
    brew install --cask font-fira-code-nerd-font 2>/dev/null || warning "字体安装失败，不影响主要功能"
}

# 通过包管理器安装工具 (回退方案)
install_via_package_manager() {
    local tool_name="$1"
    info "尝试通过包管理器安装 $tool_name..."

    # 检查sudo权限
    if ! check_sudo_privileges; then
        warning "没有sudo权限，无法通过包管理器安装 $tool_name"
        return 1
    fi

    case "$PACKAGE_MANAGER" in
        "apt")
            sudo apt install -y "$tool_name" 2>/dev/null || warning "$tool_name 包管理器安装失败"
            ;;
        "dnf")
            sudo dnf install -y "$tool_name" 2>/dev/null || warning "$tool_name 包管理器安装失败"
            ;;
        "yum")
            sudo yum install -y "$tool_name" 2>/dev/null || warning "$tool_name 包管理器安装失败"
            ;;
        "pacman")
            sudo pacman -S --noconfirm "$tool_name" 2>/dev/null || warning "$tool_name 包管理器安装失败"
            ;;
        "zypper")
            sudo zypper install -y "$tool_name" 2>/dev/null || warning "$tool_name 包管理器安装失败"
            ;;
        *)
            warning "未知包管理器，无法安装 $tool_name"
            ;;
    esac
}

# Linux 手动安装工具
install_manual_tools_linux() {
    mkdir -p "$HOME/.local/bin"

    # 安装 exa/eza
    if ! command -v exa &> /dev/null && ! command -v eza &> /dev/null; then
        info "安装 exa..."
        if curl -L "https://github.com/ogham/exa/releases/download/v0.10.1/exa-linux-x86_64-v0.10.1.zip" -o /tmp/exa.zip 2>/dev/null; then
            unzip -q /tmp/exa.zip -d /tmp/ && mv /tmp/bin/exa "$HOME/.local/bin/" && rm -rf /tmp/exa.zip /tmp/bin
            success "exa 安装成功"
        else
            warning "exa 下载失败"
        fi
    fi

    # 安装 bat
    if ! command -v bat &> /dev/null; then
        info "安装 bat..."
        BAT_VERSION="0.24.0"
        if curl -L "https://github.com/sharkdp/bat/releases/download/v${BAT_VERSION}/bat-v${BAT_VERSION}-x86_64-unknown-linux-musl.tar.gz" | tar -xz -C /tmp/ 2>/dev/null; then
            mv "/tmp/bat-v${BAT_VERSION}-x86_64-unknown-linux-musl/bat" "$HOME/.local/bin/" && rm -rf "/tmp/bat-v${BAT_VERSION}-x86_64-unknown-linux-musl"
            success "bat 安装成功"
        else
            warning "bat 下载失败"
        fi
    fi

    # 安装 ripgrep
    if ! command -v rg &> /dev/null; then
        info "安装 ripgrep..."
        RG_VERSION="14.1.0"
        if curl -L "https://github.com/BurntSushi/ripgrep/releases/download/${RG_VERSION}/ripgrep-${RG_VERSION}-x86_64-unknown-linux-musl.tar.gz" | tar -xz -C /tmp/ 2>/dev/null; then
            mv "/tmp/ripgrep-${RG_VERSION}-x86_64-unknown-linux-musl/rg" "$HOME/.local/bin/" && rm -rf "/tmp/ripgrep-${RG_VERSION}-x86_64-unknown-linux-musl"
            success "ripgrep 安装成功"
        else
            warning "ripgrep 下载失败"
        fi
    fi

    # 安装 fd
    if ! command -v fd &> /dev/null; then
        info "安装 fd..."
        FD_VERSION="10.1.0"
        if curl -L "https://github.com/sharkdp/fd/releases/download/v${FD_VERSION}/fd-v${FD_VERSION}-x86_64-unknown-linux-musl.tar.gz" | tar -xz -C /tmp/ 2>/dev/null; then
            mv "/tmp/fd-v${FD_VERSION}-x86_64-unknown-linux-musl/fd" "$HOME/.local/bin/" && rm -rf "/tmp/fd-v${FD_VERSION}-x86_64-unknown-linux-musl"
            success "fd 安装成功"
        else
            warning "fd 下载失败"
        fi
    fi

    # 安装 zoxide
    if ! command -v zoxide &> /dev/null; then
        info "安装 zoxide..."
        if curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash; then
            success "zoxide 安装成功"
        else
            warning "zoxide 安装失败"
        fi
    fi
}

# 跨平台工具安装
install_cross_platform_tools() {
    # 安装 Starship
    if ! command -v starship &> /dev/null; then
        info "安装 Starship 终端提示符..."
        if [[ "$OS_TYPE" == "macos" ]]; then
            brew install starship
        else
            mkdir -p "$HOME/.local/bin"
            if curl -sS https://starship.rs/install.sh | sh -s -- --bin-dir "$HOME/.local/bin" -y; then
                success "Starship 安装成功"
            else
                warning "Starship 安装失败"
            fi
        fi
    fi

    # 安装 McFly
    if ! command -v mcfly &> /dev/null; then
        info "安装 McFly 智能历史管理..."
        if [[ "$OS_TYPE" == "macos" ]]; then
            if brew install mcfly 2>/dev/null; then
                success "McFly 安装成功"
            else
                warning "McFly 安装失败，请检查 Homebrew"
            fi
        else
            mkdir -p "$HOME/.local/bin"
            MCFLY_VERSION="v0.8.4"
            TEMP_DIR=$(mktemp -d)

            # 下载并解压到临时目录
            if curl -L "https://github.com/cantino/mcfly/releases/download/${MCFLY_VERSION}/mcfly-${MCFLY_VERSION}-x86_64-unknown-linux-musl.tar.gz" -o "${TEMP_DIR}/mcfly.tar.gz" 2>/dev/null; then
                if tar -xzf "${TEMP_DIR}/mcfly.tar.gz" -C "${TEMP_DIR}" 2>/dev/null; then
                    # 查找解压后的 mcfly 二进制文件
                    MCFLY_BIN=$(find "${TEMP_DIR}" -name "mcfly" -type f -executable 2>/dev/null | head -1)
                    if [[ -n "$MCFLY_BIN" && -x "$MCFLY_BIN" ]]; then
                        cp "$MCFLY_BIN" "$HOME/.local/bin/mcfly"
                        chmod +x "$HOME/.local/bin/mcfly"
                        success "McFly 安装成功"
                    else
                        warning "McFly 二进制文件未找到，尝试包管理器安装"
                        install_via_package_manager "mcfly"
                    fi
                else
                    warning "McFly 解压失败，尝试包管理器安装"
                    install_via_package_manager "mcfly"
                fi
            else
                warning "McFly 下载失败，尝试包管理器安装"
                install_via_package_manager "mcfly"
            fi

            # 清理临时目录
            rm -rf "${TEMP_DIR}"
        fi
    fi
}

# 手动安装说明
show_manual_install_instructions() {
    warning "无法自动安装所有工具，请手动安装以下工具："
    echo "- fzf (模糊搜索): https://github.com/junegunn/fzf"
    echo "- zoxide (智能目录跳转): https://github.com/ajeetdsouza/zoxide"
    echo "- exa/eza (现代化ls): https://github.com/ogham/exa"
    echo "- bat (现代化cat): https://github.com/sharkdp/bat"
    echo "- ripgrep (现代化grep): https://github.com/BurntSushi/ripgrep"
    echo "- fd (现代化find): https://github.com/sharkdp/fd"
    echo "- starship (终端提示符): https://starship.rs/"
    echo "- mcfly (历史管理): https://github.com/cantino/mcfly"
}

# 生成通用配置
generate_universal_config() {
    info "生成跨平台现代化配置..."

    mkdir -p "$CONFIG_DIR"

    if [ -f "$CONFIG_DIR/universal-config.sh" ]; then
        local config_backup="$CONFIG_DIR/universal-config.sh.bak-$(date +%Y%m%d_%H%M%S)"
        cp "$CONFIG_DIR/universal-config.sh" "$config_backup"
        info "已备份现有通用配置: $config_backup"
    fi

    cat > "$CONFIG_DIR/universal-config.sh" << 'EOF'
#!/bin/bash
# Universal Modern Shell Configuration
# 跨平台现代化Shell配置

# ============ Shell 类型检测 ============
CURRENT_SHELL="bash"
if [ -n "$ZSH_VERSION" ]; then
    CURRENT_SHELL="zsh"
elif [ -n "$BASH_VERSION" ]; then
    CURRENT_SHELL="bash"
fi

# ============ 系统检测 ============
OS_TYPE="unknown"
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="macos"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS_TYPE="linux"
fi

# ============ 基础配置 ============

# 添加用户本地bin目录到PATH
if [ -d "$HOME/.local/bin" ] && ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    export PATH="$HOME/.local/bin:$PATH"
fi

# macOS Homebrew 路径
if [[ "$OS_TYPE" == "macos" ]]; then
    if [[ $(uname -m) == 'arm64' ]]; then
        # Apple Silicon Mac
        if [ -f "/opt/homebrew/bin/brew" ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
    else
        # Intel Mac
        if [ -f "/usr/local/bin/brew" ]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
    fi
fi

# Bash 特定配置
if [[ "$CURRENT_SHELL" == "bash" ]]; then
    # 启用别名扩展
    shopt -s expand_aliases

    # 历史配置优化
    shopt -s histappend
    shopt -s checkwinsize
    shopt -s histverify
fi

# 通用历史配置
HISTSIZE=50000
HISTFILESIZE=100000
HISTCONTROL=ignoredups:ignorespace:erasedups
HISTTIMEFORMAT="%Y-%m-%d %H:%M:%S "

# ============ 颜色支持 ============

# 通用颜色支持
if [[ "$OS_TYPE" == "macos" ]]; then
    export CLICOLOR=1
    export LSCOLORS=ExFxBxDxCxegedabagacad
else
    if [ -x /usr/bin/dircolors ]; then
        test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    fi
fi

# 设置编码
export LANG=en_US.UTF-8
# 检查并设置 LC_ALL（避免在不支持的系统上出错）
if locale -a 2>/dev/null | grep -q "en_US.UTF-8"; then
    export LC_ALL=en_US.UTF-8
elif locale -a 2>/dev/null | grep -q "en_US.utf8"; then
    export LC_ALL=en_US.utf8
else
    export LC_ALL=C.UTF-8
fi

# ============ 现代化工具配置 ============

# FZF - 模糊搜索配置
export FZF_DEFAULT_OPTS='
    --height 50%
    --layout=reverse
    --border=rounded
    --preview "bat --style=numbers --color=always --line-range :500 {} 2>/dev/null || cat {} 2>/dev/null || echo \"无法预览\""
    --preview-window=right:50%:wrap
    --bind "ctrl-/:toggle-preview"
    --bind "ctrl-u:preview-page-up"
    --bind "ctrl-d:preview-page-down"
    --color=fg:#f8f8f2,bg:#282a36,hl:#bd93f9
    --color=fg+:#f8f8f2,bg+:#44475a,hl+:#bd93f9
    --color=info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6
    --color=marker:#ff79c6,spinner:#ffb86c,header:#6272a4'

# 根据可用工具设置 FZF 命令
if command -v fd &> /dev/null; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git --exclude node_modules --exclude .DS_Store'
elif command -v rg &> /dev/null; then
    export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*" --glob "!node_modules/*"'
else
    export FZF_DEFAULT_COMMAND='find . -type f'
fi

export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

if command -v fd &> /dev/null; then
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git --exclude node_modules'
else
    export FZF_ALT_C_COMMAND='find . -type d'
fi

# 加载FZF键绑定 (根据 shell 类型)
if [[ "$CURRENT_SHELL" == "bash" ]]; then
    if [[ "$OS_TYPE" == "macos" ]] && [[ -f "$(brew --prefix)/opt/fzf/shell/key-bindings.bash" ]]; then
        source "$(brew --prefix)/opt/fzf/shell/key-bindings.bash"
        source "$(brew --prefix)/opt/fzf/shell/completion.bash"
    elif [ -f /usr/share/doc/fzf/examples/key-bindings.bash ]; then
        source /usr/share/doc/fzf/examples/key-bindings.bash
    elif [ -f /usr/share/fzf/key-bindings.bash ]; then
        source /usr/share/fzf/key-bindings.bash
    elif [ -f ~/.fzf.bash ]; then
        source ~/.fzf.bash
    fi
elif [[ "$CURRENT_SHELL" == "zsh" ]]; then
    if [[ "$OS_TYPE" == "macos" ]] && [[ -f "$(brew --prefix)/opt/fzf/shell/key-bindings.zsh" ]]; then
        source "$(brew --prefix)/opt/fzf/shell/key-bindings.zsh"
        source "$(brew --prefix)/opt/fzf/shell/completion.zsh"
    elif [ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]; then
        source /usr/share/doc/fzf/examples/key-bindings.zsh
    elif [ -f /usr/share/fzf/key-bindings.zsh ]; then
        source /usr/share/fzf/key-bindings.zsh
    elif [ -f ~/.fzf.zsh ]; then
        source ~/.fzf.zsh
    fi
fi

# Zoxide - 智能目录跳转
if command -v zoxide &> /dev/null; then
    eval "$(zoxide init $CURRENT_SHELL)"
fi

# McFly - 智能历史管理 (仅 Bash 支持)
if [[ "$CURRENT_SHELL" == "bash" ]] && command -v mcfly &> /dev/null; then
    eval "$(mcfly init bash)"
    export MCFLY_KEY_SCHEME=vim
    export MCFLY_FUZZY=2
    export MCFLY_RESULTS=50
    export MCFLY_INTERFACE_VIEW=BOTTOM
fi

# Starship - 美化终端提示符
if command -v starship &> /dev/null; then
    eval "$(starship init "$CURRENT_SHELL")"
fi

# ============ 智能别名系统 ============

# 基础命令增强
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# 现代化 ls 命令 (优先级: eza > exa > ls)
if command -v eza &> /dev/null; then
    alias ls='eza --icons --group-directories-first'
    alias ll='eza -la --icons --group-directories-first --time-style=long-iso --git'
    alias la='eza -a --icons --group-directories-first'
    alias l='eza --icons --group-directories-first'
    alias lt='eza -la --icons --sort=modified --git'
    alias lh='eza -la --icons --group-directories-first --git'
    alias lta='eza --tree --level=3 --icons --git-ignore'
elif command -v exa &> /dev/null; then
    alias ls='exa --icons --group-directories-first'
    alias ll='exa -la --icons --group-directories-first --time-style=long-iso --git'
    alias la='exa -a --icons --group-directories-first'
    alias l='exa --icons --group-directories-first'
    alias lt='exa -la --icons --sort=modified --git'
    alias lh='exa -la --icons --group-directories-first --git'
    alias lta='exa --tree --level=3 --icons'
else
    if [[ "$OS_TYPE" == "macos" ]]; then
        alias ls='ls -G'
        alias ll='ls -alFG'
        alias la='ls -AG'
        alias l='ls -CFG'
    else
        alias ls='ls --color=auto --group-directories-first'
        alias ll='ls -alF --color=auto --group-directories-first --time-style=long-iso'
        alias la='ls -A --color=auto --group-directories-first'
        alias l='ls -CF --color=auto --group-directories-first'
    fi
    alias lt='ls -altr'
    alias lh='ls -alh'
fi

# 现代化 cat 命令
if command -v bat &> /dev/null; then
    alias cat='bat --paging=never'
    alias bcat='bat'
    export BAT_THEME="Dracula"
fi

# 现代化 grep 命令
if command -v rg &> /dev/null; then
    alias grep='rg --color=auto'
    alias rg='rg --colors "match:bg:yellow" --colors "match:fg:black" --colors "path:fg:green" --colors "line:fg:cyan"'
fi

# 现代化 find 命令
if command -v fd &> /dev/null; then
    alias find='fd'
fi

# 现代化系统命令
if command -v procs &> /dev/null; then
    alias ps='procs'
fi

if command -v dust &> /dev/null; then
    alias du='dust'
fi

if command -v htop &> /dev/null; then
    alias top='htop'
elif command -v htop &> /dev/null; then
    alias top='htop'
fi

# 目录导航增强
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ~='cd ~'
alias -- -='cd -'

# Zoxide 别名
if command -v zoxide &> /dev/null; then
    alias cd='z'
    alias cdi='zi'
fi

# 文件操作安全化
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -i'
alias mkdir='mkdir -p'

# Git 增强别名
alias gs='git status -sb'
alias ga='git add'
alias gaa='git add .'
alias gc='git commit -m'
alias gca='git commit -am'
alias gp='git push'
alias gpl='git pull'
alias gl='git log --oneline --graph --decorate --all'
alias gd='git diff'
alias gdc='git diff --cached'
alias gb='git branch'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gm='git merge'
alias gr='git remote -v'

# 系统信息增强
alias df='df -h'
if ! command -v dust &> /dev/null; then
    alias du='du -h'
fi
alias free='free -h 2>/dev/null || vm_stat'
alias meminfo='free -h 2>/dev/null || vm_stat'

# 网络工具
alias ping='ping -c 5'
alias wget='wget -c'
alias curl='curl -L'

# macOS 特定别名
if [[ "$OS_TYPE" == "macos" ]]; then
    alias flushdns='sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder'
    alias showfiles='defaults write com.apple.finder AppleShowAllFiles YES && killall Finder'
    alias hidefiles='defaults write com.apple.finder AppleShowAllFiles NO && killall Finder'
    alias battery='pmset -g batt'
    alias cpu='top -l 1 -s 0 | grep "CPU usage"'
    alias ports='lsof -i -P | grep LISTEN'
    alias brewup='brew update && brew upgrade && brew cleanup'
    alias ip='curl -s ipinfo.io/ip'
    alias localip='ipconfig getifaddr en0'
    alias ips='ifconfig | grep "inet " | grep -v 127.0.0.1'
    alias cleanup='find . -type f -name "*.DS_Store" -ls -delete'

    # 快速打开应用
    alias code='open -a "Visual Studio Code"'
    alias xcode='open -a "Xcode"'
    alias finder='open -a "Finder"'
fi

# Tmux 快捷键
alias tmux='tmux -2'
alias tma='tmux attach'
alias tms='tmux new-session -s'
alias tml='tmux list-sessions'

# 编辑器快捷键
alias vi='vim'

# Claude Code 增强
if command -v claude &> /dev/null; then
    alias ccdsp='claude --dangerously-skip-permissions'
fi

# ============ 实用函数 ============

# 创建目录并进入
mkcd() {
    mkdir -p "$1" && cd "$1"
}

# 快速查找文件
ff() {
    if command -v fd &> /dev/null; then
        fd "$1"
    else
        find . -name "*$1*" -type f
    fi
}

# 快速查找目录
fdir() {
    if command -v fd &> /dev/null; then
        fd -t d "$1"
    else
        find . -name "*$1*" -type d
    fi
}

# 提取各种压缩文件
extract() {
    if [ -f "$1" ] ; then
        case $1 in
            *.tar.bz2)   tar xjf "$1"     ;;
            *.tar.gz)    tar xzf "$1"     ;;
            *.bz2)       bunzip2 "$1"     ;;
            *.rar)       unrar x "$1"     ;;
            *.gz)        gunzip "$1"      ;;
            *.tar)       tar xf "$1"      ;;
            *.tbz2)      tar xjf "$1"     ;;
            *.tgz)       tar xzf "$1"     ;;
            *.zip)       unzip "$1"       ;;
            *.Z)         uncompress "$1"  ;;
            *.7z)        7z x "$1"        ;;
            *.dmg)       [[ "$OS_TYPE" == "macos" ]] && hdiutil mount "$1" ;;
            *)           echo "'$1' 无法提取，不支持的格式" ;;
        esac
    else
        echo "'$1' 不是有效文件"
    fi
}

# 快速创建备份
backup() {
    if [ -n "$1" ]; then
        cp "$1" "$1.backup-$(date +%Y%m%d-%H%M%S)"
        echo "备份创建: $1.backup-$(date +%Y%m%d-%H%M%S)"
    else
        echo "用法: backup <文件名>"
    fi
}

# 查看文件夹大小
dirsize() {
    if command -v dust &> /dev/null; then
        dust -d 1 "${1:-.}"
    else
        du -sh "${1:-.}"/* 2>/dev/null | sort -hr
    fi
}

# 端口检查
port() {
    if [ -n "$1" ]; then
        if [[ "$OS_TYPE" == "macos" ]]; then
            lsof -i ":$1"
        else
            netstat -tulpn | grep ":$1"
        fi
    else
        echo "用法: port <端口号>"
    fi
}

# 快速启动 HTTP 服务器
serve() {
    local port="${1:-8000}"
    if command -v python3 &> /dev/null; then
        python3 -m http.server "$port"
    elif command -v python &> /dev/null; then
        python -m SimpleHTTPServer "$port"
    else
        echo "需要安装 Python"
    fi
}

# 系统信息
sysinfo() {
    echo -e "\033[0;32m🖥️  系统信息\033[0m"
    if [[ "$OS_TYPE" == "macos" ]]; then
        echo "操作系统: $(sw_vers -productName) $(sw_vers -productVersion)"
        echo "处理器: $(sysctl -n machdep.cpu.brand_string)"
        echo "内存: $(sysctl -n hw.memsize | awk '{print $1/1024/1024/1024 " GB"}')"
        echo "磁盘使用: $(df -h / | awk 'NR==2{print $3"/"$2" ("$5")"}')"
    else
        echo "操作系统: $(lsb_release -d 2>/dev/null | cut -f2 || uname -o)"
        echo "内核: $(uname -r)"
        echo "处理器: $(nproc) cores"
        echo "内存: $(free -h | awk '/^Mem:/ {print $3"/"$2}')"
        echo "磁盘使用: $(df -h / | awk 'NR==2{print $3"/"$2" ("$5")"}')"
    fi
    echo "正常运行时间: $(uptime | sed 's/.*up //' | sed 's/,.*//')"
}

# 显示工具帮助
show_tools() {
    echo -e "\033[0;32m🚀 跨平台现代化 Shell 工具已加载！\033[0m"
    echo -e "\033[0;34m📁 目录导航:\033[0m z <目录名> (智能跳转), zi (交互选择)"
    echo -e "\033[0;34m🔍 文件搜索:\033[0m Ctrl+T (文件), Alt+C (目录), Ctrl+R (历史)"
    echo -e "\033[0;34m📋 文件查看:\033[0m ll (详细列表), cat (语法高亮), grep (高级搜索)"
    echo -e "\033[0;34m⚡ 实用函数:\033[0m mkcd, extract, ff (查找文件), sysinfo, backup"
    if [[ "$OS_TYPE" == "macos" ]]; then
        echo -e "\033[0;35m🍎 Mac 特定:\033[0m flushdns, showfiles, hidefiles, brewup, battery"
    fi
    echo -e "\033[0;34m🎨 终端美化:\033[0m Starship 提示符, 彩色输出"
    echo -e "\033[0;35m💡 提示:\033[0m 使用 'show_tools' 随时查看此帮助"
}

# 自动显示工具提示（仅在交互式shell中）
if [[ $- == *i* ]]; then
    show_tools
fi

# ============ 补全增强 ============

# Bash 补全增强。不要在 zsh 中加载 bash_completion/git-completion.bash。
if [[ "$CURRENT_SHELL" == "bash" ]]; then
    if [[ "$OS_TYPE" == "macos" ]]; then
        if command -v brew &> /dev/null && [[ -r "$(brew --prefix)/etc/profile.d/bash_completion.sh" ]]; then
            source "$(brew --prefix)/etc/profile.d/bash_completion.sh"
        fi

        if command -v brew &> /dev/null && [[ -f "$(brew --prefix)/etc/bash_completion.d/git-completion.bash" ]]; then
            source "$(brew --prefix)/etc/bash_completion.d/git-completion.bash"
        fi
    else
        if [ -f /etc/bash_completion ]; then
            source /etc/bash_completion
        fi

        if [ -f ~/.git-completion.bash ]; then
            source ~/.git-completion.bash
        fi
    fi

    bind "set show-all-if-ambiguous on" 2>/dev/null
    bind "set show-all-if-unmodified on" 2>/dev/null
    bind "set completion-ignore-case on" 2>/dev/null
    bind "set completion-query-items 200" 2>/dev/null
    bind "set page-completions off" 2>/dev/null
fi

# ============ 性能优化 ============

# macOS 特定优化
if [[ "$OS_TYPE" == "macos" ]]; then
    # 禁用 bash 会话历史
    export SHELL_SESSION_HISTORY=0

    # 加快 Git 状态检查
    export GIT_DISCOVERY_ACROSS_FILESYSTEM=1
fi

EOF

    success "跨平台现代化配置文件生成完成"
}

# 更新shell配置文件
update_shell_config() {
    info "更新Shell配置文件..."

    if [[ "$OS" == "macos" ]]; then
        # Mac 使用 .bash_profile 和 .zshrc
        touch "$HOME/.bash_profile"
        if ! grep -q "Universal Modern Shell Configuration" "$HOME/.bash_profile"; then
            cat >> "$HOME/.bash_profile" << 'EOF'

# ============ Universal Modern Shell Configuration ============
# 跨平台现代化Shell配置 - 自动生成，请勿手动修改此部分

# 加载通用现代化配置
if [ -f ~/.config/shell/universal-config.sh ]; then
    source ~/.config/shell/universal-config.sh
fi

# 兼容 .bashrc
if [ -f ~/.bashrc ]; then
    source ~/.bashrc
fi

# ============ End Universal Configuration ============
EOF
            success "已将现代化配置添加到 .bash_profile"
        else
            info ".bash_profile 已包含现代化配置，跳过更新"
        fi

        # 不把 Universal 配置写入 .zshrc。zsh 只启用 Starship，避免
        # Oh My Zsh、compinit、bash_completion 之间互相覆盖或报错。
        info "跳过 .zshrc Universal 配置写入，后续仅启用 zsh Starship"
    else
        # Linux 使用 .bashrc
        touch "$HOME/.bashrc"
        if ! grep -q "Universal Modern Shell Configuration" "$HOME/.bashrc"; then
            cat >> "$HOME/.bashrc" << 'EOF'

# ============ Universal Modern Shell Configuration ============
# 跨平台现代化Shell配置 - 自动生成，请勿手动修改此部分

# 加载通用现代化配置
if [ -f ~/.config/shell/universal-config.sh ]; then
    source ~/.config/shell/universal-config.sh
fi

# ============ End Universal Configuration ============
EOF
            success "已将现代化配置添加到 .bashrc"
        else
            info ".bashrc 已包含现代化配置，跳过更新"
        fi
    fi
}

# 清理早期版本错误写入 .zshrc 的 Universal 块。
cleanup_zsh_universal_block() {
    local zshrc="$HOME/.zshrc"
    local tmp

    [[ -f "$zshrc" ]] || return 0

    if ! grep -q "Universal Modern Shell Configuration" "$zshrc"; then
        info ".zshrc 未发现旧 Universal 配置块，跳过清理"
        return 0
    fi

    cp "$zshrc" "$BACKUP_DIR/.zshrc.before-universal-cleanup"
    tmp="$(mktemp)"
    awk '
        $0 == "# ============ Universal Modern Shell Configuration ============" { skip=1; next }
        $0 == "# ============ End Universal Configuration ============" { skip=0; next }
        !skip { print }
    ' "$zshrc" > "$tmp"
    mv "$tmp" "$zshrc"
    success "已从 .zshrc 移除旧 Universal 配置块"
}

# 在 zsh 末尾启用 Starship，让它覆盖 Oh My Zsh 主题。
enable_starship_zsh() {
    local zshrc="$HOME/.zshrc"
    local tmp
    local start="# >>> starship-zsh >>>"
    local end="# <<< starship-zsh <<<"

    [[ -f "$zshrc" ]] || return 0

    if ! command -v starship >/dev/null 2>&1; then
        warning "未找到 starship，跳过 zsh Starship 初始化"
        return 0
    fi

    cp "$zshrc" "$BACKUP_DIR/.zshrc.before-starship-zsh"
    tmp="$(mktemp)"
    awk -v start="$start" -v end="$end" '
        $0 == start { skip=1; next }
        $0 == end { skip=0; next }
        !skip { print }
    ' "$zshrc" > "$tmp"
    mv "$tmp" "$zshrc"

    cat >> "$zshrc" << EOF

$start
# Starship prompt. Keep this near the end so it overrides Oh My Zsh themes.
if command -v starship >/dev/null 2>&1; then
  eval "\$(starship init zsh)"
fi
$end
EOF

    success "已在 .zshrc 末尾启用 Starship"
}

# 生成通用Starship配置
generate_universal_starship_config() {
    info "生成跨平台Starship配置..."

    mkdir -p "$HOME/.config"

    local starship_config="$HOME/.config/starship.toml"
    local starship_format
    starship_format='format = """
[╭─](bold blue)$os$username[@](bold blue)$hostname[ in ](bold blue)$directory$git_branch$git_status$nodejs$python$rust$golang$java$docker_context$package$cmd_duration
[╰─](bold blue)$character"""'

    if [ -f "$HOME/.config/starship.toml" ]; then
        local starship_backup="$starship_config.bak-$(date +%Y%m%d_%H%M%S)"
        cp "$starship_config" "$starship_backup"
        info "已备份现有 Starship 配置: $starship_backup"

        if grep -q '^format[[:space:]]*=[[:space:]]*"""' "$starship_config"; then
            awk -v replacement="$starship_format" '
                BEGIN { skipping=0 }
                /^format[[:space:]]*=[[:space:]]*"""/ {
                    print replacement
                    if ($0 ~ /"""[[:space:]]*$/ && $0 !~ /^format[[:space:]]*=[[:space:]]*"""[[:space:]]*$/) {
                        skipping=0
                    } else {
                        skipping=1
                    }
                    next
                }
                skipping {
                    if ($0 ~ /"""[[:space:]]*$/) skipping=0
                    next
                }
                { print }
            ' "$starship_config" > "${starship_config}.tmp" && mv "${starship_config}.tmp" "$starship_config"
            success "已更新 Starship 两行提示符 format"
        else
            {
                printf '%s\n\n' "$starship_format"
                cat "$starship_config"
            } > "${starship_config}.tmp" && mv "${starship_config}.tmp" "$starship_config"
            success "已追加 Starship 两行提示符 format"
        fi
        return 0
    fi

    cat > "$HOME/.config/starship.toml" << 'EOF'
# Starship 跨平台配置文件

format = """
[╭─](bold blue)$os$username[@](bold blue)$hostname[ in ](bold blue)$directory$git_branch$git_status$nodejs$python$rust$golang$java$docker_context$package$cmd_duration
[╰─](bold blue)$character"""

[os]
disabled = false
style = "bg:blue fg:white"

[os.symbols]
Macos = "🍎 "
Ubuntu = "🐧 "
Debian = "🌀 "
Redhat = "🎩 "
CentOS = "💠 "
Fedora = "🎓 "
Arch = "🏛️ "
openSUSE = "🦎 "
Linux = "🐧 "

[username]
style_user = "green bold"
style_root = "red bold"
format = "[$user]($style)"
disabled = false
show_always = true

[hostname]
ssh_only = false
format = "[$hostname](bold red)"
disabled = false
trim_at = ""

[directory]
truncation_length = 3
truncation_symbol = "…/"
style = "bold cyan"
read_only = " 🔒"

[character]
success_symbol = "[❯](purple)"
error_symbol = "[❯](red)"
vicmd_symbol = "[❮](green)"

[git_branch]
symbol = "🌱 "
format = "[$symbol$branch]($style) "
style = "bright-green"

[git_status]
format = '[\[$all_status$ahead_behind\]]($style) '
style = "cyan"

[cmd_duration]
format = " took [$duration]($style)"
style = "yellow"
min_time = 2000

[nodejs]
symbol = "⬢ "
style = "bold green"

[python]
symbol = "🐍 "
style = "bold yellow"

[rust]
symbol = "🦀 "
style = "bold red"

[golang]
symbol = "🐹 "
style = "bold cyan"

[java]
symbol = "☕ "
style = "bold red"

[docker_context]
symbol = "🐳 "
style = "bold blue"

[package]
symbol = "📦 "
style = "bold yellow"

[battery]
full_symbol = "🔋 "
charging_symbol = "⚡️ "
discharging_symbol = "💀 "

[[battery.display]]
threshold = 10
style = "bold red"

[[battery.display]]
threshold = 30
style = "bold yellow"

[memory_usage]
disabled = false
threshold = 70
symbol = " "
style = "bold dimmed green"
EOF

    success "跨平台Starship配置生成完成"
}

# 设置权限
set_permissions() {
    info "设置文件权限..."
    chmod +x "$CONFIG_DIR/universal-config.sh"
    success "权限设置完成"
}

# 显示安装结果
show_result() {
    success "=========================================="
    success "🎉 跨平台现代化 Shell 配置安装完成！"
    success "=========================================="
    echo
    info "检测到的系统: $OS ($PACKAGE_MANAGER)"
    echo
    info "安装的工具和功能："
    echo "✅ 智能系统检测和适配"

    if [[ "$OS" == "macos" ]]; then
        echo "✅ Homebrew 包管理器支持"
        echo "✅ Apple Silicon & Intel Mac 适配"
        echo "✅ Nerd 字体支持"
    fi

    echo "✅ 现代化文件查看 (eza/exa, bat)"
    echo "✅ 智能目录导航 (zoxide)"
    echo "✅ 模糊搜索 (fzf)"
    echo "✅ 高级搜索 (ripgrep, fd)"
    echo "✅ 历史增强 (mcfly)"
    echo "✅ 美化提示符 (starship)"

    if [[ "$OS" == "macos" ]]; then
        echo "✅ 系统监控 (htop, procs, dust)"
        echo "✅ Mac 特定功能和别名"
    fi

    echo "✅ Git 集成和别名"
    echo "✅ 跨平台实用函数"
    echo "✅ 智能别名系统"
    echo
    info "配置文件位置："
    echo "📁 主配置: ~/.config/shell/universal-config.sh"
    echo "📁 备份: $BACKUP_DIR"
    echo "📁 日志: $INSTALL_LOG"
    echo "📁 Starship: ~/.config/starship.toml"
    echo
    warning "请运行以下命令应用新配置："

    if [[ -n "${ZSH_VERSION:-}" ]] || [[ -f "$HOME/.zshrc" ]]; then
        echo "exec zsh -l"
    elif [[ "$OS" == "macos" ]]; then
        echo "source ~/.bash_profile"
    else
        echo "source ~/.bashrc"
    fi

    echo
    info "或者重新打开终端窗口"
    echo
    info "使用 'show_tools' 命令查看所有功能"
    echo
    success "享受你的跨平台现代化终端体验！ 🚀"
}

# 卸载函数
uninstall() {
    info "开始卸载跨平台现代化Bash配置..."

    # 恢复备份
    read -p "请输入要恢复的备份目录名称 (格式: .config_backup_YYYYMMDD_HHMMSS): " backup_name
    RESTORE_DIR="$HOME/$backup_name"

    if [[ -d "$RESTORE_DIR" ]]; then
        info "恢复配置备份..."
        local files_to_restore
        if [[ "$OS" == "macos" ]]; then
            files_to_restore=(".bashrc" ".bash_aliases" ".bash_profile" ".profile" ".inputrc" ".dircolors" ".zshrc")
        else
            files_to_restore=(".bashrc" ".bash_aliases" ".bash_profile" ".profile" ".inputrc" ".dircolors")
        fi

        for file in "${files_to_restore[@]}"; do
            if [[ -f "$RESTORE_DIR/$file" ]]; then
                cp "$RESTORE_DIR/$file" "$HOME/"
                info "恢复 $file"
            fi
        done
    else
        warning "备份目录不存在，跳过恢复"
    fi

    # 删除配置目录
    if [[ -d "$CONFIG_DIR" ]]; then
        rm -rf "$CONFIG_DIR"
        info "删除配置目录"
    fi

    # 删除Starship配置
    if [[ -f "$HOME/.config/starship.toml" ]]; then
        rm -f "$HOME/.config/starship.toml"
        info "删除Starship配置"
    fi

    success "卸载完成"
}

# 测试模式
test_compatibility() {
    info "开始兼容性测试..."

    echo -e "${CYAN}系统信息:${NC}"
    echo "操作系统: $OS_TYPE"
    echo "包管理器: $PACKAGE_MANAGER"

    if [[ "$OS" == "macos" ]]; then
        echo "Mac架构: $MAC_ARCH"
    fi

    echo
    echo -e "${CYAN}工具检查:${NC}"

    local tools=("curl" "git" "fzf" "zoxide" "bat" "rg" "fd" "starship" "mcfly")
    if [[ "$OS" == "macos" ]]; then
        tools+=("exa" "eza" "htop" "tree" "jq" "procs" "dust")
    else
        tools+=("exa")
    fi

    for tool in "${tools[@]}"; do
        if command -v $tool &> /dev/null; then
            echo "✅ $tool: $(command -v $tool)"
        else
            echo "❌ $tool: 未安装"
        fi
    done

    echo
    echo -e "${CYAN}配置文件检查:${NC}"

    if [[ -f "$CONFIG_DIR/universal-config.sh" ]]; then
        echo "✅ 通用配置: $CONFIG_DIR/universal-config.sh"
    else
        echo "❌ 通用配置: 未找到"
    fi

    if [[ -f "$HOME/.config/starship.toml" ]]; then
        echo "✅ Starship配置: $HOME/.config/starship.toml"
    else
        echo "❌ Starship配置: 未找到"
    fi

    echo
    success "兼容性测试完成"
}

# 显示帮助信息
show_help() {
    echo -e "${BLUE}跨平台现代化 Shell 配置安装脚本${NC}"
    echo
    echo -e "${GREEN}支持的系统:${NC}"
    echo "  • macOS (Apple Silicon & Intel)"
    echo "  • Ubuntu/Debian (APT)"
    echo "  • CentOS/RHEL/Fedora (YUM/DNF)"
    echo "  • Arch Linux (Pacman)"
    echo "  • openSUSE (Zypper)"
    echo
    echo -e "${GREEN}用法:${NC}"
    echo "  $0 [命令]"
    echo
    echo -e "${GREEN}可用命令:${NC}"
    echo "  install     - 安装现代化配置 (默认)"
    echo "  uninstall   - 卸载并恢复原配置"
    echo "  backup      - 仅创建当前配置备份"
    echo "  starship    - 仅配置 Starship 两行提示符并启用 zsh"
    echo "  fix-zsh     - 仅清理旧版 zsh 错误配置并启用 Starship"
    echo "  hostname    - 可选：将 hostname 设置为外网 IP"
    echo "  test        - 运行兼容性测试"
    echo "  help        - 显示此帮助信息"
    echo
    echo -e "${GREEN}特性:${NC}"
    echo "  • 🔍 智能系统检测"
    echo "  • 📦 跨平台包管理"
    echo "  • 🎨 Starship 两行提示符"
    echo "  • 🧹 自动清理旧版 zsh 错误配置块"
    echo "  • ⚡ 现代化工具集成"
    echo "  • 🛡️ 安全备份机制"
}

# 主函数
main() {
    clear
    echo -e "${BLUE}"
    echo "=========================================="
    echo "    跨平台现代化 Shell 配置安装脚本"
    echo "  Universal Modern Shell Configuration"
    echo "    Version 2.0.0 (Universal)"
    echo "=========================================="
    echo -e "${NC}"

    # 解析命令行参数
    case "${1:-install}" in
        "install")
            detect_system
            check_dependencies
            create_backup
            install_universal_tools
            generate_universal_config
            update_shell_config
            generate_universal_starship_config
            cleanup_zsh_universal_block
            enable_starship_zsh
            set_permissions
            show_result
            ;;
        "uninstall")
            detect_system
            uninstall
            ;;
        "backup")
            detect_system
            create_backup
            success "配置备份完成: $BACKUP_DIR"
            ;;
        "starship")
            detect_system
            create_backup
            generate_universal_starship_config
            enable_starship_zsh
            success "Starship 配置完成"
            ;;
        "fix-zsh")
            detect_system
            create_backup
            cleanup_zsh_universal_block
            enable_starship_zsh
            success "zsh 启动配置修复完成"
            ;;
        "hostname")
            detect_system
            setup_hostname_as_ip
            ;;
        "test")
            detect_system
            test_compatibility
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            error "未知命令: $1"
            echo
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
