#!/bin/bash
# =============================================================================
# Nginx 服务模块
# 运行方式: systemd（非 Docker）
# 端口: 80
# =============================================================================

service_name()  { echo "nginx"; }
service_deps()  { echo ""; }

service_install() {
    log_step "安装 Nginx"

    # 检查是否已安装
    if command -v nginx &>/dev/null; then
        log_success "Nginx 已安装"
        if ! systemctl is-active nginx &>/dev/null; then
            systemctl enable --now nginx
            log_info "已启动 Nginx"
        fi
        return 0
    fi

    # 安装
    pkg_install nginx

    # 启动并设置开机自启
    systemctl enable --now nginx

    # 放行端口
    firewall_allow 80
    firewall_allow 443

    log_success "Nginx 安装完成"
}

service_restore() {
    local restore_dir="$1"
    local backup_dir="${restore_dir}/nginx"

    if [ ! -d "$backup_dir" ]; then
        log_warn "备份中未找到 Nginx 配置，跳过恢复"
        return 0
    fi

    log_step "恢复 Nginx 配置"

    # 恢复主配置
    if [ -f "${backup_dir}/nginx.conf" ]; then
        cp "${backup_dir}/nginx.conf" /etc/nginx/nginx.conf
        log_success "恢复 nginx.conf"
    fi

    # 恢复 conf.d/ 目录（反向代理规则）
    if [ -d "${backup_dir}/conf.d" ]; then
        cp -r "${backup_dir}/conf.d/"* /etc/nginx/conf.d/ 2>/dev/null || true
        log_success "恢复 conf.d/ 反代配置"
    fi

    # 测试配置
    if nginx -t 2>/dev/null; then
        systemctl reload nginx
        log_success "Nginx 配置测试通过并重载"
    else
        log_error "Nginx 配置测试失败，请手动检查"
    fi
}

service_status() {
    if systemctl is-active nginx &>/dev/null; then
        log_success "nginx: 运行中 (端口: 80)"
        return 0
    else
        log_error "nginx: 未运行"
        return 1
    fi
}

service_verify() {
    if wait_for_port 80 10; then
        log_success "Nginx 端口 80 已就绪"
    else
        log_warn "Nginx 端口 80 未响应"
    fi
}
