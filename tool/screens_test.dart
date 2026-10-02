// Renders the real screens to PNG files for a look at the interface without
// a device or a browser. Not part of the test suite.
//
//   flutter test tool/screens_test.dart
//
// Pictures go to build/screens, or to the folder named in SCREENS_DIR.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocklino/main.dart';
import 'package:pocklino/models.dart';
import 'package:pocklino/sharing.dart';
import 'package:pocklino/store.dart';
import 'package:pocklino/transfer.dart';
import 'package:sembast/sembast.dart'
    show disableSembastCooperator, enableSembastCooperator;
import 'package:sembast/sembast_memory.dart' show databaseFactoryMemory;

const phone = Size(390, 844);
const desktop = Size(1440, 1024);
final _frame = GlobalKey();
final _folder = Directory(
  Platform.environment['SCREENS_DIR'] ?? 'build/screens',
);
int _database = 0;

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final file in files) {
      final bytes = await File(file).readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  const fonts = 'assets/fonts';
  await family('Bricolage', ['$fonts/Bricolage-Bold.ttf']);
  await family('DMSans', [
    '$fonts/DMSans-Regular.ttf',
    '$fonts/DMSans-Medium.ttf',
    '$fonts/DMSans-SemiBold.ttf',
    '$fonts/DMSans-Bold.ttf',
  ]);
  await family('DMMono', [
    '$fonts/DMMono-Regular.ttf',
    '$fonts/DMMono-Medium.ttf',
  ]);
  await family('Lora', ['$fonts/Lora-SemiBold.ttf']);
  await family('Roboto', ['$fonts/Roboto-Variable.ttf']);
  await family('NotoEmoji', ['$fonts/NotoEmoji-Variable.ttf']);
  final flutter = Platform.environment['FLUTTER_ROOT']!;
  await family('MaterialIcons', [
    '$flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
}

/// Opens a pocket of the given size. Phones get a status bar and a home
/// indicator's worth of padding, as on a real device.
Future<AppStore> open(
  WidgetTester tester,
  Size size, {
  bool night = false,
  bool examples = true,
  String owner = '',
  List<PocketEntry> extra = const [],
}) async {
  const ratio = 2.0;
  tester.view.devicePixelRatio = ratio;
  tester.view.physicalSize = size * ratio;
  final handheld = size.width < 600;
  tester.view.padding = FakeViewPadding(
    top: handheld ? 44 * ratio : 0,
    bottom: handheld ? 18 * ratio : 0,
  );
  tester.view.viewPadding = tester.view.padding;
  addTearDown(tester.view.reset);
  final database = await databaseFactoryMemory.openDatabase(
    'screens-${_database++}',
  );
  final store = AppStore(database: database);
  await store.initialize();
  await store.updateSettings(
    themePreference: night ? 'dark' : 'light',
    ownerName: owner,
  );
  if (examples) {
    await store.addExamples();
    final dinner = store.entries.firstWhere(
      (entry) => entry.kind == EntryKind.checklist,
    );
    await store.toggleItem(dinner.id, dinner.items.first.id);
  }
  for (final entry in extra) {
    await store.upsert(entry);
  }
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    await database.close();
  });
  await tester.pumpWidget(
    RepaintBoundary(key: _frame, child: PocklinoApp(store: store)),
  );
  await tester.pumpAndSettle();
  return store;
}

Future<void> shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary =
        _frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(
      pixelRatio: tester.view.devicePixelRatio,
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    _folder.createSync(recursive: true);
    File(
      '${_folder.path}/$name.png',
    ).writeAsBytesSync(data!.buffer.asUint8List());
  });
}

// Save the actual displayed payload and bounds so the bundled decoder can
// independently check the QR pixels in these screenshots.
Future<void> qrShot(WidgetTester tester, String name, PocketEntry entry) async {
  await shot(tester, name);
  final qr = find.byKey(const ValueKey('pass-qr')).last;
  final bounds = tester.getRect(qr);
  final scale = tester.view.devicePixelRatio;
  final view = tester.widget<Semantics>(qr);
  final frame = RegExp(r'Frame (\d+) of').firstMatch(view.properties.label!);
  final index = frame == null ? 0 : int.parse(frame.group(1)!) - 1;
  File('${_folder.path}/$name.json').writeAsStringSync(
    jsonEncode({
      'data': TransferCodec.frames(entry)[index],
      'x': bounds.left * scale,
      'y': bounds.top * scale,
      'width': bounds.width * scale,
      'height': bounds.height * scale,
    }),
  );
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).first);
  await tester.pumpAndSettle();
}

Future<void> tapTip(WidgetTester tester, String tip) async {
  await tester.tap(find.byTooltip(tip).first);
  await tester.pumpAndSettle();
}

Future<void> openPage(WidgetTester tester, String title) async {
  final card = find.text(title).first;
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
  // The pocket bar floats over the end of the list: lift the card clear of it.
  final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  final y = tester.getCenter(card).dy;
  if (y > height - 140) {
    await tester.drag(
      find.byKey(const ValueKey('board')),
      Offset(0, height / 2 - y),
    );
    await tester.pumpAndSettle();
  }
  await tester.tap(card);
  await tester.pumpAndSettle();
}

