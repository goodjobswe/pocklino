import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocklino/models.dart';
import 'package:pocklino/store.dart';
import 'package:sembast/sembast_memory.dart';

PocketEntry makeEntry({
  String id = 'one',
  String title = 'My page',
  EntryKind kind = EntryKind.note,
  String collection = 'Everyday',
  List<CheckItem> items = const [],
  DateTime? unlockAt,
  bool received = false,
}) => PocketEntry(
  id: id,
  title: title,
  kind: kind,
  collection: collection,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  items: items,
  unlockAt: unlockAt,
  received: received,
);

void main() {
  group('PocketEntry', () {
    test('copies list contents and exposes immutable lists', () {
      final source = [const CheckItem(id: 'item', text: 'Coffee')];
      final entry = makeEntry(items: source);
      source.clear();
      expect(entry.items, hasLength(1));
      expect(() => entry.items.clear(), throwsUnsupportedError);
    });

    test('locks only received notes before their reveal date', () {
      final future = DateTime.now().add(const Duration(days: 1));
      final created = makeEntry(unlockAt: future);
      expect(created.isLocked, isFalse);
      expect(created.copyWith(received: true).isLocked, isTrue);
      expect(
        created.copyWith(received: true, unlockAt: DateTime(2020)).isLocked,
        isFalse,
      );
      expect(
        created.copyWith(received: true, clearUnlockAt: true).isLocked,
        isFalse,
      );
    });

    test('roundtrips UTC dates, unicode, and checklist state', () {
      final entry = makeEntry(
        title: '旅行 🧳 café',
        items: [const CheckItem(id: 'one', text: '牛乳 🥛', done: true)],
      ).copyWith(
        body: 'A note\nwith two lines',
        date: DateTime.utc(2027, 2, 12),
        endDate: DateTime.utc(2027, 2, 14),
      );
      final restored = PocketEntry.fromJson(
        jsonDecode(jsonEncode(entry.toJson())),
      );
      expect(restored.toJson(), entry.toJson());
      expect(restored.completion, 1);
      expect(restored.copyWith(clearDate: true).date, isNull);
      expect(restored.copyWith(clearEndDate: true).endDate, isNull);
    });

    test('rejects duplicate items, bad dates, booleans, and unknown types', () {
      final good = makeEntry().toJson();
      for (final bad in [
        {...good, 'kind': 'future-kind'},
        {...good, 'createdAt': 'invalid'},
        {...good, 'pinned': 'true'},
        {
          ...good,
          'items': [
            {'id': 'a', 'text': 'one'},
            {'id': 'a', 'text': 'two'},
          ],
        },
      ]) {
        expect(() => PocketEntry.fromJson(bad), throwsFormatException);
      }
    });
  });

  group('AppStore', () {
    late Database database;
    late AppStore store;
    setUp(() async {
      database = await databaseFactoryMemory.openDatabase(
        'test-${DateTime.now().microsecondsSinceEpoch}',
      );
      store = AppStore(database: database);
      await store.initialize();
    });
    tearDown(() async {
      store.dispose();
      await database.close();
    });

    test(
      'starts empty, saves pages and settings across store initialization',
      () async {
        expect(store.entries, isEmpty);
        await store.upsert(makeEntry());
        await store.updateSettings(ownerName: 'Avery', themePreference: 'dark');
        final reopened = AppStore(database: database);
        await reopened.initialize();
        expect(reopened.entries.single.title, 'My page');
        expect(reopened.ownerName, 'Avery');
        expect(reopened.themePreference, 'dark');
        reopened.dispose();
      },
    );

    test(
      'serializes concurrent checklist edits without losing changes',
      () async {
        await store.upsert(
          makeEntry(
            items: [
              const CheckItem(id: 'a', text: 'Bread'),
              const CheckItem(id: 'b', text: 'Milk'),
            ],
          ),
        );
        await Future.wait([
          store.toggleItem('one', 'a'),
          store.toggleItem('one', 'b'),
        ]);
        expect(store.entries.single.completion, 1);
      },
    );

    test(
      'failed storage writes leave the visible notebook unchanged',
      () async {
        await store.upsert(makeEntry());
        await database.close();
        await expectLater(
          store.upsert(makeEntry(id: 'two')),
          throwsA(anything),
        );
        expect(store.entries, hasLength(1));
        expect(store.entries.single.id, 'one');
      },
    );

    test(
      'initialization can retry after a storage problem is resolved',
      () async {
        final record = stringMapStoreFactory.store('pocklino').record('state');
        await record.put(database, {'version': 999});
        final retrying = AppStore(database: database);
        await expectLater(retrying.initialize(), throwsFormatException);
        await record.put(database, {
          'version': 1,
          'entries': [makeEntry(title: 'Still here').toJson()],
          'collections': ['Everyday'],
          'ownerName': '',
          'themePreference': 'system',
        });
        await retrying.initialize();
        expect(retrying.entries.single.title, 'Still here');
        retrying.dispose();
      },
    );
    test('a failed edit does not poison subsequent writes', () async {
      await expectLater(
        store.updateSettings(themePreference: 'broken'),
        throwsFormatException,
      );
      await store.upsert(makeEntry());
      expect(store.entries, hasLength(1));
    });

    test('deleting a collection moves all its pages to Everyday', () async {
      await store.upsert(makeEntry(collection: 'Road trip'));
      expect(store.collections, contains('Road trip'));
      await store.deleteCollection('Road trip');
      expect(store.entries.single.collection, 'Everyday');
      expect(store.collections, isNot(contains('Road trip')));
      await expectLater(
        store.deleteCollection('Everyday'),
        throwsFormatException,
      );
    });

    test(
      'receiving creates a separate copy and retains the reveal date',
      () async {
        final future = DateTime.now().add(const Duration(days: 2));
        final entry = makeEntry(
          unlockAt: future,
        ).copyWith(isExample: true, pinned: true);
        await store.upsert(entry);
        final received = await store.importEntry(entry);
        expect(store.entries, hasLength(2));
        expect(received.id, isNot(entry.id));
        expect(received.isLocked, isTrue);
        expect(received.isExample, isFalse);
        expect(received.pinned, isFalse);
        await expectLater(store.duplicate(received), throwsFormatException);
      },
    );

    test(
      'backup merges non-destructively and duplicates ID conflicts',
      () async {
        final original = makeEntry();
        await store.upsert(original);
        final backup = store.exportBackup();
        expect(await store.restoreBackup(backup), 0);
        await store.upsert(original.copyWith(title: 'Edited locally'));
        expect(await store.restoreBackup(backup), 1);
        expect(
          store.entries.map((entry) => entry.title),
          containsAll(['My page', 'Edited locally']),
        );
        expect(store.entries.map((entry) => entry.id).toSet(), hasLength(2));
      },
    );

    test(
      'backup restores preferences and all fields into an empty notebook',
      () async {
        await store.upsert(makeEntry().copyWith(body: 'Remember café ☕'));
        await store.updateSettings(ownerName: 'Sam', themePreference: 'light');
        final backup = store.exportBackup();
        final secondDb = await databaseFactoryMemory.openDatabase('restore');
        final second = AppStore(database: secondDb);
        await second.initialize();
        expect(await second.restoreBackup(backup), 1);
        expect(second.entries.single.toJson(), store.entries.single.toJson());
        expect(second.ownerName, 'Sam');
        expect(second.themePreference, 'light');
        second.dispose();
        await secondDb.close();
      },
    );

    test(
      'invalid backup is all-or-nothing and preserves the existing data',
      () async {
        await store.upsert(makeEntry());
        final before = store.entries.single.toJson();
        final backup = jsonDecode(store.exportBackup()) as Map<String, dynamic>;
        backup['entries'] = [
          makeEntry(id: 'two').toJson(),
          {'id': 'bad'},
        ];
        await expectLater(
          store.restoreBackup(jsonEncode(backup)),
          throwsFormatException,
        );
        expect(store.entries, hasLength(1));
        expect(store.entries.single.toJson(), before);
        await expectLater(
          store.restoreBackup('x' * (AppStore.maxBackupBytes + 1)),
          throwsFormatException,
        );
      },
    );

    test(
      'examples are optional, idempotent, and can be removed separately',
      () async {
        await store.upsert(makeEntry());
        await store.addExamples();
        final count = store.entries.length;
        expect(count, greaterThan(1));
        await store.addExamples();
        expect(store.entries, hasLength(count));
        await store.clearExamples();
        expect(store.entries.single.id, 'one');
      },
    );

    test(
      'sample stationery retains exact Unicode through local storage and backup',
      () async {
        expect(makeEntry().emoji, '\u{1F4DD}');
        final withoutEmoji = makeEntry().toJson()..remove('emoji');
        expect(PocketEntry.fromJson(withoutEmoji).emoji, '\u{1F4DD}');
        await store.addExamples();
        final emojis = [
          '\u2728',
          '\u{1F951}',
          '\u{1F37F}',
          '\u{1F9F3}',
          '\u{1F48C}',
          '\u{1F33C}',
        ];
        expect(store.entries.map((entry) => entry.emoji), emojis);
        expect(store.entries.map((entry) => entry.colorIndex), [
          3,
          1,
          4,
          2,
          0,
          5,
        ]);
        expect(store.entries[0].body, contains('home \u2014 this space'));
        expect(store.entries[3].body, contains('tiny caf\u00e9,'));
        expect(store.entries[4].body, endsWith('\u{1F49B}'));
        final reopened = AppStore(database: database);
        await reopened.initialize();
        expect(reopened.entries.map((entry) => entry.emoji), emojis);
        final backup =
            jsonDecode(utf8.decode(utf8.encode(reopened.exportBackup())))
                as Map<String, dynamic>;
        final entries = backup['entries'] as List<dynamic>;
        expect(
          entries.map((entry) => (entry as Map<String, dynamic>)['emoji']),
          emojis,
        );
        expect(
          (entries[3] as Map<String, dynamic>)['body'],
          store.entries[3].body,
        );
        reopened.dispose();
      },
    );

    test(
      'invalid database state is rejected without replacing its contents',
      () async {
        final record = stringMapStoreFactory.store('pocklino').record('state');
        await record.put(database, {'version': 999, 'precious': 'untouched'});
        final damaged = AppStore(database: database);
        await expectLater(damaged.initialize(), throwsFormatException);
        expect((await record.get(database))!['precious'], 'untouched');
        damaged.dispose();
      },
    );
  });
}
