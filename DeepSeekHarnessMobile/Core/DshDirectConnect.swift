import Foundation
import Security

// MARK: - 直连模式（Direct Connect）
//
// 让 App 以"浏览器同等方式"直连 DeepSeek Harness 网页端，不依赖任何移动网关插件：
//   1. 部署带 `dsh-passwords` 密码门时：GET /gateway/login 取 CSRF → POST 表单登录
//      → 持有 `dsh_gateway_token` Cookie（JWT，12 小时），后续 HTTP 与 WS 升级都携带它。
//   2. RPC 走 `POST /api/<method>`（client-request/server-response 信封）。
//   3. 事件流是两条仅下行的 WebSocket `/api/events.mux` 与 `/api/events.host`
//      （该版本对 GET 返回 426，SSE 不可用；向流内发送数据消息会被服务端以 1008 关闭，
//       ping/pong 属于协议控制帧，不受影响——开流检测正是靠它完成的）。
//   4. 审批/提问等 answerable 帧用 `POST /api/respond` 应答；取消提问用 error code=cancelled。
// 协议细节以本机安装包源码为准：@deepseek-ai/dsh-host-apiproxy、dsh-client-connection、dsh-passwords。

enum DshDirectProtocol {
    static let gatewayCookieName = "dsh_gateway_token"
    static let csrfCookieName = "dsh_csrf"
    static let rpcTimeout: TimeInterval = 30
    static let reconnectBaseDelay: TimeInterval = 1
    static let reconnectMaxDelay: TimeInterval = 30
}

// MARK: - 凭据存储

/// 直连凭据的 Keychain 存储。账号/密码用于 token 过期后的自动重登，
/// token 用于免密续期。全部按 base URL 隔离。
enum DshDirectCredentialStore {
    struct Credentials: Codable, Equatable {
        var username: String?
        var password: String?
        var token: String?
    }

    private static let service = "ai.dsh.mobile.ios.direct"

    static func load(baseURL: URL) -> Credentials {
        guard let data = keychainRead(account: account(for: baseURL)) else { return Credentials() }
        return (try? JSONDecoder().decode(Credentials.self, from: data)) ?? Credentials()
    }

    static func save(_ credentials: Credentials, baseURL: URL) throws {
        let data = try JSONEncoder().encode(credentials)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: baseURL)
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
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

    static func delete(baseURL: URL) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: baseURL)
        ] as CFDictionary)
    }

    /// 保存失败时静默降级（token 仍可在内存中使用到进程退出）。
    static func saveQuietly(_ credentials: Credentials, baseURL: URL) {
        try? save(credentials, baseURL: baseURL)
    }

    static func account(for baseURL: URL) -> String {
        baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func keychainRead(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain 错误 \(status)"
        }
    }
}

// MARK: - 密码门认证

/// `dsh-passwords` 密码门探测与账号密码登录。
///
/// 登录页每次渲染都会下发 `dsh_csrf` Cookie，且表单隐藏域与 Cookie 同值
/// （double-submit），因此无需解析 HTML 即可完成 CSRF 提交。
enum DshDirectAuthService {
    enum GateStatus: Equatable {
        /// 部署存在密码门，携带本次请求可用的 CSRF token。
        case present(csrf: String)
        /// 目标没有密码门（直连裸 `dsh web`），所有请求免鉴权。
        case absent
    }

    enum AuthError: LocalizedError {
        case invalidURL
        case gateUnreachable(String)
        case notConfigured
        case rejected(status: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                "直连地址无效，请输入 http(s):// 开头的完整地址。"
            case .gateUnreachable(let detail):
                "无法连接网页端：\(detail)"
            case .notConfigured:
                "该部署启用了密码门，请先在设置中填写账号和密码再连接。"
            case .rejected(_, let message):
                message
            }
        }
    }

    /// URLSession 不跟随重定向，保证能读到 302 响应上的 Set-Cookie。
    final class RedirectBlocker: NSObject, URLSessionDataDelegate {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    static func normalizedBaseURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate), let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// ws/wss 升级规则：https → wss，http → ws。
    static func websocketURL(baseURL: URL, path: String) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let isSecure = components?.scheme?.lowercased() == "https"
        components?.scheme = isSecure ? "wss" : "ws"
        components?.path = path
        return components?.url
    }

    static func probeGate(baseURL: URL, session: URLSession) async throws -> GateStatus {
        guard let loginURL = URL(string: "/gateway/login", relativeTo: baseURL)?.absoluteURL else {
            throw AuthError.invalidURL
        }
        var request = URLRequest(url: loginURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AuthError.gateUnreachable("非 HTTP 响应")
            }
            if let csrf = cookieValue(from: http, name: DshDirectProtocol.csrfCookieName) {
                return .present(csrf: csrf)
            }
            return .absent
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.gateUnreachable(error.localizedDescription)
        }
    }

    /// 提交账密换取长期会话 Cookie 值（`dsh_gateway_token=<jwt>`）。
    static func login(
        baseURL: URL,
        username: String,
        password: String,
        csrf: String,
        session: URLSession
    ) async throws -> String {
        guard let loginURL = URL(string: "/gateway/login", relativeTo: baseURL)?.absoluteURL else {
            throw AuthError.invalidURL
        }
        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "csrf", value: csrf),
            URLQueryItem(name: "next", value: "/")
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.gateUnreachable("非 HTTP 响应")
        }
        if let token = cookieValue(from: http, name: DshDirectProtocol.gatewayCookieName) {
            return "\(DshDirectProtocol.gatewayCookieName)=\(token)"
        }
        switch http.statusCode {
        case 200..<400:
            throw AuthError.rejected(
                status: http.statusCode,
                message: "登录未返回会话凭据，请确认部署已安装并启用 dsh-passwords。"
            )
        case 401:
            throw AuthError.rejected(status: http.statusCode, message: "账号或密码错误（HTTP 401）。")
        case 403:
            throw AuthError.rejected(status: http.statusCode, message: "CSRF 校验失败，请重试（HTTP 403）。")
        case 429:
            throw AuthError.rejected(status: http.statusCode, message: "尝试过于频繁或账号已锁定，请稍后再试（HTTP 429）。")
        default:
            throw AuthError.rejected(status: http.statusCode, message: "登录失败（HTTP \(http.statusCode)）。")
        }
    }

    /// 从响应头提取指定 Cookie 值。多段 Set-Cookie 在 HTTPURLResponse 里可能被
    /// 合并展示，这里对原始头做一次定向扫描，避免依赖 HTTPCookie 的解析行为。
    static func cookieValue(from response: HTTPURLResponse, name: String) -> String? {
        for (key, value) in response.allHeaderFields {
            guard (key as? String)?.caseInsensitiveCompare("Set-Cookie") == .orderedSame else { continue }
            let headerText: String
            if let text = value as? String {
                headerText = text
            } else if let descriptions = (value as? [Any])?.compactMap({ $0 as? String }) {
                headerText = descriptions.joined(separator: ", ")
            } else {
                continue
            }
            for pair in headerText.split(separator: ",") {
                let trimmedPair = pair.trimmingCharacters(in: .whitespaces)
                guard trimmedPair.hasPrefix("\(name)=") else { continue }
                let valueStart = trimmedPair.index(trimmedPair.startIndex, offsetBy: name.count + 1)
                let raw = String(trimmedPair[valueStart...])
                if let semicolon = raw.firstIndex(of: ";") {
                    let candidate = String(raw[..<semicolon]).trimmingCharacters(in: .whitespaces)
                    if !candidate.isEmpty { return candidate }
                } else if !raw.isEmpty {
                    return raw
                }
            }
        }
        return nil
    }
}

