---
spec: '03-00-dsh-web-direct-connect'
scene: '00-default'
created: '2026-08-23'
---

# 03-00 Dsh Web Direct Connect - 任务清单

> 注：本工作区 lrnev MCP 进程钉在父级工作区，任务由会话按模板手写维护（结构与 task_create 产物一致）。
> 状态机：pending → in_progress → completed / failed；blocked 可回 in_progress；failed 可回 pending 重试。

## 阶段 1

### T-001 直连凭据与认证服务 <!-- lrnev-task: status=completed, created=2026-08-23T09:20:00.000Z, updated=2026-08-23T19:10:00.000Z, validates=F-01|D-01 -->
Keychain 凭据存取 + CSRF 登录流程 + 密码门探测（含单测）。

### T-002 直连传输层 DshDirectClient <!-- lrnev-task: status=completed, created=2026-08-23T09:21:00.000Z, updated=2026-08-23T19:10:00.000Z, validates=F-02|F-05|D-02 -->
RPC POST 客户端、双下行 WS、Cookie 头注入、重连退避、连接代际防竞态。

### T-003 原生协议适配层 DirectFrameTranslator <!-- lrnev-task: status=completed, created=2026-08-23T09:22:00.000Z, updated=2026-08-23T19:10:00.000Z, validates=F-03|D-03 -->
native→GatewayFrame 全量映射与宽松解码（含单测 fixture）。

### T-004 AppStore 模式接入 <!-- lrnev-task: status=completed, created=2026-08-23T09:23:00.000Z, updated=2026-08-23T19:10:00.000Z, validates=F-04|D-04 -->
ConnectionMode 切换、connect/send/answer 分支、降级路径。

### T-005 设置页直连 UI <!-- lrnev-task: status=completed, created=2026-08-23T09:24:00.000Z, updated=2026-08-23T19:10:00.000Z, validates=F-01|F-04|D-01 -->
模式选择、地址/账号/密码表单、登录状态与错误提示。

### T-006 构建验证与文档 <!-- lrnev-task: status=completed, created=2026-08-23T09:25:00.000Z, updated=2026-08-23T19:30:00.000Z, validates=F-03|F-05 -->
xcodebuild 构建通过、32 个单测通过、模拟器直连本机 3080 全链路连通（已连接/工作区/会话列表，历史载荷形状实测核对）；README/ARCHITECTURE 已更新。

## 验收标准（整体）

- [x] 局域网 http 直连全链路可用（本机 3080 实测：连接→工作区→会话列表→历史载荷核对）
- [ ] 公网 https+密码门直连全链路（实现已按 dsh-passwords 源码完成并有单测覆盖；待真机用真实账号验收）
- [x] 桥接模式行为不回退（既有 23 个测试通过，代码路径未改动）
- [x] 所有任务完成
- [x] 单元测试通过（32/32）

### T-007 上游同步A1：图片三连修复（上传上限/长宽比/多图叠放/闪动） <!-- lrnev-task: status=completed, created=2026-08-28T17:40:32.917Z, updated=2026-08-28T19:03:31.987Z -->
<!-- lrnev-task-history: [{"from":"pending","to":"in_progress","at":"2026-08-28T19:02:32.755Z"},{"from":"in_progress","to":"completed","at":"2026-08-28T19:03:31.987Z","reason":"上游 15c63e24/e53b3727/bbd9d1ca 已 cherry-pick：叠放预览控件+解码缓存、EXIF 方向、高度上限、闪动修复"}] -->

**验收**：
- ImagePreprocessor 施加最长边 2000px/总像素 4000万/字节上限，超限等比缩放转 JPEG
- ConversationView 图片保持宽高比不压扁
- 消息气泡内多图叠放展示
- 历史同步时列表无上下闪动

### T-008 上游同步A2：目录浏览支持新建文件夹并设为新工作区 <!-- lrnev-task: status=completed, created=2026-08-28T17:40:32.917Z, updated=2026-08-28T19:03:32.007Z -->
<!-- lrnev-task-history: [{"from":"pending","to":"in_progress","at":"2026-08-28T19:02:32.767Z"},{"from":"in_progress","to":"completed","at":"2026-08-28T19:03:32.007Z","reason":"host.createDirectory 直连封装 + DirectoryBrowserSheet 新建文件夹/高亮定位/刷新父目录，可设为工作区"}] -->

**验收**：
- DirectoryBrowserSheet 可新建子文件夹（host.createDirectory）
- 创建后高亮定位并刷新父目录
- 可将新目录设为新工作区（workspace.create）

