import 'package:flutter/material.dart';

/// The colours of the Pocklino mark: an ink-blue pocket, a butter note and a
/// coral dot. The interface is that mark at full size.
abstract final class PocklinoColors {
  static const oat = Color(0xFFF8F6EF);
  static const paper = Color(0xFFFFFEFA);
  static const ink = Color(0xFF243C53);
  static const butter = Color(0xFFF4E4AA);
  static const coral = Color(0xFFDD7C65);

  /// The darkest ink: outlines by day, text on butter and coral at any hour.
  static const deepInk = Color(0xFF1D3145);
}

/// One of the six papers a page can be written on.
@immutable
class PaperStock {
  const PaperStock({
    required this.fill,
    required this.fold,
    required this.edge,
    required this.ink,
    required this.quiet,
  });

  /// The face of the paper.
  final Color fill;

  /// The reverse side, seen on folded corners.
  final Color fold;

  /// The cut edge.
  final Color edge;

  /// Writing on the paper.
  final Color ink;

  /// How strongly small print is set, as a share of [ink]. Chosen so that
  /// labels keep a contrast of 4.5 to 1 on every paper.
  final double quiet;

  Color get inkSoft => ink.withValues(alpha: .86);
  Color get inkMuted => ink.withValues(alpha: quiet);
  Color get inkLine => ink.withValues(alpha: .34);
}

/// Everything the pocket interface is painted with. Day is a warm desk with
/// bright paper; evening is the inside of the pocket with dimmed paper.
@immutable
class PocketPalette extends ThemeExtension<PocketPalette> {
  const PocketPalette({
    required this.night,
    required this.desk,
    required this.ink,
    required this.muted,
    required this.line,
    required this.hairline,
    required this.sheet,
    required this.well,
    required this.pocket,
    required this.onPocket,
    required this.onPocketMuted,
    required this.stitch,
    required this.butter,
    required this.coral,
    required this.shade,
    required this.stocks,
  });

  final bool night;

  /// What the paper lies on.
  final Color desk;

  /// Text and outlines on the desk and on sheets.
  final Color ink;
  final Color muted;

  /// Outline of controls.
  final Color line;

  /// Dividers and other quiet rules.
  final Color hairline;

  /// Sheets, dialogs, menus and fields.
  final Color sheet;

  /// A recessed area on a sheet.
  final Color well;

  /// The front of the pocket: the bottom bar and the side panel.
  final Color pocket;
  final Color onPocket;
  final Color onPocketMuted;
  final Color stitch;

  final Color butter;
  final Color coral;

  /// The hard shadow under paper and buttons.
  final Color shade;

  final List<PaperStock> stocks;

  /// Outline width of paper and controls.
  double get stroke => night ? 1.1 : 1.3;

  PaperStock stock(int index) => stocks[index % stocks.length];

  static PocketPalette of(BuildContext context) =>
      Theme.of(context).extension<PocketPalette>()!;

  static final day = PocketPalette(
    night: false,
    desk: const Color(0xFFF4F0E6),
    ink: PocklinoColors.deepInk,
    muted: const Color(0xFF5E6D7A),
    line: PocklinoColors.deepInk,
    hairline: const Color(0x261D3145),
    sheet: const Color(0xFFFFFDF7),
    well: const Color(0xFFF1ECDF),
    pocket: PocklinoColors.ink,
    onPocket: const Color(0xFFF6F2E6),
    onPocketMuted: const Color(0xFFA9B8C6),
    stitch: const Color(0xFFF8D873),
    butter: const Color(0xFFF8D873),
    coral: const Color(0xFFE8785E),
    shade: PocklinoColors.deepInk,
    stocks: [
      for (final (fill, fold) in const [
        (0xFFFBF8EE, 0xFFE2DDCB),
        (0xFFF8D873, 0xFFDDB94E),
        (0xFFBCE2B6, 0xFF98C592),
        (0xFFF6B7A1, 0xFFDC967F),
        (0xFFB2D8EE, 0xFF8FBBD4),
        (0xFFD2C7F0, 0xFFB3A6D8),
      ])
        PaperStock(
          fill: Color(fill),
          fold: Color(fold),
          edge: PocklinoColors.deepInk,
          ink: PocklinoColors.deepInk,
          quiet: .78,
        ),
    ],
  );