PocketEntry _sealed() {
  final now = DateTime.now();
  return PocketEntry(
    id: 'sealed',
    title: 'Open on your birthday',
    body: 'A surprise that stays hidden.',
    kind: EntryKind.letter,
    createdAt: now,
    updatedAt: now.add(const Duration(seconds: 1)),
    unlockAt: now.add(const Duration(days: 12, hours: 5)),
    received: true,
    sender: 'Saga',
    collection: 'Little joys',
    colorIndex: 5,
  );
}

PocketEntry _watched() {
  final now = DateTime.now();
  return PocketEntry(
    id: 'watched',
    title: 'Paddington 2',
    body: 'Watched with the whole family. Marmalade for everyone.',
    kind: EntryKind.movie,
    createdAt: now,
    updatedAt: now.subtract(const Duration(minutes: 1)),
    collection: 'Watchlist',
    colorIndex: 1,
    watched: true,
  );
}

void main() {
  setUpAll(() async {
    disableSembastCooperator();
    await _loadFonts();
  });
  tearDownAll(enableSembastCooperator);

  for (final size in [phone, const Size(320, 568), desktop]) {
    for (final night in [false, true]) {
      final look = night ? 'night' : 'day';
      testWidgets('QR sharing ${size.width.toInt()}, $look', (tester) async {
        await open(tester, size, night: night, examples: false);
        final now = DateTime.utc(2026, 10, 2);
        final entry = PocketEntry(
          id: 'scan-check',
          title: 'A little memory',
          // Ordinary writing. A repeated phrase would compress into one code.
          body:
              'We took the early ferry out to the island and walked the long '
              'way round, past the lighthouse and the old boat sheds. Lunch '
              'was smoked fish on the rocks, then a swim that nobody had '
              'planned for. Remember to bring the blue thermos next time, '
              'and a second towel.\n\nThe last ferry back leaves at half past '
              'six, so we should be at the pier by six at the latest. Ask '
              'Maria about the cabin for the first week of July, and whether '
              'the bikes can stay in the shed over the winter. The key hangs '
              'behind the green door, third hook from the left.\n\nThings we '
              'said we would do before then: mend the tent zip, find the '
              'second paddle, print the tide table, and write down the name '
              'of the bakery by the harbour before we forget it again.',
          kind: EntryKind.note,
          createdAt: now,
          updatedAt: now,
        );
        showPassSheet(tester.element(find.byType(Scaffold).first), entry);
        await tester.pumpAndSettle();
        expect(find.byType(Slider).hitTestable(), findsOneWidget);
        await qrShot(tester, 'qr-${size.width.toInt()}-$look', entry);
        await tapTip(tester, 'Pause QR animation');
        await tapTip(tester, 'Next QR frame');
        await qrShot(tester, 'qr-${size.width.toInt()}-$look-next', entry);
        await tapTip(tester, 'Enlarge code');
        await qrShot(tester, 'qr-${size.width.toInt()}-$look-enlarged', entry);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('QR static enlargement', (tester) async {
    await open(tester, desktop, examples: false);
    final now = DateTime.utc(2026, 10, 2);
    final entry = PocketEntry(
      id: 'short',
      title: 'Milk',
      body: 'Remember milk.',
      kind: EntryKind.note,
      createdAt: now,
      updatedAt: now,
    );
    showPassSheet(tester.element(find.byType(Scaffold).first), entry);
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
    await qrShot(tester, 'qr-static', entry);
    await tapText(tester, 'Enlarge code');
    await qrShot(tester, 'qr-enlarged', entry);
    expect(tester.takeException(), isNull);
  });

  for (final night in [false, true]) {
    final look = night ? 'night' : 'day';

    testWidgets('home, $look', (tester) async {
      await open(tester, phone, night: night, extra: [_sealed(), _watched()]);
      await shot(tester, 'phone-$look-home');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -420));
      await shot(tester, 'phone-$look-home-scrolled');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await shot(tester, 'phone-$look-home-end');
    });

    testWidgets('wide home, $look', (tester) async {
      await open(
        tester,
        desktop,
        night: night,
        owner: 'Glenn',
        extra: [_sealed(), _watched()],
      );
      await shot(tester, 'wide-$look-home');
      await tapText(tester, 'Collections');
      await shot(tester, 'wide-$look-collections');
    });

    testWidgets('create and menus, $look', (tester) async {
      await open(tester, phone, night: night);
      await tapTip(tester, 'Create something');
      await shot(tester, 'phone-$look-create');
      await tester.tapAt(const Offset(195, 60));
      await tester.pumpAndSettle();
      await tapTip(tester, 'Item actions');
      await shot(tester, 'phone-$look-menu');
    });

    testWidgets('places, $look', (tester) async {
      await open(tester, phone, night: night, extra: [_sealed()]);
      await tapText(tester, 'Collections');
      await shot(tester, 'phone-$look-collections');
      await tapText(tester, 'Open later');
      await shot(tester, 'phone-$look-later');
      await tapText(tester, 'Archive');
      await shot(tester, 'phone-$look-archive');
    });

    testWidgets('empty, $look', (tester) async {
      await open(tester, phone, night: night, examples: false);
      await shot(tester, 'phone-$look-empty');
    });

    testWidgets('editors, $look', (tester) async {
      await open(tester, phone, night: night, extra: [_sealed(), _watched()]);
      for (final (name, title) in [
        ('note', 'A little space for your life'),
        ('checklist', 'Something good for dinner'),
        ('movie', 'The Grand Budapest Hotel'),
        ('trip', 'A weekend somewhere new'),
        ('letter', 'For your next little adventure'),
        ('sealed', 'Open on your birthday'),
      ]) {
        await openPage(tester, title);
        await shot(tester, 'phone-$look-edit-$name');
        if (name == 'letter' || name == 'movie' || name == 'trip') {
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -600),
          );
          await shot(tester, 'phone-$look-edit-$name-more');
        }
        await tapTip(tester, 'Save and go back');
      }
    });

    testWidgets('new note, $look', (tester) async {
      await open(tester, phone, night: night, examples: false);
      await tapTip(tester, 'Create something');
      await tapText(tester, 'Note');
      await shot(tester, 'phone-$look-edit-new');
    });

    testWidgets('wide editor, $look', (tester) async {
      await open(tester, desktop, night: night);
      await openPage(tester, 'Something good for dinner');
      await shot(tester, 'wide-$look-edit-checklist');
    });

    testWidgets('settings, $look', (tester) async {
      await open(tester, phone, night: night);
      await tapTip(tester, 'Settings');
      await shot(tester, 'phone-$look-settings');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -520));
      await shot(tester, 'phone-$look-settings-more');
    });

    testWidgets('dialogs and pickers, $look', (tester) async {
      await open(tester, phone, night: night);
      await tapText(tester, 'Collections');
      await tapText(tester, 'New collection');
      await shot(tester, 'phone-$look-dialog-collection');
      await tapText(tester, 'Cancel');
      await tapTip(tester, 'Collection actions');
      await tapText(tester, 'Remove collection');
      await shot(tester, 'phone-$look-dialog-remove');
      await tapText(tester, 'Keep it');
      await tapText(tester, 'Pocket');
      await openPage(tester, 'A weekend somewhere new');
      // The start date button; its label depends on the day the run is made.
      await tester.tap(find.byIcon(Icons.calendar_today_outlined));
      await tester.pumpAndSettle();
      await shot(tester, 'phone-$look-date-picker');
      await tapText(tester, 'Cancel');
      await tapTip(tester, 'Save and go back');
      await openPage(tester, 'For your next little adventure');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.schedule_rounded));
      await tester.pumpAndSettle();
      await tapText(tester, 'OK');
      await shot(tester, 'phone-$look-time-picker');
      await tapText(tester, 'Cancel');
      await tapTip(tester, 'Save and go back');
      await tester.tap(find.byTooltip('Item actions').last);
      await tester.pumpAndSettle();
      await tapText(tester, 'Delete');
      await shot(tester, 'phone-$look-snackbar');
    });

    testWidgets('large text on a small phone, $look', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.35;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester, const Size(360, 740), night: night);
      await shot(tester, 'small-$look-home-large-text');
      await tapTip(tester, 'Create something');
      await shot(tester, 'small-$look-create-large-text');
      await tapText(tester, 'Trip');
      await shot(tester, 'small-$look-edit-large-text');
      await tapTip(tester, 'Save and go back');
      await tapTip(tester, 'Settings');
      await shot(tester, 'small-$look-settings-large-text');
    });

    testWidgets('awkward windows, $look', (tester) async {
      await open(tester, const Size(1000, 460), night: night, owner: 'Glenn');
      await shot(tester, 'medium-$look-home');
      await tapText(tester, 'Collections');
      await shot(tester, 'medium-$look-collections');
    });

    testWidgets('smallest phone, $look', (tester) async {
      await open(tester, const Size(320, 568), night: night);
      await shot(tester, 'tiny-$look-home');
      await tapTip(tester, 'Create something');
      await shot(tester, 'tiny-$look-create');
      await tapText(tester, 'Letter');
      await shot(tester, 'tiny-$look-edit-letter');
    });

    testWidgets('pass and receive, $look', (tester) async {
      final store = await open(tester, phone, night: night);
      await tapTip(tester, 'Item actions');
      await tapText(tester, 'Pass a copy');
      await shot(tester, 'phone-$look-pass');
      await tapTip(tester, 'Close');
      await tapTip(tester, 'Receive a note');
      await shot(tester, 'phone-$look-receive');
      final trip = store.entries.firstWhere(
        (entry) => entry.kind == EntryKind.trip,
      );
      await tester.enterText(
        find.byType(TextField).last,
        TransferCodec.encode(trip),
      );
      await tester.ensureVisible(find.text('Preview pocket'));
      await tapText(tester, 'Preview pocket');
      await shot(tester, 'phone-$look-receive-preview');
    });
  }
}
