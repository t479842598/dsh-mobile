---
spec: '03-00-dsh-web-direct-connect'
scene: '00-default'
created: '2026-08-23'
---

# 03-00 Dsh Web Direct Connect - 设计

## L0 摘要

新增 Direct 连接栈：`DshDirectAuthService`（账密登录+Keychain）→ `DshDirectClient`（RPC POST + 双下行 WS + respond）→ `DirectFrameTranslator`（原生协议→GatewayFrame）注入现有 `AppStore.handle(_:)` 管线，UI 仅增加直连配置区。

## L1 概览

### 架构思路

复用既有单向数据流：让直连栈"说旧话"——把 DSH 原生协议翻译为 AppStore 已消费的 GatewayFrame 词汇，从而不重写状态层与全部视图。传输细节（Cookie 鉴权、426、双流）封死在 Direct 栈内部。

### 主要模块

- `Core/Direct/DshDirectCredentials.swift`：Keychain 存取（账号/密码/网关 token），按 baseURL 隔离。
- `Core/Direct/DshDirectAuthService.swift`：GET /gateway/login 抓 CSRF（Set-Cookie 解析）→ POST 表单登录 → 捕获 dsh_gateway_token；探测密码门是否存在（404=免鉴权）。
- `Core/Direct/DshDirectClient.swift`：通用 RPC（async call(method,payload)）、双 URLSessionWebSocketTask 事件流、2s 重连、Cookie 头注入。
- `Core/Direct/DirectFrameTranslator.swift`：native JSON → GatewayFrame；事件归一化复用 GatewayModels.RawSessionEvent.normalized。
- `Core/AppStore.swift`：连接模式枚举 + 直连分支接线。
- `Views/SettingsView.swift`（+ 必要的子视图）：模式选择与直连表单。

### 关键决策

| 决策 | 选项 | 倾向 | 是否产 ADR |
| --- | --- | --- | --- |
| 事件流载体 | SSE vs WebSocket | WebSocket（服务端对 GET events.* 返回 426，仅支持 WS） | 是 |
| 状态层接入 | 重写 AppStore vs 翻译成 GatewayFrame | 翻译成 GatewayFrame（改动面最小） | 否（实现细节） |
| 登录凭据形态 | 每次输密码 vs 持久化 token | Keychain 存账密+token，token 过期自动用账密重登 | 否 |

> ADR-0001（本工作区）：直连模式采用 DSH 原生协议（RPC POST + 双下行 WS）而非扩展移动网关协议。

## L2 详情

### 模块详细设计

#### D-01 认证与凭据
- `GET <base>/gateway/login`：200 → 解析 Set-Cookie `dsh_csrf`（同时可从 HTML hidden input 兜底）；404/非200 → 判定无密码门，免鉴权模式。
- `POST /gateway/login`（application/x-www-form-urlencoded：username,password,csrf,next=/）：3xx/200 且 Set-Cookie 含 `dsh_gateway_token=` → 成功；401/403/400/429 → 映射错误文案。
- HTTPCookie 手动管理（URLSession cookie 池会跨域泄漏，改用显式 Cookie 头）。token 存 Keychain（service=ai.dsh.mobile.ios.direct）。

#### D-02 直连传输层
- RPC：`call(method, payload) async throws -> JSONValue`；rpcId=UUID().uuidString；超时 30s；非 2xx 抛 TransportError(status)。并发安全（actor 或主 actor + Task）。
- WS：两条独立 `URLSessionWebSocketTask`（wss 升级规则：base https→wss，http→ws），请求头带 `Cookie: dsh_gateway_token=...` 与 `Sec-WebSocket-Protocol: dsh-direct-v1`（仅标识，服务端忽略子协议协商——注意：不得发送不被服务端接受的子协议导致握手失败时则去掉该头）。收到消息即 JSON 解码 ServerRequest 信封。发送任何客户端消息会被服务端以 1008 关闭——绝不向事件流发帧。
- 重连：指数退避（1s 起、上限 30s）；两流均在线后调 host.describe 作为 connected 判据。

#### D-03 帧翻译映射
- `workspace.list` → frame(kind:"workspaces", workspaces:[GatewayWorkspace])：WorkspaceView{workspaceId,path,title,sessionIds,…} → GatewayWorkspace（id/path/title/sessionIds 归并）。
- `session.list` → frame(kind:"sessions", …)：SessionSummary{sessionId,updatedAt,running,blank,cwd,projections.values.sessionListMetadata/title…} → SessionSummary（title 取 projections 键 title*；未知键透传）。
- `session.history` → frame(kind:"history")：events:[HistoryEntry]（升序）→ 现有 raw events；hasMore→hasMore；beforeSeq 游标 = 本页最小 seq-1；尾部页带 projections 基线。
- mux 帧 `session/event` → frame(kind:"event") 复用 RawSessionEvent.normalized；`question/requested` → kind:"question-requested"；`approval/requested` → 以 question UI 承载或先 toast；`stream/error` → kind:"error"。
- host 帧 → 会话运行状态/工作区快照更新（映射到 store 既有字段）。
- `session.prompt` accepted → frame(kind:"sent", sessionId)；命令类响应 text 可作为 assistant 提示。
- 不支持的方法（context-usage/session-stats/permission-options 等）→ 直接回 ok 空 value，UI 显示占位。

#### D-04 AppStore 接入
- `ConnectionMode` 枚举存 UserDefaults；connect() 按 mode 走 GatewayClient 或 DshDirectClient；两者共用 onFrame→handle 管线与 onConnectionFailure。
- 发送消息：direct 分支组装 PromptContentPart（text/image base64）+ clientTimeZone；sessionId 为空时先 session.create(workspaceId:) 再 prompt。

### 数据模型

- 新增 Codable 结构体镜像原生载荷：DshSessionSummary、DshWorkspaceView、DshHistoryEntry、DshMuxEnvelope/DshHostEnvelope、DshModelsCatalog 等（JSONValue 承载弱类型字段，风格与 GatewayModels 一致）。
- 凭据模型：DirectCredentials{baseURL, username, password?, token?}。

### 接口契约

- 对 AppStore 暴露：`DshDirectClient.connect(baseURL:cookie:)`、`call(_:payload:)`、便捷方法 requestWorkspaces()/requestSessions()/requestHistory(...)/sendPrompt(...)/answerQuestion(...)/cancelSession(...)、onFrame/onConnectionFailure 回调 —— 与 GatewayClient 同形，保证 AppStore 分支代码同构。

### 错误处理

- 401（WS 握手/RPC）→ 清 token → 自动账密重登一次 → 再失败才报错引导用户改密。
- 密码门存在但未登录访问 /api → 服务端 302 到登录页（HTML）→ 视作未鉴权信号触发重登。
- WS 1008/1006 → 重连退避；连续失败上报 onConnectionFailure。
- 未知 method/payload 字段 → 宽松解码（JSONValue），向前兼容。

### 测试策略

- 单元测试（XCTest）：RPC 信封构造、ServerResponse/result 解析、CSRF Set-Cookie 解析、帧翻译各映射（fixture JSON 来自真实包源码形状）。
- 集成验证：本机 `dsh web`(3080) 直连 + 模拟密码门行为的手工核对；真机走 ds.274747.xyz 域名全链路人工验收。
