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
