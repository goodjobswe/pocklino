import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'design.dart';
import 'sharing.dart';
import 'store.dart';
import 'ui_helpers.dart';

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

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder:
        (context, _) => Scaffold(
          appBar: AppBar(title: const Text('Make yourself at home')),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 48),
                children: [
                  Center(
                    child: Column(
                      children: [
                        const PocketMark(size: 82),
                        const SizedBox(height: 10),
                        Text(
                          'pocklino',
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                        const SizedBox(height: 6),
                        const Text('A little space for your life.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 36),
                  const SmallLabel('A personal touch'),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: name,
                          maxLength: 60,
                          decoration: const InputDecoration(
                            labelText: 'Your first name (optional)',
                            helperText:
                                'Only stored here. This is not an account.',
                            counterText: '',
                          ),
                          onSubmitted:
                              (_) => run(
                                () => store.updateSettings(
                                  ownerName: name.text.trim(),
                                ),
                              ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton.filledTonal(
                        tooltip: 'Save your name',
                        onPressed:
                            busy
                                ? null
                                : () => run(
                                  () => store.updateSettings(
                                    ownerName: name.text.trim(),
                                  ),
                                ),
                        icon: const Icon(Icons.check_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  DropdownButtonFormField<String>(
                    value: store.themePreference,
                    decoration: const InputDecoration(
                      labelText: 'Appearance',
                      prefixIcon: Icon(Icons.palette_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'light',
                        child: Text('Warm paper'),
                      ),
                      DropdownMenuItem(
                        value: 'dark',
                        child: Text('Evening ink'),
                      ),
                      DropdownMenuItem(
                        value: 'system',
                        child: Text('Follow my device'),
                      ),
                    ],
                    onChanged:
                        busy
                            ? null
                            : (value) => run(
                              () =>
                                  store.updateSettings(themePreference: value),
                            ),
                  ),
                  const SizedBox(height: 34),
                  const SmallLabel('Yours to keep'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: PocklinoColors.mint,
                      borderRadius: BorderRadius.circular(19),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.phone_iphone_rounded,
                          color: PocklinoColors.ink,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'No account. No Pocklino server.',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: PocklinoColors.ink,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Your notes live on this device. Export a backup to keep a spare copy or move to a new device. '
                          'Uninstalling the app or clearing browser data can remove your notes.',
                          style: TextStyle(
                            color: PocklinoColors.ink,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.download_outlined),
                    title: const Text('Export a backup'),
                    subtitle: const Text(
                      'A portable file with your notes and collections.',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: busy ? null : backup,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.restore_page_outlined),
                    title: const Text('Restore a backup'),
                    subtitle: const Text(
                      'Add saved items without replacing your pocket.',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: busy ? null : restore,
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: Text(
                      'Backup and sharing files contain readable content. Store them somewhere you trust.',
                      style: TextStyle(fontSize: 12, height: 1.6),
                    ),
                  ),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: LinearProgressIndicator(),
                    ),
                  const SizedBox(height: 28),
                  const SmallLabel('A little inspiration'),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.auto_awesome_outlined),
                    title: const Text('Explore an example pocket'),
                    subtitle: const Text(
                      'Clearly labeled examples you can edit or remove.',
                    ),
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
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.cleaning_services_outlined),
                      title: const Text('Remove all examples'),
                      subtitle: const Text(
                        'Your own items stay exactly where they are.',
                      ),
                      onTap: busy ? null : () => run(store.clearExamples),
                    ),
                  const SizedBox(height: 28),
                  const SmallLabel('The small print'),
                  const SizedBox(height: 14),
                  const Text(
                    'Passing a note creates an independent copy. Later edits do not sync.\n\n'
                    '“Open later” is a gentle reveal using the receiving device’s clock, not secure time-lock encryption. '
                    'Titles and opening dates remain visible. Messages can be accessed early through clock changes or data inspection.\n\n'
                    'Pocklino adds no analytics or advertising. External links open in your browser. '
                    'If you choose a messaging or cloud app when exporting, that service handles your file.',
                    style: TextStyle(fontSize: 13, height: 1.7),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed:
                        () => showLicensePage(
                          context: context,
                          applicationName: 'Pocklino',
                          applicationVersion: '1.0.0',
                          applicationIcon: const Padding(
                            padding: EdgeInsets.all(16),
                            child: PocketMark(size: 70),
                          ),
                        ),
                    child: const Text('Open-source licenses'),
                  ),
                  const SizedBox(height: 10),
                  const Center(
                    child: Text(
                      'Made for the little things.  ·  Version 1.0.0',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
  );
}
