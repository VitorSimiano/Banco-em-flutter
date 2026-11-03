import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Category;

import '../models/category.dart';
import '../models/note.dart';
import '../repositories/notes_repository.dart';
import '../services/auth_service.dart';
import '../widgets/note_card.dart';
import 'note_form_page.dart';

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> with WidgetsBindingObserver {
  final NotesRepository repository = NotesRepository.instance;
  final AuthService authService = AuthService();
  final TextEditingController searchController = TextEditingController();

  List<Note> notes = [];
  List<Category> categories = [];

  NoteView view = NoteView.active;
  NoteSort sort = NoteSort.updatedDesc;
  String? selectedCategoryId;
  String query = '';
  bool loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    searchController.dispose();
    super.dispose();
  }

  /// Ao voltar para o app, tenta enviar o que ficou pendente.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      syncNow(silent: true);
    }
  }

  Future<void> bootstrap() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await repository.ensureDefaultCategories(user.uid);
    await loadData();
    // Recupera da nuvem as notas deste usuário (novo login ou outro aparelho).
    await syncNow(silent: true);
  }

  Future<void> loadData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final loadedCategories = await repository.getCategories(user.uid);
    final stillExists = loadedCategories.any((c) => c.id == selectedCategoryId);
    final categoryFilter = stillExists ? selectedCategoryId : null;

    final result = await repository.getNotes(
      user.uid,
      view: view,
      query: query,
      categoryId: categoryFilter,
      sort: sort,
    );

    if (!mounted) return;
    setState(() {
      categories = loadedCategories;
      selectedCategoryId = categoryFilter;
      notes = result;
      loading = false;
    });
  }

  Future<void> syncNow({bool silent = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ok = await repository.sync(user.uid);
    if (!mounted) return;

    await loadData();
    if (!ok && !silent && mounted) {
      showMessage(
        'Não foi possível sincronizar com o Firebase. '
        'Suas notas continuam salvas no aparelho.',
      );
    }
  }

  void showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ----------------------------------------------------------------- Ações

  Future<void> openNote([Note? note]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NoteFormPage(note: note)),
    );
    await loadData();
  }

  Future<void> toggleArchive(Note note) async {
    await repository.setArchived(note, !note.archived);
    await loadData();
    showMessage(note.archived ? 'Nota desarquivada.' : 'Nota arquivada.');
  }

  Future<void> moveToTrash(Note note) async {
    await repository.moveToTrash(note);
    await loadData();
    showMessage('Nota movida para a lixeira.');
  }

  Future<void> restore(Note note) async {
    await repository.restore(note);
    await loadData();
    showMessage('Nota restaurada.');
  }

  Future<void> deleteForever(Note note) async {
    final confirmed = await confirm(
      title: 'Excluir definitivamente?',
      message: 'Essa nota será apagada do aparelho e do Firebase e não poderá '
          'ser recuperada.',
      action: 'Excluir',
    );
    if (confirmed != true) return;

    await repository.deletePermanently(note);
    await loadData();
    showMessage('Nota excluída definitivamente.');
  }

  Future<void> deleteCategory(Category category) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final confirmed = await confirm(
      title: 'Excluir categoria "${category.name}"?',
      message: 'As notas dessa categoria não serão apagadas, apenas ficarão '
          'sem categoria.',
      action: 'Excluir',
    );
    if (confirmed != true) return;

    await repository.deleteCategory(user.uid, category);
    await loadData();
    showMessage('Categoria excluída.');
  }

  Future<bool?> confirm({
    required String title,
    required String message,
    required String action,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  Future<void> logout() async {
    // O AuthGate (main.dart) volta sozinho para a tela de login.
    await authService.logout();
  }

  void changeView(NoteView newView) {
    Navigator.pop(context); // fecha o menu lateral
    setState(() => view = newView);
    loadData();
  }

  String get title {
    switch (view) {
      case NoteView.active:
        return 'Minhas notas';
      case NoteView.archived:
        return 'Arquivadas';
      case NoteView.trash:
        return 'Lixeira';
    }
  }

  String? categoryNameOf(Note note) {
    for (final category in categories) {
      if (category.id == note.categoryId) return category.name;
    }
    return null;
  }

  // -------------------------------------------------------------- Widgets

  Widget buildDrawer(User? user) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bloco de Notas',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user?.email ?? '',
                    style: const TextStyle(
                      color: Color(0xFF77717F),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.sticky_note_2_outlined),
              title: const Text('Notas'),
              selected: view == NoteView.active,
              onTap: () => changeView(NoteView.active),
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('Arquivadas'),
              selected: view == NoteView.archived,
              onTap: () => changeView(NoteView.archived),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Lixeira'),
              selected: view == NoteView.trash,
              onTap: () => changeView(NoteView.trash),
            ),
            const Spacer(),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Sair'),
              onTap: logout,
            ),
          ],
        ),
      ),
    );
  }

  Widget buildSyncBanner() {
    return ValueListenableBuilder<SyncState>(
      valueListenable: repository.syncState,
      builder: (context, state, _) {
        if (state == SyncState.idle) return const SizedBox.shrink();

        late final IconData icon;
        late final String text;
        late final Color color;

        switch (state) {
          case SyncState.syncing:
            icon = Icons.sync_rounded;
            text = 'Sincronizando com o Firebase...';
            color = const Color(0xFF6C4AB6);
            break;
          case SyncState.synced:
            icon = Icons.cloud_done_outlined;
            text = 'Notas sincronizadas com o Firebase';
            color = const Color(0xFF3D8B5F);
            break;
          case SyncState.offline:
          case SyncState.idle:
            icon = Icons.cloud_off_rounded;
            text = 'Sem conexão com o Firebase. As alterações estão salvas '
                'no aparelho e serão enviadas depois.';
            color = const Color(0xFFB45F6C);
            break;
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(text, style: TextStyle(fontSize: 12, color: color)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget buildSearchField() {
    return TextField(
      controller: searchController,
      textInputAction: TextInputAction.search,
      onChanged: (value) {
        query = value;
        loadData();
      },
      decoration: InputDecoration(
        hintText: 'Pesquisar por título ou conteúdo',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpar pesquisa',
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  searchController.clear();
                  setState(() => query = '');
                  loadData();
                },
              ),
      ),
    );
  }

  Widget buildCategoryChips() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('Todas'),
              selected: selectedCategoryId == null,
              onSelected: (_) {
                setState(() => selectedCategoryId = null);
                loadData();
              },
            ),
          ),
          for (final category in categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              // Pressionar e segurar abre a exclusão da categoria.
              child: GestureDetector(
                onLongPress: () => deleteCategory(category),
                child: ChoiceChip(
                  label: Text(category.name),
                  selected: selectedCategoryId == category.id,
                  onSelected: (_) {
                    setState(() => selectedCategoryId = category.id);
                    loadData();
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget buildEmptyState() {
    final searching = query.trim().isNotEmpty || selectedCategoryId != null;

    late final String line1;
    late final String line2;
    if (searching) {
      line1 = 'Nenhuma nota encontrada';
      line2 = 'Tente outro termo ou outra categoria.';
    } else {
      switch (view) {
        case NoteView.active:
          line1 = 'Nenhuma nota ainda';
          line2 = 'Crie sua primeira nota.';
          break;
        case NoteView.archived:
          line1 = 'Nenhuma nota arquivada';
          line2 = 'As notas arquivadas aparecem aqui.';
          break;
        case NoteView.trash:
          line1 = 'A lixeira está vazia';
          line2 = 'As notas excluídas podem ser restauradas daqui.';
          break;
      }
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: const BoxDecoration(
              color: Color(0xFFEDE5FA),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.sticky_note_2_rounded,
              size: 44,
              color: Color(0xFF6C4AB6),
            ),
          ),
          const SizedBox(height: 25),
          Text(line1, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(line2, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      drawer: buildDrawer(user),
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Sincronizar agora',
            onPressed: () => syncNow(),
            icon: const Icon(Icons.sync_rounded),
          ),
          PopupMenuButton<NoteSort>(
            tooltip: 'Ordenar',
            icon: const Icon(Icons.sort_rounded),
            initialValue: sort,
            onSelected: (value) {
              setState(() => sort = value);
              loadData();
            },
            itemBuilder: (_) => [
              for (final option in NoteSort.values)
                PopupMenuItem(value: option, child: Text(option.label)),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: view == NoteView.active
          ? FloatingActionButton.extended(
              onPressed: () => openNote(),
              backgroundColor: const Color(0xff6c4ab6),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Nova Nota',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            )
          : null,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildSyncBanner(),
            buildSearchField(),
            const SizedBox(height: 12),
            buildCategoryChips(),
            const SizedBox(height: 12),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : notes.isEmpty
                  ? buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 90),
                      itemCount: notes.length,
                      itemBuilder: (context, index) {
                        final note = notes[index];

                        return NoteCard(
                          note: note,
                          view: view,
                          categoryName: categoryNameOf(note),
                          // Na lixeira a nota não é editável: restaure primeiro.
                          onTap: view == NoteView.trash
                              ? null
                              : () => openNote(note),
                          onArchive: () => toggleArchive(note),
                          onTrash: () => moveToTrash(note),
                          onRestore: () => restore(note),
                          onDeleteForever: () => deleteForever(note),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