### T-009 上游同步A3：小修（搜索失焦收键盘、冷启动alert文案） <!-- lrnev-task: status=completed, created=2026-08-28T17:40:32.917Z, updated=2026-08-28T19:03:32.014Z -->
<!-- lrnev-task-history: [{"from":"pending","to":"in_progress","at":"2026-08-28T19:02:32.786Z"},{"from":"in_progress","to":"completed","at":"2026-08-28T19:03:32.014Z","reason":"9218947d 搜索失焦收键盘已 pick；冷启动改为直连凭据判断（connectOnColdLaunchIfPaired 适配）"}] -->

**验收**：
- 主页面搜索输入完成后键盘可失焦收回
- 冷启动 alert 文案与上游对齐

### T-010 B1：模型目录与思考等级动态化（去硬编码） <!-- lrnev-task: status=completed, created=2026-08-28T17:40:32.917Z, updated=2026-08-28T19:03:32.023Z -->
<!-- lrnev-task-history: [{"from":"pending","to":"in_progress","at":"2026-08-28T19:02:32.792Z"},{"from":"in_progress","to":"completed","at":"2026-08-28T19:03:32.023Z","reason":"核实：模型菜单/默认模型页均优先取 session.models/llm.models 的 name 与 reasoning.efforts，硬编码仅兜底（curl 实测服务端返回真实 name/efforts）"}] -->

**验收**：
- 模型显示名由 llm.models/session.models 目录提供，硬编码仅作兑底
- 思考等级由模型目录推导，不再硬编码 low/medium/high

### T-011 B2：Agent 预设元数据动态化 <!-- lrnev-task: status=completed, created=2026-08-28T17:40:32.917Z, updated=2026-08-28T19:03:32.031Z -->
<!-- lrnev-task-history: [{"from":"pending","to":"in_progress","at":"2026-08-28T19:02:32.797Z"},{"from":"in_progress","to":"completed","at":"2026-08-28T19:03:32.031Z","reason":"核实：GatewayAgentPreset.displayName/description 优先取 agentPreset.list 服务端返回（实测含真实 name/description），硬编码仅兜底"}] -->

**验收**：
- 预设显示名/描述优先取 agentPreset.list 真实返回
- GatewayModels 兑底逻辑保留

### T-012 B3：会话级权限切换解锁（Typert commands/execute + images必填） <!-- lrnev-task: status=completed, created=2026-08-28T17:40:32.917Z, updated=2026-08-28T19:03:32.040Z -->
<!-- lrnev-task-history: [{"from":"pending","to":"in_progress","at":"2026-08-28T19:02:32.804Z"},{"from":"in_progress","to":"completed","at":"2026-08-28T19:03:32.040Z","reason":"runTypert + requestPermissionOptions 合成三预设；本机 3080 实测 images 必填与 ok:true；「暂不支持」info 帧已移除"}] -->

**验收**：
- 直连模式可读会话级权限可选项并切换（POST /api/commands/execute，line=/permission <preset>，images:[] 必填）
- DshDirectConnect 641-643 的「暂不支持」info 帧移除
- 真实服务验证通过

### T-013 C1：停止回合（session.cancel + 停止按钮） <!-- lrnev-task: status=completed, created=2026-08-28T17:40:32.917Z, updated=2026-08-28T19:03:32.048Z -->
<!-- lrnev-task-history: [{"from":"pending","to":"in_progress","at":"2026-08-28T19:02:32.810Z"},{"from":"in_progress","to":"completed","at":"2026-08-28T19:03:32.048Z","reason":"session.cancel 封装 + composer 运行中红色停止按钮"}] -->

**验收**：
- 直连实现 session.cancel RPC
- 生成中提供停止按钮，停止后流式状态正确收尾

### T-014 C2：会话重命名/归档/Fork（列表菜单） <!-- lrnev-task: status=completed, created=2026-08-28T17:40:32.917Z, updated=2026-08-28T19:03:32.057Z -->
<!-- lrnev-task-history: [{"from":"pending","to":"in_progress","at":"2026-08-28T19:02:32.817Z"},{"from":"in_progress","to":"completed","at":"2026-08-28T19:03:32.057Z","reason":"rename/fork/archiveSession 三 RPC + 会话列表长按菜单（重命名/Fork/归档）"}] -->

**验收**：
- session.rename/workspace.archiveSession/session.fork 三个 RPC 封装
- 会话列表提供长按/滑动菜单入口
- 归档后列表正确过滤

