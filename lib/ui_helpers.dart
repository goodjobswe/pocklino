import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models.dart';
import 'paper.dart';

extension EntryPresentation on EntryKind {
  String get label => switch (this) {
    EntryKind.note => 'Note',
    EntryKind.checklist => 'Checklist',
    EntryKind.movie => 'Movie',
    EntryKind.trip => 'Trip',
    EntryKind.letter => 'Letter',
  };
  String get plural => switch (this) {
    EntryKind.note => 'Notes',
    EntryKind.checklist => 'Lists',
    EntryKind.movie => 'Movies',
    EntryKind.trip => 'Trips',
    EntryKind.letter => 'Letters',
  };
  String get hint => switch (this) {
    EntryKind.note => 'A thought worth keeping',
    EntryKind.checklist => 'One little thing at a time',
    EntryKind.movie => 'Your next movie night',
    EntryKind.trip => 'Somewhere to look forward to',
    EntryKind.letter => 'A little something for someone',
  };
  String get sticker => switch (this) {
    EntryKind.note => '\u{1f4dd}',
    EntryKind.checklist => '🥑',
    EntryKind.movie => '🍿',
    EntryKind.trip => '🌿',
    EntryKind.letter => '💌',
  };

  /// Every kind of page is a different thing from a pocket.
  PaperShape get shape => switch (this) {
    EntryKind.note => PaperShape.slip,
    EntryKind.checklist => PaperShape.receipt,
    EntryKind.movie => PaperShape.ticket,
    EntryKind.trip => PaperShape.tag,
    EntryKind.letter => PaperShape.envelope,
  };

  /// The paper a new page of this kind starts on.
  int get paper => switch (this) {
    EntryKind.note => 3,
    EntryKind.checklist => 1,
    EntryKind.movie => 4,
    EntryKind.trip => 2,
    EntryKind.letter => 0,
  };
}

String niceDate(DateTime value) =>
    DateFormat('MMM d, yyyy').format(value.toLocal());
String niceTime(DateTime value) =>
    DateFormat('MMM d · HH:mm').format(value.toLocal());

/// A date as printed on a tag: the year only when it is not this one.
String shortDate(DateTime value) {
  final local = value.toLocal();
  return DateFormat(
    local.year == DateTime.now().year ? 'MMM d' : 'MMM d yyyy',
  ).format(local);
}

/// Asks for one line of text. Returns null when the dialog is dismissed.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  required String action,
  String? hint,
  String initial = '',
  int maxLength = 500,
}) => showDialog<String>(
  context: context,
  builder:
      (_) => _TextPrompt(
        title: title,
        label: label,
        action: action,
        hint: hint,
        initial: initial,
        maxLength: maxLength,
      ),
);

/// Owns its controller, so the field stays valid while the dialog fades out.
class _TextPrompt extends StatefulWidget {
  const _TextPrompt({
    required this.title,
    required this.label,
    required this.action,
    required this.hint,
    required this.initial,
    required this.maxLength,
  });

  final String title;
  final String label;
  final String action;
  final String? hint;
  final String initial;
  final int maxLength;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  late final controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: controller,
      autofocus: true,
      maxLength: widget.maxLength,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
      ),
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text),
        child: Text(widget.action),
      ),
    ],
  );
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<void> openLink(BuildContext context, String value) async {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !['https', 'http'].contains(uri.scheme) ||
      uri.host.isEmpty) {
    toast(context, 'Add a complete https:// link first.');
    return;
  }
  try {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        context.mounted) {
      toast(context, 'This link could not be opened.');
    }
  } catch (_) {
    if (context.mounted) toast(context, 'This link could not be opened.');
  }
}
