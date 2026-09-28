import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../utils/webdav_errors.dart';

Future<void> showWebDavErrorDialog(BuildContext context, Object error) {
  final message = webDavErrorMessage(error, AppLocalizations.of(context)!);
  final isPerm = isWebDavPermissionError(error);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        isPerm
            ? AppLocalizations.of(ctx)!.webdavErrorPerm
            : AppLocalizations.of(ctx)!.webdavErrorGeneric,
      ),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(AppLocalizations.of(ctx)!.dialogOk),
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
