import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Category;

import '../models/category.dart';
import '../models/note.dart';
import '../repositories/notes_repository.dart';

class NoteFormPage extends StatefulWidget {
  final Note? note;

  const NoteFormPage({super.key, this.note});

  @override
  State<NoteFormPage> createState() => _NoteFormPageState();
}

class _NoteFormPageState extends State<NoteFormPage> {
  final titleController = TextEditingController();
  final contentController = TextEditingController();

  final repository = NotesRepository.instance;

  List<Category> categories = [];
  String? selectedCategoryId;
  bool saving = false;

  bool get isEditing => widget.note != null;

  @override
  void initState() {
    super.initState();

    if (isEditing) {
      titleController.text = widget.note!.title;
      contentController.text = widget.note!.content;
      selectedCategoryId = widget.note!.categoryId;
    }

    loadCategories();
  }

  Future<void> loadCategories() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final result = await repository.getCategories(user.uid);
    if (!mounted) return;

    setState(() {
      categories = result;
      // Se a categoria da nota foi excluída, a nota fica sem categoria.
      if (!result.any((c) => c.id == selectedCategoryId)) {
        selectedCategoryId = null;
      }
    });
  }

  Future<void> newCategory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _CategoryDialog(),
    );
    if (name == null || name.isEmpty) return;

    final category = await repository.createCategory(user.uid, name);
    await loadCategories();
    if (!mounted) return;
    setState(() => selectedCategoryId = category.id);
  }

  Future<void> saveNote() async {
    if (saving) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final title = titleController.text.trim();
    final content = contentController.text.trim();

    if (title.isEmpty && content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escreva um título ou um conteúdo.')),
      );
      return;
    }

    setState(() => saving = true);

    // Grava no SQLite e dispara o envio ao Firestore em segundo plano.
    if (isEditing) {
      await repository.updateNote(
        widget.note!,
        title: title,
        content: content,
        categoryId: selectedCategoryId,
      );
    } else {
      await repository.createNote(
        uid: user.uid,
        title: title,
        content: content,
        categoryId: selectedCategoryId,
      );
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditing ? 'Editar nota' : 'Nova nota',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Salvar',
            onPressed: saving ? null : saveNote,
            icon: const Icon(Icons.check_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: titleController,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF292333),
              ),
              decoration: const InputDecoration(
                hintText: 'Título',
                border: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
            const Divider(color: Color(0xFFE4DFEA)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final category in categories)
                  ChoiceChip(
                    label: Text(category.name),
                    selected: selectedCategoryId == category.id,
                    onSelected: (selected) {
                      setState(() {
                        selectedCategoryId = selected ? category.id : null;
                      });
                    },
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Nova categoria'),
                  onPressed: newCategory,
                ),
              ],
            ),
            Expanded(
              child: TextField(
                controller: contentController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(
                  fontSize: 17,
                  height: 1.5,
                  color: Color(0xFF40394A),
                ),
                decoration: const InputDecoration(
                  hintText: 'Comece a escrever...',
                  border: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Diálogo para criar categoria. É um widget próprio para que o controller
/// seja descartado junto com o diálogo.
class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog();

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nova categoria'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 40,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Nome da categoria'),
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Criar', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
