import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/category.dart';
import '../models/note.dart';

/// Fonte de dados remota (Cloud Firestore).
///
/// Estrutura na nuvem:
///   users/{uid}/notes/{noteId}
///   users/{uid}/categories/{categoryId}
///
/// Todas as chamadas têm timeout: sem internet o Firestore não devolve erro,
/// ele apenas "espera" a conexão voltar. O timeout transforma essa espera em
/// uma falha que o repositório trata (a alteração fica pendente no SQLite).
class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  static const Duration _timeout = Duration(seconds: 10);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _notes(String uid) =>
      _db.collection('users').doc(uid).collection('notes');

  CollectionReference<Map<String, dynamic>> _categories(String uid) =>
      _db.collection('users').doc(uid).collection('categories');

  /// Gera um ID único sem acessar a rede.
  String newNoteId(String uid) => _notes(uid).doc().id;

  String newCategoryId(String uid) => _categories(uid).doc().id;

  // ---------------------------------------------------------------- Notas

  Future<void> setNote(Note note) {
    return _notes(note.uid).doc(note.id).set(note.toFirestore()).timeout(_timeout);
  }

  Future<void> deleteNote(String uid, String noteId) {
    return _notes(uid).doc(noteId).delete().timeout(_timeout);
  }

  /// Lê direto do servidor (`Source.server`): se estiver offline, lança erro
  /// em vez de devolver um cache antigo.
  Future<List<Note>> fetchNotes(String uid) async {
    final snapshot = await _notes(
      uid,
    ).get(const GetOptions(source: Source.server)).timeout(_timeout);

    return snapshot.docs
        .map((doc) => Note.fromFirestore(doc.id, uid, doc.data()))
        .toList();
  }

  // ----------------------------------------------------------- Categorias

  Future<void> setCategory(Category category) {
    return _categories(
      category.uid,
    ).doc(category.id).set(category.toFirestore()).timeout(_timeout);
  }

  Future<void> deleteCategory(String uid, String categoryId) {
    return _categories(uid).doc(categoryId).delete().timeout(_timeout);
  }

  Future<List<Category>> fetchCategories(String uid) async {
    final snapshot = await _categories(
      uid,
    ).get(const GetOptions(source: Source.server)).timeout(_timeout);

    return snapshot.docs
        .map((doc) => Category.fromFirestore(doc.id, uid, doc.data()))
        .toList();
  }
}
