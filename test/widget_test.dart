import 'dart:math' as math;
import 'dart:ui' show SemanticsAction, SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocklino/editor.dart';
import 'package:pocklino/main.dart';
import 'package:pocklino/models.dart';
import 'package:pocklino/paper.dart';
import 'package:pocklino/pocket.dart';
import 'package:pocklino/store.dart';
import 'package:sembast/sembast.dart'
    show Database, disableSembastCooperator, enableSembastCooperator;
import 'package:sembast/sembast_memory.dart' show databaseFactoryMemory;

const _phone = Size(390, 844);

int _databaseNumber = 0;

class _PocketTest {
  const _PocketTest(this.store, this.database);
  final AppStore store;
  final Database database;
}

Future<_PocketTest> _openPocket(
  WidgetTester tester, {
  Size size = const Size(1100, 900),
  List<PocketEntry> entries = const [],
}) async {
  // The app picks its layout from MediaQuery, which follows the view and not
  // the surface size: 1100 wide is the side panel, a phone is the pocket bar.
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final database = await databaseFactoryMemory.openDatabase(
    'widget-pocket-${_databaseNumber++}',
  );
  final store = AppStore(database: database);
  await store.initialize();
  for (final entry in entries) {
    await store.upsert(entry);
  }
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    await database.close();
  });
  await tester.pumpWidget(PocklinoApp(store: store));
  await tester.pumpAndSettle();
  return _PocketTest(store, database);
}

Finder _fieldWithHint(String hint) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.hintText == hint,
);

Future<void> _create(WidgetTester tester, String kind) async {
  final floatingCreate = find.byTooltip('Create something');
  final create =
      floatingCreate.evaluate().isEmpty
          ? find.text('Create your first item')
          : floatingCreate;
  await tester.ensureVisible(create);
  await tester.pumpAndSettle();
  await tester.tap(create);
  await tester.pumpAndSettle();
  await tester.tap(find.text(kind));
  await tester.pumpAndSettle();
  expect(find.byType(EntryEditor), findsOneWidget);
}

Future<void> _finish(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Save and go back'));
  await tester.pumpAndSettle();
  expect(find.byType(EntryEditor), findsNothing);
}

/// The notice about examples is the last thing on the board. The pocket bar
/// floats over the end of the list, so scroll on past it before tapping.
Future<void> _clearExamples(WidgetTester tester) async {
  final clear = find.text('Clear examples');
  final board =
      find
          .descendant(
            of: find.byKey(const ValueKey('board')),
            matching: find.byType(Scrollable),
          )
          .first;
  await tester.scrollUntilVisible(clear, 400, scrollable: board);
  await tester.drag(board, const Offset(0, -300));
  await tester.pumpAndSettle();
  await tester.tap(clear);
  await tester.pumpAndSettle();
}

PocketEntry _page(String title, {String body = '', bool archived = false}) {
  final now = DateTime.now();
  return PocketEntry(
    id: title,
    title: title,
    body: body,
    kind: EntryKind.note,
    createdAt: now,
    updatedAt: now,
    archived: archived,
  );
}

/// Made-up words, enough of them for an animated sharing code.
String _longBody(int seed) {
  final random = math.Random(seed);
  const letters = 'abcdefghijklmnopqrstuvwxyz';
  return List.generate(
    500,
    (_) =>
        List.generate(
          2 + random.nextInt(7),
          (_) => letters[random.nextInt(letters.length)],
        ).join(),
  ).join(' ');
}

/// Lets the notices from earlier steps run out, so the next one shows.
Future<void> _clearNotices(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
  }
}

Future<void> _waitForAutosave(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
}

