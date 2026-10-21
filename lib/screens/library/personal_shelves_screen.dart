import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/personal_shelf.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/page_transitions.dart';

class PersonalShelvesScreen extends StatelessWidget {
  const PersonalShelvesScreen({super.key});

  Future<void> _create(BuildContext context) async {
    final values = await _shelfEditor(context);
    if (values == null || !context.mounted) return;
    context
        .read<AppState>()
        .createPersonalShelf(values.$1, description: values.$2);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      backgroundColor: kSurfaceColor,
      appBar: AppBar(
        backgroundColor: kSurfaceColor,
        title: Text('Personal shelves',
            style: headingFont(
                color: kTextColor, fontSize: 20, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: 'Create shelf',
            onPressed: state.personalShelves.length >= 100
                ? null
                : () => _create(context),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: state.personalShelves.isEmpty
          ? _ShelfEmptyState(onCreate: () => _create(context))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemCount: state.personalShelves.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final shelf = state.personalShelves[index];
                return Card(
                  color: kCardColor,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    minVerticalPadding: 12,
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(colors: kBrandGradient),
                      ),
                      child: const Icon(Icons.auto_awesome_rounded,
                          color: Colors.white),
                    ),
                    title: Text(shelf.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: Colors.white, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      shelf.description.isNotEmpty
                          ? '${shelf.description}\n${shelf.items.length} saved items'
                          : '${shelf.items.length} saved items',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: kMutedTextColor, fontSize: 12),
                    ),
                    isThreeLine: shelf.description.isNotEmpty,
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: kMutedTextColor),
                    onTap: () => Navigator.of(context).push(drillDownRoute(
                        PersonalShelfDetailScreen(shelfId: shelf.id))),
                  ),
                );
              },
            ),
    );
  }
}

class _ShelfEmptyState extends StatelessWidget {
  const _ShelfEmptyState({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.auto_awesome_rounded,
                size: 52, color: kBrandColor),
            const SizedBox(height: 16),
            Text('Make a shelf your own',
                textAlign: TextAlign.center,
                style: headingFont(
                    color: kTextColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
                'Bring songs, albums, artists and playlists together in an ordered collection that stays with you.',
                textAlign: TextAlign.center,
                style: GoogleFonts.getFont(currentFontFamily,
                    color: kMutedTextColor, height: 1.45)),
            const SizedBox(height: 20),
            FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create a shelf')),
          ]),
        ),
      );
}

class PersonalShelfDetailScreen extends StatelessWidget {
  const PersonalShelfDetailScreen({super.key, required this.shelfId});
  final String shelfId;

  Future<void> _addSongs(BuildContext context, AppState state) async {
    final selected = await showDialog<List<ShelfItem>>(
      context: context,
      builder: (_) => _AddShelfItemsDialog(
          state: state,
          initialItems: state.personalShelves
              .where((shelf) => shelf.id == shelfId)
              .expand((shelf) => shelf.items)
              .toList()),
    );
    if (selected == null || !context.mounted) return;
    state.addItemsToPersonalShelf(shelfId, selected);
  }

