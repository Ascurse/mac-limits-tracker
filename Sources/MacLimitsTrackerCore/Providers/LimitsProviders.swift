import Foundation
import Security
import os

/// Источник данных о лимитах Claude Code. DI-замыкания помечены `@Sendable`, поэтому
/// структура — честный `Sendable` без `@unchecked`. Тестовые подстановки, которые пишут в
/// захваченные `var`, обязаны сами быть `@Sendable`-безопасны (напр. `nonisolated(unsafe)`
/// поле-накопитель под их собственный лок) — компилятор теперь это проверяет на границе
/// замыкания, а не полагается на честное слово.
public struct ClaudeLimitsProvider: Sendable {
    private static let logger = Logger(
        subsystem: "dev.ascurse.MacLimitsTracker",
        category: "Claude"
    )

    let claudeBinary: String
    let statsCacheURL: URL
    let processRunner: @Sendable (String, [String]) async throws -> Data
    let fileReader: @Sendable (URL) async throws -> Data
    /// Читает JSON-blob из macOS Keychain по службе `Claude Code-credentials`.
    let keychainReader: @Sendable () async throws -> Data
    /// Выполняет GET с `Authorization: Bearer <token>`; возвращает тело ответа.
    let httpGet: @Sendable (URL, String) async throws -> Data

    static let usageURL = URL(string: "https://claude.ai/api/oauth/usage")!

    public init(
        claudeBinary: String? = nil,
        statsCacheURL: URL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/stats-cache.json"),
        processRunner: @escaping @Sendable (String, [String]) async throws -> Data = { try await ProcessRunner.run($0, $1) },
        fileReader: @escaping @Sendable (URL) async throws -> Data = { try Data(contentsOf: $0) },
        keychainReader: @escaping @Sendable () async throws -> Data = { try await KeychainStore.readClaudeCodeCredentials() },
        httpGet: @escaping @Sendable (URL, String) async throws -> Data = { try await Http.httpGet($0, $1) }
    ) {
        self.claudeBinary = claudeBinary ?? ProcessRunner.defaultClaudeBinary()
        self.statsCacheURL = statsCacheURL
        self.processRunner = processRunner
        self.fileReader = fileReader
        self.keychainReader = keychainReader
        self.httpGet = httpGet
    }

    func fetchStatus() async -> ClaudeStatus {
        let now = Date()
        var auth: ClaudeAuthStatus?
        var stats: StatsCache?
        var errors: [String] = []

        do {
            let data = try await processRunner(claudeBinary, ["auth", "status"])
            auth = ClaudeAuthParser.parse(data)
        } catch {
            Self.logger.error("auth status failed: \(friendly(error), privacy: .public)")
            errors.append("claude auth status failed: \(friendly(error))")
        }

        do {
            let data = try await fileReader(statsCacheURL)
            stats = try JSONDecoder.shared.decode(StatsCache.self, from: data)
        } catch {
            Self.logger.error("stats cache read failed: \(friendly(error), privacy: .public)")
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
                Self.logger.error("usage fetch failed: oauth token not found")
                return (nil, "claude.ai oauth token not found")
            }
            if let exp = creds.expiresAt, exp <= Date() {
                Self.logger.error("usage fetch failed: login expired")
                return (nil, "claude.ai login expired — open Claude Code to refresh")
            }
            let body = try await httpGet(Self.usageURL, creds.token)
            if let usage = ClaudeUsageParser.parse(body) { return (usage, nil) }
            Self.logger.error("usage fetch failed: response unreadable")
            return (nil, "claude.ai usage response unreadable")
        } catch {
            Self.logger.error("usage fetch failed: \(friendly(error), privacy: .public)")
            return (nil, "claude.ai usage fetch failed: \(friendly(error))")
        }
    }
}

/// Источник данных о лимитах Codex. Честный `Sendable`: см. комментарий у `ClaudeLimitsProvider`.
public struct CodexLimitsProvider: Sendable {
    private static let logger = Logger(
        subsystem: "dev.ascurse.MacLimitsTracker",
        category: "Codex"
    )

    let authFileURL: URL
    let fileReader: @Sendable (URL) async throws -> Data
    /// Выполняет init + `account/rateLimits/read` через `codex app-server`, возвращает
    /// body JSON-RPC ответа (envelope) для `id=2` или кидает ошибку.
    let appServerReader: @Sendable () async throws -> Data

