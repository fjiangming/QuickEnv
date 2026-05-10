#!/bin/bash
# =============================================================================
# QuickEnv 公共函数库
# =============================================================================

# ======================== 颜色定义 ========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ======================== 日志函数 ========================
log_info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_success() { echo -e "${GREEN}[  OK]${NC}  $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[FAIL]${NC}  $1"; }
log_step()    { echo -e "\n${BOLD}${CYAN}▶ $1${NC}"; }
log_divider() { echo -e "${CYAN}────────────────────────────────────────────────${NC}"; }

log_banner() {
    echo -e "${CYAN}"
    echo "  ╔═══════════════════════════════════════════╗"
    echo "  ║        QuickEnv - 一键服务器部署           ║"
    echo "  ║        快速部署 · 一键恢复 · 灵活扩展       ║"
    echo "  ╚═══════════════════════════════════════════╝"
    echo -e "${NC}"
}

# ======================== 系统检测 ========================

# 检测操作系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            centos|rhel|rocky|alma|fedora)
                echo "rhel"
                ;;
            ubuntu|debian|linuxmint)
                echo "debian"
                ;;
            *)
                echo "unknown"
                ;;
        esac
    else
        echo "unknown"
    fi
}

# 获取包管理器
get_pkg_manager() {
    local os_type
    os_type=$(detect_os)
    case "$os_type" in
        rhel)   echo "dnf" ;;
        debian) echo "apt" ;;
        *)      echo "unknown" ;;
    esac
}

# 安装系统包（自动适配发行版）
pkg_install() {
    local pkg_mgr
    pkg_mgr=$(get_pkg_manager)
    case "$pkg_mgr" in
        dnf)
            dnf install -y "$@" 2>/dev/null || yum install -y "$@"
            ;;
        apt)
            apt-get update -qq && apt-get install -y "$@"
            ;;
        *)
            log_error "不支持的系统，请手动安装: $*"
            return 1
            ;;
    esac
}

# ======================== Docker 检测 ========================

# 检查 Docker 是否安装
check_docker() {
    if command -v docker &>/dev/null; then
        return 0
    fi
    return 1
}

# 检查 Docker Compose 是否可用
check_docker_compose() {
    if docker compose version &>/dev/null; then
        return 0
    fi
    return 1
}

# 等待 Docker 容器就绪
wait_for_container() {
    local container_name="$1"
    local max_wait="${2:-30}"
    local count=0

    while [ $count -lt "$max_wait" ]; do
        if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done
    return 1
}

# 等待端口就绪
wait_for_port() {
    local port="$1"
    local max_wait="${2:-30}"
    local count=0

    while [ $count -lt "$max_wait" ]; do
        if ss -tlnp 2>/dev/null | grep -q ":${port} " || \
           netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done
    return 1
}

# ======================== 端口检测 ========================

# 检查端口是否被占用
check_port_available() {
    local port="$1"
    if ss -tlnp 2>/dev/null | grep -q ":${port} " || \
       netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
        return 1  # 端口已占用
    fi
    return 0  # 端口可用
}

# ======================== 防火墙 ========================

# 放行端口（自动适配 firewalld/ufw）
firewall_allow() {
    local port="$1"
    local proto="${2:-tcp}"

    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port="${port}/${proto}" 2>/dev/null
        firewall-cmd --reload 2>/dev/null
    elif command -v ufw &>/dev/null; then
        ufw allow "${port}/${proto}" 2>/dev/null
    fi
}

# ======================== 工具函数 ========================

# 确认操作
confirm() {
    local msg="${1:-确定要继续吗？}"
    echo -en "${YELLOW}${msg} [y/N]: ${NC}"
    read -r reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

# 检查命令是否存在
require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "缺少必要命令: $cmd"
        return 1
    fi
    return 0
}

# 加载全局配置
load_config() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    local config_file="${script_dir}/config.env"

    if [ -f "$config_file" ]; then
        # shellcheck source=/dev/null
        source "$config_file"
    else
        log_error "找不到配置文件: $config_file"
        return 1
    fi
}

# 获取 QuickEnv 根目录
get_quickenv_root() {
    cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}
