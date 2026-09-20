import 'package:flutter/material.dart';

import '../utils/webdav_errors.dart';

Future<void> showWebDavErrorDialog(BuildContext context, Object error) {
  final message = webDavErrorMessage(error);
  final isPerm = isWebDavPermissionError(error);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(isPerm ? '权限错误' : '操作失败'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}

Future<T?> runWebDavAction<T>(
  BuildContext context,
  Future<T> Function() action,
) async {
  try {
    return await action();
  } catch (e) {
    if (context.mounted) {
      await showWebDavErrorDialog(context, e);
    }
    return null;
  }
}
