#!/bin/bash
# =============================================================================
# 3x-ui 服务模块
# 运行方式: systemd（非 Docker）
# 端口: 54321 (面板), 443 (Hysteria2 入站)
# =============================================================================

service_name()  { echo "3x-ui"; }
service_deps()  { echo ""; }

service_install() {
    log_step "安装 3x-ui"

    # 开启 BBR 加速（提升网络性能）
    _enable_bbr

    # 检查是否已安装
    if systemctl is-active x-ui &>/dev/null; then
        log_success "3x-ui 已在运行"
        return 0
    fi

    # 使用官方一键安装脚本（非交互模式）
    # 交互顺序: SSL证书选择→2(IP自签证书), 自定义端口→y→54321
    # 通过管道自动输入回答，跳过所有交互
    log_info "执行 3x-ui 官方安装脚本（自动应答模式）..."
    printf '2\ny\n%s\n' "$PORT_3XUI_PANEL" | bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

    # 确保端口设置正确（安装脚本的交互顺序可能变化，兜底设置）
    if command -v x-ui &>/dev/null; then
        local xui_bin="/usr/local/x-ui/x-ui"
        if [ -x "$xui_bin" ]; then
            $xui_bin setting -port "$PORT_3XUI_PANEL" 2>/dev/null || true
            log_info "面板端口已设为 $PORT_3XUI_PANEL"
        fi
        systemctl restart x-ui 2>/dev/null || true
    fi

    # 放行端口
    firewall_allow "$PORT_3XUI_PANEL"
    firewall_allow 443 tcp
    firewall_allow 443 udp

    log_success "3x-ui 安装完成"
    log_warn "安装时生成的随机账号密码仅为临时值"
    log_warn "如执行 restore，备份中的 x-ui.db 会覆盖所有设置（账号、端口、节点配置）"
}

# 开启 BBR 拥塞控制算法
_enable_bbr() {
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
        log_success "BBR 已启用"
        return 0
    fi

    log_info "开启 BBR 加速..."
    cat >> /etc/sysctl.conf << 'EOF'

# BBR 拥塞控制 (QuickEnv)
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    sysctl -p >/dev/null 2>&1
    log_success "BBR 已启用"
}

service_restore() {
    local restore_dir="$1"
    local xui_backup="${restore_dir}/3x-ui"

    if [ ! -d "$xui_backup" ]; then
        log_warn "备份中未找到 3x-ui 数据，跳过恢复"
        return 0
    fi

    log_step "恢复 3x-ui 数据"

    # 停止服务
    systemctl stop x-ui 2>/dev/null || true

    # 恢复 SQLite 数据库
    if [ -f "${xui_backup}/x-ui.db" ]; then
        cp "${xui_backup}/x-ui.db" /etc/x-ui/x-ui.db
        log_success "恢复 x-ui.db"
    fi

    # 恢复 SSL 证书
    if [ -d "${xui_backup}/ssl" ]; then
        mkdir -p /etc/ssl/3x-ui
        cp "${xui_backup}/ssl/cert.pem" /etc/ssl/3x-ui/ 2>/dev/null || true
        cp "${xui_backup}/ssl/privkey.pem" /etc/ssl/3x-ui/ 2>/dev/null || true
        log_success "恢复 SSL 证书"
    fi

    # 启动服务
    systemctl start x-ui
    log_success "3x-ui 恢复完成"
}

service_status() {
    if systemctl is-active x-ui &>/dev/null; then
        log_success "3x-ui: 运行中 (面板端口: $PORT_3XUI_PANEL)"
        return 0
    else
        log_error "3x-ui: 未运行"
        return 1
    fi
}

service_verify() {
    if wait_for_port "$PORT_3XUI_PANEL" 10; then
        log_success "3x-ui 面板端口 $PORT_3XUI_PANEL 已就绪"
    else
        log_warn "3x-ui 面板端口 $PORT_3XUI_PANEL 未响应（可能使用了 HTTPS）"
    fi
}
