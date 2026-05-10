#!/bin/bash
# =============================================================================
# QuickEnv - 一键服务器环境部署
# 用法:
#   quickenv.sh <command> [profile] [options]
#
# 命令:
#   deploy [profile]              部署服务（默认 profile: full）
#   restore <profile> <backup>    部署 + 从备份恢复数据
#   status  [profile]             查看所有服务状态
#   verify  [profile]             验证所有服务是否正常
#   list                          列出可用的 profile 和服务
#
# 示例:
#   quickenv.sh deploy                              # 全量部署
#   quickenv.sh deploy minimal                      # 最小化部署
#   quickenv.sh restore full ~/backup.tar.gz        # 部署 + 恢复
#   quickenv.sh status                              # 查看状态
# =============================================================================

set -euo pipefail

# ======================== 初始化 ========================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/config.env"

# ======================== 核心函数 ========================

# 加载 profile
load_profile() {
    local profile_name="${1:-full}"
    local profile_file="${SCRIPT_DIR}/profiles/${profile_name}.conf"

    if [ ! -f "$profile_file" ]; then
        log_error "Profile 不存在: $profile_file"
        log_info "可用的 Profile:"
        ls "${SCRIPT_DIR}/profiles/"*.conf 2>/dev/null | while read -r f; do
            echo "  - $(basename "$f" .conf)"
        done
        exit 1
    fi

    # shellcheck source=/dev/null
    source "$profile_file"
    log_info "已加载 Profile: ${profile_name} (${#SERVICES[@]} 个服务)"
}

# 加载单个服务模块
load_service() {
    local svc_name="$1"
    local svc_file="${SCRIPT_DIR}/services/${svc_name}/service.sh"

    if [ ! -f "$svc_file" ]; then
        log_error "服务模块不存在: $svc_file"
        return 1
    fi

    # shellcheck source=/dev/null
    source "$svc_file"
}

# 解压备份文件
extract_backup() {
    local backup_file="$1"
    local extract_dir="/tmp/quickenv_restore_$$"

    if [ ! -f "$backup_file" ]; then
        log_error "备份文件不存在: $backup_file"
        exit 1
    fi

    log_step "解压备份文件"
    mkdir -p "$extract_dir"
    tar -xzf "$backup_file" -C "$extract_dir"

    # 找到实际的数据目录（tar 包内可能有一层日期目录）
    local inner_dir
    inner_dir=$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -1)
    if [ -n "$inner_dir" ]; then
        echo "$inner_dir"
    else
        echo "$extract_dir"
    fi
}

# ======================== 命令实现 ========================

