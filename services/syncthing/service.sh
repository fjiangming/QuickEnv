#!/bin/bash
# =============================================================================
# Syncthing + 备份 服务模块
# 运行方式: Docker (Syncthing) + cron (备份)
# 端口: 8384 (Web UI), 22000 (同步), 21027 (发现)
# 部署目录: ~/syncthing/
# 备份脚本: ~/syncthing/scripts/backup-all.sh
# 备份输出: ~/syncthing/backups/
#
# 说明: Syncthing 和备份服务始终一起部署，备份数据通过 Syncthing 同步到本地
# =============================================================================

service_name()  { echo "syncthing"; }
service_deps()  { echo ""; }

SERVICE_DIR="${DEPLOY_SYNCTHING}"

service_install() {
    log_step "部署 Syncthing + 备份服务"

    local quickenv_root
    quickenv_root=$(get_quickenv_root)

    # ======================== Syncthing ========================

    # 检查容器是否已运行
    if docker ps --format '{{.Names}}' | grep -q '^syncthing$'; then
        log_success "Syncthing 已在运行"
    else
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
    fi

    # ======================== 备份服务 ========================

    log_step "部署备份服务"

    # 创建目录
    mkdir -p "$BACKUP_SCRIPTS"
    mkdir -p "$BACKUP_ROOT"

    # 复制备份脚本
    cp "${quickenv_root}/services/syncthing/backup/backup-all.sh" "${BACKUP_SCRIPTS}/backup-all.sh"
    chmod +x "${BACKUP_SCRIPTS}/backup-all.sh"

    # 注入 QUICKENV_ROOT 使脚本能找到 config.env
    sed -i "2i\\QUICKENV_ROOT=\"${quickenv_root}\"" "${BACKUP_SCRIPTS}/backup-all.sh"

    log_success "备份脚本已部署到 ${BACKUP_SCRIPTS}/backup-all.sh"

    # 配置 cron
    local cron_line="${BACKUP_CRON_SCHEDULE} ${BACKUP_SCRIPTS}/backup-all.sh >> ${BACKUP_ROOT}/cron.log 2>&1"

    # 检查是否已有此 cron 任务
    if crontab -l 2>/dev/null | grep -qF "backup-all.sh"; then
        log_info "cron 定时任务已存在，跳过"
    else
        (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
        log_success "cron 定时任务已配置: ${BACKUP_CRON_SCHEDULE}"
    fi

    log_success "Syncthing + 备份服务部署完成"
}

service_restore() {
    local restore_dir="$1"
    # Syncthing 本身不需要从备份恢复（它就是备份工具）
    # 备份服务也不需要恢复数据
    log_info "Syncthing 已部署，请手动配对 Windows 设备（参考 syncthing_guide.md 第 4、5 章）"
    log_info "备份服务无需恢复数据"
}

service_status() {
    local ok=true

    # Syncthing 容器状态
    if docker ps --format '{{.Names}}' | grep -q '^syncthing$'; then
        log_success "syncthing: 运行中 (Web UI 端口: $PORT_SYNCTHING_UI)"
    else
        log_error "syncthing: 未运行"
        ok=false
    fi

    # 备份脚本状态
    if [ -x "${BACKUP_SCRIPTS}/backup-all.sh" ]; then
        log_success "备份脚本: 已就绪"
    else
        log_error "备份脚本: 未找到或无执行权限"
        ok=false
    fi

    # cron 状态
    if crontab -l 2>/dev/null | grep -qF "backup-all.sh"; then
        local schedule
        schedule=$(crontab -l 2>/dev/null | grep "backup-all.sh" | awk '{print $1,$2,$3,$4,$5}')
        log_success "cron 定时任务: 已配置 ($schedule)"
    else
        log_error "cron 定时任务: 未配置"
        ok=false
    fi

    $ok
}

service_verify() {
    # 验证 Syncthing
    if wait_for_port "$PORT_SYNCTHING_UI" 15; then
        log_success "Syncthing Web UI 端口 $PORT_SYNCTHING_UI 已就绪"
    else
        log_warn "Syncthing 端口 $PORT_SYNCTHING_UI 未响应"
    fi

    # 执行一次备份测试
    log_info "执行一次备份测试..."
    if "${BACKUP_SCRIPTS}/backup-all.sh"; then
        log_success "备份测试成功"

        # 检查输出
        local latest
        latest=$(ls -t "${BACKUP_ROOT}"/*.tar.gz 2>/dev/null | head -1)
        if [ -n "$latest" ]; then
            local size
            size=$(du -sh "$latest" | cut -f1)
            log_success "最新备份: $(basename "$latest") ($size)"
        fi
    else
        log_warn "备份测试失败，请检查脚本"
    fi
}
