// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $BoardsTable extends Boards with TableInfo<$BoardsTable, BoardRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BoardsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<int> color = GeneratedColumn<int>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, color, position];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'boards';
  @override
  VerificationContext validateIntegrity(
    Insertable<BoardRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    } else if (isInserting) {
      context.missing(_colorMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BoardRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BoardRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $BoardsTable createAlias(String alias) {
    return $BoardsTable(attachedDatabase, alias);
  }
}

class BoardRow extends DataClass implements Insertable<BoardRow> {
  final int id;
  final String name;
  final int color;
  final int position;
  const BoardRow({
    required this.id,
    required this.name,
    required this.color,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['color'] = Variable<int>(color);
    map['position'] = Variable<int>(position);
    return map;
  }

  BoardsCompanion toCompanion(bool nullToAbsent) {
    return BoardsCompanion(
      id: Value(id),
      name: Value(name),
      color: Value(color),
      position: Value(position),
    );
  }

  factory BoardRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BoardRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      color: serializer.fromJson<int>(json['color']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'color': serializer.toJson<int>(color),
      'position': serializer.toJson<int>(position),
    };
  }

  BoardRow copyWith({int? id, String? name, int? color, int? position}) =>
      BoardRow(
        id: id ?? this.id,
        name: name ?? this.name,
        color: color ?? this.color,
        position: position ?? this.position,
      );
  BoardRow copyWithCompanion(BoardsCompanion data) {
    return BoardRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      color: data.color.present ? data.color.value : this.color,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BoardRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, color, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BoardRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.color == this.color &&
          other.position == this.position);
}

class BoardsCompanion extends UpdateCompanion<BoardRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<int> color;
  final Value<int> position;
  const BoardsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
    this.position = const Value.absent(),
  });
  BoardsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required int color,
    required int position,
  }) : name = Value(name),
       color = Value(color),
       position = Value(position);
  static Insertable<BoardRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? color,
    Expression<int>? position,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (color != null) 'color': color,
      if (position != null) 'position': position,
    });
  }

  BoardsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<int>? color,
    Value<int>? position,
  }) {
    return BoardsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      position: position ?? this.position,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (color.present) {
      map['color'] = Variable<int>(color.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BoardsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }
}

class $TaskGroupsTable extends TaskGroups
    with TableInfo<$TaskGroupsTable, TaskGroupRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaskGroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _boardIdMeta = const VerificationMeta(
    'boardId',
  );
  @override
  late final GeneratedColumn<int> boardId = GeneratedColumn<int>(
    'board_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES boards (id)',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<int> color = GeneratedColumn<int>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, boardId, name, color, position];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'task_groups';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskGroupRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('board_id')) {
      context.handle(
        _boardIdMeta,
        boardId.isAcceptableOrUnknown(data['board_id']!, _boardIdMeta),
      );
    } else if (isInserting) {
      context.missing(_boardIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    } else if (isInserting) {
      context.missing(_colorMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TaskGroupRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskGroupRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      boardId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}board_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $TaskGroupsTable createAlias(String alias) {
    return $TaskGroupsTable(attachedDatabase, alias);
  }
}

class TaskGroupRow extends DataClass implements Insertable<TaskGroupRow> {
  final int id;
  final int boardId;
  final String name;
  final int color;
  final int position;
  const TaskGroupRow({
    required this.id,
    required this.boardId,
    required this.name,
    required this.color,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['board_id'] = Variable<int>(boardId);
    map['name'] = Variable<String>(name);
    map['color'] = Variable<int>(color);
    map['position'] = Variable<int>(position);
    return map;
  }

  TaskGroupsCompanion toCompanion(bool nullToAbsent) {
    return TaskGroupsCompanion(
      id: Value(id),
      boardId: Value(boardId),
      name: Value(name),
      color: Value(color),
      position: Value(position),
    );
  }

  factory TaskGroupRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskGroupRow(
      id: serializer.fromJson<int>(json['id']),
      boardId: serializer.fromJson<int>(json['boardId']),
      name: serializer.fromJson<String>(json['name']),
      color: serializer.fromJson<int>(json['color']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'boardId': serializer.toJson<int>(boardId),
      'name': serializer.toJson<String>(name),
      'color': serializer.toJson<int>(color),
      'position': serializer.toJson<int>(position),
    };
  }

  TaskGroupRow copyWith({
    int? id,
    int? boardId,
    String? name,
    int? color,
    int? position,
  }) => TaskGroupRow(
    id: id ?? this.id,
    boardId: boardId ?? this.boardId,
    name: name ?? this.name,
    color: color ?? this.color,
    position: position ?? this.position,
  );
  TaskGroupRow copyWithCompanion(TaskGroupsCompanion data) {
    return TaskGroupRow(
      id: data.id.present ? data.id.value : this.id,
      boardId: data.boardId.present ? data.boardId.value : this.boardId,
      name: data.name.present ? data.name.value : this.name,
      color: data.color.present ? data.color.value : this.color,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskGroupRow(')
          ..write('id: $id, ')
          ..write('boardId: $boardId, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, boardId, name, color, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskGroupRow &&
          other.id == this.id &&
          other.boardId == this.boardId &&
          other.name == this.name &&
          other.color == this.color &&
          other.position == this.position);
}

class TaskGroupsCompanion extends UpdateCompanion<TaskGroupRow> {
  final Value<int> id;
  final Value<int> boardId;
  final Value<String> name;
  final Value<int> color;
  final Value<int> position;
  const TaskGroupsCompanion({
    this.id = const Value.absent(),
    this.boardId = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
    this.position = const Value.absent(),
  });
  TaskGroupsCompanion.insert({
    this.id = const Value.absent(),
    required int boardId,
    required String name,
    required int color,
    required int position,
  }) : boardId = Value(boardId),
       name = Value(name),
       color = Value(color),
       position = Value(position);
  static Insertable<TaskGroupRow> custom({
    Expression<int>? id,
    Expression<int>? boardId,
    Expression<String>? name,
    Expression<int>? color,
    Expression<int>? position,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (boardId != null) 'board_id': boardId,
      if (name != null) 'name': name,
      if (color != null) 'color': color,
      if (position != null) 'position': position,
    });
  }

  TaskGroupsCompanion copyWith({
    Value<int>? id,
    Value<int>? boardId,
    Value<String>? name,
    Value<int>? color,
    Value<int>? position,
  }) {
    return TaskGroupsCompanion(
      id: id ?? this.id,
      boardId: boardId ?? this.boardId,
      name: name ?? this.name,
      color: color ?? this.color,
      position: position ?? this.position,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (boardId.present) {
      map['board_id'] = Variable<int>(boardId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (color.present) {
      map['color'] = Variable<int>(color.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaskGroupsCompanion(')
          ..write('id: $id, ')
          ..write('boardId: $boardId, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }
}

class $PlannerTasksTable extends PlannerTasks
    with TableInfo<$PlannerTasksTable, PlannerTaskRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlannerTasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<int> groupId = GeneratedColumn<int>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES task_groups (id)',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerMeta = const VerificationMeta('owner');
  @override
  late final GeneratedColumn<String> owner = GeneratedColumn<String>(
    'owner',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<String> priority = GeneratedColumn<String>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dueDateMeta = const VerificationMeta(
    'dueDate',
  );
  @override
  late final GeneratedColumn<String> dueDate = GeneratedColumn<String>(
    'due_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timelineMeta = const VerificationMeta(
    'timeline',
  );
  @override
  late final GeneratedColumn<String> timeline = GeneratedColumn<String>(
    'timeline',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _progressMeta = const VerificationMeta(
    'progress',
  );
  @override
  late final GeneratedColumn<double> progress = GeneratedColumn<double>(
    'progress',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    groupId,
    title,
    owner,
    status,
    priority,
    dueDate,
    timeline,
    progress,
    position,
    notes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'planner_tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlannerTaskRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('owner')) {
      context.handle(
        _ownerMeta,
        owner.isAcceptableOrUnknown(data['owner']!, _ownerMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    } else if (isInserting) {
      context.missing(_priorityMeta);
    }
    if (data.containsKey('due_date')) {
      context.handle(
        _dueDateMeta,
        dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta),
      );
    } else if (isInserting) {
      context.missing(_dueDateMeta);
    }
    if (data.containsKey('timeline')) {
      context.handle(
        _timelineMeta,
        timeline.isAcceptableOrUnknown(data['timeline']!, _timelineMeta),
      );
    } else if (isInserting) {
      context.missing(_timelineMeta);
    }
    if (data.containsKey('progress')) {
      context.handle(
        _progressMeta,
        progress.isAcceptableOrUnknown(data['progress']!, _progressMeta),
      );
    } else if (isInserting) {
      context.missing(_progressMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlannerTaskRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlannerTaskRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}group_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      owner: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}priority'],
      )!,
      dueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}due_date'],
      )!,
      timeline: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}timeline'],
      )!,
      progress: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}progress'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      )!,
    );
  }

  @override
  $PlannerTasksTable createAlias(String alias) {
    return $PlannerTasksTable(attachedDatabase, alias);
  }
}

class PlannerTaskRow extends DataClass implements Insertable<PlannerTaskRow> {
  final int id;
  final int groupId;
  final String title;
  final String owner;
  final String status;
  final String priority;
  final String dueDate;
  final String timeline;
  final double progress;
  final int position;
  final String notes;
  const PlannerTaskRow({
    required this.id,
    required this.groupId,
    required this.title,
    required this.owner,
    required this.status,
    required this.priority,
    required this.dueDate,
    required this.timeline,
    required this.progress,
    required this.position,
    required this.notes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['group_id'] = Variable<int>(groupId);
    map['title'] = Variable<String>(title);
    map['owner'] = Variable<String>(owner);
    map['status'] = Variable<String>(status);
    map['priority'] = Variable<String>(priority);
    map['due_date'] = Variable<String>(dueDate);
    map['timeline'] = Variable<String>(timeline);
    map['progress'] = Variable<double>(progress);
    map['position'] = Variable<int>(position);
    map['notes'] = Variable<String>(notes);
    return map;
  }

  PlannerTasksCompanion toCompanion(bool nullToAbsent) {
    return PlannerTasksCompanion(
      id: Value(id),
      groupId: Value(groupId),
      title: Value(title),
      owner: Value(owner),
      status: Value(status),
      priority: Value(priority),
      dueDate: Value(dueDate),
      timeline: Value(timeline),
      progress: Value(progress),
      position: Value(position),
      notes: Value(notes),
    );
  }

  factory PlannerTaskRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlannerTaskRow(
      id: serializer.fromJson<int>(json['id']),
      groupId: serializer.fromJson<int>(json['groupId']),
      title: serializer.fromJson<String>(json['title']),
      owner: serializer.fromJson<String>(json['owner']),
      status: serializer.fromJson<String>(json['status']),
      priority: serializer.fromJson<String>(json['priority']),
      dueDate: serializer.fromJson<String>(json['dueDate']),
      timeline: serializer.fromJson<String>(json['timeline']),
      progress: serializer.fromJson<double>(json['progress']),
      position: serializer.fromJson<int>(json['position']),
      notes: serializer.fromJson<String>(json['notes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'groupId': serializer.toJson<int>(groupId),
      'title': serializer.toJson<String>(title),
      'owner': serializer.toJson<String>(owner),
      'status': serializer.toJson<String>(status),
      'priority': serializer.toJson<String>(priority),
      'dueDate': serializer.toJson<String>(dueDate),
      'timeline': serializer.toJson<String>(timeline),
      'progress': serializer.toJson<double>(progress),
      'position': serializer.toJson<int>(position),
      'notes': serializer.toJson<String>(notes),
    };
  }

  PlannerTaskRow copyWith({
    int? id,
    int? groupId,
    String? title,
    String? owner,
    String? status,
    String? priority,
    String? dueDate,
    String? timeline,
    double? progress,
    int? position,
    String? notes,
  }) => PlannerTaskRow(
    id: id ?? this.id,
    groupId: groupId ?? this.groupId,
    title: title ?? this.title,
    owner: owner ?? this.owner,
    status: status ?? this.status,
    priority: priority ?? this.priority,
    dueDate: dueDate ?? this.dueDate,
    timeline: timeline ?? this.timeline,
    progress: progress ?? this.progress,
    position: position ?? this.position,
    notes: notes ?? this.notes,
  );
  PlannerTaskRow copyWithCompanion(PlannerTasksCompanion data) {
    return PlannerTaskRow(
      id: data.id.present ? data.id.value : this.id,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      title: data.title.present ? data.title.value : this.title,
      owner: data.owner.present ? data.owner.value : this.owner,
      status: data.status.present ? data.status.value : this.status,
      priority: data.priority.present ? data.priority.value : this.priority,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      timeline: data.timeline.present ? data.timeline.value : this.timeline,
      progress: data.progress.present ? data.progress.value : this.progress,
      position: data.position.present ? data.position.value : this.position,
      notes: data.notes.present ? data.notes.value : this.notes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlannerTaskRow(')
          ..write('id: $id, ')
          ..write('groupId: $groupId, ')
          ..write('title: $title, ')
          ..write('owner: $owner, ')
          ..write('status: $status, ')
          ..write('priority: $priority, ')
          ..write('dueDate: $dueDate, ')
          ..write('timeline: $timeline, ')
          ..write('progress: $progress, ')
          ..write('position: $position, ')
          ..write('notes: $notes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    groupId,
    title,
    owner,
    status,
    priority,
    dueDate,
    timeline,
    progress,
    position,
    notes,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlannerTaskRow &&
          other.id == this.id &&
          other.groupId == this.groupId &&
          other.title == this.title &&
          other.owner == this.owner &&
          other.status == this.status &&
          other.priority == this.priority &&
          other.dueDate == this.dueDate &&
          other.timeline == this.timeline &&
          other.progress == this.progress &&
          other.position == this.position &&
          other.notes == this.notes);
}

class PlannerTasksCompanion extends UpdateCompanion<PlannerTaskRow> {
  final Value<int> id;
  final Value<int> groupId;
  final Value<String> title;
  final Value<String> owner;
  final Value<String> status;
  final Value<String> priority;
  final Value<String> dueDate;
  final Value<String> timeline;
  final Value<double> progress;
  final Value<int> position;
  final Value<String> notes;
  const PlannerTasksCompanion({
    this.id = const Value.absent(),
    this.groupId = const Value.absent(),
    this.title = const Value.absent(),
    this.owner = const Value.absent(),
    this.status = const Value.absent(),
    this.priority = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.timeline = const Value.absent(),
    this.progress = const Value.absent(),
    this.position = const Value.absent(),
    this.notes = const Value.absent(),
  });
  PlannerTasksCompanion.insert({
    this.id = const Value.absent(),
    required int groupId,
    required String title,
    required String owner,
    required String status,
    required String priority,
    required String dueDate,
    required String timeline,
    required double progress,
    required int position,
    this.notes = const Value.absent(),
  }) : groupId = Value(groupId),
       title = Value(title),
       owner = Value(owner),
       status = Value(status),
       priority = Value(priority),
       dueDate = Value(dueDate),
       timeline = Value(timeline),
       progress = Value(progress),
       position = Value(position);
  static Insertable<PlannerTaskRow> custom({
    Expression<int>? id,
    Expression<int>? groupId,
    Expression<String>? title,
    Expression<String>? owner,
    Expression<String>? status,
    Expression<String>? priority,
    Expression<String>? dueDate,
    Expression<String>? timeline,
    Expression<double>? progress,
    Expression<int>? position,
    Expression<String>? notes,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (groupId != null) 'group_id': groupId,
      if (title != null) 'title': title,
      if (owner != null) 'owner': owner,
      if (status != null) 'status': status,
      if (priority != null) 'priority': priority,
      if (dueDate != null) 'due_date': dueDate,
      if (timeline != null) 'timeline': timeline,
      if (progress != null) 'progress': progress,
      if (position != null) 'position': position,
      if (notes != null) 'notes': notes,
    });
  }

  PlannerTasksCompanion copyWith({
    Value<int>? id,
    Value<int>? groupId,
    Value<String>? title,
    Value<String>? owner,
    Value<String>? status,
    Value<String>? priority,
    Value<String>? dueDate,
    Value<String>? timeline,
    Value<double>? progress,
    Value<int>? position,
    Value<String>? notes,
  }) {
    return PlannerTasksCompanion(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      title: title ?? this.title,
      owner: owner ?? this.owner,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      dueDate: dueDate ?? this.dueDate,
      timeline: timeline ?? this.timeline,
      progress: progress ?? this.progress,
      position: position ?? this.position,
      notes: notes ?? this.notes,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<int>(groupId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (owner.present) {
      map['owner'] = Variable<String>(owner.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (priority.present) {
      map['priority'] = Variable<String>(priority.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<String>(dueDate.value);
    }
    if (timeline.present) {
      map['timeline'] = Variable<String>(timeline.value);
    }
    if (progress.present) {
      map['progress'] = Variable<double>(progress.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlannerTasksCompanion(')
          ..write('id: $id, ')
          ..write('groupId: $groupId, ')
          ..write('title: $title, ')
          ..write('owner: $owner, ')
          ..write('status: $status, ')
          ..write('priority: $priority, ')
          ..write('dueDate: $dueDate, ')
          ..write('timeline: $timeline, ')
          ..write('progress: $progress, ')
          ..write('position: $position, ')
          ..write('notes: $notes')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $BoardsTable boards = $BoardsTable(this);
  late final $TaskGroupsTable taskGroups = $TaskGroupsTable(this);
  late final $PlannerTasksTable plannerTasks = $PlannerTasksTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    boards,
    taskGroups,
    plannerTasks,
  ];
}

typedef $$BoardsTableCreateCompanionBuilder =
    BoardsCompanion Function({
      Value<int> id,
      required String name,
      required int color,
      required int position,
    });
typedef $$BoardsTableUpdateCompanionBuilder =
    BoardsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<int> color,
      Value<int> position,
    });

final class $$BoardsTableReferences
    extends BaseReferences<_$AppDatabase, $BoardsTable, BoardRow> {
  $$BoardsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$TaskGroupsTable, List<TaskGroupRow>>
  _taskGroupsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.taskGroups,
    aliasName: 'boards__id__task_groups__board_id',
  );

  $$TaskGroupsTableProcessedTableManager get taskGroupsRefs {
    final manager = $$TaskGroupsTableTableManager(
      $_db,
      $_db.taskGroups,
    ).filter((f) => f.boardId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_taskGroupsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$BoardsTableFilterComposer
    extends Composer<_$AppDatabase, $BoardsTable> {
  $$BoardsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> taskGroupsRefs(
    Expression<bool> Function($$TaskGroupsTableFilterComposer f) f,
  ) {
    final $$TaskGroupsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.taskGroups,
      getReferencedColumn: (t) => t.boardId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TaskGroupsTableFilterComposer(
            $db: $db,
            $table: $db.taskGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BoardsTableOrderingComposer
    extends Composer<_$AppDatabase, $BoardsTable> {
  $$BoardsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BoardsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BoardsTable> {
  $$BoardsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  Expression<T> taskGroupsRefs<T extends Object>(
    Expression<T> Function($$TaskGroupsTableAnnotationComposer a) f,
  ) {
    final $$TaskGroupsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.taskGroups,
      getReferencedColumn: (t) => t.boardId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TaskGroupsTableAnnotationComposer(
            $db: $db,
            $table: $db.taskGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BoardsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BoardsTable,
          BoardRow,
          $$BoardsTableFilterComposer,
          $$BoardsTableOrderingComposer,
          $$BoardsTableAnnotationComposer,
          $$BoardsTableCreateCompanionBuilder,
          $$BoardsTableUpdateCompanionBuilder,
          (BoardRow, $$BoardsTableReferences),
          BoardRow,
          PrefetchHooks Function({bool taskGroupsRefs})
        > {
  $$BoardsTableTableManager(_$AppDatabase db, $BoardsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BoardsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BoardsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BoardsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> color = const Value.absent(),
                Value<int> position = const Value.absent(),
              }) => BoardsCompanion(
                id: id,
                name: name,
                color: color,
                position: position,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required int color,
                required int position,
              }) => BoardsCompanion.insert(
                id: id,
                name: name,
                color: color,
                position: position,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$BoardsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({taskGroupsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (taskGroupsRefs) db.taskGroups],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (taskGroupsRefs)
                    await $_getPrefetchedData<
                      BoardRow,
                      $BoardsTable,
                      TaskGroupRow
                    >(
                      currentTable: table,
                      referencedTable: $$BoardsTableReferences
                          ._taskGroupsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$BoardsTableReferences(db, table, p0).taskGroupsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.boardId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$BoardsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BoardsTable,
      BoardRow,
      $$BoardsTableFilterComposer,
      $$BoardsTableOrderingComposer,
      $$BoardsTableAnnotationComposer,
      $$BoardsTableCreateCompanionBuilder,
      $$BoardsTableUpdateCompanionBuilder,
      (BoardRow, $$BoardsTableReferences),
      BoardRow,
      PrefetchHooks Function({bool taskGroupsRefs})
    >;
typedef $$TaskGroupsTableCreateCompanionBuilder =
    TaskGroupsCompanion Function({
      Value<int> id,
      required int boardId,
      required String name,
      required int color,
      required int position,
    });
typedef $$TaskGroupsTableUpdateCompanionBuilder =
    TaskGroupsCompanion Function({
      Value<int> id,
      Value<int> boardId,
      Value<String> name,
      Value<int> color,
      Value<int> position,
    });

final class $$TaskGroupsTableReferences
    extends BaseReferences<_$AppDatabase, $TaskGroupsTable, TaskGroupRow> {
  $$TaskGroupsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BoardsTable _boardIdTable(_$AppDatabase db) =>
      db.boards.createAlias('task_groups__board_id__boards__id');

  $$BoardsTableProcessedTableManager get boardId {
    final $_column = $_itemColumn<int>('board_id')!;

    final manager = $$BoardsTableTableManager(
      $_db,
      $_db.boards,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_boardIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$PlannerTasksTable, List<PlannerTaskRow>>
  _plannerTasksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.plannerTasks,
    aliasName: 'task_groups__id__planner_tasks__group_id',
  );

  $$PlannerTasksTableProcessedTableManager get plannerTasksRefs {
    final manager = $$PlannerTasksTableTableManager(
      $_db,
      $_db.plannerTasks,
    ).filter((f) => f.groupId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_plannerTasksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TaskGroupsTableFilterComposer
    extends Composer<_$AppDatabase, $TaskGroupsTable> {
  $$TaskGroupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  $$BoardsTableFilterComposer get boardId {
    final $$BoardsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.boardId,
      referencedTable: $db.boards,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BoardsTableFilterComposer(
            $db: $db,
            $table: $db.boards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> plannerTasksRefs(
    Expression<bool> Function($$PlannerTasksTableFilterComposer f) f,
  ) {
    final $$PlannerTasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.plannerTasks,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlannerTasksTableFilterComposer(
            $db: $db,
            $table: $db.plannerTasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TaskGroupsTableOrderingComposer
    extends Composer<_$AppDatabase, $TaskGroupsTable> {
  $$TaskGroupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  $$BoardsTableOrderingComposer get boardId {
    final $$BoardsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.boardId,
      referencedTable: $db.boards,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BoardsTableOrderingComposer(
            $db: $db,
            $table: $db.boards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskGroupsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TaskGroupsTable> {
  $$TaskGroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  $$BoardsTableAnnotationComposer get boardId {
    final $$BoardsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.boardId,
      referencedTable: $db.boards,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BoardsTableAnnotationComposer(
            $db: $db,
            $table: $db.boards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> plannerTasksRefs<T extends Object>(
    Expression<T> Function($$PlannerTasksTableAnnotationComposer a) f,
  ) {
    final $$PlannerTasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.plannerTasks,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlannerTasksTableAnnotationComposer(
            $db: $db,
            $table: $db.plannerTasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TaskGroupsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TaskGroupsTable,
          TaskGroupRow,
          $$TaskGroupsTableFilterComposer,
          $$TaskGroupsTableOrderingComposer,
          $$TaskGroupsTableAnnotationComposer,
          $$TaskGroupsTableCreateCompanionBuilder,
          $$TaskGroupsTableUpdateCompanionBuilder,
          (TaskGroupRow, $$TaskGroupsTableReferences),
          TaskGroupRow,
          PrefetchHooks Function({bool boardId, bool plannerTasksRefs})
        > {
  $$TaskGroupsTableTableManager(_$AppDatabase db, $TaskGroupsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaskGroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaskGroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TaskGroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> boardId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> color = const Value.absent(),
                Value<int> position = const Value.absent(),
              }) => TaskGroupsCompanion(
                id: id,
                boardId: boardId,
                name: name,
                color: color,
                position: position,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int boardId,
                required String name,
                required int color,
                required int position,
              }) => TaskGroupsCompanion.insert(
                id: id,
                boardId: boardId,
                name: name,
                color: color,
                position: position,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TaskGroupsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({boardId = false, plannerTasksRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (plannerTasksRefs) db.plannerTasks],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (boardId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.boardId,
                                referencedTable: $$TaskGroupsTableReferences
                                    ._boardIdTable(db),
                                referencedColumn: $$TaskGroupsTableReferences
                                    ._boardIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (plannerTasksRefs)
                    await $_getPrefetchedData<
                      TaskGroupRow,
                      $TaskGroupsTable,
                      PlannerTaskRow
                    >(
                      currentTable: table,
                      referencedTable: $$TaskGroupsTableReferences
                          ._plannerTasksRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$TaskGroupsTableReferences(
                            db,
                            table,
                            p0,
                          ).plannerTasksRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.groupId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$TaskGroupsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TaskGroupsTable,
      TaskGroupRow,
      $$TaskGroupsTableFilterComposer,
      $$TaskGroupsTableOrderingComposer,
      $$TaskGroupsTableAnnotationComposer,
      $$TaskGroupsTableCreateCompanionBuilder,
      $$TaskGroupsTableUpdateCompanionBuilder,
      (TaskGroupRow, $$TaskGroupsTableReferences),
      TaskGroupRow,
      PrefetchHooks Function({bool boardId, bool plannerTasksRefs})
    >;
typedef $$PlannerTasksTableCreateCompanionBuilder =
    PlannerTasksCompanion Function({
      Value<int> id,
      required int groupId,
      required String title,
      required String owner,
      required String status,
      required String priority,
      required String dueDate,
      required String timeline,
      required double progress,
      required int position,
      Value<String> notes,
    });
typedef $$PlannerTasksTableUpdateCompanionBuilder =
    PlannerTasksCompanion Function({
      Value<int> id,
      Value<int> groupId,
      Value<String> title,
      Value<String> owner,
      Value<String> status,
      Value<String> priority,
      Value<String> dueDate,
      Value<String> timeline,
      Value<double> progress,
      Value<int> position,
      Value<String> notes,
    });

final class $$PlannerTasksTableReferences
    extends BaseReferences<_$AppDatabase, $PlannerTasksTable, PlannerTaskRow> {
  $$PlannerTasksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $TaskGroupsTable _groupIdTable(_$AppDatabase db) =>
      db.taskGroups.createAlias('planner_tasks__group_id__task_groups__id');

  $$TaskGroupsTableProcessedTableManager get groupId {
    final $_column = $_itemColumn<int>('group_id')!;

    final manager = $$TaskGroupsTableTableManager(
      $_db,
      $_db.taskGroups,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_groupIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PlannerTasksTableFilterComposer
    extends Composer<_$AppDatabase, $PlannerTasksTable> {
  $$PlannerTasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get owner => $composableBuilder(
    column: $table.owner,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timeline => $composableBuilder(
    column: $table.timeline,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  $$TaskGroupsTableFilterComposer get groupId {
    final $$TaskGroupsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.taskGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TaskGroupsTableFilterComposer(
            $db: $db,
            $table: $db.taskGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlannerTasksTableOrderingComposer
    extends Composer<_$AppDatabase, $PlannerTasksTable> {
  $$PlannerTasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get owner => $composableBuilder(
    column: $table.owner,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timeline => $composableBuilder(
    column: $table.timeline,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  $$TaskGroupsTableOrderingComposer get groupId {
    final $$TaskGroupsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.taskGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TaskGroupsTableOrderingComposer(
            $db: $db,
            $table: $db.taskGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlannerTasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlannerTasksTable> {
  $$PlannerTasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get owner =>
      $composableBuilder(column: $table.owner, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<String> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumn<String> get timeline =>
      $composableBuilder(column: $table.timeline, builder: (column) => column);

  GeneratedColumn<double> get progress =>
      $composableBuilder(column: $table.progress, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  $$TaskGroupsTableAnnotationComposer get groupId {
    final $$TaskGroupsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.taskGroups,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TaskGroupsTableAnnotationComposer(
            $db: $db,
            $table: $db.taskGroups,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlannerTasksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlannerTasksTable,
          PlannerTaskRow,
          $$PlannerTasksTableFilterComposer,
          $$PlannerTasksTableOrderingComposer,
          $$PlannerTasksTableAnnotationComposer,
          $$PlannerTasksTableCreateCompanionBuilder,
          $$PlannerTasksTableUpdateCompanionBuilder,
          (PlannerTaskRow, $$PlannerTasksTableReferences),
          PlannerTaskRow,
          PrefetchHooks Function({bool groupId})
        > {
  $$PlannerTasksTableTableManager(_$AppDatabase db, $PlannerTasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlannerTasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlannerTasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlannerTasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> groupId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> owner = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> priority = const Value.absent(),
                Value<String> dueDate = const Value.absent(),
                Value<String> timeline = const Value.absent(),
                Value<double> progress = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> notes = const Value.absent(),
              }) => PlannerTasksCompanion(
                id: id,
                groupId: groupId,
                title: title,
                owner: owner,
                status: status,
                priority: priority,
                dueDate: dueDate,
                timeline: timeline,
                progress: progress,
                position: position,
                notes: notes,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int groupId,
                required String title,
                required String owner,
                required String status,
                required String priority,
                required String dueDate,
                required String timeline,
                required double progress,
                required int position,
                Value<String> notes = const Value.absent(),
              }) => PlannerTasksCompanion.insert(
                id: id,
                groupId: groupId,
                title: title,
                owner: owner,
                status: status,
                priority: priority,
                dueDate: dueDate,
                timeline: timeline,
                progress: progress,
                position: position,
                notes: notes,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PlannerTasksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({groupId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (groupId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.groupId,
                                referencedTable: $$PlannerTasksTableReferences
                                    ._groupIdTable(db),
                                referencedColumn: $$PlannerTasksTableReferences
                                    ._groupIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PlannerTasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlannerTasksTable,
      PlannerTaskRow,
      $$PlannerTasksTableFilterComposer,
      $$PlannerTasksTableOrderingComposer,
      $$PlannerTasksTableAnnotationComposer,
      $$PlannerTasksTableCreateCompanionBuilder,
      $$PlannerTasksTableUpdateCompanionBuilder,
      (PlannerTaskRow, $$PlannerTasksTableReferences),
      PlannerTaskRow,
      PrefetchHooks Function({bool groupId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$BoardsTableTableManager get boards =>
      $$BoardsTableTableManager(_db, _db.boards);
  $$TaskGroupsTableTableManager get taskGroups =>
      $$TaskGroupsTableTableManager(_db, _db.taskGroups);
  $$PlannerTasksTableTableManager get plannerTasks =>
      $$PlannerTasksTableTableManager(_db, _db.plannerTasks);
}
