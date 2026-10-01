import 'package:flutter/material.dart';

/// The small, warm stationery palette used throughout Pocklino.
abstract final class PocklinoColors {
  static const canvas = Color(0xFFF8F6EF);
  static const surface = Color(0xFFFFFEFA);
  static const ink = Color(0xFF243C53);
  static const text = Color(0xFF293A40);
  static const muted = Color(0xFF6B777B);
  static const border = Color(0xFFE3E5DC);
  static const mint = Color(0xFFDCE9D5);
  static const butter = Color(0xFFF4E4AA);
  static const peach = Color(0xFFF3D8C9);
  static const sky = Color(0xFFDCEAF0);
  static const lavender = Color(0xFFE6E1EF);
  static const coral = Color(0xFFDD7C65);
  static const success = Color(0xFF426B52);
  static const cardColors = <Color>[
    surface,
    butter,
    mint,
    peach,
    sky,
    lavender,
  ];
}

abstract final class PocklinoTheme {
  static const _fallbackFonts = ['NotoEmoji', 'Roboto'];
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = dark ? const Color(0xFF19272D) : PocklinoColors.canvas;
    final surface = dark ? const Color(0xFF23343C) : PocklinoColors.surface;
    final foreground = dark ? const Color(0xFFF2F0E7) : PocklinoColors.text;
    final muted = dark ? const Color(0xFFB3BEBB) : PocklinoColors.muted;
    final border = dark ? const Color(0xFF405058) : PocklinoColors.border;
    final primary = dark ? PocklinoColors.butter : PocklinoColors.ink;
    final scheme = ColorScheme.fromSeed(
      seedColor: PocklinoColors.ink,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      onPrimary: dark ? PocklinoColors.ink : PocklinoColors.surface,
      secondary: dark ? PocklinoColors.mint : PocklinoColors.success,
      onSecondary: dark ? PocklinoColors.ink : Colors.white,
      surface: surface,
      onSurface: foreground,
      onSurfaceVariant: muted,
      outline: border,
      outlineVariant: border,
      error: dark ? const Color(0xFFF2A395) : const Color(0xFFAD453C),
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: 'DMSans',
      fontFamilyFallback: _fallbackFonts,
      scaffoldBackgroundColor: background,
    );
    TextStyle heading(double size, double height) => TextStyle(
      fontFamily: 'Lora',
      fontFamilyFallback: _fallbackFonts,
      fontSize: size,
      height: height,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.6,
      color: foreground,
    );
    final textTheme = base.textTheme.copyWith(
      displayLarge: heading(56, 1.12),
      displayMedium: heading(46, 1.15),
      displaySmall: heading(38, 1.18),
      headlineLarge: heading(34, 1.18),
      headlineMedium: heading(28, 1.22),
      headlineSmall: heading(24, 1.25),
      titleLarge: heading(22, 1.27),
      titleMedium: TextStyle(
        fontFamily: 'DMSans',
        fontFamilyFallback: _fallbackFonts,
        fontSize: 17,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: foreground,
      ),
      titleSmall: TextStyle(
        fontFamily: 'DMSans',
        fontFamilyFallback: _fallbackFonts,
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: foreground,
      ),
      bodyLarge: TextStyle(
        fontFamily: 'DMSans',
        fontFamilyFallback: _fallbackFonts,
        fontSize: 16,
        height: 1.5,
        color: foreground,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'DMSans',
        fontFamilyFallback: _fallbackFonts,
        fontSize: 15,
        height: 1.5,
        color: foreground,
      ),
      bodySmall: TextStyle(
        fontFamily: 'DMSans',
        fontFamilyFallback: _fallbackFonts,
        fontSize: 12,
        height: 1.5,
        color: muted,
      ),
      labelLarge: TextStyle(
        fontFamily: 'DMSans',
        fontFamilyFallback: _fallbackFonts,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: foreground,
      ),
      labelMedium: TextStyle(
        fontFamily: 'DMSans',
        fontFamilyFallback: _fallbackFonts,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: muted,
      ),
      labelSmall: TextStyle(
        fontFamily: 'DMSans',
        fontFamilyFallback: _fallbackFonts,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
        color: muted,
      ),
    );
    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
    );
    return base.copyWith(
      textTheme: textTheme,
      dividerColor: border,
      iconTheme: IconThemeData(color: foreground, size: 22),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: rounded,
          textStyle: const TextStyle(
            fontFamily: 'DMSans',
            fontFamilyFallback: _fallbackFonts,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          foregroundColor: foreground,
          side: BorderSide(color: border),
          shape: rounded,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 44),
          foregroundColor: primary,
          shape: rounded,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: scheme.onPrimary,
        elevation: 3,
        focusElevation: 4,
        hoverElevation: 4,
        shape: const StadiumBorder(),
        extendedTextStyle: const TextStyle(
          fontFamily: 'DMSans',
          fontFamilyFallback: _fallbackFonts,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: TextStyle(color: muted, fontSize: 15),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: dark ? const Color(0xFF4A503B) : PocklinoColors.butter,
        side: BorderSide(color: border),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(
          fontFamily: 'DMSans',
          fontFamilyFallback: _fallbackFonts,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: foreground,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: dark ? const Color(0xFF4A503B) : PocklinoColors.butter,
        height: 76,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'DMSans',
            fontFamilyFallback: _fallbackFonts,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: foreground,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: background,
        indicatorColor: dark ? const Color(0xFF4A503B) : PocklinoColors.butter,
        selectedIconTheme: IconThemeData(color: foreground),
        unselectedIconTheme: IconThemeData(color: muted),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: BorderSide(color: muted, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected)
                  ? primary
                  : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(scheme.onPrimary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
        dragHandleColor: border,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        titleTextStyle: textTheme.headlineSmall,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: PocklinoColors.ink,
        contentTextStyle: const TextStyle(
          fontFamily: 'DMSans',
          fontFamilyFallback: _fallbackFonts,
          color: PocklinoColors.surface,
          fontSize: 14,
        ),
        actionTextColor: PocklinoColors.butter,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: PocklinoColors.ink,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: const TextStyle(
          fontFamily: 'DMSans',
          fontFamilyFallback: _fallbackFonts,
          color: PocklinoColors.surface,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// A resolution-independent rendering of the Pocklino pocket-and-paper mark.
class PocketMark extends StatelessWidget {
  const PocketMark({super.key, this.size = 40, this.background = true});

  final double size;
  final bool background;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Pocklino',
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _PocketPainter(background)),
    ),
  );
}

class _PocketPainter extends CustomPainter {
  const _PocketPainter(this.background);
  final bool background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 128, size.height / 128);
    if (background) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 128, 128),
          const Radius.circular(28),
        ),
        Paint()..color = PocklinoColors.canvas,
      );
    }
    canvas.save();
    canvas.translate(64, 56);
    canvas.rotate(-0.1570796327);
    canvas.translate(-64, -56);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(39, 25, 51, 62),
        const Radius.circular(9),
      ),
      Paint()..color = PocklinoColors.butter,
    );
    final line =
        Paint()
          ..color = PocklinoColors.ink.withValues(alpha: 0.55)
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(49, 41), const Offset(76, 41), line);
    canvas.drawLine(const Offset(49, 49), const Offset(68, 49), line);
    canvas.restore();
    canvas.drawCircle(
      const Offset(91, 35),
      8,
      Paint()..color = PocklinoColors.coral,
    );
    final pocket =
        Path()
          ..moveTo(26, 53)
          ..quadraticBezierTo(26, 48, 31, 50)
          ..lineTo(64, 63)
          ..lineTo(97, 50)
          ..quadraticBezierTo(102, 48, 102, 53)
          ..lineTo(102, 87)
          ..quadraticBezierTo(102, 103, 86, 103)
          ..lineTo(42, 103)
          ..quadraticBezierTo(26, 103, 26, 87)
          ..close();
    canvas.drawPath(pocket, Paint()..color = PocklinoColors.ink);
    final seam =
        Path()
          ..moveTo(42, 83)
          ..quadraticBezierTo(64, 96, 86, 83);
    canvas.drawPath(
      seam,
      Paint()
        ..color = PocklinoColors.surface.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PocketPainter oldDelegate) =>
      oldDelegate.background != background;
}