// MARK: - 原生协议 → GatewayFrame 翻译层

/// 把 DSH 原生协议载荷翻译成 AppStore 已消费的 GatewayFrame 词汇，
/// 使状态层与全部视图在两种传输模式下复用。
enum DirectFrameTranslator {
    // workspace.list → workspaces 帧
    static func workspacesFrame(from value: JSONValue) -> GatewayFrame {
        GatewayFrame(kind: "workspaces", items: value["items"]?.arrayValue ?? [], archivedSessionIds: stringArray(value["archivedSessionIds"]))
    }

    // session.list → sessions 帧
    static func sessionsFrame(from value: JSONValue) -> GatewayFrame {
        GatewayFrame(kind: "sessions", items: value["items"]?.arrayValue ?? [])
    }

    // host.describe → host 帧
    static func hostFrame(from value: JSONValue) -> GatewayFrame {
        var frame = GatewayFrame(kind: "host")
        frame.version = value["version"]?.stringValue
        frame.cwd = value["cwd"]?.stringValue
        frame.provider = value["provider"]?.stringValue
        frame.model = value["model"]?.stringValue
        frame.attachedSessions = value["attachedSessions"]?.doubleValue.map(Int.init)
        frame.canOpenPath = value["canOpenPath"]?.boolValue
        return frame
    }

    // session.search → search 帧
    static func searchFrame(from value: JSONValue, query: String) -> GatewayFrame {
        GatewayFrame(kind: "search", items: value["items"]?.arrayValue ?? [], hasMore: value["hasMore"]?.boolValue, query: query)
    }

    // host.listDirectory → directories 帧（DirectoryListing 字段与帧字段同名同形）
    static func directoriesFrame(from value: JSONValue, requestedPath: String?) -> GatewayFrame {
        var frame = GatewayFrame(kind: "directories")
        frame.path = value["path"]?.stringValue ?? requestedPath
        frame.home = value["home"]?.stringValue
        frame.crumbs = decodeItems(value["crumbs"])
        frame.entries = decodeItems(value["entries"])
        frame.truncated = value["truncated"]?.boolValue
        return frame
    }

    // workspace.create → workspace-create 帧
    static func workspaceCreateFrame(from value: JSONValue) -> GatewayFrame {
        var frame = GatewayFrame(kind: "workspace-create")
        if let workspace = value["workspace"] {
            frame.workspace = workspace.decode(GatewayWorkspace.self)
        }
        frame.created = value["created"]?.boolValue
        return frame
    }

    // session.history → history 帧。原生分页按 beforeSeq 截断、返回升序事件；
    // 桥接协议的游标语义一致，nextBeforeSeq 由本页最小 seq 推导。
    static func historyFrame(from value: JSONValue, sessionId: String?, beforeSeq: Int?) -> GatewayFrame {
        let entries = value["events"]?.arrayValue ?? []
        let rawEvents = entries.compactMap { $0["event"] }.map { event in
            RawSessionEvent(
                type: event["type"]?.stringValue ?? "unknown",
                seq: event["seq"]?.doubleValue.map(Int.init) ?? 0,
                time: event["time"]?.doubleValue ?? 0,
                data: event["data"] ?? .null
            )
        }
        let hasMore = value["hasMore"]?.boolValue ?? false
        var frame = GatewayFrame(kind: "history")
        frame.sessionId = sessionId
        frame.events = rawEvents.sorted { $0.seq < $1.seq }
        frame.hasMore = hasMore
        if hasMore, let earliest = rawEvents.map(\.seq).min() {
            frame.nextBeforeSeq = max(0, earliest - 1)
        } else {
            frame.nextBeforeSeq = nil
        }
        frame.bytes = 0
        // 尾页携带投影基线（asOfSeq + values），与桥接协议形状一致。
        frame.projections = value["projections"]
        return frame
    }

    // session.models / llm.models → models 帧
    static func modelsFrame(from value: JSONValue, sessionId: String?, global: Bool) -> GatewayFrame {
        var frame = GatewayFrame(kind: "models")
        frame.sessionId = global ? nil : sessionId
        frame.current = value["current"]?.decode(GatewayModelSelection.self)
        frame.routable = value["routable"]?.boolValue
        frame.groups = decodeItems(value["groups"])
        frame.failures = value["failures"]?.arrayValue ?? []
        return frame
    }

    // session.selectModel → select-model 帧
    static func selectModelFrame(from value: JSONValue, sessionId: String) -> GatewayFrame {
        GatewayFrame(
            kind: "select-model",
            sessionId: sessionId,
            selected: value["selected"]?.decode(GatewayModelSelection.self)
        )
    }

    // agentPreset.list → agent-presets 帧（broken 在原生协议里是失败原因字符串）
    static func agentPresetsFrame(from value: JSONValue) -> GatewayFrame {
        let presets = (value["presets"]?.arrayValue ?? []).map { entry -> JSONValue in
            guard let broken = entry["broken"], case .string = broken, var item = entry.objectValue else { return entry }
            item["broken"] = .bool(true)
            return .object(item)
        }
        return GatewayFrame(
            kind: "agent-presets",
            presets: presets.compactMap { $0.decode(GatewayAgentPreset.self) },
            authorable: value["authorable"]?.boolValue,
            hasDocument: value["hasDocument"]?.boolValue
        )
    }

    // session.prompt 被接受 → sent 帧
    static func sentFrame(sessionId: String) -> GatewayFrame {
        GatewayFrame(kind: "sent", sessionId: sessionId)
    }

