import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 多选工具栏的外壳。网络库与音乐库**共用同一个**，宽度与滚动行为不会再
/// 各自走样。
///
/// 两处细节都是踩过的坑：
///
/// * 底色在滚动层**外面**。曾经把滚动层直接当 `SafeArea` 的孩子，按钮一
///   比屏幕宽，灰色条就只画到内容末端，右边露出一截空白。
/// * 铺满整宽要用**具体**宽度（`constraints.maxWidth`）。横向滚动层给子级
///   的宽度约束是无限的，这时候 `minWidth: double.infinity` 是个不可满足
///   的约束，整条工具栏直接不画。
class SelectionToolbar extends StatelessWidget {
  const SelectionToolbar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.elevated,
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            // 按钮多到放不下时可以横着滚，底色仍然铺满整宽。
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(children: children),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
