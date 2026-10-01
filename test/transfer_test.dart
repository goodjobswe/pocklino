import 'dart:convert';

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
    expect(token.length, lessThan(500));
    expect(TransferCodec.frames(original), [token]);
    expect(
      TransferCodec.decode(token).toJson(),
      original.copyWith(received: true).toJson(),
    );
    // An empty title is valid and required, even though optional empties vanish.
    final untitled = original.copyWith(title: '', body: '');
    expect(
      TransferCodec.decode(TransferCodec.encode(untitled)).toJson(),
      untitled.copyWith(received: true).toJson(),
    );
    // ignore: avoid_print
    print('Compact realistic short note: ${token.length} characters');
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
      final result = TransferCodec.decode(TransferCodec.encode(original));
      expect(result.toJson(), original.copyWith(received: true).toJson());
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
    final count = (payload.length / 700).ceil();
    final assembler = TransferAssembler();
    PocketEntry? completed;
    for (var i = 0; i < count; i++) {
      final start = i * 700;
      final end = (start + 700).clamp(0, payload.length);
      completed =
          assembler.add(
            '${TransferCodec.partPrefix}$id:${i + 1}:$count:${payload.substring(start, end)}',
          ) ??
          completed;
    }
    expect(completed?.toJson(), original.copyWith(received: true).toJson());
  });

  test(
    'large compact transfers keep new frames small and reconstruct Unicode',
    () {
      final original = page(body: '\u{1f9f3}' * 15000);
      final frames = TransferCodec.frames(original);
      expect(frames.length, greaterThan(128));
      expect(frames.length, lessThanOrEqualTo(TransferCodec.maxFrames));
      expect(
        frames.every((frame) => frame.split(':').last.length <= 400),
        isTrue,
      );
      final assembler = TransferAssembler();
      PocketEntry? completed;
      for (final frame in frames.reversed) {
        completed = assembler.add(frame) ?? completed;
      }
      expect(completed?.body, original.body);
      expect(assembler.progress, 1);
    },
  );
  test('QR roundtrip preserves unicode, dates, links and items', () {
    final original = page(body: 'Hej!\n旅行 🧳\nمرحبا').copyWith(
      url: 'https://www.imdb.com/title/tt2278388/',
      recipient: 'Céline',
    );
    final result = TransferCodec.decode(TransferCodec.encode(original));
    expect(result.toJson(), original.copyWith(received: true).toJson());
  });

  test(
    'received preview honors opening date and strips sender-local flags',
    () {
      final original = page(
        unlockAt: DateTime.now().add(const Duration(days: 3)),
      ).copyWith(isExample: true, pinned: true, archived: true);
      final result = TransferCodec.decode(TransferCodec.encode(original));
      expect(result.isLocked, isTrue);
      expect(result.isExample, isFalse);
      expect(result.pinned, isFalse);
      expect(result.archived, isFalse);
      expect(() => TransferCodec.encode(result), throwsFormatException);
    },
  );

  test('rejects unsupported, malformed, oversized and corrupted payloads', () {
    for (final input in [
      'hello',
      'pocklino:2:abc',
      'pocklino:1:%%%',
      'pocklino:1:___',
      '${TransferCodec.prefix}${'a' * 90001}',
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
    (envelope['e'] as Map<String, dynamic>)['title'] = 'Tampered';
    final corrupted =
        '${TransferCodec.prefix}${base64Url.encode(utf8.encode(jsonEncode(envelope))).replaceAll('=', '')}';
    expect(() => TransferCodec.decode(corrupted), throwsFormatException);
  });

  test(
    'single token assembly finishes once and reset permits another note',
    () {
      final assembler = TransferAssembler();
      final token = TransferCodec.encode(page());
      expect(assembler.progress, 0);
      expect(assembler.add(token)?.title, 'For you 💌');
      expect(assembler.progress, 1);
      expect(assembler.add(token), isNull);
      expect(
        () => assembler.add(TransferCodec.encode(page(title: 'Other'))),
        throwsFormatException,
      );
      assembler.reset();
      expect(assembler.progress, 0);
      expect(
        assembler.add(TransferCodec.encode(page(title: 'Other')))?.title,
        'Other',
      );
    },
  );

  test('animated QR assembles out of order and tolerates repeated frames', () {
    final original = page(body: 'A very lovely little adventure. ' * 120);
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
      final frames = TransferCodec.frames(page(body: 'Long note. ' * 200));
      final other = TransferCodec.frames(
        page(title: 'A different page', body: 'Long note. ' * 200),
      );
      final assembler = TransferAssembler();
      assembler.add(frames.first);
      final progress = assembler.progress;
      expect(() => assembler.add(other.first), throwsFormatException);
      final parts = frames.first.split(':');
      final first = parts.last[0];
      parts[5] = '${first == 'A' ? 'B' : 'A'}${parts.last.substring(1)}';
      expect(() => assembler.add(parts.join(':')), throwsFormatException);
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
    ]) {
      expect(() => assembler.add(input), throwsFormatException);
      expect(assembler.progress, 0);
    }
  });

  test('a corrupted assembled transfer cannot produce a note', () {
    final frames = TransferCodec.frames(page(body: 'Long note. ' * 200));
    final parts = frames.last.split(':');
    parts[5] = '${parts.last.substring(0, parts.last.length - 1)}A';
    if (parts.join(':') == frames.last) {
      parts[5] = '${parts.last.substring(0, parts.last.length - 1)}B';
    }
    final assembler = TransferAssembler();
    for (final frame in frames.take(frames.length - 1)) {
      expect(assembler.add(frame), isNull);
    }
    expect(() => assembler.add(parts.join(':')), throwsFormatException);
    expect(assembler.progress, lessThan(1));
    expect(assembler.add(frames.last), isNotNull);
  });
}
