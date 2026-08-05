## 2025-02-14 - Arbitrary Subprocess Execution via Unsafe Binary Path

**Vulnerability:**
The application used `guard binary.hasPrefix("/")` to validate paths for subprocess execution. This allowed attackers to execute arbitrary binaries if they provided custom paths (e.g., via environment variables) such as `/tmp/malicious_bin`. It also lacked directory traversal checks, theoretically allowing inputs like `/usr/bin/../../tmp/malicious_bin`.

**Learning:**
Prefix validation (`hasPrefix("/")`) is insufficient for security boundaries. Path validation must restrict the effective directory of the binary to known, safe execution contexts and explicitly reject path traversal elements (`..`).

**Prevention:**
Always restrict subprocess execution paths to an explicit whitelist of safe directories (e.g., `/usr/bin/`, `/opt/homebrew/bin/`, or specific user local bins) and enforce checks against directory traversal (`!binary.contains("..")`). Ensure that any path resolution or string manipulation accurately determines the root directory of the binary before validating it against the whitelist.
