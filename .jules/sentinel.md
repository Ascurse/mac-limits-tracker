## 2024-11-28 - Secure local file permissions

**Vulnerability:** Local JSON state files containing history data were created without specific file permissions (using `attributes: nil`), which could potentially expose local user data.
**Learning:** In macOS, using `FileManager.default.createFile` with `attributes: nil` might default to broader permissions than necessary. For files storing sensitive local data or user history, explicit file permissions should be enforced.
**Prevention:** Always explicitly use `attributes: [.posixPermissions: 0o600]` when creating local state files via `FileManager` to restrict access strictly to the owner and enforce the principle of least privilege.

## 2025-05-24 - Buffer overflow prevention when parsing external process stdout

**Vulnerability:** The JSON-RPC implementation `CodexAppServerRpc` read stdout directly into an unbound `Data` buffer (`buffer.append(chunk)`) while waiting for a newline delimiter, opening up the application to possible memory exhaustion (DoS).
**Learning:** Even when the local process (`codex app-server`) is considered trusted, defense-in-depth requires setting reasonable boundaries on memory accumulation from external I/O pipes. Unbounded buffered reads are a common vector for crashes/DoS.
**Prevention:** Enforce a strict buffer capacity limit on all stream readers and forcefully close/terminate the operation if it is exceeded.

## 2025-05-25 - Prevent DoS from unbounded external process output

**Vulnerability:** The `ProcessRunner.run` utility read standard output from external processes (like `claude auth status`) directly into memory using `pipe.fileHandleForReading.readToEnd()`. This allows a compromised or malfunctioning external process to exhaust application memory.
**Learning:** Utilities that execute arbitrary external processes should never read output without bound, even if the processes are considered trusted, to adhere to defense-in-depth principles.
**Prevention:** Always read external process output in bounded chunks and terminate the process if a safe memory threshold (e.g., 5MB) is exceeded.

## 2024-05-25 - Prevent DoS from hanging external API calls

**Vulnerability:** External API requests made via `URLSession(configuration: .ephemeral)` used default configurations which have a very high timeout (60 seconds for requests, 7 days for resources). This allows malicious or unresponsive external servers to hold connections open indefinitely, potentially exhausting threads and application resources (Denial of Service).
**Learning:** Network requests interacting with external servers should never use unbounded or overly generous default timeouts, as this represents a vector for resource exhaustion.
**Prevention:** Always specify explicitly constrained values for `timeoutIntervalForRequest` and `timeoutIntervalForResource` when configuring `URLSession`.

## 2025-05-25 - Prevent subprocess execution vulnerabilities with insecure path validation

**Vulnerability:** `ProcessRunner.run` and `CodexAppServerRpc.fetchRateLimits` checked if a binary path started with `/` using `hasPrefix("/")` to determine if it was absolute and therefore safe. However, this simplistic check allowed for directory traversal (e.g., `/usr/bin/../../malicious/path`) and could match unexpected directories (e.g., `/Users/Shared/MaliciousApp`). This could lead to arbitrary code execution if user input or compromised configuration dictates the binary path.
**Learning:** Using `hasPrefix("/")` alone is inadequate for path validation because it does not resolve relative segments (`..`). We must standardize the path to remove traversal characters and explicitly reject `..` to prevent arbitrary execution outside the intended absolute path.
**Prevention:** Always use `URL(fileURLWithPath: path).standardized.path` to resolve paths before validation and explicitly check for and reject the presence of `..` to prevent directory traversal attacks before execution.
