import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import 'models.dart';

/// A versioned, offline transfer format. Checksums detect damaged transfers;
/// they are not signatures, encryption, or proof of who sent a note.
abstract final class TransferCodec {
  static const prefix = 'pocklino:1:';
  static const partPrefix = 'pocklino-part:1:';
  static const maxPayloadBytes = 64 * 1024;
  static const maxEncodedLength = 90000;
  static const singleFrameMaxLength = 650;
  static const frameChunkSize = 400;
  // Continue receiving the larger frames emitted by the original v1 encoder.
  static const maxAcceptedFrameChunkSize = 700;
  static const maxFrames = 224;

  static String encode(PocketEntry entry) {
    if (entry.isLocked) {
      throw const FormatException(
        'This little surprise can be passed after its opening date.',
      );
    }
    final json =
        PocketEntry.fromJson(entry.toJson()).toJson()
          ..remove('pinned')
          ..remove('archived')
          ..remove('received')
          ..remove('isExample');
    // Omit only values that fromJson reconstructs identically. Keep required
    // fields even when a valid title is empty, and preserve every custom value.
    const requiredKeys = {'id', 'title', 'kind', 'createdAt', 'updatedAt'};
    json.removeWhere(
      (key, value) =>
          !requiredKeys.contains(key) &&
          (value == null ||
              value == '' ||
              value == false ||
              (value is List && value.isEmpty)),
    );
    if (json['collection'] == 'Everyday') json.remove('collection');
    if (json['emoji'] == '\u{1f4dd}') json.remove('emoji');
    if (json['colorIndex'] == 0) json.remove('colorIndex');
    final items = json['items'];
    if (items is List) {
      for (final item in items) {
        if (item is Map && item['done'] == false) item.remove('done');
      }
    }
    final bytes = utf8.encode(jsonEncode(json));
    if (bytes.length > maxPayloadBytes) {
      throw const FormatException(
        'This page is too large for QR sharing. Shorten it or split it into smaller pages (64 KB maximum).',
      );
    }
    final envelope = jsonEncode({
      'e': json,
      'h': sha256.convert(bytes).toString(),
    });
    final token =
        '$prefix${base64Url.encode(utf8.encode(envelope)).replaceAll('=', '')}';
    if (token.length > maxEncodedLength) {
      throw const FormatException('This page is too large for QR sharing.');
    }
    return token;
  }

  static PocketEntry decode(String source) {
    final token = source.trim();
    if (!token.startsWith(prefix)) {
      throw const FormatException(
        'This is not a supported Pocklino code. Ask the sender to make a new code.',
      );
    }
    if (token.length > maxEncodedLength) {
      throw const FormatException(
        'This Pocklino code exceeds the 64 KB sharing limit.',
      );
    }
    final payload = token.substring(prefix.length);
    if (payload.isEmpty || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(payload)) {
      throw const FormatException(
        'This Pocklino code is incomplete or damaged.',
      );
    }
    dynamic envelope;
    try {
      final bytes = base64Url.decode(base64Url.normalize(payload));
      if (bytes.length > maxPayloadBytes + 200) {
        throw const FormatException('This Pocklino code is too large.');
      }
      envelope = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const FormatException(
        'This Pocklino code is incomplete or damaged.',
      );
    }
    if (envelope is! Map<String, dynamic> ||
        envelope['e'] is! Map<String, dynamic> ||
        envelope['h'] is! String) {
      throw const FormatException('This Pocklino code has an invalid format.');
    }
    final data = envelope['e'] as Map<String, dynamic>;
    final bytes = utf8.encode(jsonEncode(data));
    if (bytes.length > maxPayloadBytes) {
      throw const FormatException(
        'This Pocklino code exceeds the 64 KB sharing limit.',
      );
    }
    final expectedHash = sha256.convert(bytes).toString();
    if (envelope['h'] != expectedHash) {
      throw const FormatException(
        'This code failed its integrity check. Scan or copy the complete code again.',
      );
    }
    return PocketEntry.fromJson(data).copyWith(
      received: true,
      isExample: false,
      pinned: false,
      archived: false,
    );
  }

