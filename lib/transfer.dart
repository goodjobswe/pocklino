import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'models.dart';

/// A versioned, offline transfer format. Checksums detect damaged transfers;
/// they are not signatures, encryption, or proof of who sent a note.
abstract final class TransferCodec {
  static const prefix = 'pocklino:1:';
  static const partPrefix = 'pocklino-part:1:';
  static const maxPayloadBytes = 64 * 1024;
  static const maxEncodedLength = 90000;
  // Version 1 QR frames are no longer shown, but those of earlier releases
  // are still received: up to 700 characters from the original encoder.
  static const maxAcceptedFrameChunkSize = 700;
  // Covers the full encoded-size bound of either version. The independent
  // byte/encoded-length limits apply even to larger legacy fragments.
  static const maxFrames = 375;

  // Version 2 is the format of the QR codes. The entry JSON is deflated and
  // written in base45, whose alphabet is the QR alphanumeric set, so the same
  // page needs about a third of the QR capacity of version 1. Copied codes
  // and files stay on version 1, which survives pasting and older receivers.
  static const compactPrefix = 'POCKLINO:2:';
  static const compactPartPrefix = 'POCKLINO-PART:2:';
  // What a 57 by 57 QR (version 10) holds at error-correction level M. No
  // displayed code is denser than that.
  static const maxQrCharacters = 311;
  // Leaves room for the longest frame header. A multiple of three, so pieces
  // are cut between base45 triplets and never end in a space.
  static const compactChunkSize = 276;
  static const maxCompactLength = 100000;
  static const _checkBytes = 4;

  static String encode(PocketEntry entry) {
    final (json, bytes) = _shareable(entry);
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

  /// The version 2 token: the same entry JSON as [encode], deflated, followed
  /// by the first bytes of its SHA-256 digest.
  static String encodeCompact(PocketEntry entry) {
    final (_, bytes) = _shareable(entry);
    final packed =
        Deflate(bytes, level: DeflateLevel.bestCompression).getBytes();
    final check = sha256.convert(bytes).bytes.sublist(0, _checkBytes);
    final token = '$compactPrefix${_base45Encode([...packed, ...check])}';
    if (token.length > maxCompactLength) {
      throw const FormatException('This page is too large for QR sharing.');
    }
    return token;
  }

  static (Map<String, dynamic>, List<int>) _shareable(PocketEntry entry) {
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
    return (json, bytes);
  }

  static PocketEntry decode(String source) {
    final token = source.trim();
    if (token.startsWith(compactPrefix)) return _decodeCompact(token);
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
    return _received(data);
  }

  static PocketEntry _decodeCompact(String token) {
    if (token.length > maxCompactLength) {
      throw const FormatException(
        'This Pocklino code exceeds the 64 KB sharing limit.',
      );
    }
    const damaged = FormatException(
      'This Pocklino code is incomplete or damaged.',
    );
    final blob = _base45Decode(token.substring(compactPrefix.length));
    if (blob.length <= _checkBytes) throw damaged;
    final packed = blob.length - _checkBytes;
    final List<int> bytes;
    try {
      bytes =
          Inflate(
            Uint8List.sublistView(blob, 0, packed),
            output: _BoundedOutput(maxPayloadBytes),
          ).getBytes();
    } on _TooLarge {
      throw const FormatException(
        'This Pocklino code exceeds the 64 KB sharing limit.',
      );
    } catch (_) {
      // The inflater reports damaged input in several ways, errors included.
      throw damaged;
    }
    final expected = sha256.convert(bytes).bytes;
    for (var i = 0; i < _checkBytes; i++) {
      if (blob[packed + i] != expected[i]) {
        throw const FormatException(
          'This code failed its integrity check. Scan or copy the complete code again.',
        );
      }
    }
    dynamic data;
    try {
      data = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw damaged;
    }
    if (data is! Map<String, dynamic>) {
      throw const FormatException('This Pocklino code has an invalid format.');
    }
    return _received(data);
  }

  static PocketEntry _received(Map<String, dynamic> data) =>
      PocketEntry.fromJson(data).copyWith(
        received: true,
        isExample: false,
        pinned: false,
        archived: false,
      );

  /// Short notes use one normal QR; longer notes loop numbered fragments.
  static List<String> frames(PocketEntry entry) {
    final token = encodeCompact(entry);
    if (token.length <= maxQrCharacters) return [token];
    final payload = token.substring(compactPrefix.length);
    final id = _transferId(token);
    // Even pieces rather than full ones and a short tail: every frame then
    // gets the smallest QR that the page allows.
    final most = (payload.length / compactChunkSize).ceil();
    final size = (payload.length / most / 3).ceil() * 3;
    final count = (payload.length / size).ceil();
    if (count > maxFrames) {
      throw const FormatException(
        'This note needs too many QR frames. Try a smaller note.',
      );
    }
    return List.generate(count, (index) {
      final start = index * size;
      final chunk = payload.substring(
        start,
        math.min(start + size, payload.length),
      );
      return '$compactPartPrefix$id:${index + 1}:$count:$chunk';
    });
  }
}

String _transferId(String token) {
  final digest = sha256.convert(utf8.encode(token)).toString();
  return token.startsWith(TransferCodec.compactPrefix)
      ? digest.substring(0, 8).toUpperCase()
      : digest.substring(0, 16);
}

// RFC 9285. Two bytes become three characters, a last odd byte becomes two.
const _base45 = r'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:';
final _base45Only = RegExp(r'^[0-9A-Z $%*+./:-]+$');

String _base45Encode(List<int> bytes) {
  final out = StringBuffer();
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    final value = bytes[i] * 256 + bytes[i + 1];
    out
      ..write(_base45[value % 45])
      ..write(_base45[value ~/ 45 % 45])
      ..write(_base45[value ~/ 2025]);
  }
  if (bytes.length.isOdd) {
    out
      ..write(_base45[bytes.last % 45])
      ..write(_base45[bytes.last ~/ 45]);
  }
  return out.toString();
}

