# Syncthing 部署安装及使用手册

> 适用场景：将云服务器上的 newapi / sub2api / cli-proxy-api 等项目数据自动同步备份到本地 Windows 电脑。

---

## 目录

1. [架构概览](#1-架构概览)
2. [服务器端部署（Docker）](#2-服务器端部署docker)
3. [Windows 客户端安装](#3-windows-客户端安装)
4. [设备配对](#4-设备配对)
5. [配置同步文件夹](#5-配置同步文件夹)
6. [（可选）与 Backrest 组合使用](#6-可选与-backrest-组合使用)
7. [安全加固](#7-安全加固)
8. [日常运维与监控](#8-日常运维与监控)
9. [数据恢复流程](#9-数据恢复流程)
10. [故障排查](#10-故障排查)
11. [实战：全部服务完全自动化备份](#11-实战全部服务完全自动化备份)

---

## 1. 架构概览

```
┌─────────────────────────────┐        ┌──────────────────────────┐
│        云服务器 (Linux)       │        │   你的 Windows 电脑       │
│                             │        │                          │
│  ┌─────────┐ ┌───────────┐  │        │  ┌────────────────────┐  │
│  │ new-api  │ │ sub2api   │  │        │  │  Syncthing Client  │  │
│  └────┬────┘ └─────┬─────┘  │        │  │                    │  │
│       │            │        │        │  │  D:\backups\server  │  │
│       ▼            ▼        │        │  └─────────▲──────────┘  │
│  ~/services/ (业务数据)       │        │            │             │
│       │                     │        │            │             │
│       ▼                     │        │            │             │
│  ┌──────────┐               │  P2P   │            │             │
│  │ Backrest  │──→ ~/syncthing/backups/ ════════════╝             │
│  │ (定时备份) │               │  加密传输│                          │
│  └──────────┘               │        │                          │
│  ┌──────────┐               │        │                          │
│  │Syncthing │ (监控 backups) │        │                          │
│  │ Server   │               │        │                          │
│  └──────────┘               │        │                          │
└─────────────────────────────┘        └──────────────────────────┘
```

**工作流程**：
1. Backrest 按计划定时备份业务数据到 `~/syncthing/backups/`
2. Syncthing 检测到 `~/syncthing/backups/` 有变化，自动同步到你的 Windows 电脑
3. 即使服务器丢失，你本地拥有完整备份

---

## 2. 服务器端部署（Docker）

### 2.1 创建目录结构

```bash
# 在服务器上执行
mkdir -p ~/syncthing/config
mkdir -p ~/syncthing/backups
```

### 2.2 单独部署 Syncthing

如果你只想部署 Syncthing，使用以下 `docker-compose.yml`：

```yaml
# ~/syncthing/docker-compose.yml
version: "3.8"

services:
  syncthing:
    image: lscr.io/linuxserver/syncthing:latest
    container_name: syncthing
    hostname: my-cloud-server  # 自定义，方便在 UI 中识别
    environment:
      - PUID=0       # root 用户，确保能读取所有备份文件
      - PGID=0
      - TZ=Asia/Shanghai
    volumes:
      - ~/syncthing/config:/config            # Syncthing 配置数据
      - ~/syncthing/backups:/data/backups     # 要同步的备份目录
    ports:
      - "8384:8384"    # Web UI 管理界面
      - "22000:22000/tcp"  # 文件同步（TCP）
      - "22000:22000/udp"  # 文件同步（UDP）
      - "21027:21027/udp"  # 设备发现
    restart: unless-stopped
```

### 2.3 启动服务

```bash
cd ~/syncthing
docker compose up -d
```

### 2.4 验证运行状态

```bash
docker logs syncthing
# 看到 "GUI and API listening on [::]:8384" 表示启动成功
```

### 2.5 防火墙放行

```bash
# 如果使用 ufw
sudo ufw allow 8384/tcp    # Web UI（建议配置完成后关闭，见安全加固章节）
sudo ufw allow 22000/tcp   # 同步传输
sudo ufw allow 22000/udp
sudo ufw allow 21027/udp   # 发现协议

# 如果使用 firewalld
sudo firewall-cmd --permanent --add-port=8384/tcp
sudo firewall-cmd --permanent --add-port=22000/tcp
sudo firewall-cmd --permanent --add-port=22000/udp
sudo firewall-cmd --permanent --add-port=21027/udp
sudo firewall-cmd --reload
```

> **云服务器安全组**：同样需要在云厂商控制台的安全组中放行上述端口。

---

## 3. Windows 客户端安装

### 3.1 下载安装

**方式一：官网下载**
- 访问 [https://syncthing.net/downloads/](https://syncthing.net/downloads/)
- 下载 Windows (64-bit) 版本
- 解压到任意目录，如 `D:\Tools\Syncthing\`

**方式二：包管理器安装**
```powershell
# 使用 winget
winget install Syncthing.Syncthing

# 或使用 scoop
scoop install syncthing
```

**方式三：安装 SyncTrayzor（推荐，带托盘图标）**
- 下载 [SyncTrayzor](https://github.com/canton7/SyncTrayzor/releases)
- 这是一个 Syncthing 的 Windows 包装器，提供系统托盘图标和开机自启动

### 3.2 启动 Syncthing

- 如果用 SyncTrayzor：双击启动，它会自动开机运行
- 如果用原版：运行 `syncthing.exe`，浏览器会自动打开 `http://127.0.0.1:8384`

### 3.3 创建本地备份目录

```powershell
mkdir D:\backups\server-backup
```

---

## 4. 设备配对

### 4.1 获取设备 ID

每个 Syncthing 实例都有一个唯一的设备 ID（一长串字母数字）。

**服务器端**：
1. 浏览器访问 `http://服务器IP:8384`
2. 右上角点击 **操作 (Actions)** → **显示 ID (Show ID)**
3. 复制设备 ID（或扫描二维码）

**Windows 端**：
1. 浏览器访问 `http://127.0.0.1:8384`
2. 同样操作获取本地设备 ID

### 4.2 互相添加对方

**在 Windows 端添加服务器**：
1. 点击右下角 **添加远程设备 (Add Remote Device)**
2. 粘贴服务器的设备 ID
3. 设备名称填写 `云服务器`（自定义，方便识别）
4. 点击 **保存**

**在服务器端确认**：
1. 访问服务器的 Web UI (`http://服务器IP:8384`)
2. 页面顶部会出现提示 **"新设备请求连接"**
3. 点击 **添加设备**，确认即可

> 如果没有自动弹出提示，也可以在服务器端手动添加 Windows 的设备 ID。

### 4.3 验证连接

配对成功后，在两端的 Web UI 中：
- **远程设备** 区域会显示对方，状态为 **已连接 (Connected)**
- 显示绿色图标表示连接正常

---

## 5. 配置同步文件夹

### 5.1 在服务器端添加共享文件夹

1. 在服务器 Web UI 中，点击 **添加文件夹 (Add Folder)**
2. 填写以下信息：

| 字段 | 值 | 说明 |
|------|-----|------|
| 文件夹标签 | `server-backups` | 自定义名称 |
| 文件夹路径 | `/data/backups` | 容器内路径（映射的 ~/syncthing/backups） |
| 文件夹 ID | `server-backups` | 两端需一致，自动生成也可以 |

3. 切换到 **共享** 选项卡：
   - 勾选你的 Windows 设备
4. 切换到 **文件夹类型** 选项卡：
   - 选择 **仅发送 (Send Only)** — 服务器只负责发送，不接收修改
5. 点击 **保存**

### 5.2 在 Windows 端接受共享

1. 服务器添加共享后，Windows 端会弹出提示 **"服务器想要共享文件夹 server-backups"**
2. 点击 **添加**
3. 设置本地路径为 `D:\backups\server-backup`
4. 文件夹类型选择 **仅接收 (Receive Only)** — 本地只接收，不回传
5. 点击 **保存**

### 5.3 文件夹类型说明

| 类型 | 服务器端 | Windows 端 | 说明 |
|------|---------|-----------|------|
| **仅发送** | ✅ 使用 | - | 服务器只推送文件，忽略远端修改 |
| **仅接收** | - | ✅ 使用 | 本地只接收文件，不会回传 |
| 发送与接收 | - | - | 双向同步（不推荐用于备份场景） |

### 5.4 验证同步

在服务器上创建一个测试文件：

```bash
echo "sync test $(date)" > ~/syncthing/backups/test.txt
```

几秒后检查 Windows 端 `D:\backups\server-backup\` 是否出现 `test.txt`。

---

## 6. （可选）与 Backrest 组合使用

> **本章为可选内容。** 如果你已按照第 11 章使用 `backup-all.sh` 脚本实现了自动备份，则无需部署 Backrest。Backrest 适合希望通过 Web UI 管理备份、需要增量去重/加密/快照浏览等高级功能的用户。

### 6.1 完整 docker-compose.yml

以下是包含**业务服务 + Backrest 备份 + Syncthing 同步**的完整编排文件：

```yaml
# ~/services/docker-compose.yml
version: "3.8"

services:
  # ============ 业务服务 ============

  new-api:
    image: calciumion/new-api:latest
    container_name: new-api
    ports:
      - "3000:3000"
    volumes:
      - new-api-data:/data
    environment:
      - TZ=Asia/Shanghai
    restart: always

  sub2api:
    image: sub2api-image:latest          # 替换为你的实际镜像
    container_name: sub2api
    volumes:
      - sub2api-data:/app/data
    restart: always

  cli-proxy-api:
    image: cli-proxy-image:latest        # 替换为你的实际镜像
    container_name: cli-proxy-api
    volumes:
      - cli-proxy-data:/app/data
    restart: always

  # ============ Backrest 定时备份 ============

  backrest:
    image: garethgeorge/backrest:latest
    container_name: backrest
    ports:
      - "9898:9898"                      # Backrest Web UI
    environment:
      - BACKREST_PORT=9898
      - BACKREST_DATA=/backrest-data
      - BACKREST_CONFIG=/config/config.json
      - XDG_CACHE_HOME=/cache
      - TZ=Asia/Shanghai
    volumes:
      - ./backrest/data:/backrest-data
      - ./backrest/config:/config
      - ./backrest/cache:/cache
      # 备份源（只读挂载业务数据）
      - new-api-data:/sources/new-api:ro
      - sub2api-data:/sources/sub2api:ro
      - cli-proxy-data:/sources/cli-proxy:ro
      # 备份输出目录（Syncthing 会同步此目录）
      - ~/syncthing/backups:/repos/local-backups
    restart: unless-stopped

  # ============ Syncthing 同步到本地 ============

  syncthing:
    image: lscr.io/linuxserver/syncthing:latest
    container_name: syncthing
    hostname: my-cloud-server
    environment:
      - PUID=0
      - PGID=0
      - TZ=Asia/Shanghai
    volumes:
      - ~/syncthing/config:/config
      - ~/syncthing/backups:/data/backups:ro    # 只读挂载备份目录
    ports:
      - "8384:8384"
      - "22000:22000/tcp"
      - "22000:22000/udp"
      - "21027:21027/udp"
    restart: unless-stopped

volumes:
  new-api-data:
  sub2api-data:
  cli-proxy-data:
```

### 6.2 Backrest 配置步骤

1. 访问 `http://服务器IP:9898`，首次设置管理员密码
2. **添加 Repository**：
   - 类型选 **Local**
   - 路径填 `/repos/local-backups`
   - 设置加密密码（务必记住）
3. **添加 Backup Plan**：
   - 源路径：`/sources/new-api`、`/sources/sub2api`、`/sources/cli-proxy`
   - 备份计划：如 `每天 03:00`
   - 保留策略：如保留最近 7 个每日快照 + 4 个每周快照

### 6.3 工作流程

```
03:00  Backrest 自动执行备份 → 写入 ~/syncthing/backups/
03:01  Syncthing 检测到变化 → 自动同步到 Windows D:\backups\server-backup\
```

---

## 7. 安全加固

### 7.1 设置 Web UI 密码

**首次访问时**，Syncthing 会提示设置 GUI 密码：
1. 点击 **操作 (Actions)** → **设置 (Settings)**
2. 在 **GUI** 选项卡中设置用户名和密码
3. 点击 **保存**

### 7.2 限制 Web UI 访问

配置完成后，建议关闭 8384 端口的公网访问：

```bash
# 方式一：防火墙只允许本地访问
sudo ufw delete allow 8384/tcp

# 之后通过 SSH 隧道访问 Web UI
ssh -L 8384:127.0.0.1:8384 user@服务器IP
# 然后本地浏览器访问 http://127.0.0.1:8384
```

或者在 docker-compose 中只绑定本地：

```yaml
    ports:
      - "127.0.0.1:8384:8384"  # 仅本机可访问
```

### 7.3 启用 HTTPS

在 Syncthing 的 **设置 → GUI** 中勾选 **Use HTTPS for GUI**。

### 7.4 传输安全

Syncthing 默认使用 **TLS 1.3 加密** 进行所有设备间通信，无需额外配置。

---

## 8. 日常运维与监控

### 8.1 查看同步状态

- 在 Web UI 中查看文件夹的同步状态：**最新同步时间**、**文件数量**、**总大小**
- 状态图标含义：
  - 🟢 **最新 (Up to Date)**：同步完成
  - 🔵 **同步中 (Syncing)**：正在传输
  - 🟡 **本地有更改**：等待同步
  - 🔴 **错误**：需要检查

### 8.2 查看日志

```bash
# 服务器端
docker logs syncthing --tail 100 -f

# Windows 端
# SyncTrayzor 内置日志查看器，或查看 %APPDATA%\Syncthing 目录
```

### 8.3 带宽限制

如果同步占用太多带宽：
1. **设置 → 连接** 中设置上传/下载速率限制
2. 建议服务器端上传限制为 `5000 KB/s`（约 5MB/s），避免影响业务

### 8.4 忽略不需要同步的文件

在同步文件夹根目录创建 `.stignore` 文件：

```
// ~/syncthing/backups/.stignore
// 忽略临时文件
*.tmp
*.lock
*.part
```

---

## 9. 数据恢复流程

当服务器丢失，需要从本地备份恢复时：

### 9.1 如果使用 Backrest 备份

```bash
# 1. 在新服务器上安装 Backrest
docker run -d --name backrest \
  -p 9898:9898 \
  -v ./backrest-restore:/backrest-data \
  -v ./config:/config \
  -v D:\backups\server-backup:/repos/local-backups \
  garethgeorge/backrest:latest

# 2. 在 Backrest Web UI 中添加 Repository，指向备份目录
# 3. 浏览快照，选择要恢复的版本
# 4. 点击恢复，选择恢复路径
```

### 9.2 如果直接同步的数据文件

```bash
# 1. 在新服务器上创建数据目录
mkdir -p ~/services/new-api/data ~/services/sub2api/data

# 2. 从本地电脑上传备份（使用 scp 或 rclone）
scp -r D:\backups\server-backup\new-api\* user@新服务器:~/services/new-api/data/

# 3. 启动业务容器，挂载恢复的数据目录
```

---

## 10. 故障排查

### 10.1 设备无法连接

| 症状 | 排查步骤 |
|------|---------|
| 设备显示"断开连接" | 检查防火墙是否放行 22000/tcp、22000/udp、21027/udp |
| 长时间"发现中" | 确认两端都能访问公网，检查云服务商安全组 |
| NAT 穿透失败 | 在设置中启用"中继服务器"作为备用 |

### 10.2 同步卡住

```bash
# 重启 Syncthing 容器
docker restart syncthing
```

如果持续卡住，尝试在 Web UI 中：
1. 暂停文件夹同步
2. 重新扫描文件夹
3. 恢复同步

### 10.3 磁盘空间不足

```bash
# 检查备份目录大小
du -sh ~/syncthing/backups/

# 如果 Backrest 备份过多，在 Backrest UI 中调整保留策略
# 或手动清理旧备份
```

### 10.4 Windows 端常见问题

| 问题 | 解决方案 |
|------|---------|
| 开机不自启 | 使用 SyncTrayzor 替代原版，自带开机自启 |
| 文件被占用无法同步 | 关闭占用文件的程序，或在 `.stignore` 中排除 |
| 同步速度慢 | 检查带宽限制设置，或切换为有线网络 |

---

## 附录：常用命令速查

```bash
# ===== Docker 管理 =====
docker compose up -d              # 启动所有服务
docker compose down               # 停止所有服务
docker compose restart syncthing  # 重启 Syncthing
docker logs syncthing -f          # 查看实时日志

# ===== 手动备份 =====
# 紧急情况下手动打包数据
tar -czf ~/syncthing/backups/emergency-$(date +%Y%m%d).tar.gz ~/services/

# ===== 检查同步状态（API） =====
curl -s -H "X-API-Key: YOUR_API_KEY" http://127.0.0.1:8384/rest/db/status?folder=server-backups | jq .
```

---

## 11. 实战：全部服务完全自动化备份

本章以服务器上实际部署的所有服务为案例，手把手实现“定时备份 + 自动同步到本地电脑”的完全自动化方案。

### 11.1 实际部署环境概览

> 以下信息基于对服务器 `186.241.91.116` 的实际目录分析（2026-05-10）。

| 项目 | 部署目录 | 运行方式 | 数据存储方式 |
|------|---------|---------|------------|
| CLIProxyAPI | `~/cpa/` | Docker (cli-proxy-api) | 纯文件系统 |
| sub2api | `~/sub2api-deploy/` | Docker (sub2api + postgres + redis) | PostgreSQL + Redis + 文件 |
| 3x-ui | `/usr/local/x-ui/` | systemd 服务 | SQLite 数据库 + SSL 证书 |
| Nginx | `/etc/nginx/` | systemd 服务 | 配置文件 |
| Syncthing | `~/syncthing/` | Docker (syncthing) | 已部署 ✅ |

### 11.2 需备份的数据清单

#### CLIProxyAPI (`~/cpa/`)

数据存储方式：**纯文件系统**（无数据库），所有状态存在本地文件中。

| 数据 | 宿主机路径 | 容器内路径 | 大小 | 重要性 | 说明 |
|------|-----------|-----------|------|--------|------|
| config.yaml | `~/cpa/config.yaml` | `/CLIProxyAPI/config.yaml` | ~0.5KB | 🔴 必备 | API Key、路由策略、远程管理密钥等核心配置 |
| auths/ 目录 | `~/cpa/auths/` | `/root/.cli-proxy-api` | ~315KB (72个文件) | 🔴 必备 | 所有 Codex OAuth 认证凭据，丢失需全部重新授权 |
| docker-compose.yml | `~/cpa/docker-compose.yml` | - | ~0.3KB | 🟡 可选 | 容器编排配置，可从源码重新获取 |
| logs/ 目录 | `~/cpa/logs/` | `/CLIProxyAPI/logs` | 变化 | 🟢 非必需 | 运行日志，排查问题用 |

#### sub2api (`~/sub2api-deploy/`)

数据存储方式：**PostgreSQL + Redis + 应用数据目录**。

| 数据 | 宿主机路径 | 容器内路径 | 大小 | 重要性 | 说明 |
|------|-----------|-----------|------|--------|------|
| PostgreSQL 数据库 | `~/sub2api-deploy/postgres_data/` | `/var/lib/postgresql/data` | ~78MB | 🔴 必备 | 用户、账号、订阅、使用量、OAuth 绑定等全部核心数据 |
| .env 文件 | `~/sub2api-deploy/.env` | - | ~20KB | 🔴 必备 | POSTGRES_PASSWORD、JWT_SECRET、TOTP_ENCRYPTION_KEY 等，**丢失会导致登录失效和 2FA 失效** |
| data/ 目录 | `~/sub2api-deploy/data/` | `/app/data` | ~185KB | 🔴 必备 | config.yaml（运行时生成）、model_pricing.json（定价数据） |
| docker-compose.yml | `~/sub2api-deploy/docker-compose.yml` | - | ~11KB | 🟡 可选 | 容器编排配置 |
| redis_data/ | `~/sub2api-deploy/redis_data/` | `/data` | ~16KB | 🟡 可选 | dump.rdb 快照，本质是缓存，可自动重建 |

> **⚠️ 关键提醒**：sub2api 使用 PostgreSQL，其数据目录 `postgres_data/` **不能直接复制**（运行中复制会导致数据不一致），必须用 `pg_dump` 导出 SQL 文件才安全。

#### 3x-ui (`/etc/x-ui/` + `/etc/ssl/3x-ui/`)

数据存储方式：**SQLite 数据库**，以 systemd 服务运行（非 Docker）。

| 数据 | 路径 | 大小 | 重要性 | 说明 |
|------|------|------|--------|------|
| x-ui.db | `/etc/x-ui/x-ui.db` | ~64KB | 🔴 必备 | SQLite 数据库，包含所有入站规则、用户账号、流量统计 |
| SSL 证书 | `/etc/ssl/3x-ui/cert.pem` | ~1.7KB | 🔴 必备 | 面板 HTTPS 证书 |
| SSL 私钥 | `/etc/ssl/3x-ui/privkey.pem` | ~1.7KB | 🔴 必备 | 面板 HTTPS 私钥 |
| 日志 | `/var/log/x-ui/` | ~320KB | 🟢 非必需 | 运行日志和封禁记录 |

#### Nginx (`/etc/nginx/`)

数据存储方式：**纯配置文件**，以 systemd 服务运行。

| 数据 | 路径 | 大小 | 重要性 | 说明 |
|------|------|------|--------|------|
| 反代配置 | `/etc/nginx/conf.d/nginx.conf` | ~2.2KB | 🔴 必备 | 含 3 个反代规则：epointapi/epoint2api/cpa → 本地端口 |
| 主配置 | `/etc/nginx/nginx.conf` | ~2.3KB | 🟡 可选 | 基本未改动，可从默认配置恢复 |

### 11.3 服务器实际目录结构

```
~/                                       # /root/
├── cpa/                                 # CLIProxyAPI 部署目录
│   ├── docker-compose.yml
│   ├── config.yaml                      # 🔴 需备份
│   ├── auths/                           # 🔴 需备份（72个认证文件）
│   └── logs/
├── sub2api-deploy/                      # sub2api 部署目录
│   ├── docker-compose.yml
│   ├── .env                             # 🔴 需备份（敏感配置）
│   ├── data/                            # 🔴 需备份（config.yaml + 定价数据）
│   │   ├── config.yaml
│   │   ├── model_pricing.json
│   │   ├── logs/
│   │   └── pages/
│   ├── postgres_data/                   # 🔴 需 pg_dump 备份（核心数据库）
│   └── redis_data/                      # 🟡 可选
└── syncthing/                           # Syncthing（已部署）
    ├── docker-compose.yml
    ├── config/
    ├── scripts/
    │   └── backup-all.sh                # 自动备份脚本
    └── backups/                         # 备份输出目录（自动同步到本地）

/etc/
├── x-ui/
│   └── x-ui.db                          # 🔴 3x-ui SQLite 数据库
├── ssl/3x-ui/
│   ├── cert.pem                         # 🔴 SSL 证书
│   └── privkey.pem                      # 🔴 SSL 私钥
└── nginx/
    ├── nginx.conf                       # 🟡 主配置
    └── conf.d/
        └── nginx.conf                   # 🔴 反代规则
```

### 11.4 创建自动备份脚本

在服务器上创建备份脚本：

```bash
mkdir -p ~/syncthing/scripts
```

备份脚本位于项目中的 `services/backup/backup-all.sh`，**请勿手动编辑服务器上的脚本**，所有改动应在项目中完成后通过部署更新。

部署方式（二选一）：

**方式 A：使用 QuickEnv 一键部署（推荐）**

```bash
cd ~/QuickEnv && bash quickenv.sh deploy
# 部署过程会自动复制脚本到 ~/syncthing/scripts/ 并配置 cron
```

**方式 B：手动复制**

```bash
# 从项目中复制脚本
cp ~/QuickEnv/services/backup/backup-all.sh ~/syncthing/scripts/backup-all.sh
chmod +x ~/syncthing/scripts/backup-all.sh

# 注入 QuickEnv 路径（使脚本能读取 config.env 中的统一配置）
sed -i '2i\QUICKENV_ROOT="$HOME/QuickEnv"' ~/syncthing/scripts/backup-all.sh
```

脚本会从 `config.env` 读取以下配置（不再硬编码）：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `BACKUP_ROOT` | `~/syncthing/backups` | 备份输出目录 |
| `DEPLOY_CPA` | `~/cpa` | CLIProxyAPI 部署目录 |
| `DEPLOY_SUB2API` | `~/sub2api-deploy` | sub2api 部署目录 |
| `BACKUP_RETENTION_DAYS` | `7` | 备份保留天数 |

脚本备份的内容：

| 服务 | 备份项 |
|------|--------|
| CLIProxyAPI | `config.yaml` + `auths/` + `docker-compose.yml` |
| sub2api | PostgreSQL `pg_dump` + `.env` + `data/` + `docker-compose.yml` |
| 3x-ui | `x-ui.db` (SQLite) + SSL 证书 |
| Nginx | `nginx.conf` + `conf.d/` |

> 完整脚本源码参见 [`services/backup/backup-all.sh`](services/backup/backup-all.sh)

赋予执行权限：

```bash
chmod +x ~/syncthing/scripts/backup-all.sh
```

### 11.5 设置定时任务（cron）

```bash
crontab -e
```

添加以下行：

```cron
# 每天凌晨 3:00 执行全量备份
0 3 * * * $HOME/syncthing/scripts/backup-all.sh >> $HOME/syncthing/backups/cron.log 2>&1

# （可选）每12小时备份一次
# 0 */12 * * * $HOME/syncthing/scripts/backup-all.sh >> $HOME/syncthing/backups/cron.log 2>&1
```

验证 cron 已生效：

```bash
crontab -l
```

### 11.6 备份清理管理

#### 自动清理（已内置）

备份脚本中已通过 `BACKUP_RETENTION_DAYS` 变量实现自动清理，默认保留最近 **7 天**的备份。修改该值即可调整保留天数：

```bash
# 编辑 QuickEnv 配置
nano ~/QuickEnv/config.env

# 修改这一行：
BACKUP_RETENTION_DAYS=7    # 改为你需要的天数，如 14 保留两周、30 保留一个月

# 然后重新部署备份脚本使其生效
cd ~/QuickEnv && bash quickenv.sh deploy
```

#### 手动删除指定时间段的备份

```bash
# 删除超过 N 天的备份
find ~/syncthing/backups/ -name "*.tar.gz" -mtime +30 -print -delete

# 删除某个日期之前的所有备份（如 2026-05-01 之前）
find ~/syncthing/backups/ -name "*.tar.gz" ! -newermt "2026-05-01" -print -delete

# 删除某个日期范围内的备份（如 5月1日 到 5月5日）
find ~/syncthing/backups/ -name "*.tar.gz" -newermt "2026-04-30" ! -newermt "2026-05-06" -print -delete

# 删除某一天的所有备份（利用文件名中的日期前缀）
rm -v ~/syncthing/backups/20260508_*.tar.gz

# 删除某个月的所有备份
rm -v ~/syncthing/backups/202605*.tar.gz
```

#### 只保留最近 N 份备份

```bash
# 只保留最近 5 份，删除其余所有
cd ~/syncthing/backups/
ls -t *.tar.gz | tail -n +6 | xargs rm -v

# 预览会删除哪些（不实际删除）
ls -t *.tar.gz | tail -n +6
```

#### 查看备份占用空间

```bash
# 查看总大小
du -sh ~/syncthing/backups/

# 按大小排序列出所有备份
ls -lhS ~/syncthing/backups/*.tar.gz

# 按时间排序列出
ls -lht ~/syncthing/backups/*.tar.gz
```

> **提示**：删除服务器上的备份文件后，Syncthing 不会自动删除 Windows 端已同步的对应文件（因为 Windows 端设置为"仅接收"模式）。如需同步删除，需在 Windows 端手动清理 `D:\backups\server-backup\` 中的旧文件。

### 11.7 部署步骤

> 以下步骤基于你的服务器当前状态：CLIProxyAPI 和 sub2api 已在运行，Syncthing 已部署。只需创建备份脚本并配置 cron。

```bash
# 1. 创建备份脚本目录
mkdir -p ~/syncthing/scripts

# 2. 创建备份脚本（内容见 11.4 节）
nano ~/syncthing/scripts/backup-all.sh
chmod +x ~/syncthing/scripts/backup-all.sh

# 3. 手动执行一次备份测试
~/syncthing/scripts/backup-all.sh

# 4. 检查备份产物
ls -la ~/syncthing/backups/

# 5. 确认 Syncthing 已配置好 ~/syncthing/backups 的同步（参照第4、5章）
# 访问 http://186.241.91.116:8384，确认 backups 文件夹为"仅发送"

# 6. 配置 cron 定时任务（参照 11.5 节）
crontab -e
```

### 11.8 验证自动化流程

```bash
# 1. 手动触发备份
~/syncthing/scripts/backup-all.sh

# 2. 检查备份日志
cat ~/syncthing/backups/backup.log

# 3. 检查备份文件
ls -lh ~/syncthing/backups/*.tar.gz

# 4. 验证 SQL 备份完整性
mkdir /tmp/verify && cd /tmp/verify
tar -xzf ~/syncthing/backups/最新备份文件.tar.gz
head -50 */sub2api/sub2api-database.sql    # 应看到 CREATE TABLE 等语句
ls */cpa/auths/                            # 应看到所有认证文件

# 5. 检查 Syncthing 同步状态
docker logs syncthing --tail 20

# 6. 检查 Windows 端
# 打开 D:\backups\server-backup\，确认 .tar.gz 文件已出现
```

### 11.9 从备份恢复（灾难恢复）

当服务器需要重建时，按以下顺序恢复（**建议严格按顺序执行**）：

#### 第 1 步：上传备份并解压

```bash
# 从 Windows 本地电脑上传最新备份到新服务器
scp D:\backups\server-backup\最新备份.tar.gz root@新服务器IP:~/

# 解压
cd ~ && tar -xzf 最新备份.tar.gz
RESTORE_DIR=$(ls -td */ | head -1)
echo "恢复目录: $RESTORE_DIR"
ls "$RESTORE_DIR"
# 应看到: cpa/  sub2api/  3x-ui/  nginx/
```

#### 第 2 步：恢复 Nginx（反向代理，最先恢复）

```bash
# 安装 nginx
yum install -y nginx   # CentOS/RHEL
# apt install -y nginx  # Debian/Ubuntu

# 恢复配置文件
cp "$RESTORE_DIR/nginx/nginx.conf" /etc/nginx/nginx.conf
cp -r "$RESTORE_DIR/nginx/conf.d" /etc/nginx/conf.d

# 测试配置并启动
nginx -t && systemctl enable --now nginx
```

#### 第 3 步：恢复 3x-ui

```bash
# 安装 3x-ui（官方一键脚本）
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

# 停止服务，恢复数据
systemctl stop x-ui

# 恢复 SQLite 数据库（覆盖安装时生成的空数据库）
cp "$RESTORE_DIR/3x-ui/x-ui.db" /etc/x-ui/x-ui.db

# 恢复 SSL 证书
mkdir -p /etc/ssl/3x-ui
cp "$RESTORE_DIR/3x-ui/ssl/cert.pem" /etc/ssl/3x-ui/
cp "$RESTORE_DIR/3x-ui/ssl/privkey.pem" /etc/ssl/3x-ui/

# 启动
systemctl start x-ui
```

#### 第 4 步：恢复 CLIProxyAPI

```bash
mkdir -p ~/cpa
cp "$RESTORE_DIR/cpa/config.yaml" ~/cpa/
cp -r "$RESTORE_DIR/cpa/auths" ~/cpa/
cp "$RESTORE_DIR/cpa/docker-compose.yml" ~/cpa/

cd ~/cpa && docker compose up -d
```

#### 第 5 步：恢复 sub2api

```bash
mkdir -p ~/sub2api-deploy
cp "$RESTORE_DIR/sub2api/.env" ~/sub2api-deploy/
cp "$RESTORE_DIR/sub2api/docker-compose.yml" ~/sub2api-deploy/
cp -r "$RESTORE_DIR/sub2api/data" ~/sub2api-deploy/

# 先启动 PostgreSQL 和 Redis
cd ~/sub2api-deploy
docker compose up -d postgres redis
sleep 10  # 等待 PG 就绪

# 导入数据库
cat "$RESTORE_DIR/sub2api/sub2api-database.sql" | \
    docker exec -i sub2api-postgres psql -U sub2api -d sub2api

# 启动 sub2api
docker compose up -d sub2api
```

#### 第 6 步：恢复 Syncthing + 备份脚本

```bash
# 创建目录
mkdir -p ~/syncthing/{config,scripts,backups}

# 部署 Syncthing（参照第 2 章的 docker-compose.yml）
cat > ~/syncthing/docker-compose.yml << 'EOF'
version: "3.8"
services:
  syncthing:
    image: lscr.io/linuxserver/syncthing:latest
    container_name: syncthing
    hostname: my-cloud-server
    environment:
      - PUID=0
      - PGID=0
      - TZ=Asia/Shanghai
    volumes:
      - ~/syncthing/config:/config
      - ~/syncthing/backups:/data/backups
    ports:
      - "8384:8384"
      - "22000:22000/tcp"
      - "22000:22000/udp"
      - "21027:21027/udp"
    restart: unless-stopped
EOF
cd ~/syncthing && docker compose up -d

# 创建备份脚本（内容见 11.4 节，或从本地电脑上传）
# nano ~/syncthing/scripts/backup-all.sh
chmod +x ~/syncthing/scripts/backup-all.sh

# 恢复 cron 定时任务
(crontab -l 2>/dev/null; echo "0 3 * * * \$HOME/syncthing/scripts/backup-all.sh >> \$HOME/syncthing/backups/cron.log 2>&1") | crontab -

# 重新配对 Windows 设备（参照第 4、5 章）
# 访问 http://新服务器IP:8384
```

#### 第 7 步：验证所有服务

```bash
# 检查所有容器
docker ps

# 检查 systemd 服务
systemctl status x-ui nginx

# 测试各服务端口
curl -s http://127.0.0.1:8317/health  # CLIProxyAPI
curl -s http://127.0.0.1:8080/health  # sub2api
curl -s http://127.0.0.1:8384         # Syncthing

# 手动执行一次备份确认正常
~/syncthing/scripts/backup-all.sh
```

### 11.10 完整自动化流程图

```
                     每天凌晨 3:00（cron 触发）
                              │
                              ▼
              ┌───────────────────────────────┐
              │     backup-all.sh 执行        │
              │                               │
              │  1. cp ~/cpa/ 配置+认证凭据    │
              │  2. pg_dump sub2api 数据库     │
              │     + cp .env 和 data/        │
              │  3. cp 3x-ui 数据库+SSL证书   │
              │  4. cp Nginx 配置文件          │
              │  5. tar.gz 打包压缩            │
              │  6. 清理超过7天的旧备份          │
              └───────────────┬───────────────┘
                              │
                              ▼
                    ~/syncthing/backups/
                    20260510_030000.tar.gz
                              │
                              │  Syncthing 自动检测变化
                              │  P2P 加密传输
                              ▼
              ┌───────────────────────────────┐
              │     Windows 本地电脑            │
              │     D:\backups\server-backup\  │
              │     20260510_030000.tar.gz     │
              │                               │
              │     ✅ 安全备份完成              │
              └───────────────────────────────┘
```

