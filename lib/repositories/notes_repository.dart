import 'dart:async';

import 'package:flutter/foundation.dart' hide Category;

import '../database/database_helper.dart';
import '../models/category.dart';
import '../models/note.dart';
import '../models/sync_status.dart';
import '../services/firestore_service.dart';
import '../utils/text_utils.dart';

/// Estado atual da sincronização, observado pela interface.
enum SyncState { idle, syncing, synced, offline }

/// Repositório: único ponto de acesso a notas e categorias para a interface.
///
/// Estratégia "local primeiro" (offline-first):
///  1. Toda alteração é gravada primeiro no SQLite, marcada como `pending`.
///  2. Em seguida tenta-se enviar ao Firestore (em segundo plano). Se der
///     certo, o registro vira `synced`; se falhar, continua `pending`.
///  3. `sync()` reconcilia os dois lados: traz o que mudou na nuvem, envia o
///     que está pendente e aplica exclusões. Conflitos: vence a alteração
///     com `updatedAt` mais recente (last-write-wins).
class NotesRepository {
  NotesRepository._();

  static final NotesRepository instance = NotesRepository._();

  final DatabaseHelper _local = DatabaseHelper.instance;
  final FirestoreService _remote = FirestoreService();

  /// A interface escuta este valor (padrão Observer) para mostrar o status.
  final ValueNotifier<SyncState> syncState = ValueNotifier(SyncState.idle);

  bool _syncing = false;

  static const Map<String, String> _defaultCategories = {
    'estudos': 'Estudos',
    'trabalho': 'Trabalho',
    'pessoal': 'Pessoal',
  };

  int _now() => DateTime.now().millisecondsSinceEpoch;

  // ============================================================ Categorias

  Future<List<Category>> getCategories(String uid) => _local.getCategories(uid);

  /// Cria as categorias iniciais uma única vez por usuário neste aparelho.
  /// Os IDs são fixos (`{uid}_default_estudos`...) para que dois aparelhos do
  /// mesmo usuário não gerem categorias duplicadas.
  Future<void> ensureDefaultCategories(String uid) async {
    final key = 'seeded_$uid';
    if (await _local.getMeta(key) != null) return;

    final now = _now();
    for (final entry in _defaultCategories.entries) {
      final id = '${uid}_default_${entry.key}';
      if (await _local.getCategory(id) == null) {
        await _local.upsertCategory(
          Category(
            id: id,
            uid: uid,
            name: entry.value,
            createdAt: now,
            updatedAt: now,
            syncStatus: SyncStatus.pending,
          ),
        );
      }
    }
    await _local.setMeta(key, '1');
  }

  /// Cria uma categoria. Se já existir uma com o mesmo nome (ignorando
  /// maiúsculas e acentos), devolve a existente.
  Future<Category> createCategory(String uid, String name) async {
    final cleanName = name.trim();
    final existing = await _local.getCategories(uid);
    for (final category in existing) {
      if (normalizeText(category.name) == normalizeText(cleanName)) {
        return category;
      }
    }

    final now = _now();
    final category = Category(
      id: _remote.newCategoryId(uid),
      uid: uid,
      name: cleanName,
      createdAt: now,
      updatedAt: now,
      syncStatus: SyncStatus.pending,
    );
    await _local.upsertCategory(category);
    unawaited(_pushCategory(category));
    return category;
  }

  /// Exclui a categoria. As notas que a usavam ficam sem categoria.
  Future<void> deleteCategory(String uid, Category category) async {
    final now = _now();

    final affected = await _local.getNotesByCategory(uid, category.id);
    for (final note in affected) {
      await _local.upsertNote(
        note.copyWith(
          categoryId: null,
          updatedAt: now,
          syncStatus: SyncStatus.pending,
        ),
      );
    }

    await _local.upsertCategory(
      category.copyWith(updatedAt: now, syncStatus: SyncStatus.pendingDelete),
    );
    unawaited(sync(uid));
  }

  // ================================================================ Notas

  /// Lista notas do SQLite. A pesquisa compara título e conteúdo sem diferenciar
  /// maiúsculas/minúsculas nem acentos. Funciona offline, pois usa só o banco
  /// local (que é mantido igual à nuvem pela sincronização).
  Future<List<Note>> getNotes(
    String uid, {
    NoteView view = NoteView.active,
    String query = '',
    String? categoryId,
    NoteSort sort = NoteSort.updatedDesc,
  }) async {
    final notes = await _local.getNotes(
      uid,
      view: view,
      categoryId: categoryId,
      sort: sort,
    );

    final q = normalizeText(query.trim());
    if (q.isEmpty) return notes;

    return notes
        .where(
          (n) =>
              normalizeText(n.title).contains(q) ||
              normalizeText(n.content).contains(q),
        )
        .toList();
  }

  Future<Note> createNote({
    required String uid,
    required String title,
    required String content,
    String? categoryId,
  }) async {
    final now = _now();
    final note = Note(
      id: _remote.newNoteId(uid),
      uid: uid,
      title: title,
      content: content,
      categoryId: categoryId,
      createdAt: now,
      updatedAt: now,
      syncStatus: SyncStatus.pending,
    );
    await _local.upsertNote(note);
    unawaited(_pushNote(note));
    return note;
  }

  Future<Note> updateNote(
    Note note, {
    required String title,
    required String content,
    String? categoryId,
  }) {
    return _mutate(
      note.copyWith(title: title, content: content, categoryId: categoryId),
    );
  }

  /// Arquivar / desarquivar.
  Future<Note> setArchived(Note note, bool archived) {
    return _mutate(note.copyWith(archived: archived));
  }

