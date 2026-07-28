import 'dart:convert';
import 'dart:ui';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../app_paths.dart';
import '../../models/planner_models.dart' as model;

part 'app_database.g.dart';

@DataClassName('BoardRow')
class Boards extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get color => integer()();
  IntColumn get position => integer()();
}

@DataClassName('TaskGroupRow')
class TaskGroups extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get boardId => integer().references(Boards, #id)();
  TextColumn get name => text()();
  IntColumn get color => integer()();
  IntColumn get position => integer()();
}

@DataClassName('PlannerTaskRow')
class PlannerTasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get groupId => integer().references(TaskGroups, #id)();
  TextColumn get title => text()();
  TextColumn get owner => text()();
  TextColumn get status => text()();
  TextColumn get priority => text()();
  TextColumn get dueDate => text()();
  TextColumn get timeline => text()();
  RealColumn get progress => real()();
  IntColumn get position => integer()();
  TextColumn get notes => text().withDefault(const Constant(''))();
}

/// Free-floating notes on the sticky board. Position and size are persisted so
/// the canvas looks exactly as the user left it.
@DataClassName('StickyNoteRow')
class StickyNotes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withDefault(const Constant(''))();

  /// Quill Delta JSON, matching the format used by task notes.
  TextColumn get body => text().withDefault(const Constant(''))();
  IntColumn get color => integer()();
  RealColumn get x => real()();
  RealColumn get y => real()();
  RealColumn get width => real().withDefault(const Constant(260))();
  RealColumn get height => real().withDefault(const Constant(240))();

  /// Draw order; the most recently touched note floats to the top.
  IntColumn get z => integer().withDefault(const Constant(0))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();

  /// Set when the note was created from a task, so the card can link back.
  IntColumn get taskId => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

