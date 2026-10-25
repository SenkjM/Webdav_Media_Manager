package com.senkjm.media_manager

/**
 * FFI bridge for driver and account operations (Phase 2 Wave C).
 * All methods suspend and dispatch to background thread.
 */
interface AccountApi {
    // ── Driver-level operations ───────────────────────────────────────────

    /**
     * List directory entries using driver-level config (no saved account).
     * @param providerType e.g. "webdav", "aliyundrive", "115"
     * @param configJson JSON object with provider-specific config
     * @param path Remote path to list
     * @return JSON array string or throws on error
     */
    suspend fun driverList(providerType: String, configJson: String, path: String): String

    suspend fun driverMkdir(providerType: String, configJson: String, path: String): String
    suspend fun driverRename(providerType: String, configJson: String, oldPath: String, newPath: String): String
    suspend fun driverRemove(providerType: String, configJson: String, path: String): String

    /**
     * Get metadata for a single entry.
     * @return JSON object string, "null" if not found, or throws on error
     */
    suspend fun driverGet(providerType: String, configJson: String, path: String): String

    // ── Account-based operations ──────────────────────────────────────────

    /**
     * List directory entries for a saved account.
     * @param accountId DB-stored account UUID
     * @param path Remote path to list
     * @return JSON array string or throws on error
     */
    suspend fun accountListDir(accountId: String, path: String): String

    suspend fun accountMkdir(accountId: String, path: String): String
    suspend fun accountRename(accountId: String, oldPath: String, newPath: String): String
    suspend fun accountRemove(accountId: String, path: String): String

    /**
     * Get metadata for a single entry in the account's directory.
     * @return JSON object string, "null" if not found, or throws on error
     */
    suspend fun accountGetEntry(accountId: String, path: String): String
}
