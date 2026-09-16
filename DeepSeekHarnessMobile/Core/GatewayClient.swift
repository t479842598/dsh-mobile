import Foundation
import Security

// 非 final：保留子类扩展点（直连栈已移除，见 git 历史）。
@MainActor
class GatewayClient: ObservableObject {
    /// History responses contain raw trajectory events (including request
    /// context) and can exceed URLSessionWebSocketTask's 1 MiB default.
    /// Gateway v0.1.12 normally keeps history pages below 4 MiB. Retain a much
    /// larger transport ceiling for the documented case where one indivisible
    /// event is itself larger than the page budget.
    static let maximumIncomingMessageSize = 64 * 1024 * 1024

    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var serverPort: Int?
    @Published private(set) var clientCount: Int?

    var onFrame: ((GatewayFrame) -> Void)?
    var onConnectionFailure: ((String) -> Void)?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    var reconnectTask: Task<Void, Never>?
    private var endpoint: URL?
    var wantsConnection = false
    private var pairingCode: String?
    var lastReportedFailure: String?
    /// iOS may suspend and tear down a normal WebSocket after the app moves
    /// into the background. Keep this lifecycle state separate from protocol
    /// failures so an expected transport interruption doesn't become a modal
    /// error when the app returns to the foreground.
    // 后台生命周期标记对直连子类可见（iOS 挂起会拆掉 WebSocket，见下方注释）。
    var isApplicationInBackground = false
    var isRecoveringFromBackground = false

    deinit {
        receiveTask?.cancel()
        reconnectTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
    }

    /// 供同模块的直连子类驱动连接状态（state 的 setter 保持 private）。
    func updateState(_ newValue: ConnectionState) {
        state = newValue
    }

    func connect(to rawEndpoint: String) {
        isRecoveringFromBackground = false
        beginConnection(to: rawEndpoint, pairingCode: nil, resetReportedFailure: true)
    }

    func connectForPairing(_ payload: GatewayPairingPayload) {
        isRecoveringFromBackground = false
        beginConnection(to: payload.publicUrl, pairingCode: payload.pairingCode, resetReportedFailure: true)
    }

    /// 该网关地址在 Keychain 里是否有已保存的配对凭据（冷启动自动重连判断用）。
    func hasStoredCredential(for rawEndpoint: String) -> Bool {
        guard let url = URL(string: rawEndpoint) else { return false }
        return GatewayTokenStore.load(for: url) != nil
    }

    /// Records the scene transition and optionally keeps the transport alive
    /// while AppStore owns a finite UIKit background-task assertion.
    func applicationDidEnterBackground(keepConnectionAlive: Bool) {
        isApplicationInBackground = true
        isRecoveringFromBackground = true
        if !keepConnectionAlive {
            suspendTransportForBackground()
        }
    }

    /// Restores the transport immediately instead of waiting for the delayed
    /// reconnect loop. A successful `hello` clears recovery mode.
    func applicationDidBecomeActive() {
        isApplicationInBackground = false
        guard wantsConnection, !state.isConnected, let endpoint else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        beginConnection(
            to: endpoint.absoluteString,
            pairingCode: pairingCode,
            resetReportedFailure: false
        )
    }

    /// Called when iOS revokes the finite background execution allowance.
    /// Closing deliberately avoids repeatedly reconnecting while suspended.
    func backgroundExecutionDidExpire() {
        guard isApplicationInBackground else { return }
        suspendTransportForBackground()
    }

