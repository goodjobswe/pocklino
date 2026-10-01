import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'design.dart';
import 'models.dart';

extension EntryPresentation on EntryKind {
  String get label => switch (this) {
    EntryKind.note => 'Note',
    EntryKind.checklist => 'Checklist',
    EntryKind.movie => 'Movie',
    EntryKind.trip => 'Trip',
    EntryKind.letter => 'Little note',
  };
  String get plural => switch (this) {
    EntryKind.note => 'Notes',
    EntryKind.checklist => 'Lists',
    EntryKind.movie => 'Movies',
    EntryKind.trip => 'Trips',
    EntryKind.letter => 'Little notes',
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
  IconData get icon => switch (this) {
    EntryKind.note => Icons.edit_note_rounded,
    EntryKind.checklist => Icons.checklist_rounded,
    EntryKind.movie => Icons.movie_outlined,
    EntryKind.trip => Icons.explore_outlined,
    EntryKind.letter => Icons.mail_outline_rounded,
  };
}

Color entryColor(PocketEntry entry) =>
    PocklinoColors.cardColors[entry.colorIndex %
        PocklinoColors.cardColors.length];

String niceDate(DateTime value) =>
    DateFormat('MMM d, yyyy').format(value.toLocal());
String niceTime(DateTime value) =>
    DateFormat('MMM d · HH:mm').format(value.toLocal());

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

class SmallLabel extends StatelessWidget {
  const SmallLabel(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.6,
      color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}