# 部署命令
cmd_deploy() {
    local profile="${1:-full}"

    log_banner
    log_step "开始部署 (Profile: $profile)"
    log_divider

    load_profile "$profile"

    # 1. 检查环境
    log_step "检查系统环境"
    local os_type
    os_type=$(detect_os)
    log_info "操作系统: $os_type"

    # 2. 安装 Docker（如果有 Docker 服务需要部署）
    local needs_docker=false
    for svc in "${SERVICES[@]}"; do
        if [[ "$svc" != "nginx" && "$svc" != "3x-ui" ]]; then
            needs_docker=true
            break
        fi
    done

    if $needs_docker; then
        source "${SCRIPT_DIR}/lib/docker-setup.sh"
        install_docker

        if ! check_docker_compose; then
            log_error "Docker Compose 不可用，请手动安装"
            exit 1
        fi
        log_success "Docker Compose 已就绪"
    fi

    # 3. 逐个部署服务
    local total=${#SERVICES[@]}
    local current=0
    local failed=()

    for svc in "${SERVICES[@]}"; do
        current=$((current + 1))
        log_divider
        log_info "[$current/$total] 部署服务: $svc"

        # 加载服务模块（每次重新 source 以隔离函数定义）
        load_service "$svc"

        if service_install; then
            log_success "$svc 部署成功"
        else
            log_error "$svc 部署失败"
            failed+=("$svc")
        fi
    done

    # 4. 输出摘要
    log_divider
    log_step "部署摘要"
    echo ""
    echo "  总服务数: $total"
    echo "  成功: $((total - ${#failed[@]}))"
    echo "  失败: ${#failed[@]}"
    if [ ${#failed[@]} -gt 0 ]; then
        echo "  失败列表: ${failed[*]}"
    fi
    echo ""

    if [ ${#failed[@]} -eq 0 ]; then
        log_success "所有服务部署完成！"
    else
        log_warn "部分服务部署失败，请检查日志"
        return 1
    fi
}

# 恢复命令
cmd_restore() {
    local profile="${1:-full}"
    local backup_file="$2"

    if [ -z "$backup_file" ]; then
        log_error "请指定备份文件路径"
        echo "用法: quickenv.sh restore <profile> <backup.tar.gz>"
        exit 1
    fi

    log_banner
    log_step "开始部署 + 恢复 (Profile: $profile)"
    log_divider

    # 先部署
    cmd_deploy "$profile"

    # 解压备份
    local restore_dir
    restore_dir=$(extract_backup "$backup_file")
    log_success "备份已解压到: $restore_dir"
    log_info "备份内容:"
    ls "$restore_dir"

    # 逐个恢复
    load_profile "$profile"
    local total=${#SERVICES[@]}
    local current=0

    for svc in "${SERVICES[@]}"; do
        current=$((current + 1))
        log_divider
        log_info "[$current/$total] 恢复服务数据: $svc"

        load_service "$svc"
        service_restore "$restore_dir" || log_warn "$svc 恢复出现问题"
    done

    # 清理临时目录
    rm -rf "$restore_dir"
    log_success "临时文件已清理"

    log_divider
    log_step "恢复完成"
    log_info "建议执行 'quickenv.sh verify' 验证所有服务状态"
}

# 状态命令
cmd_status() {
    local profile="${1:-full}"

    log_banner
    log_step "服务状态 (Profile: $profile)"
    log_divider

    load_profile "$profile"

    local ok_count=0
    local fail_count=0

    for svc in "${SERVICES[@]}"; do
        load_service "$svc"
        if service_status; then
            ok_count=$((ok_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
    done

    log_divider
    echo ""
    echo "  运行中: $ok_count / $((ok_count + fail_count))"
    echo ""
}

# 验证命令
cmd_verify() {
    local profile="${1:-full}"

    log_banner
    log_step "验证服务 (Profile: $profile)"
    log_divider

    load_profile "$profile"

    for svc in "${SERVICES[@]}"; do
        load_service "$svc"
        service_verify || true
    done

    log_divider
    log_success "验证完成"
}

# 列表命令
cmd_list() {
    log_banner

    log_step "可用 Profile"
    for f in "${SCRIPT_DIR}/profiles/"*.conf; do
        local name
        name=$(basename "$f" .conf)
        echo "  - $name"
    done

    log_step "可用服务模块"
    for d in "${SCRIPT_DIR}/services/"*/; do
        local name
        name=$(basename "$d")
        local svc_file="${d}service.sh"
        if [ -f "$svc_file" ]; then
            echo "  - $name"
        fi
    done
}

# 帮助信息
show_help() {
    echo "QuickEnv - 一键服务器环境部署工具"
    echo ""
    echo "用法: quickenv.sh <command> [options]"
    echo ""
    echo "命令:"
    echo "  deploy  [profile]              部署服务（默认: full）"
    echo "  restore <profile> <backup>     部署 + 从备份恢复"
    echo "  status  [profile]              查看服务状态"
    echo "  verify  [profile]              验证服务健康"
    echo "  list                           列出可用 profile 和服务"
    echo "  help                           显示帮助"
    echo ""
    echo "示例:"
    echo "  quickenv.sh deploy                          # 全量部署"
    echo "  quickenv.sh deploy minimal                  # 最小化部署"
    echo "  quickenv.sh restore full ~/backup.tar.gz    # 部署 + 恢复"
    echo "  quickenv.sh status                          # 查看状态"
}

# ======================== 入口 ========================

main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        deploy)
            cmd_deploy "$@"
            ;;
        restore)
            cmd_restore "$@"
            ;;
        status)
            cmd_status "$@"
            ;;
        verify)
            cmd_verify "$@"
            ;;
        list)
            cmd_list
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "未知命令: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
