import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
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

class TestScannerPlatform extends MobileScannerPlatform {
  final captures = StreamController<BarcodeCapture?>.broadcast();
  final starts = <StartOptions>[];
  int stops = 0;
  int disposals = 0;
  Future<void>? nextStartGate;

  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Widget buildCameraView() => const ColoredBox(color: Colors.black);
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    starts.add(options);
    final gate = nextStartGate;
    nextStartGate = null;
    if (gate != null) await gate;
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.off,
      size: Size(640, 480),
      numberOfCameras: 1,
    );
  }

  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> dispose() async => disposals++;
}

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
    'speed changes preserve the frame and restart timing; paused stays paused',
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
      final frameCount = TransferCodec.frames(longEntry).length;
      expect(find.text('Frame 1 of $frameCount'), findsOneWidget);
      expect(find.text('1.0 s / frame'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 649));
      expect(find.text('Frame 1 of $frameCount'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('Frame 2 of $frameCount'), findsOneWidget);

      // Move the actual slider to its Slower endpoint.
      final slider = tester.getRect(find.byType(Slider));
      await tester.tapAt(Offset(slider.left + 24, slider.center.dy));
      await tester.pump();
      expect(find.text('2.0 s / frame'), findsOneWidget);
      expect(find.text('Frame 2 of $frameCount'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1999));
      expect(find.text('Frame 2 of $frameCount'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('Frame 3 of $frameCount'), findsOneWidget);

      await tester.tap(find.byTooltip('Pause QR animation'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Play QR animation'), findsOneWidget);
      await tester.tapAt(Offset(slider.right - 24, slider.center.dy));
      await tester.pump();
      expect(find.text('0.4 s / frame'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Frame 3 of $frameCount'), findsOneWidget);
      await tester.tap(find.byTooltip('Next QR frame'));
      await tester.pump();
      expect(find.text('Frame 4 of $frameCount'), findsOneWidget);
      await tester.tap(find.byTooltip('Play QR animation'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 399));
      expect(find.text('Frame 4 of $frameCount'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('Frame 5 of $frameCount'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Close'));
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Pass a little something'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final phone in [
    const Size(390, 844),
    const Size(360, 640),
    const Size(320, 568),
  ]) {
    testWidgets('QR and speed slider initially visible on $phone phone', (
      tester,
    ) async {
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final original = entry(body: List.filled(50, 'A little memory. ').join());
      await tester.pumpWidget(
        host((context) => () => showPassSheet(context, original)),
      );
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      final viewport = Offset.zero & phone;
      for (final finder in [
        find.byKey(const ValueKey('pass-qr')),
        find.byType(Slider),
        find.text('Slower'),
        find.text('Faster'),
      ]) {
        final rect = tester.getRect(finder);
        expect(viewport.contains(rect.topLeft), isTrue);
        expect(viewport.contains(rect.bottomRight), isTrue);
        expect(finder.hitTestable(), findsOneWidget);
      }
      expect(
        tester.getSize(find.byKey(const ValueKey('pass-qr'))).width,
        greaterThanOrEqualTo(220),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'a static code hides speed controls and can be enlarged and closed',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime(2026, 10, 1);
      final original = PocketEntry(
        id: 'a',
        title: 'Hi',
        body: 'A note.',
        kind: EntryKind.note,
        createdAt: now,
        updatedAt: now,
      );
      expect(TransferCodec.frames(original), hasLength(1));
      await tester.pumpWidget(
        host((context) => () => showPassSheet(context, original)),
      );
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsNothing);
      final originalSize = tester.getSize(
        find.byKey(const ValueKey('pass-qr')),
      );
      await tester.tap(find.text('Enlarge code'));
      await tester.pumpAndSettle();
      final enlarged = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Enlarged Pocklino pass code.',
      );
      expect(tester.getSize(enlarged).width, greaterThan(originalSize.width));
      await tester.tap(find.byTooltip('Close enlarged code'));
      await tester.pumpAndSettle();
      expect(enlarged, findsNothing);
      expect(find.text('Pass a little something'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'camera scans only QR, retains pieces across lifecycle and reopening, and disposes',
    (tester) async {
      final scanner = TestScannerPlatform();
      final previousPlatform = MobileScannerPlatform.instance;
      MobileScannerPlatform.instance = scanner;
      addTearDown(() async {
        MobileScannerPlatform.instance = previousPlatform;
        await scanner.captures.close();
      });
      final store =
          (await tester.runAsync(() async {
            final database = await databaseFactoryMemory.openDatabase(
              'scanner-${DateTime.now().microsecondsSinceEpoch}',
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
      expect(scanner.starts, isEmpty);
      await tester.tap(find.text('Open camera'));
      await tester.pumpAndSettle();
      expect(scanner.starts.single.formats, [BarcodeFormat.qrCode]);
      final frames = TransferCodec.frames(
        entry(body: List.filled(50, 'A little memory. ').join()),
      );
      void detect(String value) => scanner.captures.add(
        BarcodeCapture(
          barcodes: [Barcode(rawValue: value, format: BarcodeFormat.qrCode)],
        ),
      );
      detect(frames[1]);
      await tester.pumpAndSettle();
      expect(
        find.text('1 of ${frames.length} pieces received'),
        findsOneWidget,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(scanner.stops, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(scanner.starts, hasLength(2));
      detect(frames[1]);
      await tester.pumpAndSettle();
      expect(
        find.text('1 of ${frames.length} pieces received'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Close camera'));
      await tester.pumpAndSettle();
      expect(scanner.disposals, 1);
      await tester.tap(find.text('Open camera'));
      await tester.pumpAndSettle();
      expect(scanner.starts, hasLength(3));
      detect(frames[0]);
      await tester.pumpAndSettle();
      expect(
        find.text('2 of ${frames.length} pieces received'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(scanner.disposals, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reopening waits for pending camera startup and disposal', (
    tester,
  ) async {
    final scanner = TestScannerPlatform();
    final startup = Completer<void>();
    scanner.nextStartGate = startup.future;
    final previousPlatform = MobileScannerPlatform.instance;
    MobileScannerPlatform.instance = scanner;
    addTearDown(() async {
      MobileScannerPlatform.instance = previousPlatform;
      await scanner.captures.close();
    });
    final store =
        (await tester.runAsync(() async {
          final database = await databaseFactoryMemory.openDatabase(
            'scanner-startup-${DateTime.now().microsecondsSinceEpoch}',
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
    await tester.tap(find.text('Open camera'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(scanner.starts, hasLength(1));
    await tester.tap(find.byTooltip('Close camera'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open camera'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    // The earlier camera still owns pending startup. Do not start or dispose
    // the shared native camera until that startup resolves.
    expect(scanner.starts, hasLength(1));
    expect(scanner.disposals, 0);
    startup.complete();
    await tester.pumpAndSettle();
    expect(scanner.disposals, 1);
    expect(scanner.starts, hasLength(2));
    expect(find.byType(MobileScanner), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(scanner.disposals, 2);
    expect(tester.takeException(), isNull);
  });
}
