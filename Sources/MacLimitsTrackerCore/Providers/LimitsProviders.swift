import Foundation

/// Источник данных о лимитах Claude Code.
public struct ClaudeLimitsProvider {
    let claudeBinary: String
    let statsCacheURL: URL
    let processRunner: (String, [String]) async throws -> Data
    let fileReader: (URL) async throws -> Data

    public init(
        claudeBinary: String? = nil,
        statsCacheURL: URL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/stats-cache.json"),
        processRunner: @escaping (String, [String]) async throws -> Data = ProcessRunner.run,
        fileReader: @escaping (URL) async throws -> Data = { try Data(contentsOf: $0) }
    ) {
        self.claudeBinary = claudeBinary ?? ProcessRunner.defaultClaudeBinary()
        self.statsCacheURL = statsCacheURL
        self.processRunner = processRunner
        self.fileReader = fileReader
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
            fetchedAt: now,
            providerError: errorMessage
        )
    }
}

/// Источник данных о лимитах Codex.
public struct CodexLimitsProvider {
    let authFileURL: URL
    let fileReader: (URL) async throws -> Data

    public init(
        authFileURL: URL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json"),
        fileReader: @escaping (URL) async throws -> Data = { try Data(contentsOf: $0) }
    ) {
        self.authFileURL = authFileURL
        self.fileReader = fileReader
    }

    public func fetch() async -> CodexStatus {
        let now = Date()
        do {
            let data = try await fileReader(authFileURL)
            let file = try JSONDecoder().decode(CodexAuthFileJSON.self, from: data)
            let token = file.tokens?.idToken ?? file.tokens?.accessToken
            let loggedIn = (token != nil) && (file.authMode != nil)
            if let token {
                let claims = CodexClaimsParser.parse(token)
                return CodexStatus(
                    loggedIn: loggedIn,
                    authMode: file.authMode,
                    email: claims.email,
                    planType: claims.planType,
                    subscriptionActiveUntil: claims.subscriptionActiveUntil,
                    daysUntilRenewal: CodexClaimsParser.daysUntilRenewal(from: claims),
                    accountOwner: claims.accountOwner,
                    fetchedAt: now,
                    providerError: nil
                )
            }
            return CodexStatus(
                loggedIn: loggedIn,
                authMode: file.authMode,
                email: nil, planType: nil,
                subscriptionActiveUntil: nil, daysUntilRenewal: nil,
                accountOwner: nil, fetchedAt: now,
                providerError: "auth.json has no ChatGPT tokens"
            )
        } catch {
            return CodexStatus(
                loggedIn: false, authMode: nil,
                email: nil, planType: nil,
                subscriptionActiveUntil: nil, daysUntilRenewal: nil,
                accountOwner: nil, fetchedAt: now,
                providerError: "auth.json read failed: \(friendly(error))"
            )
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

func friendly(_ error: Error) -> String {
    let ns = error as NSError
    if ns.domain == NSCocoaErrorDomain, ns.code == 260 { return "file not found" }
    if ns.domain == NSPOSIXErrorDomain { return ns.localizedDescription }
    return error.localizedDescription
}