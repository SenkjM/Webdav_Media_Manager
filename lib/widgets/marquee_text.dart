import 'package:flutter/material.dart';

import '../models/webdav_account.dart';

/// Display label: 名称（用户名）
String webDavAccountLabel(WebDavAccount account) {
  final user = account.username.trim();
  if (user.isEmpty) return account.name;
  return '${account.name}（$user）';
}

/// Horizontally auto-scrolling text when overflow; otherwise static.
class MarqueeText extends StatefulWidget {
  const MarqueeText(
    this.text, {
    super.key,
    this.style,
    this.height = 20,
  });

  final String text;
  final TextStyle? style;
  final double height;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final ScrollController _controller;
  AnimationController? _anim;
  bool _needsScroll = false;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  void _check() {
    if (!mounted || !_controller.hasClients) return;
    final max = _controller.position.maxScrollExtent;
    final needs = max > 1;
    if (needs != _needsScroll) {
      setState(() => _needsScroll = needs);
    }
    _anim?.dispose();
    _anim = null;
    if (!needs) {
      _controller.jumpTo(0);
      return;
    }
    _anim = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (max * 40).clamp(4000, 16000).toInt()),
    )..addListener(() {
        if (!_controller.hasClients) return;
        _controller.jumpTo(max * _anim!.value);
      });
    Future<void> loop() async {
      while (mounted && _needsScroll && _anim != null) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        if (!mounted || _anim == null) return;
        await _anim!.forward(from: 0);
        await Future<void>.delayed(const Duration(milliseconds: 800));
        if (!mounted || _anim == null) return;
        _controller.jumpTo(0);
      }
    }
    loop();
  }

  @override
  void dispose() {
    _anim?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: ClipRect(
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Text(
            widget.text,
            style: widget.style,
            maxLines: 1,
            softWrap: false,
          ),
        ),
      ),
    );
  }
}
