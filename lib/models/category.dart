import 'sync_status.dart';

int _asInt(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;

/// Categoria usada para organizar as notas (Estudos, Trabalho, Pessoal ou
/// qualquer outra criada pelo usuário).
class Category {
  final String id;
  final String uid;
  final String name;
  final int createdAt;
  final int updatedAt;
  final int syncStatus;

  const Category({
    required this.id,
    required this.uid,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = SyncStatus.pending,
  });

  Category copyWith({String? name, int? updatedAt, int? syncStatus}) {
    return Category(
      id: id,
      uid: uid,
      name: name ?? this.name,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uid': uid,
      'name': name,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'sync_status': syncStatus,
    };
  }

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'] as String,
      uid: map['uid'] as String,
      name: map['name'] as String,
      createdAt: _asInt(map['created_at']),
      updatedAt: _asInt(map['updated_at']),
      syncStatus: _asInt(map['sync_status'], SyncStatus.pending),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'name': name,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory Category.fromFirestore(
    String id,
    String uid,
    Map<String, dynamic> data,
  ) {
    return Category(
      id: id,
      uid: uid,
      name: (data['name'] as String?) ?? '',
      createdAt: _asInt(data['createdAt']),
      updatedAt: _asInt(data['updatedAt']),
      syncStatus: SyncStatus.synced,
    );
  }
}
