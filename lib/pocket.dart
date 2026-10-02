import 'package:flutter/material.dart';

import 'design.dart';
import 'paper.dart';

/// The places in a pocket, in the order the navigation shows them.
const pocketPlaces = ['Pocket', 'Collections', 'Open later', 'Archive'];

Widget _placeIcon(int index, Color color, double size) => switch (index) {
  0 => PocketGlyph(size: size, color: color),
  1 => Icon(Icons.folder_outlined, size: size, color: color),
  2 => Icon(Icons.mail_outline_rounded, size: size, color: color),
  _ => Icon(Icons.inventory_2_outlined, size: size, color: color),
};

/// The pocket of the mark, drawn as an icon.
class PocketGlyph extends StatelessWidget {
  const PocketGlyph({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _PocketGlyphPainter(
        color ?? IconTheme.of(context).color ?? PocketPalette.of(context).ink,
      ),
    ),
  );
}

class _PocketGlyphPainter extends CustomPainter {
  const _PocketGlyphPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final pen =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(4, 6.5)
        ..lineTo(12, 9.5)
        ..lineTo(20, 6.5)
        ..lineTo(20, 15)
        ..arcToPoint(const Offset(15, 20), radius: const Radius.circular(5))
        ..lineTo(9, 20)
        ..arcToPoint(const Offset(4, 15), radius: const Radius.circular(5))
        ..close()
        ..moveTo(8, 14.4)
        ..quadraticBezierTo(12, 17, 16, 14.4),
      pen,
    );
  }

  @override
  bool shouldRepaint(covariant _PocketGlyphPainter old) => old.color != color;
}

/// The coral button of the mark. It makes room for something new.
class CreateButton extends StatefulWidget {
  const CreateButton({super.key, required this.onPressed, this.wide = false});

  final VoidCallback onPressed;

  /// A labelled bar for the side panel instead of the round button.
  final bool wide;

  static const size = 62.0;

  @override
  State<CreateButton> createState() => _CreateButtonState();
}

