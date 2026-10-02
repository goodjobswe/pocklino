import 'dart:convert';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocklino/models.dart';
import 'package:pocklino/transfer.dart';

PocketEntry page({
  String body = '',
  String title = 'For you 💌',
  DateTime? unlockAt,
}) => PocketEntry(
  id: 'test-note',
  title: title,
  body: body,
  kind: EntryKind.letter,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  unlockAt: unlockAt,
  items: [const CheckItem(id: 'a', text: '牛乳 café 🥛', done: true)],
);

/// Made-up words. A repeated phrase would deflate to almost nothing and
/// never need more than one QR.
String prose(int words, {int seed = 1}) {
  final random = math.Random(seed);
  const letters = 'abcdefghijklmnopqrstuvwxyz';
  return List.generate(
    words,
    (_) =>
        List.generate(
          2 + random.nextInt(7),
          (_) => letters[random.nextInt(letters.length)],
        ).join(),
  ).join(' ');
}

/// An independent RFC 9285 encoder, so the tests do not check the codec
/// against itself.
String base45(List<int> bytes) {
  const alphabet = r'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:';
  final out = StringBuffer();
  for (var i = 0; i < bytes.length; i += 2) {
    if (i + 1 < bytes.length) {
      var value = (bytes[i] << 8) | bytes[i + 1];
      for (var digit = 0; digit < 3; digit++) {
        out.write(alphabet[value % 45]);
        value ~/= 45;
      }
    } else {
      out
        ..write(alphabet[bytes[i] % 45])
        ..write(alphabet[bytes[i] ~/ 45]);
    }
  }
  return out.toString();
}

/// A version 2 token built by hand from the given entry JSON bytes.
String compactToken(List<int> json, {List<int>? check}) =>
    '${TransferCodec.compactPrefix}${base45([...Deflate(json).getBytes(), ...check ?? sha256.convert(json).bytes.take(4)])}';

/// Replaces the fragment of a frame, which in version 2 may contain colons.
String withChunk(String frame, String Function(String chunk) change) {
  final parts = frame.split(':');
  return [...parts.take(5), change(parts.skip(5).join(':'))].join(':');
}

String chunkOf(String frame) => frame.split(':').skip(5).join(':');

final qrAlphanumeric = RegExp(r'^[0-9A-Z $%*+./:-]+$');

const encoders = {
  'version 1': TransferCodec.encode,
  'version 2': TransferCodec.encodeCompact,
};

