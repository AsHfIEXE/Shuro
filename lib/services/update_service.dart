import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class UpdateInfo {
  final String current, latest, url, notes;
  final bool newer;
  const UpdateInfo({
    required this.current,
    required this.latest,
    required this.url,
    required this.notes,
    required this.newer,
  });
}

/// Checks the project's GitHub releases for a newer tagged version.
/// No API token, no background polling - only when the user asks.
class UpdateService {
  static const _repo = 'AsHfIEXE/Shuro';

  Future<UpdateInfo?> check() async {
    final info = await PackageInfo.fromPlatform();
    final res = await http
        .get(Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'Shuro-UpdateCheck'
            })
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final j = json.decode(res.body) as Map<String, dynamic>;
    final tag = (j['tag_name'] as String? ?? '').replaceFirst(RegExp(r'^v'), '');
    if (tag.isEmpty) return null;
    return UpdateInfo(
      current: info.version,
      latest: tag,
      url: (j['html_url'] as String?) ?? 'https://github.com/$_repo/releases',
      notes: (j['body'] as String?) ?? '',
      newer: _cmp(tag, info.version) > 0,
    );
  }

  static int _cmp(String a, String b) {
    final pa = a.split('.').map(int.tryParse).toList();
    final pb = b.split('.').map(int.tryParse).toList();
    for (var i = 0; i < 3; i++) {
      final x = i < pa.length ? (pa[i] ?? 0) : 0;
      final y = i < pb.length ? (pb[i] ?? 0) : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}