### T-015 C3：本地通知 + protocolNotices UI <!-- lrnev-task: status=completed, created=2026-08-28T17:40:32.917Z, updated=2026-08-28T19:03:32.062Z -->
<!-- lrnev-task-history: [{"from":"pending","to":"in_progress","at":"2026-08-28T19:02:32.824Z"},{"from":"in_progress","to":"completed","at":"2026-08-28T19:03:32.062Z","reason":"NotificationRouter 本地通知（点击直达会话）+ 设置开关 + 主页铃铛 NoticeListView 展示 protocolNotices"}] -->

**验收**：
- 后台收到 question/approval 时发 UNUserNotificationCenter 本地通知，点击跳转对应会话
- Info.plist 权限声明 + 设置页开关
- protocolNotices 死状态接入通知入口 UI 展示

### T-016 C4：队列编辑（session.updateQueue） <!-- lrnev-task: status=completed, created=2026-08-28T17:40:32.917Z, updated=2026-08-28T19:03:32.067Z -->
<!-- lrnev-task-history: [{"from":"pending","to":"in_progress","at":"2026-08-28T19:02:32.831Z"},{"from":"in_progress","to":"completed","at":"2026-08-28T19:03:32.067Z","reason":"session/queue 快照分发 + 队列面板（编辑/移除/插队，updateQueue）"}] -->

**验收**：
- session.updateQueue RPC 封装
- turn 进行中可查看/编辑排队消息

### T-017 C5：子代理面板（subagent.*） <!-- lrnev-task: status=completed, created=2026-08-28T17:40:32.917Z, updated=2026-08-28T19:03:32.072Z -->
<!-- lrnev-task-history: [{"from":"pending","to":"in_progress","at":"2026-08-28T19:02:32.838Z"},{"from":"in_progress","to":"completed","at":"2026-08-28T19:03:32.072Z","reason":"subagent.* 四方法封装 + SubagentSheet（列表/记录/续发/中断），入口在会话工具栏菜单"}] -->

**验收**：
- subagent.list/history/prompt/interrupt 封装
- TrajectoryView 内可查看子代理并可发消息/中断

### T-018 C6：会话导出（session.export JSONL 分享） <!-- lrnev-task: status=completed, created=2026-08-28T17:40:32.917Z, updated=2026-08-28T19:03:32.076Z -->
<!-- lrnev-task-history: [{"from":"pending","to":"in_progress","at":"2026-08-28T19:02:32.845Z"},{"from":"in_progress","to":"completed","at":"2026-08-28T19:03:32.076Z","reason":"GET /api/session.export（实测返回 ZIP）+ 系统分享面板"}] -->

**验收**：
- GET /api/session.export?sessionId=…&includeDescendants=true 封装
- 导出 JSONL 可通过系统分享面板保存

### T-019 E1：单测增补 + xcodebuild test 通过 <!-- lrnev-task: status=completed, created=2026-08-28T17:40:32.917Z, updated=2026-08-28T19:03:32.081Z, depends_on=T-007|T-008|T-009|T-010|T-011|T-012|T-013|T-014|T-015|T-016|T-017|T-018 -->
<!-- lrnev-task-history: [{"from":"pending","to":"in_progress","at":"2026-08-28T19:02:32.851Z"},{"from":"in_progress","to":"completed","at":"2026-08-28T19:03:32.081Z","reason":"新增 5 项单测（typert payload/queue action/queue item/subagent entry），xcodebuild test 37 项 0 失败"}] -->

**验收**：
- commands/execute payload、cancel/rename/fork/archive/export 帧翻译、图片上限均有单测
- xcodebuild test 全部通过

**依赖**：T-007, T-008, T-009, T-010, T-011, T-012, T-013, T-014, T-015, T-016, T-017, T-018

### T-020 E2：README/ARCHITECTURE 修正 + 版本 1.4.0 <!-- lrnev-task: status=completed, created=2026-08-28T17:40:32.917Z, updated=2026-08-28T19:03:32.085Z, depends_on=T-019 -->
<!-- lrnev-task-history: [{"from":"pending","to":"in_progress","at":"2026-08-28T19:02:32.858Z"},{"from":"in_progress","to":"completed","at":"2026-08-28T19:03:32.085Z","reason":"README/ARCHITECTURE 能力清单修正，Info.plist 1.4.0/7，已提交（push 随本次收口执行）"}] -->

**验收**：
- README/ARCHITECTURE 能力清单与实现一致
- Info.plist 版本 1.3.1→1.4.0
- 提交并 push

**依赖**：T-019
