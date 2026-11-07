import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/services/dlna_cast_service.dart';

/// The cast mode of a new session: the device preset is the persistent truth,
/// devices without one follow the settings-page default (the same value the
/// compatibility sheet shows), and MKV passthrough forces direct on top.
void main() {
  test('a configured device keeps its own switch', () {
    expect(
      resolveSessionDirect(
        deviceForceDirect: true,
        defaultValue: false,
        mkvDirect: false,
      ),
      isTrue,
    );
    expect(
      resolveSessionDirect(
        deviceForceDirect: false,
        defaultValue: true,
        mkvDirect: false,
      ),
      isFalse,
    );
  });

  test('a device without a preset follows the global default', () {
    // Regression: this used to be a hard-coded `true`, so a cast went direct
    // while the compatibility sheet displayed the (off) global default.
    expect(
      resolveSessionDirect(
        deviceForceDirect: null,
        defaultValue: false,
        mkvDirect: false,
      ),
      isFalse,
    );
    expect(
      resolveSessionDirect(
        deviceForceDirect: null,
        defaultValue: true,
        mkvDirect: false,
      ),
      isTrue,
    );
  });

  test('MKV passthrough wins over both switches', () {
    expect(
      resolveSessionDirect(
        deviceForceDirect: false,
        defaultValue: false,
        mkvDirect: true,
      ),
      isTrue,
    );
  });
}
