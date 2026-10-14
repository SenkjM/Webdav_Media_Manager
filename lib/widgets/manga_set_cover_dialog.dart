// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// Result of the blocking "set current page as cover" dialog.
enum MangaCoverSetOutcome { done, cancelled, failed }

/// Modal progress for setting a manga cover.
///
/// The route is up before [work] starts, so cancelling pops this dialog and
/// not the reader underneath. [barrierDismissible] stays false at the call
/// site; the only way out is Cancel or the work finishing.
class MangaSetCoverDialog extends StatefulWidget {
  const MangaSetCoverDialog({
    super.key,
    required this.title,
    required this.body,
    required this.cancelLabel,
    required this.work,
  });

  final String title;
  final String body;
  final String cancelLabel;
  final Future<MangaCoverSetOutcome> Function(CancelToken cancel) work;

  @override
  State<MangaSetCoverDialog> createState() => _MangaSetCoverDialogState();
}

class _MangaSetCoverDialogState extends State<MangaSetCoverDialog> {
  final CancelToken _cancel = CancelToken();
  var _closed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_run());
    });
  }

  Future<void> _run() async {
    var outcome = MangaCoverSetOutcome.failed;
    try {
      outcome = await widget.work(_cancel);
    } catch (e) {
      outcome = (e is DioException && CancelToken.isCancel(e)) ||
              _cancel.isCancelled
          ? MangaCoverSetOutcome.cancelled
          : MangaCoverSetOutcome.failed;
    }
    _finish(outcome);
  }

  void _finish(MangaCoverSetOutcome outcome) {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.pop(context, outcome);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(widget.title),
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text(widget.body)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _cancel.cancel('user cancelled set cover');
              _finish(MangaCoverSetOutcome.cancelled);
            },
            child: Text(widget.cancelLabel),
          ),
        ],
      ),
    );
  }
}
