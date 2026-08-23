---
spec: '03-00-dsh-web-direct-connect'
scene: '00-default'
status: in-progress
priority: P0
created: '2026-08-23'
---

# 03-00 Dsh Web Direct Connect - 需求

## L0 摘要

为 iOS App 新增"直连网页端"模式：输入 DSH 部署地址与账号密码即可像浏览器一样直连 DeepSeek Harness 网页端（本地或远程域名），不改动网页端任何代码。

## L1 概览

### 目标

在不修改 DeepSeek Harness（网页端）及其插件的前提下，让本 App 通过网页端自身的原生协议完成登录与远程控制：经 `dsh-passwords` 密码门用账号密码换取会话 Cookie，之后直接调用 DSH 的 `/api/*` RPC 并订阅 `/api/events.mux`、`/api/events.host` 两个下行 WebSocket，实现工作区/会话/实时对话的完整移动端体验。现有"移动桥接"模式保持可用，两种模式在设置中切换。

### 用户故事

- 作为 DSH 用户，我希望在 App 里输入域名 + 账号密码就能登录网页端，以便不用配置任何网关插件和配对码。
- 作为 DSH 用户，我希望通过公网域名（https/wss）远程使用 App 控制家里的 Harness，以便在外出时继续对话和监控 Agent 执行。
- 作为 DSH 用户，我希望在局域网内直接输入 `http://<ip>:3080` 直连未加密码门的 DSH，以便本机调试零配置。
- 作为已有用户，我希望保留原有扫码配对的桥接模式，以便旧部署不受影响。

### 范围

**包含**：
- `dsh-passwords` 登录流程客户端实现（CSRF 获取、表单提交、Cookie 持久化）
- 无密码门部署的直连支持（自动探测、免登录）
- DSH 原生协议传输层：RPC POST + 双下行 WS + respond 应答
- 原生协议到现有 GatewayFrame 状态流的适配层
- 远程控制核心能力：工作区列表、会话列表、历史分页、实时流式对话、发送消息（含图片）、取消会话、提问应答、审批应答、模型选择、新建/重命名会话、目录浏览与新建工作区
- 设置页直连模式 UI 与模式切换

**不包含**：
- 网页端/Harness Host 侧的任何改动
- 子代理（subagent）、目标（goals）、技能、凭据管理等设置类页面的完整复刻
- 会话 fork、队列编辑（queue 编辑可后补）、权限预设切换等低频写操作
- Android 端

## L2 详情

### 详细需求

#### F-01 账号密码登录
- 描述：针对带 `dsh-passwords` 密码门的部署，App 先 GET `/gateway/login` 获取 CSRF（Cookie `dsh_csrf`），再以表单编码提交 `username/password/csrf` 到 `POST /gateway/login`，成功后从 Set-Cookie 取得 `dsh_gateway_token`（JWT，12h）。账号密码与 token 均存 Keychain；token 有效期内重启免登录。
- 验收：
  - WHEN 用户输入正确账密 THEN 登录成功并进入已连接状态；
  - WHEN 密码错误 THEN 展示服务端 401 语义的错误且不清空已输入的用户名；
  - WHEN 目标地址不存在密码门（404）THEN 自动按免鉴权直连处理，不报错阻断。

#### F-02 直连原生协议传输层
- 描述：所有 RPC 以 `POST /api/<method>` 发送 `{type:"client-request",rpcId,method,payload}`，解析 `{type:"server-response",rpcId,result}` 信封；事件流以 WebSocket 连接 `/api/events.mux` 与 `/api/events.host`（GET 返回 426 说明该版本仅支持 WS），每条文本消息为 `{type:"server-request",rpcId,method,payload}`；对 answerable 帧（approval/question requested）以 `POST /api/respond` 回 `{type:"client-response",rpcId,result}`。
- 验收：
  - WHEN 双流均打开且 host.describe 成功 THEN 进入 connected 状态；
  - WHEN 任一事件流断开 THEN 自动重连并在恢复后重新拉取基线数据。

#### F-03 远程控制能力映射
- 描述：将原生方法映射进现有状态流：workspace.list→workspaces 帧；session.list→sessions 帧；session.history→history 帧（含 beforeSeq 向前分页）；mux/host 流帧→event 帧（复用既有事件归一化）；session.prompt 成功→sent 帧；question/requested→question-requested 帧；session.models→models 帧。
- 验收：
  - WHEN 选择会话 THEN 能加载历史并跟随实时增量渲染；
  - WHEN 发送消息 THEN Agent 正常执行且流式内容逐步显示；
  - WHEN Agent 发起提问/审批 THEN App 可作答且执行继续；
  - WHEN 点击停止 THEN 当前回合被取消。

#### F-04 模式共存与切换
- 描述：设置页提供"连接方式"选择（移动桥接 / 直连网页端）。桥接路径行为不变；直连模式的地址、账号、密码、token 独立存储。
- 验收：
  - WHEN 切换模式 THEN 使用对应凭据与端点重连，互不污染。

#### F-05 地址形态兼容
- 描述：直连地址支持 `https://domain`（公网）、`http://ip:port`（局域网）；HTTP 升级为 ws，HTTPS 升级为 wss。
- 验收：
  - WHEN 输入 https 域名 THEN RPC 走 https、WS 走 wss 且握手携带 Cookie。

### 非功能性需求

- 性能：历史分页沿用现有预算策略；WS 帧解码不阻塞主线程。
- 兼容性：iOS 17+；对未知事件类型保留原样透传（ignorable 语义）；对不支持的方法（context-usage 等）静默降级不崩溃。
- 安全：账号密码/token 仅存 Keychain；日志不输出凭据。

### 边界与依赖

- 依赖外部：DeepSeek Harness（≥0.1.0-rc.6 实测版本）与可选的 dsh-passwords ≥2.5.1；协议以本机安装包源码为准（dsh-host-apiproxy/dsh-client-connection/dsh-passwords dist）。
- 不依赖其他 Spec。

### 验收标准

- [ ] 初始失败信号：当前 App 无法用账号密码直连域名使用网页端能力
- [ ] 完成后：在同一部署上分别验证 局域网 http 直连 与 公网 https+密码门 直连，均可完成 登录→浏览会话→发送消息→流式接收→回答提问→取消 全链路
- [ ] 所有任务完成
- [ ] 单元测试通过（协议信封构造/解析、帧翻译）