    // session.attachment → attachment 帧
    static func attachmentFrame(from value: JSONValue, sessionId: String) -> GatewayFrame? {
        guard let encodedData = value["data"]?.stringValue,
              let attachment = value["attachment"]?.decode(GatewayImageAttachment.self) else { return nil }
        return GatewayFrame(kind: "attachment", sessionId: sessionId, attachment: attachment, data: encodedData)
    }

    // mux 流 question/requested → question-requested 帧
    static func questionRequestedFrame(rpcId: String, payload: JSONValue) -> GatewayFrame? {
        guard let sessionId = payload["sessionId"]?.stringValue else { return nil }
        let questions = payload["questions"]?.arrayValue ?? []
        return GatewayFrame(
            kind: "question-requested",
            sessionId: sessionId,
            rpcId: rpcId,
            questions: questions.compactMap { $0.decode(GatewayQuestion.self) },
            replay: payload["replay"]?.boolValue
        )
    }

    // mux 流 approval/requested → 以既有提问 UI 承载审批决策
    static func approvalQuestionFrame(rpcId: String, payload: JSONValue) -> GatewayFrame? {
        guard let sessionId = payload["sessionId"]?.stringValue,
              let approvalId = payload["approvalId"]?.stringValue else { return nil }
        let toolName = payload["toolName"]?.stringValue ?? "工具调用"
        var question: [String: JSONValue] = [
            "id": .string(approvalId),
            "header": .string("执行审批"),
            "question": .string("允许执行「\(toolName)」吗？"),
            "options": .array([
                .object(["label": .string("允许一次")]),
                .object(["label": .string("本次拒绝")])
            ]),
            "intent": .object(["kind": .string("approval"), "approve": .string("允许一次")])
        ]
        if let reason = payload["reason"]?.stringValue, !reason.isEmpty {
            question["detail"] = .string(reason)
        }
        return GatewayFrame(
            kind: "question-requested",
            sessionId: sessionId,
            rpcId: rpcId,
            questions: [JSONValue.object(question)].compactMap { $0.decode(GatewayQuestion.self) },
            replay: payload["replay"]?.boolValue
        )
    }

    // RPC 业务错误 → error 帧（requestType 用于 AppStore 收敛对应的 loading 态）
    static func errorFrame(
        code: String,
        message: String,
        requestType: String?,
        sessionId: String? = nil,
        target: String? = nil,
        value: String? = nil
    ) -> GatewayFrame {
        GatewayFrame(kind: "error", code: code, message: message, requestType: requestType, target: target, value: value)
    }

    private static func decodeItems<T: Decodable>(_ value: JSONValue?) -> [T] where T: Decodable {
        (value?.arrayValue ?? []).compactMap { $0.decode(T.self) }
    }

    private static func stringArray(_ value: JSONValue?) -> [String]? {
        value?.arrayValue?.compactMap(\.stringValue)
    }
}

// MARK: - 直连客户端

/// 直连模式的传输实现。继承 `GatewayClient` 以保持 AppStore 与视图层
/// 的既有类型和调用点不变——实例由 AppStore 按 `ConnectionMode` 切换。
@MainActor
final class DshDirectClient: GatewayClient {
    /// 未勾选"记住密码"时的一次性密码：仅参与本次登录，不落任何存储。
    var transientPassword: String?
    /// `dsh_gateway_token=<jwt>` 形态的会话 Cookie；无密码门部署保持 nil。
    private var cookieHeader: String?
    private var httpBaseURL: URL?
    private var muxSocket: URLSessionWebSocketTask?
    private var hostSocket: URLSessionWebSocketTask?
    private var muxReceiveTask: Task<Void, Never>?
    private var hostReceiveTask: Task<Void, Never>?
    private var connectGeneration = 0
    private var reconnectAttempt = 0
    private var muxOpened = false
    private var hostOpened = false
    private var isAuthenticating = false
    /// 审批帧没有独立 UI：rpcId → (sessionId, approvalId)，答案经提问管线转回 respond。
    private var pendingApprovals: [String: (sessionId: String, approvalId: String)] = [:]
    /// 审批解决帧只带 approvalId，需要反查 rpcId 清理提问状态。
    private var approvalRpcIds: [String: String] = [:]
    private var keepaliveTask: Task<Void, Never>?
    private lazy var redirectBlocker = DshDirectAuthService.RedirectBlocker()
    private lazy var httpSession: URLSession = makeHTTPSession()
    private lazy var socketSession: URLSession = makeHTTPSession()

    override func connect(to rawEndpoint: String) {
        disconnect(reconnect: false)
        guard let base = DshDirectAuthService.normalizedBaseURL(rawEndpoint) else {
            terminate("直连地址无效，请输入 http(s):// 开头的完整地址（例如 https://ds.example.com）。")
            return
        }
        wantsConnection = true
        httpBaseURL = base
        lastReportedFailure = nil
        reconnectAttempt = 0
        updateState(.connecting)
        Task { await self.establishConnection(generation: self.connectGeneration) }
    }

    override func disconnect(reconnect: Bool = false) {
        wantsConnection = reconnect
        connectGeneration &+= 1
        reconnectTask?.cancel()
        reconnectTask = nil
        teardownStreams()
        updateState(.disconnected)
    }

    override func applicationDidEnterBackground(keepConnectionAlive: Bool) {
        isApplicationInBackground = true
        isRecoveringFromBackground = true
        if !keepConnectionAlive { suspendTransportForBackground() }
    }

    override func applicationDidBecomeActive() {
        isApplicationInBackground = false
        guard wantsConnection, state != .connected, httpBaseURL != nil else { return }
        // 递增代际：使所有在后台残留的接收/重连任务静默退出，
        // 避免旧代失败调度新重连与新连接产生竞态（连接⇄失败来回跳的根因）。
        connectGeneration &+= 1
        reconnectTask?.cancel()
        reconnectTask = nil
        let generation = connectGeneration
        Task { await self.establishConnection(generation: generation) }
    }

    override func backgroundExecutionDidExpire() {
        guard isApplicationInBackground else { return }
        suspendTransportForBackground()
    }

    override func ping() {
        // 直连模式的心跳由两条下行流的存活监测承担；ping 仅为兼容设置页入口。
        Task { _ = try? await call("host.describe", .object([:])) }
    }

    // MARK: 查询类方法（RPC → 帧）

    override func requestWorkspaces() {
        runRPC(method: "workspace.list", payload: .object([:]), requestType: "workspaces") {
            DirectFrameTranslator.workspacesFrame(from: $0)
        }
    }

    override func requestSessions() {
        runRPC(method: "session.list", payload: .object([:]), requestType: "sessions") {
            DirectFrameTranslator.sessionsFrame(from: $0)
        }
    }

