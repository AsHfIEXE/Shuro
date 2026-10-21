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
  });

  final String id;
  final String name;
  final String description;
  final List<ShelfItem> items;

  PersonalShelf copyWith(
          {String? name, String? description, List<ShelfItem>? items}) =>
      PersonalShelf(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        items: items ?? this.items,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'items': items.map((item) => item.toJson()).toList(),
      };

  factory PersonalShelf.fromJson(Map<String, dynamic> json) => PersonalShelf(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        items: (json['items'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ShelfItem.fromJson)
            .toList(),
      );
}