class _CreateButtonState extends State<CreateButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final palette = PocketPalette.of(context);
    final OutlinedBorder outline =
        widget.wide
            ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))
            : const CircleBorder();
    final edge = outline.copyWith(
      side:
          palette.night
              ? BorderSide.none
              : BorderSide(color: PocklinoColors.deepInk, width: 1.5),
    );
    final still = MediaQuery.disableAnimationsOf(context);
    // A tooltip alone is not read out as a name on every platform.
    return Semantics(
      button: true,
      label: 'Create something',
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: 'Create something',
        excludeFromSemantics: true,
        child: AnimatedContainer(
          duration: Duration(milliseconds: still ? 0 : 90),
          curve: Curves.easeOut,
          width: widget.wide ? null : CreateButton.size,
          height: widget.wide ? 48 : CreateButton.size,
          transform: Matrix4.translationValues(0, _down ? 3 : 0, 0),
          decoration: ShapeDecoration(
            shape: outline,
            shadows: [
              BoxShadow(
                color: const Color(0xFF111D28),
                offset: Offset(0, _down ? 1 : 4),
                blurRadius: 0,
              ),
            ],
          ),
          child: Material(
            color: palette.coral,
            shape: edge,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onPressed,
              onHighlightChanged: (value) {
                if (mounted) setState(() => _down = value);
              },
              customBorder: edge,
              splashColor: const Color(0x331D3145),
              child:
                  widget.wide
                      ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.add_rounded,
                            size: 22,
                            color: PocklinoColors.deepInk,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Create',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: PocketType.body(
                                15,
                                color: PocklinoColors.deepInk,
                                weight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      )
                      : const Icon(
                        Icons.add_rounded,
                        size: 32,
                        color: PocklinoColors.deepInk,
                      ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The front of the pocket along the bottom of a phone. Pages slide behind
/// its stitched edge, and the coral button sits in the notch.
class PocketBar extends StatelessWidget {
  const PocketBar({
    super.key,
    required this.index,
    required this.onSelect,
    required this.onCreate,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onCreate;

  /// How far the button stands above the corners of the pocket.
  static const rise = 22.0;

  /// How deep the edge dips towards the middle.
  static const dip = 16.0;

  /// The pocket itself, from its corners down.
  static const depth = 72.0;

  static const height = rise + depth;

  @override
  Widget build(BuildContext context) {
    final palette = PocketPalette.of(context);
    final inset = MediaQuery.viewPaddingOf(context).bottom;
    Widget place(int i) => Expanded(
      child: _BarPlace(
        index: i,
        selected: index == i,
        onTap: () => onSelect(i),
      ),
    );
    // The labels have no room to grow much; the icons carry them.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: SizedBox(
        height: height + inset,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              top: rise,
              child: ClipPath(
                clipper: const _PocketEdge(dip),
                child: ColoredBox(
                  color: palette.pocket,
                  child: CustomPaint(
                    painter: _EdgeStitch(palette.stitch, dip),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: rise + dip + 6,
              height: depth - dip - 8,
              child: Material(
                type: MaterialType.transparency,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    place(0),
                    place(1),
                    const SizedBox(width: CreateButton.size + 14),
                    place(2),
                    place(3),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Center(child: CreateButton(onPressed: onCreate)),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarPlace extends StatelessWidget {
  const _BarPlace({
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = PocketPalette.of(context);
    final color = selected ? palette.stitch : palette.onPocketMuted;
    return Semantics(
      button: true,
      selected: selected,
      child: InkResponse(
        onTap: onTap,
        radius: 34,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _placeIcon(index, color, 23),
            const SizedBox(height: 3),
            Text(
              pocketPlaces[index],
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: PocketType.body(
                10.5,
                color: color,
                weight: selected ? FontWeight.w700 : FontWeight.w600,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PocketEdge extends CustomClipper<Path> {
  const _PocketEdge(this.dip);
  final double dip;

  @override
  Path getClip(Size size) =>
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width / 2, dip)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();

  @override
  bool shouldReclip(covariant _PocketEdge old) => old.dip != dip;
}

class _EdgeStitch extends CustomPainter {
  const _EdgeStitch(this.color, this.dip);
  final Color color;
  final double dip;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      dashPath(
        Path()
          ..moveTo(-2, 8)
          ..lineTo(size.width / 2, dip + 8)
          ..lineTo(size.width + 2, 8),
      ),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _EdgeStitch old) =>
      old.color != color || old.dip != dip;
}

/// The front of the pocket down the side of a wide window.
class PocketSidebar extends StatelessWidget {
  const PocketSidebar({
    super.key,
    required this.index,
    required this.onSelect,
    required this.onCreate,
    required this.collections,
    required this.collection,
    required this.onCollection,
    required this.onReceive,
    required this.onSettings,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onCreate;
  final List<String> collections;

  /// The collection being looked at, if any.
  final String? collection;
  final ValueChanged<String> onCollection;
  final VoidCallback onReceive;
  final VoidCallback onSettings;

  static const width = 252.0;

  @override
  Widget build(BuildContext context) {
    final palette = PocketPalette.of(context);
    return SizedBox(
      width: width,
      child: ColoredBox(
        color: palette.pocket,
        child: CustomPaint(
          foregroundPainter: _SideStitch(palette.stitch),
          child: Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 22, 28, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // All but the last two rows scroll, so a short window
                  // loses nothing.
                  Expanded(
                    child: ListView(
                      primary: false,
                      padding: EdgeInsets.zero,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Row(
                            children: [
                              const PocketMark(size: 40),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Wordmark(
                                  size: 26,
                                  color: palette.onPocket,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 26),
                        CreateButton(onPressed: onCreate, wide: true),
                        const SizedBox(height: 24),
                        for (var i = 0; i < pocketPlaces.length; i++)
                          _SideRow(
                            leading: _placeIcon(
                              i,
                              index == i && collection == null
                                  ? palette.stitch
                                  : palette.onPocket,
                              21,
                            ),
                            label: pocketPlaces[i],
                            selected: index == i && collection == null,
                            onTap: () => onSelect(i),
                          ),
                        const SizedBox(height: 22),
                        Padding(
                          padding: const EdgeInsets.only(left: 12, bottom: 6),
                          child: MonoLabel(
                            'Collections',
                            color: palette.onPocketMuted,
                          ),
                        ),
                        for (var i = 0; i < collections.length; i++)
                          _SideRow(
                            leading: Padding(
                              padding: const EdgeInsets.all(5),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: PocketPalette.day.stock(i).fill,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: const SizedBox.square(dimension: 11),
                              ),
                            ),
                            label: collections[i],
                            selected: collection == collections[i],
                            quiet: true,
                            onTap: () => onCollection(collections[i]),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SideRow(
                    leading: Icon(
                      Icons.qr_code_scanner_rounded,
                      size: 21,
                      color: palette.onPocket,
                    ),
                    label: 'Receive a note',
                    onTap: onReceive,
                  ),
                  _SideRow(
                    leading: Icon(
                      Icons.tune_rounded,
                      size: 21,
                      color: palette.onPocket,
                    ),
                    label: 'Settings',
                    onTap: onSettings,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SideRow extends StatelessWidget {
  const _SideRow({
    required this.leading,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.quiet = false,
  });

  final Widget leading;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  /// Collections speak a little more softly than places.
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final palette = PocketPalette.of(context);
    final color =
        selected
            ? palette.stitch
            : quiet
            ? palette.onPocket.withValues(alpha: .82)
            : palette.onPocket;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color:
              selected
                  ? palette.onPocket.withValues(alpha: .09)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            hoverColor: palette.onPocket.withValues(alpha: .06),
            splashColor: palette.onPocket.withValues(alpha: .1),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: quiet ? 8 : 10,
              ),
              child: Row(
                children: [
                  SizedBox.square(dimension: 21, child: Center(child: leading)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PocketType.body(
                        quiet ? 14 : 14.5,
                        color: color,
                        weight: quiet ? FontWeight.w500 : FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SideStitch extends CustomPainter {
  const _SideStitch(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width - 9;
    canvas.drawPath(
      dashPath(
        Path()
          ..moveTo(x, -2)
          ..lineTo(x, size.height + 2),
      ),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SideStitch old) => old.color != color;
}
