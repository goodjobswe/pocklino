import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'storage/database.dart';

/// A local, transactionally persisted notebook. Nothing leaves this store
/// unless the user explicitly exports or shares it.
class AppStore extends ChangeNotifier {
  AppStore({Database? database}) : _database = database;

  // A restore reads its whole file into memory, so the file needs a bound.
  // An export has none: whatever the notebook holds can always be saved.
  static const maxRestoreBytes = 50 * 1024 * 1024;
  static const maxEntries = 10000;
  static const defaultCollections = [
    'Everyday',
    'Watchlist',
    'Adventures',
    'Little joys',
  ];

  /// How long each frame of an animated sharing code can stay on screen, in
  /// milliseconds, from slowest to fastest.
  static const sharingSpeeds = [
    2000,
    1500,
    1000,
    700,
    500,
    400,
    300,
    200,
    150,
    100,
  ];
  static const defaultSharingSpeed = 500;
  static const _uuid = Uuid();
  static final _record = stringMapStoreFactory
      .store('pocklino')
      .record('state');

  Database? _database;
  Future<void>? _initialization;
  Future<void> _tail = Future<void>.value();
  List<PocketEntry> _entries = [];
  List<String> _collections = [...defaultCollections];
  String _ownerName = '';
  String _themePreference = 'system';
  int _sharingSpeed = defaultSharingSpeed;

  List<PocketEntry> get entries => List.unmodifiable(_entries);
  List<String> get collections => List.unmodifiable(_collections);
  String get ownerName => _ownerName;
  String get themePreference => _themePreference;

  /// One of [sharingSpeeds], as last chosen on the pass sheet.
  int get sharingSpeed => _sharingSpeed;

  Future<void> initialize() =>
      _initialization ??= _initialize().catchError((
        Object error,
        StackTrace stack,
      ) {
        _initialization = null;
        Error.throwWithStackTrace(error, stack);
      });

  Future<void> _initialize() async {
    _database ??= await openPocketDatabase();
    final state = await _record.get(_database!);
    if (state != null) {
      final parsed = _parseState(Map<String, dynamic>.from(state));
      _entries = parsed.entries;
      _collections = parsed.collections;
      _ownerName = parsed.ownerName;
      _themePreference = parsed.themePreference;
      _sharingSpeed = _nearestSpeed(state['sharingSpeed']);
    }
    notifyListeners();
  }