  static final evening = PocketPalette(
    night: true,
    desk: const Color(0xFF0E1822),
    ink: const Color(0xFFF1ECDF),
    muted: const Color(0xFF9FB0BF),
    line: const Color(0x52F1ECDF),
    hairline: const Color(0x1FF1ECDF),
    sheet: const Color(0xFF182634),
    well: const Color(0xFF223446),
    pocket: const Color(0xFF1A2A38),
    onPocket: const Color(0xFFF1ECDF),
    onPocketMuted: const Color(0xFF9FB0BF),
    stitch: const Color(0xFFF8D873),
    butter: const Color(0xFFF8D873),
    coral: const Color(0xFFE8785E),
    shade: const Color(0xFF060B10),
    stocks: [
      for (final (fill, fold, hue) in const [
        (0xFF27333F, 0xFF3A4856, 0xFFFBF8EE),
        (0xFF3A3420, 0xFF574E2E, 0xFFF8D873),
        (0xFF22382B, 0xFF335240, 0xFFBCE2B6),
        (0xFF41291F, 0xFF613D2E, 0xFFF6B7A1),
        (0xFF1E3545, 0xFF2E4F66, 0xFFB2D8EE),
        (0xFF2F2A45, 0xFF463F66, 0xFFD2C7F0),
      ])
        PaperStock(
          fill: Color(fill),
          fold: Color(fold),
          edge: Color(hue).withValues(alpha: .55),
          ink: const Color(0xFFF1ECDF),
          quiet: .66,
        ),
    ],
  );

  @override
  PocketPalette copyWith() => this;

  @override
  PocketPalette lerp(covariant PocketPalette? other, double t) =>
      other == null || t < .5 ? this : other;
}

/// The three voices of the interface: a grotesque for titles, a plain sans for
/// reading and a monospace for the small print found on tickets and receipts.
abstract final class PocketType {
  static const fallback = ['NotoEmoji', 'Roboto'];

  static TextStyle display(
    double size, {
    Color? color,
    FontWeight weight = FontWeight.w700,
    double height = 1.14,
  }) => TextStyle(
    fontFamily: 'Bricolage',
    fontFamilyFallback: fallback,
    fontSize: size,
    height: height,
    fontWeight: weight,
    letterSpacing: size * -.012,
    color: color,
  );

  static TextStyle body(
    double size, {
    Color? color,
    FontWeight weight = FontWeight.w400,
    double height = 1.45,
  }) => TextStyle(
    fontFamily: 'DMSans',
    fontFamilyFallback: fallback,
    fontSize: size,
    height: height,
    fontWeight: weight,
    letterSpacing: 0,
    color: color,
  );

  /// Set in capitals by [MonoLabel]; the tracking assumes that.
  static TextStyle mono(
    double size, {
    Color? color,
    FontWeight weight = FontWeight.w500,
  }) => TextStyle(
    fontFamily: 'DMMono',
    fontFamilyFallback: fallback,
    fontSize: size,
    height: 1.3,
    fontWeight: weight,
    letterSpacing: size * .09,
    color: color,
  );

  static TextStyle emoji(double size, {Color? color}) => TextStyle(
    fontFamily: 'NotoEmoji',
    fontSize: size,
    height: 1.15,
    color: color,
  );
}

abstract final class PocklinoTheme {
  static ThemeData get light => _build(PocketPalette.day);
  static ThemeData get dark => _build(PocketPalette.evening);

