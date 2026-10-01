import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocklino/editor.dart';
import 'package:pocklino/main.dart';
import 'package:pocklino/models.dart';
import 'package:pocklino/store.dart';
import 'package:sembast/sembast.dart'
    show Database, disableSembastCooperator, enableSembastCooperator;
import 'package:sembast/sembast_memory.dart' show databaseFactoryMemory;

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
  await tester.binding.setSurfaceSize(size);
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
    await tester.binding.setSurfaceSize(null);
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
  await tester.tap(find.widgetWithText(ListTile, kind));
  await tester.pumpAndSettle();
  expect(find.byType(EntryEditor), findsOneWidget);
}

Future<void> _finish(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Save and go back'));
  await tester.pumpAndSettle();
  expect(find.byType(EntryEditor), findsNothing);
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

    final clear = find.text('Clear examples');
    await tester.scrollUntilVisible(
      clear,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(clear);
    await tester.pumpAndSettle();
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

      final search = _fieldWithHint('Find a little something…');
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

    final clear = find.text('Clear examples');
    await tester.scrollUntilVisible(
      clear,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(clear);
    await tester.pumpAndSettle();

    expect(pocket.store.entries, hasLength(1));
    expect(pocket.store.entries.single.title, 'My own little joys');
    expect(pocket.store.entries.single.isExample, isFalse);
  });

  testWidgets('The two-column example board fits a typical phone', (
    tester,
  ) async {
    final pocket = await _openPocket(tester, size: const Size(390, 844));
    await pocket.store.addExamples();
    await tester.pumpAndSettle();
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
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);

    for (final kind in ['Note', 'Checklist', 'Movie', 'Trip', 'Little note']) {
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
}
