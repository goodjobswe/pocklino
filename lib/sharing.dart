import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'design.dart';
import 'models.dart';
import 'paper.dart';
import 'store.dart';
import 'transfer.dart';
import 'ui_helpers.dart';

const _maximumImportBytes = 256 * 1024;

/// Open the platform share sheet on mobile, or save a portable file elsewhere.
/// The file contains the content itself and needs no Pocklino account or server.
Future<void> shareTextFile(
  BuildContext context,
  String name,
  String content,
) async {
  final bytes = Uint8List.fromList(utf8.encode(content));
  final nativeMobile =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  if (nativeMobile) {
    final box = context.findRenderObject();
    final origin =
        box is RenderBox && box.hasSize
            ? box.localToGlobal(Offset.zero) & box.size
            : const Rect.fromLTWH(0, 0, 1, 1);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'application/octet-stream')],
        fileNameOverrides: [name],
        subject: 'A little something from Pocklino',
        sharePositionOrigin: origin,
      ),
    );
  } else {
    await FilePicker.saveFile(
      dialogTitle: 'Save your Pocklino file',
      fileName: name,
      bytes: bytes,
    );
  }
}

/// With a [store], the sheet opens at the sharing speed chosen last time and
/// remembers a new choice.
Future<void> showPassSheet(
  BuildContext context,
  PocketEntry entry, {
  AppStore? store,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => _PassSheet(entry: entry, store: store),
  );
}

Future<void> showReceiveSheet(BuildContext context, AppStore store) async {
  if (kIsWeb) {
    // Bundle the decoder with the application so scanning makes no CDN requests.
    MobileScannerPlatform.instance
      ..setWebBarcodeReader(WebBarcodeReader.zxingJs)
      ..setBarcodeLibraryScriptUrl('assets/zxing.min.js');
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => _ReceiveSheet(store: store),
  );
}

class _PassSheet extends StatefulWidget {
  const _PassSheet({required this.entry, this.store});
  final PocketEntry entry;
  final AppStore? store;

  @override
  State<_PassSheet> createState() => _PassSheetState();
}

class _PassSheetState extends State<_PassSheet> with WidgetsBindingObserver {
  List<String> _frames = const [];
  String? _token;
  String? _error;
  Timer? _timer;
  // A notifier, so the enlarged code keeps playing above this sheet.
  final _shown = ValueNotifier<int>(0);
  int get _frame => _shown.value;
  set _frame(int value) => _shown.value = value;
  // Drawing a code takes a moment, and at the faster speeds each one comes
  // round many times.
  final _images = <int, QrImage>{};
  late int _frameDurationMs =
      widget.store?.sharingSpeed ?? AppStore.defaultSharingSpeed;
  bool _playing = true;
  bool _saving = false;

  QrImage _imageAt(int frame) => _images[frame] ??= _passImage(_frames[frame]);