  /// Serialize user actions so two rapid edits cannot overwrite each other.
  Future<T> _mutate<T>(Future<T> Function() action) async {
    await initialize();
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _save({
    required List<PocketEntry> entries,
    List<String>? collections,
    String? ownerName,
    String? themePreference,
    int? sharingSpeed,
  }) async {
    if (entries.length > maxEntries) {
      throw const FormatException(
        'This notebook can hold at most 10,000 pages.',
      );
    }
    final nextCollections = [...(collections ?? _collections)];
    for (final entry in entries) {
      if (!nextCollections.contains(entry.collection)) {
        nextCollections.add(entry.collection);
      }
    }
    if (nextCollections.length > 1000) {
      throw const FormatException(
        'This notebook can hold at most 1,000 collections.',
      );
    }
    final nextName = ownerName ?? _ownerName;
    final nextTheme = themePreference ?? _themePreference;
    final nextSpeed = sharingSpeed ?? _sharingSpeed;
    final state = <String, Object?>{
      'version': 1,
      'entries': entries.map((entry) => entry.toJson()).toList(),
      'collections': nextCollections,
      'ownerName': nextName,
      'themePreference': nextTheme,
      'sharingSpeed': nextSpeed,
    };
    await _database!.transaction((txn) => _record.put(txn, state));
    _entries = List.of(entries);
    _collections = nextCollections;
    _ownerName = nextName;
    _themePreference = nextTheme;
    _sharingSpeed = nextSpeed;
    notifyListeners();
  }

  Future<void> upsert(PocketEntry entry) => _mutate(() async {
    // Apply the same validation to edits and imported data.
    final valid = PocketEntry.fromJson(entry.toJson());
    final next = [..._entries];
    final index = next.indexWhere((item) => item.id == valid.id);
    if (index < 0) {
      next.add(valid);
    } else {
      next[index] = valid;
    }
    await _save(entries: next);
  });

  Future<void> remove(String id) => _mutate(() async {
    await _save(entries: _entries.where((entry) => entry.id != id).toList());
  });

  /// Delete every archived page. Returns them, so the caller can offer to
  /// [putBack] what was removed.
  Future<List<PocketEntry>> clearArchive() => _mutate(() async {
    final removed = _entries.where((entry) => entry.archived).toList();
    if (removed.isNotEmpty) {
      await _save(entries: _entries.where((entry) => !entry.archived).toList());
    }
    return removed;
  });

  /// Delete every page and every collection that was added. The name, the
  /// look and the sharing speed stay.
  Future<void> clearAll() => _mutate(() async {
    await _save(entries: const [], collections: defaultCollections);
  });

  /// Undo a clear: pages come back unless their place has been taken.
  Future<void> putBack(
    List<PocketEntry> entries, {
    List<String> collections = const [],
  }) => _mutate(() async {
    final present = {for (final entry in _entries) entry.id};
    await _save(
      entries: [
        ..._entries,
        ...entries.where((entry) => !present.contains(entry.id)),
      ],
      collections: {..._collections, ...collections}.toList(),
    );
  });

  Future<PocketEntry> duplicate(PocketEntry entry) => _mutate(() async {
    if (entry.isLocked) {
      throw const FormatException(
        'This little surprise is not ready to open yet.',
      );
    }
    final now = DateTime.now();
    final title =
        entry.title.length > 492 ? entry.title.substring(0, 492) : entry.title;
    final copy = entry.copyWith(
      id: _uuid.v4(),
      title: '$title (copy)',
      createdAt: now,
      updatedAt: now,
      pinned: false,
      archived: false,
      received: false,
      isExample: false,
      items: entry.items.map((item) => item.copyWith(id: _uuid.v4())).toList(),
    );
    await _save(entries: [..._entries, copy]);
    return copy;
  });

  Future<void> toggleItem(String entryId, String itemId) => _mutate(() async {
    final index = _entries.indexWhere((entry) => entry.id == entryId);
    if (index < 0) return;
    final entry = _entries[index];
    if (entry.isLocked) {
      throw const FormatException('This surprise is still sealed.');
    }
    final items =
        entry.items
            .map(
              (item) =>
                  item.id == itemId ? item.copyWith(done: !item.done) : item,
            )
            .toList();
    final next = [..._entries];
    next[index] = entry.copyWith(items: items, updatedAt: DateTime.now());
    await _save(entries: next);
  });

  Future<void> addCollection(String name) => _mutate(() async {
    final trimmed = _validateCollection(name);
    if (_collections.any(
      (item) => item.toLowerCase() == trimmed.toLowerCase(),
    )) {
      return;
    }
    await _save(entries: _entries, collections: [..._collections, trimmed]);
  });

  Future<void> deleteCollection(String name) => _mutate(() async {
    if (name == 'Everyday') {
      throw const FormatException('Everyday is your default collection.');
    }
    final now = DateTime.now();
    await _save(
      entries:
          _entries
              .map(
                (entry) =>
                    entry.collection == name
                        ? entry.copyWith(collection: 'Everyday', updatedAt: now)
                        : entry,
              )
              .toList(),
      collections: _collections.where((item) => item != name).toList(),
    );
  });

  Future<void> updateSettings({
    String? ownerName,
    String? themePreference,
    int? sharingSpeed,
  }) => _mutate(() async {
    if (ownerName != null && ownerName.length > 100) {
      throw const FormatException(
        'Please use a name with 100 characters or fewer.',
      );
    }
    if (themePreference != null &&
        !['system', 'light', 'dark'].contains(themePreference)) {
      throw const FormatException(
        'Choose a system, light, or dark appearance.',
      );
    }
    await _save(
      entries: _entries,
      ownerName: ownerName?.trim(),
      themePreference: themePreference,
      sharingSpeed: sharingSpeed == null ? null : _nearestSpeed(sharingSpeed),
    );
  });

  Future<PocketEntry> importEntry(PocketEntry entry) => _mutate(() async {
    final valid = PocketEntry.fromJson(entry.toJson());
    final copy = valid.copyWith(
      id: _uuid.v4(),
      received: true,
      isExample: false,
      pinned: false,
      archived: false,
      updatedAt: DateTime.now(),
      items: valid.items.map((item) => item.copyWith(id: _uuid.v4())).toList(),
    );
    await _save(entries: [..._entries, copy]);
    return copy;
  });

  String exportBackup() {
    return jsonEncode({
      'format': 'pocklino-backup',
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'entries': _entries.map((entry) => entry.toJson()).toList(),
      'collections': _collections,
      'ownerName': _ownerName,
      'themePreference': _themePreference,
    });
  }

  /// Validate everything before writing. Exact matches are skipped; a changed
  /// page with an existing ID is preserved as a new copy. Existing pages are
  /// never removed. Preferences restore only into an otherwise empty notebook.
  Future<int> restoreBackup(String source) => _mutate(() async {
    // The file reader bounds the bytes. A string is never longer than those.
    if (source.length > maxRestoreBytes) {
      throw const FormatException(
        'Choose a Pocklino backup smaller than 50 MB.',
      );
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException(
        'This file is not a readable Pocklino backup.',
      );
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'pocklino-backup') {
      throw const FormatException('Choose a Pocklino backup file.');
    }
    final backup = _parseState(decoded);
    final next = [..._entries];
    final byId = {for (final entry in next) entry.id: entry};
    var added = 0;
    for (final entry in backup.entries) {
      final existing = byId[entry.id];
      if (existing != null &&
          jsonEncode(existing.toJson()) == jsonEncode(entry.toJson())) {
        continue;
      }
      final restored =
          existing == null ? entry : entry.copyWith(id: _uuid.v4());
      next.add(restored);
      byId[restored.id] = restored;
      added++;
    }
    final restorePreferences = _entries.isEmpty && _ownerName.isEmpty;
    await _save(
      entries: next,
      collections: {..._collections, ...backup.collections}.toList(),
      ownerName: restorePreferences ? backup.ownerName : null,
      themePreference: restorePreferences ? backup.themePreference : null,
    );
    return added;
  });

  Future<void> addExamples() => _mutate(() async {
    if (_entries.any((entry) => entry.isExample)) return;
    final now = DateTime.now();
    PocketEntry example(
      String title,
      EntryKind kind, {
      String body = '',
      String emoji = '📝',
      int color = 0,
      String collection = 'Everyday',
      List<String> items = const [],
      String url = '',
      DateTime? date,
      DateTime? endDate,
      DateTime? unlockAt,
      String recipient = '',
      String sender = '',
      bool pinned = false,
    }) => PocketEntry(
      id: _uuid.v4(),
      title: title,
      kind: kind,
      body: body,
      emoji: emoji,
      collection: collection,
      colorIndex: color,
      createdAt: now,
      updatedAt: now,
      items:
          items.map((text) => CheckItem(id: _uuid.v4(), text: text)).toList(),
      url: url,
      date: date,
      endDate: endDate,
      unlockAt: unlockAt,
      recipient: recipient,
      sender: sender,
      pinned: pinned,
      isExample: true,
    );
    final examples = [
      example(
        'A little space for your life',
        EntryKind.note,
        emoji: '✨',
        color: 3,
        pinned: true,
        body:
            'Big plans. Tiny reminders. Things that make you smile.\n\nMake yourself at home. This space is yours. Create a page, give it a little personality, and pass it to someone you love.\n\nThese are sample pages. You can edit them or remove all examples in Settings.',
      ),
      example(
        'Something good for dinner',
        EntryKind.checklist,
        emoji: '🥑',
        color: 1,
        items: [
          'Avocados',
          'Cherry tomatoes',
          'Fresh sourdough',
          'Burrata',
          'Something sweet',
        ],
      ),
      example(
        'The Grand Budapest Hotel',
        EntryKind.movie,
        emoji: '🍿',
        color: 4,
        collection: 'Watchlist',
        body:
            'For a rainy evening, with a big bowl of popcorn.\nA little adventure, a lot of pink.',
        url: 'https://www.imdb.com/title/tt2278388/',
      ),
      example(
        'A weekend somewhere new',
        EntryKind.trip,
        emoji: '🧳',
        color: 2,
        collection: 'Adventures',
        body:
            'A slow morning, a tiny café, and no particular rush.\n\nFind somewhere by the water. Leave room for getting lost.',
        date: now.add(const Duration(days: 21)),
        endDate: now.add(const Duration(days: 23)),
        items: [
          'Book a lovely little place',
          'Save a few places to eat',
          'Pack the camera',
        ],
      ),
      example(
        'For your next little adventure',
        EntryKind.letter,
        emoji: '💌',
        color: 0,
        collection: 'Little joys',
        body:
            'A reminder to be a little brave, take the scenic route, and send me a photo. You have got this. 💛',
        recipient: 'Someone special',
        sender: 'Me',
        unlockAt: now.add(const Duration(days: 7)),
      ),
      example(
        'Tiny things, big smiles',
        EntryKind.note,
        emoji: '🌼',
        color: 5,
        collection: 'Little joys',
        body:
            'Warm sheets.\nThe first sip of coffee.\nA song you had forgotten you loved.\nFinding a note in your pocket.',
      ),
    ];
    await _save(entries: [..._entries, ...examples]);
  });

  Future<void> clearExamples() => _mutate(() async {
    await _save(entries: _entries.where((entry) => !entry.isExample).toList());
  });
}

/// A stored speed that is missing or not on the list must never keep the
/// notebook from opening, so it settles on the nearest one instead.
int _nearestSpeed(Object? value) {
  if (value is! int) return AppStore.defaultSharingSpeed;
  return AppStore.sharingSpeeds.reduce(
    (a, b) => (a - value).abs() <= (b - value).abs() ? a : b,
  );
}

String _validateCollection(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty || trimmed.length > 120) {
    throw const FormatException(
      'Collection names need between 1 and 120 characters.',
    );
  }
  return trimmed;
}

