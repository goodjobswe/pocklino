import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'design.dart';
import 'models.dart';
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
          colorIndex: switch (kind) {
            EntryKind.note => 3,
            EntryKind.checklist => 1,
            EntryKind.movie => 4,
            EntryKind.trip => 2,
            EntryKind.letter => 0,
          },
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

  Future<void> editItem(CheckItem item) async {
    final controller = TextEditingController(text: item.text);
    final result = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Edit item'),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 500,
              onSubmitted: (value) => Navigator.pop(ctx, value),
              decoration: const InputDecoration(labelText: 'Item'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, controller.text),
                child: const Text('Done'),
              ),
            ],
          ),
    );
    controller.dispose();
    if (result != null && result.trim().isNotEmpty && mounted) {
      update(
        entry.copyWith(
          items:
              entry.items
                  .map(
                    (e) =>
                        e.id == item.id ? e.copyWith(text: result.trim()) : e,
                  )
                  .toList(),
        ),
      );
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
          title: Text(
            entry.isLocked ? 'An envelope for later' : entry.kind.label,
          ),
          actions: [
            if (!entry.isLocked)
              IconButton(
                tooltip: entry.pinned ? 'Unpin' : 'Pin to top',
                onPressed: () => update(entry.copyWith(pinned: !entry.pinned)),
                icon: Icon(
                  entry.pinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                ),
              ),
            if (!entry.isLocked)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: FilledButton.icon(
                  onPressed: pass,
                  icon: const Icon(Icons.qr_code_rounded, size: 18),
                  label: const Text('Pass'),
                ),
              ),
          ],
        ),
        body:
            entry.isLocked
                ? sealedEnvelope()
                : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(22, 18, 22, 60),
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final collection = collectionPicker();
                            final colors = colorPicker();
                            if (constraints.maxWidth < 500) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  collection,
                                  const SizedBox(height: 12),
                                  colors,
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Expanded(child: collection),
                                const SizedBox(width: 18),
                                colors,
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: entryColor(entry),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Theme(
                            data: PocklinoTheme.light,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      entry.kind.icon,
                                      color: PocklinoColors.ink,
                                      size: 21,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: SmallLabel(
                                        entry.kind.hint,
                                        color: PocklinoColors.ink.withValues(
                                          alpha: .65,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 17),
                                TextField(
                                  controller: title,
                                  maxLines: null,
                                  maxLength: 200,
                                  style: const TextStyle(
                                    fontFamily: 'Lora',
                                    fontSize: 30,
                                    height: 1.25,
                                    color: PocklinoColors.ink,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: switch (entry.kind) {
                                      EntryKind.movie =>
                                        'What are we watching?',
                                      EntryKind.trip => 'Where are we going?',
                                      EntryKind.letter =>
                                        'A little note for you…',
                                      EntryKind.checklist => 'A list for…',
                                      _ => 'Give this thought a home…',
                                    },
                                    counterText: '',
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    filled: false,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                if (entry.kind == EntryKind.letter) ...[
                                  Center(
                                    child: Text(
                                      entry.emoji,
                                      style: const TextStyle(
                                        fontFamily: 'NotoEmoji',
                                        fontSize: 60,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                ],
                                TextField(
                                  controller: body,
                                  minLines:
                                      entry.kind == EntryKind.note ||
                                              entry.kind == EntryKind.letter
                                          ? 7
                                          : 3,
                                  maxLines: null,
                                  maxLength: 60000,
                                  style: const TextStyle(
                                    color: PocklinoColors.ink,
                                    fontSize: 16,
                                    height: 1.8,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: switch (entry.kind) {
                                      EntryKind.movie =>
                                        'Why it’s on your list, who recommended it, or a favorite quote…',
                                      EntryKind.trip =>
                                        'Day 1: a slow morning, a new place…\nKeep your itinerary, addresses, and ideas here.',
                                      EntryKind.checklist =>
                                        'A little context (optional)…',
                                      EntryKind.letter =>
                                        'Something kind, something funny,\nsomething only the two of you understand…',
                                      _ => 'Let your thoughts land here.',
                                    },
                                    counterText: '',
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    filled: false,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (entry.kind == EntryKind.checklist ||
                            entry.kind == EntryKind.trip)
                          checklist(),
                        if (entry.kind == EntryKind.movie ||
                            entry.kind == EntryKind.trip) ...[
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
                          const SizedBox(height: 10),
                          const Text(
                            'Links open in your browser. Linked websites need internet.',
                            style: TextStyle(fontSize: 11),
                          ),
                          const SizedBox(height: 22),
                        ],
                        if (entry.kind == EntryKind.movie)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Watched it'),
                            subtitle: const Text(
                              'Another good story in your pocket.',
                            ),
                            value: entry.watched,
                            onChanged:
                                (value) =>
                                    update(entry.copyWith(watched: value)),
                          ),
                        if (entry.kind == EntryKind.trip) ...[
                          const SmallLabel('Dates to look forward to'),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final value = await pickDate(entry.date);
                                  if (value != null && context.mounted) {
                                    update(
                                      entry.copyWith(
                                        date: value,
                                        clearEndDate:
                                            entry.endDate != null &&
                                            entry.endDate!.isBefore(value),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(
                                  Icons.calendar_today_outlined,
                                  size: 17,
                                ),
                                label: Text(
                                  entry.date == null
                                      ? 'Start date'
                                      : niceDate(entry.date!),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final value = await pickDate(
                                    entry.endDate ?? entry.date,
                                  );
                                  if (value != null && context.mounted) {
                                    if (entry.date != null &&
                                        value.isBefore(entry.date!)) {
                                      toast(
                                        context,
                                        'Choose an end date after the start date.',
                                      );
                                    } else {
                                      update(entry.copyWith(endDate: value));
                                    }
                                  }
                                },
                                icon: const Icon(
                                  Icons.event_outlined,
                                  size: 17,
                                ),
                                label: Text(
                                  entry.endDate == null
                                      ? 'End date'
                                      : niceDate(entry.endDate!),
                                ),
                              ),
                              if (entry.date != null || entry.endDate != null)
                                TextButton(
                                  onPressed:
                                      () => update(
                                        entry.copyWith(
                                          clearDate: true,
                                          clearEndDate: true,
                                        ),
                                      ),
                                  child: const Text('Clear dates'),
                                ),
                            ],
                          ),
                        ],
                        if (entry.kind == EntryKind.letter) letterOptions(),
                        const SizedBox(height: 30),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              failed
                                  ? Icons.error_outline
                                  : saving || dirty
                                  ? Icons.edit_outlined
                                  : Icons.check_circle_outline,
                              size: 16,
                              color:
                                  failed
                                      ? Theme.of(context).colorScheme.error
                                      : null,
                            ),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                failed
                                    ? 'Not saved yet'
                                    : saving
                                    ? 'Saving…'
                                    : dirty
                                    ? 'A little change…'
                                    : store.entries.any(
                                      (saved) => saved.id == entry.id,
                                    )
                                    ? 'Saved on this device'
                                    : 'Ready for your first thought',
                                style: const TextStyle(fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            if (failed)
                              TextButton(
                                onPressed: save,
                                child: const Text('Retry'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
      ),
    );
  }

  Widget collectionPicker() => DropdownButtonFormField<String>(
    isExpanded: true,
    value:
        store.collections.contains(entry.collection)
            ? entry.collection
            : 'Everyday',
    decoration: const InputDecoration(labelText: 'Collection'),
    items:
        store.collections
            .map(
              (name) => DropdownMenuItem(
                value: name,
                child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
    onChanged: (value) {
      if (value != null) {
        update(entry.copyWith(collection: value));
      }
    },
  );

  Widget colorPicker() => Semantics(
    label: 'Choose a card color',
    child: Wrap(
      spacing: 2,
      runSpacing: 2,
      children: [
        for (int i = 0; i < PocklinoColors.cardColors.length; i++)
          Tooltip(
            message: 'Color ${i + 1}',
            child: InkWell(
              onTap: () => update(entry.copyWith(colorIndex: i)),
              borderRadius: BorderRadius.circular(22),
              child: SizedBox.square(
                dimension: 44,
                child: Center(
                  child: Container(
                    width: 27,
                    height: 27,
                    decoration: BoxDecoration(
                      color: PocklinoColors.cardColors[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            entry.colorIndex == i
                                ? PocklinoColors.ink
                                : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child:
                        entry.colorIndex == i
                            ? const Icon(
                              Icons.check_rounded,
                              size: 15,
                              color: PocklinoColors.ink,
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

  Widget checklist() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: SmallLabel(
              entry.kind == EntryKind.trip
                  ? 'Packing & things to do'
                  : 'One thing at a time',
            ),
          ),
          if (entry.items.any((item) => item.done))
            TextButton(
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
        ],
      ),
      const SizedBox(height: 10),
      for (final item in [
        ...entry.items.where((e) => !e.done),
        ...entry.items.where((e) => e.done),
      ])
        Dismissible(
          key: ValueKey(item.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: Theme.of(context).colorScheme.errorContainer,
            child: const Icon(Icons.delete_outline),
          ),
          onDismissed:
              (_) => update(
                entry.copyWith(
                  items: entry.items.where((e) => e.id != item.id).toList(),
                ),
              ),
          child: Row(
            children: [
              Checkbox(
                value: item.done,
                onChanged:
                    (value) => update(
                      entry.copyWith(
                        items:
                            entry.items
                                .map(
                                  (e) =>
                                      e.id == item.id
                                          ? e.copyWith(done: value ?? false)
                                          : e,
                                )
                                .toList(),
                      ),
                    ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => editItem(item),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    child: Text(
                      item.text,
                      style: TextStyle(
                        fontSize: 15,
                        decoration:
                            item.done ? TextDecoration.lineThrough : null,
                        color:
                            item.done
                                ? Theme.of(context).colorScheme.onSurfaceVariant
                                : null,
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove item',
                icon: const Icon(Icons.close_rounded, size: 17),
                onPressed:
                    () => update(
                      entry.copyWith(
                        items:
                            entry.items.where((e) => e.id != item.id).toList(),
                      ),
                    ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 10),
      TextField(
        controller: itemText,
        maxLines: 3,
        minLines: 1,
        maxLength: 4000,
        onSubmitted: (_) => addItems(),
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          hintText: 'Add an item…',
          counterText: '',
          prefixIcon: const Icon(Icons.add_rounded),
          suffixIcon: IconButton(
            tooltip: 'Add item',
            onPressed: addItems,
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ),
      ),
      const SizedBox(height: 28),
    ],
  );

  Widget letterOptions() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SmallLabel('Make it a little more you'),
      const SizedBox(height: 14),
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
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => update(entry.copyWith(emoji: emoji)),
              child: Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color:
                      emoji == entry.emoji
                          ? entryColor(entry)
                          : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  emoji,
                  style: const TextStyle(fontFamily: 'NotoEmoji', fontSize: 26),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 24),
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
      const SizedBox(height: 20),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Open later'),
        subtitle: const Text('An envelope for a future moment.'),
        value: entry.unlockAt != null,
        onChanged:
            (value) => update(
              value
                  ? entry.copyWith(
                    unlockAt: DateTime.now().add(const Duration(days: 1)),
                  )
                  : entry.copyWith(clearUnlockAt: true),
            ),
      ),
      if (entry.unlockAt != null) ...[
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () async {
            final value = await pickDate(entry.unlockAt, withTime: true);
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
        const Text(
          'Pocklino hides the received message until this time using the receiving device’s clock. '
          'It is a playful surprise, not a secure lock; changing the clock or inspecting the shared data can reveal it early.',
          style: TextStyle(fontSize: 12, height: 1.6),
        ),
      ],
    ],
  );

  Widget sealedEnvelope() {
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
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            children: [
              const SmallLabel('A little anticipation'),
              const SizedBox(height: 30),
              Container(
                width: 280,
                height: 190,
                decoration: BoxDecoration(
                  color: entryColor(entry),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.mail_outline_rounded,
                      size: 160,
                      color: PocklinoColors.ink,
                    ),
                    Positioned(
                      bottom: 48,
                      child: CircleAvatar(
                        backgroundColor: PocklinoColors.coral,
                        child: Icon(
                          Icons.favorite_rounded,
                          color: Colors.white,
                          size: 21,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text(
                entry.title,
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              if (entry.sender.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('A little something from ${entry.sender}'),
                ),
              const SizedBox(height: 22),
              Text(
                'Opens ${niceTime(entry.unlockAt!)}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 9),
              Text(
                countdown,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 24),
              const Text(
                'Come back when the moment arrives.\nYour envelope will open right here.',
                textAlign: TextAlign.center,
                style: TextStyle(height: 1.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
