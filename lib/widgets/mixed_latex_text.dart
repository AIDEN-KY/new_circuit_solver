import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// 在中文段落中混排行内 LaTeX，并自动识别常见物理量、数值和单位。
class MixedLatexText extends StatelessWidget {
  const MixedLatexText(
    this.value, {
    this.style,
    this.autoDetectMath = true,
    super.key,
  });

  final String value;
  final TextStyle? style;
  final bool autoDetectMath;

  static final RegExp _explicitMath = RegExp(
    r'(\$[^$\n]+\$|\\\([^\n]+?\\\))',
  );
  static final RegExp _plainMath = RegExp(
    r'((?:[A-Za-z][A-Za-z0-9]*(?:_\{?[A-Za-z0-9]+\}?)?|[-+]?\d+(?:\.\d+)?)(?:\s*(?:=|≈|≤|≥|\+|-|×|÷|/)\s*(?:[A-Za-z][A-Za-z0-9]*(?:_\{?[A-Za-z0-9]+\}?)?|[-+]?\d+(?:\.\d+)?))*\s*(?:[kMmunpμ]?(?:Ω|A|V|W|F|H|s|Hz)|%|℃|°C)?)',
  );

  @override
  Widget build(BuildContext context) {
    final TextStyle effective = DefaultTextStyle.of(context).style.merge(style);
    final List<InlineSpan> spans = <InlineSpan>[];
    int cursor = 0;
    for (final RegExpMatch match in _explicitMath.allMatches(value)) {
      if (match.start > cursor) {
        _appendPlain(spans, value.substring(cursor, match.start), effective);
      }
      final String source = match.group(0)!;
      _appendMath(
        spans,
        source.startsWith(r'$')
            ? source.substring(1, source.length - 1)
            : source.substring(2, source.length - 2),
        effective,
      );
      cursor = match.end;
    }
    if (cursor < value.length) {
      _appendPlain(spans, value.substring(cursor), effective);
    }
    return SelectionArea(
      child: RichText(
        text: TextSpan(style: effective, children: spans),
      ),
    );
  }

  void _appendPlain(
    List<InlineSpan> spans,
    String text,
    TextStyle effective,
  ) {
    if (!autoDetectMath) {
      spans.add(TextSpan(text: text));
      return;
    }
    int cursor = 0;
    for (final RegExpMatch match in _plainMath.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      _appendMath(spans, _plainToLatex(match.group(0)!), effective);
      cursor = match.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
  }

  void _appendMath(
    List<InlineSpan> spans,
    String latex,
    TextStyle effective,
  ) {
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Math.tex(
          latex.trim(),
          mathStyle: MathStyle.text,
          textStyle: effective,
          onErrorFallback: (_) => Text(latex, style: effective),
        ),
      ),
    );
  }

  String _plainToLatex(String source) {
    String result = source.trim().replaceAll('≈', r'\approx ');
    result = result.replaceAll('≤', r'\le ');
    result = result.replaceAll('≥', r'\ge ');
    result = result.replaceAll('×', r'\times ');
    result = result.replaceAll('÷', r'\div ');
    result = result.replaceAll('Ω', r'\Omega');
    result = result.replaceAll('μ', r'\mu ');
    return result;
  }
}
