import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/song.dart';
import '../../services/library_health.dart';
import '../../state/app_state.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/desktop_tokens.dart';
import '../../widgets/motion.dart' show Entrance;

/// Read-only health report over the songs already loaded on this device.
///
/// It never talks to the server and never edits metadata: it counts what the
/// current library objects can prove, and says "not reported" style things
/// plainly instead of implying a fix happened.
class LibraryHealthScreen extends StatelessWidget {
  const LibraryHealthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final songs = context.watch<AppState>().allSongs;
    final report = LibraryHealthReport.build(songs);

    return Scaffold(
      backgroundColor: kSurfaceColor,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Text(
                    'Library health',
                    style: DesktopTokens.section(headingFont(
                      color: kTextColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    )),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Checked on device from the ${report.totalSongs} tracks already '
                'loaded. Nothing is uploaded and nothing is changed.',
                style: GoogleFonts.getFont(currentFontFamily,
                    color: kStatusText, fontSize: 12, height: 16 / 12),
              ),
            ),
            if (report.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
                child: Column(
                  children: [
                    Icon(Icons.verified_rounded,
                        size: 34, color: kBrandColor.withValues(alpha: 0.9)),
                    const SizedBox(height: 12),
                    Text('No problems found',
                        style: GoogleFonts.getFont(currentFontFamily,
                            color: kTextColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(
                      report.totalSongs == 0
                          ? 'There are no tracks loaded yet, so there was '
                              'nothing to check.'
                          : 'Every loaded track has artwork, an artist, an '
                              'album and a length, and no exact duplicates '
                              'were found.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: kMutedTextColor, fontSize: 12, height: 1.5),
                    ),
                  ],
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  '${report.totalIssues} track${report.totalIssues == 1 ? '' : 's'} '
                  'across ${report.issues.length} '
                  'check${report.issues.length == 1 ? '' : 's'}',
                  style: GoogleFonts.getFont(currentFontFamily,
                      color: kBrandColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6),
                ),
              ),
              for (final (i, issue) in report.issues.indexed)
                Entrance(
                  delay: Entrance.stagger(i),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: _IssueSection(issue: issue),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _IssueSection extends StatefulWidget {
  final HealthIssue issue;

  const _IssueSection({required this.issue});

  @override
  State<_IssueSection> createState() => _IssueSectionState();
}

class _IssueSectionState extends State<_IssueSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final issue = widget.issue;
    final shown = _expanded ? issue.songs : issue.songs.take(3).toList();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: kRaisedColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kHairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    issue.title,
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: kTextColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: kBrandColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${issue.count}',
                      style: GoogleFonts.getFont(currentFontFamily,
                          color: kVioletLight,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              issue.detail,
              style: GoogleFonts.getFont(currentFontFamily,
                  color: kStatusText, fontSize: 12, height: 16 / 12),
            ),
            const SizedBox(height: 4),
            for (final song in shown) _IssueRow(song: song, queue: issue.songs),
            if (issue.count > 3)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(
                    _expanded ? 'Show fewer' : 'Show all ${issue.count}',
                    style: GoogleFonts.getFont(currentFontFamily,
                        color: _expanded ? kStatusText : kVioletLight,
                        fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _IssueRow extends StatelessWidget {
  final Song song;
  final List<Song> queue;

  const _IssueRow({required this.song, required this.queue});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(Icons.music_note_rounded, size: 16, color: kMutedTextColor),
      title: Text(song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.getFont(currentFontFamily,
              color: kTextColor, fontSize: 13)),
      subtitle: Text(song.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.getFont(currentFontFamily,
              color: kMutedTextColor, fontSize: 11.5)),
      trailing: IconButton(
        tooltip: 'Play',
        icon: const Icon(Icons.play_arrow_rounded, size: 18),
        onPressed: () =>
            context.read<PlayerController>().playSong(song, queue: queue),
      ),
      onTap: () =>
          context.read<PlayerController>().playSong(song, queue: queue),
    );
  }
}
