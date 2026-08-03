## 2024-11-28 - Secure local file permissions

**Vulnerability:** Local JSON state files containing history data were created without specific file permissions (using `attributes: nil`), which could potentially expose local user data.
**Learning:** In macOS, using `FileManager.default.createFile` with `attributes: nil` might default to broader permissions than necessary. For files storing sensitive local data or user history, explicit file permissions should be enforced.
**Prevention:** Always explicitly use `attributes: [.posixPermissions: 0o600]` when creating local state files via `FileManager` to restrict access strictly to the owner and enforce the principle of least privilege.

## 2025-05-24 - Buffer overflow prevention when parsing external process stdout

**Vulnerability:** The JSON-RPC implementation `CodexAppServerRpc` read stdout directly into an unbound `Data` buffer (`buffer.append(chunk)`) while waiting for a newline delimiter, opening up the application to possible memory exhaustion (DoS).
**Learning:** Even when the local process (`codex app-server`) is considered trusted, defense-in-depth requires setting reasonable boundaries on memory accumulation from external I/O pipes. Unbounded buffered reads are a common vector for crashes/DoS.
**Prevention:** Enforce a strict buffer capacity limit on all stream readers and forcefully close/terminate the operation if it is exceeded.
