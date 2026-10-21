import 'package:flutter/foundation.dart';

enum ShelfItemType { song, album, artist, playlist }

@immutable
class ShelfItem {
  const ShelfItem({required this.type, required this.id});

  final ShelfItemType type;
  final String id;

  Map<String, Object> toJson() => {'type': type.name, 'id': id};

  factory ShelfItem.fromJson(Map<String, dynamic> json) => ShelfItem(
        type: ShelfItemType.values.firstWhere(
          (type) => type.name == json['type'],
          orElse: () => ShelfItemType.song,
        ),
        id: json['id'] as String,
      );
}

@immutable
class PersonalShelf {
  const PersonalShelf({
    required this.id,
    required this.name,
    this.description = '',
    this.items = const [],
    this.coverBase64,
  });

  final String id;
  final String name;
  final String description;
  final List<ShelfItem> items;

  /// Device-local PNG/JPEG bytes. A shelf cover is intentionally never sent
  /// back to a Navidrome server or written into original music files.
  final String? coverBase64;

  PersonalShelf copyWith({
    String? name,
    String? description,
    List<ShelfItem>? items,
    String? coverBase64,
    bool clearCover = false,
  }) =>
      PersonalShelf(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        items: items ?? this.items,
        coverBase64: clearCover ? null : (coverBase64 ?? this.coverBase64),
      );

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'items': items.map((item) => item.toJson()).toList(),
        if (coverBase64 != null) 'coverBase64': coverBase64!,
      };

  factory PersonalShelf.fromJson(Map<String, dynamic> json) => PersonalShelf(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        coverBase64: json['coverBase64'] as String?,
        items: (json['items'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ShelfItem.fromJson)
            .toList(),
      );
}
