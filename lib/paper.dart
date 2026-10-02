import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'design.dart';

/// The silhouettes of the things people keep in a pocket.
enum PaperShape {
  /// A plain sheet.
  sheet,

  /// A note with a folded corner.
  slip,

  /// A till receipt, torn off along the bottom.
  receipt,

  /// A cinema ticket with a perforated stub.
  ticket,

  /// A luggage tag.
  tag,

  /// An envelope seen from the back.
  envelope,

  /// A folder with a tab.
  folder,
}

/// Cuts a rectangle into one of the [PaperShape]s and draws its edge.
class PaperBorder extends OutlinedBorder {
  const PaperBorder(this.shape, {super.side, this.stub = 0, this.radius = 6});

  final PaperShape shape;

  /// Height of a ticket's stub, measured from the bottom edge.
  final double stub;
  final double radius;

  static const fold = 20.0;
  static const tooth = 9.0;
  static const bite = 5.0;
  static const notch = 7.0;
  static const chamfer = 17.0;
  static const hole = 5.5;
  static const holeDrop = 17.0;
  static const tab = 13.0;

  /// How far an envelope's flap reaches down on a paper of this width.
  static double flapDepth(double width) => (width * .28).clamp(40.0, 104.0);

  /// The room a silhouette takes from its content.
  static EdgeInsets inset(PaperShape shape) => switch (shape) {
    PaperShape.receipt => const EdgeInsets.only(bottom: bite),
    PaperShape.tag => const EdgeInsets.only(top: holeDrop + hole + 2),
    PaperShape.folder => const EdgeInsets.only(top: tab),
    _ => EdgeInsets.zero,
  };

  static double tabWidth(double width) => (width * .42).clamp(56.0, 132.0);

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  PaperBorder copyWith({BorderSide? side}) =>
      PaperBorder(shape, side: side ?? this.side, stub: stub, radius: radius);

  @override
  ShapeBorder scale(double t) => PaperBorder(
    shape,
    side: side.scale(t),
    stub: stub * t,
    radius: radius * t,
  );

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final l = rect.left, t = rect.top, r = rect.right, b = rect.bottom;
    final corner = Radius.circular(math.min(radius, rect.shortestSide / 2));
    final c = corner.x;
    final path = Path();
    void bottomCorners() {
      path
        ..lineTo(r, b - c)
        ..arcToPoint(Offset(r - c, b), radius: corner)
        ..lineTo(l + c, b)
        ..arcToPoint(Offset(l, b - c), radius: corner);
    }

    switch (shape) {
      case PaperShape.sheet:
      case PaperShape.envelope:
        path.addRRect(RRect.fromRectAndRadius(rect, corner));
      case PaperShape.slip:
        final f = math.min(fold, rect.width / 3);
        path
          ..moveTo(l + c, t)
          ..lineTo(r - f, t)
          ..lineTo(r, t + f);
        bottomCorners();
        path
          ..lineTo(l, t + c)
          ..arcToPoint(Offset(l + c, t), radius: corner)
          ..close();
      case PaperShape.receipt:
        final teeth = math.max(3, (rect.width / tooth).round());
        final step = rect.width / teeth;
        path
          ..moveTo(l + c, t)
          ..lineTo(r - c, t)
          ..arcToPoint(Offset(r, t + c), radius: corner)
          ..lineTo(r, b - bite);
        for (var i = 0; i < teeth; i++) {
          path
            ..lineTo(r - (i + .5) * step, b)
            ..lineTo(i == teeth - 1 ? l : r - (i + 1) * step, b - bite);
        }
        path
          ..lineTo(l, t + c)
          ..arcToPoint(Offset(l + c, t), radius: corner)
          ..close();
      case PaperShape.ticket:
        final y = (b - stub).clamp(t + c + notch, b - c - notch);
        const bitten = Radius.circular(notch);
        path
          ..moveTo(l + c, t)
          ..lineTo(r - c, t)
          ..arcToPoint(Offset(r, t + c), radius: corner)
          ..lineTo(r, y - notch)
          ..arcToPoint(Offset(r, y + notch), radius: bitten, clockwise: false);
        bottomCorners();
        path
          ..lineTo(l, y + notch)
          ..arcToPoint(Offset(l, y - notch), radius: bitten, clockwise: false)
          ..lineTo(l, t + c)
          ..arcToPoint(Offset(l + c, t), radius: corner)
          ..close();
      case PaperShape.tag:
        final cut = math.min(chamfer, rect.width / 4);
        path
          ..moveTo(l + cut, t)
          ..lineTo(r - cut, t)
          ..lineTo(r, t + cut);
        bottomCorners();
        path
          ..lineTo(l, t + cut)
          ..close()
          ..addOval(
            Rect.fromCircle(
              center: Offset(rect.center.dx, t + holeDrop),
              radius: hole,
            ),
          )
          ..fillType = PathFillType.evenOdd;
      case PaperShape.folder:
        final width = tabWidth(rect.width);
        path
          ..moveTo(l + c, t)
          ..lineTo(l + width - 12, t)
          ..lineTo(l + width, t + tab)
          ..lineTo(r - c, t + tab)
          ..arcToPoint(Offset(r, t + tab + c), radius: corner);
        bottomCorners();
        path
          ..lineTo(l, t + c)
          ..arcToPoint(Offset(l + c, t), radius: corner)
          ..close();
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width <= 0) return;
    canvas.drawPath(
      getOuterPath(rect),
      side.toPaint()..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PaperBorder &&
      other.shape == shape &&
      other.side == side &&
      other.stub == stub &&
      other.radius == radius;

  @override
  int get hashCode => Object.hash(shape, side, stub, radius);
}

/// Splits [source] into dashes, so curves and corners can be stitched.
Path dashPath(Path source, {double dash = 6, double gap = 5}) {
  final result = Path();
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      final end = math.min(distance + dash, metric.length);
      result.addPath(metric.extractPath(distance, end), Offset.zero);
      distance = end + gap;
    }
  }
  return result;
}

