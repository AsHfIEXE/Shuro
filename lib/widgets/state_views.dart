import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Shared "system state" views (15. System states in the spec) so every
/// screen handles loading/empty/error/offline consistently instead of each
/// screen inventing its own.

class LoadingView extends StatelessWidget {
  final String? message;
  const LoadingView({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: kBrandColor),
          if (message != null) ...[
            const SizedBox(height: 14),
            Text(message!, style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}

class EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyStateView({super.key, required this.icon, required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: kMutedTextColor, size: 42),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center,
                style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, textAlign: TextAlign.center,
                  style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 13)),
            ],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

class ErrorStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const ErrorStateView({
    super.key,
    this.icon = Icons.error_outline_rounded,
    required this.title,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.redAccent.shade100, size: 42),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center,
                style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center,
                style: GoogleFonts.getFont(currentFontFamily, color: kMutedTextColor, fontSize: 13)),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              OutlinedButton(
                onPressed: onRetry,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: kDividerColor)),
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Slim banner for "Offline" / "No connection" — sits at the top of a
/// screen without blocking the (possibly cached) content underneath it.
class OfflineBanner extends StatelessWidget {
  final String message;
  const OfflineBanner({super.key, this.message = "You're offline — showing downloaded content"});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.amber.withValues(alpha: 0.12),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.amber, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: GoogleFonts.getFont(currentFontFamily, color: Colors.amber.shade100, fontSize: 12))),
        ],
      ),
    );
  }
}

/// Small red snackbar helper for transient errors (download failed,
/// playback error) rather than a full-screen state.
void showErrorSnackBar(BuildContext context, String message) {
  // Clear first: a queued stack of old snackbars used to play out one after
  // another, so a later error could appear long after the action that caused it
  // (and an older one could still be on screen when the new one was needed).
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      // Previously a dim translucent red bar with low-contrast text — readable
      // in a screenshot, illegible in the hand. Now: solid error surface,
      // white text, a leading icon, rounded and inset so it reads as a
      // deliberate alert rather than a rendering artifact.
      content: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.getFont(currentFontFamily, fontSize: 13, color: Colors.white, height: 1.35),
            ),
          ),
        ],
      ),
      backgroundColor: const Color(0xFFB3261E),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 6,
      duration: const Duration(seconds: 4),
    ),
  );
}

/// The neutral counterpart to [showErrorSnackBar] — for confirmations
/// ("Added 3 files", "Cleared", "Downloading…") that aren't errors and
/// shouldn't read as one. Every screen that was rolling its own plain
/// SnackBar for this now goes through here instead, so they all share one
/// look.
void showSuccessSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: GoogleFonts.getFont(currentFontFamily, fontSize: 13)),
      backgroundColor: kCardColor,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Shared yes/no confirmation for an action that removes or overwrites
/// something. Returns false when the user dismisses the dialog, so callers can
/// write `if (await confirmAction(...))`.
///
/// Destructive actions in this app used to fire immediately on a single tap —
/// removing a music folder, deleting a local song — with no confirmation and no
/// undo, which is how a mis-tap silently changed someone's library.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Remove',
  String cancelLabel = 'Cancel',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: kCardColor,
      title: Text(title, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
      content: Text(message, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white70, fontSize: 13, height: 1.45)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(cancelLabel, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white70, fontSize: 13)),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(
            confirmLabel,
            style: GoogleFonts.getFont(currentFontFamily, color: destructive ? Colors.redAccent.shade100 : kBrandColor, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Shared rename dialog — a text field pre-filled with the current name,
/// "Cancel"/"Save" — used by playlists (two entry points) and saved servers
/// so there's one place styling it instead of three near-identical copies.
/// Returns the trimmed new name, or null if cancelled, left blank, or
/// unchanged after trimming.
Future<String?> promptForRename(
  BuildContext context, {
  required String title,
  required String currentName,
  String? hintText,
}) async {
  final controller = TextEditingController(text: currentName);
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: kCardColor,
      title: Text(title, style: GoogleFonts.getFont(currentFontFamily, color: Colors.white, fontSize: 16)),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: GoogleFonts.getFont(currentFontFamily, color: Colors.white),
        decoration: InputDecoration(hintText: hintText, hintStyle: const TextStyle(color: kMutedTextColor)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(controller.text), child: const Text('Save')),
      ],
    ),
  );
  final trimmed = result?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

/// Shared runner for every "Add a music folder"/"Add files" entry point
/// (Home's empty state, Library's Local tab) — awaits [importFn]
/// (`appState.importLocalFolder`/`importLocalFiles`), shows a success
/// snackbar for however many files were added, and turns a failure into a
/// friendly error snackbar instead of an unhandled crash. The one failure
/// mode worth a specific message is [LocalImportUnsupportedException]
/// (running in a browser, where there's no real device filesystem to
/// import from); anything else gets a generic "couldn't import" message.
Future<void> runLocalImport(BuildContext context, Future<int> Function() importFn) async {
  try {
    final count = await importFn();
    if (!context.mounted) return;
    if (count > 0) showSuccessSnackBar(context, 'Added $count file${count == 1 ? '' : 's'}');
  } catch (e) {
    if (!context.mounted) return;
    showErrorSnackBar(context, e is LocalImportUnsupportedException ? e.message : "Couldn't import that — try again.");
  }
}