  /// Short notes use one normal QR; longer notes loop numbered fragments.
  static List<String> frames(PocketEntry entry) {
    final token = encode(entry);
    if (token.length <= singleFrameMaxLength) return [token];
    final payload = token.substring(prefix.length);
    final id = _transferId(token);
    final count = (payload.length / frameChunkSize).ceil();
    if (count > maxFrames) {
      throw const FormatException(
        'This note needs too many QR frames. Try a smaller note.',
      );
    }
    return List.generate(count, (index) {
      final start = index * frameChunkSize;
      final chunk = payload.substring(
        start,
        math.min(start + frameChunkSize, payload.length),
      );
      return '$partPrefix$id:${index + 1}:$count:$chunk';
    });
  }
}

String _transferId(String token) =>
    sha256.convert(utf8.encode(token)).toString().substring(0, 16);

/// Collects animated QR fragments in any order. Repeated frames are harmless.
/// A different transfer or conflicting frame leaves the valid collected data
/// intact and asks the user to reset before changing senders.
class TransferAssembler {
  String? _id;
  int? _count;
  final Map<int, String> _chunks = {};
  bool _complete = false;

  double get progress =>
      _complete
          ? 1
          : _count == null
          ? 0
          : _chunks.length / _count!;
  int get receivedFrames => _chunks.length;
  int get totalFrames => _count ?? 0;

  void reset() {
    _id = null;
    _count = null;
    _chunks.clear();
    _complete = false;
  }

  PocketEntry? add(String source) {
    // Bound before trim or splitting, including scans of unrelated QR codes.
    if (source.length > TransferCodec.maxEncodedLength + 100) {
      throw const FormatException('This code is too large to read safely.');
    }
    final token = source.trim();
    if (token.startsWith(TransferCodec.prefix)) {
      final id = _transferId(token);
      _checkTransfer(id);
      if (_complete) return null;
      final entry = TransferCodec.decode(token);
      _id = id;
      _complete = true;
      return entry;
    }
    if (!token.startsWith(TransferCodec.partPrefix)) {
      throw const FormatException(
        'Point the camera at a Pocklino sharing code.',
      );
    }
    final parts = token.split(':');
    if (parts.length != 6 || !RegExp(r'^[a-f0-9]{16}$').hasMatch(parts[2])) {
      throw const FormatException('This QR frame is damaged. Keep scanning.');
    }
    final id = parts[2];
    final index = int.tryParse(parts[3]);
    final count = int.tryParse(parts[4]);
    final chunk = parts[5];
    if (index == null ||
        count == null ||
        count < 1 ||
        count > TransferCodec.maxFrames ||
        index < 1 ||
        index > count ||
        chunk.isEmpty ||
        chunk.length > TransferCodec.maxAcceptedFrameChunkSize ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(chunk)) {
      throw const FormatException(
        'This QR frame has invalid size or numbering.',
      );
    }
    _checkTransfer(id);
    if (_count != null && _count != count) {
      throw const FormatException(
        'These QR frames disagree. Reset and ask the sender to reopen the code.',
      );
    }
    final previous = _chunks[index];
    if (previous != null) {
      if (previous != chunk) {
        throw const FormatException(
          'A QR frame changed during transfer. Reset and scan the note again.',
        );
      }
      return null;
    }
    if (_complete) return null;
    final next = {..._chunks, index: chunk};
    final length = next.values.fold<int>(0, (sum, part) => sum + part.length);
    if (length + TransferCodec.prefix.length > TransferCodec.maxEncodedLength) {
      throw const FormatException(
        'This QR transfer exceeds the sharing size limit.',
      );
    }
    if (next.length == count) {
      final completeToken =
          '${TransferCodec.prefix}${List.generate(count, (index) => next[index + 1]!).join()}';
      if (_transferId(completeToken) != id) {
        throw const FormatException(
          'This QR transfer is damaged. Reset and scan the note again.',
        );
      }
      final entry = TransferCodec.decode(completeToken);
      _id = id;
      _count = count;
      _chunks.addAll(next);
      _complete = true;
      return entry;
    }
    _id = id;
    _count = count;
    _chunks[index] = chunk;
    return null;
  }

  void _checkTransfer(String id) {
    if (_id != null && _id != id) {
      throw const FormatException(
        'This code belongs to a different note. Reset the scanner to receive it.',
      );
    }
  }
}
