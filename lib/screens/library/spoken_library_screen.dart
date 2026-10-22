import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/spoken_media.dart';
import '../../state/spoken_library_state.dart';
import '../../theme/app_theme.dart';

/// Separate books/podcasts workspace. It deliberately does not flatten a
/// show into a playable row: only whole books and episode rows are playable.
class SpokenLibraryScreen extends StatelessWidget {
  const SpokenLibraryScreen({super.key});

  Future<void> _connect(BuildContext context) async {
    final url = TextEditingController();
    final token = TextEditingController();
    final name = TextEditingController(text: 'Audiobookshelf');
    final values = await showDialog<(String, String, String)>(
        context: context,
        builder: (context) => AlertDialog(
              backgroundColor: kCardColor,
              title: const Text('Connect Audiobookshelf'),
              content: SizedBox(
                  width: 420,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: name,
                        decoration: const InputDecoration(
                            labelText: 'Connection name')),
                    TextField(
                        controller: url,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                            labelText: 'Server URL',
                            hintText: 'https://books.example.com')),
                    TextField(
                        controller: token,
                        obscureText: true,
                        decoration: const InputDecoration(
                            labelText: 'API token',
                            helperText: 'Stored in secure device storage.')),
                  ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(
                        context, (name.text, url.text, token.text)),
                    child: const Text('Connect'))
              ],
            ));
    url.dispose();
    token.dispose();
    name.dispose();
    if (values == null || !context.mounted) return;
    await context
        .read<SpokenLibraryState>()
        .connect(name: values.$1, url: values.$2, token: values.$3);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SpokenLibraryState>();
    return Scaffold(
        backgroundColor: kSurfaceColor,
        appBar: AppBar(
            backgroundColor: kSurfaceColor,
            title: const Text('Books & podcasts'),
            actions: [
              IconButton(
                  tooltip: 'Refresh libraries',
                  onPressed: state.connection == null || state.loading
                      ? null
                      : state.refresh,
                  icon: const Icon(Icons.refresh_rounded)),
            ]),
        body: state.connection == null
            ? _ConnectState(onConnect: () => _connect(context))
            : RefreshIndicator(
                onRefresh: state.refresh,
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      Text(state.connection!.name,
                          style: headingFont(
                              color: kTextColor,
                              fontSize: 22,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                          'Books retain a whole-book timeline. Podcast episodes retain independent progress.',
                          style: GoogleFonts.getFont(currentFontFamily,
                              color: kMutedTextColor, height: 1.4)),
                      if (state.loading)
                        const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator())),
                      if (state.error != null)
                        _ErrorBanner(message: state.error!),
                      for (final library in state.libraries)
                        _LibrarySection(
                            library: library,
                            items:
                                state.itemsByLibrary[library.id] ?? const []),
                    ]),
              ));
  }
}

class _ConnectState extends StatelessWidget {
  const _ConnectState({required this.onConnect});
  final VoidCallback onConnect;
  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.menu_book_rounded, size: 52, color: kBrandColor),
            const SizedBox(height: 16),
            Text('Bring your spoken library together',
                style: headingFont(
                    color: kTextColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
                'Connect an Audiobookshelf server for audiobooks and podcasts. Music stays in its own Navidrome workspace.',
                textAlign: TextAlign.center,
                style: GoogleFonts.getFont(currentFontFamily,
                    color: kMutedTextColor, height: 1.45)),
            const SizedBox(height: 20),
            FilledButton.icon(
                onPressed: onConnect,
                icon: const Icon(Icons.link_rounded),
                label: const Text('Connect Audiobookshelf'))
          ])));
}

class _LibrarySection extends StatelessWidget {
  const _LibrarySection({required this.library, required this.items});
  final SpokenLibrary library;
  final List<SpokenItem> items;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 28),
        Text(
            '${library.name} · ${library.type == SpokenMediaType.book ? 'Audiobooks' : 'Podcasts'}',
            style: headingFont(
                color: kTextColor, fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        if (items.isEmpty)
          Text('No items found in this library.',
              style: GoogleFonts.getFont(currentFontFamily,
                  color: kMutedTextColor))
        else
          ...items.map((item) => Card(
              color: kCardColor,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                  leading: CircleAvatar(
                      backgroundColor: kBrandColor.withValues(alpha: .35),
                      child: Icon(item.isBook
                          ? Icons.menu_book_rounded
                          : Icons.podcasts_rounded)),
                  title: Text(item.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      item.isBook
                          ? '${item.creator} · ${(item.duration.inMinutes / 60).toStringAsFixed(1)} hr'
                          : '${item.creator} · ${item.episodes.length} episodes',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  trailing: item.isBook
                      ? const Icon(Icons.play_arrow_rounded)
                      : const Icon(Icons.chevron_right_rounded))))
      ]);
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
          color: Colors.red.withValues(alpha: .16),
          child: ListTile(
              leading: const Icon(Icons.error_outline_rounded,
                  color: Colors.redAccent),
              title: Text(message))));
}
