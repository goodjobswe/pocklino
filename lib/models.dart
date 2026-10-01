/// The five useful shapes of a Pocklino page.
enum EntryKind { note, checklist, movie, trip, letter }

class CheckItem {
  const CheckItem({required this.id, required this.text, this.done = false});

  final String id;
  final String text;
  final bool done;

  CheckItem copyWith({String? id, String? text, bool? done}) => CheckItem(
    id: id ?? this.id,
    text: text ?? this.text,
    done: done ?? this.done,
  );

  Map<String, Object?> toJson() => {'id': id, 'text': text, 'done': done};

  factory CheckItem.fromJson(Map<String, dynamic> json) => CheckItem(
    id: _string(json, 'id', max: 128, nonempty: true),
    text: _string(json, 'text', max: 4000),
    done: _boolean(json, 'done'),
  );
}

class PocketEntry {
  PocketEntry({
    required this.id,
    required this.title,
    required this.kind,
    required this.createdAt,
    required this.updatedAt,
    this.body = '',
    this.emoji = '📝',
    this.collection = 'Everyday',
    this.colorIndex = 0,
    this.pinned = false,
    this.archived = false,
    List<CheckItem> items = const [],
    this.url = '',
    this.date,
    this.endDate,
    this.unlockAt,
    this.recipient = '',
    this.sender = '',
    this.received = false,
    this.watched = false,
    this.isExample = false,
  }) : items = List.unmodifiable(items);

  final String id;
  final String title;
  final String body;
  final EntryKind kind;
  final String emoji;
  final String collection;
  final int colorIndex;
  final bool pinned;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<CheckItem> items;
  final String url;
  final DateTime? date;
  final DateTime? endDate;
  final DateTime? unlockAt;
  final String recipient;
  final String sender;
  final bool received;
  final bool watched;
  final bool isExample;

  /// A friendly reveal date, enforced by the app and the device's local clock.
  /// It is not cryptographic access control: a recipient owns the transferred data.
  bool get isLocked =>
      received && unlockAt != null && DateTime.now().isBefore(unlockAt!);
  double get completion =>
      items.isEmpty
          ? 0
          : items.where((item) => item.done).length / items.length;

  PocketEntry copyWith({
    String? id,
    String? title,
    String? body,
    EntryKind? kind,
    String? emoji,
    String? collection,
    int? colorIndex,
    bool? pinned,
    bool? archived,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<CheckItem>? items,
    String? url,
    DateTime? date,
    DateTime? endDate,
    DateTime? unlockAt,
    bool clearDate = false,
    bool clearEndDate = false,
    bool clearUnlockAt = false,
    String? recipient,
    String? sender,
    bool? received,
    bool? watched,
    bool? isExample,
  }) => PocketEntry(
    id: id ?? this.id,
    title: title ?? this.title,
    body: body ?? this.body,
    kind: kind ?? this.kind,
    emoji: emoji ?? this.emoji,
    collection: collection ?? this.collection,
    colorIndex: colorIndex ?? this.colorIndex,
    pinned: pinned ?? this.pinned,
    archived: archived ?? this.archived,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    items: items ?? this.items,
    url: url ?? this.url,
    date: clearDate ? null : date ?? this.date,
    endDate: clearEndDate ? null : endDate ?? this.endDate,
    unlockAt: clearUnlockAt ? null : unlockAt ?? this.unlockAt,
    recipient: recipient ?? this.recipient,
    sender: sender ?? this.sender,
    received: received ?? this.received,
    watched: watched ?? this.watched,
    isExample: isExample ?? this.isExample,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'kind': kind.name,
    'emoji': emoji,
    'collection': collection,
    'colorIndex': colorIndex,
    'pinned': pinned,
    'archived': archived,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'items': items.map((item) => item.toJson()).toList(),
    'url': url,
    'date': date?.toUtc().toIso8601String(),
    'endDate': endDate?.toUtc().toIso8601String(),
    'unlockAt': unlockAt?.toUtc().toIso8601String(),
    'recipient': recipient,
    'sender': sender,
    'received': received,
    'watched': watched,
    'isExample': isExample,
  };

  factory PocketEntry.fromJson(Map<String, dynamic> json) {
    final kindName = _string(json, 'kind', max: 24, nonempty: true);
    final kinds = EntryKind.values.where((kind) => kind.name == kindName);
    if (kinds.isEmpty) {
      throw const FormatException('This note has an unsupported type.');
    }
    final color = json['colorIndex'] ?? 0;
    if (color is! int || color < 0 || color > 255) {
      throw const FormatException('This note has an invalid color.');
    }
    final rawItems = json['items'] ?? <dynamic>[];
    if (rawItems is! List || rawItems.length > 1000) {
      throw const FormatException('A list can contain at most 1,000 items.');
    }
    final items =
        rawItems.map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException(
              'This note contains an invalid list item.',
            );
          }
          return CheckItem.fromJson(item);
        }).toList();
    if (items.map((item) => item.id).toSet().length != items.length) {
      throw const FormatException(
        'This note contains duplicate list item identifiers.',
      );
    }
    return PocketEntry(
      id: _string(json, 'id', max: 128, nonempty: true),
      title: _string(json, 'title', max: 500),
      body: _string(json, 'body', max: 200000, fallback: ''),
      kind: kinds.first,
      emoji: _string(json, 'emoji', max: 64, fallback: '📝'),
      collection: _string(
        json,
        'collection',
        max: 120,
        nonempty: true,
        fallback: 'Everyday',
      ),
      colorIndex: color,
      pinned: _boolean(json, 'pinned'),
      archived: _boolean(json, 'archived'),
      createdAt: _date(json, 'createdAt', required: true)!,
      updatedAt: _date(json, 'updatedAt', required: true)!,
      items: items,
      url: _string(json, 'url', max: 8000, fallback: ''),
      date: _date(json, 'date'),
      endDate: _date(json, 'endDate'),
      unlockAt: _date(json, 'unlockAt'),
      recipient: _string(json, 'recipient', max: 500, fallback: ''),
      sender: _string(json, 'sender', max: 500, fallback: ''),
      received: _boolean(json, 'received'),
      watched: _boolean(json, 'watched'),
      isExample: _boolean(json, 'isExample'),
    );
  }
}

String _string(
  Map<String, dynamic> json,
  String key, {
  required int max,
  bool nonempty = false,
  String? fallback,
}) {
  final value = json[key] ?? fallback;
  if (value is! String ||
      value.length > max ||
      (nonempty && value.trim().isEmpty)) {
    throw FormatException('This note has an invalid $key field.');
  }
  return value;
}

bool _boolean(Map<String, dynamic> json, String key) {
  final value = json[key] ?? false;
  if (value is! bool) {
    throw FormatException('This note has an invalid $key field.');
  }
  return value;
}

DateTime? _date(
  Map<String, dynamic> json,
  String key, {
  bool required = false,
}) {
  final value = json[key];
  if (value == null && !required) return null;
  if (value is! String || value.length > 40) {
    throw FormatException('This note has an invalid $key date.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || parsed.year < 1900 || parsed.year > 9999) {
    throw FormatException('This note has an invalid $key date.');
  }
  return parsed;
}