/// A piece of paper cut to a [PaperShape]. By day it lies on the desk with a
/// hard shadow and sinks when pressed; in the evening it only keeps its edge.
class Paper extends StatefulWidget {
  const Paper({
    super.key,
    required this.shape,
    required this.stock,
    required this.child,
    this.stub,
    this.stubHeight = 44,
    this.padding = const EdgeInsets.fromLTRB(14, 14, 14, 10),
    this.onTap,
    this.onLongPress,
    this.pinned = false,
    this.raised = true,
    this.radius = 6,
    this.button = false,
  });

  final PaperShape shape;
  final PaperStock stock;
  final Widget child;

  /// Announce the whole paper as one button. Leave it off when the paper
  /// holds controls of its own, which a button would hide from a reader.
  final bool button;

  /// What a ticket carries below its perforation.
  final Widget? stub;
  final double stubHeight;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool pinned;
  final bool raised;
  final double radius;

  @override
  State<Paper> createState() => _PaperState();
}

class _PaperState extends State<Paper> {
  bool _down = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = PocketPalette.of(context);
    final stock = widget.stock;
    final ticket = widget.shape == PaperShape.ticket;
    final border = PaperBorder(
      widget.shape,
      stub: ticket ? widget.stubHeight : 0,
      radius: widget.radius,
      side: BorderSide(color: stock.edge, width: palette.stroke),
    );
    final lift = widget.raised && !palette.night;
    final still = MediaQuery.disableAnimationsOf(context);
    Widget content = Padding(
      padding: widget.padding + PaperBorder.inset(widget.shape),
      child: widget.child,
    );
    if (ticket) {
      // In a box taller than its content the stub keeps to the bottom edge,
      // where the perforation is cut.
      content = Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          content,
          SizedBox(
            height: widget.stubHeight,
            child: Padding(
              padding: EdgeInsets.only(
                left: widget.padding.left,
                right: widget.padding.right,
              ),
              child: widget.stub,
            ),
          ),
        ],
      );
    }
    content = CustomPaint(
      painter: _PaperDetails(
        shape: widget.shape,
        stock: stock,
        stroke: palette.stroke,
        stub: ticket ? widget.stubHeight : 0,
      ),
      child: DefaultTextStyle.merge(
        style: PocketType.body(13, color: stock.inkSoft),
        child: IconTheme.merge(
          data: IconThemeData(color: stock.ink),
          child: content,
        ),
      ),
    );
    final tappable = widget.onTap != null || widget.onLongPress != null;
    // Pressed, the paper sinks into its shadow. Under a pointer the shadow
    // grows instead of the paper moving, so the pointer never loses it.
    final shadow =
        _down
            ? 1.0
            : _hover && tappable
            ? 4.5
            : 3.0;
    return AnimatedContainer(
      duration: Duration(milliseconds: still ? 0 : 90),
      curve: Curves.easeOut,
      transform: Matrix4.translationValues(0, lift && _down ? 2 : 0, 0),
      decoration: ShapeDecoration(
        shape: border.copyWith(side: BorderSide.none),
        shadows: [
          if (lift)
            BoxShadow(
              color: palette.shade,
              offset: Offset(0, shadow),
              blurRadius: 0,
            ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.passthrough,
        children: [
          Material(
            color: stock.fill,
            shape: border,
            clipBehavior: Clip.antiAlias,
            child:
                tappable
                    ? Semantics(
                      button: widget.button,
                      child: InkWell(
                        onTap: widget.onTap,
                        onLongPress: widget.onLongPress,
                        onHighlightChanged: (value) {
                          if (mounted) setState(() => _down = value);
                        },
                        onHover: (value) {
                          if (mounted) setState(() => _hover = value);
                        },
                        customBorder: border,
                        splashColor: stock.ink.withValues(alpha: .07),
                        highlightColor: stock.ink.withValues(alpha: .04),
                        hoverColor: stock.ink.withValues(alpha: .04),
                        child: content,
                      ),
                    )
                    : content,
          ),
          if (widget.pinned)
            Positioned(
              left: 0,
              right: 0,
              top:
                  widget.shape == PaperShape.tag
                      ? PaperBorder.holeDrop - PinHead.size / 2
                      : -PinHead.size / 2,
              child: const IgnorePointer(child: Center(child: PinHead())),
            ),
        ],
      ),
    );
  }
}

