import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_service.dart';

/// "Check for updates" flow: spinner while GitHub answers, then either the
/// up-to-date notice or the download dialog.
Future<void> showUpdateCheck(BuildContext context) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  UpdateInfo? info;
  try {
    info = await UpdateService().check();
  } catch (_) {
    info = null;
  }
  if (!context.mounted) return;
  Navigator.of(context).pop(); // spinner
  if (info == null) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not reach GitHub. Try again later.')));
    return;
  }
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(info!.newer ? 'Update available' : 'You are up to date'),
      content: Text(info.newer
          ? 'Shuro ${info.latest} is out (you have ${info.current}).'
          : 'Shuro ${info.current} is the latest release.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close')),
        if (info.newer)
          FilledButton(
            onPressed: () {
              launchUrl(Uri.parse(info!.url),
                  mode: LaunchMode.externalApplication);
              Navigator.pop(dialogContext);
            },
            child: const Text('Download'),
          ),
      ],
    ),
  );
}