void main() {
  test('compact short note omits defaults and fits a clear single QR', () {
    final original = PocketEntry(
      id: '550e8400-e29b-41d4-a716-446655440000',
      title: 'Remember milk',
      body: 'Pick up milk on the way home.',
      kind: EntryKind.note,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final token = TransferCodec.encode(original);
    final envelope =
        jsonDecode(
              utf8.decode(
                base64Url.decode(
                  base64Url.normalize(
                    token.substring(TransferCodec.prefix.length),
                  ),
                ),
              ),
            )
            as Map<String, dynamic>;
    final data = envelope['e'] as Map<String, dynamic>;
    expect(data.keys.toSet(), {
      'id',
      'title',
      'body',
      'kind',
      'createdAt',
      'updatedAt',
    });
    expect(token.length, lessThanOrEqualTo(400));
    expect(
      TransferCodec.decode(token).toJson(),
      original.copyWith(received: true).toJson(),
    );
    final compact = TransferCodec.encodeCompact(original);
    expect(TransferCodec.frames(original), [compact]);
    expect(compact.length, lessThanOrEqualTo(TransferCodec.maxQrCharacters));
    expect(qrAlphanumeric.hasMatch(compact), isTrue);
    expect(
      TransferCodec.decode(compact).toJson(),
      original.copyWith(received: true).toJson(),
    );
    // An empty title is valid and required, even though optional empties vanish.
    final untitled = original.copyWith(title: '', body: '');
    for (final encode in encoders.values) {
      expect(
        TransferCodec.decode(encode(untitled)).toJson(),
        untitled.copyWith(received: true).toJson(),
      );
    }
    // ignore: avoid_print
    print(
      'Compact realistic short note: ${token.length} characters as a copied code, ${compact.length} in its QR',
    );
  });

  test('base45 follows RFC 9285', () {
    expect(base45(utf8.encode('AB')), 'BB8');
    expect(base45(utf8.encode('Hello!!')), '%69 VD92EX0');
    expect(base45(utf8.encode('base-45')), 'UJCLQE7W581');
    // The codec reads a token written by the independent encoder above, and
    // writes one that differs from it in nothing but the deflate stream.
    final original = page(body: 'Hej!\n旅行 🧳');
    final json =
        (jsonDecode(
              utf8.decode(
                base64Url.decode(
                  base64Url.normalize(
                    TransferCodec.encode(
                      original,
                    ).substring(TransferCodec.prefix.length),
                  ),
                ),
              ),
            )
            as Map<String, dynamic>)['e'];
    expect(
      TransferCodec.decode(
        compactToken(utf8.encode(jsonEncode(json))),
      ).toJson(),
      original.copyWith(received: true).toJson(),
    );
  });

  test('a page of ordinary text needs under half the QR capacity', () {
    final original = page(
      body:
          'We took the early ferry out to the island and walked the long way '
          'round, past the lighthouse and the old boat sheds. Lunch was '
          'smoked fish on the rocks, then a swim that nobody had planned for. '
          'Remember to bring the blue thermos next time, and a second towel. '
          'The last ferry back leaves at half past six, so we should be at '
          'the pier by six at the latest. Ask Maria about the cabin for the '
          'first week of July, and whether the bikes can stay in the shed.',
    );
    // Byte mode costs 8 bits a character, alphanumeric mode 5.5.
    final before = TransferCodec.encode(original).length * 8;
    final after = TransferCodec.encodeCompact(original).length * 5.5;
    expect(after, lessThan(before * 0.5));
  });

  test(
    'one QR up to the density limit, then even pieces; earlier larger single codes are still read',
    () {
      PocketEntry note(int words) => PocketEntry(
        id: 'a',
        title: '',
        body: prose(words),
        kind: EntryKind.note,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      var words = 1;
      while (TransferCodec.encodeCompact(note(words + 1)).length <=
          TransferCodec.maxQrCharacters) {
        words++;
      }
      final staticEntry = note(words);
      final staticToken = TransferCodec.encodeCompact(staticEntry);
      expect(
        staticToken.length,
        inInclusiveRange(
          TransferCodec.maxQrCharacters - 12,
          TransferCodec.maxQrCharacters,
        ),
      );
      expect(TransferCodec.frames(staticEntry), [staticToken]);
      final frames = TransferCodec.frames(note(words + 1));
      expect(frames, hasLength(2));
      expect(
        chunkOf(frames[0]).length - chunkOf(frames[1]).length,
        inInclusiveRange(0, 3),
      );

      final legacyEntry = note(40);
      final legacyToken = TransferCodec.encode(legacyEntry);
      expect(legacyToken.length, inInclusiveRange(401, 650));
      expect(
        TransferAssembler().add(legacyToken)?.toJson(),
        legacyEntry.copyWith(received: true).toJson(),
      );
    },
  );

  test('no frame is denser than a 57 by 57 alphanumeric code', () {
    for (final words in [60, 150, 400, 1500, 6000]) {
      final original = page(body: prose(words, seed: words));
      final frames = TransferCodec.frames(original);
      expect(frames.length, greaterThan(1));
      for (final frame in frames) {
        expect(frame.length, lessThanOrEqualTo(TransferCodec.maxQrCharacters));
        expect(qrAlphanumeric.hasMatch(frame), isTrue);
        // A fragment that ended in a space would lose it to a trim.
        expect(frame.endsWith(' '), isFalse);
      }
      final lengths = frames.map((frame) => chunkOf(frame).length).toList();
      expect(
        lengths.first - lengths.last,
        inInclusiveRange(0, 3 * frames.length),
      );
      expect(lengths.take(frames.length - 1).toSet(), hasLength(1));
      final assembler = TransferAssembler();
      PocketEntry? completed;
      for (final frame in frames) {
        completed = assembler.add(' $frame\n') ?? completed;
      }
      expect(completed?.toJson(), original.copyWith(received: true).toJson());
    }
  });

  test(
    'compact payload retains non-default fields and unchecked list items',
    () {
      final original = page(body: 'A note for you \u{1f496}').copyWith(
        emoji: '\u{1f9f3}',
        collection: 'Summer',
        colorIndex: 4,
        watched: true,
        date: DateTime.utc(2027, 2, 1),
        endDate: DateTime.utc(2027, 2, 3),
        sender: 'Sam',
        recipient: 'Avery',
        items: [
          const CheckItem(id: 'a', text: 'Milk \u{1f95b}'),
          const CheckItem(id: 'b', text: 'Coffee', done: true),
        ],
      );
      for (final encode in encoders.values) {
        final result = TransferCodec.decode(encode(original));
        expect(result.toJson(), original.copyWith(received: true).toJson());
      }
    },
  );

  test('decoder accepts original full v1 envelope and 700-character frames', () {
    final original = page(body: 'Legacy transfer. ' * 100);
    final data = original.toJson();
    final legacy =
        '${TransferCodec.prefix}${base64Url.encode(utf8.encode(jsonEncode({'e': data, 'h': sha256.convert(utf8.encode(jsonEncode(data))).toString()}))).replaceAll('=', '')}';
    expect(
      TransferCodec.decode(legacy).toJson(),
      original.copyWith(received: true).toJson(),
    );
    final payload = legacy.substring(TransferCodec.prefix.length);
    final id = sha256.convert(utf8.encode(legacy)).toString().substring(0, 16);
    for (final size in [700, 240]) {
      final count = (payload.length / size).ceil();
      final assembler = TransferAssembler();
      PocketEntry? completed;
      for (var i = 0; i < count; i++) {
        final start = i * size;
        final end = (start + size).clamp(0, payload.length);
        completed =
            assembler.add(
              '${TransferCodec.partPrefix}$id:${i + 1}:$count:${payload.substring(start, end)}',
            ) ??
            completed;
      }
      expect(completed?.toJson(), original.copyWith(received: true).toJson());
    }
  });

  test(
    'full 64 KiB Unicode transfer recovers a missing piece on a later loop',
    () {
      final seed = page(body: 'x');
      final seedToken = TransferCodec.encode(seed);
      final envelope =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(
                    base64Url.normalize(
                      seedToken.substring(TransferCodec.prefix.length),
                    ),
                  ),
                ),
              )
              as Map<String, dynamic>;
      final seedBytes = utf8.encode(jsonEncode(envelope['e'])).length;
      // The body already has one byte. Fill the remaining entry budget
      // exactly, with characters in no order that deflate could shorten much.
      final bodyBytes = TransferCodec.maxPayloadBytes - seedBytes + 1;
      final random = math.Random(7);
      final alphabet = [
        ...'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
            .split(''),
        '\u{1f9f3}',
        '牛',
        'é',
      ];
      final text = StringBuffer();
      var used = 0;
      while (true) {
        final next = alphabet[random.nextInt(alphabet.length)];
        final size = utf8.encode(next).length;
        if (used + size > bodyBytes) break;
        text.write(next);
        used += size;
      }
      final body = '$text${'x' * (bodyBytes - used)}';
      final original = seed.copyWith(body: body);
      expect(seedBytes - 1 + utf8.encode(body).length, 64 * 1024);
      final frames = TransferCodec.frames(original);
      expect(frames.length, greaterThan(200));
      expect(frames.length, lessThanOrEqualTo(TransferCodec.maxFrames));
      expect(
        frames.every((frame) => frame.length <= TransferCodec.maxQrCharacters),
        isTrue,
      );
      final assembler = TransferAssembler();
      final missing = frames[frames.length ~/ 2];
      for (final frame in frames.reversed.where((frame) => frame != missing)) {
        expect(assembler.add(frame), isNull);
        expect(assembler.add(frame), isNull);
      }
      expect(assembler.receivedFrames, frames.length - 1);
      expect(assembler.totalFrames, frames.length);
      expect(assembler.progress, lessThan(1));
      final completed = assembler.add(missing);
      expect(completed?.toJson(), original.copyWith(received: true).toJson());
      expect(assembler.progress, 1);
      expect(assembler.add(missing), isNull);
      expect(
        TransferCodec.decode(TransferCodec.encode(original)).toJson(),
        original.copyWith(received: true).toJson(),
      );
      for (final encode in encoders.values) {
        expect(
          () => encode(original.copyWith(body: '${original.body}x')),
          throwsFormatException,
        );
      }
      // ignore: avoid_print
      print('Full 64 KiB page: ${frames.length} frames');
    },
  );

  test('QR roundtrip preserves unicode, dates, links and items', () {
    final original = page(body: 'Hej!\n旅行 🧳\nمرحبا').copyWith(
      url: 'https://www.imdb.com/title/tt2278388/',
      recipient: 'Céline',
    );
    for (final encode in encoders.values) {
      final result = TransferCodec.decode(encode(original));
      expect(result.toJson(), original.copyWith(received: true).toJson());
    }
  });

  test(
    'received preview honors opening date and strips sender-local flags',
    () {
      final original = page(
        unlockAt: DateTime.now().add(const Duration(days: 3)),
      ).copyWith(isExample: true, pinned: true, archived: true);
      for (final encode in encoders.values) {
        final result = TransferCodec.decode(encode(original));
        expect(result.isLocked, isTrue);
        expect(result.isExample, isFalse);
        expect(result.pinned, isFalse);
        expect(result.archived, isFalse);
        expect(() => encode(result), throwsFormatException);
        expect(() => TransferCodec.frames(result), throwsFormatException);
      }
    },
  );

  test('rejects unsupported, malformed, oversized and corrupted payloads', () {
    for (final input in [
      'hello',
      'pocklino:2:abc',
      'pocklino:1:%%%',
      'pocklino:1:___',
      '${TransferCodec.prefix}${'a' * 90001}',
      'POCKLINO:3:ABC',
      TransferCodec.compactPrefix,
      '${TransferCodec.compactPrefix}abc',
      '${TransferCodec.compactPrefix}AB',
      '${TransferCodec.compactPrefix}ABCD',
      // Three characters that spell a number above 65535.
      '${TransferCodec.compactPrefix}:::::::::',
      '${TransferCodec.compactPrefix}${'A' * 100002}',
    ]) {
      expect(() => TransferCodec.decode(input), throwsFormatException);
    }
    expect(
      () => TransferCodec.encode(page(body: '🧳' * 20000)),
      throwsFormatException,
    );
    final token = TransferCodec.encode(page());
    final envelope =
        jsonDecode(
              utf8.decode(
                base64Url.decode(
                  base64Url.normalize(
                    token.substring(TransferCodec.prefix.length),
                  ),
                ),
              ),
            )
            as Map<String, dynamic>;
    final json = utf8.encode(jsonEncode(envelope['e']));
    (envelope['e'] as Map<String, dynamic>)['title'] = 'Tampered';
    final corrupted =
        '${TransferCodec.prefix}${base64Url.encode(utf8.encode(jsonEncode(envelope))).replaceAll('=', '')}';
    expect(() => TransferCodec.decode(corrupted), throwsFormatException);

    // The same for version 2: a sound token, then each kind of damage.
    expect(TransferCodec.decode(compactToken(json)).title, 'For you 💌');
    final tampered = utf8.encode(jsonEncode(envelope['e']));
    for (final input in [
      compactToken(
        tampered,
        check: sha256.convert(json).bytes.take(4).toList(),
      ),
      compactToken(json, check: [0, 0, 0, 0]),
      compactToken(utf8.encode('[1,2,3]')),
      compactToken(utf8.encode('not json')),
      compactToken(utf8.encode('{"id":"a"}')),
      compactToken(json).substring(0, compactToken(json).length - 9),
      // Not a deflate stream at all.
      '${TransferCodec.compactPrefix}${base45(List.filled(40, 0xff))}',
    ]) {
      expect(() => TransferCodec.decode(input), throwsFormatException);
    }
    for (final encode in encoders.values) {
      final sound = encode(page(body: prose(80)));
      for (final at in [20, sound.length ~/ 2, sound.length - 2]) {
        final other = sound[at] == 'A' ? 'B' : 'A';
        expect(
          () => TransferCodec.decode(sound.replaceRange(at, at + 1, other)),
          throwsFormatException,
        );
      }
    }
  });

  test('a small code cannot inflate past the entry size limit', () {
    // A megabyte of one letter deflates to about a kilobyte.
    final bomb = utf8.encode('{"body":"${'a' * (1024 * 1024)}"}');
    final token = compactToken(bomb);
    expect(token.length, lessThan(4000));
    expect(
      () => TransferCodec.decode(token),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('64 KB'),
        ),
      ),
    );
    expect(() => TransferAssembler().add(token), throwsFormatException);
  });

  test(
    'single token assembly finishes once and reset permits another note',
    () {
      for (final encode in encoders.values) {
        final assembler = TransferAssembler();
        final token = encode(page());
        expect(assembler.progress, 0);
        expect(assembler.add(token)?.title, 'For you 💌');
        expect(assembler.progress, 1);
        expect(assembler.add(token), isNull);
        expect(
          () => assembler.add(encode(page(title: 'Other'))),
          throwsFormatException,
        );
        assembler.reset();
        expect(assembler.progress, 0);
        expect(assembler.add(encode(page(title: 'Other')))?.title, 'Other');
      }
    },
  );

  test('animated QR assembles out of order and tolerates repeated frames', () {
    final original = page(body: prose(600));
    final frames = TransferCodec.frames(original);
    expect(frames.length, greaterThan(2));
    final assembler = TransferAssembler();
    PocketEntry? completed;
    for (final frame in frames.reversed) {
      completed = assembler.add(frame) ?? completed;
      expect(assembler.add(frame), isNull);
    }
    expect(completed?.body, original.body);
    expect(assembler.progress, 1);
    expect(assembler.receivedFrames, frames.length);
  });

  test(
    'rejects mixed notes and conflicting frames without discarding progress',
    () {
      final frames = TransferCodec.frames(page(body: prose(400)));
      final other = TransferCodec.frames(
        page(title: 'A different page', body: prose(400)),
      );
      final assembler = TransferAssembler();
      assembler.add(frames.first);
      final progress = assembler.progress;
      expect(() => assembler.add(other.first), throwsFormatException);
      // Neither can a version 1 transfer join one that began as version 2.
      expect(
        () => assembler.add(
          '${TransferCodec.partPrefix}0123456789abcdef:1:${frames.length}:abc',
        ),
        throwsFormatException,
      );
      expect(
        () => assembler.add(
          withChunk(
            frames.first,
            (chunk) => '${chunk[0] == 'A' ? 'B' : 'A'}${chunk.substring(1)}',
          ),
        ),
        throwsFormatException,
      );
      expect(assembler.progress, progress);
      PocketEntry? entry;
      for (final frame in frames.skip(1)) {
        entry = assembler.add(frame) ?? entry;
      }
      expect(entry, isNotNull);
    },
  );

  test('rejects impossible counts, indices, and oversized frame chunks', () {
    final assembler = TransferAssembler();
    for (final input in [
      'pocklino-part:1:0123456789abcdef:0:3:abc',
      'pocklino-part:1:0123456789abcdef:4:3:abc',
      'pocklino-part:1:0123456789abcdef:1:999999:abc',
      'pocklino-part:1:0123456789abcdef:1:3:${'a' * 701}',
      'pocklino-part:1:0123456789abcdef:1:3:abc:abc',
      'POCKLINO-PART:2:0123ABCD:0:3:ABC',
      'POCKLINO-PART:2:0123ABCD:4:3:ABC',
      'POCKLINO-PART:2:0123ABCD:1:999999:ABC',
      'POCKLINO-PART:2:0123ABCD:1:3:${'A' * (TransferCodec.compactChunkSize + 1)}',
      'POCKLINO-PART:2:0123ABCD:1:3:abc',
      'POCKLINO-PART:2:0123ABCD:1:3:',
      'POCKLINO-PART:2:0123ABCD:1:3',
      'POCKLINO-PART:2:0123abcd:1:3:ABC',
      'POCKLINO-PART:2:0123456789ABCDEF:1:3:ABC',
      'POCKLINO-PART:3:0123ABCD:1:3:ABC',
    ]) {
      expect(() => assembler.add(input), throwsFormatException);
      expect(assembler.progress, 0);
    }
  });

  test('more allowed frames do not increase the encoded transfer limit', () {
    for (final (partPrefix, id, fullChunk, limit) in [
      (
        TransferCodec.partPrefix,
        '0123456789abcdef',
        'a' * TransferCodec.maxAcceptedFrameChunkSize,
        TransferCodec.maxEncodedLength - TransferCodec.prefix.length,
      ),
      (
        TransferCodec.compactPartPrefix,
        '0123ABCD',
        'A' * TransferCodec.compactChunkSize,
        TransferCodec.maxCompactLength - TransferCodec.compactPrefix.length,
      ),
    ]) {
      final assembler = TransferAssembler();
      final fittingChunks = limit ~/ fullChunk.length;
      expect(fittingChunks, lessThan(TransferCodec.maxFrames));
      for (var index = 1; index <= fittingChunks; index++) {
        expect(
          assembler.add(
            '$partPrefix$id:$index:${TransferCodec.maxFrames}:$fullChunk',
          ),
          isNull,
        );
      }
      expect(
        () => assembler.add(
          '$partPrefix$id:${fittingChunks + 1}:${TransferCodec.maxFrames}:$fullChunk',
        ),
        throwsFormatException,
      );
      expect(assembler.receivedFrames, fittingChunks);
    }
  });

  test('a corrupted assembled transfer cannot produce a note', () {
    final frames = TransferCodec.frames(page(body: prose(400)));
    final damaged = withChunk(frames.last, (chunk) {
      final end = chunk[chunk.length - 1] == 'A' ? 'B' : 'A';
      return '${chunk.substring(0, chunk.length - 1)}$end';
    });
    final assembler = TransferAssembler();
    for (final frame in frames.take(frames.length - 1)) {
      expect(assembler.add(frame), isNull);
    }
    expect(() => assembler.add(damaged), throwsFormatException);
    expect(assembler.progress, lessThan(1));
    expect(assembler.add(frames.last), isNotNull);
  });
}
