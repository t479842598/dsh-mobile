---
title: 'dsh-mobile'
created: '2026-08-23'
---

# dsh-mobile

## L0 摘要

DeepSeek Harness 的原生 iOS 客户端（SwiftUI），支持移动桥接与直连网页端两种方式远程控制 DSH。

## L1 概览

### 项目目标

在 iPhone 上还原 DeepSeek Harness 网页端的对话、轨迹与工作区体验：工作区/会话管理、实时流式对话、Agent 轨迹、模型选择与部署级配置。

### 核心用户

- 自部署 DeepSeek Harness 并希望在移动端使用的开发者。

### 当前阶段

- 桥接模式（dsh-plugin-mobile-gateway/bridge，`/ws/mobile` 配对）已可用并上架开发中。
- 进行中：03-00-dsh-web-direct-connect —— 免网关插件、账密直连网页端（含远程域名），协议为 DSH 原生 RPC+双下行 WS（见 ADR-0001）。

## L2 详情

### 背景

上游仓库 https://github.com/Clarklevis1995/dsh-mobile 。部署侧常见形态：`dsh web`（3080/3090）前置 `dsh-passwords` 密码门与反代（如 ds.274747.xyz）。

### 范围

**包含**：
- iOS App 源码（SwiftUI + URLSession WebSocket/RPC）
- 直连 DSH 原生协议的客户端实现

**不包含**：
- DeepSeek Harness 网页端及其插件的任何改动
- Android 客户端

### 关键约束

- 不修改网页端；协议以本机安装包源码为准，向前兼容用宽松解码。
- 凭据仅存 Keychain。
