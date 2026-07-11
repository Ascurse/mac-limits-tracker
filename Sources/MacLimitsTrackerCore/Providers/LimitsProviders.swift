import Foundation
import Security

/// Источник данных о лимитах Claude Code.
public struct ClaudeLimitsProvider {
    let claudeBinary: String
    let statsCacheURL: URL
    let processRunner: (String, [String]) async throws -> Data
    let fileReader: (URL) async throws -> Data
    /// Читает JSON-blob из macOS Keychain по службе `Claude Code-credentials`.
    let keychainReader: () async throws -> Data
    /// Выполняет GET с `Authorization: Bearer <token>`; возвращает тело ответа.
    let httpGet: (URL, String) async throws -> Data

    static let usageURL = URL(string: "https://claude.ai/api/oauth/usage")!

    public init(
        claudeBinary: String? = nil,
        statsCacheURL: URL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/stats-cache.json"),
        processRunner: @escaping (String, [String]) async throws -> Data = ProcessRunner.run,
        fileReader: @escaping (URL) async throws -> Data = { try Data(contentsOf: $0) },
        keychainReader: @escaping () async throws -> Data = KeychainStore.readClaudeCodeCredentials,
        httpGet: @escaping (URL, String) async throws -> Data = Http.httpGet
    ) {
        self.claudeBinary = claudeBinary ?? ProcessRunner.defaultClaudeBinary()
        self.statsCacheURL = statsCacheURL
        self.processRunner = processRunner
        self.fileReader = fileReader
        self.keychainReader = keychainReader
        self.httpGet = httpGet
    }

    public func fetch() async -> ClaudeStatus {
        let now = Date()
        var auth: ClaudeAuthStatus?
        var stats: StatsCache?
        var errors: [String] = []

        do {
            let data = try await processRunner(claudeBinary, ["auth", "status"])
            auth = ClaudeAuthParser.parse(data)
        } catch {
            errors.append("claude auth status failed: \(friendly(error))")
        }

        do {
            let data = try await fileReader(statsCacheURL)
            stats = try JSONDecoder().decode(StatsCache.self, from: data)
        } catch {
            errors.append("stats cache read failed: \(friendly(error))")
        }

        let (usage, usageError) = await fetchUsage()

        let errorMessage = errors.isEmpty ? nil : errors.joined(separator: "; ")

        let today = stats.flatMap { StatsCacheUsage.todayUsage(from: $0) }
        let latestDay = stats.flatMap { StatsCacheUsage.latestUsage(from: $0) }
        return ClaudeStatus(
            loggedIn: auth?.loggedIn ?? false,
            authMethod: auth?.authMethod,
            apiProvider: auth?.apiProvider,
            email: auth?.email,
            subscriptionType: auth?.subscriptionType,
            orgName: auth?.orgName,
            today: today,
            latestDay: latestDay,
            lastComputedDate: stats?.lastComputedDate,
            totalSessions: stats?.totalSessions,
            totalMessages: stats?.totalMessages,
            usage: usage,
            usageError: usageError,
            fetchedAt: now,
            providerError: errorMessage
        )
    }

    /// /api/oauth/usage независим от `claude auth status`: токен живёт в keychain
    /// и endpoint отвечает даже когда бинарь `claude` недоступен или кеш статистики битый.
    private func fetchUsage() async -> (ClaudeUsage?, String?) {
        do {
            let keychainData = try await keychainReader()
            guard let creds = ClaudeKeychainCredentialsParser.accessToken(keychainData) else {
                return (nil, "claude.ai oauth token not found")
            }
            if let exp = creds.expiresAt, exp <= Date() {
                return (nil, "claude.ai login expired — open Claude Code to refresh")
            }
            let body = try await httpGet(Self.usageURL, creds.token)
            if let usage = ClaudeUsageParser.parse(body) { return (usage, nil) }
            return (nil, "claude.ai usage response unreadable")
        } catch {
            return (nil, "claude.ai usage fetch failed: \(friendly(error))")
        }
    }
}

/// Источник данных о лимитах Codex.
public struct CodexLimitsProvider {
    let authFileURL: URL
    let fileReader: (URL) async throws -> Data
    /// Выполняет init + `account/rateLimits/read` через `codex app-server`, возвращает
    /// body JSON-RPC ответа (envelope) для `id=2` или кидает ошибку.
    let appServerReader: () async throws -> Data

    public init(
        authFileURL: URL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json"),
        fileReader: @escaping (URL) async throws -> Data = { try Data(contentsOf: $0) },
        appServerReader: (() async throws -> Data)? = nil
    ) {
        self.authFileURL = authFileURL
        self.fileReader = fileReader
        if let reader = appServerReader {
            self.appServerReader = reader
        } else {
            let bin = ProcessRunner.defaultCodexBinary()
            self.appServerReader = { try await CodexAppServerRpc(codexBinary: bin).fetchRateLimits() }
        }
    }

