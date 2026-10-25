/// **Wave B cutover (B6)**: the pure-Dart HTTP stream bridge is gutted.
///
/// The Rust local proxy ([RustProxyBridge] / `wdmm_proxy_*` FFI) is the
/// replacement path. It already serves local files over HTTP; serving
/// Dart-driver byte ranges (MustProxy / crypt streams) and DLNA LAN cast
/// needs the credential bridge planned for proxy-cutover-R12. Until that
/// lands, [expose] fails loudly so neither path silently runs the obsolete
/// Dart server.
///
/// The class shell is preserved so call sites compile unchanged. Callers
/// should let the [UnsupportedError] propagate into their existing error
/// handling and surface it as a user-visible error state.
class LocalStreamBridge {
  LocalStreamBridge({
    this.idleTimeout = const Duration(minutes: 10),
    Object? bindAddress,
    String? externalHost,
  });

  final Duration idleTimeout;

  /// Always throws. The Dart HTTP server that backed this is gone; the Rust
  /// proxy is the replacement (see class doc).
  Future<Uri> expose({
    required String accountId,
    required String remotePath,
    required int size,
    required Stream<List<int>> Function(String path, int start, int end) ranges,
    String? name,
  }) async {
    throw UnsupportedError(
      'LocalStreamBridge is gutted (Wave B / B6). MustProxy and DLNA LAN '
      'cast require the Rust credential bridge (TODO proxy-cutover-R12).',
    );
  }

  /// No-op. The Dart HTTP server that backed this is gone.
  Future<void> dispose() async {}
}
