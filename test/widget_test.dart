// Testes unitários dos modelos e utilitários (não dependem de Firebase nem de
// emulador). Execute com: flutter test

import 'package:flutter_test/flutter_test.dart' hide Category;

import 'package:bloco_de_nota_turma_a/models/category.dart';
import 'package:bloco_de_nota_turma_a/models/note.dart';
import 'package:bloco_de_nota_turma_a/models/sync_status.dart';
import 'package:bloco_de_nota_turma_a/utils/text_utils.dart';

void main() {
  const note = Note(
    id: 'n1',
    uid: 'user1',
    title: 'Estudar',
    content: 'Revisar Flutter e Firebase',
    categoryId: 'c1',
    createdAt: 1000,
    updatedAt: 2000,
    archived: true,
    deletedAt: null,
    syncStatus: SyncStatus.pending,
  );

  group('Note', () {
    test('toMap/fromMap preservam todos os campos (SQLite)', () {
      final copy = Note.fromMap(note.toMap());

      expect(copy.id, note.id);
      expect(copy.uid, note.uid);
      expect(copy.title, note.title);
      expect(copy.content, note.content);
      expect(copy.categoryId, 'c1');
      expect(copy.createdAt, 1000);
      expect(copy.updatedAt, 2000);
      expect(copy.archived, isTrue);
      expect(copy.deletedAt, isNull);
      expect(copy.syncStatus, SyncStatus.pending);
    });

    test('toFirestore/fromFirestore preservam os dados e marcam como synced', () {
      final copy = Note.fromFirestore('n1', 'user1', note.toFirestore());

      expect(copy.title, note.title);
      expect(copy.categoryId, 'c1');
      expect(copy.archived, isTrue);
      expect(copy.syncStatus, SyncStatus.synced);
      expect(note.toFirestore().containsKey('syncStatus'), isFalse);
    });

    test('copyWith(null) limpa categoria e lixeira; omitir mantém', () {
      final trashed = note.copyWith(deletedAt: 5000);
      expect(trashed.isTrashed, isTrue);
      expect(trashed.categoryId, 'c1');

      final restored = trashed.copyWith(deletedAt: null, categoryId: null);
      expect(restored.isTrashed, isFalse);
      expect(restored.categoryId, isNull);
    });
  });

  group('Category', () {
    test('toMap/fromMap e Firestore', () {
      const category = Category(
        id: 'c1',
        uid: 'user1',
        name: 'Estudos',
        createdAt: 1,
        updatedAt: 2,
      );

      final fromSql = Category.fromMap(category.toMap());
      expect(fromSql.name, 'Estudos');
      expect(fromSql.syncStatus, SyncStatus.pending);

      final fromCloud = Category.fromFirestore(
        'c1',
        'user1',
        category.toFirestore(),
      );
      expect(fromCloud.name, 'Estudos');
      expect(fromCloud.syncStatus, SyncStatus.synced);
    });
  });

  group('Pesquisa (normalizeText)', () {
    test('ignora maiúsculas e acentos', () {
      expect(normalizeText('Ação'), 'acao');
      expect(normalizeText('REUNIÃO'), 'reuniao');
      expect(normalizeText('Coração'), contains('coracao'));
    });

    test('permite encontrar texto sem acento em texto acentuado', () {
      final content = normalizeText('Lista de compras: maçã e pão');
      expect(content.contains(normalizeText('MACA')), isTrue);
      expect(content.contains(normalizeText('pao')), isTrue);
      expect(content.contains(normalizeText('banana')), isFalse);
    });
  });

  group('formatDateTime', () {
    test('formata dd/MM/aaaa HH:mm', () {
      final millis = DateTime(2026, 3, 5, 9, 7).millisecondsSinceEpoch;
      expect(formatDateTime(millis), '05/03/2026 09:07');
    });
  });
}