    public init(
        authFileURL: URL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json"),
        fileReader: @escaping @Sendable (URL) async throws -> Data = { try Data(contentsOf: $0) },
        appServerReader: (@Sendable () async throws -> Data)? = nil
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

    private func readAuthFile() async throws -> CodexAuthFileJSON {
        let data = try await fileReader(authFileURL)
        return try JSONDecoder.shared.decode(CodexAuthFileJSON.self, from: data)
    }

    private func buildStatus(
        file: CodexAuthFileJSON,
        token: String?,
        usage: CodexUsage?,
        usageError: String?,
        now: Date
    ) -> CodexStatus {
        let loggedIn = (token != nil) && (file.authMode != nil)
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
        Self.logger.error("auth token missing")
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
    }

    private func buildErrorStatus(error: Error, now: Date) -> CodexStatus {
        let message = friendly(error)
        Self.logger.error("auth file read failed: \(message, privacy: .public)")
        return CodexStatus(
            loggedIn: false, authMode: nil,
            email: nil, planType: nil,
            subscriptionActiveUntil: nil, daysUntilRenewal: nil,
            accountOwner: nil,
            usage: nil, usageError: nil,
            fetchedAt: now,
            providerError: "auth.json read failed: \(message)"
        )
    }

    func fetchStatus() async -> CodexStatus {
        let now = Date()
        do {
            let file = try await readAuthFile()
            let token = file.tokens?.idToken ?? file.tokens?.accessToken
            let (usage, usageError) = await fetchUsage()

            return buildStatus(
                file: file,
                token: token,
                usage: usage,
                usageError: usageError,
                now: now
            )
        } catch {
            return buildErrorStatus(error: error, now: now)
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
            Self.logger.error("usage fetch failed: response unreadable")
            return (CodexUsage(snapshot: nil, error: "codex usage response unreadable"),
                    "codex usage response unreadable")
        } catch {
            let msg = "codex app-server: \(friendly(error))"
            Self.logger.error("usage fetch failed: \(friendly(error), privacy: .public)")
            return (CodexUsage(snapshot: nil, error: msg), msg)
        }
    }
}

/// Источник данных о лимитах Kimi (Moonshot AI). Логин определяется по локальному
/// credentials-файлу (непустой `refresh_token`), usage — по live-запросу к
/// `GET /coding/v1/usages` (см. bd mac-limits-tracker-6gk.8).
public struct KimiLimitsProvider: Sendable {
    private static let logger = Logger(
        subsystem: "dev.ascurse.MacLimitsTracker",
        category: "Kimi"
    )

    /// Дефолтный путь credentials-файла; вынесен в статику, чтобы `ProviderRegistry`
    /// мог использовать то же значение по умолчанию без дублирования. Должен быть
    /// `public` — Swift требует видимость default-параметра не ниже видимости функции,
    /// даже в пределах модуля.
    public static let defaultCredentialsURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".kimi-code/credentials/kimi-code.json")

    static let usagesURL = URL(string: "https://api.kimi.com/coding/v1/usages")!

    let credentialsURL: URL
    let fileReader: @Sendable (URL) async throws -> Data
    /// Выполняет GET с `Authorization: Bearer <token>`; возвращает тело ответа.
    let httpGet: @Sendable (URL, String) async throws -> Data
    /// Обновляет access_token через auth.kimi.com и атомарно переписывает credentials-файл.
    let refresh: @Sendable (KimiCredentialsFile) async throws -> KimiCredentialsFile

    init(
        credentialsURL: URL = KimiLimitsProvider.defaultCredentialsURL,
        fileReader: @escaping @Sendable (URL) async throws -> Data = { try Data(contentsOf: $0) },
        refresh: (@Sendable (KimiCredentialsFile) async throws -> KimiCredentialsFile)? = nil,
        // UA нейтральный: `Http.httpGet` по умолчанию шлёт `claude-code/...`, что для
        // стороннего API Kimi некорректно и может триггерить фильтрацию по UA.
        httpGet: @escaping @Sendable (URL, String) async throws -> Data = {
            try await Http.httpGet($0, $1, userAgent: "mac-limits-tracker/1.0")
        }
    ) {
        self.credentialsURL = credentialsURL
        self.fileReader = fileReader
        self.refresh = refresh ?? { old in
            try await KimiTokenRefresher().refreshedCredentials(old: old, credentialsURL: credentialsURL)
        }
        self.httpGet = httpGet
    }

