import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// 统一渲染接口返回的 LaTeX，并在表达式异常时回退为可复制文本。
class LatexText extends StatelessWidget {
  const LatexText(
    this.value, {
    this.color,
    this.fontSize = 18,
    super.key,
  });

  final String value;
  final Color? color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final String normalized = _normalize(value);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SelectableMath.tex(
        normalized,
        mathStyle: MathStyle.display,
        textStyle: TextStyle(
          color: color ?? Theme.of(context).colorScheme.onSurface,
          fontSize: fontSize,
        ),
        onErrorFallback: (_) => SelectableText(
          value,
          style: TextStyle(color: color, fontSize: fontSize),
        ),
      ),
    );
  }

  String _normalize(String source) {
    String result = source.trim();
    if (result.startsWith(r'$$') && result.endsWith(r'$$') && result.length > 4) {
      result = result.substring(2, result.length - 2).trim();
    } else if (result.startsWith(r'$') && result.endsWith(r'$') && result.length > 2) {
      result = result.substring(1, result.length - 1).trim();
    }
    return result;
  }
}
