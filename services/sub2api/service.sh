#!/bin/bash
# =============================================================================
# sub2api 服务模块
# 运行方式: Docker (3个容器: sub2api + PostgreSQL + Redis)
# 端口: 9000 (宿主机) -> 8080 (容器内)
# 部署目录: ~/sub2api-deploy/
# =============================================================================

service_name()  { echo "sub2api"; }
service_deps()  { echo ""; }

SERVICE_DIR="${DEPLOY_SUB2API}"

service_install() {
    log_step "部署 sub2api"

    # 检查容器是否已运行
    if docker ps --format '{{.Names}}' | grep -q '^sub2api$'; then
        log_success "sub2api 已在运行"
        return 0
    fi

    mkdir -p "$SERVICE_DIR"
    mkdir -p "${SERVICE_DIR}/data"
    mkdir -p "${SERVICE_DIR}/postgres_data"
    mkdir -p "${SERVICE_DIR}/redis_data"

    # 复制 docker-compose.yml
    local quickenv_root
    quickenv_root=$(get_quickenv_root)
    cp "${quickenv_root}/services/sub2api/docker-compose.yml" "${SERVICE_DIR}/docker-compose.yml"

    # 初始化 .env（如果不存在则从模板生成）
    if [ ! -f "${SERVICE_DIR}/.env" ]; then
        if [ -f "${quickenv_root}/services/sub2api/.env.template" ]; then
            log_info "从模板初始化 .env ..."
            cp "${quickenv_root}/services/sub2api/.env.template" "${SERVICE_DIR}/.env"

            # 自动生成安全密钥替换占位符
            local pg_pass jwt_secret totp_key admin_pass
            pg_pass=$(openssl rand -hex 32)
            jwt_secret=$(openssl rand -hex 32)
            totp_key=$(openssl rand -hex 32)
            admin_pass=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)

            sed -i "s/^POSTGRES_PASSWORD=CHANGE_ME.*/POSTGRES_PASSWORD=${pg_pass}/" "${SERVICE_DIR}/.env"
            sed -i "s/^JWT_SECRET=CHANGE_ME.*/JWT_SECRET=${jwt_secret}/" "${SERVICE_DIR}/.env"
            sed -i "s/^TOTP_ENCRYPTION_KEY=CHANGE_ME.*/TOTP_ENCRYPTION_KEY=${totp_key}/" "${SERVICE_DIR}/.env"
            sed -i "s/^ADMIN_PASSWORD=CHANGE_ME.*/ADMIN_PASSWORD=${admin_pass}/" "${SERVICE_DIR}/.env"

            log_success ".env 已生成（密钥已自动填充）"
            log_warn "管理员密码: ${admin_pass}  ← 请记录！"
        else
            log_error ".env 模板不存在，sub2api 无法启动"
            return 1
        fi
    fi

    # 启动
    cd "$SERVICE_DIR"
    docker compose up -d

    # 放行端口
    firewall_allow "$PORT_SUB2API"

    log_success "sub2api 部署完成"
}

service_restore() {
    local restore_dir="$1"
    local backup_dir="${restore_dir}/sub2api"

    if [ ! -d "$backup_dir" ]; then
        log_warn "备份中未找到 sub2api 数据，跳过恢复"
        return 0
    fi

    log_step "恢复 sub2api 数据"

    # 先停止所有容器，避免数据冲突
    cd "$SERVICE_DIR" 2>/dev/null && docker compose down 2>/dev/null || true

    mkdir -p "$SERVICE_DIR"

    # 恢复 .env（必须在启动 PG 之前，因为包含数据库密码）
    if [ -f "${backup_dir}/.env" ]; then
        cp "${backup_dir}/.env" "${SERVICE_DIR}/.env"
        log_success "恢复 .env"
    fi

    # 恢复 docker-compose.yml
    if [ -f "${backup_dir}/docker-compose.yml" ]; then
        cp "${backup_dir}/docker-compose.yml" "${SERVICE_DIR}/docker-compose.yml"
        log_success "恢复 docker-compose.yml"
    fi

    # 恢复 data/ 目录
    if [ -d "${backup_dir}/data" ]; then
        rm -rf "${SERVICE_DIR}/data"
        cp -r "${backup_dir}/data" "${SERVICE_DIR}/"
        log_success "恢复 data/"
    fi

    # ⚠️ 清空 PG/Redis 数据目录，避免 deploy 阶段用新密码初始化的数据
    #    与恢复的 .env 中旧密码不匹配导致连接失败
    log_info "清空数据库数据目录（将从 SQL 备份重建）..."
    rm -rf "${SERVICE_DIR}/postgres_data"
    rm -rf "${SERVICE_DIR}/redis_data"
    mkdir -p "${SERVICE_DIR}/postgres_data"
    mkdir -p "${SERVICE_DIR}/redis_data"

    # 启动 PostgreSQL 和 Redis（使用恢复后的 .env 中的密码初始化）
    cd "$SERVICE_DIR"
    docker compose up -d postgres redis 2>/dev/null || \
    docker compose up -d sub2api-postgres sub2api-redis 2>/dev/null || true
    log_info "等待 PostgreSQL 初始化完成..."
    sleep 15

    # 导入数据库
    if [ -f "${backup_dir}/sub2api-database.sql" ]; then
        log_info "导入 PostgreSQL 数据库..."
        cat "${backup_dir}/sub2api-database.sql" | \
            docker exec -i sub2api-postgres psql -U sub2api -d sub2api 2>/dev/null && \
            log_success "PostgreSQL 数据库导入完成" || \
            log_warn "数据库导入出现警告（可能是正常的）"
    fi

    # 启动 sub2api
    docker compose up -d
    firewall_allow "$PORT_SUB2API"

    log_success "sub2api 恢复完成"
}

service_status() {
    local all_ok=true

    if docker ps --format '{{.Names}}' | grep -q '^sub2api$'; then
        log_success "sub2api: 运行中 (端口: $PORT_SUB2API)"
    else
        log_error "sub2api: 未运行"
        all_ok=false
    fi

    if docker ps --format '{{.Names}}' | grep -q '^sub2api-postgres$'; then
        log_success "sub2api-postgres: 运行中"
    else
        log_error "sub2api-postgres: 未运行"
        all_ok=false
    fi

    if docker ps --format '{{.Names}}' | grep -q '^sub2api-redis$'; then
        log_success "sub2api-redis: 运行中"
    else
        log_error "sub2api-redis: 未运行"
        all_ok=false
    fi

    $all_ok
}

service_verify() {
    if wait_for_port "$PORT_SUB2API" 20; then
        log_success "sub2api 端口 $PORT_SUB2API 已就绪"
    else
        log_warn "sub2api 端口 $PORT_SUB2API 未响应"
    fi
}