/// The marks printed or creased into a paper: the fold of a slip, the
/// perforation of a ticket, the eyelet of a tag and the flap of an envelope.
class _PaperDetails extends CustomPainter {
  const _PaperDetails({
    required this.shape,
    required this.stock,
    required this.stroke,
    required this.stub,
  });

  final PaperShape shape;
  final PaperStock stock;
  final double stroke;
  final double stub;

  @override
  void paint(Canvas canvas, Size size) {
    final line =
        Paint()
          ..color = stock.inkLine
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    switch (shape) {
      case PaperShape.slip:
        final f = math.min(PaperBorder.fold, size.width / 3);
        final x = size.width - f;
        final crease =
            Path()
              ..moveTo(x, 0)
              ..lineTo(x, f - 3)
              ..quadraticBezierTo(x, f, x + 3, f)
              ..lineTo(size.width, f);
        canvas.drawPath(
          Path.from(crease)..close(),
          Paint()..color = stock.fold,
        );
        canvas.drawPath(
          crease,
          Paint()
            ..color = stock.edge
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeJoin = StrokeJoin.round,
        );
      case PaperShape.ticket:
        final y = size.height - stub;
        final dot = Paint()..color = stock.inkLine;
        const inset = PaperBorder.notch + 6;
        final count = ((size.width - inset * 2) / 6).floor();
        if (count > 0) {
          final step = (size.width - inset * 2) / count;
          for (var i = 0; i <= count; i++) {
            canvas.drawCircle(Offset(inset + i * step, y), 1, dot);
          }
        }
      case PaperShape.tag:
        canvas.drawCircle(
          Offset(size.width / 2, PaperBorder.holeDrop),
          PaperBorder.hole + 4,
          line,
        );
      case PaperShape.envelope:
        final middle = size.width / 2;
        final depth = PaperBorder.flapDepth(size.width);
        final rise = 7 * depth / middle;
        canvas.drawPath(
          Path()
            ..moveTo(1, 2)
            ..lineTo(middle - 7, depth - rise)
            ..quadraticBezierTo(middle, depth, middle + 7, depth - rise)
            ..lineTo(size.width - 1, 2),
          line,
        );
      case PaperShape.sheet:
      case PaperShape.receipt:
      case PaperShape.folder:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _PaperDetails old) =>
      old.shape != shape ||
      old.stock != stock ||
      old.stroke != stroke ||
      old.stub != stub;
}

/// The coral head of the pin that holds a pinned page.
class PinHead extends StatelessWidget {
  const PinHead({super.key});

  static const size = 15.0;