    override func requestHost() {
        runRPC(method: "host.describe", payload: .object([:]), requestType: "host") {
            DirectFrameTranslator.hostFrame(from: $0)
        }
    }

    override func searchSessions(_ query: String) {
        runRPC(method: "session.search", payload: .object(["query": .string(query)]), requestType: "search") {
            DirectFrameTranslator.searchFrame(from: $0, query: query)
        }
    }

    override func requestDirectories(path: String? = nil) {
        var payload: [String: JSONValue] = [:]
        if let path, !path.isEmpty { payload["path"] = .string(path) }
        runRPC(method: "host.listDirectory", payload: .object(payload), requestType: "directories") {
            DirectFrameTranslator.directoriesFrame(from: $0, requestedPath: path)
        }
    }

    override func createWorkspace(path: String) {
        runRPC(method: "workspace.create", payload: .object(["path": .string(path)]), requestType: "workspace-create") {
            DirectFrameTranslator.workspaceCreateFrame(from: $0)
        }
    }

    override func requestModels(sessionId: String? = nil) {
        let global = sessionId == nil || sessionId?.isEmpty == true
        let method = global ? "llm.models" : "session.models"
        let payload: JSONValue = global ? .object([:]) : .object(["sessionId": .string(sessionId!)])
        runRPC(method: method, payload: payload, requestType: "models") {
            DirectFrameTranslator.modelsFrame(from: $0, sessionId: sessionId, global: global)
        }
    }

    override func selectModel(sessionId: String, provider: String, model: String, reasoningEffort: String?) {
        var payload: [String: JSONValue] = [
            "sessionId": .string(sessionId),
            "provider": .string(provider),
            "model": .string(model)
        ]
        if let reasoningEffort, !reasoningEffort.isEmpty { payload["reasoningEffort"] = .string(reasoningEffort) }
        runRPC(method: "session.selectModel", payload: .object(payload), requestType: "select-model") {
            DirectFrameTranslator.selectModelFrame(from: $0, sessionId: sessionId)
        }
    }

    override func requestAttachment(sessionId: String, attachmentId: String) {
        runRPC(
            method: "session.attachment",
            payload: .object(["sessionId": .string(sessionId), "attachmentId": .string(attachmentId)]),
            requestType: nil
        ) { DirectFrameTranslator.attachmentFrame(from: $0, sessionId: sessionId) }
    }

    override func requestHistory(
        sessionId: String,
        beforeSeq: Int? = nil,
        maxMessages: Int = 50,
        maxBytes: Int? = nil,
        view: String? = nil
    ) {
        var payload: [String: JSONValue] = [
            "sessionId": .string(sessionId),
            "maxMessages": .number(Double(maxMessages))
        ]
        if let beforeSeq { payload["beforeSeq"] = .number(Double(beforeSeq)) }
        runRPC(method: "session.history", payload: .object(payload), requestType: "history") {
            DirectFrameTranslator.historyFrame(from: $0, sessionId: sessionId, beforeSeq: beforeSeq)
        }
    }

    override func requestAgentPresets() {
        runRPC(method: "agentPreset.list", payload: .object([:]), requestType: "agent-presets") {
            DirectFrameTranslator.agentPresetsFrame(from: $0)
        }
    }

    // MARK: 直连暂不支持的方法（合成空成功帧收敛 loading，UI 静默降级）

    override func requestPermissionOptions(sessionId: String?) {
        emit(GatewayFrame(kind: "permission-options", sessionId: sessionId))
    }

    override func setPermission(sessionId: String, name: String) {
        emit(DirectFrameTranslator.errorFrame(code: "unsupported", message: "直连模式暂不支持切换权限预设，请前往 WebUI 操作。", requestType: "permission", sessionId: sessionId))
    }

    override func requestContextUsage(sessionId: String) {
        emit(GatewayFrame(kind: "context-usage", sessionId: sessionId))
    }

    override func requestSessionStats(sessionId: String) {
        emit(GatewayFrame(kind: "session-stats", sessionId: sessionId))
    }

    override func requestDefaults() {
        emitSettingsSnapshot()
    }

    override func requestDefaultModel() {
        emitSettingsSnapshot()
    }

    /// 读 settings.describe，把 agent-default-model/agent-presets/permission 翻译为
    /// defaults + default-model 帧注入 AppStore。所有三个命名空间一次 RPC 拉完。
    private func emitSettingsSnapshot() {
        Task {
            do {
                let describe = try await self.call("settings.describe", .object([:]))
                let namespaces = describe["namespaces"]?.arrayValue ?? []
                let agentPresets = namespaceValue(namespaces, ns: "agent-presets")
                let permission = namespaceValue(namespaces, ns: "permission")
                let defaultModel = namespaceValue(namespaces, ns: "agent-default-model")

                if let defaultPreset = agentPresets?["default"]?.stringValue {
                    cacheSettingsRevision("agent-presets", from: namespaces)
                    emit(GatewayFrame(kind: "defaults", agentPresetDefault: defaultPreset, permissionDefault: permission?["defaultPreset"]?.stringValue))
                }
                if let provider = defaultModel?["provider"]?.stringValue,
                   let model = defaultModel?["model"]?.stringValue {
                    cacheSettingsRevision("agent-default-model", from: namespaces)
                    emit(GatewayFrame(kind: "default-model", selection: GatewayModelSelection(
                        provider: provider,
                        model: model,
                        reasoningEffort: defaultModel?["reasoningEffort"]?.stringValue
                    )))
                }
            } catch {
                emit(DirectFrameTranslator.errorFrame(code: "transport", message: "读取远端设置失败：\(error.localizedDescription)", requestType: "defaults"))
            }
        }
    }

    override func saveDefaultModel(provider: String, model: String, reasoningEffort: String?) {
        var section: [String: JSONValue] = ["provider": .string(provider), "model": .string(model)]
        if let effort = reasoningEffort { section["reasoningEffort"] = .string(effort) }
        writeSetting(ns: "agent-default-model", section: .object(section), requestType: "save-default-model") { value in
            GatewayFrame(kind: "save-default-model", saved: GatewayModelSelection(
                provider: value["provider"]?.stringValue ?? provider,
                model: value["model"]?.stringValue ?? model,
                reasoningEffort: value["reasoningEffort"]?.stringValue ?? reasoningEffort
            ))
        }
    }