  /// "0.5", or "0.15" for the one speed that needs the second decimal.
  static String _seconds(int milliseconds) =>
      (milliseconds / 1000).toStringAsFixed(milliseconds % 100 == 0 ? 1 : 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      _token = TransferCodec.encode(widget.entry);
      _frames = TransferCodec.frames(widget.entry);
      _startAnimation();
    } on FormatException catch (error) {
      _error = error.message;
    } catch (_) {
      _error =
          'This pocket could not be prepared. Close this sheet and try again.';
    }
  }

  void _startAnimation() {
    _timer?.cancel();
    if (!_playing || _frames.length < 2) return;
    _timer = Timer.periodic(Duration(milliseconds: _frameDurationMs), (_) {
      if (mounted) setState(() => _frame = (_frame + 1) % _frames.length);
    });
  }

  void _setSpeed(double value) {
    setState(() => _frameDurationMs = AppStore.sharingSpeeds[value.round()]);
    _startAnimation();
  }

  /// Keep the choice for the next page that is passed. The whole notebook is
  /// written for this, so only once the slider is let go.
  void _keepSpeed(double value) {
    final store = widget.store;
    if (store == null) return;
    unawaited(
      store
          .updateSettings(sharingSpeed: AppStore.sharingSpeeds[value.round()])
          .catchError((Object _) {}),
    );
  }

  Future<void> _enlargeCode() => showDialog<void>(
    context: context,
    builder:
        (context) => Dialog.fullscreen(
          backgroundColor: Colors.white,
          child: SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    tooltip: 'Close enlarged code',
                    color: Colors.black,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder:
                        (context, constraints) => Center(
                          child: ValueListenableBuilder<int>(
                            valueListenable: _shown,
                            builder:
                                (context, frame, _) => _PassQr(
                                  image: _imageAt(frame),
                                  size: constraints.biggest.shortestSide,
                                  label:
                                      _frames.length == 1
                                          ? 'Enlarged Pocklino pass code.'
                                          : 'Enlarged Pocklino pass code. Frame ${frame + 1} of ${_frames.length}.',
                                ),
                          ),
                        ),
                  ),
                ),
                if (_frames.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ValueListenableBuilder<int>(
                      valueListenable: _shown,
                      builder:
                          (context, frame, _) => Text(
                            'Frame ${frame + 1} of ${_frames.length}',
                            style: PocketType.body(
                              14,
                              color: Colors.black,
                              weight: FontWeight.w600,
                            ),
                          ),
                    ),
                  ),
              ],
            ),
          ),
        ),
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startAnimation();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _shown.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: _token!));
      if (mounted) {
        toast(context, 'Pass code copied. Paste it in Pocklino to receive.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not copy. Try saving a file instead.');
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final safeName =
          widget.entry.title.replaceAll(RegExp(r'[^a-zA-Z0-9 _-]'), '').trim();
      await shareTextFile(
        context,
        '${safeName.isEmpty ? 'a-little-something' : safeName.substring(0, safeName.length.clamp(0, 60))}.pocklino',
        _token!,
      );
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error =
                  'The file could not be shared. Your pocket is safe; you can copy its code instead.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = PocketPalette.of(context);
    final stock = palette.stock(widget.entry.colorIndex);
    final opensLater = widget.entry.unlockAt?.isAfter(DateTime.now()) ?? false;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final compact = screenHeight < 720;
    // Tighten the surrounding paper on short phones so the code stays large
    // while its speed control remains within reach without scrolling. A tall
    // window gets a larger code: a monitor has far fewer pixels to the
    // module than a phone.
    final qrSize = (screenHeight * 0.92 - (compact ? 280 : 380)).clamp(
      220.0,
      440.0,
    );
    return _SheetFrame(
      title: 'Pass a little something',
      subtitle: 'From your pocket to theirs.',
      compact: compact,
      children: [
        Paper(
          shape: PaperShape.sheet,
          stock: stock,
          padding: EdgeInsets.fromLTRB(
            14,
            compact ? 8 : 12,
            12,
            compact ? 8 : 12,
          ),
          child: Row(
            children: [
              PaperGlyph(widget.entry.kind.shape, size: 22, color: stock.ink),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  widget.entry.title.isEmpty
                      ? 'A little something'
                      : widget.entry.title,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: PocketType.display(
                    compact ? 15 : 17,
                    color: stock.ink,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.north_east_rounded, size: 19, color: stock.ink),
            ],
          ),
        ),
        SizedBox(height: compact ? 12 : 16),
        if (_frames.isNotEmpty) ...[
          Center(
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: PocklinoColors.deepInk,
                  width: palette.stroke,
                ),
                boxShadow: [
                  if (!palette.night)
                    BoxShadow(
                      color: palette.shade,
                      offset: const Offset(0, 3),
                      blurRadius: 0,
                    ),
                ],
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return _PassQr(
                    image: _imageAt(_frame),
                    size: constraints.maxWidth.clamp(0.0, qrSize),
                    label:
                        'Pocklino pass code. Frame ${_frame + 1} of ${_frames.length}.',
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (_frames.length > 1) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Sharing speed',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PocketType.body(
                      14,
                      color: palette.ink,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_seconds(_frameDurationMs)} s / frame',
                  style: PocketType.body(12, color: palette.muted),
                ),
              ],
            ),
            Semantics(
              label: 'Sharing speed',
              child: Slider(
                // The steps are not even: they shorten toward the fast end.
                value:
                    AppStore.sharingSpeeds.indexOf(_frameDurationMs).toDouble(),
                max: AppStore.sharingSpeeds.length - 1,
                divisions: AppStore.sharingSpeeds.length - 1,
                label: '${_seconds(_frameDurationMs)} seconds per frame',
                semanticFormatterCallback:
                    (value) =>
                        '${_seconds(AppStore.sharingSpeeds[value.round()])} seconds per frame',
                onChanged: _setSpeed,
                onChangeEnd: _keepSpeed,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Slower',
                  style: PocketType.body(12, color: palette.muted),
                ),
                Text(
                  'Faster',
                  style: PocketType.body(12, color: palette.muted),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip:
                      _playing ? 'Pause QR animation' : 'Play QR animation',
                  onPressed: () {
                    setState(() => _playing = !_playing);
                    _startAnimation();
                  },
                  icon: Icon(
                    _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                ),
                Flexible(
                  child: Text(
                    'Frame ${_frame + 1} of ${_frames.length}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PocketType.body(
                      14,
                      color: palette.ink,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next QR frame',
                  onPressed: () {
                    setState(() {
                      _playing = false;
                      _frame = (_frame + 1) % _frames.length;
                    });
                    _timer?.cancel();
                  },
                  icon: const Icon(Icons.skip_next_rounded),
                ),
                IconButton(
                  tooltip: 'Enlarge code',
                  onPressed: _enlargeCode,
                  icon: const Icon(Icons.fullscreen_rounded),
                ),
              ],
            ),
            Text(
              'Having trouble scanning? Try slowing down.',
              textAlign: TextAlign.center,
              style: PocketType.body(14, color: palette.muted),
            ),
            const SizedBox(height: 6),
            Text(
              'Keep the other camera pointed at the code until all pieces arrive.',
              textAlign: TextAlign.center,
              style: PocketType.body(12, color: palette.muted),
            ),
          ] else ...[
            TextButton.icon(
              onPressed: _enlargeCode,
              icon: const Icon(Icons.fullscreen_rounded),
              label: const Text('Enlarge code'),
            ),
            Text(
              'Open Pocklino on the other device,\ntap Receive, then scan this code.',
              textAlign: TextAlign.center,
              style: PocketType.body(14, color: palette.muted, height: 1.5),
            ),
          ],
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _copy,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy code'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon:
                      _saving
                          ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.ios_share_rounded, size: 18),
                  label: Text(
                    kIsWeb ||
                            defaultTargetPlatform == TargetPlatform.windows ||
                            defaultTargetPlatform == TargetPlatform.linux ||
                            defaultTargetPlatform == TargetPlatform.macOS
                        ? 'Save file'
                        : 'Share file',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _Hint(
            icon: Icons.content_copy_rounded,
            text:
                'You are passing a copy. Later edits stay on each device. Anyone who scans this code can keep it.',
          ),
          if (opensLater) ...[
            const SizedBox(height: 10),
            _Hint(
              icon: Icons.schedule_rounded,
              text:
                  'Opens ${_dateTime(widget.entry.unlockAt!)}. This surprise follows the receiving device’s clock; it is not securely encrypted.',
            ),
          ],
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorNotice(message: _error!),
        ],
      ],
    );
  }
}