@DriftDatabase(tables: [Boards, TaskGroups, PlannerTasks, StickyNotes])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (migrator) => migrator.createAll(),
      onUpgrade: (migrator, from, to) async {
        if (from < 2) {
          await migrator.addColumn(plannerTasks, plannerTasks.notes);
        }
        if (from < 3) {
          await migrator.createTable(stickyNotes);
        }
      },
    );
  }

  Future<List<model.Board>> loadBoards() async {
    final boardRows = await (select(
      boards,
    )..orderBy([(row) => OrderingTerm.asc(row.position)])).get();
    final groupRows = await (select(
      taskGroups,
    )..orderBy([(row) => OrderingTerm.asc(row.position)])).get();
    final taskRows =
        await (select(plannerTasks)..orderBy([
              (row) => OrderingTerm.asc(row.groupId),
              (row) => OrderingTerm.asc(row.position),
              (row) => OrderingTerm.asc(row.id),
            ]))
            .get();

    return boardRows.map((boardRow) {
      final groups = groupRows
          .where((groupRow) => groupRow.boardId == boardRow.id)
          .map((groupRow) {
            final tasks = taskRows
                .where((taskRow) => taskRow.groupId == groupRow.id)
                .map(_taskFromRow)
                .toList();

            return model.TaskGroup(
              id: groupRow.id,
              boardId: groupRow.boardId,
              name: groupRow.name,
              color: Color(groupRow.color),
              tasks: tasks,
            );
          })
          .toList();

      return model.Board(
        id: boardRow.id,
        name: boardRow.name,
        color: Color(boardRow.color),
        groups: groups,
      );
    }).toList();
  }

  Future<int> createBoard({required String name, required Color color}) async {
    final position = (await select(boards).get()).length;
    return into(boards).insert(
      BoardsCompanion.insert(
        name: name.trim(),
        color: color.toARGB32(),
        position: position,
      ),
    );
  }

  Future<void> updateBoardName({
    required int boardId,
    required String name,
  }) async {
    await (update(boards)..where((row) => row.id.equals(boardId))).write(
      BoardsCompanion(name: Value(name.trim())),
    );
  }

  Future<void> updateBoardColor({
    required int boardId,
    required Color color,
  }) async {
    await (update(boards)..where((row) => row.id.equals(boardId))).write(
      BoardsCompanion(color: Value(color.toARGB32())),
    );
  }

  Future<int> createGroup({
    required int boardId,
    required String name,
    required Color color,
  }) async {
    final groupRows = await (select(
      taskGroups,
    )..where((row) => row.boardId.equals(boardId))).get();
    return into(taskGroups).insert(
      TaskGroupsCompanion.insert(
        boardId: boardId,
        name: name.trim(),
        color: color.toARGB32(),
        position: groupRows.length,
      ),
    );
  }

  Future<void> updateGroupName({
    required int groupId,
    required String name,
  }) async {
    await (update(taskGroups)..where((row) => row.id.equals(groupId))).write(
      TaskGroupsCompanion(name: Value(name.trim())),
    );
  }

  Future<void> updateGroupColor({
    required int groupId,
    required Color color,
  }) async {
    await (update(taskGroups)..where((row) => row.id.equals(groupId))).write(
      TaskGroupsCompanion(color: Value(color.toARGB32())),
    );
  }

  Future<int> addTask({
    required int groupId,
    required String title,
    required String owner,
    required model.TaskStatus status,
    required model.TaskPriority priority,
    required String dueDate,
    required String timeline,
    required double progress,
    required int position,
  }) async {
    return into(plannerTasks).insert(
      PlannerTasksCompanion.insert(
        groupId: groupId,
        title: title.trim(),
        owner: owner.trim(),
        status: status.name,
        priority: priority.name,
        dueDate: dueDate.trim().isEmpty ? 'No date' : dueDate.trim(),
        timeline: timeline.trim().isEmpty ? 'Unscheduled' : timeline.trim(),
        progress: progress,
        position: position,
      ),
    );
  }

  Future<void> updateTask({
    required model.PlannerTask task,
    required int groupId,
    required String title,
    required String owner,
    required model.TaskStatus status,
    required model.TaskPriority priority,
    required String dueDate,
    required String timeline,
    required double progress,
  }) async {
    await (update(plannerTasks)..where((row) => row.id.equals(task.id))).write(
      PlannerTasksCompanion(
        groupId: Value(groupId),
        title: Value(title.trim()),
        owner: Value(owner.trim()),
        status: Value(status.name),
        priority: Value(priority.name),
        dueDate: Value(dueDate.trim().isEmpty ? 'No date' : dueDate.trim()),
        timeline: Value(
          timeline.trim().isEmpty ? 'Unscheduled' : timeline.trim(),
        ),
        progress: Value(progress),
      ),
    );
  }

  Future<void> updateTaskNotes(
    model.PlannerTask task,
    List<String> notes,
  ) async {
    final cleaned = notes
        .map((note) => note.trim())
        .where((note) => note.isNotEmpty)
        .toList();
    await (update(plannerTasks)..where((row) => row.id.equals(task.id))).write(
      PlannerTasksCompanion(notes: Value(jsonEncode(cleaned))),
    );
  }

  Future<void> updateTaskStatus(
    model.PlannerTask task,
    model.TaskStatus status,
  ) async {
    var progress = task.progress.clamp(0, 0.9).toDouble();
    if (status == model.TaskStatus.done) {
      progress = 1.0;
    } else if (status == model.TaskStatus.notStarted) {
      progress = 0.0;
    }
    await (update(plannerTasks)..where((row) => row.id.equals(task.id))).write(
      PlannerTasksCompanion(
        status: Value(status.name),
        progress: Value(progress),
      ),
    );
  }

  Future<void> updateTaskProgress(
    model.PlannerTask task,
    double progress,
  ) async {
    final normalizedProgress = progress.clamp(0, 1).toDouble();
    var status = task.status;
    if (normalizedProgress <= 0) {
      status = model.TaskStatus.notStarted;
    } else if (normalizedProgress >= 1) {
      status = model.TaskStatus.done;
    } else if (status == model.TaskStatus.done ||
        status == model.TaskStatus.notStarted) {
      status = model.TaskStatus.working;
    }

    await (update(plannerTasks)..where((row) => row.id.equals(task.id))).write(
      PlannerTasksCompanion(
        progress: Value(normalizedProgress),
        status: Value(status.name),
      ),
    );
  }

  Future<void> updateTaskPositions(
    int groupId,
    List<int> orderedTaskIds,
  ) async {
    await transaction(() async {
      for (var index = 0; index < orderedTaskIds.length; index++) {
        final taskId = orderedTaskIds[index];
        await (update(plannerTasks)..where(
              (row) => row.id.equals(taskId) & row.groupId.equals(groupId),
            ))
            .write(PlannerTasksCompanion(position: Value(index)));
      }
    });
  }

  Future<void> deleteBoard(int boardId) async {
    await transaction(() async {
      final groupRows = await (select(
        taskGroups,
      )..where((row) => row.boardId.equals(boardId))).get();
      final groupIds = groupRows.map((group) => group.id).toList();

      for (final groupId in groupIds) {
        await (delete(
          plannerTasks,
        )..where((row) => row.groupId.equals(groupId))).go();
      }

      await (delete(
        taskGroups,
      )..where((row) => row.boardId.equals(boardId))).go();
      await (delete(boards)..where((row) => row.id.equals(boardId))).go();
    });
  }

  Future<void> deleteGroup(int groupId) async {
    await transaction(() async {
      await (delete(
        plannerTasks,
      )..where((row) => row.groupId.equals(groupId))).go();
      await (delete(taskGroups)..where((row) => row.id.equals(groupId))).go();
    });
  }

  Future<void> deleteTask(int taskId) async {
    await (delete(plannerTasks)..where((row) => row.id.equals(taskId))).go();
  }

  // === Sticky notes ===

  Future<List<model.StickyNote>> loadStickyNotes() async {
    final rows =
        await (select(stickyNotes)..orderBy([
              (row) => OrderingTerm.asc(row.z),
              (row) => OrderingTerm.asc(row.id),
            ]))
            .get();
    return rows.map(_stickyFromRow).toList();
  }

  Future<int> createStickyNote({
    required double x,
    required double y,
    required Color color,
    String title = '',
    String body = '',
    int? taskId,
  }) async {
    final now = DateTime.now();
    final topZ = await _topStickyZ();
    return into(stickyNotes).insert(
      StickyNotesCompanion.insert(
        title: Value(title.trim()),
        body: Value(body),
        color: color.toARGB32(),
        x: x,
        y: y,
        z: Value(topZ + 1),
        taskId: Value(taskId),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> updateStickyContent({
    required int noteId,
    required String title,
    required String body,
  }) async {
    await (update(stickyNotes)..where((row) => row.id.equals(noteId))).write(
      StickyNotesCompanion(
        title: Value(title.trim()),
        body: Value(body),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Persists a drag. Position only — deliberately does not bump [updatedAt],
  /// since moving a note is not editing it.
  Future<void> moveStickyNote({
    required int noteId,
    required double x,
    required double y,
  }) async {
    await (update(stickyNotes)..where((row) => row.id.equals(noteId))).write(
      StickyNotesCompanion(x: Value(x), y: Value(y)),
    );
  }

  Future<void> resizeStickyNote({
    required int noteId,
    required double width,
    required double height,
  }) async {
    await (update(stickyNotes)..where((row) => row.id.equals(noteId))).write(
      StickyNotesCompanion(width: Value(width), height: Value(height)),
    );
  }

  Future<void> updateStickyColor({
    required int noteId,
    required Color color,
  }) async {
    await (update(stickyNotes)..where((row) => row.id.equals(noteId))).write(
      StickyNotesCompanion(
        color: Value(color.toARGB32()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> setStickyPinned({
    required int noteId,
    required bool pinned,
  }) async {
    await (update(stickyNotes)..where((row) => row.id.equals(noteId))).write(
      StickyNotesCompanion(pinned: Value(pinned)),
    );
  }

  /// Raises a note above all others, so the one being touched is never buried.
  Future<void> bringStickyToFront(int noteId) async {
    final topZ = await _topStickyZ();
    await (update(stickyNotes)..where((row) => row.id.equals(noteId))).write(
      StickyNotesCompanion(z: Value(topZ + 1)),
    );
  }

  Future<void> deleteStickyNote(int noteId) async {
    await (delete(stickyNotes)..where((row) => row.id.equals(noteId))).go();
  }

  Future<int> _topStickyZ() async {
    final rows = await (select(
      stickyNotes,
    )..orderBy([(row) => OrderingTerm.desc(row.z)])).get();
    return rows.isEmpty ? 0 : rows.first.z;
  }

  model.StickyNote _stickyFromRow(StickyNoteRow row) {
    return model.StickyNote(
      id: row.id,
      title: row.title,
      body: row.body,
      color: Color(row.color),
      x: row.x,
      y: row.y,
      width: row.width,
      height: row.height,
      z: row.z,
      pinned: row.pinned,
      taskId: row.taskId,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  model.PlannerTask _taskFromRow(PlannerTaskRow row) {
    return model.PlannerTask(
      id: row.id,
      groupId: row.groupId,
      title: row.title,
      owner: row.owner,
      status: model.TaskStatus.fromName(row.status),
      priority: model.TaskPriority.fromName(row.priority),
      dueDate: row.dueDate,
      timeline: row.timeline,
      progress: row.progress,
      notes: _decodeNotes(row.notes),
    );
  }

  /// Notes are stored as a JSON array of strings. Falls back to treating any
  /// legacy plain-text value as a single note.
  List<String> _decodeNotes(String raw) {
    if (raw.trim().isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((item) => item.toString())
            .where((note) => note.trim().isNotEmpty)
            .toList();
      }
    } catch (_) {
      // Legacy single-note text.
    }
    return [raw];
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final file = await databaseFile();
    return NativeDatabase.createInBackground(file);
  });
}