    public func fetch() async -> CodexStatus {
        let now = Date()
        do {
            let data = try await fileReader(authFileURL)
            let file = try JSONDecoder().decode(CodexAuthFileJSON.self, from: data)
            let token = file.tokens?.idToken ?? file.tokens?.accessToken
            let loggedIn = (token != nil) && (file.authMode != nil)

            let (usage, usageError) = await fetchUsage()
            let claims = token.map(CodexClaimsParser.parse)
            if token != nil {
                return CodexStatus(
                    loggedIn: loggedIn,
                    authMode: file.authMode,
                    email: claims?.email,
                    planType: claims?.planType,
                    subscriptionActiveUntil: claims?.subscriptionActiveUntil,
                    daysUntilRenewal: claims.flatMap { CodexClaimsParser.daysUntilRenewal(from: $0) },
                    accountOwner: claims?.accountOwner,
                    usage: usage,
                    usageError: usageError,
                    fetchedAt: now,
                    providerError: nil
                )
            }
            return CodexStatus(
                loggedIn: loggedIn,
                authMode: file.authMode,
                email: nil, planType: nil,
                subscriptionActiveUntil: nil, daysUntilRenewal: nil,
                accountOwner: nil,
                usage: usage,
                usageError: usageError,
                fetchedAt: now,
                providerError: "auth.json has no ChatGPT tokens"
            )
        } catch {
            return CodexStatus(
                loggedIn: false, authMode: nil,
                email: nil, planType: nil,
                subscriptionActiveUntil: nil, daysUntilRenewal: nil,
                accountOwner: nil,
                usage: nil, usageError: nil,
                fetchedAt: now,
                providerError: "auth.json read failed: \(friendly(error))"
            )
        }
    }

    /// `codex app-server` JSON-RPC. Независимо от JWT-секции: токен читается из
    /// `~/.codex/auth.json` самим codex, от нас никакого пайплайна токенов. Ошибка — нефатально.
    private func fetchUsage() async -> (CodexUsage?, String?) {
        do {
            let envelope = try await appServerReader()
            if let snapshot = CodexUsageParser.parse(envelope) {
                return (CodexUsage(snapshot: snapshot, error: nil), nil)
            }
            return (CodexUsage(snapshot: nil, error: "codex usage response unreadable"),
                    "codex usage response unreadable")
        } catch {
            let msg = "codex app-server: \(friendly(error))"
            return (CodexUsage(snapshot: nil, error: msg), msg)
        }
    }
}

public enum ProcessRunner {
    public static func run(_ binary: String, _ args: [String]) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        // stderr не читается — направляем в /dev/null, чтобы заполненный буфер трубы не заблокировал дочерний процесс.
        process.standardError = FileHandle.nullDevice
        try process.run()
        let outData = try pipe.fileHandleForReading.readToEnd()
        process.waitUntilExit()
        return outData ?? Data()
    }

    /// Ищет бинарь `codex` среди типичных мест установки. Зеркало `defaultClaudeBinary`.
    public static func defaultCodexBinary(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String {
        if let p = environment["CODEX_BIN"], !p.isEmpty { return p }
        let home = environment["HOME"]
            ?? environment["USER"].map { "/Users/\($0)" }
            ?? NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        return candidates.first(where: fileExists) ?? candidates.last!
    }

    /// Ищет бинарь `claude` среди типичных мест установки. Первый существующий кандидат побеждает,
    /// иначе возвращается последний как разумный дефолт (даже если файла там нет).
    public static func defaultClaudeBinary(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String {
        if let p = environment["CLAUDE_BIN"], !p.isEmpty { return p }
        let home = environment["HOME"]
            ?? environment["USER"].map { "/Users/\($0)" }
            ?? NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude"
        ]
        return candidates.first(where: fileExists) ?? candidates.last!
    }
}

/// JSON-RPC over stdio клиент к `codex app-server`.
/// Init → `account/rateLimits/read`. Возвращает body ответа для `id=2` (одну newline-строку).
/// Subprocess spawned-on-demand на каждый refresh и гасится по завершении операции.
public final class CodexAppServerRpc {
    let codexBinary: String

    public init(codexBinary: String) {
        self.codexBinary = codexBinary
    }

    public enum Error: Swift.Error {
        case noResponseWithId(Int)
        case spawnFailed(String)
    }

