import 'package:flutter/foundation.dart';

/// A named, saved selection for offline preparation. It stores a snapshot of
/// playable identities rather than acting as a background rule.
@immutable
class OfflinePlan {
  const OfflinePlan({
    required this.id,
    required this.name,
    required this.songIds,
    required this.createdAtMs,
  });

  final String id;
  final String name;
  final List<String> songIds;
  final int createdAtMs;

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'songIds': songIds,
        'createdAtMs': createdAtMs,
      };

  factory OfflinePlan.fromJson(Map<String, dynamic> json) => OfflinePlan(
        id: json['id'] as String,
        name: json['name'] as String,
        songIds: (json['songIds'] as List<dynamic>? ?? const []).cast<String>(),
        createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
      );
}
