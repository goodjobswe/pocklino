import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'design.dart';
import 'models.dart';
import 'paper.dart';
import 'sharing.dart';
import 'store.dart';
import 'ui_helpers.dart';

class EntryEditor extends StatefulWidget {
  const EntryEditor({
    super.key,
    required this.store,
    this.entry,
    this.kind,
    this.collection,
  });
  final AppStore store;
  final PocketEntry? entry;
  final EntryKind? kind;
  final String? collection;
  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> with WidgetsBindingObserver {
  late PocketEntry entry;
  late TextEditingController title;
  late TextEditingController body;
  late TextEditingController link;
  late TextEditingController recipient;
  late TextEditingController sender;
  final itemText = TextEditingController();
  Timer? debounce;
  Timer? revealClock;
  Future<void> writes = Future<void>.value();
  bool dirty = false;
  bool saving = false;
  bool failed = false;
  bool closing = false;
  int revision = 0;
  AppStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final now = DateTime.now();
    final kind = widget.kind ?? EntryKind.note;
    entry =
        widget.entry ??
        PocketEntry(
          id: const Uuid().v4(),
          title: '',
          kind: kind,
          createdAt: now,
          updatedAt: now,
          collection:
              widget.collection ??
              switch (kind) {
                EntryKind.movie => 'Watchlist',
                EntryKind.trip => 'Adventures',
                EntryKind.letter => 'Little joys',
                _ => 'Everyday',
              },
          emoji: kind.sticker,
          colorIndex: kind.paper,
          sender: store.ownerName,
        );
    title = TextEditingController(text: entry.title);
    body = TextEditingController(text: entry.body);
    link = TextEditingController(text: entry.url);
    recipient = TextEditingController(text: entry.recipient);
    sender = TextEditingController(text: entry.sender);
    for (final controller in [title, body, link, recipient, sender]) {
      controller.addListener(changed);
    }
    revealClock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && entry.received && entry.unlockAt != null) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      save();
    }
  }

  void changed() {
    if (entry.isLocked) return;
    revision++;
    setState(() {
      dirty = true;
      failed = false;
    });
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 650), save);
  }

  PocketEntry snapshot() => entry.copyWith(
    title:
        title.text.trim().isEmpty
            ? 'Untitled ${entry.kind.label.toLowerCase()}'
            : title.text.trim(),
    body: body.text,
    url: link.text.trim(),
    recipient: recipient.text.trim(),
    sender: sender.text.trim(),
    updatedAt: DateTime.now(),
    isExample: false,
  );

  Future<bool> save() async {
    debounce?.cancel();
    if (entry.isLocked || !dirty) return !failed;
    if (widget.entry == null &&
        !store.entries.any((saved) => saved.id == entry.id) &&
        title.text.trim().isEmpty &&
        body.text.trim().isEmpty &&
        entry.items.isEmpty &&
        link.text.trim().isEmpty) {
      return true;
    }
    final value = snapshot();
    final version = revision;
    if (mounted) setState(() => saving = true);
    var success = true;
    writes = writes.then((_) async {
      try {
        await store.upsert(value);
        if (mounted && version == revision) {
          setState(() {
            dirty = false;
            failed = false;
          });
        }
      } catch (_) {
        success = false;
        if (mounted) setState(() => failed = true);
      }
    });
    await writes;
    if (mounted) setState(() => saving = false);
    return success;
  }

  Future<void> finish() async {
    if (closing) return;
    closing = true;
    final saved = await save();
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      closing = false;
      toast(
        context,
        'Your changes could not be saved. Please try again before leaving.',
      );
    }
  }

  void update(PocketEntry value) {
    setState(() => entry = value);
    changed();
  }

  void addItems() {
    final texts = itemText.text
        .split('\n')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty);
    if (texts.isEmpty) return;
    final additions =
        texts
            .map((text) => CheckItem(id: const Uuid().v4(), text: text))
            .toList();
    itemText.clear();
    update(entry.copyWith(items: [...entry.items, ...additions]));
  }

  void setItem(CheckItem item, {String? text, bool? done}) => update(
    entry.copyWith(
      items:
          entry.items
              .map(
                (e) => e.id == item.id ? e.copyWith(text: text, done: done) : e,
              )
              .toList(),
    ),
  );

  void removeItem(CheckItem item) => update(
    entry.copyWith(items: entry.items.where((e) => e.id != item.id).toList()),
  );

  Future<void> editItem(CheckItem item) async {
    final result = await promptText(
      context,
      title: 'Edit item',
      label: 'Item',
      action: 'Done',
      initial: item.text,
    );
    if (result != null && result.trim().isNotEmpty && mounted) {
      setItem(item, text: result.trim());
    }
  }

  Future<DateTime?> pickDate(DateTime? initial, {bool withTime = false}) async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected == null || !mounted) return null;
    if (!withTime) return selected;
    final time = await showTimePicker(
      context: context,
      initialTime:
          initial == null ? TimeOfDay.now() : TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(
      selected.year,
      selected.month,
      selected.day,
      time.hour,
      time.minute,
    );
  }

  Future<void> pass() async {
    if (title.text.trim().isEmpty &&
        body.text.trim().isEmpty &&
        entry.items.isEmpty) {
      toast(context, 'Add a little something before passing it on.');
      return;
    }
    if (await save() && mounted) await showPassSheet(context, snapshot());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    debounce?.cancel();
    revealClock?.cancel();
    for (final controller in [title, body, link, recipient, sender, itemText]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locked = entry.isLocked;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) finish();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Save and go back',
            onPressed: finish,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title:
              locked
                  ? const Text('An envelope for later')
                  : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Text(entry.kind.label), status()],
                  ),
          actions: [
            if (!locked)
              IconButton(
                tooltip: entry.pinned ? 'Unpin' : 'Pin to top',
                onPressed: () => update(entry.copyWith(pinned: !entry.pinned)),
                icon: Icon(
                  entry.pinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                ),
              ),
            if (!locked)
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 14),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: pass,
                  icon: const Icon(Icons.qr_code_rounded, size: 18),
                  label: const Text('Pass'),
                ),
              ),
          ],
        ),
        body:
            locked
                ? sealedEnvelope()
                : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 56),
                      children: [
                        // Always present, so that showing the notice does not
                        // shift the fields below it and take their focus.
                        if (failed) retryNotice() else const SizedBox.shrink(),
                        tools(),
                        const SizedBox(height: 12),
                        page(),
                        ...beside(),
                      ],
                    ),
                  ),
                ),
      ),
    );
  }

  /// Where the page stands, in the small print under the title.
  Widget status() {
    final palette = PocketPalette.of(context);
    return MonoLabel(
      failed
          ? 'Not saved yet'
          : saving
          ? 'Saving…'
          : dirty
          ? 'A little change…'
          : store.entries.any((saved) => saved.id == entry.id)
          ? 'Saved on this device'
          : 'Ready when you are',
      size: 9.5,
      color: failed ? Theme.of(context).colorScheme.error : palette.muted,
    );
  }

  Widget retryNotice() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.error),
          const SizedBox(width: 10),
          const Expanded(child: Text('These changes are not saved yet.')),
          TextButton(onPressed: save, child: const Text('Retry')),
        ],
      ),
    );
  }

  /// Where the page is kept and which paper it is on.
  Widget tools() => LayoutBuilder(
    builder: (context, constraints) {
      // A collection name and six papers do not share one row on the
      // narrowest phones.
      if (constraints.maxWidth < 300) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            collectionPicker(),
            const SizedBox(height: 4),
            colorPicker(33),
          ],
        );
      }
      return Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: collectionPicker(),
            ),
          ),
          const SizedBox(width: 8),
          colorPicker(
            constraints.maxWidth >= 440
                ? 44
                : constraints.maxWidth < 350
                ? 30
                : 33,
          ),
        ],
      );
    },
  );

  Widget collectionPicker() {
    final palette = PocketPalette.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Collection',
      position: PopupMenuPosition.under,
      borderRadius: BorderRadius.circular(10),
      onSelected: (value) => update(entry.copyWith(collection: value)),
      itemBuilder:
          (_) => [
            for (final name in store.collections)
              PopupMenuItem(
                value: name,
                child: Row(
                  children: [
                    SizedBox(
                      width: 26,
                      child:
                          name == entry.collection
                              ? const Icon(Icons.check_rounded, size: 18)
                              : null,
                    ),
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        decoration: BoxDecoration(
          color: palette.night ? null : palette.sheet,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: palette.line, width: palette.stroke),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PaperGlyph(PaperShape.folder, size: 16, color: palette.ink),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                entry.collection,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PocketType.body(
                  14,
                  color: palette.ink,
                  weight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ),
            Icon(Icons.arrow_drop_down_rounded, size: 20, color: palette.ink),
          ],
        ),
      ),
    );
  }

  Widget colorPicker(double slot) {
    final palette = PocketPalette.of(context);
    final current = entry.colorIndex % palette.stocks.length;
    return Semantics(
      label: 'Choose a paper color',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < palette.stocks.length; i++)
            Tooltip(
              message: 'Color ${i + 1}',
              child: InkResponse(
                onTap: () => update(entry.copyWith(colorIndex: i)),
                radius: 22,
                child: SizedBox(
                  width: slot,
                  height: 44,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: 25,
                      height: 25,
                      decoration: BoxDecoration(
                        color: palette.stocks[i].fill,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color:
                              i == current
                                  ? palette.ink
                                  : palette.stocks[i].edge,
                          width: i == current ? 2.4 : palette.stroke,
                        ),
                      ),
                      child:
                          i == current
                              ? Icon(
                                Icons.check_rounded,
                                size: 15,
                                color: palette.stocks[i].ink,
                              )
                              : null,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// A field with nothing around it: the paper is the field.
  ///
  /// A hint keeps its place under the text once something is written, so it
  /// is held to one line then; otherwise a long hint would leave a gap.
  InputDecoration bare(
    String hint,
    TextStyle style,
    PaperStock stock, {
    required bool empty,
  }) => InputDecoration(
    hintText: hint,
    hintStyle: style.copyWith(
      color: stock.ink.withValues(alpha: stock.quiet - .16),
    ),
    hintMaxLines: empty ? 4 : 1,
    counterText: '',
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    filled: false,
    isDense: true,
    contentPadding: EdgeInsets.zero,
  );

  /// The page itself, cut to the shape of the thing it is.
  Widget page() {
    final palette = PocketPalette.of(context);
    final stock = palette.stock(entry.colorIndex);
    final roomy = MediaQuery.sizeOf(context).width >= 600;
    final edge = roomy ? 28.0 : 18.0;
    final titleStyle = PocketType.display(
      roomy ? 31 : 26,
      color: stock.ink,
      height: 1.16,
    );
    final bodyStyle = PocketType.body(16, color: stock.ink, height: 1.6);
    final heading = [
      MonoLabel(
        entry.kind == EntryKind.movie ? 'Admit one' : entry.kind.hint,
        color: stock.inkMuted,
      ),
      const SizedBox(height: 9),
      TextField(
        controller: title,
        maxLines: null,
        maxLength: 200,
        cursorColor: stock.ink,
        textCapitalization: TextCapitalization.sentences,
        style: titleStyle,
        decoration: bare(
          switch (entry.kind) {
            EntryKind.movie => 'What are we watching?',
            EntryKind.trip => 'Where are we going?',
            EntryKind.letter => 'A little note for you…',
            EntryKind.checklist => 'A list for…',
            _ => 'Give this thought a home…',
          },
          titleStyle,
          stock,
          empty: title.text.isEmpty,
        ),
      ),
    ];
    Widget writing(int lines) => TextField(
      controller: body,
      minLines: lines,
      maxLines: null,
      maxLength: 60000,
      cursorColor: stock.ink,
      textCapitalization: TextCapitalization.sentences,
      style: bodyStyle,
      decoration: bare(
        switch (entry.kind) {
          EntryKind.movie =>
            'Why it’s on your list, who recommended it, or a favorite quote…',
          EntryKind.trip =>
            'Day 1: a slow morning, a new place…\nKeep your itinerary, addresses, and ideas here.',
          EntryKind.checklist => 'A little context (optional)…',
          EntryKind.letter =>
            'Something kind, something funny,\nsomething only the two of you understand…',
          _ => 'Let your thoughts land here.',
        },
        bodyStyle,
        stock,
        empty: body.text.isEmpty,
      ),
    );
    final padding = EdgeInsets.fromLTRB(edge, edge, edge, edge);
    switch (entry.kind) {
      case EntryKind.note:
        return Paper(
          shape: PaperShape.slip,
          stock: stock,
          pinned: entry.pinned,
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [...heading, const SizedBox(height: 14), writing(9)],
          ),
        );
      case EntryKind.checklist:
        return Paper(
          shape: PaperShape.receipt,
          stock: stock,
          pinned: entry.pinned,
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...heading,
              const SizedBox(height: 10),
              writing(1),
              const SizedBox(height: 16),
              checklist(stock),
            ],
          ),
        );
      case EntryKind.movie:
        return Paper(
          shape: PaperShape.ticket,
          stock: stock,
          pinned: entry.pinned,
          padding: padding,
          stubHeight: 62,
          stub: MergeSemantics(
            child: Row(
              children: [
                Icon(
                  entry.watched
                      ? Icons.check_circle_rounded
                      : Icons.play_arrow_rounded,
                  size: 20,
                  color: stock.ink,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Watched it',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PocketType.body(
                      16,
                      color: stock.ink,
                      weight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ),
                paperSwitch(
                  stock,
                  entry.watched,
                  (value) => update(entry.copyWith(watched: value)),
                ),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [...heading, const SizedBox(height: 14), writing(4)],
          ),
        );
      case EntryKind.trip:
        return Paper(
          shape: PaperShape.tag,
          stock: stock,
          pinned: entry.pinned,
          padding: padding.copyWith(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...heading,
              const SizedBox(height: 14),
              dates(stock),
              const SizedBox(height: 16),
              writing(3),
              const SizedBox(height: 16),
              checklist(stock),
            ],
          ),
        );
      case EntryKind.letter:
        return Paper(
          shape: PaperShape.envelope,
          stock: stock,
          pinned: entry.pinned,
          padding: padding.copyWith(top: 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SealOnFlap(
                inset: edge,
                sealSize: 48,
                seal: WaxSeal(emoji: entry.emoji, size: 48),
              ),
              const SizedBox(height: 18),
              ...heading,
              const SizedBox(height: 14),
              writing(7),
            ],
          ),
        );
    }
  }

  Widget paperSwitch(
    PaperStock stock,
    bool value,
    ValueChanged<bool> onChanged,
  ) => Switch(
    value: value,
    onChanged: onChanged,
    thumbColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.selected) ? stock.fill : stock.inkMuted,
    ),
    trackColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.selected)
              ? stock.ink
              : Colors.transparent,
    ),
    trackOutlineColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.selected)
              ? Colors.transparent
              : stock.inkMuted,
    ),
  );

  /// The controls that lie on the desk beside the page.
  List<Widget> beside() => [
    if (entry.kind == EntryKind.movie || entry.kind == EntryKind.trip) ...[
      const SizedBox(height: 26),
      TextField(
        controller: link,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText:
              entry.kind == EntryKind.movie
                  ? 'IMDb or movie link'
                  : 'A useful link',
          hintText:
              entry.kind == EntryKind.movie
                  ? 'https://www.imdb.com/title/…'
                  : 'https://…',
          prefixIcon: const Icon(Icons.link_rounded),
          suffixIcon: IconButton(
            tooltip: 'Open link',
            onPressed: () => openLink(context, link.text),
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Links open in your browser. Linked websites need internet.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
    if (entry.kind == EntryKind.letter) ...[
      const SizedBox(height: 26),
      letterOptions(),
    ],
  ];

  Widget dates(PaperStock stock) {
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      foregroundColor: stock.ink,
      backgroundColor: Colors.transparent,
      side: BorderSide(
        color: stock.inkLine,
        width: PocketPalette.of(context).stroke,
      ),
    );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          style: style,
          onPressed: () async {
            final value = await pickDate(entry.date);
            if (value != null && mounted) {
              update(
                entry.copyWith(
                  date: value,
                  clearEndDate:
                      entry.endDate != null && entry.endDate!.isBefore(value),
                ),
              );
            }
          },
          icon: const Icon(Icons.calendar_today_outlined, size: 16),
          label: Text(
            entry.date == null ? 'Start date' : shortDate(entry.date!),
          ),
        ),
        OutlinedButton.icon(
          style: style,
          onPressed: () async {
            final value = await pickDate(entry.endDate ?? entry.date);
            if (value != null && mounted) {
              if (entry.date != null && value.isBefore(entry.date!)) {
                toast(context, 'Choose an end date after the start date.');
              } else {
                update(entry.copyWith(endDate: value));
              }
            }
          },
          icon: const Icon(Icons.event_outlined, size: 16),
          label: Text(
            entry.endDate == null ? 'End date' : shortDate(entry.endDate!),
          ),
        ),
        if (entry.date != null || entry.endDate != null)
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 40),
              foregroundColor: stock.ink,
            ),
            onPressed:
                () =>
                    update(entry.copyWith(clearDate: true, clearEndDate: true)),
            child: const Text('Clear dates'),
          ),
      ],
    );
  }

  Widget checklist(PaperStock stock) {
    final done = entry.items.where((item) => item.done).length;
    final itemStyle = PocketType.body(16, color: stock.ink, height: 1.35);
    OutlineInputBorder box(BorderSide side) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: side,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashedRule(color: stock.inkLine),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          child: Row(
            children: [
              Expanded(
                child: MonoLabel(
                  entry.kind == EntryKind.trip
                      ? 'Packing & things to do'
                      : 'The list',
                  color: stock.inkMuted,
                ),
              ),
              if (entry.items.isNotEmpty)
                MonoLabel('$done/${entry.items.length}', color: stock.ink),
              if (done > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      foregroundColor: stock.ink,
                    ),
                    onPressed:
                        () => update(
                          entry.copyWith(
                            items:
                                entry.items
                                    .map((item) => item.copyWith(done: false))
                                    .toList(),
                          ),
                        ),
                    child: const Text('Reset'),
                  ),
                ),
            ],
          ),
        ),
        for (final item in [
          ...entry.items.where((e) => !e.done),
          ...entry.items.where((e) => e.done),
        ])
          Dismissible(
            key: ValueKey(item.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              color: stock.ink.withValues(alpha: .12),
              child: Icon(Icons.delete_outline, color: stock.ink),
            ),
            onDismissed: (_) => removeItem(item),
            child: Row(
              children: [
                Semantics(
                  checked: item.done,
                  label: item.done ? 'Done' : 'Not done',
                  child: InkResponse(
                    onTap: () => setItem(item, done: !item.done),
                    radius: 22,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(2, 13, 14, 13),
                      child: InkCheck(done: item.done, stock: stock, size: 20),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => editItem(item),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        item.text,
                        style: itemStyle.copyWith(
                          color: item.done ? stock.inkMuted : null,
                          decoration:
                              item.done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove item',
                  icon: Icon(
                    Icons.close_rounded,
                    size: 17,
                    color: stock.inkMuted,
                  ),
                  onPressed: () => removeItem(item),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        TextField(
          controller: itemText,
          maxLines: 3,
          minLines: 1,
          maxLength: 4000,
          onSubmitted: (_) => addItems(),
          textInputAction: TextInputAction.done,
          cursorColor: stock.ink,
          style: itemStyle,
          decoration: InputDecoration(
            hintText: 'Add an item…',
            hintStyle: itemStyle.copyWith(color: stock.inkMuted),
            counterText: '',
            filled: true,
            fillColor: stock.ink.withValues(alpha: .07),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 13,
            ),
            prefixIcon: Icon(
              Icons.add_rounded,
              size: 20,
              color: stock.inkMuted,
            ),
            suffixIcon: IconButton(
              tooltip: 'Add item',
              onPressed: addItems,
              icon: Icon(
                Icons.arrow_upward_rounded,
                size: 20,
                color: stock.ink,
              ),
            ),
            border: box(BorderSide.none),
            enabledBorder: box(BorderSide.none),
            focusedBorder: box(BorderSide(color: stock.ink, width: 1.5)),
          ),
        ),
      ],
    );
  }

  Widget letterOptions() {
    final palette = PocketPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MonoLabel('Make it a little more you'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final emoji in [
              '💌',
              '🌷',
              '✨',
              '🍋',
              '🌈',
              '🧸',
              '🎂',
              '🫶',
              '☕',
              '🌻',
            ])
              Material(
                color: emoji == entry.emoji ? palette.coral : palette.sheet,
                shape: CircleBorder(
                  side: BorderSide(
                    color:
                        emoji == entry.emoji ? palette.ink : palette.hairline,
                    width: palette.stroke,
                  ),
                ),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => update(entry.copyWith(emoji: emoji)),
                  child: SizedBox.square(
                    dimension: 48,
                    child: Center(
                      child: Text(
                        emoji,
                        style: PocketType.emoji(
                          24,
                          color:
                              emoji == entry.emoji
                                  ? PocklinoColors.deepInk
                                  : palette.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: recipient,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'For',
                  hintText: 'Someone lovely',
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: sender,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'From',
                  hintText: 'You',
                  counterText: '',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // The opening time is a sheet of its own: the switch, and once it is
        // on, the moment and what it does and does not promise.
        Material(
          color: palette.sheet,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: palette.line, width: palette.stroke),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: const EdgeInsets.fromLTRB(16, 4, 10, 4),
                title: const Text('Open later'),
                subtitle: const Text('An envelope for a future moment.'),
                value: entry.unlockAt != null,
                onChanged:
                    (value) => update(
                      value
                          ? entry.copyWith(
                            unlockAt: DateTime.now().add(
                              const Duration(days: 1),
                            ),
                          )
                          : entry.copyWith(clearUnlockAt: true),
                    ),
              ),
              if (entry.unlockAt != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final value = await pickDate(
                            entry.unlockAt,
                            withTime: true,
                          );
                          if (value != null && mounted) {
                            if (!value.isAfter(DateTime.now())) {
                              toast(context, 'Choose a moment in the future.');
                            } else {
                              update(entry.copyWith(unlockAt: value));
                            }
                          }
                        },
                        icon: const Icon(Icons.schedule_rounded, size: 19),
                        label: Text(niceTime(entry.unlockAt!)),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Pocklino hides the received message until this time using the receiving device’s clock. '
                        'It is a playful surprise, not a secure lock; changing the clock or inspecting the shared data can reveal it early.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget sealedEnvelope() {
    final palette = PocketPalette.of(context);
    final stock = palette.stock(entry.colorIndex);
    final remaining = entry.unlockAt!.difference(DateTime.now());
    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    final minutes = remaining.inMinutes % 60;
    final countdown =
        days > 0
            ? '$days days · $hours hours'
            : hours > 0
            ? '$hours hours · $minutes minutes'
            : remaining.inSeconds > 60
            ? '$minutes minutes'
            : 'Less than a minute';
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            children: [
              const MonoLabel('A little anticipation'),
              const SizedBox(height: 22),
              SizedBox(
                width: 280,
                child: Paper(
                  shape: PaperShape.envelope,
                  stock: stock,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(
                    children: [
                      const SealOnFlap(
                        inset: 20,
                        sealSize: 52,
                        paperWidth: 280,
                        seal: WaxSeal(icon: Icons.lock_rounded, size: 52),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        entry.title,
                        textAlign: TextAlign.center,
                        style: PocketType.display(22, color: stock.ink),
                      ),
                      if (entry.sender.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            'A little something from ${entry.sender}',
                            textAlign: TextAlign.center,
                            style: PocketType.body(14, color: stock.inkSoft),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),
              MonoLabel('Opens ${niceTime(entry.unlockAt!)}'),
              const SizedBox(height: 8),
              Text(
                countdown,
                textAlign: TextAlign.center,
                style: PocketType.display(26, color: palette.ink),
              ),
              const SizedBox(height: 18),
              Text(
                'Come back when the moment arrives.\nYour envelope will open right here.',
                textAlign: TextAlign.center,
                style: PocketType.body(15, color: palette.muted, height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
