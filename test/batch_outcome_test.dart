// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/queue_task.dart';
import 'package:webdav_media_manager/utils/batch_outcome.dart';

void main() {
  test('batch outcome: success / partial / failed', () {
    expect(batchOutcome(ok: 3, failed: 0), TaskStatus.completed);
    expect(batchOutcome(ok: 2, failed: 1), TaskStatus.partial);
    expect(batchOutcome(ok: 0, failed: 2), TaskStatus.failed);
  });

  test('retryItem retries up to 3 then rethrows', () async {
    var n = 0;
    await expectLater(
      retryItem(() async {
        n++;
        throw StateError('x');
      }),
      throwsStateError,
    );
    expect(n, 3);
  });

  test('retryItem succeeds on 2nd attempt', () async {
    var n = 0;
    final v = await retryItem(() async {
      if (++n < 2) throw StateError('x');
      return 7;
    });
    expect(v, 7);
    expect(n, 2);
  });

  test('retryItem does not retry cancel', () async {
    var n = 0;
    await expectLater(
      retryItem(() async {
        n++;
        throw ArgumentError('cancel');
      }, isCancel: (e) => e is ArgumentError),
      throwsArgumentError,
    );
    expect(n, 1);
  });

  test('partial is terminal and round-trips by name', () {
    expect(TaskStatus.values.byName('partial'), TaskStatus.partial);
  });
}