    public func fetchRateLimits() async throws -> Data {
        let initReq = Self.makeEnvelope(method: "initialize", params: [
            "protocolVersion": "2025-11-25",
            "clientInfo": ["name": "mac-limits-tracker", "version": "0.1"],
            "capabilities": [:]
        ], id: 1)
        let rateReq = Self.makeEnvelope(method: "account/rateLimits/read", params: [:], id: 2)
        let stdinBytes = (initReq + "\n" + rateReq + "\n").data(using: .utf8) ?? Data()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexBinary)
        process.arguments = ["app-server"]
        let inPipe = Pipe()
        let outPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        // stderr не читается — /dev/null не блокирует буфер.
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw Error.spawnFailed(friendly(error))
        }

        return try await withCheckedThrowingContinuation { cont in
            let state = RpcCallState(inPipe: inPipe, outPipe: outPipe,
                                     process: process, continuation: cont)

            outPipe.fileHandleForReading.readabilityHandler = { fh in
                state.handleReadable(fh.availableData)
            }

            inPipe.fileHandleForWriting.write(stdinBytes)

            // Hard timeout 25s — backend ChatGPT/cloudflare может тормозить; не блокируем UI навсегда.
            DispatchQueue.global().asyncAfter(deadline: .now() + 25) {
                state.fail(.noResponseWithId(2))
            }
        }
    }

    /// Потокобезопасное состояние одного RPC-вызова. `readabilityHandler` и таймаут приходят
    /// с разных очередей, поэтому mutable-поля (`buffer`, `resolved`) под общим NSLock, а
    /// continuation резолвится ровно один раз.
    private final class RpcCallState: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()
        private var resolved = false
        private let inPipe: Pipe
        private let outPipe: Pipe
        private let process: Process
        private let continuation: CheckedContinuation<Data, Swift.Error>

        init(inPipe: Pipe, outPipe: Pipe, process: Process,
             continuation: CheckedContinuation<Data, Swift.Error>) {
            self.inPipe = inPipe
            self.outPipe = outPipe
            self.process = process
            self.continuation = continuation
        }

        func handleReadable(_ chunk: Data) {
            lock.lock()
            if resolved { lock.unlock(); return }
            if chunk.isEmpty {
                lock.unlock()
                // stdout EOF — server закрылся раньше id=2.
                resolve(.failure(.noResponseWithId(2)))
                return
            }
            buffer.append(chunk)
            var outcome: Result<Data, Error>?
            while let newlineRange = buffer.range(of: Data([0x0A])) {
                let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
                buffer.removeSubrange(0..<newlineRange.upperBound)
                guard !lineData.isEmpty,
                      let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      obj["id"] as? Int == 2
                else { continue }
                if let err = obj["error"] as? [String: Any],
                   let message = (err["message"] as? String) ?? (err["data"] as? String) {
                    outcome = .failure(.spawnFailed(message))
                } else {
                    outcome = .success(lineData)
                }
                break
            }
            lock.unlock()
            if let outcome { resolve(outcome) }
        }

        func fail(_ error: Error) {
            resolve(.failure(error))
        }

        private func resolve(_ result: Result<Data, Error>) {
            lock.lock()
            if resolved { lock.unlock(); return }
            resolved = true
            lock.unlock()

            outPipe.fileHandleForReading.readabilityHandler = nil
            try? inPipe.fileHandleForWriting.close()
            // Закрытие stdin обычно завершает app-server само; terminate() — страховка,
            // чтобы на каждом обновлении не копились подвисшие процессы.
            if process.isRunning { process.terminate() }
            continuation.resume(with: result.mapError { $0 as Swift.Error })
        }
    }

    private static func makeEnvelope(method: String, params: [String: Any], id: Int) -> String {
        var envelope: [String: Any] = ["jsonrpc": "2.0", "method": method, "id": id]
        envelope["params"] = params
        guard let data = try? JSONSerialization.data(withJSONObject: envelope),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }
}

/// Чтение учётных данных Claude Code из macOS Keychain (служба `Claude Code-credentials`).
public enum KeychainStore {
    /// Имя службы, под которой Claude Code хранит `claudeAiOauth` (access/refresh tokens).
    /// Суффиксированные записи `Claude Code-credentials-{hash}` — это MCP-плагиновые секреты,
    /// нас не интересующие: точное совпадение `kSecAttrService` отсекает их.
    public static let claudeCodeCredentialsService = "Claude Code-credentials"

    public static func readClaudeCodeCredentials() async throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: claudeCodeCredentialsService,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw NSError(
                domain: "KeychainStore",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "keychain read failed (status \(status))"]
            )
        }
        return data
    }
}

/// Минимальный сетевой клиент: GET с Bearer-токеном.
public enum Http {
    public static func httpGet(_ url: URL, _ bearerToken: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("claude-code/2.1.207", forHTTPHeaderField: "User-Agent")

        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(
                domain: "Network",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]
            )
        }
        return data
    }
}

func friendly(_ error: Error) -> String {
    let ns = error as NSError
    if ns.domain == NSCocoaErrorDomain, ns.code == 260 { return "file not found" }
    if ns.domain == NSPOSIXErrorDomain { return ns.localizedDescription }
    return error.localizedDescription
}