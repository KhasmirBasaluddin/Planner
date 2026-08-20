import 'package:flutter/material.dart';

import '../../core/supabase/planner_repository.dart';
import '../../models/planner_models.dart';
import '../../shared/utils/planner_colors.dart';
import '../../shared/widgets/app_dialog.dart';

/// Everything deleted in this workspace, and the way back.
///
/// Deleting has always been soft — the row keeps its `deleted_at` and is only
/// destroyed by the 30-day purge — but nothing in the app ever showed the bin,
/// so in practice a deleted task was gone for good. This is the missing half.
///
/// It matters more now that members cannot hard delete: their Delete leaves
/// the task recoverable, and somebody has to be able to find it.
Future<bool?> showDeletedItemsDialog(
  BuildContext context, {
  required PlannerRepository repository,
  required Workspace workspace,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) =>
        _DeletedItemsDialog(repository: repository, workspace: workspace),
  );
}

class _DeletedItemsDialog extends StatefulWidget {
  const _DeletedItemsDialog({required this.repository, required this.workspace});

  final PlannerRepository repository;
  final Workspace workspace;

  @override
  State<_DeletedItemsDialog> createState() => _DeletedItemsDialogState();
}

/// One recoverable row, flattened out of the three lists the RPC returns.
typedef _Item = ({
  String entity,
  String id,
  String label,
  DateTime? deletedAt,
});

class _DeletedItemsDialogState extends State<_DeletedItemsDialog> {
  List<_Item> _items = [];
  bool _loading = true;
  String? _error;
  bool _restoredAnything = false;

  /// Ids currently being restored, so a row can show progress without
  /// disabling the whole list.
  final Set<String> _working = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.repository.loadDeletedItems(
        widget.workspace.id,
      );
      final items = <_Item>[];

      void collect(String entity, String key, String nameField) {
        for (final row in (data[key] as List? ?? const [])) {
          if (row is! Map<String, dynamic>) {
            continue;
          }
          items.add((
            entity: entity,
            id: row['id'] as String,
            label: (row[nameField] ?? 'Untitled') as String,
            deletedAt: DateTime.tryParse((row['deleted_at'] ?? '') as String),
          ));
        }
      }

      collect('boards', 'boards', 'name');
      collect('task_groups', 'groups', 'name');
      collect('tasks', 'tasks', 'title');

      // Newest first: the thing someone just deleted by mistake is the thing
      // they came here for.
      items.sort((a, b) {
        final left = a.deletedAt;
        final right = b.deletedAt;
        if (left == null || right == null) {
          return 0;
        }
        return right.compareTo(left);
      });

      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _describe(error);
        });
      }
    }
  }

  Future<void> _restore(_Item item) async {
    setState(() {
      _working.add(item.id);
      _error = null;
    });
    try {
      switch (item.entity) {
        case 'boards':
          await widget.repository.restoreBoard(item.id);
        case 'task_groups':
          await widget.repository.restoreGroup(item.id);
        default:
          await widget.repository.restoreTask(item.id);
      }
      _restoredAnything = true;
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() => _error = _describe(error));
      }
    } finally {
      if (mounted) {
        setState(() => _working.remove(item.id));
      }
    }
  }

  String _describe(Object error) {
    final raw = error.toString().replaceFirst(RegExp(r'^\w+Exception: '), '');
    if (raw.contains('permission')) {
      return 'You do not have permission to restore that.';
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icons.restore_from_trash_rounded,
      title: 'Deleted items',
      width: 520,
      message:
          'Deleting only hides something — it is kept for 30 days before it '
          'is removed for good. Anything in here can be put back.',
      content: SizedBox(
        height: 320,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: tint(plannerRed, 0.08),
                  borderRadius: BorderRadius.circular(radiusSm),
                  border: Border.all(color: tint(plannerRed, 0.25)),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: plannerRed, fontSize: 12),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : _items.isEmpty
                  ? const _BinEmpty()
                  : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 7),
                      itemBuilder: (context, index) => _Row(
                        item: _items[index],
                        busy: _working.contains(_items[index].id),
                        onRestore: () => _restore(_items[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_restoredAnything),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.item,
    required this.busy,
    required this.onRestore,
  });

  final _Item item;
  final bool busy;
  final VoidCallback onRestore;

  /// A board carries its groups and tasks back with it, so it is worth saying
  /// which kind of thing is being restored.
  ({IconData icon, String noun}) get _kind => switch (item.entity) {
    'boards' => (icon: Icons.dashboard_outlined, noun: 'Board'),
    'task_groups' => (icon: Icons.folder_outlined, noun: 'Group'),
    _ => (icon: Icons.check_box_outlined, noun: 'Task'),
  };

  @override
  Widget build(BuildContext context) {
    final kind = _kind;

    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 9, 9),
      decoration: BoxDecoration(
        color: plannerCard,
        borderRadius: BorderRadius.circular(radiusMd),
        border: Border.all(color: plannerBorder),
      ),
      child: Row(
        children: [
          Icon(kind.icon, size: 17, color: plannerMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: plannerInk,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${kind.noun} · ${_removed(item.deletedAt)}',
                  style: const TextStyle(color: plannerMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: onRestore,
              icon: const Icon(Icons.restore_rounded, size: 15),
              label: const Text('Restore'),
            ),
        ],
      ),
    );
  }

  /// How long is left, not how long ago — the purge is the deadline that
  /// matters to someone looking at this list.
  static String _removed(DateTime? at) {
    if (at == null) {
      return 'deleted';
    }
    final days = 30 - DateTime.now().difference(at.toLocal()).inDays;
    if (days <= 0) {
      return 'removed for good very soon';
    }
    if (days == 1) {
      return 'removed for good tomorrow';
    }
    return 'removed for good in $days days';
  }
}

class _BinEmpty extends StatelessWidget {
  const _BinEmpty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline_rounded, size: 28, color: plannerFaint),
            SizedBox(height: 12),
            Text(
              'Nothing deleted',
              style: TextStyle(
                color: plannerText,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 5),
            Text(
              'Boards, groups and tasks you delete appear here for 30 days.',
              textAlign: TextAlign.center,
              style: TextStyle(color: plannerMuted, fontSize: 12, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