  Future<void> _edit(BuildContext context, PersonalShelf shelf) async {
    final values = await _shelfEditor(context,
        name: shelf.name, description: shelf.description);
    if (values != null && context.mounted) {
      context
          .read<AppState>()
          .renamePersonalShelf(shelf.id, values.$1, values.$2);
    }
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kCardColor,
        title: const Text('Delete this shelf?'),
        content: const Text(
            'The saved collection will be removed. Your music files and playlists stay untouched.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      context.read<AppState>().deletePersonalShelf(shelfId);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final shelf =
        state.personalShelves.where((item) => item.id == shelfId).firstOrNull;
    if (shelf == null)
      return const Scaffold(
          body: Center(child: Text('This shelf is no longer available.')));
    final songs = state.songsForPersonalShelf(shelf);
    final player = context.read<PlayerController>();
    return Scaffold(
      backgroundColor: kSurfaceColor,
      appBar: AppBar(
        backgroundColor: kSurfaceColor,
        title: Text(shelf.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
              tooltip: 'Edit shelf',
              onPressed: () => _edit(context, shelf),
              icon: const Icon(Icons.edit_outlined)),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') _delete(context);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete shelf'))
            ],
          ),
        ],
      ),
      body: Column(children: [
        if (shelf.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text(shelf.description,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kMutedTextColor, height: 1.4))),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            Text('${shelf.items.length} saved · ${songs.length} playable',
                style: GoogleFonts.getFont(currentFontFamily,
                    color: kMutedTextColor, fontSize: 12)),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: shelf.items.length >= 500
                  ? null
                  : () => _addSongs(context, state),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add items'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: songs.isEmpty
                  ? null
                  : () => player.playSong(songs.first, queue: songs),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Play'),
            ),
          ]),
        ),
        Expanded(
          child: shelf.items.isEmpty
              ? Center(
                  child: Text('Add songs to start your collection.',
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: kMutedTextColor)))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: shelf.items.length,
                  onReorderItem: (oldIndex, newIndex) =>
                      state.reorderPersonalShelf(shelf.id, oldIndex, newIndex),
                  itemBuilder: (context, index) {
                    final item = shelf.items[index];
                    final song = item.type == ShelfItemType.song
                        ? state.songById(item.id)
                        : null;
                    final label = song?.title ??
                        switch (item.type) {
                          ShelfItemType.song => 'Unavailable song',
                          ShelfItemType.album =>
                            state.albumById(item.id)?.title ??
                                'Unavailable album',
                          ShelfItemType.artist =>
                            state.artistById(item.id)?.name ??
                                'Unavailable artist',
                          ShelfItemType.playlist => state.playlists
                                  .where((p) => p.id == item.id)
                                  .firstOrNull
                                  ?.name ??
                              'Unavailable playlist',
                        };
                    return ListTile(
                      key: ValueKey('${item.type.name}:${item.id}'),
                      leading: song?.artwork == null
                          ? const CircleAvatar(
                              backgroundColor: kCardColor,
                              child: Icon(Icons.music_note_rounded,
                                  color: kBrandColor))
                          : CircleAvatar(backgroundImage: song!.artwork),
                      title: Text(label,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: song == null
                          ? Text(item.type.name)
                          : Text(song.artist,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (song != null)
                          IconButton(
                              tooltip: 'Play from here',
                              onPressed: () =>
                                  player.playSong(song, queue: songs),
                              icon: const Icon(Icons.play_arrow_rounded)),
                        IconButton(
                            tooltip: 'Remove',
                            onPressed: () =>
                                state.removePersonalShelfItem(shelf.id, index),
                            icon: const Icon(Icons.close_rounded)),
                        const Icon(Icons.drag_handle_rounded,
                            color: kMutedTextColor),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class _ShelfCandidate {
  const _ShelfCandidate(this.item, this.title, this.subtitle);
  final ShelfItem item;
  final String title;
  final String subtitle;
}

class _AddShelfItemsDialog extends StatefulWidget {
  const _AddShelfItemsDialog({required this.state, required this.initialItems});
  final AppState state;
  final List<ShelfItem> initialItems;

  @override
  State<_AddShelfItemsDialog> createState() => _AddShelfItemsDialogState();
}

class _AddShelfItemsDialogState extends State<_AddShelfItemsDialog> {
  String _key(ShelfItem item) => '${item.type.name}:${item.id}';
  late final Set<String> _selectedIds = widget.initialItems.map(_key).toSet();
  late final List<ShelfItem> _selectedItems = [...widget.initialItems];
  String _query = '';

  List<_ShelfCandidate> _candidates(ShelfItemType type) {
    final state = widget.state;
    return switch (type) {
      ShelfItemType.song => state.allSongs
          .map((song) => _ShelfCandidate(
              ShelfItem(type: type, id: song.id), song.title, song.artist))
          .toList(),
      ShelfItemType.album => state.catalogAlbums
          .map((album) => _ShelfCandidate(
              ShelfItem(type: type, id: album.id),
              album.title,
              '${album.artist} · ${album.year == 0 ? 'Album' : album.year}'))
          .toList(),
      ShelfItemType.artist => state.catalogArtists
          .map((artist) => _ShelfCandidate(
              ShelfItem(type: type, id: artist.id), artist.name, 'Artist'))
          .toList(),
      ShelfItemType.playlist => state.playlists
          .map((playlist) => _ShelfCandidate(
              ShelfItem(type: type, id: playlist.id),
              playlist.name,
              playlist.isSmart
                  ? 'Smart playlist'
                  : '${playlist.songIds.length} songs'))
          .toList(),
    };
  }

  Widget _tab(ShelfItemType type) {
    final query = _query.toLowerCase();
    final candidates = _candidates(type)
        .where((candidate) =>
            candidate.title.toLowerCase().contains(query) ||
            candidate.subtitle.toLowerCase().contains(query))
        .take(500)
        .toList();
    if (candidates.isEmpty)
      return const Center(child: Text('Nothing to add here yet.'));
    return ListView.builder(
      itemCount: candidates.length,
      itemBuilder: (context, index) {
        final candidate = candidates[index];
        final key = _key(candidate.item);
        return CheckboxListTile(
          value: _selectedIds.contains(key),
          contentPadding: EdgeInsets.zero,
          title: Text(candidate.title,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(candidate.subtitle,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          onChanged: (checked) => setState(() {
            if (checked == true) {
              if (_selectedIds.add(key)) _selectedItems.add(candidate.item);
            } else {
              _selectedIds.remove(key);
              _selectedItems.removeWhere((item) => _key(item) == key);
            }
          }),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: ShelfItemType.values.length,
      child: AlertDialog(
        backgroundColor: kCardColor,
        title: const Text('Add to shelf'),
        content: SizedBox(
          width: (MediaQuery.sizeOf(context).width - 56).clamp(280, 480),
          height: 470,
          child: Column(children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  labelText: 'Search music and playlists'),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
            const SizedBox(height: 4),
            const TabBar(isScrollable: true, tabs: [
              Tab(text: 'Songs'),
              Tab(text: 'Albums'),
              Tab(text: 'Artists'),
              Tab(text: 'Playlists'),
            ]),
            Expanded(
              child:
                  TabBarView(children: ShelfItemType.values.map(_tab).toList()),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, _selectedItems),
              child: Text('Add ${_selectedItems.length}')),
        ],
      ),
    );
  }
}

Future<(String, String)?> _shelfEditor(BuildContext context,
    {String name = '', String description = ''}) async {
  final nameController = TextEditingController(text: name);
  final descriptionController = TextEditingController(text: description);
  final result = await showDialog<(String, String)>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: kCardColor,
      title: Text(name.isEmpty ? 'Create a shelf' : 'Edit shelf'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
            controller: nameController,
            autofocus: true,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Name')),
        TextField(
            controller: descriptionController,
            maxLength: 180,
            maxLines: 2,
            decoration:
                const InputDecoration(labelText: 'Description (optional)')),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final value = nameController.text.trim();
            if (value.isNotEmpty)
              Navigator.pop(
                  context, (value, descriptionController.text.trim()));
          },
          child: Text(name.isEmpty ? 'Create' : 'Save'),
        ),
      ],
    ),
  );
  nameController.dispose();
  descriptionController.dispose();
  return result;
}
