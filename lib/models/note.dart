import 'sync_status.dart';

/// Em qual "visão" a lista de notas está sendo exibida.
enum NoteView { active, archived, trash }

/// Opções de ordenação da lista de notas.
enum NoteSort {
  updatedDesc('Última atualização (mais recente)', 'updated_at DESC'),
  updatedAsc('Última atualização (mais antiga)', 'updated_at ASC'),
  createdDesc('Data de criação (mais recente)', 'created_at DESC'),
  createdAsc('Data de criação (mais antiga)', 'created_at ASC');

  final String label;

  /// Trecho `ORDER BY` usado na consulta SQLite.
  final String orderBy;

  const NoteSort(this.label, this.orderBy);
}

int _asInt(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;

class Note {
  static const Object _keep = Object();

  /// Mesmo ID no SQLite e no Firestore (users/{uid}/notes/{id}).
  final String id;
  final String uid;
  final String title;
  final String content;
  final String? categoryId;

  /// Datas em milissegundos desde a época (epoch).
  final int createdAt;
  final int updatedAt;

  final bool archived;

  /// Se não for nulo, a nota está na lixeira (exclusão temporária).
  final int? deletedAt;

  /// Veja [SyncStatus]. Existe só no SQLite, não vai para o Firestore.
  final int syncStatus;

  const Note({
    required this.id,
    required this.uid,
    required this.title,
    required this.content,
    this.categoryId,
    required this.createdAt,
    required this.updatedAt,
    this.archived = false,
    this.deletedAt,
    this.syncStatus = SyncStatus.pending,
  });

  bool get isTrashed => deletedAt != null;

  /// Cria uma cópia alterada. Para [categoryId] e [deletedAt], passar `null`
  /// explicitamente limpa o campo; omitir mantém o valor atual.
  Note copyWith({
    String? title,
    String? content,
    Object? categoryId = _keep,
    int? updatedAt,
    bool? archived,
    Object? deletedAt = _keep,
    int? syncStatus,
  }) {
    return Note(
      id: id,
      uid: uid,
      title: title ?? this.title,
      content: content ?? this.content,
      categoryId: identical(categoryId, _keep)
          ? this.categoryId
          : categoryId as String?,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      archived: archived ?? this.archived,
      deletedAt:
          identical(deletedAt, _keep) ? this.deletedAt : deletedAt as int?,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  // ---------------------------------------------------------------- SQLite

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uid': uid,
      'title': title,
      'content': content,
      'category_id': categoryId,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'archived': archived ? 1 : 0,
      'deleted_at': deletedAt,
      'sync_status': syncStatus,
    };
  }

  factory Note.fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'] as String,
      uid: map['uid'] as String,
      title: map['title'] as String,
      content: map['content'] as String,
      categoryId: map['category_id'] as String?,
      createdAt: _asInt(map['created_at']),
      updatedAt: _asInt(map['updated_at']),
      archived: _asInt(map['archived']) == 1,
      deletedAt: map['deleted_at'] == null ? null : _asInt(map['deleted_at']),
      syncStatus: _asInt(map['sync_status'], SyncStatus.pending),
    );
  }

  // ------------------------------------------------------------- Firestore

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'title': title,
      'content': content,
      'categoryId': categoryId,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'archived': archived,
      'deletedAt': deletedAt,
    };
  }

  factory Note.fromFirestore(String id, String uid, Map<String, dynamic> data) {
    return Note(
      id: id,
      uid: uid,
      title: (data['title'] as String?) ?? '',
      content: (data['content'] as String?) ?? '',
      categoryId: data['categoryId'] as String?,
      createdAt: _asInt(data['createdAt']),
      updatedAt: _asInt(data['updatedAt']),
      archived: (data['archived'] as bool?) ?? false,
      deletedAt: data['deletedAt'] == null ? null : _asInt(data['deletedAt']),
      syncStatus: SyncStatus.synced,
    );
  }
}
