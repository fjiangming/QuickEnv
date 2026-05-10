#!/bin/bash
# =============================================================================
# new-api 服务模块
# 运行方式: Docker
# 端口: 3000
# 部署目录: ~/new-api/
# =============================================================================

service_name()  { echo "new-api"; }
service_deps()  { echo ""; }

SERVICE_DIR="${DEPLOY_NEWAPI}"

service_install() {
    log_step "部署 new-api"

    # 检查容器是否已运行
    if docker ps --format '{{.Names}}' | grep -q '^new-api$'; then
        log_success "new-api 已在运行"
        return 0
    fi

    mkdir -p "$SERVICE_DIR"

    # 复制 docker-compose.yml
    local quickenv_root
    quickenv_root=$(get_quickenv_root)
    cp "${quickenv_root}/services/new-api/docker-compose.yml" "${SERVICE_DIR}/docker-compose.yml"

    # 启动
    cd "$SERVICE_DIR"
    docker compose up -d

    # 放行端口
    firewall_allow "$PORT_NEWAPI"

    log_success "new-api 部署完成"
}

service_restore() {
    local restore_dir="$1"
    local backup_dir="${restore_dir}/new-api"

    if [ ! -d "$backup_dir" ]; then
        log_warn "备份中未找到 new-api 数据，跳过恢复"
        return 0
    fi

    log_step "恢复 new-api 数据"

    # 如果备份中有 docker-compose.yml，优先用备份的
    if [ -f "${backup_dir}/docker-compose.yml" ]; then
        cp "${backup_dir}/docker-compose.yml" "${SERVICE_DIR}/docker-compose.yml"
        log_success "恢复 docker-compose.yml"
    fi

    # 重启以应用恢复的配置
    cd "$SERVICE_DIR"
    docker compose down 2>/dev/null || true
    docker compose up -d

    log_success "new-api 恢复完成"
}

service_status() {
    if docker ps --format '{{.Names}}' | grep -q '^new-api$'; then
        log_success "new-api: 运行中 (端口: $PORT_NEWAPI)"
        return 0
    else
        log_error "new-api: 未运行"
        return 1
    fi
}

service_verify() {
    if wait_for_port "$PORT_NEWAPI" 15; then
        log_success "new-api 端口 $PORT_NEWAPI 已就绪"
    else
        log_warn "new-api 端口 $PORT_NEWAPI 未响应"
    fi
}
