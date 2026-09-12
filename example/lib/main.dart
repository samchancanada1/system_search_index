import 'dart:async';

import 'package:flutter/material.dart';
import 'package:system_search_index/system_search_index.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NotesApp());
}

class NotesApp extends StatelessWidget {
  const NotesApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Fieldnotes',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF187763)),
      useMaterial3: true,
    ),
    home: const NotesPage(),
  );
}

final sampleNotes = [
  SearchItem(
    id: 'weekend',
    domain: 'notes',
    title: 'Weekend in Montreal',
    description: 'Train tickets, a museum visit, and dinner with Alex.',
    textContent:
        'Take the train on Friday. Visit the fine arts museum on Saturday. Dinner with Alex near the old port.',
    keywords: ['travel', 'weekend', 'Montreal'],
    deepLink: Uri.parse('fieldnotes://notes/weekend'),
  ),
  SearchItem(
    id: 'pasta',
    domain: 'notes',
    title: 'Lemon pasta',
    description: 'A quick dinner with lemon, parmesan, and fresh basil.',
    textContent:
        'Boil pasta. Mix lemon zest, olive oil, parmesan, basil, and a little pasta water. Ready in 20 minutes.',
    keywords: ['recipe', 'food', 'dinner'],
    deepLink: Uri.parse('fieldnotes://notes/pasta'),
  ),
  SearchItem(
    id: 'launch',
    domain: 'notes',
    title: 'Launch checklist',
    description: 'Finish onboarding, review translations, and record the demo.',
    textContent:
        'Before releasing the app: test sign-in, verify translations, check accessibility labels, and record a short demo.',
    keywords: ['work', 'release', 'app'],
    deepLink: Uri.parse('fieldnotes://notes/launch'),
  ),
];

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final _index = SystemSearchIndex();
  final _query = TextEditingController();
  final _notes = [...sampleNotes];
  SearchCapabilities? _capabilities;
  SearchResponse _response = const SearchResponse.empty();
  StreamSubscription<SearchActivation>? _subscription;
  Timer? _debounce;
  int _revision = 0;
  bool _busy = true;
  bool _semantic = true;
  bool _systemVisible = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final capabilities = await _index.getCapabilities();
      if (!mounted) return;
      setState(() => _capabilities = capabilities);
      if (!capabilities.indexing) {
        setState(() {
          _busy = false;
          _error = 'Native search unavailable on this device.';
        });
        return;
      }
      if (capabilities.activationEvents) {
        _subscription = _index.activations.listen(
          (event) {
            final match = _notes.where(
              (n) => n.id == event.id && n.domain == event.domain,
            );
            if (mounted && match.isNotEmpty) _open(match.first);
          },
          onError: (Object error) {
            if (mounted) setState(() => _error = '$error');
          },
        );
      }
      await _index.configure(androidSystemVisibility: false);
      await _index.indexAll(_notes);
      if (mounted) setState(() => _busy = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _mutate(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted && _query.text.trim().isNotEmpty) await _search();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _search() async {
    final revision = ++_revision;
    try {
      final response = await _index.search(
        _query.text,
        domain: 'notes',
        semantic: _semantic,
      );
      if (mounted && revision == _revision) {
        setState(() {
          _response = response;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && revision == _revision) setState(() => _error = '$error');
    }
  }

  void _changed(String text) {
    ++_revision;
    _debounce?.cancel();
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  void _open(SearchItem note) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(note.textContent ?? note.description ?? ''),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  children: note.keywords
                      .map((k) => Chip(label: Text(k)))
                      .toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _add() async {
    final title = TextEditingController();
    final body = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New note'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              TextField(
                controller: body,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Note'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (title.text.trim().isNotEmpty) Navigator.pop(context, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final titleText = title.text.trim();
    final bodyText = body.text.trim();
    // Dialog routes may still use their controllers during the closing animation.
    Future<void>.delayed(const Duration(seconds: 1), () {
      title.dispose();
      body.dispose();
    });
    if (saved != true || !mounted) return;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final note = SearchItem(
      id: id,
      domain: 'notes',
      title: titleText,
      textContent: bodyText,
      description: bodyText,
      deepLink: Uri.parse('fieldnotes://notes/$id'),
    );
    await _mutate(() async {
      await _index.index(note);
      if (mounted) setState(() => _notes.insert(0, note));
    });
  }

  @override
  void dispose() {
    _revision++;
    _debounce?.cancel();
    _subscription?.cancel();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.text.trim().isNotEmpty;
    final items = searching ? _response.items : _notes;
    final ready = _capabilities?.indexing == true && !_busy;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fieldnotes'),
        actions: [
          IconButton(
            tooltip: 'Reindex notes',
            icon: const Icon(Icons.sync),
            onPressed: ready
                ? () => _mutate(() => _index.indexAll(_notes))
                : null,
          ),
          IconButton(
            tooltip: 'Clear note index',
            icon: const Icon(Icons.playlist_remove),
            onPressed: ready
                ? () => _mutate(() => _index.removeDomain('notes'))
                : null,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _query,
                    onChanged: _changed,
                    enabled: ready,
                    decoration: InputDecoration(
                      hintText: 'Search notes',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: searching
                          ? IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _query.clear();
                                _changed('');
                              },
                            )
                          : null,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                if (_capabilities?.semanticSearch == true)
                  SwitchListTile(
                    title: const Text('Semantic search'),
                    value: _semantic,
                    onChanged: ready
                        ? (value) {
                            setState(() => _semantic = value);
                            _search();
                          }
                        : null,
                  ),
                if (_capabilities?.systemSurface ==
                    SearchSystemSurface.deviceDependent)
                  SwitchListTile(
                    title: const Text('Allow system search'),
                    value: _systemVisible,
                    onChanged: ready
                        ? (value) => _mutate(() async {
                            await _index.configure(
                              androidSystemVisibility: value,
                            );
                            if (mounted) setState(() => _systemVisible = value);
                          })
                        : null,
                  ),
                if (_busy) const LinearProgressIndicator(minHeight: 2),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (searching && _response.suggestions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      children: _response.suggestions
                          .map(
                            (text) => ActionChip(
                              label: Text(text),
                              onPressed: () {
                                _query.text = text;
                                _changed(text);
                              },
                            ),
                          )
                          .toList(),
                    ),
                  ),
                Expanded(
                  child: items.isEmpty
                      ? const Center(child: Text('No matching notes'))
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 96),
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final note = items[i];
                            return ListTile(
                              leading: const Icon(Icons.description_outlined),
                              title: Text(note.title),
                              subtitle: Text(
                                note.description ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _open(note),
                              trailing: IconButton(
                                tooltip: 'Delete note',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: ready
                                    ? () => _mutate(() async {
                                        await _index.remove([
                                          note.id,
                                        ], domain: note.domain);
                                        if (mounted) {
                                          setState(
                                            () => _notes.removeWhere(
                                              (n) =>
                                                  n.id == note.id &&
                                                  n.domain == note.domain,
                                            ),
                                          );
                                        }
                                      })
                                    : null,
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New note',
        onPressed: ready ? _add : null,
        child: const Icon(Icons.add),
      ),
    );
  }
}