  static ThemeData _build(PocketPalette p) {
    final brightness = p.night ? Brightness.dark : Brightness.light;
    final primary = p.night ? p.butter : p.ink;
    final onPrimary = p.night ? PocklinoColors.deepInk : p.sheet;
    final scheme = ColorScheme.fromSeed(
      seedColor: PocklinoColors.ink,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: p.butter,
      onPrimaryContainer: PocklinoColors.deepInk,
      secondary: p.coral,
      onSecondary: PocklinoColors.deepInk,
      secondaryContainer: p.butter,
      onSecondaryContainer: PocklinoColors.deepInk,
      tertiary: p.coral,
      onTertiary: PocklinoColors.deepInk,
      tertiaryContainer: p.coral,
      onTertiaryContainer: PocklinoColors.deepInk,
      surface: p.sheet,
      onSurface: p.ink,
      onSurfaceVariant: p.muted,
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: p.sheet,
      surfaceContainerLow: p.sheet,
      surfaceContainer: p.sheet,
      surfaceContainerHigh: p.sheet,
      surfaceContainerHighest: p.well,
      outline: p.night ? p.line : p.muted,
      outlineVariant: p.hairline,
      inverseSurface: p.pocket,
      onInverseSurface: p.onPocket,
      inversePrimary: p.butter,
      error: p.night ? const Color(0xFFF2A395) : const Color(0xFFB3402F),
      onError: p.night ? PocklinoColors.deepInk : Colors.white,
      errorContainer:
          p.night ? const Color(0xFF55291F) : const Color(0xFFFBDDD3),
      onErrorContainer: p.ink,
      shadow: p.shade,
      scrim: p.night ? Colors.black : PocklinoColors.deepInk,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: 'DMSans',
      fontFamilyFallback: PocketType.fallback,
      scaffoldBackgroundColor: p.desk,
      extensions: [p],
    );
    final textTheme = base.textTheme.copyWith(
      displayLarge: PocketType.display(52, color: p.ink, height: 1.05),
      displayMedium: PocketType.display(44, color: p.ink, height: 1.06),
      displaySmall: PocketType.display(36, color: p.ink, height: 1.08),
      headlineLarge: PocketType.display(32, color: p.ink, height: 1.1),
      headlineMedium: PocketType.display(27, color: p.ink, height: 1.12),
      headlineSmall: PocketType.display(23, color: p.ink),
      titleLarge: PocketType.display(20, color: p.ink, height: 1.2),
      titleMedium: PocketType.body(
        16,
        color: p.ink,
        weight: FontWeight.w600,
        height: 1.35,
      ),
      titleSmall: PocketType.body(
        14,
        color: p.ink,
        weight: FontWeight.w600,
        height: 1.35,
      ),
      bodyLarge: PocketType.body(16, color: p.ink, height: 1.5),
      bodyMedium: PocketType.body(15, color: p.ink, height: 1.5),
      bodySmall: PocketType.body(13, color: p.muted),
      labelLarge: PocketType.body(
        15,
        color: p.ink,
        weight: FontWeight.w600,
        height: 1.2,
      ),
      labelMedium: PocketType.body(
        13,
        color: p.muted,
        weight: FontWeight.w600,
        height: 1.2,
      ),
      labelSmall: PocketType.mono(10.5, color: p.muted),
    );
    final outline = BorderSide(color: p.line, width: p.stroke);
    final control = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    final buttonText = PocketType.body(
      15,
      weight: FontWeight.w600,
      height: 1.2,
    );
    OutlineInputBorder field(BorderSide side) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: side,
    );
    return base.copyWith(
      textTheme: textTheme,
      dividerColor: p.hairline,
      dividerTheme: DividerThemeData(color: p.hairline, thickness: 1, space: 1),
      splashColor: p.ink.withValues(alpha: .08),
      highlightColor: p.ink.withValues(alpha: .05),
      hoverColor: p.ink.withValues(alpha: .05),
      focusColor: p.ink.withValues(alpha: .1),
      iconTheme: IconThemeData(color: p.ink, size: 22),
      appBarTheme: AppBarTheme(
        backgroundColor: p.desk,
        foregroundColor: p.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 4,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: p.sheet,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: outline,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          backgroundColor: primary,
          foregroundColor: onPrimary,
          disabledBackgroundColor: p.ink.withValues(alpha: .14),
          disabledForegroundColor: p.ink.withValues(alpha: .45),
          shape: control,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          foregroundColor: p.ink,
          backgroundColor: p.night ? Colors.transparent : p.sheet,
          side: outline,
          shape: control,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 44),
          foregroundColor: p.night ? p.butter : p.ink,
          shape: control,
          textStyle: buttonText,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: p.ink),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.coral,
        foregroundColor: PocklinoColors.deepInk,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: const CircleBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.night ? p.ink.withValues(alpha: .06) : p.sheet,
        hintStyle: PocketType.body(15, color: p.muted),
        labelStyle: PocketType.body(15, color: p.muted),
        floatingLabelStyle: PocketType.body(
          15,
          color: p.ink,
          weight: FontWeight.w600,
        ),
        helperStyle: PocketType.body(12, color: p.muted),
        prefixIconColor: p.muted,
        suffixIconColor: p.ink,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: field(outline),
        enabledBorder: field(outline),
        disabledBorder: field(BorderSide(color: p.hairline, width: p.stroke)),
        focusedBorder: field(BorderSide(color: primary, width: 2)),
        errorBorder: field(BorderSide(color: scheme.error, width: p.stroke)),
        focusedErrorBorder: field(BorderSide(color: scheme.error, width: 2)),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.night ? p.butter : p.ink,
        // Butter would vanish on the butter paper by day.
        selectionColor:
            p.night
                ? p.butter.withValues(alpha: .3)
                : p.ink.withValues(alpha: .22),
        selectionHandleColor: p.coral,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: BorderSide(color: p.ink, width: 1.6),
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected)
                  ? primary
                  : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(onPrimary),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? onPrimary : p.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected)
                  ? primary
                  : Colors.transparent,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected)
                  ? Colors.transparent
                  : p.muted,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: p.hairline,
        circularTrackColor: Colors.transparent,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.ink,
        textColor: p.ink,
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodySmall,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.sheet,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: outline,
        ),
        textStyle: PocketType.body(15, color: p.ink, weight: FontWeight.w500),
        labelTextStyle: WidgetStatePropertyAll(
          PocketType.body(15, color: p.ink, weight: FontWeight.w500),
        ),
        iconColor: p.ink,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.sheet,
        modalBackgroundColor: p.sheet,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        modalBarrierColor: (p.night ? Colors.black : PocklinoColors.deepInk)
            .withValues(alpha: .55),
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.sheet,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        barrierColor: (p.night ? Colors.black : PocklinoColors.deepInk)
            .withValues(alpha: .55),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: outline,
        ),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.sheet,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: outline,
        ),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: p.sheet,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: outline,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.night ? const Color(0xFF2B4157) : p.pocket,
        contentTextStyle: PocketType.body(14, color: p.onPocket),
        actionTextColor: p.butter,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.night ? const Color(0xFF2B4157) : p.pocket,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: PocketType.body(12, color: p.onPocket),
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
    container: true,
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
        Paint()..color = PocklinoColors.oat,
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
        ..color = PocklinoColors.paper.withValues(alpha: 0.8)
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

/// The lowercase wordmark, set in Lora 600 as in the logo.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    'pocklino',
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.fade,
    style: TextStyle(
      fontFamily: 'Lora',
      fontSize: size,
      height: 1.1,
      fontWeight: FontWeight.w600,
      letterSpacing: -size / 26,
      color: color ?? PocketPalette.of(context).ink,
    ),
  );
}
