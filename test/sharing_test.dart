import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocklino/design.dart';
import 'package:pocklino/models.dart';
import 'package:pocklino/sharing.dart';
import 'package:pocklino/store.dart';
import 'package:pocklino/transfer.dart';
import 'package:sembast/sembast_memory.dart';

PocketEntry entry({String body = 'Remember the popcorn', DateTime? unlockAt}) {
  final now = DateTime(2026, 10, 1);
  return PocketEntry(
    id: 'source-id',
    title: 'For your next adventure',
    body: body,
    kind: unlockAt == null ? EntryKind.note : EntryKind.letter,
    createdAt: now,
    updatedAt: now,
    unlockAt: unlockAt,
    url: 'https://example.com/surprise',
    items: const [CheckItem(id: 'hidden-item', text: 'A hidden gift idea')],
  );
}

Widget host(VoidCallback Function(BuildContext) action) => MaterialApp(
  theme: PocklinoTheme.light,
  home: Scaffold(
    body: Builder(
      builder:
          (context) => Center(
            child: FilledButton(
              onPressed: action(context),
              child: const Text('Start'),
            ),
          ),
    ),
  ),
);

void main() {
  testWidgets(
    'receive previews a future letter without disclosing its contents, then persists a new copy',
    (tester) async {
      final store =
          (await tester.runAsync(() async {
            final database = await databaseFactoryMemory.openDatabase(
              'sharing-${DateTime.now().microsecondsSinceEpoch}',
            );
            final result = AppStore(database: database);
            await result.initialize();
            addTearDown(() async {
              result.dispose();
              await database.close();
            });
            return result;
          }))!;
      final original = entry(
        body: 'The secret birthday message',
        unlockAt: DateTime(2099, 10, 1),
      );
      await tester.pumpWidget(
        host((context) => () => showReceiveSheet(context, store)),
      );
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      // Opening Receive must not open or request access to the camera.
      expect(find.text('Open camera'), findsOneWidget);
      expect(find.text('Camera unavailable'), findsNothing);
      await tester.enterText(
        find.byType(TextField),
        TransferCodec.encode(original),
      );
      await tester.ensureVisible(find.text('Preview pocket'));
      await tester.tap(find.text('Preview pocket'));
      await tester.pumpAndSettle();
      expect(find.text(original.title), findsOneWidget);
      expect(find.text(original.body), findsNothing);
      expect(find.text(original.url), findsNothing);
      expect(find.text(original.items.first.text), findsNothing);
      expect(find.text('Keep the envelope'), findsOneWidget);
      expect(store.entries, isEmpty);
      await tester.ensureVisible(find.text('Keep the envelope'));
      await tester.tap(find.text('Keep the envelope'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(store.entries, hasLength(1));
      expect(store.entries.single.id, isNot(original.id));
      expect(store.entries.single.isLocked, isTrue);
      expect(store.entries.single.body, original.body);
      expect(
        find.text('A little something, now in your pocket.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an invalid pass code cannot create a pocket and can be corrected',
    (tester) async {
      final store =
          (await tester.runAsync(() async {
            final database = await databaseFactoryMemory.openDatabase(
              'sharing-${DateTime.now().microsecondsSinceEpoch}',
            );
            final result = AppStore(database: database);
            await result.initialize();
            addTearDown(() async {
              result.dispose();
              await database.close();
            });
            return result;
          }))!;
      await tester.pumpWidget(
        host((context) => () => showReceiveSheet(context, store)),
      );
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'https://unrelated.example/',
      );
      await tester.ensureVisible(find.text('Preview pocket'));
      await tester.tap(find.text('Preview pocket'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Point the camera at a Pocklino sharing code.'),
        findsOneWidget,
      );
      expect(store.entries, isEmpty);
      await tester.enterText(
        find.byType(TextField),
        TransferCodec.encode(entry()),
      );
      await tester.ensureVisible(find.text('Preview pocket'));
      await tester.tap(find.text('Preview pocket'));
      await tester.pumpAndSettle();
      expect(find.text('Keep in my pocket'), findsOneWidget);
      expect(
        find.textContaining('Point the camera at a Pocklino sharing code.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'animated pass codes can be paused and dismissed on a narrow phone',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final longEntry = entry(
        body: List.filled(50, 'A little memory. ').join(),
      );
      await tester.pumpWidget(
        host((context) => () => showPassSheet(context, longEntry)),
      );
      await tester.tap(find.text('Start'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byTooltip('Pause QR animation'));
      await tester.tap(find.byTooltip('Pause QR animation'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Play QR animation'), findsOneWidget);
      expect(find.textContaining('Frame 1 of'), findsOneWidget);
      await tester.tap(find.byTooltip('Next QR frame'));
      await tester.pump();
      expect(find.textContaining('Frame 2 of'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Close'));
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Pass a little something'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