    override func setDefault(target: String, value: String) {
        let (ns, section): (String, JSONValue) = {
            switch target {
            case "agent-preset": return ("agent-presets", .object(["default": .string(value)]))
            case "permission": return ("permission", .object(["defaultPreset": .string(value)]))
            default: return (target, .object([:]))
            }
        }()
        writeSetting(ns: ns, section: section, requestType: "set-default") { _ in
            GatewayFrame(kind: "set-default", target: target, value: value, applied: true)
        }
    }

    // MARK: - settings.describe / settings.replace 实现

    private var settingsRevisions: [String: Int] = [:]

    private func namespaceValue(_ namespaces: [JSONValue], ns: String) -> JSONValue? {
        namespaces.first { $0["ns"]?.stringValue == ns }?["value"]
    }

    private func cacheSettingsRevision(_ ns: String, from namespaces: [JSONValue]) {
        if let entry = namespaces.first(where: { $0["ns"]?.stringValue == ns }),
           let rev = entry["revision"]?.doubleValue {
            settingsRevisions[ns] = Int(rev)
        }
    }

    private func writeSetting(
        ns: String,
        section: JSONValue,
        requestType: String,
        frame: @escaping (JSONValue) -> GatewayFrame
    ) {
        Task {
            do {
                let rev = settingsRevisions[ns] ?? 0
                let result = try await self.call("settings.replace", .object([
                    "ns": .string(ns),
                    "section": section,
                    "expectedRevision": .number(Double(rev))
                ]))
                if let newRev = result["revision"]?.doubleValue {
                    settingsRevisions[ns] = Int(newRev)
                }
                let applied = result["value"] ?? section
                emit(frame(applied))
            } catch let error as RPCBusinessError {
                emit(DirectFrameTranslator.errorFrame(code: error.code, message: error.message, requestType: requestType))
            } catch {
                emit(DirectFrameTranslator.errorFrame(code: "transport", message: "修改远端设置失败：\(error.localizedDescription)", requestType: requestType))
            }
        }
    }

    override func requestProviders() {
        // 全局模型目录（llm.models）已覆盖 providers 的消费场景。
        requestModels()
    }

    /// mux 流聚合了全部会话事件，订阅动作退化为空操作。
    override func subscribe(sessionId: String?) {}

    // MARK: 发送与应答

    override func sendMessage(
        text: String,
        images: [GatewayOutgoingImage] = [],
        sessionId: String?,
        workspaceId: String? = nil
    ) {
        guard state.isConnected else {
            updateState(.failed("直连尚未就绪，请稍候重试"))
            return
        }
        Task {
            await self.sendPrompt(text: text, images: images, sessionId: sessionId, workspaceId: workspaceId)
        }
    }

    override func answerQuestion(rpcId: String, sessionId: String, answers: [GatewayQuestionAnswer]) {
        Task {
            await self.respondToInteraction(rpcId: rpcId, sessionId: sessionId, answers: answers)
        }
    }

    override func cancelQuestion(rpcId: String, sessionId: String) {
        Task {
            if pendingApprovals[rpcId] != nil {
                // 原生协议里审批没有"跳过"出口（respond 对非 ok 一律 bad-response），
                // 明确告知用户需要做出选择，而不是让提交静默失败。
                emit(GatewayFrame(kind: "question-response", sessionId: sessionId, rpcId: rpcId, action: "cancel", accepted: false, reason: "执行审批无法跳过，请选择允许或拒绝。"))
                return
            }
            let receipt = try? await respond(
                rpcId: rpcId,
                result: .object([
                    "ok": .bool(false),
                    "error": .object([
                        "code": .string("cancelled"),
                        "message": .string("用户跳过了这组问题"),
                        "details": .object([:])
                    ])
                ])
            )
            emit(GatewayFrame(kind: "question-response", sessionId: sessionId, rpcId: rpcId, action: "cancel", accepted: receipt?["accepted"]?.boolValue == true))
        }
    }

    // MARK: 连接建立

    private func establishConnection(generation: Int) async {
        guard wantsConnection, generation == connectGeneration, let base = httpBaseURL else { return }
        updateState(.connecting)
        do {
            try await ensureAuthenticated(base: base, generation: generation)
            guard generation == connectGeneration else { return }
            openStreams(base: base, generation: generation)
            try await waitForStreamsOpen(timeout: 15, generation: generation)
            guard generation == connectGeneration else { return }
            let description = try await call("host.describe", .object([:]))
            guard generation == connectGeneration else { return }
            reconnectAttempt = 0
            isRecoveringFromBackground = false
            updateState(.connected)
            startKeepalive(generation: generation)
            onFrame?(GatewayFrame(
                kind: "hello",
                protocol: 3,
                capabilities: ["images"],
                authenticated: true,
                version: description["version"]?.stringValue
            ))
        } catch {
            // 过期代际的失败必须静默丢弃：新一代连接可能已经就绪，
            // 否则旧套接字的 ENOTCONN 会把健康的新流拆掉，形成级联重连。
            guard generation == connectGeneration, wantsConnection else { return }
            handleEstablishmentFailure(error)
        }
    }

    private func ensureAuthenticated(base: URL, generation: Int) async throws {
        if let stored = DshDirectCredentialStore.load(baseURL: base).token {
            cookieHeader = stored
        }
        // 先探测是否真的存在密码门；无门则清掉本地凭据直接放行。
        let status = try await DshDirectAuthService.probeGate(baseURL: base, session: httpSession)
        guard case .present(let csrf) = status else {
            cookieHeader = nil
            return
        }
        guard cookieHeader != nil else {
            try await authenticate(base: base, csrf: csrf)
            return
        }
        // 已有 token：有效性由首个 RPC/WS 升级验证，401 时走 reauthenticate。
    }

    private func authenticate(base: URL, csrf: String? = nil) async throws {
        guard !isAuthenticating else { return }
        let credentials = DshDirectCredentialStore.load(baseURL: base)
        let password = credentials.password ?? transientPassword
        guard let username = credentials.username, !username.isEmpty,
              let password, !password.isEmpty else {
            throw DshDirectAuthService.AuthError.notConfigured
        }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let effectiveCsrf: String
        if let csrf {
            effectiveCsrf = csrf
        } else {
            guard case .present(let fresh) = try await DshDirectAuthService.probeGate(baseURL: base, session: httpSession) else {
                cookieHeader = nil
                return
            }
            effectiveCsrf = fresh
        }
        let token = try await DshDirectAuthService.login(
            baseURL: base,
            username: username,
            password: password,
            csrf: effectiveCsrf,
            session: httpSession
        )
        cookieHeader = token
        var updated = credentials
        updated.token = token
        DshDirectCredentialStore.saveQuietly(updated, baseURL: base)
    }

