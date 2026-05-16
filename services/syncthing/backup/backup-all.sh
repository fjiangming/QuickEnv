#!/bin/bash
# =============================================================================
# 全量自动备份脚本 - CLIProxyAPI + sub2api + eshop + 3x-ui + Nginx
# 用途：定时备份所有业务数据到 ~/syncthing/backups/，由 Syncthing 同步到本地
# =============================================================================

set -euo pipefail

# ======================== 配置区 ========================
# QUICKENV_ROOT 由 service_install() 部署时注入到脚本头部
# 若存在则从 config.env 读取路径，否则使用默认值
if [ -n "${QUICKENV_ROOT:-}" ] && [ -f "${QUICKENV_ROOT}/config.env" ]; then
    source "${QUICKENV_ROOT}/config.env"
fi

BACKUP_ROOT="${BACKUP_ROOT:-$HOME/syncthing/backups}"
CPA_DIR="${DEPLOY_CPA:-$HOME/cpa}"
SUB2API_DIR="${DEPLOY_SUB2API:-$HOME/sub2api-deploy}"
ESHOP_DIR="${DEPLOY_ESHOP:-$HOME/eshop}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$BACKUP_ROOT/$TIMESTAMP"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
LOG_FILE="$BACKUP_ROOT/backup.log"
# ========================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "========== 开始备份 =========="
mkdir -p "$BACKUP_DIR"

# -------------------------------------------------------
# 1. CLIProxyAPI - 文件备份（无数据库）
# -------------------------------------------------------
log "[1/5] 备份 CLIProxyAPI..."
CLI_BACKUP="$BACKUP_DIR/cpa"
mkdir -p "$CLI_BACKUP"

if [ -f "$CPA_DIR/config.yaml" ]; then
    cp "$CPA_DIR/config.yaml" "$CLI_BACKUP/config.yaml"
    log "  ✓ config.yaml"
fi

if [ -d "$CPA_DIR/auths" ]; then
    cp -r "$CPA_DIR/auths" "$CLI_BACKUP/auths"
    AUTH_COUNT=$(find "$CLI_BACKUP/auths/" -type f | wc -l)
    log "  ✓ auths/ 目录 (${AUTH_COUNT} 个认证文件)"
fi

if [ -f "$CPA_DIR/docker-compose.yml" ]; then
    cp "$CPA_DIR/docker-compose.yml" "$CLI_BACKUP/docker-compose.yml"
    log "  ✓ docker-compose.yml"
fi

log "[1/5] CLIProxyAPI 备份完成"

# -------------------------------------------------------
# 2. sub2api - PostgreSQL 导出 + 文件备份
# -------------------------------------------------------
log "[2/5] 备份 sub2api..."
SUB2API_BACKUP="$BACKUP_DIR/sub2api"
mkdir -p "$SUB2API_BACKUP"

if docker ps --format '{{.Names}}' | grep -q '^sub2api-postgres$'; then
    docker exec sub2api-postgres pg_dump \
        -U sub2api \
        -d sub2api \
        --no-owner \
        --no-privileges \
        --clean \
        --if-exists \
        > "$SUB2API_BACKUP/sub2api-database.sql" 2>> "$LOG_FILE"
    log "  ✓ PostgreSQL 数据库导出 ($(du -sh "$SUB2API_BACKUP/sub2api-database.sql" | cut -f1))"
else
    log "  ⚠ sub2api-postgres 容器未运行，跳过数据库备份"
fi

if [ -f "$SUB2API_DIR/.env" ]; then
    cp "$SUB2API_DIR/.env" "$SUB2API_BACKUP/.env"
    log "  ✓ .env"
fi

if [ -d "$SUB2API_DIR/data" ]; then
    cp -r "$SUB2API_DIR/data" "$SUB2API_BACKUP/data"
    log "  ✓ data/ 目录"
fi

if [ -f "$SUB2API_DIR/docker-compose.yml" ]; then
    cp "$SUB2API_DIR/docker-compose.yml" "$SUB2API_BACKUP/docker-compose.yml"
    log "  ✓ docker-compose.yml"
fi

log "[2/5] sub2api 备份完成"

# -------------------------------------------------------
# 3. eshop (Dujiao-Next) - PostgreSQL 导出 + 配置 + 上传文件
# -------------------------------------------------------
log "[3/5] 备份 eshop (Dujiao-Next)..."
ESHOP_BACKUP="$BACKUP_DIR/eshop"
mkdir -p "$ESHOP_BACKUP"

