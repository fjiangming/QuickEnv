# QuickEnv

> 一键部署 · 一键恢复 · 灵活扩展

云服务器环境快速部署与灾难恢复工具。通过模块化的服务定义和 Profile 机制，实现新服务器上的一键环境搭建，配合 Syncthing 自动备份，完成 **5 分钟从零恢复到生产状态** 的目标。

## 包含的服务

### 必须部署（full.conf）

| 服务 | 端口 | 运行方式 | 说明 |
|------|------|---------|------|
| 3x-ui | 54321 / 443 | systemd | 代理面板 + Hysteria2 |
| sub2api | 9000 | Docker (3容器) | 订阅转换服务 |
| cli-proxy-api | 8317 | Docker (host模式) | CLI 代理 API |
| Nginx | 80 | systemd | 反向代理 |
| Syncthing | 8384 | Docker | 文件同步 |
| 备份服务 | - | cron | 定时全量备份 |

### 可选服务（需手动添加到 Profile）

| 服务 | 端口 | 说明 |
|------|------|------|
| new-api | 3000 | API 管理平台（暂未部署） |

## 快速开始

### 1. 全新部署

```bash
# 拉取代码
git clone https://github.com/你的用户名/QuickEnv.git ~/QuickEnv

# 全量部署
cd ~/QuickEnv && bash quickenv.sh deploy

# 或最小化部署（不含 Syncthing 和备份）
bash quickenv.sh deploy minimal
```

### 2. 灾难恢复（从备份恢复）

```bash
# 1. 上传备份文件到新服务器
scp E:\syncthing-windows-amd64-v2.0.16\server-backup\20260510_042735.tar.gz root@新服务器:~/

# 2. 一键部署 + 恢复
cd ~/QuickEnv && bash quickenv.sh restore full ~/20260510_030000.tar.gz
```

### 3. 查看状态

```bash
bash quickenv.sh status
```

## 项目结构

```
QuickEnv/
├── quickenv.sh              # 主入口
├── config.env               # 全局配置（端口、目录等）
├── lib/
│   ├── common.sh            # 公共函数库
│   └── docker-setup.sh      # Docker 安装
├── services/                # 服务模块（每个子目录 = 一个服务）
│   ├── 3x-ui/service.sh
│   ├── new-api/service.sh + docker-compose.yml  # 可选
│   ├── sub2api/service.sh + docker-compose.yml
│   ├── cli-proxy-api/service.sh + docker-compose.yml
│   ├── nginx/service.sh
│   ├── syncthing/service.sh
│   └── backup/service.sh + backup-all.sh
├── profiles/                # 部署配置
│   ├── full.conf            # 全量部署
│   ├── minimal.conf         # 最小化部署
│   └── custom.conf.example  # 自定义模板
└── syncthing_guide.md       # Syncthing 完整手册
```

## 扩展新服务

只需 3 步：

### 1. 创建服务目录

```bash
mkdir -p services/my-service
```

### 2. 编写 service.sh

```bash
#!/bin/bash
# services/my-service/service.sh

service_name()  { echo "my-service"; }
service_deps()  { echo ""; }  # 依赖的服务，空格分隔

service_install() {
    log_step "部署 my-service"
    # 你的安装逻辑...
    log_success "my-service 部署完成"
}

service_restore() {
    local restore_dir="$1"
    # 从 $restore_dir 恢复数据...
}

service_status() {
    # 检查服务状态，返回 0=正常 1=异常
    docker ps --format '{{.Names}}' | grep -q '^my-service$'
}

service_verify() {
    # 验证服务健康...
    wait_for_port 9999 10
}
```

### 3. 添加到 Profile

```bash
# 编辑 profiles/full.conf，在 SERVICES 数组中添加：
SERVICES=(
    ...
    my-service
)
```

## 备份与恢复架构

```
每天 03:00 (cron)
        │
        ▼
  backup-all.sh ──→ ~/syncthing/backups/*.tar.gz
        │                    │
        │               Syncthing P2P
        │                    │
        ▼                    ▼
   服务器本地             Windows 本地
               E:\syncthing-windows-amd64-v2.0.16\server-backup\
```

详细的 Syncthing 配置和操作指南，参见 [syncthing_guide.md](syncthing_guide.md)。

## 命令参考

| 命令 | 说明 |
|------|------|
| `quickenv.sh deploy [profile]` | 部署服务 |
| `quickenv.sh restore <profile> <backup.tar.gz>` | 部署 + 恢复数据 |
| `quickenv.sh status [profile]` | 查看服务运行状态 |
| `quickenv.sh verify [profile]` | 验证服务健康 |
| `quickenv.sh list` | 列出可用 profile 和服务 |

## 注意事项

- **敏感文件不入库**：`.env`、`config.yaml`（含 API Key）、`auths/` 等已在 `.gitignore` 中排除
- **恢复优先于部署**：`restore` 命令先全新部署，再从备份覆盖配置和数据；无备份的服务保持全新部署状态
- **sub2api 的 docker-compose.yml**：模板仅供参考，建议优先使用备份中恢复的原始版本
- **3x-ui 安装**：自动应答模式安装（IP自签证书 + 端口 54321），安装时的随机账号密码为临时值，restore 时会被 x-ui.db 覆盖
- **Syncthing 配对**：部署后需手动在 Web UI 中配对 Windows 设备
- **new-api**：目前为可选服务，如需部署请添加到 `profiles/full.conf` 的 `SERVICES` 数组中
