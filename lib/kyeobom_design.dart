import 'package:flutter/material.dart';

/// Color/layout tokens transcribed from the user-supplied Figma 49:2 overview.
/// Dark navy, blue accent and restrained white cards replace the old teal UI.
abstract final class KyeobomPalette {
  static const navy = Color(0xFF111A30);
  static const navyLight = Color(0xFF243047);
  static const blue = Color(0xFF315FEA);
  static const bluePale = Color(0xFFEDF3FF);
  static const teal = blue; // Backwards-compatible UI alias, not used for video.
  static const deepTeal = navy;
  static const ink = Color(0xFF1A2436);
  static const muted = Color(0xFF8C98AB);
  static const canvas = Color(0xFFF8FAFD);
  static const border = Color(0xFFE8EDF5);
  static const night = Color(0xFF020406);
  static const green = Color(0xFF24B88B);
}

abstract final class KyeobomTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: KyeobomPalette.blue,
      brightness: Brightness.light,
      surface: Colors.white,
    ).copyWith(
      primary: KyeobomPalette.navy,
      onPrimary: Colors.white,
      secondary: KyeobomPalette.blue,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: KyeobomPalette.canvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: KyeobomPalette.canvas,
        foregroundColor: KyeobomPalette.ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 27, fontWeight: FontWeight.w800,
          letterSpacing: -0.9, height: 1.27, color: KyeobomPalette.ink,
        ),
        titleLarge: TextStyle(
          fontSize: 21, fontWeight: FontWeight.w800,
          letterSpacing: -0.7, color: KyeobomPalette.ink,
        ),
        bodyMedium: TextStyle(
          fontSize: 14, height: 1.45, color: KyeobomPalette.muted,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: const TextStyle(color: Color(0xFFADB7C5), fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: KyeobomPalette.border),
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: KyeobomPalette.blue, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.redAccent),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: KyeobomPalette.navy,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: KyeobomPalette.ink,
          minimumSize: const Size.fromHeight(50),
          side: const BorderSide(color: KyeobomPalette.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: KyeobomPalette.border),
        ),
      ),
    );
  }
}

/// Shows the user's own app icon after tools/apply_kyeobom_icons.sh is run.
/// Before installation it uses a neutral vector placeholder, not an invented
/// replacement for the provided design asset.
class KyeobomMark extends StatelessWidget {
  const KyeobomMark({super.key, this.size = 64, this.showTile = true});
  final double size;
  final bool showTile;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: KyeobomPalette.navy,
        borderRadius: BorderRadius.circular(size * .23),
      ),
      child: Icon(Icons.visibility_rounded,
          color: Colors.white, size: size * .43),
    );
    final image = Image.asset(
      'assets/branding/app_icon_real.png',
      width: size, height: size, fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
    return Semantics(label: '켜봄 앱 로고', child: image);
  }
}

class KyeobomEyebrow extends StatelessWidget {
  const KyeobomEyebrow(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: KyeobomPalette.blue, fontWeight: FontWeight.w700,
      fontSize: 11, letterSpacing: .8,
    ),
  );
}

class KyeobomRoleCard extends StatelessWidget {
  const KyeobomRoleCard({
    super.key, required this.icon, required this.title,
    required this.subtitle, required this.onTap, this.featured = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool featured;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(15),
    child: InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: featured ? KyeobomPalette.blue : KyeobomPalette.border,
            width: featured ? 1.5 : 1,
          ),
          boxShadow: [BoxShadow(
            color: KyeobomPalette.navy.withValues(alpha: .025),
            blurRadius: 16, offset: const Offset(0, 5),
          )],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: featured ? KyeobomPalette.bluePale : KyeobomPalette.canvas,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(featured ? '거치폰' : '뷰어폰',
                style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: featured ? KyeobomPalette.blue : KyeobomPalette.muted,
                ),
              ),
            ),
            const Spacer(),
            CircleAvatar(
              radius: 20,
              backgroundColor: featured ? KyeobomPalette.navy : KyeobomPalette.bluePale,
              child: Icon(icon, size: 19,
                color: featured ? Colors.white : KyeobomPalette.navy),
            ),
          ]),
          const SizedBox(height: 13),
          Text(title, style: const TextStyle(
            color: KyeobomPalette.ink, fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(
            color: KyeobomPalette.muted, fontSize: 13, height: 1.45)),
          const SizedBox(height: 16),
          Row(children: [
            Icon(Icons.check_circle_outline_rounded,
              color: featured ? KyeobomPalette.blue : KyeobomPalette.muted, size: 16),
            const SizedBox(width: 7),
            Expanded(child: Text(
              featured ? '화면을 어둡게 유지하며 대기' : '원할 때 실시간 영상 확인',
              style: const TextStyle(fontSize: 12, color: KyeobomPalette.muted),
            )),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Text(featured ? '거치폰으로 시작하기' : '홈캠 보러 가기',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: featured ? KyeobomPalette.blue : KyeobomPalette.ink)),
            const SizedBox(width: 3),
            const Icon(Icons.arrow_forward_rounded, size: 16,
              color: KyeobomPalette.blue),
          ]),
        ]),
      ),
    ),
  );
}

class KyeobomStatusPill extends StatelessWidget {
  const KyeobomStatusPill({
    super.key, required this.label, this.active = false, this.dark = false,
  });
  final String label;
  final bool active, dark;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: dark ? const Color(0xBB14231C) : KyeobomPalette.bluePale,
      borderRadius: BorderRadius.circular(100),
      border: Border.all(color: dark
          ? const Color(0x663A6654) : KyeobomPalette.border),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(
          shape: BoxShape.circle, color: active ? KyeobomPalette.green
              : (dark ? Colors.white54 : KyeobomPalette.muted))),
        const SizedBox(width: 7),
        Text(label, style: TextStyle(color: dark ? Colors.white70 : KyeobomPalette.ink,
          fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    ),
  );
}