    /// RPC 或 WS 升级遇到 401 时：丢弃旧 token，用存储的账密重登一次后重试。
    private func reauthenticate() async -> Bool {
        guard let base = httpBaseURL else { return false }
        var credentials = DshDirectCredentialStore.load(baseURL: base)
        credentials.token = nil
        DshDirectCredentialStore.saveQuietly(credentials, baseURL: base)
        cookieHeader = nil
        do {
            try await authenticate(base: base)
            return cookieHeader != nil
        } catch {
            terminate(authErrorDescription(error))
            return false
        }
    }

    private func openStreams(base: URL, generation: Int) {
        teardownStreams()
        for (path, isMux) in [("/api/events.mux", true), ("/api/events.host", false)] {
            guard let url = DshDirectAuthService.websocketURL(baseURL: base, path: path) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            if let cookieHeader {
                request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }
            let socket = socketSession.webSocketTask(with: request)
            socket.maximumMessageSize = Self.maximumIncomingMessageSize
            if isMux {
                muxSocket = socket
                // ⚠️ 不要用 Task { await self?.receiveLoop(...) }——那样会把整个
                // 接收循环钉在主 actor 上，流式对话时每秒数百个事件会把主线程塞满，
                // 导致 UI 4-5 秒才刷新一批。
                let weakSelf = self as DshDirectClient?
                muxReceiveTask = Task.detached { [weakSelf] in await weakSelf?.receiveLoop(socket, isMux: true, generation: generation) }
            } else {
                hostSocket = socket
                let weakSelf = self as DshDirectClient?
                hostReceiveTask = Task.detached { [weakSelf] in await weakSelf?.receiveLoop(socket, isMux: false, generation: generation) }
            }
            socket.resume()
        }
    }

