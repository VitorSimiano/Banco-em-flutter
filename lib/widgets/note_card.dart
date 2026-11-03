import 'package:flutter/material.dart';

import '../models/note.dart';
import '../models/sync_status.dart';
import '../utils/text_utils.dart';

enum _NoteAction { archive, trash, restore, deleteForever }

class NoteCard extends StatelessWidget {
  final Note note;
  final String? categoryName;

  /// Visão atual: define quais ações aparecem no menu da nota.
  final NoteView view;

  final VoidCallback? onTap;
  final VoidCallback onArchive;
  final VoidCallback onTrash;
  final VoidCallback onRestore;
  final VoidCallback onDeleteForever;

  const NoteCard({
    super.key,
    required this.note,
    required this.view,
    this.categoryName,
    this.onTap,
    required this.onArchive,
    required this.onTrash,
    required this.onRestore,
    required this.onDeleteForever,
  });

  void _handle(_NoteAction action) {
    switch (action) {
      case _NoteAction.archive:
        onArchive();
        break;
      case _NoteAction.trash:
        onTrash();
        break;
      case _NoteAction.restore:
        onRestore();
        break;
      case _NoteAction.deleteForever:
        onDeleteForever();
        break;
    }
  }

  List<PopupMenuEntry<_NoteAction>> _menuItems() {
    if (view == NoteView.trash) {
      return const [
        PopupMenuItem(
          value: _NoteAction.restore,
          child: Text('Restaurar'),
        ),
        PopupMenuItem(
          value: _NoteAction.deleteForever,
          child: Text('Excluir definitivamente'),
        ),
      ];
    }
    return [
      PopupMenuItem(
        value: _NoteAction.archive,
        child: Text(view == NoteView.archived ? 'Desarquivar' : 'Arquivar'),
      ),
      const PopupMenuItem(
        value: _NoteAction.trash,
        child: Text('Mover para a lixeira'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final pendingSync = note.syncStatus != SyncStatus.synced;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 8, 20),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE5FA),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.notes_rounded, color: Color(0xFF6C4AB6)),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      note.title.isEmpty ? 'Sem título' : note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF292333),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      note.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF77717F),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (categoryName != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEDE5FA),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              categoryName!,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6C4AB6),
                              ),
                            ),
                          ),
                        Text(
                          formatDateTime(note.updatedAt),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9A94A1),
                          ),
                        ),
                        if (pendingSync)
                          const Tooltip(
                            message: 'Aguardando envio ao Firebase',
                            child: Icon(
                              Icons.cloud_off_rounded,
                              size: 14,
                              color: Color(0xFFB45F6C),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_NoteAction>(
                onSelected: _handle,
                itemBuilder: (_) => _menuItems(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