  @override
  Widget build(BuildContext context) {
    final palette = PocketPalette.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: palette.coral,
        shape: BoxShape.circle,
        border: Border.all(
          color: palette.night ? palette.desk : palette.shade,
          width: palette.stroke,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.shade.withValues(alpha: palette.night ? .6 : 1),
            offset: const Offset(0, 2),
            blurRadius: 0,
          ),
        ],
      ),
      child: Align(
        alignment: const Alignment(-.35, -.4),
        child: Container(
          width: 3.5,
          height: 3.5,
          decoration: const BoxDecoration(
            color: Color(0x99FFFFFF),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// The wax seal on an envelope.
class WaxSeal extends StatelessWidget {
  const WaxSeal({super.key, this.icon, this.emoji, this.size = 36})
    : assert(icon != null || emoji != null);

  final IconData? icon;
  final String? emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = PocketPalette.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.coral,
        shape: BoxShape.circle,
        border:
            palette.night
                ? null
                : Border.all(color: palette.shade, width: palette.stroke),
        boxShadow: [
          if (!palette.night)
            BoxShadow(
              color: palette.shade,
              offset: const Offset(0, 2),
              blurRadius: 0,
            ),
        ],
      ),
      child:
          icon != null
              ? Icon(icon, size: size * .5, color: PocklinoColors.deepInk)
              : Text(
                emoji!,
                style: PocketType.emoji(
                  size * .5,
                  color: PocklinoColors.deepInk,
                ),
              ),
    );
  }
}

/// Opens a menu just below itself.
///
/// Unlike [PopupMenuButton], the open menu does not look back at the button.
/// The chosen action may therefore remove the button's page from the screen
/// while the menu is still closing.
class MenuButton<T> extends StatelessWidget {
  const MenuButton({
    super.key,
    required this.tooltip,
    required this.items,
    required this.onSelected,
    required this.child,
  });

  final String tooltip;
  final List<PopupMenuEntry<T>> Function() items;
  final ValueChanged<T> onSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Future<void> open() async {
      final button = context.findRenderObject()! as RenderBox;
      final overlay =
          Navigator.of(context).overlay!.context.findRenderObject()!
              as RenderBox;
      final below = Rect.fromPoints(
        button.localToGlobal(
          button.size.bottomLeft(Offset.zero),
          ancestor: overlay,
        ),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      );
      final choice = await showMenu<T>(
        context: context,
        position: RelativeRect.fromRect(below, Offset.zero & overlay.size),
        items: items(),
      );
      if (choice != null) onSelected(choice);
    }

    // A tooltip alone is not read out as a name on every platform.
    return Semantics(
      button: true,
      label: tooltip,
      onTap: open,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: open,
          child: child,
        ),
      ),
    );
  }
}

/// Leaves room for an envelope's flap and sets a seal on its tip.
class SealOnFlap extends StatelessWidget {
  const SealOnFlap({
    super.key,
    required this.seal,
    required this.sealSize,
    required this.inset,
    this.paperWidth,
  });

  final Widget seal;
  final double sealSize;

  /// The envelope's horizontal padding around this widget.
  final double inset;

  /// The envelope's width when the caller knows it. Measured otherwise,
  /// which a parent asking for intrinsic sizes cannot do.
  final double? paperWidth;

  Widget _place(double width) => Padding(
    padding: EdgeInsets.only(
      top: PaperBorder.flapDepth(width) - sealSize / 2 - 3,
    ),
    child: Center(child: seal),
  );

  @override
  Widget build(BuildContext context) =>
      paperWidth != null
          ? _place(paperWidth!)
          : LayoutBuilder(
            builder:
                (context, constraints) =>
                    _place(constraints.maxWidth + inset * 2),
          );
}

/// The grip at the top of a sheet.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 38,
      height: 4,
      decoration: BoxDecoration(
        color: PocketPalette.of(context).ink.withValues(alpha: .22),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

/// A tick box drawn in the ink of the paper it sits on.
class InkCheck extends StatelessWidget {
  const InkCheck({
    super.key,
    required this.done,
    required this.stock,
    this.size = 16,
  });

  final bool done;
  final PaperStock stock;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: done ? stock.ink : null,
      borderRadius: BorderRadius.circular(size * .28),
      border: Border.all(color: stock.ink, width: 1.6),
    ),
    child:
        done
            ? Icon(Icons.check_rounded, size: size * .72, color: stock.fill)
            : null,
  );
}

/// Small print: capitals in the monospace.
class MonoLabel extends StatelessWidget {
  const MonoLabel(
    this.text, {
    super.key,
    this.color,
    this.size = 10,
    this.weight = FontWeight.w500,
    this.textAlign,
  });

  final String text;
  final Color? color;
  final double size;
  final FontWeight weight;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: textAlign,
    style: PocketType.mono(
      size,
      color: color ?? PocketPalette.of(context).muted,
      weight: weight,
    ),
  );
}

/// A rubber stamp, as on the example pages.
class Stamp extends StatelessWidget {
  const Stamp(this.text, {super.key, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 1),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(3),
      border: Border.all(color: color, width: 1),
    ),
    child: Text(text, maxLines: 1, style: PocketType.mono(8.5, color: color)),
  );
}