  /// Exclusão temporária: a nota vai para a lixeira.
  Future<Note> moveToTrash(Note note) {
    return _mutate(note.copyWith(deletedAt: _now()));
  }

  /// Recupera uma nota da lixeira.
  Future<Note> restore(Note note) {
    return _mutate(note.copyWith(deletedAt: null));
  }

  /// Exclusão definitiva (local e na nuvem).
  Future<void> deletePermanently(Note note) async {
    await _local.upsertNote(
      note.copyWith(syncStatus: SyncStatus.pendingDelete),
    );
    unawaited(_deleteRemoteNote(note));
  }

  Future<Note> _mutate(Note changed) async {
    final updated = changed.copyWith(
      updatedAt: _now(),
      syncStatus: SyncStatus.pending,
    );
    await _local.upsertNote(updated);
    unawaited(_pushNote(updated));
    return updated;
  }

  // ====================================================== Envio individual

  Future<void> _pushNote(Note note) async {
    try {
      await _remote.setNote(note);
      await _local.markNoteSynced(note.id, note.updatedAt);
      await _refreshStateAfterPush(note.uid);
    } catch (_) {
      syncState.value = SyncState.offline;
    }
  }

  Future<void> _pushCategory(Category category) async {
    try {
      await _remote.setCategory(category);
      await _local.markCategorySynced(category.id, category.updatedAt);
      await _refreshStateAfterPush(category.uid);
    } catch (_) {
      syncState.value = SyncState.offline;
    }
  }

  Future<void> _deleteRemoteNote(Note note) async {
    try {
      await _remote.deleteNote(note.uid, note.id);
      await _local.deleteNoteRow(note.id);
      await _refreshStateAfterPush(note.uid);
    } catch (_) {
      syncState.value = SyncState.offline;
    }
  }

  Future<void> _refreshStateAfterPush(String uid) async {
    if (await _local.countPending(uid) == 0) {
      syncState.value = SyncState.synced;
    }
  }

  Future<int> pendingCount(String uid) => _local.countPending(uid);

  // ========================================================== Sincronização

  /// Sincroniza SQLite <-> Firestore. Devolve `true` se terminou sem erro.
  /// Qualquer falha de rede interrompe a sincronização; o que já foi
  /// gravado continua consistente e o resto fica `pending` para a próxima vez.
  Future<bool> sync(String uid) async {
    if (_syncing) return false;
    _syncing = true;
    syncState.value = SyncState.syncing;

    try {
      await _syncCategories(uid);
      await _syncNotes(uid);
      syncState.value = SyncState.synced;
      return true;
    } catch (_) {
      syncState.value = SyncState.offline;
      return false;
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncNotes(String uid) async {
    // Se estiver offline, o fetch lança erro e nada abaixo é executado.
    final remoteList = await _remote.fetchNotes(uid);
    final remoteById = {for (final r in remoteList) r.id: r};
    final local = await _local.getAllNotes(uid);

    // 1) Exclusões definitivas feitas offline.
    for (final l in local.where((n) => n.syncStatus == SyncStatus.pendingDelete)) {
      await _remote.deleteNote(uid, l.id);
      await _local.deleteNoteRow(l.id);
      remoteById.remove(l.id);
    }

    final alive = local
        .where((n) => n.syncStatus != SyncStatus.pendingDelete)
        .toList();
    final localById = {for (final l in alive) l.id: l};

    // 2) Nuvem -> local: notas novas ou mais recentes na nuvem.
    for (final r in remoteById.values) {
      final l = localById[r.id];
      if (l == null || r.updatedAt > l.updatedAt) {
        await _local.upsertNote(r.copyWith(syncStatus: SyncStatus.synced));
      }
    }

    // 3) Local -> nuvem: notas pendentes que não perderam para a nuvem.
    for (final l in alive.where((n) => n.syncStatus == SyncStatus.pending)) {
      final r = remoteById[l.id];
      if (r == null || l.updatedAt >= r.updatedAt) {
        await _remote.setNote(l);
        await _local.markNoteSynced(l.id, l.updatedAt);
      }
    }

    // 4) Notas já sincronizadas que sumiram da nuvem (excluídas em outro
    //    aparelho) são removidas daqui.
    for (final l in alive.where(
      (n) =>
          n.syncStatus == SyncStatus.synced && !remoteById.containsKey(n.id),
    )) {
      await _local.deleteNoteRow(l.id);
    }
  }

  Future<void> _syncCategories(String uid) async {
    final remoteList = await _remote.fetchCategories(uid);
    final remoteById = {for (final r in remoteList) r.id: r};
    final local = await _local.getAllCategories(uid);

    for (final l in local.where((c) => c.syncStatus == SyncStatus.pendingDelete)) {
      await _remote.deleteCategory(uid, l.id);
      await _local.deleteCategoryRow(l.id);
      remoteById.remove(l.id);
    }

    final alive = local
        .where((c) => c.syncStatus != SyncStatus.pendingDelete)
        .toList();
    final localById = {for (final l in alive) l.id: l};

    for (final r in remoteById.values) {
      final l = localById[r.id];
      if (l == null || r.updatedAt > l.updatedAt) {
        await _local.upsertCategory(r.copyWith(syncStatus: SyncStatus.synced));
      }
    }

    for (final l in alive.where((c) => c.syncStatus == SyncStatus.pending)) {
      final r = remoteById[l.id];
      if (r == null || l.updatedAt >= r.updatedAt) {
        await _remote.setCategory(l);
        await _local.markCategorySynced(l.id, l.updatedAt);
      }
    }

    for (final l in alive.where(
      (c) =>
          c.syncStatus == SyncStatus.synced && !remoteById.containsKey(c.id),
    )) {
      await _local.deleteCategoryRow(l.id);
    }
  }
}
