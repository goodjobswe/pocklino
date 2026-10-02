import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'design.dart';
import 'paper.dart';
import 'sharing.dart';
import 'store.dart';
import 'ui_helpers.dart';

/// The version shown to people. A test keeps it in step with pubspec.yaml.
const appVersion = '1.0.0';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.store});
  final AppStore store;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final name = TextEditingController(text: widget.store.ownerName);
  bool busy = false;
  AppStore get store => widget.store;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } on FormatException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (_) {
      if (mounted) {
        toast(
          context,
          'That could not be completed. Your existing notes are safe.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> backup() => run(() async {
    final data = store.exportBackup();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    await shareTextFile(context, 'pocklino-backup-$stamp.json', data);
  });

  Future<void> restore() => run(() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      allowMultiple: false,
      withReadStream: true,
      withData: false,
    );
    if (result == null) return;
    final file = result.files.single;
    if (file.size > AppStore.maxBackupBytes) {
      throw const FormatException(
        'Choose a Pocklino backup smaller than 10 MB.',
      );
    }
    final bytes = <int>[];
    if (file.readStream != null) {
      await for (final chunk in file.readStream!) {
        if (bytes.length + chunk.length > AppStore.maxBackupBytes) {
          throw const FormatException('This backup is too large.');
        }
        bytes.addAll(chunk);
      }
    } else if (file.bytes != null) {
      bytes.addAll(file.bytes!);
    } else {
      throw const FormatException(
        'This file could not be read. Please choose it again.',
      );
    }
    final data = utf8.decode(bytes);
    if (!mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Bring these things into your pocket?'),
            content: const Text(
              'This adds items from the backup. Your existing notes stay safe; identical items are skipped '
              'and conflicting versions are kept as separate copies.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Restore backup'),
              ),
            ],
          ),
    );
    if (yes != true) return;
    final count = await store.restoreBackup(data);
    if (mounted) toast(context, '$count items brought into your pocket.');
  });

  Future<void> saveName() =>
      run(() => store.updateSettings(ownerName: name.text.trim()));

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      final palette = PocketPalette.of(context);
      final small = Theme.of(context).textTheme.bodySmall;
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 48),
              children: [
                Row(
                  children: [
                    PocketMark(size: 58, background: palette.night),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Wordmark(size: 29),
                          const SizedBox(height: 3),
                          Text('A little space for your life.', style: small),
                        ],
                      ),
                    ),
                  ],
                ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 14),
                    child: LinearProgressIndicator(),
                  ),
                const _Section('A personal touch'),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: name,
                        maxLength: 60,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Your first name (optional)',
                          helperText:
                              'Only stored here. This is not an account.',
                          helperMaxLines: 2,
                          counterText: '',
                        ),
                        onSubmitted: (_) => saveName(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: IconButton.filledTonal(
                        tooltip: 'Save your name',
                        style: IconButton.styleFrom(
                          backgroundColor: palette.butter,
                          foregroundColor: PocklinoColors.deepInk,
                        ),
                        onPressed: busy ? null : saveName,
                        icon: const Icon(Icons.check_rounded),
                      ),
                    ),
                  ],
                ),
                const _Section('Appearance'),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (index, (value, label))
                        in const [
                          ('light', 'Warm paper'),
                          ('dark', 'Evening ink'),
                          ('system', 'Follow my device'),
                        ].indexed) ...[
                      if (index > 0) const SizedBox(width: 10),
                      Expanded(
                        child: _LookTile(
                          value: value,
                          label: label,
                          selected: store.themePreference == value,
                          onTap:
                              busy
                                  ? null
                                  : () => run(
                                    () => store.updateSettings(
                                      themePreference: value,
                                    ),
                                  ),
                        ),
                      ),
                    ],
                  ],
                ),
                const _Section('Yours to keep'),
                Paper(
                  shape: PaperShape.slip,
                  stock: palette.stock(2),
                  padding: const EdgeInsets.fromLTRB(18, 16, 30, 18),
                  child: Builder(
                    builder: (context) {
                      final stock = palette.stock(2);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No account. No Pocklino server.',
                            style: PocketType.display(18, color: stock.ink),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            'Your notes live on this device. Export a backup to keep a spare copy or move to a new device. '
                            'Uninstalling the app or clearing browser data can remove your notes.',
                            style: PocketType.body(
                              14,
                              color: stock.inkSoft,
                              height: 1.55,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                _Panel(
                  children: [
                    _Action(
                      icon: Icons.download_outlined,
                      title: 'Export a backup',
                      subtitle:
                          'A portable file with your notes and collections.',
                      onTap: busy ? null : backup,
                    ),
                    _Action(
                      icon: Icons.restore_page_outlined,
                      title: 'Restore a backup',
                      subtitle:
                          'Add saved items without replacing your pocket.',
                      onTap: busy ? null : restore,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Backup and sharing files contain readable content. Store them somewhere you trust.',
                    style: small,
                  ),
                ),
                const _Section('A little inspiration'),
                _Panel(
                  children: [
                    _Action(
                      icon: Icons.auto_awesome_outlined,
                      title: 'Explore an example pocket',
                      subtitle:
                          'Clearly labeled examples you can edit or remove.',
                      onTap:
                          busy
                              ? null
                              : () => run(() async {
                                await store.addExamples();
                                if (context.mounted) {
                                  toast(
                                    context,
                                    'Example items are waiting in your pocket.',
                                  );
                                }
                              }),
                    ),
                    if (store.entries.any((e) => e.isExample))
                      _Action(
                        icon: Icons.cleaning_services_outlined,
                        title: 'Remove all examples',
                        subtitle: 'Your own items stay exactly where they are.',
                        onTap: busy ? null : () => run(store.clearExamples),
                      ),
                  ],
                ),
                const _Section('The small print'),
                Text(
                  'Passing a note creates an independent copy. Later edits do not sync.\n\n'
                  '“Open later” is a gentle reveal using the receiving device’s clock, not secure time-lock encryption. '
                  'Titles and opening dates remain visible. Messages can be accessed early through clock changes or data inspection.\n\n'
                  'Pocklino adds no analytics or advertising. External links open in your browser. '
                  'If you choose a messaging or cloud app when exporting, that service handles your file.',
                  style: PocketType.body(
                    13.5,
                    color: palette.muted,
                    height: 1.65,
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed:
                        () => showLicensePage(
                          context: context,
                          applicationName: 'Pocklino',
                          applicationVersion: appVersion,
                          applicationIcon: const Padding(
                            padding: EdgeInsets.all(16),
                            child: PocketMark(size: 70),
                          ),
                        ),
                    child: const Text('Open-source licenses'),
                  ),
                ),
                const SizedBox(height: 26),
                const Center(
                  child: MonoLabel(
                    'Made for the little things  ·  Version $appVersion',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 34, bottom: 12),
    child: MonoLabel(title, size: 11),
  );
}

/// A sheet of settings rows.
class _Panel extends StatelessWidget {
  const _Panel({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = PocketPalette.of(context);
    return Material(
      color: palette.sheet,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.line, width: palette.stroke),
      ),
      child: Column(
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0) const Divider(indent: 16, endIndent: 16),
            child,
          ],
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}

/// One of the three looks, shown as a small picture of the pocket.
class _LookTile extends StatelessWidget {
  const _LookTile({
    required this.value,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String value;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = PocketPalette.of(context);
    final border = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color:
            selected
                ? (palette.night ? palette.butter : palette.ink)
                : palette.ink.withValues(alpha: palette.night ? .3 : .38),
        width: selected ? 2.2 : palette.stroke,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            Material(
              shape: border,
              clipBehavior: Clip.antiAlias,
              color: Colors.transparent,
              child: AspectRatio(
                aspectRatio: 1.45,
                child: CustomPaint(painter: _LookPainter(value)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (selected)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: palette.ink,
                    ),
                  ),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: PocketType.body(
                      13,
                      color: palette.ink,
                      weight: selected ? FontWeight.w700 : FontWeight.w500,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _LookPainter extends CustomPainter {
  const _LookPainter(this.value);
  final String value;

  void _scene(Canvas canvas, Size size, PocketPalette palette) {
    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.desk);
    void paper(Rect rect, int stock) {
      final shape = RRect.fromRectAndRadius(rect, const Radius.circular(2.5));
      canvas.drawRRect(shape, Paint()..color = palette.stock(stock).fill);
      canvas.drawRRect(
        shape,
        Paint()
          ..color = palette.stock(stock).edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    paper(Rect.fromLTWH(w * .12, h * .16, w * .34, h * .5), 3);
    paper(Rect.fromLTWH(w * .54, h * .16, w * .34, h * .36), 1);
    paper(Rect.fromLTWH(w * .54, h * .6, w * .34, h * .3), 4);
    canvas.drawPath(
      Path()
        ..moveTo(0, h * .72)
        ..lineTo(w / 2, h * .8)
        ..lineTo(w, h * .72)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close(),
      Paint()..color = palette.pocket,
    );
    canvas.drawPath(
      dashPath(
        Path()
          ..moveTo(0, h * .72 + 4)
          ..lineTo(w / 2, h * .8 + 4)
          ..lineTo(w, h * .72 + 4),
        dash: 3,
        gap: 2.5,
      ),
      Paint()
        ..color = palette.stitch
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawCircle(
      Offset(w / 2, h * .76),
      5,
      Paint()..color = palette.coral,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (value != 'system') {
      _scene(
        canvas,
        size,
        value == 'dark' ? PocketPalette.evening : PocketPalette.day,
      );
      return;
    }
    // Half day, half evening, cut on the diagonal.
    final slant = size.width * .12;
    final day =
        Path()
          ..moveTo(0, 0)
          ..lineTo(size.width / 2 + slant, 0)
          ..lineTo(size.width / 2 - slant, size.height)
          ..lineTo(0, size.height)
          ..close();
    canvas.save();
    canvas.clipPath(day);
    _scene(canvas, size, PocketPalette.day);
    canvas.restore();
    canvas.save();
    canvas.clipPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        day,
      ),
    );
    _scene(canvas, size, PocketPalette.evening);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LookPainter old) => old.value != value;
}
