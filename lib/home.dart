import 'dart:async';
import 'package:flutter/material.dart';
import 'design.dart';
import 'editor.dart';
import 'models.dart';
import 'paper.dart';
import 'pocket.dart';
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
  /// An index into [pocketPlaces].
  int page = 0;
  EntryKind? filter;
  String search = '';
  String? collection;
  final searchText = TextEditingController();
  Timer? clock;
  AppStore get store => widget.store;
  bool get archived => page == 3;

  /// How far a card's menu reaches into the paper's right margin.
  static const _menuReach = 12.0;
  bool get collectionList => page == 1 && collection == null;

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
    searchText.dispose();
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
    final choice = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (context) => const _CreateSheet(),
    );
    if (!mounted) return;
    if (choice == _CreateSheet.receive) {
      await showReceiveSheet(context, store);
    } else if (choice case final EntryKind kind) {
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
    final value = await promptText(
      context,
      title: 'New collection',
      label: 'Collection name',
      hint: 'Weekend adventures',
      action: 'Create',
      maxLength: 40,
    );
    if (value != null && value.trim().isNotEmpty) {
      await act(() => store.addCollection(value.trim()));
    }
  }

  Future<void> removeCollection(String name) async {
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
    if (yes == true) await act(() => store.deleteCollection(name));
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

  Future<void> emptyArchive() async {
    final count = store.entries.where((entry) => entry.archived).length;
    final yes = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Empty the archive?'),
            content: Text(
              'This deletes ${count == 1 ? 'the 1 archived page' : 'all $count archived pages'}. '
              'The pages in your pocket stay.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep them'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Empty the archive'),
              ),
            ],
          ),
    );
    if (yes != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final removed = await store.clearArchive();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 10),
          content: const Text('The archive is empty.'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => act(() => store.putBack(removed)),
          ),
        ),
      );
    } catch (_) {
      if (mounted) toast(context, 'The archive could not be emptied.');
    }
  }

  void menu(PocketEntry entry, String action) {
    switch (action) {
      case 'pin':
        act(() => store.upsert(entry.copyWith(pinned: !entry.pinned)));
      case 'pass':
        showPassSheet(context, entry, store: store);
      case 'copy':
        act(() => store.duplicate(entry));
      case 'archive':
        act(() => store.upsert(entry.copyWith(archived: !entry.archived)));
      case 'delete':
        remove(entry);
    }
  }

  void openSettings() => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => SettingsPage(store: store)),
  );

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

  void clearSearch() {
    searchText.clear();
    setState(() => search = '');
  }

  void selectPage(int value) {
    searchText.clear();
    setState(() {
      page = value;
      collection = null;
      filter = null;
      search = '';
    });
  }

  void openCollection(String name) {
    searchText.clear();
    setState(() {
      page = 1;
      collection = name;
      filter = null;
      search = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final width = MediaQuery.sizeOf(context).width;
        final wide = width >= 900;
        // Only a roomy window has space for the search beside the title.
        final inlineSearch = width >= 1120;
        final gutter = wide ? 36.0 : 16.0;
        final entries = visibleEntries;
        final inset = MediaQuery.viewPaddingOf(context).bottom;
        Widget list = SingleChildScrollView(
          key: const ValueKey('board'),
          padding: EdgeInsets.fromLTRB(
            gutter,
            wide ? 28 : 8,
            gutter,
            wide ? 36 + inset : PocketBar.rise + PocketBar.dip + 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header(wide, inlineSearch, entries.length),
              if (collectionList) ...[
                const SizedBox(height: 22),
                collectionBoard(),
              ] else ...[
                if (!inlineSearch) ...[
                  const SizedBox(height: 14),
                  searchField(),
                ],
                if (page != 2) ...[const SizedBox(height: 12), filters(wide)],
                if (archived && store.entries.any((entry) => entry.archived))
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: TextButton.icon(
                        onPressed: emptyArchive,
                        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                        label: const Text('Empty the archive'),
                      ),
                    ),
                  ),
                SizedBox(height: wide ? 26 : 22),
                if (entries.isEmpty) emptyState() else board(entries),
                if (page == 0 && store.entries.any((entry) => entry.isExample))
                  examplesNote(),
              ],
              const SizedBox(height: 26),
              const Center(child: MonoLabel('On your device. Yours to keep.')),
            ],
          ),
        );
        if (!wide) {
          // The list runs under the pocket bar and ends where the pocket's
          // edge dips lowest: pages slide in behind the edge, and whatever
          // still shows above it can be tapped.
          list = Padding(
            padding: EdgeInsets.only(
              bottom: PocketBar.depth - PocketBar.dip + inset,
            ),
            child: list,
          );
        }
        return Scaffold(
          extendBody: true,
          body: SafeArea(
            bottom: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (wide)
                  PocketSidebar(
                    index: page,
                    onSelect: selectPage,
                    onCreate: create,
                    collections: store.collections,
                    collection: collection,
                    onCollection: openCollection,
                    onReceive: () => showReceiveSheet(context, store),
                    onSettings: openSettings,
                  ),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child: list,
                    ),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar:
              wide
                  ? null
                  : PocketBar(
                    index: page,
                    onSelect: selectPage,
                    onCreate: create,
                  ),
        );
      },
    );
  }

  Widget header(bool wide, bool inlineSearch, int count) {
    final palette = PocketPalette.of(context);
    final title =
        collection ??
        switch (page) {
          1 => 'Collections',
          2 => 'Open later',
          3 => 'Archive',
          _ =>
            store.ownerName.trim().isEmpty
                ? 'My pocket'
                : '${store.ownerName.trim()}’s pocket',
        };
    final total = collectionList ? store.collections.length : count;
    final noun = collectionList ? 'collection' : 'thing';
    final titleBlock = Row(
      children: [
        if (collection != null)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              tooltip: 'All collections',
              onPressed: () {
                searchText.clear();
                setState(() {
                  collection = null;
                  filter = null;
                  search = '';
                });
              },
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PocketType.display(
                    wide ? 38 : 31,
                    color: palette.ink,
                    height: 1.12,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              MonoLabel(
                store.entries.isEmpty && !collectionList
                    ? 'Empty for now'
                    : '$total ${total == 1 ? noun : '${noun}s'}',
                size: 11,
              ),
            ],
          ),
        ),
      ],
    );
    if (wide) {
      return Row(
        children: [
          Expanded(child: titleBlock),
          if (inlineSearch && !collectionList) ...[
            const SizedBox(width: 24),
            SizedBox(width: 340, child: searchField()),
          ],
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: titleBlock),
        IconButton(
          tooltip: 'Receive a note',
          onPressed: () => showReceiveSheet(context, store),
          icon: const Icon(Icons.qr_code_scanner_rounded),
        ),
        IconButton(
          tooltip: 'Settings',
          onPressed: openSettings,
          icon: const Icon(Icons.tune_rounded),
        ),
      ],
    );
  }

  Widget searchField() => TextField(
    controller: searchText,
    onChanged: (value) => setState(() => search = value),
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      hintText: 'Search your pocket',
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      prefixIcon: const Icon(Icons.search_rounded, size: 21),
      suffixIcon:
          search.isEmpty
              ? null
              : IconButton(
                tooltip: 'Clear search',
                onPressed: clearSearch,
                icon: const Icon(Icons.close_rounded, size: 19),
              ),
    ),
  );

  Widget filters(bool wide) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    // On a phone the chips run on to the edge of the screen.
    clipBehavior: wide ? Clip.hardEdge : Clip.none,
    child: Row(
      children: [
        _FilterChip(
          label: 'Everything',
          selected: filter == null,
          onTap: () => setState(() => filter = null),
        ),
        for (final kind in EntryKind.values)
          _FilterChip(
            label: kind.plural,
            shape: kind.shape,
            selected: filter == kind,
            onTap: () => setState(() => filter = kind),
          ),
      ],
    ),
  );

  Widget board(List<PocketEntry> entries) => LayoutBuilder(
    builder: (context, constraints) {
      // Larger text needs wider papers, so it gets fewer columns.
      final scale = (MediaQuery.textScalerOf(context).scale(100) / 100).clamp(
        1.0,
        2.0,
      );
      final width = constraints.maxWidth / scale;
      final count =
          width >= 1000
              ? 4
              : width >= 640
              ? 3
              : width >= 300
              ? 2
              : 1;
      final gap = constraints.maxWidth >= 640 ? 18.0 : 12.0;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int column = 0; column < count; column++) ...[
            if (column > 0) SizedBox(width: gap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (
                    int index = column;
                    index < entries.length;
                    index += count
                  )
                    Padding(
                      key: ValueKey(entries[index].id),
                      padding: EdgeInsets.only(bottom: gap + 4),
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
    final palette = PocketPalette.of(context);
    final stock = palette.stock(entry.colorIndex);
    final locked = entry.isLocked;
    final title = Text(
      entry.title.isEmpty
          ? 'Untitled ${entry.kind.label.toLowerCase()}'
          : entry.title,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: PocketType.display(19, color: stock.ink),
    );
    Widget body(int lines) => Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Text(entry.body, maxLines: lines, overflow: TextOverflow.ellipsis),
    );
    final badges = [
      if (entry.received && !entry.isExample)
        Tooltip(
          message: 'Received',
          child: Icon(
            Icons.call_received_rounded,
            size: 13,
            color: stock.inkMuted,
          ),
        ),
      if (entry.isExample) Stamp('EXAMPLE', color: stock.inkMuted),
    ];
    PopupMenuItem<String> action(String value, IconData icon, String label) =>
        PopupMenuItem(
          value: value,
          child: Row(
            children: [
              Icon(icon, size: 19),
              const SizedBox(width: 12),
              Text(label),
            ],
          ),
        );
    final actions = MenuButton<String>(
      tooltip: 'Item actions',
      onSelected: (action) => menu(entry, action),
      items:
          () => [
            action(
              'pin',
              entry.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              entry.pinned ? 'Unpin' : 'Pin to top',
            ),
            if (!locked) action('pass', Icons.qr_code_rounded, 'Pass a copy'),
            if (!locked)
              action('copy', Icons.content_copy_rounded, 'Make a copy'),
            action(
              'archive',
              entry.archived
                  ? Icons.unarchive_outlined
                  : Icons.inventory_2_outlined,
              entry.archived ? 'Bring back' : 'Archive',
            ),
            action('delete', Icons.delete_outline_rounded, 'Delete'),
          ],
      child: SizedBox.square(
        dimension: 44,
        child: Icon(Icons.more_horiz_rounded, size: 20, color: stock.inkMuted),
      ),
    );
    // The stamp drops to a line of its own before it crowds out the name.
    final footer = Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              MonoLabel(entry.collection, color: stock.inkMuted),
              ...badges,
            ],
          ),
        ),
        actions,
      ],
    );
    final items = [
      for (final item in entry.items.take(entry.kind == EntryKind.trip ? 3 : 5))
        Semantics(
          checked: item.done,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => act(() => store.toggleItem(entry.id, item.id)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: InkCheck(done: item.done, stock: stock, size: 15),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: PocketType.body(
                        13,
                        color: item.done ? stock.inkMuted : stock.ink,
                        height: 1.3,
                      ).copyWith(
                        decoration:
                            item.done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ];
    final hidden = entry.items.length - items.length;
    final more =
        hidden > 0
            ? Padding(
              padding: const EdgeInsets.only(top: 3),
              child: MonoLabel('+ $hidden more', color: stock.inkMuted),
            )
            : null;
    void open() => edit(entry);
    // Everything above the footer keeps clear of the paper's right edge. The
    // footer runs on to it, which gives the menu a full-size target.
    Widget page(List<Widget> content) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: _menuReach),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: content,
          ),
        ),
        footer,
      ],
    );
    const padding = EdgeInsets.fromLTRB(14, 14, 14 - _menuReach, 4);

    // A page that may not be opened yet is a sealed envelope, whatever kind
    // it is. It shows its title, its sender and its opening time only.
    switch (locked ? EntryKind.letter : entry.kind) {
      case EntryKind.note:
        return Paper(
          shape: PaperShape.slip,
          stock: stock,
          pinned: entry.pinned,
          onTap: open,
          padding: padding,
          child: page([title, if (entry.body.isNotEmpty) body(6)]),
        );
      case EntryKind.checklist:
        final done = entry.items.where((item) => item.done).length;
        return Paper(
          shape: PaperShape.receipt,
          stock: stock,
          pinned: entry.pinned,
          onTap: open,
          padding: padding,
          child: page([
            title,
            if (items.isNotEmpty) ...[
              const SizedBox(height: 3),
              ...items,
              if (more != null) more,
            ] else if (entry.body.isNotEmpty)
              body(4),
            const SizedBox(height: 10),
            DashedRule(color: stock.inkLine),
            if (items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(child: MonoLabel('Done', color: stock.inkMuted)),
                    MonoLabel('$done/${entry.items.length}', color: stock.ink),
                  ],
                ),
              ),
          ]),
        );
      case EntryKind.movie:
        return Paper(
          shape: PaperShape.ticket,
          stock: stock,
          pinned: entry.pinned,
          onTap: open,
          padding: const EdgeInsets.fromLTRB(14, 12, 14 - _menuReach, 14),
          stubHeight: 44,
          stub: Row(
            children: [
              Icon(
                entry.watched
                    ? Icons.check_circle_rounded
                    : Icons.play_arrow_rounded,
                size: 15,
                color: stock.ink,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: MonoLabel(
                  entry.watched ? 'Watched' : 'To watch',
                  color: stock.ink,
                ),
              ),
              if (entry.url.isNotEmpty)
                Icon(Icons.link_rounded, size: 15, color: stock.inkMuted),
              actions,
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.only(right: _menuReach),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: MonoLabel(entry.collection, color: stock.inkMuted),
                    ),
                    for (final badge in badges) ...[
                      const SizedBox(width: 6),
                      badge,
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                title,
                if (entry.body.isNotEmpty) body(3),
              ],
            ),
          ),
        );
      case EntryKind.trip:
        return Paper(
          shape: PaperShape.tag,
          stock: stock,
          pinned: entry.pinned,
          onTap: open,
          padding: padding,
          child: page([
            title,
            if (entry.date != null)
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Row(
                  children: [
                    Flexible(
                      child: MonoLabel(
                        shortDate(entry.date!),
                        color: stock.ink,
                      ),
                    ),
                    if (entry.endDate != null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 12,
                          color: stock.ink,
                        ),
                      ),
                      Flexible(
                        child: MonoLabel(
                          shortDate(entry.endDate!),
                          color: stock.ink,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 3),
              ...items,
              if (more != null) more,
            ] else if (entry.body.isNotEmpty)
              body(3),
          ]),
        );
      case EntryKind.letter:
        final opens =
            entry.unlockAt != null && entry.unlockAt!.isAfter(DateTime.now());
        final who =
            entry.received
                ? (entry.sender.isEmpty ? null : 'From ${entry.sender}')
                : (entry.recipient.isEmpty ? null : 'For ${entry.recipient}');
        return Paper(
          shape: PaperShape.envelope,
          stock: stock,
          pinned: entry.pinned,
          onTap: open,
          padding: const EdgeInsets.fromLTRB(14, 0, 14 - _menuReach, 4),
          child: page([
            SealOnFlap(
              inset: 14,
              sealSize: 36,
              seal:
                  locked
                      ? const WaxSeal(icon: Icons.lock_rounded)
                      : WaxSeal(emoji: entry.emoji),
            ),
            const SizedBox(height: 10),
            title,
            if (who != null)
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: MonoLabel(who, color: stock.inkMuted),
              ),
            if (opens)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: MonoLabel(
                  'Opens ${niceTime(entry.unlockAt!)}',
                  color: stock.ink,
                ),
              ),
            if (!locked && entry.body.isNotEmpty) body(3),
          ]),
        );
    }
  }

  Widget examplesNote() {
    final palette = PocketPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_outlined, size: 17, color: palette.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'You’re exploring example items.',
              style: PocketType.body(13, color: palette.muted),
            ),
          ),
          TextButton(
            onPressed: () => act(store.clearExamples),
            child: const Text('Clear examples'),
          ),
        ],
      ),
    );
  }

  Widget emptyState() {
    final palette = PocketPalette.of(context);
    final isNew =
        store.entries.isEmpty &&
        search.isEmpty &&
        filter == null &&
        collection == null &&
        page == 0;
    final String title;
    final String text;
    if (isNew) {
      title = 'Start with one little thing.';
      text =
          'A thought, a list, a place to go.\nNo account. Just you and your pocket.';
    } else if (search.isNotEmpty) {
      title = 'Nothing found.';
      text = 'Nothing matches this search. Try a different word.';
    } else if (archived && filter == null) {
      title = 'Nothing archived.';
      text = 'Things you archive rest here, out of the way but still yours.';
    } else if (archived) {
      title = 'Nothing here yet.';
      text = 'Nothing of this kind is archived. Try another filter.';
    } else if (page == 2) {
      title = 'No envelopes waiting.';
      text =
          'Write a letter and choose an opening time,\nor receive one from someone you love.';
    } else {
      title = 'Nothing here yet.';
      text = 'Create something new, or try another filter.';
    }
    return GhostPaper(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 38),
      child: Column(
        children: [
          PocketMark(size: 92, background: palette.night),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: PocketType.body(15, color: palette.muted, height: 1.55),
          ),
          if (!archived && search.isEmpty) ...[
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: create,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                isNew ? 'Create your first item' : 'Create something',
              ),
            ),
          ],
          if (isNew)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton(
                onPressed: () => act(store.addExamples),
                child: const Text('Take a peek at an example pocket'),
              ),
            ),
        ],
      ),
    );
  }

  Widget collectionBoard() => LayoutBuilder(
    builder: (context, constraints) {
      final palette = PocketPalette.of(context);
      final count =
          constraints.maxWidth >= 860
              ? 3
              : constraints.maxWidth >= 520
              ? 2
              : 1;
      const gap = 16.0;
      final width = (constraints.maxWidth - gap * (count - 1)) / count;
      return Wrap(
        spacing: gap,
        runSpacing: gap + 4,
        children: [
          for (int i = 0; i < store.collections.length; i++)
            SizedBox(
              width: width,
              child: collectionFolder(i, palette.stock(i)),
            ),
          SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.only(top: PaperBorder.tab),
              child: GhostPaper(
                onTap: addCollection,
                radius: 8,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 23,
                ),
                child: Row(
                  children: [
                    Icon(Icons.add_rounded, color: palette.ink),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'New collection',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PocketType.body(
                          15,
                          color: palette.ink,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget collectionFolder(int index, PaperStock stock) {
    final name = store.collections[index];
    final count =
        store.entries
            .where((entry) => entry.collection == name && !entry.archived)
            .length;
    final removable = name != 'Everyday';
    return Paper(
      shape: PaperShape.folder,
      stock: stock,
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      onTap: () => openCollection(name),
      onLongPress: removable ? () => removeCollection(name) : null,
      child: Row(
        children: [
          Expanded(
            // The name is the button a reader hears; the menu beside it
            // stays a control of its own.
            child: Semantics(
              button: true,
              onTap: () => openCollection(name),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PocketType.display(20, color: stock.ink),
                  ),
                  const SizedBox(height: 4),
                  MonoLabel(
                    '$count ${count == 1 ? 'thing' : 'things'}',
                    color: stock.inkMuted,
                  ),
                ],
              ),
            ),
          ),
          if (removable)
            MenuButton<String>(
              tooltip: 'Collection actions',
              onSelected: (_) => removeCollection(name),
              items:
                  () => const [
                    PopupMenuItem(
                      value: 'remove',
                      child: Text('Remove collection'),
                    ),
                  ],
              child: SizedBox.square(
                dimension: 48,
                child: Icon(Icons.more_horiz_rounded, color: stock.inkMuted),
              ),
            )
          else
            SizedBox.square(
              dimension: 48,
              child: Icon(Icons.arrow_forward_rounded, color: stock.inkMuted),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.shape,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final PaperShape? shape;

  @override
  Widget build(BuildContext context) {
    final palette = PocketPalette.of(context);
    final ink = selected ? PocklinoColors.deepInk : palette.ink;
    final border = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(
        color:
            selected
                ? (palette.night ? palette.butter : palette.ink)
                : palette.ink.withValues(alpha: palette.night ? .3 : .38),
        width: palette.stroke,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? palette.butter : Colors.transparent,
          shape: border,
          child: InkWell(
            onTap: onTap,
            customBorder: border,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (shape != null) ...[
                    PaperGlyph(shape!, size: 15, color: ink),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: PocketType.body(
                      13.5,
                      color: ink,
                      weight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The five kinds of page, each offered as the paper it will be kept on,
/// and the way to take in a page someone else is passing.
class _CreateSheet extends StatelessWidget {
  const _CreateSheet();

  /// Returned instead of an [EntryKind] when the user wants to receive.
  static const receive = 'receive';
  static const _gap = 14.0;

  @override
  Widget build(BuildContext context) {
    final palette = PocketPalette.of(context);
    Widget words(String label, String hint, Color ink, Color muted) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: PocketType.display(18, color: ink),
        ),
        const SizedBox(height: 3),
        Text(
          hint,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: PocketType.body(12.5, color: muted, height: 1.3),
        ),
      ],
    );
    Widget option(EntryKind kind, double width) {
      final stock = palette.stock(kind.paper);
      final text = words(kind.label, kind.hint, stock.ink, stock.inkMuted);
      return Paper(
        shape: kind.shape,
        stock: stock,
        onTap: () => Navigator.pop(context, kind),
        button: true,
        padding:
            kind == EntryKind.letter
                ? const EdgeInsets.fromLTRB(14, 0, 14, 14)
                : const EdgeInsets.fromLTRB(14, 13, 14, 12),
        stubHeight: 30,
        stub:
            kind == EntryKind.movie
                ? Align(
                  alignment: Alignment.centerLeft,
                  child: MonoLabel('Admit one', color: stock.inkMuted),
                )
                : null,
        child:
            kind == EntryKind.letter
                ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SealOnFlap(
                      inset: 14,
                      sealSize: 32,
                      paperWidth: width,
                      seal: WaxSeal(emoji: kind.sticker, size: 32),
                    ),
                    const SizedBox(height: 8),
                    text,
                  ],
                )
                : text,
      );
    }

    Widget pair(Widget left, Widget right) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: _gap),
          Expanded(child: right),
        ],
      ),
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - _gap) / 2;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SheetHandle(),
                const SizedBox(height: 16),
                Text(
                  'Make room for something.',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Big plans. Small thoughts. All welcome here.',
                  style: PocketType.body(14, color: palette.muted),
                ),
                const SizedBox(height: 20),
                pair(
                  option(EntryKind.note, width),
                  option(EntryKind.checklist, width),
                ),
                const SizedBox(height: 18),
                pair(
                  option(EntryKind.movie, width),
                  option(EntryKind.trip, width),
                ),
                const SizedBox(height: 18),
                pair(
                  option(EntryKind.letter, width),
                  GhostPaper(
                    radius: 8,
                    padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
                    onTap: () => Navigator.pop(context, receive),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(
                          Icons.qr_code_scanner_rounded,
                          size: 26,
                          color: palette.ink,
                        ),
                        const SizedBox(height: 10),
                        words(
                          'Receive',
                          'Something passed to you',
                          palette.ink,
                          palette.muted,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
