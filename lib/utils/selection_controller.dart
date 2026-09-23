import 'package:flutter/foundation.dart';

/// 列表 / 网格多选的唯一状态源。
///
/// 存在的理由：多选工具栏曾经把「全选」和「退出多选」做成两个互不相干的
/// 按钮，于是**一进入多选就摆着一个叉号**——用户会以为那是「关闭」，点它
/// 等于白选；而全选之后那个按钮又变成「取消全选」，顺手把多选也退掉，
/// 选得越多越容易一次点没。
///
/// 现在的规则只有一条：**计数器对比**。选中数与可选总数相等时，那个按钮
/// 才是叉号（取消全选）；任何一次手动取消都会把计数打回去，按钮随即变回
/// 「全选」。
///
/// 关键点是 [isAllSelected] 用计数比较而不是「记不记得按过全选」：用户手动
/// 一个个点满之后，按钮也该变成叉号；反过来，从整组进入多选再逐条取消到
/// 只剩一条时，按钮必须变回「全选」。
///
/// 多选界面本身只由 [exit] 结束，**不会**被「取消全选」顺手带走。
@immutable
class SelectionController {
  const SelectionController({
    this.active = false,
    this.selected = const <String>{},
    this.total = 0,
  });

  /// 是否处于多选界面。
  final bool active;

  /// 已选条目的 key。
  final Set<String> selected;

  /// 当前列表里可选条目的总数。
  final int total;

  int get count => selected.length;

  bool contains(String key) => selected.contains(key);

  /// 空列表不算全选：没有可选项时按钮不该变成叉号。
  bool get isAllSelected => total > 0 && selected.length >= total;

  /// 工具栏上那个按钮当前是不是叉号（取消全选）。
  bool get showsDeselect => isAllSelected;

  /// 进入多选。
  ///
  /// [selectOnly] 给出初始选中集合：[entry] 是 [SelectionEntry.selectAll] 时
  /// 整组选（界面带着整组进来），否则只选 [key]。
  SelectionController enter(
    String key, {
    SelectionEntry entry = SelectionEntry.toggle,
    Iterable<String> selectOnly = const <String>[],
  }) {
    return SelectionController(
      active: true,
      selected: entry == SelectionEntry.selectAll
          ? selectOnly.toSet()
          : {...selected, key},
      total: total,
    );
  }

  /// 点按一行：已选则取消，未选则加入。
  ///
  /// 取消到空集合时退出多选——这是旧行为，保留（列表上没有别的「结束」手势）。
  SelectionController toggle(String key) {
    final next = {...selected};
    if (!next.remove(key)) next.add(key);
    return SelectionController(
      active: next.isNotEmpty,
      selected: next,
      total: total,
    );
  }

  /// 点工具栏那个按钮。
  ///
  /// 不是全选 → 全选；已经是全选 → 只清空选择，**保持多选界面**。
  /// [allKeys] 由列表传入，控制器不持有列表副本。
  SelectionController toggleSelectAll(Iterable<String> allKeys) {
    if (isAllSelected) {
      return SelectionController(active: active, total: total);
    }
    return SelectionController(
      active: true,
      selected: allKeys.toSet(),
      total: total,
    );
  }

  /// 退出多选。
  SelectionController exit() => SelectionController(total: total);

  /// 列表内容或总数变化后同步：丢掉已经不存在的 key，并同步新的总数。
  SelectionController sync({required int total, Iterable<String>? validKeys}) {
    final next = validKeys == null
        ? {...selected}
        : selected.where(validKeys.contains).toSet();
    return SelectionController(
      active: active && next.isNotEmpty,
      selected: next,
      total: total,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SelectionController &&
      other.active == active &&
      other.total == total &&
      setEquals(other.selected, selected);

  @override
  int get hashCode => Object.hash(active, total, Object.hashAllUnordered(selected));

  @override
  String toString() =>
      'SelectionController(active: $active, count: $count, total: $total)';
}

/// 多选进入方式。
enum SelectionEntry {
  /// 长按 / 点按勾选进来，选中数不一定等于总数。
  toggle,

  /// 按了「全选」，或界面带着整组进入多选。
  selectAll,
}