if docker ps --format '{{.Names}}' | grep -q '^dujiao-db$'; then
    docker exec dujiao-db pg_dump \
        -U dujiao \
        -d dujiao_db \
        --no-owner \
        --no-privileges \
        --clean \
        --if-exists \
        > "$ESHOP_BACKUP/eshop-database.sql" 2>> "$LOG_FILE"
    log "  ✓ PostgreSQL 数据库导出 ($(du -sh "$ESHOP_BACKUP/eshop-database.sql" | cut -f1))"
else
    log "  ⚠ dujiao-db 容器未运行，跳过数据库备份"
fi

if [ -f "$ESHOP_DIR/config.yml" ]; then
    cp "$ESHOP_DIR/config.yml" "$ESHOP_BACKUP/config.yml"
    log "  ✓ config.yml"
fi

if [ -f "$ESHOP_DIR/docker-compose.yml" ]; then
    cp "$ESHOP_DIR/docker-compose.yml" "$ESHOP_BACKUP/docker-compose.yml"
    log "  ✓ docker-compose.yml"
fi

if [ -d "$ESHOP_DIR/uploads" ]; then
    cp -r "$ESHOP_DIR/uploads" "$ESHOP_BACKUP/uploads"
    UPLOAD_COUNT=$(find "$ESHOP_BACKUP/uploads/" -type f 2>/dev/null | wc -l)
    log "  ✓ uploads/ 目录 (${UPLOAD_COUNT} 个文件)"
fi

log "[3/5] eshop 备份完成"

# -------------------------------------------------------
# 4. 3x-ui - SQLite 数据库 + SSL 证书
# -------------------------------------------------------
log "[4/5] 备份 3x-ui..."
XUI_BACKUP="$BACKUP_DIR/3x-ui"
mkdir -p "$XUI_BACKUP"

if [ -f /etc/x-ui/x-ui.db ]; then
    cp /etc/x-ui/x-ui.db "$XUI_BACKUP/x-ui.db"
    log "  ✓ x-ui.db"
fi

if [ -d /etc/ssl/3x-ui ]; then
    cp -r /etc/ssl/3x-ui "$XUI_BACKUP/ssl"
    log "  ✓ SSL 证书"
fi

log "[4/5] 3x-ui 备份完成"

# -------------------------------------------------------
# 5. Nginx - 配置文件
# -------------------------------------------------------
log "[5/5] 备份 Nginx 配置..."
NGINX_BACKUP="$BACKUP_DIR/nginx"
mkdir -p "$NGINX_BACKUP"

if [ -f /etc/nginx/nginx.conf ]; then
    cp /etc/nginx/nginx.conf "$NGINX_BACKUP/nginx.conf"
    log "  ✓ nginx.conf"
fi

if [ -d /etc/nginx/conf.d ]; then
    cp -r /etc/nginx/conf.d "$NGINX_BACKUP/conf.d"
    log "  ✓ conf.d/"
fi

log "[5/5] Nginx 备份完成"

# -------------------------------------------------------
# 6. 压缩本次备份
# -------------------------------------------------------
log "压缩备份文件..."
cd "$BACKUP_ROOT"
tar -czf "${TIMESTAMP}.tar.gz" "$TIMESTAMP"
rm -rf "$BACKUP_DIR"
log "✓ 已压缩为 ${TIMESTAMP}.tar.gz ($(du -sh "${TIMESTAMP}.tar.gz" | cut -f1))"

# -------------------------------------------------------
# 7. 清理过期备份
# -------------------------------------------------------
DELETED_COUNT=$(find "$BACKUP_ROOT" -name "*.tar.gz" -mtime +$RETENTION_DAYS -print -delete | wc -l)
if [ "$DELETED_COUNT" -gt 0 ]; then
    log "✓ 已清理 ${DELETED_COUNT} 个过期备份（超过 ${RETENTION_DAYS} 天）"
fi

# -------------------------------------------------------
# 8. 输出摘要
# -------------------------------------------------------
TOTAL_SIZE=$(du -sh "$BACKUP_ROOT" | cut -f1)
BACKUP_COUNT=$(find "$BACKUP_ROOT" -name "*.tar.gz" | wc -l)
log "========== 备份完成 =========="
log "本次备份: ${TIMESTAMP}.tar.gz"
log "备份总数: ${BACKUP_COUNT} 个"
log "占用空间: ${TOTAL_SIZE}"
log "Syncthing 将自动同步到本地电脑"
log "=============================="