    private func beginConnection(to rawEndpoint: String, pairingCode: String?, resetReportedFailure: Bool) {
        disconnect(reconnect: false)
        guard let url = URL(string: rawEndpoint), ["ws", "wss"].contains(url.scheme?.lowercased() ?? "") else {
            fail("二维码中的 publicUrl 不是有效的 ws:// 或 wss:// 地址", shouldReconnect: false)
            return
        }
        wantsConnection = true
        endpoint = url
        self.pairingCode = pairingCode
        if resetReportedFailure { lastReportedFailure = nil }
        state = .connecting
        var request = URLRequest(url: url)
        do {
            request.setValue(try GatewayDeviceIdentityStore.loadOrCreate(), forHTTPHeaderField: "X-DSH-Device-ID")
        } catch {
            fail("无法读取或创建设备唯一标识：\(error.localizedDescription)", shouldReconnect: false)
            return
        }
        if let pairingCode {
            request.setValue("dsh-mobile-v1, dsh-pair.\(pairingCode)", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        } else if let token = GatewayTokenStore.load(for: url) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("dsh-mobile-v1", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        } else {
            // This still permits the explicitly documented local Debug mode.
            // A production gateway responds with HTTP 401 and the UI routes the
            // user to pairing instead of silently treating the socket as ready.
            request.setValue("dsh-mobile-v1", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        }
        let socket = URLSession.shared.webSocketTask(with: request)
        socket.maximumMessageSize = Self.maximumIncomingMessageSize
        self.socket = socket
        socket.resume()
        receiveTask = Task { [weak self] in await self?.receiveLoop(socket) }
    }

    func disconnect(reconnect: Bool = false) {
        wantsConnection = reconnect
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        pairingCode = nil
        state = .disconnected
    }

    func ping() { send(["type": "ping"]) }

    func requestWorkspaces() { send(["type": "workspaces"]) }
    func requestSessions() { send(["type": "sessions"]) }
    func requestHost() { send(["type": "host"]) }
    func searchSessions(_ query: String) { send(["type": "search", "query": query]) }
    func requestDirectories(path: String? = nil) {
        var payload: [String: Any] = ["type": "directories"]
        if let path, !path.isEmpty { payload["path"] = path }
        send(payload)
    }
    func createWorkspace(path: String) { send(["type": "workspace-create", "path": path]) }
    func createDirectory(path: String, name: String) {
        send(["type": "directory-create", "path": path, "name": name])
    }
    func renameSession(sessionId: String, title: String) {
        send(["type": "session-rename", "sessionId": sessionId, "title": title])
    }
    func archiveSession(sessionId: String) {
        send(["type": "session-archive", "sessionId": sessionId])
    }
    /// 停止当前回合（对齐安卓桥端 session-cancel）。turn/end 由事件流自然收敛。
    func cancelTurn(sessionId: String) {
        send(["type": "session-cancel", "sessionId": sessionId])
    }
    /// 以下为直连原生协议独有能力，网关桥插件没有对应报文：
    /// 调用方已收敛为空态/提示，UI 入口同步隐藏，保留方法仅为编译期兼容。
    func forkSession(sessionId: String) { /* 网关桥模式暂不支持创建 Fork */ }
    func updateQueueItem(sessionId: String, itemId: String, action: DshQueueAction) { /* 网关桥模式暂不支持队列操作 */ }
    func requestSubagents(parentSessionId: String) { /* 网关桥模式暂不支持子代理列表 */ }
    func requestSubagentHistory(
        parentSessionId: String,
        childSessionId: String,
        mode: String,
        beforeSeq: Int? = nil,
        maxMessages: Int = 50
    ) async throws -> (events: [RawSessionEvent], hasMore: Bool) {
        throw BridgeUnsupportedError("网关桥模式暂不支持查看子代理记录")
    }
    func promptSubagent(parentSessionId: String, childSessionId: String, text: String) async throws {
        throw BridgeUnsupportedError("网关桥模式暂不支持与子代理对话")
    }
    func interruptSubagent(parentSessionId: String, childSessionId: String, mode: String) async throws {
        throw BridgeUnsupportedError("网关桥模式暂不支持中断子代理")
    }
    func downloadSessionExport(sessionId: String, includeDescendants: Bool = true) async throws -> Data {
        throw BridgeUnsupportedError("网关桥模式暂不支持导出会话")
    }
    func requestModels(sessionId: String? = nil) {
        var payload: [String: Any] = ["type": "models"]
        if let sessionId, !sessionId.isEmpty { payload["sessionId"] = sessionId }
        send(payload)
    }
    func requestProviders() {
        send(["type": "providers"])
    }
    func selectModel(sessionId: String, provider: String, model: String, reasoningEffort: String?) {
        var payload: [String: Any] = [
            "type": "select-model",
            "sessionId": sessionId,
            "provider": provider,
            "model": model
        ]
        if let reasoningEffort, !reasoningEffort.isEmpty { payload["reasoningEffort"] = reasoningEffort }
        send(payload)
    }
    func requestPermissionOptions(sessionId: String?) {
        var payload: [String: Any] = ["type": "permission-options"]
        if let sessionId, !sessionId.isEmpty { payload["sessionId"] = sessionId }
        send(payload)
    }
    func setPermission(sessionId: String, name: String) {
        send(["type": "permission", "sessionId": sessionId, "name": name])
    }
    func requestContextUsage(sessionId: String) {
        send(["type": "context-usage", "sessionId": sessionId])
    }
    func requestSessionStats(sessionId: String) {
        send(["type": "session-stats", "sessionId": sessionId])
    }
    func requestTasks(sessionId: String) {
        send(["type": "tasks", "sessionId": sessionId])
    }
    func requestGoal(sessionId: String) {
        send(["type": "goal", "sessionId": sessionId])
    }
    func pauseGoal(sessionId: String, ref: GatewayGoalRef) {
        send(["type": "goal-pause", "sessionId": sessionId, "ref": ["id": ref.id, "revision": ref.revision]])
    }
    func resumeGoal(sessionId: String, ref: GatewayGoalRef) {
        send(["type": "goal-resume", "sessionId": sessionId, "ref": ["id": ref.id, "revision": ref.revision]])
    }
    func clearGoal(sessionId: String, ref: GatewayGoalRef) {
        send(["type": "goal-clear", "sessionId": sessionId, "ref": ["id": ref.id, "revision": ref.revision]])
    }
    func editGoal(sessionId: String, ref: GatewayGoalRef, objective: String) {
        send([
            "type": "goal-edit",
            "sessionId": sessionId,
            "ref": ["id": ref.id, "revision": ref.revision],
            "objective": objective
        ])
    }
    func requestAgentPresets() {
        send(["type": "agent-presets"])
    }
    func requestDefaults() {
        send(["type": "defaults"])
    }
    func requestDefaultModel() {
        send(["type": "default-model"])
    }
    func saveDefaultModel(provider: String, model: String, reasoningEffort: String?) {
        var payload: [String: Any] = ["type": "save-default-model", "provider": provider, "model": model]
        if let reasoningEffort, !reasoningEffort.isEmpty { payload["reasoningEffort"] = reasoningEffort }
        send(payload)
    }
    func setDefault(target: String, value: String) {
        send(["type": "set-default", "target": target, "value": value])
    }
    func requestHistory(
        sessionId: String,
        beforeSeq: Int? = nil,
        maxMessages: Int = 50,
        maxBytes: Int? = nil,
        view: String? = nil,
        historyFormatVersion: Int? = nil
    ) {
        var payload: [String: Any] = ["type": "history", "sessionId": sessionId, "maxMessages": maxMessages]
        if let beforeSeq, let historyFormatVersion {
            guard beforeSeq >= 0 else { return }
            payload["beforeSeq"] = beforeSeq
            payload["historyFormatVersion"] = historyFormatVersion
        } else if let beforeSeq {
            payload["beforeSeq"] = beforeSeq
        }
        if let maxBytes { payload["maxBytes"] = maxBytes }
        if let view { payload["view"] = view }
        send(payload)
    }

    func requestAttachment(sessionId: String, attachmentId: String) {
        send([
            "type": "attachment",
            "sessionId": sessionId,
            "attachmentId": attachmentId
        ])
    }

    func subscribe(sessionId: String?) {
        if let sessionId, !sessionId.isEmpty {
            send(["type": "subscribe", "sessionId": sessionId])
        } else {
            send(["type": "unsubscribe"])
        }
    }

    func sendMessage(
        text: String,
        images: [GatewayOutgoingImage] = [],
        sessionId: String?,
        workspaceId: String? = nil
    ) {
        guard let socket else {
            state = .failed("WebSocket 尚未连接")
            return
        }
        let request = GatewayMessageRequest(
            sessionId: sessionId?.isEmpty == false ? sessionId : nil,
            text: text,
            images: images.map {
                GatewayMessageRequest.Image(
                    mediaType: $0.mediaType,
                    data: $0.data,
                    name: $0.name
                )
            },
            workspaceId: sessionId == nil && workspaceId?.isEmpty == false ? workspaceId : nil,
            clientTimeZone: TimeZone.current.identifier
        )
        Task { [weak self] in
            do {
                let payload = try await Task.detached(priority: .userInitiated) {
                    try JSONEncoder().encode(request)
                }.value
                try await socket.send(.string(String(decoding: payload, as: UTF8.self)))
            } catch {
                self?.handleFailure(error, socket: socket)
            }
        }
    }

    func answerQuestion(rpcId: String, sessionId: String, answers: [GatewayQuestionAnswer]) {
        let encodedAnswers: [[String: Any]] = answers.map { answer in
            var value: [String: Any] = [
                "id": answer.id,
                "selected": answer.selected
            ]
            if let custom = answer.custom { value["custom"] = custom }
            return value
        }
        send([
            "type": "question-answer",
            "rpcId": rpcId,
            "sessionId": sessionId,
            "answers": encodedAnswers
        ])
    }

    func cancelQuestion(rpcId: String, sessionId: String) {
        send([
            "type": "question-cancel",
            "rpcId": rpcId,
            "sessionId": sessionId
        ])
    }

    private func send(_ object: [String: Any]) {
        guard let socket else {
            state = .failed("WebSocket 尚未连接")
            return
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: object)
            let text = String(decoding: data, as: UTF8.self)
            Task {
                do { try await socket.send(.string(text)) }
                catch { handleFailure(error, socket: socket) }
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func receiveLoop(_ socket: URLSessionWebSocketTask) async {
        do {
            while !Task.isCancelled {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case .string(let text): data = Data(text.utf8)
                case .data(let payload): data = payload
                @unknown default: continue
                }
                do {
                    // A history page can contain thousands of raw events. JSON
                    // decoding must not occupy the main actor that drives SwiftUI.
                    let frame = try await Task.detached(priority: .userInitiated) {
                        try GatewayWireDecoder.decode(data)
                    }.value
                    if frame.kind == "paired" {
                        guard let endpoint, let token = frame.token, !token.isEmpty else {
                            fail("配对响应缺少长期设备 token，未保存凭据", shouldReconnect: false)
                            return
                        }
                        do {
                            try GatewayTokenStore.save(token, for: endpoint)
                            pairingCode = nil
                        } catch {
                            fail("配对成功，但无法将设备 token 写入 Keychain：\(error.localizedDescription)", shouldReconnect: false)
                            return
                        }
                    } else if frame.kind == "hello" {
                        // `hello` is the protocol's authentication boundary.
                        // Debug mode may explicitly return authenticated=false.
                        state = .connected
                        lastReportedFailure = nil
                        isRecoveringFromBackground = false
                        serverPort = frame.port
                        clientCount = frame.clients
                    }
                    onFrame?(frame)
                } catch {
                    // One future or malformed frame must not tear down an otherwise healthy socket.
                    onFrame?(GatewayFrame(kind: "error", code: "decode-failed", message: error.localizedDescription))
                }
            }
        } catch is CancellationError {
            return
        } catch {
            handleFailure(error, socket: socket)
        }
    }

    private func handleFailure(_ error: Error, socket: URLSessionWebSocketTask? = nil) {
        guard wantsConnection else { return }
        let nsError = error as NSError
        // `beginConnection` deliberately cancels the previous task before it
        // installs the replacement. Its receive loop can finish one actor turn
        // later, after `wantsConnection` has become true again. Never let that
        // stale cancellation overwrite the new connection or surface as a
        // user-facing "连接失败" alert.
        if let socket, let activeSocket = self.socket, socket !== activeSocket { return }
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        let statusCode = Self.httpResponse(from: socket, error: nsError)?.statusCode
        let closeCode = socket?.closeCode.rawValue
        let closeReason = socket?.closeReason.flatMap { String(data: $0, encoding: .utf8) }
        let detail: String
        let shouldReconnect: Bool
        let shouldReportFailure: Bool
        switch (statusCode, closeCode) {
        case (401, _):
            if pairingCode == nil, let endpoint { GatewayTokenStore.delete(for: endpoint) }
            detail = "鉴权失败（HTTP 401）：设备 token 无效、已被吊销，或配对码已过期/使用过，请重新扫码配对。"
            shouldReconnect = false
            shouldReportFailure = true
        case (503, _):
            detail = "移动网关暂未开启（HTTP 503）。已保留设备凭据，开启网关后会自动重连。"
            shouldReconnect = true
            shouldReportFailure = !(isApplicationInBackground || isRecoveringFromBackground)
        case (_, 4003):
            detail = "服务端已重新开启设备鉴权（WebSocket 4003），请使用已保存的设备凭据重连或重新扫码。"
            shouldReconnect = false
            shouldReportFailure = true
        case (_, 4004):
            detail = "移动网关已关闭（WebSocket 4004）。已保留设备凭据，重新开启后会自动重连。"
            shouldReconnect = true
            shouldReportFailure = !(isApplicationInBackground || isRecoveringFromBackground)
        case (_, _) where nsError.code == NSURLErrorCancelled:
            // The connection was cancelled (e.g. a pairing attempt superseded by
            // a new connect, or the transport torn down deliberately). Do not
            // spin an endless 2s reconnect loop for a cancelled attempt.
            detail = "WebSocket 连接已取消（\(nsError.localizedDescription)）。请重新扫码配对或重试连接。"
            shouldReconnect = false
            shouldReportFailure = !(isApplicationInBackground || isRecoveringFromBackground)
        default:
            let reasonSuffix = closeReason.flatMap { $0.isEmpty ? nil : "；服务端原因：\($0)" } ?? ""
            detail = "WebSocket 连接失败：\(nsError.localizedDescription)（\(nsError.domain) \(nsError.code)）\(reasonSuffix)"
            shouldReconnect = true
            shouldReportFailure = !(isApplicationInBackground || isRecoveringFromBackground)
        }
        fail(detail, shouldReconnect: shouldReconnect, reportFailure: shouldReportFailure)
    }

    private func fail(_ detail: String, shouldReconnect: Bool, reportFailure: Bool = true) {
        state = .failed(detail)
        socket = nil
        receiveTask = nil
        if !shouldReconnect { wantsConnection = false }
        if reportFailure, lastReportedFailure != detail {
            lastReportedFailure = detail
            onConnectionFailure?(detail)
        }
        reconnectTask?.cancel()
        guard shouldReconnect else { return }
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.wantsConnection, let endpoint = self.endpoint else { return }
            self.beginConnection(
                to: endpoint.absoluteString,
                pairingCode: self.pairingCode,
                resetReportedFailure: false
            )
        }
    }

    private func suspendTransportForBackground() {
        wantsConnection = true
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        state = .disconnected
    }

    private static func httpResponse(from socket: URLSessionWebSocketTask?, error: NSError) -> HTTPURLResponse? {
        if let response = socket?.response as? HTTPURLResponse { return response }
        for key in ["NSErrorFailingURLResponseKey", "NSURLErrorFailingURLResponseErrorKey"] {
            if let response = error.userInfo[key] as? HTTPURLResponse { return response }
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return httpResponse(from: socket, error: underlying)
        }
        return nil
    }
}

private struct GatewayMessageRequest: Encodable, Sendable {
    struct Image: Encodable, Sendable {
        var mediaType: String
        // JSONEncoder serializes Data as standard Base64 without a Data URL
        // prefix, exactly matching protocol 3.
        var data: Data
        var name: String?
    }

    let type = "message"
    var sessionId: String?
    var text: String
    var images: [Image]
    var workspaceId: String?
    var clientTimeZone: String
}

private enum GatewayDeviceIdentityStore {
    private static let service = "ai.dsh.mobile.ios.device-identity"
    private static let account = "installation"

    static func loadOrCreate() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           let stored = String(data: data, encoding: .utf8),
           !stored.isEmpty {
            return stored
        }
        guard status == errSecItemNotFound else { throw KeychainError(status: status) }

        let value = UUID().uuidString.lowercased()
        var insertion = query
        insertion.removeValue(forKey: kSecReturnData as String)
        insertion.removeValue(forKey: kSecMatchLimit as String)
        insertion[kSecValueData as String] = Data(value.utf8)
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(insertion as CFDictionary, nil)
        if addStatus == errSecDuplicateItem { return try loadOrCreate() }
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        return value
    }

    private struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain 错误 \(status)"
        }
    }
}

/// 网关桥插件没有对应报文的能力，调用时抛给 AppStore 转成提示。
struct BridgeUnsupportedError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private enum GatewayTokenStore {
    private static let service = "ai.dsh.mobile.ios.gateway-token"

    static func load(for endpoint: URL) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: endpoint),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String, for endpoint: URL) throws {
        let account = account(for: endpoint)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insertion = base
            attributes.forEach { insertion[$0.key] = $0.value }
            let status = SecItemAdd(insertion as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError(status: status) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError(status: updateStatus)
        }
    }

    static func delete(for endpoint: URL) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: endpoint)
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func account(for endpoint: URL) -> String {
        endpoint.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain 错误 \(status)"
        }
    }
}
