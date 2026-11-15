import 'package:flutter/material.dart';

/// Visual-only design tokens for KyeoBom.
/// The real-time connection, camera and audio behavior live outside this file.
abstract final class KyeobomPalette {
  static const Color teal = Color(0xFF2F8278);
  static const Color deepTeal = Color(0xFF185A55);
  static const Color ink = Color(0xFF182724);
  static const Color muted = Color(0xFF73837F);
  static const Color canvas = Color(0xFFF7F9F8);
  static const Color border = Color(0xFFE5ECE9);
  static const Color night = Color(0xFF080A0A);
}

abstract final class KyeobomTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: KyeobomPalette.teal,
      brightness: Brightness.light,
      surface: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: KyeobomPalette.canvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: KyeobomPalette.canvas,
        foregroundColor: KyeobomPalette.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: KyeobomPalette.ink,
          fontSize: 28,
          height: 1.32,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
        ),
        titleLarge: TextStyle(
          color: KyeobomPalette.ink,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        bodyMedium: TextStyle(
          color: KyeobomPalette.muted,
          fontSize: 14,
          height: 1.5,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: KyeobomPalette.border),
          borderRadius: BorderRadius.circular(16),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(
            color: KyeobomPalette.teal,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.redAccent),
          borderRadius: BorderRadius.circular(16),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: KyeobomPalette.teal,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: KyeobomPalette.deepTeal,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: KyeobomPalette.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

/// A vector-built approximation of the house/lens symbol.
/// It does not depend on a remote Figma asset URL or a new package.
class KyeobomMark extends StatelessWidget {
  const KyeobomMark({super.key, this.size = 80, this.showTile = true});

  final double size;
  final bool showTile;

  @override
  Widget build(BuildContext context) {
    final symbol = CustomPaint(
      size: Size.square(size * (showTile ? 0.60 : 1)),
      painter: const _HomeLensPainter(),
    );
    if (!showTile) return Semantics(label: '켜봄 로고', child: symbol);
    return Semantics(
      label: '켜봄 로고',
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFE5F2EE),
          borderRadius: BorderRadius.circular(size * .27),
        ),
        child: symbol,
      ),
    );
  }
}

class _HomeLensPainter extends CustomPainter {
  const _HomeLensPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final house = Path()
      ..moveTo(w * .14, h * .43)
      ..lineTo(w * .50, h * .11)
      ..lineTo(w * .86, h * .43)
      ..lineTo(w * .86, h * .86)
      ..quadraticBezierTo(w * .86, h * .92, w * .80, h * .92)
      ..lineTo(w * .20, h * .92)
      ..quadraticBezierTo(w * .14, h * .92, w * .14, h * .86)
      ..close();
    canvas.drawPath(house, Paint()..color = KyeobomPalette.teal);
    final roof = Path()
      ..moveTo(w * .08, h * .44)
      ..lineTo(w * .50, h * .07)
      ..lineTo(w * .92, h * .44);
    canvas.drawPath(
      roof,
      Paint()
        ..color = KyeobomPalette.deepTeal
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * .125
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final lens = Offset(w * .50, h * .60);
    canvas.drawCircle(lens, w * .235, Paint()..color = Colors.white);
    canvas.drawCircle(lens, w * .17, Paint()..color = KyeobomPalette.deepTeal);
    canvas.drawCircle(
      Offset(w * .53, h * .63),
      w * .085,
      Paint()..color = const Color(0xFF0C4744),
    );
  }

  @override
  bool shouldRepaint(covariant _HomeLensPainter oldDelegate) => false;
}

class KyeobomEyebrow extends StatelessWidget {
  const KyeobomEyebrow(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: KyeobomPalette.teal,
          fontSize: 12,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w800,
        ),
      );
}

class KyeobomRoleCard extends StatelessWidget {
  const KyeobomRoleCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.featured = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: featured ? const Color(0xFFF0F8F5) : Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: featured ? const Color(0xFFC5DFD7) : KyeobomPalette.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(17),
                  color: featured
                      ? const Color(0xFFD8EEE7)
                      : KyeobomPalette.canvas,
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: KyeobomPalette.deepTeal, size: 27),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        color: KyeobomPalette.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: KyeobomPalette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: KyeobomPalette.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class KyeobomStatusPill extends StatelessWidget {
  const KyeobomStatusPill({
    super.key,
    required this.label,
    this.active = false,
    this.dark = false,
  });

  final String label;
  final bool active;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? const Color(0xFFB8DCD2) : KyeobomPalette.deepTeal;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF162523) : const Color(0xFFEAF4F0),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? const Color(0xFF55D6B7) : fg.withValues(alpha: .50),
              ),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