class _ParsedState {
  const _ParsedState(
    this.entries,
    this.collections,
    this.ownerName,
    this.themePreference,
  );
  final List<PocketEntry> entries;
  final List<String> collections;
  final String ownerName;
  final String themePreference;
}

_ParsedState _parseState(Map<String, dynamic> state) {
  if (state['version'] != 1) {
    throw const FormatException(
      'This notebook was made with a different version of Pocklino.',
    );
  }
  final rawEntries = state['entries'];
  final rawCollections = state['collections'];
  if (rawEntries is! List ||
      rawEntries.length > AppStore.maxEntries ||
      rawCollections is! List ||
      rawCollections.length > 1000) {
    throw const FormatException(
      'This notebook has invalid pages or collections.',
    );
  }
  final entries =
      rawEntries.map((entry) {
        if (entry is! Map) {
          throw const FormatException(
            'This notebook contains an invalid page.',
          );
        }
        return PocketEntry.fromJson(Map<String, dynamic>.from(entry));
      }).toList();
  if (entries.map((entry) => entry.id).toSet().length != entries.length) {
    throw const FormatException(
      'This notebook contains duplicate page identifiers.',
    );
  }
  final collections = <String>{'Everyday'};
  for (final collection in rawCollections) {
    if (collection is! String) {
      throw const FormatException(
        'This notebook contains an invalid collection.',
      );
    }
    collections.add(_validateCollection(collection));
  }
  for (final entry in entries) {
    collections.add(entry.collection);
  }
  final name = state['ownerName'] ?? '';
  final theme = state['themePreference'] ?? 'system';
  if (name is! String ||
      name.length > 100 ||
      theme is! String ||
      !['system', 'light', 'dark'].contains(theme)) {
    throw const FormatException('This notebook contains invalid preferences.');
  }
  return _ParsedState(entries, collections.toList(), name, theme);
}