void main() {
  // Sembast normally yields to real timers during long operations. Widget
  // tests control a fake clock, so disable that scheduler for these tiny stores.
  setUpAll(disableSembastCooperator);
  tearDownAll(() => enableSembastCooperator());
  testWidgets('A new pocket is empty until examples are explicitly requested', (
    tester,
  ) async {
    final pocket = await _openPocket(tester);

    expect(pocket.store.entries, isEmpty);
    expect(find.text('Start with one little thing.'), findsOneWidget);
    expect(find.text('EXAMPLE'), findsNothing);

    final examples = find.text('Take a peek at an example pocket');
    await tester.ensureVisible(examples);
    await tester.tap(examples);
    await tester.pumpAndSettle();

    expect(pocket.store.entries, isNotEmpty);
    expect(pocket.store.entries.every((entry) => entry.isExample), isTrue);
    expect(find.text('EXAMPLE'), findsWidgets);
    expect(find.text('The Grand Budapest Hotel'), findsOneWidget);

    await _clearExamples(tester);
    expect(pocket.store.entries, isEmpty);
    expect(find.text('EXAMPLE'), findsNothing);
  });

  testWidgets(
    'A note created through the sheet autosaves and survives reload',
    (tester) async {
      final pocket = await _openPocket(tester);
      await _create(tester, 'Note');

      await tester.enterText(
        _fieldWithHint('Give this thought a home…'),
        'A place worth remembering',
      );
      await tester.enterText(
        _fieldWithHint('Let your thoughts land here.'),
        'The little cafe beside the water. Ask for a window seat.',
      );
      await _waitForAutosave(tester);

      expect(pocket.store.entries, hasLength(1));
      expect(pocket.store.entries.single.kind, EntryKind.note);
      expect(
        pocket.store.entries.single.body,
        'The little cafe beside the water. Ask for a window seat.',
      );
      await _finish(tester);
      expect(find.text('A place worth remembering'), findsOneWidget);

      final reloaded = AppStore(database: pocket.database);
      await reloaded.initialize();
      expect(reloaded.entries.single.title, 'A place worth remembering');
      expect(reloaded.entries.single.body, pocket.store.entries.single.body);
      reloaded.dispose();
    },
  );

  testWidgets('Leaving before the debounce finishes still saves the note', (
    tester,
  ) async {
    final pocket = await _openPocket(tester);
    await _create(tester, 'Note');
    await tester.enterText(
      _fieldWithHint('Give this thought a home…'),
      'A quick thought',
    );
    await _finish(tester);

    expect(pocket.store.entries.single.title, 'A quick thought');
    expect(find.text('A quick thought'), findsOneWidget);
  });

  testWidgets('Clearing a newly autosaved note persists the empty content', (
    tester,
  ) async {
    final pocket = await _openPocket(tester);
    await _create(tester, 'Note');
    final title = _fieldWithHint('Give this thought a home\u2026');
    final body = _fieldWithHint('Let your thoughts land here.');
    await tester.enterText(title, 'A temporary thought');
    await tester.enterText(body, 'This text should disappear when I clear it.');
    await _waitForAutosave(tester);
    expect(pocket.store.entries, hasLength(1));

    await tester.enterText(title, '');
    await tester.enterText(body, '');
    await _finish(tester);

    expect(pocket.store.entries, hasLength(1));
    expect(pocket.store.entries.single.title, 'Untitled note');
    expect(pocket.store.entries.single.body, isEmpty);
    final reloaded = AppStore(database: pocket.database);
    await reloaded.initialize();
    expect(reloaded.entries.single.title, 'Untitled note');
    expect(reloaded.entries.single.body, isEmpty);
    reloaded.dispose();
  });

  testWidgets('Checklist items can be added and checked from the home card', (
    tester,
  ) async {
    final pocket = await _openPocket(tester);
    await _create(tester, 'Checklist');
    await tester.enterText(_fieldWithHint('A list for…'), 'Sunday groceries');

    final itemField = _fieldWithHint('Add an item…');
    await tester.ensureVisible(itemField);
    await tester.enterText(itemField, 'Milk\nFresh bread');
    await tester.tap(find.byTooltip('Add item'));
    await _waitForAutosave(tester);

    expect(pocket.store.entries.single.items.map((item) => item.text), [
      'Milk',
      'Fresh bread',
    ]);
    expect(
      pocket.store.entries.single.items.every((item) => !item.done),
      isTrue,
    );
    await _finish(tester);

    await tester.ensureVisible(find.text('Milk'));
    await tester.tap(find.text('Milk'));
    await tester.pumpAndSettle();
    expect(pocket.store.entries.single.items.first.done, isTrue);
    expect(pocket.store.entries.single.items.last.done, isFalse);
    expect(find.byType(EntryEditor), findsNothing);

    final reloaded = AppStore(database: pocket.database);
    await reloaded.initialize();
    expect(reloaded.entries.single.items.first.done, isTrue);
    reloaded.dispose();
  });

  testWidgets(
    'Future received letters hide content in cards, search, and editor',
    (tester) async {
      const secret = 'The surprise is a weekend in Kyoto';
      final now = DateTime.now();
      final letter = PocketEntry(
        id: 'sealed-letter',
        title: 'For a special morning',
        body: secret,
        kind: EntryKind.letter,
        createdAt: now,
        updatedAt: now,
        unlockAt: now.add(const Duration(days: 7)),
        received: true,
        sender: 'A friend',
        items: const [
          CheckItem(id: 'hidden-item', text: 'Secret boarding passes'),
        ],
      );
      await _openPocket(tester, entries: [letter]);

      expect(find.text(letter.title), findsOneWidget);
      expect(find.textContaining(secret), findsNothing);
      expect(find.text('Secret boarding passes'), findsNothing);

      final search = _fieldWithHint('Search your pocket');
      await tester.enterText(search, 'Kyoto');
      await tester.pumpAndSettle();
      expect(find.text(letter.title), findsNothing);
      expect(
        find.text('Nothing matches this search. Try a different word.'),
        findsOneWidget,
      );

      await tester.enterText(search, 'Secret boarding passes');
      await tester.pumpAndSettle();
      expect(find.text(letter.title), findsNothing);

      await tester.enterText(search, 'special morning');
      await tester.pumpAndSettle();
      expect(find.text(letter.title), findsOneWidget);
      await tester.tap(find.text(letter.title));
      await tester.pumpAndSettle();

      expect(find.text('An envelope for later'), findsOneWidget);
      expect(find.textContaining(secret), findsNothing);
      expect(find.text('Secret boarding passes'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Pass'), findsNothing);
      expect(
        find.textContaining('A little something from A friend'),
        findsOneWidget,
      );
    },
  );

  testWidgets('An edited example survives clearing the remaining examples', (
    tester,
  ) async {
    final pocket = await _openPocket(tester);
    await pocket.store.addExamples();
    await tester.pumpAndSettle();
    final example = find.text('Tiny things, big smiles');
    await tester.ensureVisible(example);
    await tester.tap(example);
    await tester.pumpAndSettle();
    await tester.enterText(
      _fieldWithHint('Give this thought a home\u2026'),
      'My own little joys',
    );
    await _finish(tester);

    await _clearExamples(tester);

    expect(pocket.store.entries, hasLength(1));
    expect(pocket.store.entries.single.title, 'My own little joys');
    expect(pocket.store.entries.single.isExample, isFalse);
  });

  testWidgets('The two-column example board fits a typical phone', (
    tester,
  ) async {
    final pocket = await _openPocket(tester, size: _phone);
    await pocket.store.addExamples();
    await tester.pumpAndSettle();
    expect(find.byType(PocketBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Clear examples'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home, create sheet, and every editor fit a small phone', (
    tester,
  ) async {
    await _openPocket(tester, size: const Size(360, 800));
    expect(find.byType(PocketBar), findsOneWidget);
    expect(tester.takeException(), isNull);

    for (final kind in ['Note', 'Checklist', 'Movie', 'Trip', 'Letter']) {
      await _create(tester, kind);
      expect(
        tester.takeException(),
        isNull,
        reason: '$kind should fit a 360px screen',
      );
      await _finish(tester);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Deleting from a card menu removes the page and can be undone', (
    tester,
  ) async {
    final pocket = await _openPocket(tester, size: _phone);
    await _create(tester, 'Note');
    await tester.enterText(
      _fieldWithHint('Give this thought a home…'),
      'Soon gone',
    );
    await _finish(tester);
    expect(pocket.store.entries, hasLength(1));

    // The card leaves the screen while its menu is still closing.
    await tester.tap(find.byTooltip('Item actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(pocket.store.entries, isEmpty);
    expect(find.text('Start with one little thing.'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(pocket.store.entries.single.title, 'Soon gone');
    expect(find.text('Soon gone'), findsOneWidget);
  });

  testWidgets('Archived pages move to the Archive place and come back', (
    tester,
  ) async {
    final now = DateTime.now();
    final pocket = await _openPocket(
      tester,
      size: _phone,
      entries: [
        PocketEntry(
          id: 'kept',
          title: 'Keep for later',
          kind: EntryKind.note,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
    await tester.tap(find.byTooltip('Item actions'));
    await tester.pumpAndSettle();
    // The menu item, not the place of the same name in the pocket bar.
    await tester.tap(find.text('Archive').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(pocket.store.entries.single.archived, isTrue);
    expect(find.text('Keep for later'), findsNothing);

    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('Keep for later'), findsOneWidget);
    await tester.tap(find.byTooltip('Item actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bring back'));
    await tester.pumpAndSettle();
    expect(pocket.store.entries.single.archived, isFalse);
    expect(find.text('Nothing archived.'), findsOneWidget);
  });

  testWidgets('A page can be archived, brought back and deleted from its own '
      'menu, and the delete undone', (tester) async {
    final pocket = await _openPocket(
      tester,
      size: _phone,
      entries: [_page('Keep for later')],
    );
    await tester.tap(find.text('Keep for later'));
    await tester.pumpAndSettle();
    expect(find.byType(EntryEditor), findsOneWidget);
    await tester.tap(find.byTooltip('Page actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(EntryEditor), findsNothing);
    expect(pocket.store.entries.single.archived, isTrue);
    expect(find.text('Moved to the archive.'), findsOneWidget);
    expect(find.text('Keep for later'), findsNothing);
    await _clearNotices(tester);

    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep for later'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Page actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bring back'));
    await tester.pumpAndSettle();
    expect(find.byType(EntryEditor), findsNothing);
    expect(pocket.store.entries.single.archived, isFalse);
    expect(find.text('Back in your pocket.'), findsOneWidget);
    await _clearNotices(tester);

    // Delete with words that the autosave has not written yet.
    await tester.tap(find.text('Pocket'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep for later'));
    await tester.pumpAndSettle();
    await tester.enterText(
      _fieldWithHint('Let your thoughts land here.'),
      'Written a moment ago',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('Page actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(EntryEditor), findsNothing);
    expect(pocket.store.entries, isEmpty);
    // No late save brings the page back.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(pocket.store.entries, isEmpty);
    expect(find.text('“Keep for later” removed'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(pocket.store.entries.single.title, 'Keep for later');
    expect(pocket.store.entries.single.body, 'Written a moment ago');
    expect(find.text('Keep for later'), findsOneWidget);
  });

  testWidgets('Deleting a new page that was never saved just closes it', (
    tester,
  ) async {
    final pocket = await _openPocket(tester, size: _phone);
    await _create(tester, 'Note');
    await tester.tap(find.byTooltip('Page actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(EntryEditor), findsNothing);
    expect(pocket.store.entries, isEmpty);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('The archive can be emptied after a confirmation, and undone', (
    tester,
  ) async {
    final pocket = await _openPocket(
      tester,
      size: _phone,
      entries: [
        _page('Still here'),
        _page('Old one', archived: true),
        _page('Old two', archived: true),
      ],
    );
    expect(find.text('Empty the archive'), findsNothing);
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('Old one'), findsOneWidget);

    await tester.tap(find.text('Empty the archive'));
    await tester.pumpAndSettle();
    expect(find.text('Empty the archive?'), findsOneWidget);
    expect(find.textContaining('all 2 archived pages'), findsOneWidget);
    await tester.tap(find.text('Keep them'));
    await tester.pumpAndSettle();
    expect(pocket.store.entries, hasLength(3));

    await tester.tap(find.text('Empty the archive'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Empty the archive').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(pocket.store.entries.map((entry) => entry.title), ['Still here']);
    expect(find.text('Nothing archived.'), findsOneWidget);
    expect(find.text('Empty the archive'), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(pocket.store.entries, hasLength(3));
    expect(pocket.store.entries.where((entry) => entry.archived), hasLength(2));
    expect(find.text('Old two'), findsOneWidget);
  });

  testWidgets('Settings can clear the whole pocket after a confirmation, and '
      'undo it', (tester) async {
    final pocket = await _openPocket(
      tester,
      size: _phone,
      entries: [_page('In the pocket'), _page('Put away', archived: true)],
    );
    await pocket.store.addCollection('Summer');
    await pocket.store.updateSettings(ownerName: 'Glenn');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    final clear = find.text('Clear my pocket');
    await tester.scrollUntilVisible(
      clear,
      300,
      scrollable:
          find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
    );
    await tester.pumpAndSettle();

    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(find.text('Clear your whole pocket?'), findsOneWidget);
    expect(find.textContaining('all 2 pages'), findsOneWidget);
    await tester.tap(find.text('Keep everything'));
    await tester.pumpAndSettle();
    expect(pocket.store.entries, hasLength(2));

    await tester.tap(clear);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete everything'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(pocket.store.entries, isEmpty);
    expect(pocket.store.collections, AppStore.defaultCollections);
    expect(pocket.store.ownerName, 'Glenn');
    expect(find.text('Your pocket is already empty.'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(pocket.store.entries.map((entry) => entry.title), [
      'In the pocket',
      'Put away',
    ]);
    expect(pocket.store.entries.last.archived, isTrue);
    expect(pocket.store.collections, contains('Summer'));
  });

  testWidgets('The sharing speed chosen for one page is there for the next', (
    tester,
  ) async {
    final pocket = await _openPocket(
      tester,
      size: _phone,
      entries: [
        _page('First long page', body: _longBody(1)),
        _page('Second long page', body: _longBody(2)),
      ],
    );
    expect(pocket.store.sharingSpeed, AppStore.defaultSharingSpeed);
    await tester.tap(find.byTooltip('Item actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pass a copy'));
    await tester.pumpAndSettle();
    expect(find.text('0.5 s / frame'), findsOneWidget);
    // The Slower end: the fastest speed would never let the test settle.
    final slider = tester.getRect(find.byType(Slider));
    await tester.tapAt(Offset(slider.left + 24, slider.center.dy));
    await tester.pumpAndSettle();
    expect(find.text('2.0 s / frame'), findsOneWidget);
    expect(pocket.store.sharingSpeed, 2000);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    // From the other page's card.
    await tester.tap(find.byTooltip('Item actions').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pass a copy'));
    await tester.pumpAndSettle();
    expect(find.text('2.0 s / frame'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    // And from inside a page.
    await tester.tap(find.text('Second long page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pass'));
    await tester.pumpAndSettle();
    expect(find.text('2.0 s / frame'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A collection can be added after cancelling the dialog once', (
    tester,
  ) async {
    final pocket = await _openPocket(tester, size: _phone);
    await tester.tap(find.text('Collections'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New collection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(pocket.store.collections, hasLength(4));

    await tester.tap(find.text('New collection'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Weekend plans');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(pocket.store.collections, contains('Weekend plans'));
    expect(find.text('Weekend plans'), findsOneWidget);
  });

  testWidgets('A sealed page of any kind shows only its envelope on its card', (
    tester,
  ) async {
    const secret = 'Tickets are in the blue folder';
    final now = DateTime.now();
    final sealed = PocketEntry(
      id: 'sealed-list',
      title: 'Open at the airport',
      body: secret,
      kind: EntryKind.checklist,
      createdAt: now,
      updatedAt: now,
      unlockAt: now.add(const Duration(days: 3)),
      received: true,
      sender: 'Saga',
      items: const [CheckItem(id: 'one', text: 'Boarding passes')],
    );
    final pocket = await _openPocket(tester, size: _phone, entries: [sealed]);

    expect(find.text(sealed.title), findsOneWidget);
    expect(find.textContaining(secret), findsNothing);
    expect(find.text('Boarding passes'), findsNothing);
    expect(find.text('FROM SAGA'), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    expect(pocket.store.entries.single.items.single.done, isFalse);

    await tester.tap(find.text(sealed.title));
    await tester.pumpAndSettle();
    expect(find.text('An envelope for later'), findsOneWidget);
    expect(find.textContaining(secret), findsNothing);
    expect(find.text('Boarding passes'), findsNothing);
  });

  testWidgets('The empty pocket offers its own button for a first page', (
    tester,
  ) async {
    final pocket = await _openPocket(tester, size: _phone);
    await tester.tap(find.text('Create your first item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checklist'));
    await tester.pumpAndSettle();
    expect(find.byType(EntryEditor), findsOneWidget);
    await tester.enterText(_fieldWithHint('A list for…'), 'First things');
    await _finish(tester);
    expect(pocket.store.entries.single.title, 'First things');
    expect(pocket.store.entries.single.kind, EntryKind.checklist);
  });

  testWidgets('A wide window keeps the pocket down the side', (tester) async {
    final pocket = await _openPocket(tester, size: const Size(1280, 800));
    await pocket.store.addExamples();
    await tester.pumpAndSettle();
    expect(find.byType(PocketSidebar), findsOneWidget);
    expect(find.byType(PocketBar), findsNothing);
    expect(tester.takeException(), isNull);

    // A collection in the side panel opens that collection.
    await tester.tap(find.text('Watchlist').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('All collections'), findsOneWidget);
    expect(find.text('The Grand Budapest Hotel'), findsOneWidget);
    expect(find.text('Something good for dinner'), findsNothing);

    // The places and the two actions at its foot stay within reach.
    await tester.tap(find.text('Open later'));
    await tester.pumpAndSettle();
    expect(find.text('For your next little adventure'), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'.toUpperCase()), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A save that fails keeps the cursor in the field', (
    tester,
  ) async {
    await _openPocket(tester, size: _phone);
    await _create(tester, 'Movie');
    final link = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'IMDb or movie link',
    );
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pump();
    // A link beyond the 8000 characters a page may hold cannot be saved.
    await tester.enterText(link, 'https://example.com/${'a' * 8100}');
    await _waitForAutosave(tester);
    expect(find.text('These changes are not saved yet.'), findsOneWidget);
    final field = tester.widget<TextField>(link);
    expect(
      tester.testTextInput.hasAnyClients,
      isTrue,
      reason: 'the field must still be connected to the keyboard',
    );
    expect(field.controller!.text, startsWith('https://example.com/'));

    await tester.enterText(link, 'https://example.com/film');
    await _waitForAutosave(tester);
    expect(find.text('These changes are not saved yet.'), findsNothing);
    await _finish(tester);
  });

  testWidgets('Papers that act as one control are announced as buttons', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _openPocket(tester, size: _phone);
    await tester.tap(find.byTooltip('Create something'));
    await tester.pumpAndSettle();
    for (final kind in ['Note', 'Checklist', 'Movie', 'Trip', 'Letter']) {
      final paper = find.ancestor(
        of: find.text(kind),
        matching: find.byType(Paper),
      );
      expect(paper, findsOneWidget);
      final node = tester.getSemantics(find.text(kind));
      expect(
        node.hasFlag(SemanticsFlag.isButton),
        isTrue,
        reason: '$kind should be announced as a button',
      );
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    }
    handle.dispose();
  });
}
