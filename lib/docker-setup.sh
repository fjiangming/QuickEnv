#!/bin/bash
# =============================================================================
# Docker + Docker Compose 一键安装
# 支持: CentOS/RHEL/Rocky/Alma, Ubuntu/Debian
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

install_docker() {
    log_step "安装 Docker"

    # 已安装则跳过
    if check_docker; then
        local ver
        ver=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
        log_success "Docker 已安装 (版本: $ver)"
        return 0
    fi

    local os_type
    os_type=$(detect_os)

    case "$os_type" in
        rhel)
            _install_docker_rhel
            ;;
        debian)
            _install_docker_debian
            ;;
        *)
            log_warn "无法自动安装 Docker，尝试使用官方一键脚本..."
            _install_docker_official
            ;;
    esac

    # 启动并设置开机自启
    systemctl enable --now docker
    log_success "Docker 安装完成"
}

_install_docker_rhel() {
    log_info "检测到 RHEL 系发行版，使用 dnf 安装..."

    # 移除旧版本
    dnf remove -y docker docker-client docker-client-latest \
        docker-common docker-latest docker-latest-logrotate \
        docker-logrotate docker-engine 2>/dev/null || true

    # 安装依赖
    dnf install -y dnf-plugins-core

    # 添加 Docker 官方源
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 2>/dev/null || \
        dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/centos/docker-ce.repo 2>/dev/null

    # 安装 Docker
    dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
}

_install_docker_debian() {
    log_info "检测到 Debian 系发行版，使用 apt 安装..."

    # 移除旧版本
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    # 安装依赖
    apt-get update -qq
    apt-get install -y ca-certificates curl gnupg lsb-release

    # 添加 Docker GPG 密钥
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # 添加 Docker 源
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    # 安装 Docker
    apt-get update -qq
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
}

_install_docker_official() {
    curl -fsSL https://get.docker.com | sh
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_docker
fi
