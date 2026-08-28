<div align="center">

<img src="Design/whale-girl-ios-app-promo-16x9-v3.png" alt="鲸鱼娘展示 DeepSeek Harness Mobile iOS 应用" width="100%">

# DeepSeek Harness Mobile

**在 iPhone 上原生直连 DeepSeek Harness，不用装任何网关插件。**

一个使用 SwiftUI 构建的 DeepSeek Harness iOS 客户端。像浏览器一样用部署地址和账号密码直连你的 Harness（局域网免登录、公网走 `dsh-passwords` 密码门），在移动端还原工作区、对话、轨迹的全套体验，与 WebUI 共用同一协议且不需要任何网关插件。

![iOS 17+](https://img.shields.io/badge/iOS-17.0%2B-111827?logo=apple&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-Native-F05138?logo=swift&logoColor=white)
![Appearance](https://img.shields.io/badge/Appearance-Light%20%2F%20Dark-6B7280)

</div>

## 项目简介

DshMobile 通过 DSH 浏览器自身的原生协议直连 DeepSeek Harness，不需要任何额外网关插件：

- **局域网本机/同网段**：填 `http://<ip>:3080` 即连即用，无需密码。
- **公网域名远程**：安装 `dsh-passwords` 密码门后填域名 + 账号密码，走 `https/wss` 安全加密。

通信层由三个物理通路组成（与浏览器一致）：
- `POST /api/<method>`：RPC 调用（工作区列表、会话列表、历史分页、发送消息等）
- `/api/events.mux`（WebSocket）：聚合全部会话事件流，实时推送对话内容、工具调用与提问
- `/api/events.host`（WebSocket）：宿主级信息流（会话增删、运行状态、工作区变化）
- `POST /api/respond`：审批/提问应答

App 内的 `DshDirectClient` 负责登录鉴权（CSRF + Cookie）、RPC 与双下行 WS 生命周期管理及指数退避重连，然后将原生协议翻译成 GatewayFrame 注入既有状态管线——全部视图、历史分页、实时渲染都不需要感知传输差异。

## 功能亮点

- **零插件直连**：像浏览器一样用地址 + 账号密码连接，局域网免登录、公网 HTTPS 加密。
- **原生实时对话**：接收 WebSocket 增量事件，逐步展示正文、思考过程、工具调用和工具结果。
- **历史与实时解耦**：大量历史记录分页合并时，实时尾部仍可独立更新，避免阻塞生成和用户滚动。
- **智能吸底**：停留在底部时跟随新内容；用户主动浏览历史后停止抢夺滚动位置。
- **完整轨迹视图**：查看 Duration、Turns、Calls、Input、Model、Tools 时间线，并展开单条记录的参数、结果、Schema 与耗时。
- **工作区与会话管理**：浏览目录、创建或切换工作区，搜索会话并创建新会话。
- **会话配置**：切换当前会话的模型、思考等级与权限预设。
- **全局默认配置**：查看并修改新会话默认使用的 Agent 预设、权限、模型和思考等级（写操作受 harness PRIVILEGED 限制，远程 403 时提示前往 WebUI）。
- **安全存储**：账号密码与会话 Cookie 仅存于系统 Keychain，日志不输出凭据。
- **移动端交互**：对话与轨迹页面常驻并支持左右滑动切换，保留各自的滚动位置和页面状态。

## 界面预览

### 核心体验

<table>
  <tr>
    <td width="33.33%" align="center"><img src="Docs/images/screenshots/home.png" alt="DeepSeek Harness Mobile 工作区首页" width="100%"></td>
    <td width="33.33%" align="center"><img src="Docs/images/screenshots/conversation-light.png" alt="浅色模式对话" width="100%"></td>
    <td width="33.33%" align="center"><img src="Docs/images/screenshots/trajectory-light.png" alt="浅色模式轨迹" width="100%"></td>
  </tr>
  <tr>
    <td align="center"><strong>工作区首页</strong><br>Harness 视觉与最近会话</td>
    <td align="center"><strong>对话</strong><br>Markdown、代码与工具结果</td>
    <td align="center"><strong>轨迹</strong><br>时间概览与事件时间线</td>
  </tr>
</table>

### 默认配置

<table>
  <tr>
    <td width="33.33%" align="center"><img src="Docs/images/screenshots/settings.png" alt="应用设置" width="100%"></td>
    <td width="33.33%" align="center"><img src="Docs/images/screenshots/agent-presets.png" alt="Agent 预设" width="100%"></td>
    <td width="33.33%" align="center"><img src="Docs/images/screenshots/default-model.png" alt="默认模型" width="100%"></td>
  </tr>
  <tr>
    <td align="center"><strong>设置</strong><br>连接地址与账号配置</td>
    <td align="center"><strong>Agent 预设</strong><br>工具、提示词与能力组合</td>
    <td align="center"><strong>默认模型</strong><br>查看当前的模型与思考等级</td>
  </tr>
</table>

### 工作区操作与轨迹详情

<table>
  <tr>
    <td width="33.33%" align="center"><img src="Docs/images/screenshots/workspace-switcher.png" alt="切换工作区" width="100%"></td>
    <td width="33.33%" align="center"><img src="Docs/images/screenshots/workspace-directory-picker.png" alt="选择工作区目录" width="100%"></td>
    <td width="33.33%" align="center"><img src="Docs/images/screenshots/trajectory-detail-light.png" alt="轨迹详情面板" width="100%"></td>
  </tr>
  <tr>
    <td align="center"><strong>切换工作区</strong><br>快速访问不同项目</td>
    <td align="center"><strong>目录选择</strong><br>浏览并创建工作区</td>
    <td align="center"><strong>轨迹详情</strong><br>摘要、Token 与内容预览</td>
  </tr>
</table>

### 设置与连接

<table>
  <tr>
    <td width="33.33%" align="center"><img src="Docs/images/screenshots/settings.png" alt="直连设置" width="100%"></td>
    <td width="33.33%" align="center"><img src="Docs/images/screenshots/conversation-dark.png" alt="深色模式对话" width="100%"></td>
  </tr>
  <tr>
    <td align="center"><strong>直连设置</strong><br>地址、账号、密码与凭据管理</td>
    <td align="center"><strong>深色对话</strong><br>阅读、代码与输入面板</td>
  </tr>
</table>

## 快速开始

### 环境要求

- macOS 26 与可构建 iOS 17.0+ 的 Xcode 26
- iOS 17.0+ 模拟器或真机

**服务端**：你需要一台运行 DeepSeek Harness（≥0.1.0-rc.6 实测）的机器。

| 使用场景 | 服务端要求 |
| --- | --- |
| 本机调试（模拟器） | `dsh web` 启动即可，无需额外插件 |
| 局域网真机 | `dsh web --host 0.0.0.0`（或使用局域网 IP 作为 trusted-host） |
| 公网远程 | `dsh web` + `dsh-passwords` 密码门 + TLS 反向代理（推荐 nginx + Let's Encrypt） |

### 安装 dsh-passwords（公网远程必需）

`dsh-passwords` 是 DSH 的社区密码门插件，提供账号密码登录与 HTTPS 网关。

```bash
# 1. 全局安装密码门
npm install -g dsh-passwords

# 2. 生成密钥并注册为 DSH 插件
dsh-passwords install

# 3. 生成安装密钥后，打开 dsh-passwords 的 .env 文件填入配置
# .env 位置（macOS npm 全局路径，可用 npm root -g 确认）：
#   <npm-global>/node_modules/dsh-passwords/.env
```

**.env 配置示例**：

```env
SETUP_KEY=<dsh-passwords install 生成的密钥>
MCP_GATEWAY_HOST=127.0.0.1
MCP_GATEWAY_PORT=3080                # 密码门对外端口（用户浏览器和 App 连这里）
MCP_GATEWAY_UPSTREAM=http://127.0.0.1:3090
MCP_GATEWAY_AUTO_TLS=0
MCP_GATEWAY_PUBLIC_HOST=ds.example.com
```

> 实际部署建议：`dsh web --port 3090` 把 web 移到 3090，密码门自动接管 3080。访问时只需填密码门地址（如 `https://ds.example.com`），`dsh-passwords` 负责反向代理 + 登录鉴权，无需暴露 `3090`。

**首次设置**：

1. 浏览器打开 `http://localhost:3080/gateway/login`（或你的公网域名）
2. 输入 `.env` 里的 `SETUP_KEY`
3. 创建主账号（用户名 ≥ 3 位，密码 ≥ 12 位强密码）

**公网部署（nginx 反向代理）**：

```nginx
server {
    listen 443 ssl;
    server_name ds.example.com;
    # … SSL 证书配置 …

    location / {
        proxy_pass http://127.0.0.1:3080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}
```

> 关键：WebSocket 升级必须穿透反代（`Upgrade` / `Connection` 头），超时设为一天（`86400s`），否则实时事件流会中断。

**使用 Docker 部署**：

```bash
# DSH + dsh-passwords 一键容器化（推荐使用社区维护的 compose 文件）
# 参考：https://github.com/t479842598/dsh-deploy（示例）
docker run -d \
  --name dsh \
  -p 3080:3080 \
  -p 3090:3090 \
  -v ~/.dsh:/root/.dsh \
  -e DSH_TRUSTED_HOSTS=ds.example.com \
  your-dsh-image
```

> Docker 部署时注意挂载 `~/.dsh` 以持久化会话、凭据与插件配置；`DSH_TRUSTED_HOSTS` 需包含你的公网域名。

### App 连接步骤

1. 启动 DeepSeek Harness（`dsh web`，公网场景先配置好 `dsh-passwords`）。
2. Xcode 打开 `DeepSeekHarnessMobile.xcodeproj`，选择 Scheme 和目标设备运行。
3. 进入设置 → 在「直连网页端」区域填入地址和账号密码，点击「登录并连接」。

| 场景 | 直连地址 |
| --- | --- |
| iOS 模拟器（本机调试） | `http://127.0.0.1:3080` |
| 同一局域网内的 iPhone | `http://<Mac-LAN-IP>:3080` |
| 公网（带 dsh-passwords） | `https://<your-domain>` |
| 公网（TLS 反代 + dsh-passwords） | `https://<your-domain>` |

> [!NOTE]
> 真机不能使用 `127.0.0.1` 访问 Mac，请改用 Mac 的局域网 IP。局域网裸部署的 DSH（未装密码门）只填地址即可免登录连接。

## 技术实现

```
                    DeepSeek Harness (DSH)
                            │
               dsh-passwords 密码门（可选）
               ┌────────────┼────────────┐
               │  POST /api/*       (RPC) │
               │  /api/events.mux   (WS)  │
               │  /api/events.host  (WS)  │
               │  /api/respond      (应答) │
               │  (账密登录 → Cookie 鉴权) │
               └────────────┬────────────┘
                            │
              ┌─────────────▼─────────────┐
              │     DshDirectClient        │
              │  · 登录（CSRF + Cookie）     │
              │  · RPC 调用                 │
              │  · 双下行 WS 生命周期        │
              │  · 协议翻译（→GatewayFrame） │
              └─────────────┬─────────────┘
                            │
               GatewayFrame → AppStore.handle(_:)
                            │
                  ┌─────────┼─────────┐
                  │         │         │
             Workspace  Conversation  Settings
                  │         │         │
                  └─────────┼─────────┘
                            ▼
             SwiftUI + UIKit interoperability
```

- SwiftUI 原生界面，必要位置与 UIKit 协作以获得稳定的分页、滚动和增量渲染体验。
- 历史分页与实时事件尾部采用独立数据路径，再按事件身份安全合并。
- 已渲染消息保持稳定，流式传输时只更新正在生成的内容块。
- 双下行 WS 配有 30s 间隔的 keepalive ping，防止 iOS 回收空闲 TCP 连接。
- iOS 26 及以上使用系统 Liquid Glass 能力，较早系统使用视觉一致的材质回退。
- 连接中断自动指数退避重连（临时网络故障不终止），凭据过期自动用 Keychain 已存账密重登。

## 当前覆盖范围

### 已支持

| 能力 | 说明 |
| --- | --- |
| 工作区列表 | 浏览、创建、切换工作区；目录浏览中可直接新建文件夹并设为工作区 |
| 会话列表 | 按最近活动排序，显示标题、运行状态、未读标记；长按重命名/Fork/归档 |
| 实时流式对话 | Markdown 渲染、思考过程、工具调用/结果、图片附件（多图叠放 + 点击查看大图） |
| 历史分页 | 向前加载更早记录，尾部事件独立更新 |
| 发送消息 | 文字 + 图片，自动创建新会话 |
| 提问应答 | Agent 提问/审批的 UI 交互与提交；后台到达时发本地通知并可点击直达会话 |
| 会话取消 | 停止当前回合（session.cancel） |
| 模型切换 | 浏览并选择模型/思考等级（目录与等级均由服务端提供） |
| 权限切换 | 会话级权限预设切换（Typert commands/execute 斜杠命令通道） |
| 队列编辑 | 排队消息查看/编辑/移除/插队（session/queue 快照 + session.updateQueue） |
| 子代理 | 查看会话的子代理谱系，读取记录、续发消息、中断运行 |
| 会话导出 | 导出会话为 ZIP（含子代理），经系统分享面板保存 |
| 会话搜索 | 按内容搜索会话 |
| 目录浏览 | 服务端文件系统导航与工作区创建 |
| 轨迹视图 | Turn/Step/Tool 时间线与详情 |
| 协议通知中心 | 主页铃铛入口，展示协议事件与操作结果 |

### 暂未覆盖

自定义 Agent 预设的创建/编辑、非图片文件上传、APNs 远程推送、中英双语本地化——这些能力 App 会给出提示或保持入口隐藏，不会崩溃。默认配置写操作（默认 Agent/模型/权限）已支持，但受 harness PRIVILEGED 限制：远程域名返回 403 时提示前往 WebUI 操作。

## 项目文档

- [架构说明](ARCHITECTURE.md)
- [Harness / WebUI 功能与协议调研](Docs/exploration.md)
- [移动端设计规范](Design/design-spec.md)

## 当前状态

项目持续随 DeepSeek Harness 演进。它是面向 Harness 的社区原生 iOS 客户端，不代表 DeepSeek 官方发布。