final _qrAlphanumeric = RegExp(r'^[0-9A-Z $%*+./:-]+$');

/// The smallest code that holds [data]. Sharing codes use only the QR
/// alphanumeric set, which takes 5.5 bits a character instead of 8. On a
/// screen the loss is blur, not damage, so level M and larger modules read
/// better than a higher level.
QrImage _passImage(String data) {
  final alphanumeric = _qrAlphanumeric.hasMatch(data);
  for (var version = 1; ; version++) {
    final code = QrCode(version, QrErrorCorrectLevel.M);
    if (alphanumeric) {
      code.addAlphaNumeric(data);
    } else {
      code.addData(data);
    }
    try {
      return QrImage(code);
    } on InputTooLongException {
      if (version == 40) rethrow;
    }
  }
}

/// Keep a four-module white quiet zone, independent of QR version or size.
class _PassQr extends StatelessWidget {
  const _PassQr({required this.image, required this.size, required this.label});

  final QrImage image;
  final double size;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey('pass-qr'),
      label: label,
      image: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: _QrMatrixPainter(
          qr: image,
          pixelRatio: MediaQuery.devicePixelRatioOf(context),
        ),
      ),
    );
  }
}

/// Paint the actual matrix on whole device pixels, including finder patterns.
/// This avoids independently rounded finder strokes and overlapping modules.
class _QrMatrixPainter extends CustomPainter {
  const _QrMatrixPainter({required this.qr, required this.pixelRatio});

