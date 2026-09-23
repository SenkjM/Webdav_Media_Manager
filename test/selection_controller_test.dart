import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/utils/selection_controller.dart';

/// 多选交互回归：那个按钮只在**计数打满**时才是叉号，且叉号只取消全选、
/// 不退出多选界面。旧实现把「全选」和「关闭」做成两个按钮，一进多选就
/// 摆着叉号，全选后再点一次又会连多选一起退掉。
void main() {
  const keys = ['a', 'b', 'c', 'd'];

  SelectionController fresh() => SelectionController(total: keys.length);

  group('全选判定用计数对比', () {
    test('只选了一项时不是全选，按钮显示「全选」', () {
      final s = fresh().enter('a');
      expect(s.count, 1);
      expect(s.isAllSelected, isFalse);
      expect(s.showsDeselect, isFalse);
    });

    test('手动一项项点满之后也算全选，按钮变叉号', () {
      var s = fresh().enter('a');
      for (final k in ['b', 'c', 'd']) {
        s = s.toggle(k);
      }
      expect(s.isAllSelected, isTrue);
      expect(s.showsDeselect, isTrue);
    });

    test('空列表永远不算全选', () {
      const s = SelectionController(active: true, total: 0);
      expect(s.isAllSelected, isFalse);
    });
  });

  group('叉号是取消全选，不是退出多选', () {
    test('全选后取消全选：选择清空，但仍在多选界面', () {
      final all = fresh().toggleSelectAll(keys);
      expect(all.isAllSelected, isTrue);
      final cleared = all.toggleSelectAll(keys);
      expect(cleared.count, 0);
      expect(cleared.active, isTrue, reason: '取消全选不该顺手退出多选');
      expect(cleared.showsDeselect, isFalse, reason: '计数掉下来了，按钮回到「全选」');
    });

    test('取消全选之后再全选仍然可用', () {
      final again = fresh()
          .toggleSelectAll(keys)
          .toggleSelectAll(keys)
          .toggleSelectAll(keys);
      expect(again.count, keys.length);
    });

    // 回归：音乐库从来没有调用过 sync，total 一直是 0，于是全选之后
    // isAllSelected 永远为假——「全选点多少遍还是全选」，按钮回不到叉号。
    // 计数对比的总数只能由这次传入的列表决定。
    test('界面从未同步过 total 时，全选之后仍然能取消全选', () {
      final all = const SelectionController().toggleSelectAll(keys);
      expect(all.isAllSelected, isTrue);
      expect(all.showsDeselect, isTrue);
      final cleared = all.toggleSelectAll(keys);
      expect(cleared.count, 0);
      expect(cleared.active, isTrue);
      expect(cleared.showsDeselect, isFalse);
    });

    test('列表变长后按新列表判定全选，而不是沿用旧总数', () {
      final s = fresh().toggleSelectAll(keys);
      expect(s.isAllSelected, isTrue);
      final more = s.toggleSelectAll([...keys, 'e']);
      expect(more.count, 0, reason: '旧总数下它是「全选」，新列表下应当转为取消全选');
      expect(more.active, isTrue);
    });

    test('从整组进入多选，逐条取消到最后一条时按钮变回「全选」', () {
      var s = fresh().enter('', entry: SelectionEntry.selectAll, selectOnly: keys);
      expect(s.showsDeselect, isTrue);
      for (final k in ['a', 'b', 'c']) {
        s = s.toggle(k);
      }
      expect(s.count, 1);
      expect(s.showsDeselect, isFalse);
    });
  });

  group('退出与同步', () {
    test('取消到最后一项时退出多选（旧行为，保留）', () {
      final s = fresh().enter('a').toggle('a');
      expect(s.active, isFalse);
      expect(s.count, 0);
    });

    test('exit 清空选择', () {
      final s = fresh().toggleSelectAll(keys).exit();
      expect(s.active, isFalse);
      expect(s.count, 0);
    });

    test('列表变短后，已经不存在的 key 会被丢掉', () {
      final s = fresh()
          .toggleSelectAll(keys)
          .sync(total: 2, validKeys: ['a', 'b']);
      expect(s.count, 2);
      expect(s.total, 2);
      expect(s.isAllSelected, isTrue, reason: '新的总数是 2，选中的正好是这 2 个');
    });

    test('同步到空列表时退出多选', () {
      final s = fresh().enter('a').sync(total: 0, validKeys: const []);
      expect(s.active, isFalse);
    });
  });

  group('相等性', () {
    test('同一份状态的两个实例相等（Set 按内容比较）', () {
      final a = fresh().toggleSelectAll(keys);
      final b = fresh().toggleSelectAll(keys);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
