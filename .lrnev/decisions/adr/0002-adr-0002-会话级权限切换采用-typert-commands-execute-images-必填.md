---
number: '0002'
title: ADR 0002 — 会话级权限切换采用 Typert commands/execute（images 必填）
status: proposed
scope: global
created: '2026-08-29'
date: '2026-08-29'
---

# 0002. ADR 0002 — 会话级权限切换采用 Typert commands/execute（images 必填）

## 状态

proposed

## 背景

手机端直连栈（POST /api/<ns>.<method> BFF）没有会话级权限切换方法；WebUI 的权限预设功能实际通过 Typert Remote 端点 POST /api/commands/execute 以斜杠命令方式实现。上游 Clarklevis1995/dsh-mobile 的 Mobile Gateway 踩坑记录（commit 6f55f3c，2026-08-27）证实：harness 新版 descriptor 要求 commands/execute 必填 images 字段，缺省报 arguments-invalid missing \"images\"；其 Gateway 补上 images: [] 后 53 个 dispatch 用例通过。

## 决策

直连栈新增 Typert RPC 通道 POST /api/commands/execute（body: agentId + line + images:[]）用于 /permission 斜杠命令切换会话级权限；权限可选项来源执行时对真实服务验证后再定（commands/list 或会话事件），UI 复用现有权限 Menu。后续队列、子代理等需要斜杠命令通道的能力也走同一端点。

## 备选方案

- 新增权限专用 BFF RPC —— BFF rpc-map 无此方法，需改 harness 本体不可行
- 维持 WebUI 操作权限 —— 手机端体验断裂，与目标相悶

## 后果

待补充

## 参考

- 待补充
