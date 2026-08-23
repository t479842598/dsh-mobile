<div align="center">

<img src="Design/whale-girl-ios-app-promo-16x9-v3.png" alt="鲸鱼娘展示 DeepSeek Harness Mobile iOS 应用" width="100%">

# DeepSeek Harness Mobile

**在 iPhone 上延续 DeepSeek Harness 的原生工作流。**

一个使用 SwiftUI 构建的 DeepSeek Harness iOS 客户端，在移动端还原 WebUI 的对话、轨迹与工作区体验。

![iOS 17+](https://img.shields.io/badge/iOS-17.0%2B-111827?logo=apple&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-Native-F05138?logo=swift&logoColor=white)
![WebSocket](https://img.shields.io/badge/WebSocket-Realtime-2563EB)
![Appearance](https://img.shields.io/badge/Appearance-Light%20%2F%20Dark-6B7280)

</div>

## 项目简介

DeepSeek Harness Mobile 是一个面向 DeepSeek Harness 的原生 iOS 客户端。它支持两种连接方式：

- **直连网页端**（推荐）：像浏览器一样直连 DSH，输入域名和账号密码即可远程控制，无需任何网关插件。公网通过 `dsh-passwords` 密码门 + `https/wss` 安全连接，局域网可免登录直连。
- **移动桥接**：通过 `dsh-plugin-mobile-gateway` / `dsh-plugin-mobile-bridge` 与 Harness 建立 WebSocket 连接，扫码或手动 Token 配对。

两种方式共享同一套状态层与视图，将工作区、会话、实时回复和 Agent 执行轨迹带到 iPhone，同时延续 DeepSeek WebUI 克制、清晰的视觉语言。

界面提供浅色与深色模式，并在支持的系统上使用 Liquid Glass 导航与交互控件；深色首页则以深海蓝、水波纹、网格和点阵鲸鱼构成与 Harness 官网一致的视觉氛围。

## 项目海报

<p align="center">
  <img src="Design/deepseek-harness-xiaohongshu-poster.png" alt="DeepSeek Harness Mobile 项目海报" width="620">
</p>

## 功能亮点

- **直连网页端**：无需任何网关插件，像浏览器一样输入部署地址与账号密码直接连接 DeepSeek Harness 网页端，支持公网域名（`https/wss` + `dsh-passwords` 密码门）与局域网裸部署（`http://<ip>:<port>` 免登录）。
- **原生实时对话**：接收 WebSocket 增量事件，逐步展示正文、思考过程、工具调用和工具结果。
- **历史与实时解耦**：大量历史记录分页合并时，实时尾部仍可独立更新，避免阻塞生成和用户滚动。
- **智能吸底**：停留在底部时跟随新内容；用户主动浏览历史后停止抢夺滚动位置。
- **完整轨迹视图**：查看 Duration、Turns、Calls、Input、Model、Tools 时间线，并展开单条记录的参数、结果、Schema 与耗时。
- **工作区与会话管理**：浏览目录、创建或切换工作区，搜索会话并创建新会话。
- **会话配置**：切换当前会话的模型、思考等级与访问权限。
- **全局默认配置**：设置新会话默认使用的 Agent 预设、权限、模型和思考等级，并与 WebUI 使用同一部署配置。
- **安全配对**：桥接模式支持扫描 WebUI 二维码或手动连接；长期凭据保存在系统安全存储中。直连模式的账号密码与会话 Cookie 同样仅存于 Keychain。
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
    <td align="center"><strong>设置</strong><br>部署默认值与网关状态</td>
    <td align="center"><strong>Agent 预设</strong><br>工具、提示词与能力组合</td>
    <td align="center"><strong>默认模型</strong><br>模型与思考等级</td>
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

### 浅色、深色与设备配对

<table>
  <tr>
    <td width="33.33%" align="center"><img src="Docs/images/screenshots/pairing-light.png" alt="浅色模式设备认证" width="100%"></td>
    <td width="33.33%" align="center"><img src="Docs/images/screenshots/pairing-dark.png" alt="深色模式设备认证" width="100%"></td>
    <td width="33.33%" align="center"><img src="Docs/images/screenshots/conversation-dark.png" alt="深色模式对话" width="100%"></td>
  </tr>
  <tr>
    <td align="center"><strong>浅色配对</strong><br>手动输入配对信息</td>
    <td align="center"><strong>深色配对</strong><br>完整深色模式适配</td>
    <td align="center"><strong>深色对话</strong><br>阅读、代码与输入面板</td>
  </tr>
</table>

## 功能详解

### 对话与轨迹

同一个 Session 内可以在“对话”和“轨迹”之间点击或横向滑动切换。两个页面保持独立生命周期，切换时不会重新加载已有内容。

- 对话页支持 Markdown、代码块、实时 reasoning、工具摘要和工具结果。
- 轨迹页以角色标签和时间轴组织 User、Assistant、Tool 等事件。
- 点击轨迹记录可从 Bottom Sheet 查看请求摘要、原始参数、结果、Token 用量与耗时。

### Agent、模型与权限

应用既能调整当前会话，也能维护之后新建会话使用的部署级默认值：

| 配置 | 能力 |
| --- | --- |
| Agent 预设 | 读取可用预设并设为全局默认值 |
| 默认模型 | 选择 Provider、模型与默认思考等级 |
| 会话模型 | 在运行中的 Session 内切换模型和 reasoning effort |
| 权限 | 支持 `read-only`、`workspace-write`、`danger-full-access` |

### 配对与可信设备

移动端可扫描 WebUI 生成的一次性二维码完成配对。公网地址必须使用 `wss://`，配对码仅可使用一次并会在短时间后过期；已配对设备可在网关管理界面中查看和管理。

> 从 v1.2 起，App 支持两种连接方式（设置 → 连接方式）：
> - **移动桥接**：通过 `dsh-plugin-mobile-gateway` / `dsh-plugin-mobile-bridge` 插件的扫码/Token 配对（本小节）。
> - **直连网页端**：像浏览器一样用账号密码直连 DeepSeek Harness 网页端，无需任何网关插件（见下一小节）。

#### 配对步骤

1. **确认当前尚未配对。** 第一次进入 DshMobile 时，应用可能提示“鉴权失败（HTTP 401）”。这表示当前设备还没有与 Mobile Gateway 完成配对，关闭提示后继续下面的操作即可。

   <p align="center">
     <img src="Docs/images/screenshots/pairing-01-authentication-failed.png" alt="DshMobile 首次启动时提示鉴权失败" width="320">
   </p>

2. **打开配对页面。** 点击 App 右上角的鉴权按钮，在弹出的“设备认证”页面中选择扫码，或准备手动输入 WebUI 生成的 Base64URL 配对 Token。

   <p align="center">
     <img src="Docs/images/screenshots/pairing-dark.png" alt="DshMobile 设备认证与手动输入配对信息页面" width="320">
   </p>

3. **在 WebUI 中打开移动设备管理。** 成功安装并启用 `dsh-plugin-mobile-gateway` 后启动 DeepSeek Harness WebUI，左侧导航栏底部会出现“移动设备”入口，点击进入。

   <p align="center">
     <img src="Docs/images/screenshots/pairing-03-webui-mobile-device-entry.png" alt="DeepSeek Harness WebUI 左下角的移动设备入口" width="100%">
   </p>

4. **开启网关和设备鉴权。** WebUI 右侧会弹出“移动设备”面板，请同时开启“允许移动设备连接”和“设备鉴权”两个开关。

   <p align="center">
     <img src="Docs/images/screenshots/pairing-04-webui-gateway-settings.png" alt="WebUI 移动设备面板中的连接和设备鉴权开关" width="390">
   </p>

5. **确认地址并生成二维码。** 检查 WebSocket 地址是否为手机能够访问的 Mac 局域网 IP，然后填写设备名称并点击“生成配对二维码”。同一局域网可以使用 `ws://`；通过公网连接时必须使用 `wss://`。

   <p align="center">
     <img src="Docs/images/screenshots/pairing-05-webui-qr-token.png" alt="确认 WebSocket 地址并生成配对二维码和 Token" width="390">
   </p>

6. **选择扫码或手动输入。** 根据需要，使用 DshMobile 扫描 WebUI 中的二维码；也可以点击“复制配对 Token”，再将 Token 粘贴到 App 的设备认证页面。配对 Token 只能使用一次，并会在 5 分钟后过期。

7. **确认连接成功。** 配对完成后返回首页，最近会话区域右侧会显示绿色“已连接”状态，此时即可开始使用移动端。

   <p align="center">
     <img src="Docs/images/screenshots/pairing-07-connected.png" alt="DshMobile 配对完成后的已连接状态" width="320">
   </p>

### 直连网页端（无需网关插件）

选择“直连网页端”后，在设置中填写部署地址与账号密码即可像浏览器一样远程使用 Harness，适合公网域名远程控制与局域网免配对直连。

1. **填写部署地址。** 公网部署填域名，例如 `https://ds.example.com`；局域网裸部署填 `http://<Mac-IP>:3080`（未安装密码门时免登录，只填地址即可连接）。

2. **填写账号密码（有密码门时）。** 地址带 `dsh-passwords` 密码门时，App 会自动走“GET /gateway/login 取 CSRF → POST 提交账密 → 持有会话 Cookie”的浏览器同款登录流程；勾选“记住密码”则账号密码与登录 Cookie 都存入 Keychain，后续自动续期。

3. **点击“登录并连接”。** 连接成功后 App 直连 DSH 的原生协议：RPC 走 `POST /api/*`，实时事件走 `/api/events.mux` 与 `/api/events.host` 两条下行 WebSocket，提问/审批通过 `/api/respond` 应答——与网页端共用同一协议面，因此不用修改网页端任何代码。

   常用地址速查：

   | 场景 | 地址 |
   | --- | --- |
   | 本机调试（模拟器） | `http://127.0.0.1:3080` |
   | 局域网 iPhone | `http://<Mac-LAN-IP>:3080` |
   | 公网（带密码门） | `https://<your-domain>` |

> 直连模式当前覆盖：工作区/会话浏览、历史分页、实时流式对话（含图片）、提问与执行审批应答、会话取消、模型切换、新建/重命名、目录浏览与新建工作区、搜索。部署默认配置（默认 Agent/模型/权限）的修改、权限预设切换等低频写操作暂未覆盖，请到 WebUI 操作。

## 技术实现

App 支持两种连接方式，共享同一套帧驱动的状态层与视图：

```
                         DeepSeek Harness
                               │
          ┌────────────────────┼────────────────────┐
          │  桥接模式             │  直连模式              │
          │  dsh-plugin-mobile-  │  dsh-passwords 密码门   │
          │  gateway / bridge    │  (可选)                 │
          │  ws://host:3080/     │                         │
          │  ws/mobile           │  POST /api/* (RPC)      │
          │  (配对码 + Token)      │  /api/events.mux  (WS  │
          │                     │       下行事件流)       │
          └──────────┬──────────┘  /api/events.host (WS  │
                     │               下行信息流)       │
                     │             /api/respond    (应答)  │
                     │             (账密 + Cookie 鉴权)    │
                     └──────────────┬────────────────────┘
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

**桥接模式**（dsh-plugin-mobile-gateway / dsh-plugin-mobile-bridge）：移动端通过 `/ws/mobile` 端点与网关插件建立单一全双工 WebSocket，JSON 帧直传。配对通过 WebUI 二维码或手动输入 Token 完成。

**直连模式**（v1.2 起）：不再依赖任何网关插件，像浏览器一样直连 DSH 网页端。其核心是 DSH 浏览器客户端自身的三条物理通路：
- `POST /api/<method>`（RPC，JSON 信封 client-request ↔ server-response）
- `/api/events.mux`（WebSocket，聚合全会话事件流——仅下行）
- `/api/events.host`（WebSocket，宿主级信息流——仅下行）
- `POST /api/respond`（审批/提问应答）

直连栈（`Core/DshDirectConnect.swift`）负责：账号密码登录（CSRF + Cookie）、RPC 调用、双流生命周期与指数退避重连、原生协议→GatewayFrame 翻译——AppStore 与全部视图仅消费 GatewayFrame，完全不需要感知传输差异。

- SwiftUI 原生界面，必要位置与 UIKit 协作以获得稳定的分页、滚动和增量渲染体验。
- 历史分页与实时事件尾部采用独立数据路径，再按事件身份安全合并。
- 已渲染消息保持稳定，流式传输时只更新正在生成的内容块。
- iOS 26 及以上使用系统 Liquid Glass 能力，较早系统使用视觉一致的材质回放。

## 运行项目

### 环境要求

- macOS 26 与可构建 iOS 17.0+ 的 Xcode 26
- iOS 17.0+ 模拟器或真机
- DeepSeek Harness（≥0.1.0-rc.6 实测）
- **桥接模式**需要：已启用 `dsh-plugin-mobile-gateway`（或 `dsh-plugin-mobile-bridge`）
- **直连模式**不需要任何网关插件，只需 DSH 本身运行即可（公网远程建议安装 `dsh-passwords` 提供账号密码登录）

### 启动步骤

1. 启动 DeepSeek Harness（`dsh web`）。
2. 使用 Xcode 打开 `DeepSeekHarnessMobile.xcodeproj`。
3. 选择 `DeepSeekHarnessMobile` Scheme 和目标设备后运行。
4. 在设置中选择连接方式：
   - **直连网页端**：输入地址 + 账号密码（推荐）
   - **移动桥接**：扫描 WebUI 配对二维码，或手动填写网关地址

本机调试时常用的连接地址：

| 场景 | 桥接地址 | 直连地址 |
| --- | --- | --- |
| iOS Simulator | `ws://127.0.0.1:3080/ws/mobile` | `http://127.0.0.1:3080` |
| 同一局域网内的 iPhone | `ws://<Mac-LAN-IP>:3080/ws/mobile` | `http://<Mac-LAN-IP>:3080` |
| 公网（带密码门） | `wss://<your-domain>/ws/mobile` | `https://<your-domain>` |
| 公网（TLS 反代） | `wss://<your-domain>/ws/mobile` | `https://<your-domain>` |

> [!NOTE]
> 真机不能使用 `127.0.0.1` 访问 Mac，请改用 Mac 的局域网 IP；公网部署应在网关前配置 TLS 反向代理。

## 项目文档

- [架构说明](ARCHITECTURE.md)
- [Harness / WebUI 功能与协议调研](Docs/exploration.md)
- [移动端设计规范](Design/design-spec.md)

## 当前状态

项目仍处于开发阶段，协议与界面会随 DeepSeek Harness 持续演进。它是面向 Harness 的社区原生客户端，不代表 DeepSeek 官方发布。