    /// 下行流空闲时没有任何数据帧（host 流尤其如此），开流检测依赖 ping→pong：
    /// sendPing 在收到对端 PONG 后才回调，即升级握手成功的可靠信号。
    private func waitForStreamsOpen(timeout: TimeInterval, generation: Int) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(muxOpened && hostOpened) {
            guard wantsConnection, generation == connectGeneration else { throw CancellationError() }
            if Date() > deadline {
                throw DshDirectAuthService.AuthError.gateUnreachable("事件流握手超时，请检查网络与部署状态")
            }
            if !muxOpened, let socket = muxSocket, (try? await ping(socket)) != nil {
                muxOpened = true
            }
            if !hostOpened, let socket = hostSocket, (try? await ping(socket)) != nil {
                hostOpened = true
            }
            if !(muxOpened && hostOpened) {
                try await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func ping(_ socket: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            socket.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// 事件接收循环。不继承主 actor——在 Task.detached 里跑，确保
    /// JSON 解码与事件归一化的开销不阻塞主线程（流式对话每秒数百 chunk）。
    private nonisolated func receiveLoop(_ socket: URLSessionWebSocketTask, isMux: Bool, generation: Int) async {
        do {
            while !Task.isCancelled {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case .string(let text): data = Data(text.utf8)
                case .data(let payload): data = payload
                @unknown default: continue
                }
                // JSON 解码在后台做，减少主线程压力。
                guard let envelope = try? JSONDecoder().decode(JSONValue.self, from: data),
                      envelope["type"]?.stringValue == "server-request",
                      let rpcId = envelope["rpcId"]?.stringValue,
                      let payload = envelope["payload"] else { continue }
                let method = envelope["method"]?.stringValue ?? payload["type"]?.stringValue ?? ""
                // 非 session/event 帧量极少，session/event 帧才是瓶颈。
                // 把归一化（RawSessionEvent.normalized）也留在后台线程做。
                if method == "session/event" {
                    guard let sessionId = payload["sessionId"]?.stringValue,
                          let event = payload["event"] else { continue }
                    let raw = RawSessionEvent(
                        type: event["type"]?.stringValue ?? "unknown",
                        seq: event["seq"]?.doubleValue.map(Int.init) ?? 0,
                        time: event["time"]?.doubleValue ?? 0,
                        data: event["data"] ?? .null
                    )
                    let normalized = raw.normalized(sessionId: sessionId)
                    await emitOnMain(GatewayFrame(
                        kind: "event", sessionId: sessionId,
                        seq: raw.seq, time: raw.time,
                        event: normalized.event
                    ))
                } else {
                    await processNonEventEnvelope(method: method, rpcId: rpcId, payload: payload)
                }
            }
        } catch is CancellationError {
            return
        } catch {
            await handleStreamFailureOnMain(error, generation: generation)
        }
    }

    @MainActor
    private func emitOnMain(_ frame: GatewayFrame) { emit(frame) }

    @MainActor
    private func processNonEventEnvelope(method: String, rpcId: String, payload: JSONValue) {
        ingestEnvelopePayload(method: method, rpcId: rpcId, payload: payload)
    }

    @MainActor
    private func handleStreamFailureOnMain(_ error: Error, generation: Int) {
        handleStreamFailure(error, generation: generation)
    }

    /// 解析 server-request 信封并派发到对应翻译器。
    /// 仅运行在 @MainActor 上——JSON 解码与 session/event 归一化已在 receiveLoop（后台）完成。
    /// 此函数仅处理非 session/event 的控制帧（提问、审批、host 流等少量帧）。
    private func ingestEnvelopePayload(method: String, rpcId: String, payload: JSONValue) {
        switch method {
        case "question/requested":
            if let frame = DirectFrameTranslator.questionRequestedFrame(rpcId: rpcId, payload: payload) {
                emit(frame)
            }
        case "question/resolved":
            emit(GatewayFrame(
                kind: "question-resolved",
                sessionId: payload["sessionId"]?.stringValue,
                rpcId: payload["questionRpcId"]?.stringValue ?? rpcId,
                outcome: payload["outcome"]?.stringValue
            ))
        case "approval/requested":
            if let frame = DirectFrameTranslator.approvalQuestionFrame(rpcId: rpcId, payload: payload),
               let sessionId = payload["sessionId"]?.stringValue,
               let approvalId = payload["approvalId"]?.stringValue {
                pendingApprovals[rpcId] = (sessionId, approvalId)
                approvalRpcIds[approvalId] = rpcId
                emit(frame)
            }
        case "approval/resolved":
            guard let approvalId = payload["approvalId"]?.stringValue,
                  let rpcId = approvalRpcIds.removeValue(forKey: approvalId) else { return }
            pendingApprovals.removeValue(forKey: rpcId)
            emit(GatewayFrame(kind: "question-resolved", sessionId: payload["sessionId"]?.stringValue, rpcId: rpcId, outcome: "answered"))
        case "host/session-added", "host/session-removed", "host/workspace-changed",
             "host/workspace-removed", "host/archived-sessions-changed":
            // 远端结构变化后重新拉基线，保持多端一致。
            requestWorkspaces()
            requestSessions()
        case "stream/error":
            let error = payload["error"]
            emit(DirectFrameTranslator.errorFrame(
                code: error?["code"]?.stringValue ?? "internal",
                message: error?["message"]?.stringValue ?? "事件流报告未知错误。",
                requestType: nil
            ))
        default:
            break
        }
    }

    // MARK: RPC

    private func call(_ method: String, _ payload: JSONValue, allowReauth: Bool = true) async throws -> JSONValue {
        guard let base = httpBaseURL else { throw DshDirectAuthService.AuthError.notConfigured }
        guard let url = URL(string: "/api/\(method)", relativeTo: base)?.absoluteURL else {
            throw DshDirectAuthService.AuthError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = DshDirectProtocol.rpcTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let cookieHeader {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        let envelope: [String: JSONValue] = [
            "type": .string("client-request"),
            "rpcId": .string(UUID().uuidString.lowercased()),
            "method": .string(method),
            "payload": payload
        ]
        request.httpBody = try JSONEncoder().encode(envelope)
        let (data, response) = try await httpSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DshDirectAuthService.AuthError.gateUnreachable("非 HTTP 响应")
        }
        if http.statusCode == 401, allowReauth {
            if await reauthenticate() {
                return try await call(method, payload, allowReauth: false)
            }
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DshDirectAuthService.AuthError.rejected(status: http.statusCode, message: "请求 \(method) 失败（HTTP \(http.statusCode)）。")
        }
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        guard decoded["type"]?.stringValue == "server-response",
              let result = decoded["result"] else {
            throw DshDirectAuthService.AuthError.gateUnreachable("\(method) 响应信封不符合协议")
        }
        if result["ok"]?.boolValue == true {
            return result["value"] ?? .null
        }
        let error = result["error"]
        throw RPCBusinessError(
            code: error?["code"]?.stringValue ?? "internal",
            message: error?["message"]?.stringValue ?? "\(method) 调用失败"
        )
    }

    private func respond(rpcId: String, result: JSONValue) async throws -> JSONValue {
        guard let base = httpBaseURL,
              let url = URL(string: "/api/respond", relativeTo: base)?.absoluteURL else {
            throw DshDirectAuthService.AuthError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = DshDirectProtocol.rpcTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let cookieHeader {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        let envelope: [String: JSONValue] = [
            "type": .string("client-response"),
            "rpcId": .string(rpcId),
            "result": result
        ]
        request.httpBody = try JSONEncoder().encode(envelope)
        let (data, _) = try await httpSession.data(for: request)
        return (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .object([:])
    }

    private func sendPrompt(text: String, images: [GatewayOutgoingImage], sessionId: String?, workspaceId: String?) async {
        do {
            var targetSessionId = sessionId
            if targetSessionId == nil || targetSessionId?.isEmpty == true {
                var createPayload: [String: JSONValue] = [:]
                if let workspaceId, !workspaceId.isEmpty { createPayload["workspaceId"] = .string(workspaceId) }
                let created = try await call("session.create", .object(createPayload))
                guard let newId = created["sessionId"]?.stringValue else {
                    throw RPCBusinessError(code: "internal", message: "会话创建响应缺少 sessionId。")
                }
                targetSessionId = newId
            }
            var content: [JSONValue] = [.object(["type": .string("text"), "text": .string(text)])]
            for image in images {
                content.append(.object([
                    "type": .string("image"),
                    "mediaType": .string(image.mediaType),
                    "data": .string(image.data.base64EncodedString()),
                    "name": image.name.map { JSONValue.string($0) } ?? .null
                ]))
            }
            _ = try await call("session.prompt", .object([
                "sessionId": .string(targetSessionId ?? ""),
                "mode": .string("queue"),
                "content": .array(content),
                "clientTimeZone": .string(TimeZone.current.identifier)
            ]))
            if let targetSessionId {
                emit(DirectFrameTranslator.sentFrame(sessionId: targetSessionId))
            }
        } catch let error as RPCBusinessError {
            emit(DirectFrameTranslator.errorFrame(code: error.code, message: error.message, requestType: "message", sessionId: sessionId))
        } catch {
            emit(DirectFrameTranslator.errorFrame(code: "transport", message: error.localizedDescription, requestType: "message", sessionId: sessionId))
        }
    }

    private func respondToInteraction(rpcId: String, sessionId: String, answers: [GatewayQuestionAnswer]) async {
        if let approval = pendingApprovals[rpcId] {
            let approved = answers.contains { $0.selected.contains("允许一次") }
            let outcome = approved ? "allowed-once" : "rejected"
            do {
                let receipt = try await respond(rpcId: rpcId, result: .object([
                    "ok": .bool(true),
                    "value": .object([
                        "sessionId": .string(approval.sessionId),
                        "approvalId": .string(approval.approvalId),
                        "outcome": .string(outcome)
                    ])
                ]))
                emit(GatewayFrame(kind: "question-response", sessionId: approval.sessionId, rpcId: rpcId, action: "answer", accepted: receipt["accepted"]?.boolValue == true))
            } catch {
                emit(GatewayFrame(kind: "question-response", sessionId: approval.sessionId, rpcId: rpcId, action: "answer", accepted: false, reason: error.localizedDescription))
            }
            return
        }
        let encodedAnswers: [JSONValue] = answers.map { answer in
            var item: [String: JSONValue] = [
                "id": .string(answer.id),
                "selected": .array(answer.selected.map(JSONValue.string))
            ]
            if let custom = answer.custom { item["custom"] = .string(custom) }
            return .object(item)
        }
        do {
            let receipt = try await respond(rpcId: rpcId, result: .object([
                "ok": .bool(true),
                "value": .object([
                    "sessionId": .string(sessionId),
                    "answer": .object(["answers": .array(encodedAnswers)])
                ])
            ]))
            let accepted = receipt["accepted"]?.boolValue == true
            emit(GatewayFrame(
                kind: "question-response",
                sessionId: sessionId,
                rpcId: rpcId,
                action: "answer",
                accepted: accepted,
                reason: accepted ? nil : (receipt["reason"]?.stringValue ?? "bad-response")
            ))
        } catch {
            emit(GatewayFrame(kind: "question-response", sessionId: sessionId, rpcId: rpcId, action: "answer", accepted: false, reason: error.localizedDescription))
        }
    }

    // MARK: 状态与生命周期辅助

    private func runRPC(
        method: String,
        payload: JSONValue,
        requestType: String?,
        translate: @escaping (JSONValue) -> GatewayFrame?
    ) {
        guard state.isConnected else {
            updateState(.failed("直连尚未就绪，请稍候重试"))
            return
        }
        Task {
            do {
                let value = try await self.call(method, payload)
                if let frame = translate(value) { self.emit(frame) }
            } catch let error as RPCBusinessError {
                self.emit(DirectFrameTranslator.errorFrame(code: error.code, message: error.message, requestType: requestType))
            } catch {
                self.emit(DirectFrameTranslator.errorFrame(code: "transport", message: error.localizedDescription, requestType: requestType))
            }
        }
    }

    private func emit(_ frame: GatewayFrame) {
        onFrame?(frame)
    }

    private func handleStreamFailure(_ error: Error, generation: Int) {
        guard wantsConnection, generation == connectGeneration else { return }
        if isCancellation(error) { return }
        if state.isConnected { return }  // 已有健康连接，旧流失败不触发重连
        if isUnauthorized(error) {
            Task {
                if await self.reauthenticate() {
                    self.scheduleReconnect(reason: "会话凭据已刷新，正在重新连接")
                }
                // reauthenticate 失败时已经终止并给出指引，不再进入重连循环。
            }
            return
        }
        scheduleReconnect(reason: "事件流中断：\(error.localizedDescription)")
    }

    private func handleEstablishmentFailure(_ error: Error) {
        // 如果已有连接在运行（并发 establishConnection 的先到者已成功），
        // 本失败方静默退出，不触发重连拆掉好连接。
        if state.isConnected { return }
        if let authError = error as? DshDirectAuthService.AuthError {
            switch authError {
            case .invalidURL:
                terminate(authError.localizedDescription)
            case .notConfigured:
                terminate(authError.localizedDescription)
            case .rejected(let status, _) where status == 401:
                // 凭据过期：丢弃旧 token 并重试重登，不终止。
                var credentials = DshDirectCredentialStore.load(baseURL: httpBaseURL!)
                credentials.token = nil
                DshDirectCredentialStore.saveQuietly(credentials, baseURL: httpBaseURL!)
                cookieHeader = nil
                scheduleReconnect(reason: "凭据已过期，正在用账号密码重新登录")
            case .rejected:
                terminate(authError.localizedDescription)
            case .gateUnreachable:
                // 临时网络故障（TCP 超时 / DNS 解析失败等）：指数退避重试，不终止。
                scheduleReconnect(reason: authError.localizedDescription)
            }
            return
        }
        if error is RPCBusinessError {
            scheduleReconnect(reason: error.localizedDescription)
            return
        }
        if isCancellation(error) { return }
        scheduleReconnect(reason: error.localizedDescription)
    }

    /// 预测成功 → 停止当前重连定时器、继续接收事件。
    private func scheduleReconnect(reason: String) {
        teardownStreams()
        updateState(.failed(reason))
        reportFailureOnce("直连连接中断：\(reason)")
        reconnectAttempt += 1
        reconnectTask?.cancel()
        let delay = min(
            DshDirectProtocol.reconnectMaxDelay,
            DshDirectProtocol.reconnectBaseDelay * pow(2, Double(min(reconnectAttempt, 6)))
        )
        let jitter = Double.random(in: 0...(delay / 2))
        let generation = connectGeneration
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay + jitter))
            guard let self, self.wantsConnection, generation == self.connectGeneration else { return }
            await self.establishConnection(generation: generation)
        }
    }

    /// 终止连接（不可恢复场景：地址无效、未配置账密、服务端拒绝）：停止重连并把失败原因交给 UI。
    private func terminate(_ detail: String) {
        wantsConnection = false
        reconnectTask?.cancel()
        reconnectTask = nil
        teardownStreams()
        updateState(.failed(detail))
        reportFailureOnce(detail)
    }

    /// 启动双流保活定时器（每 30 秒 ping 一次），防止 iOS 回收空闲 TCP 连接。
    private func startKeepalive(generation: Int) {
        keepaliveTask?.cancel()
        keepaliveTask = Task { [weak self] in
            while !Task.isCancelled, let self {
                try? await Task.sleep(for: .seconds(30))
                guard self.connectGeneration == generation, self.state.isConnected else { return }
                if let socket = self.muxSocket { try? await self.ping(socket) }
                if let socket = self.hostSocket { try? await self.ping(socket) }
            }
        }
    }

    private func reportFailureOnce(_ detail: String) {
        guard lastReportedFailure != detail else { return }
        lastReportedFailure = detail
        if presentsFailure() { onConnectionFailure?(detail) }
    }

    private func presentsFailure() -> Bool {
        !(isApplicationInBackground || isRecoveringFromBackground)
    }

    private func isCancellation(_ error: Error) -> Bool {
        (error as NSError).code == NSURLErrorCancelled
    }

    private func isUnauthorized(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorBadServerResponse {
            return httpResponseStatus(of: nsError) == 401
        }
        return httpResponseStatus(of: nsError) == 401
    }

    private func httpResponseStatus(of nsError: NSError) -> Int? {
        for key in ["NSErrorFailingURLResponseKey", "NSURLErrorFailingURLResponseErrorKey"] {
            if let response = nsError.userInfo[key] as? HTTPURLResponse { return response.statusCode }
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return httpResponseStatus(of: underlying)
        }
        return nil
    }

    private func authErrorDescription(_ error: Error) -> String {
        (error as? DshDirectAuthService.AuthError)?.localizedDescription ?? error.localizedDescription
    }

    private func teardownStreams() {
        keepaliveTask?.cancel()
        keepaliveTask = nil
        muxReceiveTask?.cancel()
        hostReceiveTask?.cancel()
        muxReceiveTask = nil
        hostReceiveTask = nil
        muxSocket?.cancel(with: .goingAway, reason: nil)
        hostSocket?.cancel(with: .normalClosure, reason: nil)
        muxSocket = nil
        hostSocket = nil
        muxOpened = false
        hostOpened = false
        pendingApprovals.removeAll()
        approvalRpcIds.removeAll()
    }

    private func suspendTransportForBackground() {
        wantsConnection = true
        reconnectTask?.cancel()
        reconnectTask = nil
        teardownStreams()
        updateState(.disconnected)
    }

    private func makeHTTPSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = DshDirectProtocol.rpcTimeout
        return URLSession(configuration: configuration, delegate: redirectBlocker, delegateQueue: nil)
    }

    private struct RPCBusinessError: LocalizedError {
        let code: String
        let message: String
        var errorDescription: String? { message }
    }
}
