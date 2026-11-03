import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Shared catalog validation and staged writes for offline and AI extraction.
class CatalogIO {
  static Map<String, dynamic> readDictionary(File file) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException {
      // JSON decoder errors otherwise echo potentially private catalog contents.
      throw FormatException('Invalid JSON in ${file.path}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Expected a JSON object in ${file.path}');
    }
    return decoded;
  }

  static bool containsKey(Map<String, dynamic> dictionary, String key) {
    if (dictionary.containsKey(key)) return true;
    dynamic current = dictionary;
    for (final part in key.split('.')) {
      if (current is! Map || !current.containsKey(part)) return false;
      current = current[part];
    }
    return true;
  }

  static void insert(
    Map<String, dynamic> dictionary,
    String key,
    String value,
  ) {
    final parts = key.split('.');
    if (parts.length == 1 || dictionary[parts.first] is! Map<String, dynamic>) {
      dictionary[key] = value;
      return;
    }
    var current = dictionary;
    for (final part in parts.take(parts.length - 1)) {
      if (!current.containsKey(part)) current[part] = <String, dynamic>{};
      final child = current[part];
      if (child is! Map<String, dynamic>) {
        throw FormatException(
          'Cannot add "$key": "$part" is already a translation, not a namespace.',
        );
      }
      current = child;
    }
    current[parts.last] = value;
  }

  static void validateOutput(File file) {
    var path = file.path;
    while (true) {
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      // Never redirect a write through a symlink, including a parent directory.
      if (type == FileSystemEntityType.link) {
        throw FileSystemException('Output path contains a symbolic link', path);
      }
      if (path == file.path &&
          type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file) {
        throw FileSystemException('Output is not a regular file', path);
      }
      if (path != file.path &&
          type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.directory) {
        throw FileSystemException('Output parent is not a directory', path);
      }
      final parent = p.dirname(path);
      if (parent == path) break;
      path = parent;
    }
  }

  static void writeOutput(File output, String content) {
    validateOutput(output);
    final mode = output.existsSync() ? output.statSync().mode & 0x1ff : 0x180;
    output.parent.createSync(recursive: true);
    final temporary = output.parent.createTempSync('.string_extractor_');
    try {
      final staged = File(p.join(temporary.path, 'strings.json'));
      staged.writeAsStringSync(content, flush: true);
      if (!Platform.isWindows) {
        // Dart has no chmod API. Set permissions before exposing staged content,
        // retaining existing access or using owner-only access for new files.
        final permissions = Process.runSync('/bin/chmod', [
          mode.toRadixString(8),
          staged.path,
        ]);
        if (permissions.exitCode != 0) {
          throw FileSystemException(
            'Could not set output permissions',
            staged.path,
          );
        }
      }
      validateOutput(output);
      // Same-filesystem rename avoids truncating the existing translation file.
      staged.renameSync(output.path);
    } finally {
      temporary.deleteSync(recursive: true);
    }
  }
}