    func fetchStatus() async -> KimiStatus {
        let now = Date()
        do {
            let creds = try await readCredentials()
            guard !creds.refreshToken.isEmpty else {
                Self.logger.error("credentials refresh token missing")
                return KimiStatus(loggedIn: false, plan: nil, usage: nil, usageError: nil,
                                  providerError: "kimi-code refresh token missing", fetchedAt: now)
            }

            let activeCreds: KimiCredentialsFile
            do {
                activeCreds = try await refreshIfNeeded(creds, now: now)
            } catch {
                let jwtPlan = KimiJwtPayloadParser.planClaim(fromToken: creds.accessToken)
                Self.logger.error("token refresh failed: \(friendly(error), privacy: .public)")
                return mapRefreshError(error, jwtPlan: jwtPlan, now: now)
            }

            let refreshedJwtPlan = KimiJwtPayloadParser.planClaim(fromToken: activeCreds.accessToken)
            let (usage, membershipLevel, usageError) = await fetchUsage(creds: activeCreds)
            let plan = membershipLevel.flatMap(KimiMembershipLevelFormatter.prettify) ?? refreshedJwtPlan
            return KimiStatus(loggedIn: true, plan: plan, usage: usage,
                              usageError: usageError, providerError: nil, fetchedAt: now)
        } catch {
            let message = friendly(error)
            Self.logger.error("credentials read failed: \(message, privacy: .public)")
            return KimiStatus(
                loggedIn: false, plan: nil, usage: nil, usageError: nil,
                providerError: "kimi-code credentials read failed: \(message)",
                fetchedAt: now
            )
        }
    }

    private func readCredentials() async throws -> KimiCredentialsFile {
        let data = try await fileReader(credentialsURL)
        return try JSONDecoder.shared.decode(KimiCredentialsFile.self, from: data)
    }

    private func refreshIfNeeded(_ creds: KimiCredentialsFile, now: Date) async throws -> KimiCredentialsFile {
        if let expiresAt = creds.expiresAt, expiresAt <= now.timeIntervalSince1970 {
            return try await refresh(creds)
        }
        return creds
    }

    private func mapRefreshError(_ error: Error, jwtPlan: String?, now: Date) -> KimiStatus {
        if let refreshError = error as? KimiTokenRefreshError {
            switch refreshError {
            case .loginExpired:
                Self.logger.error("token refresh failed: login expired")
                return KimiStatus(loggedIn: true, plan: jwtPlan, usage: nil,
                                  usageError: "Kimi login expired — open Kimi Code to refresh",
                                  providerError: nil, fetchedAt: now)
            case .refreshFailed(let msg):
                Self.logger.error("token refresh failed: \(msg, privacy: .public)")
                return KimiStatus(loggedIn: true, plan: jwtPlan, usage: nil,
                                  usageError: "Kimi token refresh failed: \(msg)",
                                  providerError: nil, fetchedAt: now)
            }
        }
        let message = friendly(error)
        Self.logger.error("token refresh failed: \(message, privacy: .public)")
        return KimiStatus(loggedIn: true, plan: jwtPlan, usage: nil,
                          usageError: "Kimi token refresh failed: \(friendly(error))",
                          providerError: nil, fetchedAt: now)
    }

    /// Делает запрос `/coding/v1/usages` и, если сервер отвечает 401, один раз пытается
    /// обновить токен и повторить запрос. Результат маппится в понятный `usageError`.
    private func fetchUsage(
        creds: KimiCredentialsFile
    ) async -> (usage: KimiUsage?, membershipLevel: String?, error: String?) {
        let expiredMessage = "Kimi login expired — open Kimi Code to refresh"
        do {
            let body = try await httpGet(Self.usagesURL, creds.accessToken)
            guard let parsed = KimiUsagesParser.parse(body) else {
                Self.logger.error("usage fetch failed: response unreadable")
                return (nil, nil, "Kimi usage response unreadable")
            }
            return (parsed.usage, parsed.membershipLevel, nil)
        } catch {
            guard isUnauthorized(error) else {
                Self.logger.error("usage fetch failed: \(friendly(error), privacy: .public)")
                return (nil, nil, "Kimi usage fetch failed: \(friendly(error))")
            }
            do {
                let newCreds = try await refresh(creds)
                let body = try await httpGet(Self.usagesURL, newCreds.accessToken)
                guard let parsed = KimiUsagesParser.parse(body) else {
                    Self.logger.error("usage retry failed: response unreadable")
                    return (nil, nil, "Kimi usage response unreadable")
                }
                return (parsed.usage, parsed.membershipLevel, nil)
            } catch let refreshError as KimiTokenRefreshError {
                switch refreshError {
                case .loginExpired:
                    Self.logger.error("token refresh failed: login expired")
                    return (nil, nil, expiredMessage)
                case .refreshFailed(let msg):
                    Self.logger.error("token refresh failed: \(msg, privacy: .public)")
                    return (nil, nil, "Kimi token refresh failed: \(msg)")
                }
            } catch {
                Self.logger.error("token refresh failed: \(friendly(error), privacy: .public)")
                return (nil, nil, "Kimi token refresh failed: \(friendly(error))")
            }
        }
    }

