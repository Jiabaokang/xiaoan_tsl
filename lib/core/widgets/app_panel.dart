import 'package:flutter/material.dart';

// 翻译页各区域共用的圆角容器。
class AppPanel extends StatelessWidget {
  const AppPanel({super.key, required this.child, this.tinted = false});

  final Widget child;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: tinted
            ? scheme.primaryContainer.withValues(alpha: 0.48)
            : scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}
