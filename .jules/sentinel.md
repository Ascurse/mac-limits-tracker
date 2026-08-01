## 2024-11-28 - Secure local file permissions

**Vulnerability:** Local JSON state files containing history data were created without specific file permissions (using `attributes: nil`), which could potentially expose local user data.
**Learning:** In macOS, using `FileManager.default.createFile` with `attributes: nil` might default to broader permissions than necessary. For files storing sensitive local data or user history, explicit file permissions should be enforced.
**Prevention:** Always explicitly use `attributes: [.posixPermissions: 0o600]` when creating local state files via `FileManager` to restrict access strictly to the owner and enforce the principle of least privilege.
