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
import 'store.dart';
import 'transfer.dart';

const _ink = Color(0xFF243C53);
const _paper = Color(0xFFF8F6EF);
const _coral = Color(0xFFDD7C65);
const _muted = Color(0xFF687581);
const _mint = Color(0xFFE4EEE4);
const _line = Color(0xFFE3E1D8);
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

Future<void> showPassSheet(BuildContext context, PocketEntry entry) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => _PassSheet(entry: entry),
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
  const _PassSheet({required this.entry});
  final PocketEntry entry;

  @override
  State<_PassSheet> createState() => _PassSheetState();
}

class _PassSheetState extends State<_PassSheet> with WidgetsBindingObserver {
  List<String> _frames = const [];
  String? _token;
  String? _error;
  Timer? _timer;
  int _frame = 0;
  bool _playing = true;
  bool _saving = false;

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
    _timer = Timer.periodic(const Duration(milliseconds: 650), (_) {
      if (mounted) setState(() => _frame = (_frame + 1) % _frames.length);
    });
  }

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
    super.dispose();
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: _token!));
      if (mounted) {
        _toast(context, 'Pass code copied. Paste it in Pocklino to receive.');
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
    final opensLater = widget.entry.unlockAt?.isAfter(DateTime.now()) ?? false;
    return _SheetFrame(
      title: 'Pass a little something',
      subtitle: 'From your pocket to theirs.',
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _mint,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Text(
                widget.entry.emoji,
                style: const TextStyle(fontFamily: 'NotoEmoji', fontSize: 27),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.entry.title.isEmpty
                      ? 'A little something'
                      : widget.entry.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    color: _ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.north_east_rounded, size: 20, color: _ink),
            ],
          ),
        ),
        const SizedBox(height: 22),
        if (_frames.isNotEmpty) ...[
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _line),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x09243C53),
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = (constraints.maxWidth - 8).clamp(120.0, 300.0);
                  return Semantics(
                    label:
                        'Pocklino pass code. Frame ${_frame + 1} of ${_frames.length}.',
                    image: true,
                    child: QrImageView(
                      data: _frames[_frame],
                      size: size,
                      padding: const EdgeInsets.all(16),
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: _ink,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: _ink,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_frames.length > 1) ...[
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
                Text(
                  'Frame ${_frame + 1} of ${_frames.length}',
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w600,
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
              ],
            ),
            const Text(
              'Keep the other camera pointed at the code until all pieces arrive.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, height: 1.45),
            ),
          ] else
            const Text(
              'Open Pocklino on the other device,\ntap Receive, then scan this code.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, height: 1.5),
            ),
          const SizedBox(height: 24),
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
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                height: 260,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      onDetect: _onDetect,
                      errorBuilder:
                          (context, error) => Container(
                            color: _mint,
                            padding: const EdgeInsets.all(28),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.no_photography_outlined,
                                  color: _ink,
                                  size: 32,
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'Camera unavailable',
                                  style: TextStyle(
                                    color: _ink,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Allow camera access in your device or browser settings, then reopen the scanner. You can also choose a file or paste a code.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: _muted, height: 1.5),
                                ),
                              ],
                            ),
                          ),
                      placeholderBuilder:
                          (context) => const ColoredBox(
                            color: _ink,
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
                          backgroundColor: _paper,
                          foregroundColor: _ink,
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
            const Text(
              'Hold the code inside the camera view.\nFor moving codes, keep scanning until every piece arrives.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, height: 1.5),
            ),
          ] else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
              decoration: BoxDecoration(
                color: _mint,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.qr_code_scanner_rounded,
                    size: 54,
                    color: _ink,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Good things travel light.',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _cameraSupported
                        ? 'Point your camera at a Pocklino code.\nNo internet needed to pass a pocket.'
                        : 'Choose a Pocklino file or paste a pass code.\nYour pockets stay on this device.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _muted, height: 1.5),
                  ),
                  if (_cameraSupported) ...[
                    const SizedBox(height: 20),
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
          if (_assembler.progress > 0 && _assembler.progress < 1) ...[
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _assembler.progress,
                minHeight: 7,
                backgroundColor: _line,
                color: _coral,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(_assembler.progress * 100).round()}% of your pocket received',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                TextButton(onPressed: _reset, child: const Text('Start over')),
              ],
            ),
          ],
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickFile,
            icon: const Icon(Icons.file_open_outlined, size: 18),
            label: Text(_busy ? 'Reading file…' : 'Choose a Pocklino file'),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              const Expanded(child: Divider(color: _line)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'OR PASTE A CODE',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _muted,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const Expanded(child: Divider(color: _line)),
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
            style: const TextStyle(fontSize: 13, color: _ink),
            decoration: InputDecoration(
              hintText: 'Paste your Pocklino pass code here…',
              hintStyle: const TextStyle(color: _muted),
              filled: true,
              fillColor: Colors.white,
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _line),
              ),
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

  Widget _buildPreview(BuildContext context, PocketEntry entry) {
    final locked = entry.unlockAt?.isAfter(DateTime.now()) ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: locked ? const Color(0xFFF4E2D8) : _mint,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                locked ? '💌' : entry.emoji,
                style: const TextStyle(fontFamily: 'NotoEmoji', fontSize: 38),
              ),
              const SizedBox(height: 16),
              Text(
                entry.title.isEmpty ? 'A little something' : entry.title,
                style: const TextStyle(
                  fontSize: 25,
                  color: _ink,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              if (locked) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.lock_clock_outlined,
                      size: 19,
                      color: _ink,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ready to open ${_dateTime(entry.unlockAt!)}',
                        style: const TextStyle(color: _ink, height: 1.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'A little anticipation is part of the gift. Keep this envelope safe until its moment arrives.',
                  style: TextStyle(color: _muted, height: 1.55),
                ),
              ] else ...[
                Text(
                  '${_kindLabel(entry.kind.name)}${entry.items.isNotEmpty ? ' · ${entry.items.length} items' : ''}',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                if (entry.body.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    entry.body,
                    maxLines: 7,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _ink, height: 1.6),
                  ),
                ],
                if (entry.items.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  ...entry.items
                      .take(5)
                      .map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                item.done
                                    ? Icons.check_circle_outline_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                size: 18,
                                color: _muted,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  item.text,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _ink,
                                    height: 1.4,
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
                      ),
                  if (entry.items.length > 5)
                    Text(
                      '+ ${entry.items.length - 5} more items',
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                ],
                if (entry.date != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    DateFormat('MMM d, yyyy').format(entry.date!.toLocal()),
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
                if (entry.url.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.link_rounded, size: 17, color: _muted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          entry.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        _Hint(
          icon: locked ? Icons.schedule_rounded : Icons.content_copy_rounded,
          text:
              locked
                  ? 'Open later uses this device’s clock. It is a thoughtful surprise, not secure encryption.'
                  : 'Keeping this creates a new copy. You can edit it freely; changes will not sync back to the sender.',
        ),
        const SizedBox(height: 22),
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

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.title,
    required this.subtitle,
    required this.children,
  });
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: PocklinoTheme.light,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.92,
          ),
          decoration: const BoxDecoration(
            color: _paper,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              key: ValueKey(title),
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _line,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 25,
                                fontFamily: 'Lora',
                                fontWeight: FontWeight.w500,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Close',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded, color: _ink),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ...children,
                ],
              ),
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
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 17, color: _muted),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(color: _muted, fontSize: 12, height: 1.5),
        ),
      ),
    ],
  );
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message, this.onReset});
  final String message;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8E3DB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded, size: 18, color: _ink),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 13,
                    height: 1.5,
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

String _dateTime(DateTime date) =>
    DateFormat('MMM d, yyyy · HH:mm').format(date.toLocal());

String _kindLabel(String kind) => switch (kind) {
  'checklist' => 'Checklist',
  'movie' => 'Movie',
  'trip' => 'Travel plan',
  'letter' => 'Little letter',
  _ => 'Note',
};

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