Uint8List _base45Decode(String text) {
  const damaged = FormatException(
    'This Pocklino code is incomplete or damaged.',
  );
  if (text.length % 3 == 1 || !_base45Only.hasMatch(text)) throw damaged;
  final out = BytesBuilder(copy: false);
  for (var i = 0; i < text.length; i += 3) {
    var value = _base45.indexOf(text[i]) + _base45.indexOf(text[i + 1]) * 45;
    if (i + 2 == text.length) {
      if (value > 0xff) throw damaged;
      out.addByte(value);
    } else {
      value += _base45.indexOf(text[i + 2]) * 2025;
      if (value > 0xffff) throw damaged;
      out
        ..addByte(value >> 8)
        ..addByte(value & 0xff);
    }
  }
  return out.takeBytes();
}

class _TooLarge implements Exception {
  const _TooLarge();
}

/// Stops inflating at the entry size limit, so a small crafted code cannot
/// expand into a very large allocation.
class _BoundedOutput extends OutputMemoryStream {
  _BoundedOutput(this.limit);
  final int limit;

  void _room(int added) {
    if (length + added > limit) throw const _TooLarge();
  }

  @override
  void writeByte(int value) {
    _room(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _room(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _room(stream.length);
    super.writeStream(stream);
  }
}

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
    if (source.length > TransferCodec.maxCompactLength + 100) {
      throw const FormatException('This code is too large to read safely.');
    }
    final token = source.trim();
    if (token.startsWith(TransferCodec.prefix) ||
        token.startsWith(TransferCodec.compactPrefix)) {
      final id = _transferId(token);
      _checkTransfer(id);
      if (_complete) return null;
      final entry = TransferCodec.decode(token);
      _id = id;
      _complete = true;
      return entry;
    }
    final compact = token.startsWith(TransferCodec.compactPartPrefix);
    if (!compact && !token.startsWith(TransferCodec.partPrefix)) {
      throw const FormatException(
        'Point the camera at a Pocklino sharing code.',
      );
    }
    // A version 2 fragment is base45 and may itself contain colons.
    final parts = token.split(':');
    if ((compact ? parts.length < 6 : parts.length != 6) ||
        !(compact ? RegExp(r'^[A-F0-9]{8}$') : RegExp(r'^[a-f0-9]{16}$'))
            .hasMatch(parts[2])) {
      throw const FormatException('This QR frame is damaged. Keep scanning.');
    }
    final id = parts[2];
    final index = int.tryParse(parts[3]);
    final count = int.tryParse(parts[4]);
    final chunk = parts.sublist(5).join(':');
    if (index == null ||
        count == null ||
        count < 1 ||
        count > TransferCodec.maxFrames ||
        index < 1 ||
        index > count ||
        chunk.isEmpty ||
        chunk.length >
            (compact
                ? TransferCodec.compactChunkSize
                : TransferCodec.maxAcceptedFrameChunkSize) ||
        !(compact ? _base45Only : RegExp(r'^[A-Za-z0-9_-]+$')).hasMatch(
          chunk,
        )) {
      throw const FormatException(
        'This QR frame has invalid size or numbering.',
      );
    }
    final prefix = compact ? TransferCodec.compactPrefix : TransferCodec.prefix;
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
    if (length + prefix.length >
        (compact
            ? TransferCodec.maxCompactLength
            : TransferCodec.maxEncodedLength)) {
      throw const FormatException(
        'This QR transfer exceeds the sharing size limit.',
      );
    }
    if (next.length == count) {
      final completeToken =
          '$prefix${List.generate(count, (index) => next[index + 1]!).join()}';
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
