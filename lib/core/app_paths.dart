import 'dart:io';

import 'package:path/path.dart' as path;

import 'constants.dart';

Future<Directory> appDataDirectory() async {
  final projectDirectory = _findProjectDirectory(Directory.current);
  final directory = Directory(
    path.join(projectDirectory.path, databaseDirectoryName),
  );
  if (!directory.existsSync()) {
    directory.createSync(recursive: true);
  }
  return directory;
}

Future<File> databaseFile() async {
  final directory = await appDataDirectory();
  return File(path.join(directory.path, databaseFileName));
}

Directory _findProjectDirectory(Directory start) {
  var directory = start.absolute;
  while (true) {
    if (File(path.join(directory.path, 'pubspec.yaml')).existsSync()) {
      return directory;
    }

    final parent = directory.parent;
    if (parent.path == directory.path) {
      return start.absolute;
    }
    directory = parent;
  }
}
