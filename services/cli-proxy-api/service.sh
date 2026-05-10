#!/bin/bash
# =============================================================================
# cli-proxy-api (CLIProxyAPI) 服务模块
# 运行方式: Docker (network_mode: host)
# 端口: 8317 (主服务) + OAuth 回调端口 (8085/1455/54545/51121/11451)
# 部署目录: ~/cpa/
# =============================================================================

service_name()  { echo "cli-proxy-api"; }
service_deps()  { echo ""; }

SERVICE_DIR="${DEPLOY_CPA}"

service_install() {
    log_step "部署 cli-proxy-api"

    # 检查容器是否已运行
    if docker ps --format '{{.Names}}' | grep -q '^cli-proxy-api$'; then
        log_success "cli-proxy-api 已在运行"
        return 0
    fi

    mkdir -p "$SERVICE_DIR"

    # 复制 docker-compose.yml
    local quickenv_root
    quickenv_root=$(get_quickenv_root)
    cp "${quickenv_root}/services/cli-proxy-api/docker-compose.yml" "${SERVICE_DIR}/docker-compose.yml"

    # 检查核心配置文件
    if [ ! -f "${SERVICE_DIR}/config.yaml" ]; then
        log_warn "config.yaml 不存在，cli-proxy-api 可能无法正常工作"
        log_warn "请通过 --restore 从备份恢复，或手动创建"
    fi

    # 启动
    cd "$SERVICE_DIR"
    docker compose up -d

    # 放行端口（network_mode: host 下需逐个放行）
    firewall_allow "$PORT_CPA"
    firewall_allow 8085    # Gemini OAuth
    firewall_allow 1455    # OpenAI Codex OAuth
    firewall_allow 54545   # Claude OAuth
    firewall_allow 51121   # Antigravity OAuth
    firewall_allow 11451   # iFlow OAuth

    log_success "cli-proxy-api 部署完成"
}

service_restore() {
    local restore_dir="$1"
    local backup_dir="${restore_dir}/cpa"

    if [ ! -d "$backup_dir" ]; then
        log_warn "备份中未找到 cli-proxy-api 数据，跳过恢复"
        return 0
    fi

    log_step "恢复 cli-proxy-api 数据"

    mkdir -p "$SERVICE_DIR"

    # 恢复 config.yaml（API Key、路由策略等核心配置）
    if [ -f "${backup_dir}/config.yaml" ]; then
        cp "${backup_dir}/config.yaml" "${SERVICE_DIR}/config.yaml"
        log_success "恢复 config.yaml"
    fi

    # 恢复 auths/ 目录（OAuth 认证凭据，最关键）
    if [ -d "${backup_dir}/auths" ]; then
        rm -rf "${SERVICE_DIR}/auths"
        cp -r "${backup_dir}/auths" "${SERVICE_DIR}/auths"
        local auth_count
        auth_count=$(find "${SERVICE_DIR}/auths" -type f | wc -l)
        log_success "恢复 auths/ ($auth_count 个认证文件)"
    fi

    # 恢复 docker-compose.yml
    if [ -f "${backup_dir}/docker-compose.yml" ]; then
        cp "${backup_dir}/docker-compose.yml" "${SERVICE_DIR}/docker-compose.yml"
        log_success "恢复 docker-compose.yml"
    fi

    # 重启
    cd "$SERVICE_DIR"
    docker compose down 2>/dev/null || true
    docker compose up -d
    firewall_allow "$PORT_CPA"

    log_success "cli-proxy-api 恢复完成"
}

service_status() {
    if docker ps --format '{{.Names}}' | grep -q '^cli-proxy-api$'; then
        log_success "cli-proxy-api: 运行中 (端口: $PORT_CPA)"
        return 0
    else
        log_error "cli-proxy-api: 未运行"
        return 1
    fi
}

service_verify() {
    if wait_for_port "$PORT_CPA" 15; then
        log_success "cli-proxy-api 端口 $PORT_CPA 已就绪"

        # 尝试健康检查
        local resp
        resp=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${PORT_CPA}/health" 2>/dev/null || echo "000")
        if [ "$resp" = "200" ]; then
            log_success "cli-proxy-api 健康检查通过"
        fi
    else
        log_warn "cli-proxy-api 端口 $PORT_CPA 未响应"
    fi
}
