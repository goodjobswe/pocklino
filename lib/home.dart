import 'dart:async';
import 'package:flutter/material.dart';
import 'design.dart';
import 'editor.dart';
import 'models.dart';
import 'settings.dart';
import 'sharing.dart';
import 'store.dart';
import 'ui_helpers.dart';

class PocketHome extends StatefulWidget {
  const PocketHome({super.key, required this.store});
  final AppStore store;
  @override
  State<PocketHome> createState() => _PocketHomeState();
}

class _PocketHomeState extends State<PocketHome> {
  int page = 0;
  EntryKind? filter;
  String search = '';
  String? collection;
  bool archived = false;
  Timer? clock;
  AppStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    clock?.cancel();
    super.dispose();
  }

  Future<void> act(Future<dynamic> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        toast(context, 'That change could not be saved. Please try again.');
      }
    }
  }

  void edit(PocketEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EntryEditor(store: store, entry: entry),
      ),
    );
  }

  Future<void> create() async {
    final kind = await showModalBottomSheet<EntryKind>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 540),
      builder:
          (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Make room for something.',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  const Text('Big plans. Small thoughts. All welcome here.'),
                  const SizedBox(height: 20),
                  for (final kind in EntryKind.values)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color:
                              PocklinoColors.cardColors[kind.index %
                                  PocklinoColors.cardColors.length],
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(kind.icon, color: PocklinoColors.ink),
                      ),
                      title: Text(
                        kind.label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(kind.hint),
                      trailing: const Icon(
                        Icons.arrow_forward_rounded,
                        size: 19,
                      ),
                      onTap: () => Navigator.pop(context, kind),
                    ),
                ],
              ),
            ),
          ),
    );
    if (kind != null && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder:
              (_) =>
                  EntryEditor(store: store, kind: kind, collection: collection),
        ),
      );
    }
  }

  Future<void> addCollection() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('A new little collection'),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: 'Collection name',
                hintText: 'Weekend adventures',
              ),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('Create'),
              ),
            ],
          ),
    );
    controller.dispose();
    if (value != null && value.trim().isNotEmpty) {
      await act(() => store.addCollection(value.trim()));
    }
  }

  Future<void> remove(PocketEntry entry) async {
    try {
      await store.remove(entry.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('“${entry.title}” removed'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => act(() => store.upsert(entry)),
          ),
        ),
      );
    } catch (_) {
      if (mounted) toast(context, 'This item could not be removed.');
    }
  }

  void menu(PocketEntry entry, String action) {
    switch (action) {
      case 'pin':
        act(() => store.upsert(entry.copyWith(pinned: !entry.pinned)));
      case 'pass':
        showPassSheet(context, entry);
      case 'copy':
        act(() => store.duplicate(entry));
      case 'archive':
        act(() => store.upsert(entry.copyWith(archived: !entry.archived)));
      case 'delete':
        remove(entry);
    }
  }

  List<PocketEntry> get visibleEntries {
    final query = search.toLowerCase().trim();
    return store.entries.where((entry) {
        if (entry.archived != archived) return false;
        if (page == 2 &&
            (entry.kind != EntryKind.letter || entry.unlockAt == null)) {
          return false;
        }
        if (filter != null && entry.kind != filter) return false;
        if (collection != null && entry.collection != collection) return false;
        final text =
            entry.isLocked
                ? '${entry.title} ${entry.collection}'
                : '${entry.title} ${entry.body} ${entry.collection} ${entry.items.map((item) => item.text).join(' ')}';
        return query.isEmpty || text.toLowerCase().contains(query);
      }).toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final wide = MediaQuery.sizeOf(context).width >= 900;
        final entries = visibleEntries;
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                if (wide) sidebar(),
                Expanded(
                  child: Column(
                    children: [
                      topbar(wide),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1180),
                            child: ListView(
                              padding: EdgeInsets.fromLTRB(
                                wide ? 44 : 20,
                                wide ? 25 : 12,
                                wide ? 44 : 20,
                                112,
                              ),
                              children: [
                                header(wide),
                                const SizedBox(height: 27),
                                if (page == 1 &&
                                    collection == null &&
                                    !archived) ...[
                                  collectionBoard(),
                                ] else ...[
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          onChanged:
                                              (value) => setState(
                                                () => search = value,
                                              ),
                                          decoration: InputDecoration(
                                            hintText:
                                                'Find a little something…',
                                            prefixIcon: const Icon(
                                              Icons.search_rounded,
                                              size: 22,
                                            ),
                                            filled: true,
                                            fillColor:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.surface,
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              borderSide: BorderSide.none,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      IconButton.filledTonal(
                                        tooltip:
                                            archived
                                                ? 'Show your pocket'
                                                : 'Open archive',
                                        onPressed:
                                            () => setState(
                                              () => archived = !archived,
                                            ),
                                        icon: Icon(
                                          archived
                                              ? Icons.inventory_2_rounded
                                              : Icons.inventory_2_outlined,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  if (page != 2) filters(),
                                  const SizedBox(height: 24),
                                  Row(
                                    children: [
                                      SmallLabel(
                                        archived
                                            ? 'Safely tucked away'
                                            : 'Your little things',
                                      ),
                                      const Spacer(),
                                      Text(
                                        entries.length.toString() +
                                            (entries.length == 1
                                                ? ' item'
                                                : ' items'),
                                        style:
                                            Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  if (entries.isEmpty)
                                    emptyState()
                                  else
                                    board(entries),
                                  if (store.entries.any(
                                    (entry) => entry.isExample,
                                  )) ...[
                                    const SizedBox(height: 28),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.auto_awesome_outlined,
                                          size: 17,
                                        ),
                                        const SizedBox(width: 8),
                                        const Expanded(
                                          child: Text(
                                            'You’re exploring example items.',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed:
                                              () => act(store.clearExamples),
                                          child: const Text('Clear examples'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                                const SizedBox(height: 36),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.phone_iphone_rounded,
                                      size: 14,
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        'On your device. Yours to keep.',
                                        textAlign: TextAlign.center,
                                        style:
                                            Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          floatingActionButton:
              store.entries.isEmpty &&
                      page == 0 &&
                      !archived &&
                      collection == null
                  ? null
                  : FloatingActionButton.extended(
                    onPressed: create,
                    tooltip: 'Create something',
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Create'),
                  ),
          bottomNavigationBar:
              wide
                  ? null
                  : NavigationBar(
                    selectedIndex: page,
                    onDestinationSelected: selectPage,
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.grid_view_rounded),
                        label: 'My pocket',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.folder_outlined),
                        label: 'Collections',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.mark_email_unread_outlined),
                        label: 'Open later',
                      ),
                    ],
                  ),
        );
      },
    );
  }

  void selectPage(int value) => setState(() {
    page = value;
    collection = null;
    archived = false;
    filter = null;
    search = '';
  });

  Widget topbar(bool wide) => Padding(
    padding: EdgeInsets.fromLTRB(wide ? 38 : 16, 12, wide ? 38 : 12, 6),
    child: Row(
      children: [
        if (!wide) ...[
          const PocketMark(size: 38),
          const SizedBox(width: 7),
          const Text(
            'pocklino',
            style: TextStyle(
              fontFamily: 'Lora',
              fontSize: 23,
              fontWeight: FontWeight.w600,
              letterSpacing: -1,
            ),
          ),
        ] else
          Row(
            children: [
              Icon(Icons.circle, size: 7, color: PocklinoColors.success),
              const SizedBox(width: 8),
              const SmallLabel('A space that’s only yours'),
            ],
          ),
        const Spacer(),
        IconButton(
          tooltip: 'Receive a note',
          onPressed: () => showReceiveSheet(context, store),
          icon: const Icon(Icons.qr_code_scanner_rounded),
        ),
        IconButton(
          tooltip: 'Settings',
          onPressed:
              () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => SettingsPage(store: store),
                ),
              ),
          icon: const Icon(Icons.tune_rounded),
        ),
      ],
    ),
  );

  Widget sidebar() => Container(
    width: 230,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border(
        right: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: .3),
        ),
      ),
    ),
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            PocketMark(size: 42),
            SizedBox(width: 8),
            Text(
              'pocklino',
              style: TextStyle(
                fontFamily: 'Lora',
                fontSize: 26,
                letterSpacing: -1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(left: 7, top: 10),
          child: Text(
            'A little space for your life.',
            style: TextStyle(fontSize: 11),
          ),
        ),
        const SizedBox(height: 42),
        for (final (index, icon, label) in [
          (0, Icons.grid_view_rounded, 'My pocket'),
          (1, Icons.folder_outlined, 'Collections'),
          (2, Icons.mark_email_unread_outlined, 'Open later'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: ListTile(
              dense: true,
              selected: page == index,
              selectedTileColor: PocklinoColors.butter.withValues(alpha: .45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: Icon(icon, size: 20),
              title: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () => selectPage(index),
            ),
          ),
        const SizedBox(height: 26),
        const Padding(
          padding: EdgeInsets.only(left: 12),
          child: SmallLabel('Collections'),
        ),
        const SizedBox(height: 10),
        for (final name in store.collections.take(6))
          ListTile(
            dense: true,
            leading: Icon(
              Icons.circle,
              size: 8,
              color:
                  PocklinoColors.cardColors[store.collections.indexOf(name) %
                      PocklinoColors.cardColors.length],
            ),
            title: Text(name, overflow: TextOverflow.ellipsis),
            onTap:
                () => setState(() {
                  page = 1;
                  collection = name;
                  filter = null;
                  archived = false;
                }),
          ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: PocklinoColors.mint,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.qr_code_rounded, color: PocklinoColors.ink),
              const SizedBox(height: 9),
              const Text(
                'Good things are\nnice to pass on.',
                style: TextStyle(
                  fontFamily: 'Lora',
                  color: PocklinoColors.ink,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  foregroundColor: PocklinoColors.ink,
                ),
                onPressed: () => showReceiveSheet(context, store),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Receive a note'),
                    SizedBox(width: 7),
                    Icon(Icons.arrow_forward_rounded, size: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget header(bool wide) {
    final title =
        archived
            ? 'Tucked away.'
            : collection ??
                switch (page) {
                  1 => 'A place for everything.',
                  2 => 'Good things take time.',
                  _ =>
                    store.ownerName.trim().isEmpty
                        ? 'Your little world.'
                        : '${store.ownerName}’s little world.',
                };
    final subtitle =
        archived
            ? 'Still yours. Just a little out of the way.'
            : page == 2
            ? 'Little envelopes for moments worth waiting for.'
            : page == 1
            ? 'Gather your plans, favorites, and everyday things.'
            : 'Plans, lists & lovely little things. All in your pocket.';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (collection != null)
                TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: () => setState(() => collection = null),
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: const Text('All collections'),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SmallLabel(
                    page == 2
                        ? 'A little anticipation'
                        : 'Make yourself at home',
                  ),
                ),
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Lora',
                  fontSize: wide ? 41 : 31,
                  height: 1.18,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -1.3,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: wide ? 15 : 13,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (wide)
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Transform.rotate(
              angle: .06,
              child: const PocketMark(size: 108),
            ),
          ),
      ],
    );
  }

  Widget filters() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        filterChip(null, 'Everything'),
        for (final kind in EntryKind.values) filterChip(kind, kind.plural),
      ],
    ),
  );

  Widget filterChip(EntryKind? kind, String label) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: filter == kind,
      showCheckmark: false,
      onSelected: (_) => setState(() => filter = kind),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
  );

  Widget board(List<PocketEntry> entries) => LayoutBuilder(
    builder: (context, constraints) {
      final count =
          constraints.maxWidth >= 820
              ? 3
              : constraints.maxWidth >= 340
              ? 2
              : 1;
      const gap = 16.0;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int column = 0; column < count; column++) ...[
            if (column > 0) const SizedBox(width: gap),
            Expanded(
              child: Column(
                children: [
                  for (
                    int index = column;
                    index < entries.length;
                    index += count
                  )
                    Padding(
                      padding: const EdgeInsets.only(bottom: gap),
                      child: entryCard(entries[index]),
                    ),
                ],
              ),
            ),
          ],
        ],
      );
    },
  );

  Widget entryCard(PocketEntry entry) {
    final locked = entry.isLocked;
    return Material(
      color: entryColor(entry),
      borderRadius: BorderRadius.circular(21),
      child: InkWell(
        borderRadius: BorderRadius.circular(21),
        onTap: () => edit(entry),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 219),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(17, 11, 13, 17),
            child: DefaultTextStyle(
              style: const TextStyle(
                fontFamily: 'DMSans',
                fontFamilyFallback: ['NotoEmoji', 'Roboto'],
                color: PocklinoColors.ink,
                fontSize: 13,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        locked ? Icons.lock_outline_rounded : entry.kind.icon,
                        size: 19,
                        color: PocklinoColors.ink,
                      ),
                      if (entry.pinned)
                        const Padding(
                          padding: EdgeInsets.only(left: 7),
                          child: Icon(
                            Icons.push_pin_rounded,
                            size: 12,
                            color: PocklinoColors.ink,
                          ),
                        ),
                      const Spacer(),
                      PopupMenuButton<String>(
                        tooltip: 'Item actions',
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.more_horiz_rounded,
                          color: PocklinoColors.ink,
                        ),
                        onSelected: (action) => menu(entry, action),
                        itemBuilder:
                            (_) => [
                              PopupMenuItem(
                                value: 'pin',
                                child: Text(
                                  entry.pinned ? 'Unpin' : 'Pin to top',
                                ),
                              ),
                              if (!locked)
                                const PopupMenuItem(
                                  value: 'pass',
                                  child: Text('Pass a copy'),
                                ),
                              if (!locked)
                                const PopupMenuItem(
                                  value: 'copy',
                                  child: Text('Make a copy'),
                                ),
                              PopupMenuItem(
                                value: 'archive',
                                child: Text(
                                  entry.archived ? 'Bring back' : 'Archive',
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ],
                      ),
                    ],
                  ),
                  if (entry.kind == EntryKind.letter) ...[
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          locked ? '💌' : entry.emoji,
                          style: const TextStyle(
                            fontFamily: 'NotoEmoji',
                            fontSize: 37,
                          ),
                        ),
                      ),
                    ),
                  ] else if (entry.kind == EntryKind.trip) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        entry.emoji,
                        style: const TextStyle(
                          fontFamily: 'NotoEmoji',
                          fontSize: 32,
                        ),
                      ),
                    ),
                  ],
                  Text(
                    entry.title.isEmpty
                        ? 'Untitled ${entry.kind.label.toLowerCase()}'
                        : entry.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Lora',
                      fontSize: 21,
                      height: 1.22,
                      color: PocklinoColors.ink,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (locked)
                    Text(
                      'Opens ${niceTime(entry.unlockAt!)}',
                      style: const TextStyle(fontSize: 12, height: 1.5),
                    )
                  else if (entry.kind == EntryKind.checklist ||
                      entry.kind == EntryKind.trip &&
                          entry.items.isNotEmpty) ...[
                    for (final item in entry.items.take(4))
                      InkWell(
                        borderRadius: BorderRadius.circular(5),
                        onTap:
                            () =>
                                act(() => store.toggleItem(entry.id, item.id)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                item.done
                                    ? Icons.check_box_rounded
                                    : Icons.check_box_outline_blank_rounded,
                                size: 17,
                                color: PocklinoColors.ink.withValues(
                                  alpha: item.done ? .45 : .8,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  item.text,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    height: 1.3,
                                    fontSize: 12,
                                    color: PocklinoColors.ink.withValues(
                                      alpha: item.done ? .5 : 1,
                                    ),
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
                    if (entry.items.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value:
                                entry.items.where((e) => e.done).length /
                                entry.items.length,
                            minHeight: 3,
                            color: PocklinoColors.ink.withValues(alpha: .55),
                            backgroundColor: PocklinoColors.ink.withValues(
                              alpha: .08,
                            ),
                          ),
                        ),
                      ),
                  ] else ...[
                    if (entry.body.isNotEmpty)
                      Text(
                        entry.body,
                        maxLines: entry.kind == EntryKind.note ? 5 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(height: 1.7),
                      ),
                    if (entry.kind == EntryKind.movie) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Icon(
                            entry.watched
                                ? Icons.check_circle_outline
                                : Icons.play_circle_outline_rounded,
                            size: 15,
                            color: PocklinoColors.ink,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              entry.watched
                                  ? 'Watched'
                                  : 'Movie night material',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                  if (entry.kind == EntryKind.trip && entry.date != null) ...[
                    const SizedBox(height: 9),
                    Text(
                      niceDate(entry.date!),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.collection.toUpperCase(),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 1.3,
                            fontWeight: FontWeight.w700,
                            color: PocklinoColors.ink.withValues(alpha: .65),
                          ),
                        ),
                      ),
                      if (entry.isExample)
                        const Text(
                          'EXAMPLE',
                          style: TextStyle(fontSize: 8, letterSpacing: .5),
                        ),
                      if (entry.received && !entry.isExample)
                        const Icon(
                          Icons.call_received_rounded,
                          size: 12,
                          color: PocklinoColors.ink,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget emptyState() {
    final isNew =
        store.entries.isEmpty &&
        search.isEmpty &&
        filter == null &&
        collection == null &&
        page == 0 &&
        !archived;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 42),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: .25),
        ),
      ),
      child: Column(
        children: [
          const PocketMark(size: 100),
          const SizedBox(height: 22),
          Text(
            isNew
                ? 'Start with one little thing.'
                : page == 2
                ? 'A little surprise belongs here.'
                : 'A little room to grow.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 10),
          Text(
            isNew
                ? 'A thought, a list, a place to go.\nNo account. Just you and your pocket.'
                : search.isNotEmpty
                ? 'Nothing matches this search. Try a different word.'
                : page == 2
                ? 'Create a little note and choose an opening time,\nor receive an envelope from someone you love.'
                : 'Create something new, or try another filter.',
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.7),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: create,
            icon: const Icon(Icons.add_rounded),
            label: Text(isNew ? 'Create your first item' : 'Create something'),
          ),
          if (isNew)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: TextButton(
                onPressed: () => act(store.addExamples),
                child: const Text('Take a peek at an example pocket'),
              ),
            ),
        ],
      ),
    );
  }

  Widget collectionBoard() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(child: SmallLabel('Give your things a home')),
          TextButton.icon(
            onPressed: addCollection,
            icon: const Icon(Icons.add_rounded),
            label: const Text('New collection'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      for (int i = 0; i < store.collections.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color:
                PocklinoColors.cardColors[i % PocklinoColors.cardColors.length],
            borderRadius: BorderRadius.circular(20),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 22,
                vertical: 16,
              ),
              leading: const Icon(
                Icons.folder_outlined,
                color: PocklinoColors.ink,
                size: 30,
              ),
              title: Text(
                store.collections[i],
                style: const TextStyle(
                  fontFamily: 'Lora',
                  fontSize: 22,
                  color: PocklinoColors.ink,
                ),
              ),
              subtitle: Text(
                '${store.entries.where((e) => e.collection == store.collections[i] && !e.archived).length} little things',
                style: const TextStyle(color: PocklinoColors.ink),
              ),
              trailing: const Icon(
                Icons.arrow_forward_rounded,
                color: PocklinoColors.ink,
              ),
              onTap: () => setState(() => collection = store.collections[i]),
              onLongPress:
                  store.collections[i] == 'Everyday'
                      ? null
                      : () async {
                        final name = store.collections[i];
                        final yes = await showDialog<bool>(
                          context: context,
                          builder:
                              (ctx) => AlertDialog(
                                title: Text('Remove “$name”?'),
                                content: const Text(
                                  'Your items will move to Everyday. Nothing will be deleted.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Keep it'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Remove collection'),
                                  ),
                                ],
                              ),
                        );
                        if (yes == true) {
                          await act(() => store.deleteCollection(name));
                        }
                      },
            ),
          ),
        ),
    ],
  );
}
