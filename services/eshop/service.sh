#!/bin/bash
# =============================================================================
# eshop (Dujiao-Next) 服务模块
# 运行方式: Docker (3个容器: dujiao-aio + PostgreSQL + Redis)
# 端口: 2000 (宿主机) -> 80 (容器内)
# 部署目录: ~/eshop/
# =============================================================================

service_name()  { echo "eshop"; }
service_deps()  { echo ""; }

SERVICE_DIR="${DEPLOY_ESHOP}"

service_install() {
    log_step "部署 eshop (Dujiao-Next)"

    # 检查容器是否已运行
    if docker ps --format '{{.Names}}' | grep -q '^dujiao-aio$'; then
        log_success "eshop 已在运行"
        return 0
    fi

    mkdir -p "$SERVICE_DIR"
    mkdir -p "${SERVICE_DIR}/uploads"
    mkdir -p "${SERVICE_DIR}/logs"
    mkdir -p "${SERVICE_DIR}/pg_data"
    mkdir -p "${SERVICE_DIR}/redis_data"

    # 复制 docker-compose.yml
    local quickenv_root
    quickenv_root=$(get_quickenv_root)
    cp "${quickenv_root}/services/eshop/docker-compose.yml" "${SERVICE_DIR}/docker-compose.yml"

    # 初始化 config.yml（如果不存在则从模板复制）
    if [ ! -f "${SERVICE_DIR}/config.yml" ]; then
        if [ -f "${quickenv_root}/services/eshop/config.yml" ]; then
            log_info "从模板初始化 config.yml ..."
            cp "${quickenv_root}/services/eshop/config.yml" "${SERVICE_DIR}/config.yml"

            # 自动生成安全密钥替换默认值
            local pg_pass jwt_secret user_jwt_secret
            pg_pass=$(openssl rand -hex 16)
            jwt_secret=$(openssl rand -hex 24)
            user_jwt_secret=$(openssl rand -hex 24)

            sed -i "s/secret_password/${pg_pass}/g" "${SERVICE_DIR}/config.yml"
            sed -i "s/b3a4f8e7d2c1945a8f0c3d2e1b4a5f6e8d7c9b0a1f2e3d4c/${jwt_secret}/" "${SERVICE_DIR}/config.yml"
            sed -i "s/d9c8b7a6e5f4d3c2b1a0f9e8d7c6b5a4f3e2d1c0b9a8f7e6/${user_jwt_secret}/" "${SERVICE_DIR}/config.yml"

            # 同步数据库密码到 docker-compose
            sed -i "s/secret_password/${pg_pass}/g" "${SERVICE_DIR}/docker-compose.yml"

            log_success "config.yml 已生成（密钥已自动填充）"
        else
            log_warn "config.yml 模板不存在，eshop 将使���容器默认配置"
        fi
    fi

    # 启动
    cd "$SERVICE_DIR"
    docker compose up -d

    # 放行端口
    firewall_allow "$PORT_ESHOP"

    log_success "eshop 部署完成"
}

service_restore() {
    local restore_dir="$1"
    local backup_dir="${restore_dir}/eshop"

    if [ ! -d "$backup_dir" ]; then
        log_warn "备份中未找到 eshop 数据，跳过恢复"
        return 0
    fi

    log_step "恢复 eshop 数据"

    # 先停止所有容器，避免数据冲突
    cd "$SERVICE_DIR" 2>/dev/null && docker compose down 2>/dev/null || true

    mkdir -p "$SERVICE_DIR"

    # 恢复 config.yml
    if [ -f "${backup_dir}/config.yml" ]; then
        cp "${backup_dir}/config.yml" "${SERVICE_DIR}/config.yml"
        log_success "恢复 config.yml"
    fi

    # 恢复 docker-compose.yml
    if [ -f "${backup_dir}/docker-compose.yml" ]; then
        cp "${backup_dir}/docker-compose.yml" "${SERVICE_DIR}/docker-compose.yml"
        log_success "恢复 docker-compose.yml"
    fi

    # 恢复 uploads/ 目录
    if [ -d "${backup_dir}/uploads" ]; then
        rm -rf "${SERVICE_DIR}/uploads"
        cp -r "${backup_dir}/uploads" "${SERVICE_DIR}/"
        log_success "恢复 uploads/"
    fi

    # 清空 PG/Redis 数据目录，从 SQL 备份重建
    log_info "清空数据库数据目录（将从 SQL 备份重建）..."
    rm -rf "${SERVICE_DIR}/pg_data"
    rm -rf "${SERVICE_DIR}/redis_data"
    mkdir -p "${SERVICE_DIR}/pg_data"
    mkdir -p "${SERVICE_DIR}/redis_data"

    # 启动 PostgreSQL 和 Redis
    cd "$SERVICE_DIR"
    docker compose up -d dujiao-db dujiao-redis 2>/dev/null || true
    log_info "等待 PostgreSQL 初始化完成..."
    sleep 15

    # 导入数据库
    if [ -f "${backup_dir}/eshop-database.sql" ]; then
        log_info "导入 PostgreSQL 数据库..."
        cat "${backup_dir}/eshop-database.sql" | \
            docker exec -i dujiao-db psql -U dujiao -d dujiao_db 2>/dev/null && \
            log_success "PostgreSQL 数据库导入完成" || \
            log_warn "数据库导入出现警告（可能是正常的）"
    fi

    # 启动全部容器
    docker compose up -d
    firewall_allow "$PORT_ESHOP"

    log_success "eshop 恢复完成"
}

service_status() {
    local all_ok=true

    if docker ps --format '{{.Names}}' | grep -q '^dujiao-aio$'; then
        log_success "eshop (dujiao-aio): 运行中 (端口: $PORT_ESHOP)"
    else
        log_error "eshop (dujiao-aio): 未运行"
        all_ok=false
    fi

    if docker ps --format '{{.Names}}' | grep -q '^dujiao-db$'; then
        log_success "dujiao-db: 运行中"
    else
        log_error "dujiao-db: 未运行"
        all_ok=false
    fi

    if docker ps --format '{{.Names}}' | grep -q '^dujiao-redis$'; then
        log_success "dujiao-redis: 运行中"
    else
        log_error "dujiao-redis: 未运行"
        all_ok=false
    fi

    $all_ok
}

service_verify() {
    if wait_for_port "$PORT_ESHOP" 20; then
        log_success "eshop 端口 $PORT_ESHOP 已就绪"
    else
        log_warn "eshop 端口 $PORT_ESHOP 未响应"
    fi
}
