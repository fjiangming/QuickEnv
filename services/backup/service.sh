#!/bin/bash
# =============================================================================
# 备份服务模块
# 功能: 部署 backup-all.sh 脚本 + 配置 cron 定时任务
# 依赖: syncthing (备份输出目录在 ~/syncthing/backups/)
# =============================================================================

service_name()  { echo "backup"; }
service_deps()  { echo "syncthing"; }

service_install() {
    log_step "部署备份服务"

    local quickenv_root
    quickenv_root=$(get_quickenv_root)

    # 创建目录
    mkdir -p "$BACKUP_SCRIPTS"
    mkdir -p "$BACKUP_ROOT"

    # 复制备份脚本
    cp "${quickenv_root}/services/backup/backup-all.sh" "${BACKUP_SCRIPTS}/backup-all.sh"
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

    log_success "备份服务部署完成"
}

service_restore() {
    # 备份服务本身不需要恢复数据
    log_info "备份服务无需恢复数据"
}

service_status() {
    local ok=true

    # 检查脚本
    if [ -x "${BACKUP_SCRIPTS}/backup-all.sh" ]; then
        log_success "备份脚本: 已就绪"
    else
        log_error "备份脚本: 未找到或无执行权限"
        ok=false
    fi

    # 检查 cron
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
    # 手动执行一次备份测试
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
