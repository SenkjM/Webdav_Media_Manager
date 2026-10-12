// SPDX-License-Identifier: AGPL-3.0-or-later
import '../models/queue_task.dart';

/// Internal automatic retries per file in batch tasks (scan / manga scrape).
const int kBatchItemMaxAttempts = 3;

/// All ok → completed; some failed → partial; all failed → failed.
TaskStatus batchOutcome({required int ok, required int failed}) {
  if (failed <= 0) return TaskStatus.completed;
  if (ok <= 0) return TaskStatus.failed;
  return TaskStatus.partial;
}

/// Run [body] up to [attempts] times. [isCancel] errors rethrow immediately.
Future<T> retryItem<T>(
  Future<T> Function() body, {
  int attempts = kBatchItemMaxAttempts,
  bool Function(Object e)? isCancel,
}) async {
  Object? last;
  StackTrace? lastSt;
  for (var i = 0; i < attempts; i++) {
    try {
      return await body();
    } catch (e, st) {
      if (isCancel?.call(e) ?? false) rethrow;
      last = e;
      lastSt = st;
    }
  }
  Error.throwWithStackTrace(last!, lastSt!);
}