  final QrImage qr;
  final double pixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = false;
    canvas.drawRect(Offset.zero & size, paint..color = Colors.white);
    final pixels = (size.shortestSide * pixelRatio).floor();
    final modulePixels = pixels ~/ (qr.moduleCount + 8);
    if (modulePixels < 1) return;
    final codePixels = qr.moduleCount * modulePixels;
    final insetPixels = ((pixels - codePixels) / 2).floor();
    paint.color = Colors.black;
    for (var row = 0; row < qr.moduleCount; row++) {
      for (var column = 0; column < qr.moduleCount; column++) {
        if (!qr.isDark(row, column)) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            (insetPixels + column * modulePixels) / pixelRatio,
            (insetPixels + row * modulePixels) / pixelRatio,
            modulePixels / pixelRatio,
            modulePixels / pixelRatio,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QrMatrixPainter oldDelegate) =>
      qr != oldDelegate.qr || pixelRatio != oldDelegate.pixelRatio;
}

/// Own the camera only while its preview is visible. Camera operations are
/// serialized so closing or backgrounding during startup still releases it.
class _QrCamera extends StatefulWidget {
  const _QrCamera({
    required this.onDetect,
    required this.errorBuilder,
    required this.placeholderBuilder,
  });

  final void Function(BarcodeCapture) onDetect;
  final Widget Function(BuildContext, MobileScannerException) errorBuilder;
  final WidgetBuilder placeholderBuilder;

  @override
  State<_QrCamera> createState() => _QrCameraState();
}

class _QrCameraState extends State<_QrCamera> with WidgetsBindingObserver {
  // The native scanner is shared. A newly opened preview must wait until an
  // earlier preview has finished starting and released the camera.
  static Future<void>? _cameraOperation;

  static void _enqueue(Future<void> Function() operation) {
    final previous = _cameraOperation ?? Future<void>.value();
    final next = previous.then((_) => operation());
    _cameraOperation = next;
    unawaited(
      next.then((_) {
        if (identical(_cameraOperation, next)) _cameraOperation = null;
      }),
    );
  }

