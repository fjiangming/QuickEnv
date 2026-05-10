#!/bin/bash
# =============================================================================
# Syncthing 服务模块
# 运行方式: Docker
# 端口: 8384 (Web UI), 22000 (同步), 21027 (发现)
# 部署目录: ~/syncthing/
# =============================================================================

service_name()  { echo "syncthing"; }
service_deps()  { echo ""; }

SERVICE_DIR="${DEPLOY_SYNCTHING}"

service_install() {
    log_step "部署 Syncthing"

    # 检查容器是否已运行
    if docker ps --format '{{.Names}}' | grep -q '^syncthing$'; then
        log_success "Syncthing 已在运行"
        return 0
    fi

    mkdir -p "${SERVICE_DIR}/config"
    mkdir -p "${SERVICE_DIR}/backups"
    mkdir -p "${SERVICE_DIR}/scripts"

    # 写入 docker-compose.yml
    cat > "${SERVICE_DIR}/docker-compose.yml" << 'EOF'
version: "3.8"

services:
  syncthing:
    image: lscr.io/linuxserver/syncthing:latest
    container_name: syncthing
    hostname: my-cloud-server
    environment:
      - PUID=0
      - PGID=0
      - TZ=Asia/Shanghai
    volumes:
      - ./config:/config
      - ./backups:/data/backups
    ports:
      - "8384:8384"
      - "22000:22000/tcp"
      - "22000:22000/udp"
      - "21027:21027/udp"
    restart: unless-stopped
EOF

    # 启动
    cd "$SERVICE_DIR"
    docker compose up -d

    # 放行端口
    firewall_allow "$PORT_SYNCTHING_UI"
    firewall_allow "$PORT_SYNCTHING_SYNC" tcp
    firewall_allow "$PORT_SYNCTHING_SYNC" udp
    firewall_allow "$PORT_SYNCTHING_DISCOVERY" udp

    log_success "Syncthing 部署完成"
    log_info "请访问 http://<服务器IP>:${PORT_SYNCTHING_UI} 配置设备配对"
}

service_restore() {
    local restore_dir="$1"
    # Syncthing 本身不需要从备份恢复（它就是备份工具）
    # 只需要重新配对 Windows 设备即可
    log_info "Syncthing 已部署，请手动配对 Windows 设备（参考 syncthing_guide.md 第 4、5 章）"
}

service_status() {
    if docker ps --format '{{.Names}}' | grep -q '^syncthing$'; then
        log_success "syncthing: 运行中 (Web UI 端口: $PORT_SYNCTHING_UI)"
        return 0
    else
        log_error "syncthing: 未运行"
        return 1
    fi
}

service_verify() {
    if wait_for_port "$PORT_SYNCTHING_UI" 15; then
        log_success "Syncthing Web UI 端口 $PORT_SYNCTHING_UI 已就绪"
    else
        log_warn "Syncthing 端口 $PORT_SYNCTHING_UI 未响应"
    fi
}
