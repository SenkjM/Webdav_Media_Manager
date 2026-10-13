import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/queue_task.dart';
import 'package:webdav_media_manager/services/task_store.dart';

/// `QueueTask.toMap()` writes column names straight into the INSERT, so a field
/// with no matching column fails at runtime on *every* write while
/// `flutter analyze` stays green.
///
/// That is how `is_enumerator` shipped broken: the list showed tasks with no
/// progress, nothing was ever persisted, and a restart lost whatever was left.
/// These tests make the model and the DDL move together.
void main() {
  /// Column names declared in `queue_tasks`, read from the DDL itself.
  Set<String> ddlColumns() => RegExp(
    r'^ {2}(\w+) ',
    multiLine: true,
  ).allMatches(TaskStore.createTableSql).map((m) => m.group(1)!).toSet();

  group('queue_tasks schema', () {
    test('the DDL declares the columns the parser expects', () {
      final cols = ddlColumns();
      expect(cols, contains('id'));
      expect(cols, contains('is_enumerator'));
      expect(cols, contains('next_retry_at'));
    });

    test('every QueueTask.toMap() key exists in the DDL', () {
      final task = QueueTask(
        id: 'task-1',
        sourceName: 'src',
        remotePath: '/comics/a.cbz',
        fileName: 'a.cbz',
        createdAt: DateTime(2026, 1, 1),
      );
      final cols = ddlColumns();
      final missing = task
          .toMap()
          .keys
          .where((k) => !cols.contains(k))
          .toList();
      expect(
        missing,
        isEmpty,
        reason:
            'QueueTask.toMap() writes $missing but queue_tasks has no such '
            'column, so every insert throws. Add the column and bump '
            'TaskStore.schemaVersion.',
      );
    });

    test('fields survive a toMap/fromMap round trip', () {
      final task = QueueTask(
        id: 'task-2',
        sourceName: 'src',
        remotePath: '/comics/b.cbz',
        fileName: 'b.cbz',
        createdAt: DateTime(2026, 1, 1),
        kind: TaskKind.mangaPack,
        status: TaskStatus.active,
        unitsTotal: 7,
        unitsDone: 3,
        cacheGroupId: 'group-1',
        isEnumerator: true,
      );
      final back = QueueTask.fromMap(task.toMap());
      expect(back.kind, TaskKind.mangaPack);
      expect(back.status, TaskStatus.active);
      expect(back.unitsTotal, 7);
      expect(back.unitsDone, 3);
      expect(back.cacheGroupId, 'group-1');
      expect(back.isEnumerator, isTrue);
    });
  });
}
