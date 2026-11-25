import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// Verbatim Quran text. Always RTL, never truncated, selectable.
class QuranText extends StatelessWidget {
  final String text;
  final double size;
  final TextAlign align;
  final Color? color;
  const QuranText(this.text, {super.key, this.size = 28, this.align = TextAlign.right, this.color});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SelectableText(
        text,
        textAlign: align,
        style: quranStyle(size, color ?? p.ink),
        semanticsLabel: text,
      ),
    );
  }
}

/// Arabic-Indic end-of-ayah ornament with the verse number.
String ayahMark(int n) {
  const digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  final s = n.toString().split('').map((d) => digits[int.parse(d)]).join();
  return '۝$s';
}

class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsets padding;
  const SectionLabel(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(20, 28, 20, 10)});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(children: [
        Expanded(child: Text(text.toUpperCase(), style: Theme.of(context).textTheme.labelSmall)),
        ?trailing,
      ]),
    );
  }
}

class Surface extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final VoidCallback? onTap;
  final Color? color;
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: margin,
      child: Material(
        color: color ?? p.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: p.line),
            ),
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

class Tag extends StatelessWidget {
  final String text;
  final Color? color;
  final Color? background;
  final IconData? icon;
  const Tag(this.text, {super.key, this.color, this.background, this.icon});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final fg = color ?? p.inkSoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: background ?? p.surfaceAlt, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
        Text(text, style: sans(11.5, weight: FontWeight.w600, color: fg)),
      ]),
    );
  }
}

class ThinProgress extends StatelessWidget {
  final double value;
  final double height;
  const ThinProgress(this.value, {super.key, this.height = 4});
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: height,
        backgroundColor: p.line,
        color: p.accent,
      ),
    );
  }
}

class ProgressRing extends StatelessWidget {
  final double value;
  final double size;
  final Widget? child;
  final double stroke;
  const ProgressRing({super.key, required this.value, this.size = 120, this.child, this.stroke = 6});
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(value.clamp(0, 1), p.line, p.accent, stroke),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color track, fill;
  final double stroke;
  _RingPainter(this.v, this.track, this.fill, this.stroke);
  @override
  void paint(Canvas c, Size s) {
    final r = Rect.fromLTWH(stroke / 2, stroke / 2, s.width - stroke, s.height - stroke);
    final base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    c.drawArc(r, 0, math.pi * 2, false, base);
    if (v > 0) {
      final arc = Paint()
        ..color = fill
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      c.drawArc(r, -math.pi / 2, math.max(v * math.pi * 2, 0.04), false, arc);
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.fill != fill || o.track != track;
}

/// The brand mark: a rising path with three stations – three moments in a
/// day, one continuous journey. Drawn in code so it scales and themes.
/// Geometry matches design/app-icon-1024.svg.
class BrandMark extends StatelessWidget {
  final double size;
  final Color? color;
  final Color? gapColor;
  const BrandMark({super.key, this.size = 56, this.color, this.gapColor});
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: BrandMarkPainter(color ?? p.accent, gapColor ?? p.bg)),
    );
  }
}

class BrandMarkPainter extends CustomPainter {
  final Color color;
  final Color gap;
  BrandMarkPainter(this.color, this.gap);

  static const _p = [Offset(0.14, 0.80), Offset(0.47, 0.80), Offset(0.53, 0.22), Offset(0.86, 0.22)];
  static const _stations = [(0.0, 0.052), (0.5, 0.066), (1.0, 0.082)];

  static Offset _at(double t) {
    final u = 1 - t;
    return _p[0] * (u * u * u) + _p[1] * (3 * u * u * t) + _p[2] * (3 * u * t * t) + _p[3] * (t * t * t);
  }

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final path = Path()
      ..moveTo(_p[0].dx * w, _p[0].dy * w)
      ..cubicTo(_p[1].dx * w, _p[1].dy * w, _p[2].dx * w, _p[2].dy * w, _p[3].dx * w, _p[3].dy * w);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.038
        ..strokeCap = StrokeCap.round,
    );
    for (final (t, r) in _stations) {
      final c = _at(t) * w;
      canvas.drawCircle(c, w * (r + 0.03), Paint()..color = gap);
      canvas.drawCircle(c, w * r, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(BrandMarkPainter o) => o.color != color || o.gap != gap;
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 48),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: p.accentSoft, shape: BoxShape.circle),
          child: Icon(icon, color: p.accent, size: 28),
        ),
        const SizedBox(height: 18),
        Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(message, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: 18), action!],
      ]),
    );
  }
}

/// Renders Tanzil's transliteration markup: <u>…</u> marks long vowels
/// (shown underlined) and <b>…</b> letters that are written but not
/// pronounced in connected reading (shown faint). Text is not altered.
class TransliterationText extends StatelessWidget {
  final String raw;
  final double size;
  const TransliterationText(this.raw, {super.key, this.size = 15});
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final base = sans(size, color: p.inkSoft, height: 1.55).copyWith(fontStyle: FontStyle.italic);
    final spans = <TextSpan>[];
    final re = RegExp(r'<(u|b)>(.*?)</\1>', caseSensitive: false);
    var i = 0;
    final normalised = raw.replaceAll('</U>', '</u>').replaceAll('</B>', '</b>');
    for (final m in re.allMatches(normalised)) {
      if (m.start > i) spans.add(TextSpan(text: normalised.substring(i, m.start)));
      final kind = m.group(1)!.toLowerCase();
      spans.add(TextSpan(
        text: m.group(2),
        style: kind == 'u'
            ? TextStyle(decoration: TextDecoration.underline, decorationColor: p.inkFaint, color: p.ink)
            : TextStyle(color: p.inkFaint),
      ));
      i = m.end;
    }
    if (i < normalised.length) spans.add(TextSpan(text: normalised.substring(i)));
    return Text.rich(TextSpan(style: base, children: spans));
  }
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
}

String formatInt(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}