  // The default looks at one camera picture every 250 ms. A moving code can
  // change ten times a second, so every picture of the camera is looked at:
  // 20 ms is shorter than the gap between two of them.
  final _controller = MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.qrCode],
    detectionTimeoutMs: 20,
  );
  bool _active = true;
  bool _disposed = false;
  MobileScannerException? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _active = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncCamera();
    });
  }

  void _syncCamera() {
    _enqueue(() async {
      if (_disposed) return;
      try {
        if (_active) {
          if (_error != null && mounted) setState(() => _error = null);
          await _controller.start();
        } else {
          await _controller.stop();
        }
      } on MobileScannerException catch (error) {
        if (mounted) setState(() => _error = error);
      } catch (_) {
        if (mounted) {
          setState(
            () =>
                _error = const MobileScannerException(
                  errorCode: MobileScannerErrorCode.genericError,
                ),
          );
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    // The permission prompt can itself send the app inactive. Queue the latest
    // state behind startup, rather than starting a second camera session.
    _syncCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposed = true;
    _enqueue(() async {
      try {
        await _controller.dispose();
      } catch (error) {
        // A native teardown failure must not block a future camera attempt or
        // escape from this already-disposed widget as an unhandled future.
        debugPrint('Could not release the QR camera: $error');
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _error != null
          ? widget.errorBuilder(context, _error!)
          : MobileScanner(
            controller: _controller,
            useAppLifecycleState: false,
            onDetect: widget.onDetect,
            errorBuilder: widget.errorBuilder,
            placeholderBuilder: widget.placeholderBuilder,
          );
}

class _ReceiveSheet extends StatefulWidget {
  const _ReceiveSheet({required this.store});
  final AppStore store;

  @override
  State<_ReceiveSheet> createState() => _ReceiveSheetState();
}

class _ReceiveSheetState extends State<_ReceiveSheet> {
  final _input = TextEditingController();
  final _assembler = TransferAssembler();
  PocketEntry? _preview;
  String? _error;
  String? _lastScan;
  bool _scanning = false;
  bool _busy = false;

  bool get _cameraSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _accept(String input) {
    if (_busy || _preview != null) return;
    final text = input.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Paste a Pocklino pass code first.');
      return;
    }
    if (text.length > _maximumImportBytes) {
      setState(
        () =>
            _error =
                'That code is too large. A single pocket can contain up to 64 KB of text.',
      );
      return;
    }
    try {
      final entry = _assembler.add(text);
      if (!mounted) return;
      setState(() {
        _error = null;
        if (entry != null) {
          _preview = entry;
          _scanning = false;
        }
      });
      if (entry != null) FocusScope.of(context).unfocus();
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error =
                  'This is not a readable Pocklino code. Try a fresh code or file.',
        );
      }
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_scanning || _preview != null || _busy || !mounted) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value == _lastScan) continue;
      _lastScan = value;
      _accept(value);
      if (_preview != null) break;
    }
  }

  void _reset() {
    _assembler.reset();
    setState(() {
      _preview = null;
      _error = null;
      _lastScan = null;
      _input.clear();
    });
  }

  Future<void> _pickFile() async {
    setState(() {
      _scanning = false;
      _busy = true;
      _error = null;
    });
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Receive a Pocklino pocket',
        type: FileType.custom,
        allowedExtensions: ['pocklino', 'json', 'txt'],
        allowMultiple: false,
        withData: false,
        withReadStream: true,
      );
      if (result == null || !mounted) return;
      final file = result.files.single;
      if (file.size > _maximumImportBytes) {
        throw const FormatException(
          'This file is too large for a single pocket. Restore a full backup from Settings.',
        );
      }
      final bytes = BytesBuilder(copy: false);
      final stream = file.readStream ?? file.xFile.openRead();
      await for (final chunk in stream) {
        bytes.add(chunk);
        if (bytes.length > _maximumImportBytes) {
          throw const FormatException(
            'This file is too large for a single pocket. Restore a full backup from Settings.',
          );
        }
      }
      final text = utf8.decode(bytes.takeBytes());
      if (!mounted) return;
      _assembler.reset();
      setState(() => _busy = false);
      _accept(text);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error =
                  'Could not read that file. Choose a .pocklino file, or paste its pass code below.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _keep() async {
    if (_preview == null || _busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.store.importEntry(_preview!);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('A little something, now in your pocket.'),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Your pocket could not be saved. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = PocketPalette.of(context);
    return _SheetFrame(
      title:
          _preview == null
              ? 'A little something for you'
              : 'Make a little room',
      subtitle:
          _preview == null
              ? 'A note, a plan, a lovely surprise.'
              : 'Preview it, then keep your own copy.',
      children: [
        if (_preview != null)
          _buildPreview(context, _preview!)
        else ...[
          if (_scanning) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 260,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _QrCamera(
                      onDetect: _onDetect,
                      errorBuilder:
                          (context, error) => Container(
                            color: palette.well,
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.no_photography_outlined,
                                  color: palette.ink,
                                  size: 32,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Camera unavailable',
                                  style: PocketType.display(
                                    19,
                                    color: palette.ink,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Allow camera access in your device or browser settings, then reopen the scanner. You can also choose a file or paste a code.',
                                  textAlign: TextAlign.center,
                                  style: PocketType.body(
                                    14,
                                    color: palette.muted,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      placeholderBuilder:
                          (context) => const ColoredBox(
                            color: PocklinoColors.deepInk,
                            child: Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                          ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton.filled(
                        tooltip: 'Close camera',
                        style: IconButton.styleFrom(
                          backgroundColor: PocklinoColors.oat,
                          foregroundColor: PocklinoColors.deepInk,
                        ),
                        onPressed: () => setState(() => _scanning = false),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Hold the code inside the camera view.\nFor moving codes, keep scanning until every piece arrives.',
              textAlign: TextAlign.center,
              style: PocketType.body(14, color: palette.muted, height: 1.5),
            ),
          ] else
            GhostPaper(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    Icon(
                      Icons.qr_code_scanner_rounded,
                      size: 48,
                      color: palette.ink,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Good things travel light.',
                      textAlign: TextAlign.center,
                      style: PocketType.display(20, color: palette.ink),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _cameraSupported
                          ? 'Point your camera at a Pocklino code.\nNo internet needed to pass a pocket.'
                          : 'Choose a Pocklino file or paste a pass code.\nYour pockets stay on this device.',
                      textAlign: TextAlign.center,
                      style: PocketType.body(
                        14,
                        color: palette.muted,
                        height: 1.5,
                      ),
                    ),
                    if (_cameraSupported) ...[
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed:
                            _busy
                                ? null
                                : () => setState(() {
                                  _scanning = true;
                                  _lastScan = null;
                                  _error = null;
                                }),
                        icon: const Icon(Icons.photo_camera_outlined, size: 18),
                        label: const Text('Open camera'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (_assembler.progress > 0 && _assembler.progress < 1) ...[
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _assembler.progress,
                minHeight: 7,
                backgroundColor: palette.hairline,
                color: palette.coral,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    '${_assembler.receivedFrames} of ${_assembler.totalFrames} pieces received',
                    style: PocketType.body(12, color: palette.muted),
                  ),
                ),
                TextButton(onPressed: _reset, child: const Text('Start over')),
              ],
            ),
          ],
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickFile,
            icon: const Icon(Icons.file_open_outlined, size: 18),
            label: Text(_busy ? 'Reading file…' : 'Choose a Pocklino file'),
          ),
          const SizedBox(height: 22),
          const Row(
            children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: MonoLabel('Or paste a code'),
              ),
              Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _input,
            minLines: 2,
            maxLines: 4,
            maxLength: _maximumImportBytes,
            autocorrect: false,
            enableSuggestions: false,
            style: PocketType.mono(
              12.5,
              color: palette.ink,
              weight: FontWeight.w400,
            ).copyWith(letterSpacing: 0, height: 1.45),
            decoration: InputDecoration(
              hintText: 'Paste your Pocklino pass code here…',
              hintStyle: PocketType.body(14, color: palette.muted),
              counterText: '',
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _busy ? null : () => _accept(_input.text),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Preview pocket'),
            ),
          ),
          const SizedBox(height: 10),
          const _Hint(
            icon: Icons.devices_rounded,
            text:
                'Nothing is uploaded. You choose what to keep, and every received pocket becomes your own copy.',
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 14),
          _ErrorNotice(
            message: _error!,
            onReset: _assembler.progress > 0 ? _reset : null,
          ),
        ],
      ],
    );
  }

  /// The page as it will lie in the pocket. A page that opens later shows
  /// only its sealed envelope.
  Widget _buildPreview(BuildContext context, PocketEntry entry) {
    final palette = PocketPalette.of(context);
    final stock = palette.stock(entry.colorIndex);
    final locked = entry.unlockAt?.isAfter(DateTime.now()) ?? false;
    final shape = locked ? PaperShape.envelope : entry.kind.shape;
    final envelope = shape == PaperShape.envelope;
    final quiet = PocketType.body(12.5, color: stock.inkMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Paper(
          shape: shape,
          stock: stock,
          padding: EdgeInsets.fromLTRB(20, envelope ? 0 : 20, 20, 20),
          stubHeight: 40,
          stub:
              shape == PaperShape.ticket
                  ? Align(
                    alignment: Alignment.centerLeft,
                    child: MonoLabel(
                      entry.watched ? 'Watched' : 'To watch',
                      color: stock.ink,
                    ),
                  )
                  : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (envelope) ...[
                SealOnFlap(
                  inset: 20,
                  sealSize: 46,
                  seal:
                      locked
                          ? const WaxSeal(icon: Icons.lock_rounded, size: 46)
                          : WaxSeal(emoji: entry.emoji, size: 46),
                ),
                const SizedBox(height: 16),
              ],
              Text(
                entry.title.isEmpty ? 'A little something' : entry.title,
                style: PocketType.display(24, color: stock.ink),
              ),
              const SizedBox(height: 10),
              if (locked) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_clock_outlined, size: 19, color: stock.ink),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ready to open ${_dateTime(entry.unlockAt!)}',
                        style: PocketType.body(
                          15,
                          color: stock.ink,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'A little anticipation is part of the gift. Keep this envelope safe until its moment arrives.',
                  style: PocketType.body(
                    14,
                    color: stock.inkMuted,
                    height: 1.55,
                  ),
                ),
              ] else ...[
                MonoLabel(
                  '${entry.kind.label}${entry.items.isNotEmpty ? ' · ${entry.items.length} items' : ''}',
                  color: stock.inkMuted,
                ),
                if (entry.body.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    entry.body,
                    maxLines: 7,
                    overflow: TextOverflow.ellipsis,
                    style: PocketType.body(15, color: stock.ink, height: 1.55),
                  ),
                ],
                if (entry.items.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  for (final item in entry.items.take(5))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: InkCheck(
                              done: item.done,
                              stock: stock,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item.text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: PocketType.body(
                                15,
                                color: stock.ink,
                                height: 1.35,
                              ).copyWith(
                                decoration:
                                    item.done
                                        ? TextDecoration.lineThrough
                                        : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (entry.items.length > 5)
                    Text(
                      '+ ${entry.items.length - 5} more items',
                      style: quiet,
                    ),
                ],
                if (entry.date != null) ...[
                  const SizedBox(height: 10),
                  Text(niceDate(entry.date!), style: quiet),
                ],
                if (entry.url.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.link_rounded, size: 17, color: stock.inkMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          entry.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: quiet,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        _Hint(
          icon: locked ? Icons.schedule_rounded : Icons.content_copy_rounded,
          text:
              locked
                  ? 'Open later uses this device’s clock. It is a thoughtful surprise, not secure encryption.'
                  : 'Keeping this creates a new copy. You can edit it freely; changes will not sync back to the sender.',
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _keep,
          icon:
              _busy
                  ? const SizedBox.square(
                    dimension: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.favorite_border_rounded, size: 18),
          label: Text(
            _busy
                ? 'Keeping it…'
                : locked
                ? 'Keep the envelope'
                : 'Keep in my pocket',
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : _reset,
          child: const Text('Try another code'),
        ),
      ],
    );
  }
}

/// A sheet of paper drawn up from the pocket.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.title,
    required this.subtitle,
    required this.children,
    this.compact = false,
  });
  final String title;
  final String subtitle;
  final List<Widget> children;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = PocketPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        decoration: BoxDecoration(
          color: palette.sheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            key: ValueKey(title),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SheetHandle(),
                SizedBox(height: compact ? 6 : 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style:
                                compact
                                    ? PocketType.display(19, color: palette.ink)
                                    : Theme.of(context).textTheme.headlineSmall,
                          ),
                          if (!compact) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: PocketType.body(14, color: palette.muted),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Close',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 10 : 20),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = PocketPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: palette.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: PocketType.body(12.5, color: palette.muted)),
        ),
      ],
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message, this.onReset});
  final String message;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: scheme.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: PocketType.body(
                      13.5,
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            if (onReset != null)
              TextButton(
                onPressed: onReset,
                child: const Text('Reset this transfer'),
              ),
          ],
        ),
      ),
    );
  }
}

String _dateTime(DateTime date) =>
    DateFormat('MMM d, yyyy · HH:mm').format(date.toLocal());