    private func isUnauthorized(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == "Network" && ns.code == 401
    }
}

extension KimiLimitsProvider {
    /// Синхронная проверка перед регистрацией провайдера (без сети/подпроцессов):
    /// нет файла или пуст refresh_token — провайдер скрывается из реестра
    /// (см. критерий приёмки bd mac-limits-tracker-6gk.3).
    static func hasUsableCredentials(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let creds = try? JSONDecoder.shared.decode(KimiCredentialsFile.self, from: data)
        else { return false }
        return !creds.refreshToken.isEmpty
    }
}

public enum ProcessRunner {
    public enum RunError: Swift.Error, LocalizedError {
        case unsafeBinaryPath(String)
        case outputExceededLimit

        public var errorDescription: String? {
            switch self {
            case .unsafeBinaryPath(let path):
                return "unsafe binary path: \(path) (must be absolute)"
            case .outputExceededLimit:
                return "process output exceeded safe buffer limit"
            }
        }
    }

    public static func run(_ binary: String, _ args: [String]) async throws -> Data {
        guard binary.hasPrefix("/") else {
            throw RunError.unsafeBinaryPath(binary)
        }
        guard !binary.contains("..") else {
            throw RunError.unsafeBinaryPath(binary)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary).standardized
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        // stderr не читается — направляем в /dev/null, чтобы заполненный буфер трубы не заблокировал дочерний процесс.
        process.standardError = FileHandle.nullDevice
        try process.run()

        let handle = pipe.fileHandleForReading
        var outData = Data()
        let maxLimit = 5 * 1024 * 1024 // 5MB limit

        if #available(macOS 10.15.4, *) {
            while let chunk = try handle.read(upToCount: 8192), !chunk.isEmpty {
                if outData.count + chunk.count > maxLimit {
                    process.terminate()
                    throw RunError.outputExceededLimit
                }
                outData.append(chunk)
            }
        } else {
            let data = handle.readDataToEndOfFile()
            if data.count > maxLimit {
                process.terminate()
                throw RunError.outputExceededLimit
            }
            outData = data
        }

        process.waitUntilExit()
        return outData
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

        guard codexBinary.hasPrefix("/") else {
            throw Error.spawnFailed("unsafe binary path: \(codexBinary) (must be absolute)")
        }
        guard !codexBinary.contains("..") else {
            throw Error.spawnFailed("unsafe binary path: \(codexBinary) (directory traversal not allowed)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexBinary).standardized
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

            // 🛡️ Security: Limit buffer size to prevent memory exhaustion (DoS) from unbounded output
            if buffer.count + chunk.count > 5 * 1024 * 1024 { // 5MB limit
                buffer.removeAll() // Clear buffer to prevent further memory usage
                lock.unlock()
                resolve(.failure(.spawnFailed("codex app-server output exceeded safe buffer limit")))
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
    internal static var sharedSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        // 🛡️ Security: Explicit timeouts to prevent thread exhaustion (DoS) from hanging external API calls
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 30.0
        return URLSession(configuration: config)
    }()

    /// `userAgent` по умолчанию — как у Claude Code CLI, чтобы не менять поведение
    /// существующих вызовов; провайдеры с другим API (напр. Kimi) передают свой.
    public static func httpGet(
        _ url: URL, _ bearerToken: String, userAgent: String = "claude-code/2.1.207"
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await sharedSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(
                domain: "Network",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]
            )
        }
        return data
    }

    /// POST application/x-www-form-urlencoded. В отличие от httpGet, НЕ бросает на
    /// non-2xx: refresh-эндпоинт Kimi кодирует причину отказа в теле (error=invalid_grant),
    /// поэтому (status, body) возвращаются вызывающему для классификации. Бросает только
    /// транспортные ошибки.
    public static func httpPostForm(
        _ url: URL,
        headers: [String: String],
        form: [(String, String)]
    ) async throws -> (statusCode: Int, body: Data) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let bodyString = form.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        request.httpBody = Data(bodyString.utf8)

        let (data, response) = try await sharedSession.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (statusCode, data)
    }
}

func friendly(_ error: Error) -> String {
    let ns = error as NSError
    if ns.domain == NSCocoaErrorDomain, ns.code == 260 { return "file not found" }
    if ns.domain == NSPOSIXErrorDomain { return ns.localizedDescription }
    return error.localizedDescription
}