/// The dashed rule that closes a receipt.
class DashedRule extends StatelessWidget {
  const DashedRule({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 1.4,
    width: double.infinity,
    child: CustomPaint(painter: _DashedRulePainter(color)),
  );
}

class _DashedRulePainter extends CustomPainter {
  const _DashedRulePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    canvas.drawPath(
      dashPath(
        Path()
          ..moveTo(0, y)
          ..lineTo(size.width, y),
        dash: 4,
        gap: 3,
      ),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.height,
    );
  }

  @override
  bool shouldRepaint(covariant _DashedRulePainter old) => old.color != color;
}

/// The outline of a paper that is not there yet.
class GhostPaper extends StatelessWidget {
  const GhostPaper({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 14,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = PocketPalette.of(context);
    final content = Padding(padding: padding, child: child);
    return CustomPaint(
      painter: _GhostPainter(
        color: palette.ink.withValues(alpha: palette.night ? .4 : .5),
        radius: radius,
        stroke: palette.stroke,
      ),
      child:
          onTap == null
              ? content
              : Semantics(
                button: true,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(radius),
                    child: content,
                  ),
                ),
              ),
    );
  }
}

class _GhostPainter extends CustomPainter {
  const _GhostPainter({
    required this.color,
    required this.radius,
    required this.stroke,
  });

  final Color color;
  final double radius;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      dashPath(
        Path()..addRRect(
          RRect.fromRectAndRadius(
            (Offset.zero & size).deflate(stroke / 2),
            Radius.circular(radius),
          ),
        ),
      ),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _GhostPainter old) =>
      old.color != color || old.radius != radius || old.stroke != stroke;
}

/// A [PaperShape] at icon size, for filters and labels.
class PaperGlyph extends StatelessWidget {
  const PaperGlyph(this.shape, {super.key, this.size = 16, this.color});

  final PaperShape shape;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _GlyphPainter(
        shape,
        color ?? IconTheme.of(context).color ?? PocketPalette.of(context).ink,
      ),
    ),
  );
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.shape, this.color);

  final PaperShape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 16, size.height / 16);
    final pen =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    final path = Path();
    switch (shape) {
      case PaperShape.sheet:
        path.addRRect(
          RRect.fromLTRBR(3, 2, 13, 14, const Radius.circular(1.5)),
        );
      case PaperShape.slip:
        path
          ..moveTo(3, 2)
          ..lineTo(9.5, 2)
          ..lineTo(13, 5.5)
          ..lineTo(13, 14)
          ..lineTo(3, 14)
          ..close()
          ..moveTo(9.5, 2)
          ..lineTo(9.5, 5.5)
          ..lineTo(13, 5.5);
      case PaperShape.receipt:
        path
          ..moveTo(3, 12.6)
          ..lineTo(3, 2)
          ..lineTo(13, 2)
          ..lineTo(13, 12.6)
          ..lineTo(11.33, 14.2)
          ..lineTo(9.67, 12.6)
          ..lineTo(8, 14.2)
          ..lineTo(6.33, 12.6)
          ..lineTo(4.67, 14.2)
          ..close()
          ..moveTo(5.6, 5.4)
          ..lineTo(10.4, 5.4)
          ..moveTo(5.6, 8.4)
          ..lineTo(10.4, 8.4);
      case PaperShape.ticket:
        const bite = Radius.circular(1.7);
        path
          ..moveTo(3, 2)
          ..lineTo(13, 2)
          ..lineTo(13, 8)
          ..arcToPoint(const Offset(13, 11.4), radius: bite, clockwise: false)
          ..lineTo(13, 14)
          ..lineTo(3, 14)
          ..lineTo(3, 11.4)
          ..arcToPoint(const Offset(3, 8), radius: bite, clockwise: false)
          ..close();
      case PaperShape.tag:
        path
          ..moveTo(5.8, 2)
          ..lineTo(10.2, 2)
          ..lineTo(13, 4.8)
          ..lineTo(13, 14)
          ..lineTo(3, 14)
          ..lineTo(3, 4.8)
          ..close()
          ..addOval(Rect.fromCircle(center: const Offset(8, 5.6), radius: 1.1));
      case PaperShape.envelope:
        path
          ..addRRect(
            RRect.fromLTRBR(2, 3.5, 14, 12.5, const Radius.circular(1.2)),
          )
          ..moveTo(2.4, 4.2)
          ..lineTo(8, 8.8)
          ..lineTo(13.6, 4.2);
      case PaperShape.folder:
        path
          ..moveTo(2, 4)
          ..lineTo(6.2, 4)
          ..lineTo(7.8, 5.8)
          ..lineTo(14, 5.8)
          ..lineTo(14, 13)
          ..lineTo(2, 13)
          ..close();
    }
    canvas.drawPath(path, pen);
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter old) =>
      old.shape != shape || old.color != color;
}
