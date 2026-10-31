import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'model.dart';

class ProjectStore {
  static Future<Project> read(String path) async {
    final file = File(path);
    if (await file.length() > 16 * 1024 * 1024) {
      throw const FormatException('Файл проекта слишком большой');
    }
    try {
      final project = Project.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
      String resolve(String ref) => File(ref).isAbsolute
          ? ref
          : File('${file.parent.path}/$ref').absolute.path;
      return project.copy(
        audio: project.audio == null ? null : resolve(project.audio!),
        images: [
          for (final image in project.images)
            image.copy(path: resolve(image.path)),
        ],
      );
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Не удалось прочитать проект: $e');
    }
  }

  static Future<void> save(String path, Project project) async {
    project.validate();
    final dest = File(path), stage = File('$path.tmp');
    await dest.parent.create(recursive: true);
    await stage.writeAsString(
      const JsonEncoder.withIndent('  ').convert(project.toJson()),
      flush: true,
    );
    await read(stage.path);
    if (await dest.exists()) {
      // Never replace a good backup with a corrupt primary file.
      try {
        await read(path);
        await dest.copy('$path.bak');
      } on FormatException {
        /* Keep backup. */
      }
      await dest.delete();
    }
    await stage.rename(path);
  }

  static Future<List<String>> missing(Project p) async {
    final result = <String>[];
    for (final path in {
      if (p.audio != null) p.audio!,
      ...p.images.map((e) => e.path),
    }) {
      if (!await File(path).exists()) result.add(path);
    }
    return result;
  }
}

class LocalLibrary {
  final Directory root;
  LocalLibrary(this.root);
  static Future<LocalLibrary> open() async {
    var dir = await getApplicationSupportDirectory();
    if (Platform.isWindows) dir = await windowsLibraryRoot(dir);
    await dir.create(recursive: true);
    return LocalLibrary(dir);
  }

  static Future<Directory> windowsLibraryRoot(Directory current) async {
    // Preserve existing media and recent projects when product metadata changes.
    for (final name in ['Leos Fast Video Edit', 'leos_fast_video_edit']) {
      final legacy = Directory('${current.parent.path}/$name');
      if (await legacy.exists()) return legacy;
    }
    return current;
  }

  Future<String> importFile(String path) async {
    final src = File(path);
    if (!await src.exists() || await src.length() == 0) {
      throw const FormatException('Исходный файл отсутствует или пуст');
    }
    final dir = await Directory('${root.path}/media').create(recursive: true);
    final name = path.replaceAll('\\', '/').split('/').last;
    return (await src.copy(
      '${dir.path}/${DateTime.now().microsecondsSinceEpoch}_$name',
    )).path;
  }

  Future<Map<String, dynamic>> loadPreferences() async {
    try {
      return jsonDecode(await File('${root.path}/settings.json').readAsString())
          as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> preferences(Map<String, dynamic> data) async {
    final temp = File('${root.path}/settings.json.tmp');
    await temp.writeAsString(jsonEncode(data), flush: true);
    final dest = File('${root.path}/settings.json');
    if (await dest.exists()) await dest.delete();
    await temp.rename(dest.path);
  }

  String projectPath(String name) =>
      '${root.path}/projects/${DateTime.now().millisecondsSinceEpoch}_${name.replaceAll(RegExp(r'[^a-zA-Zа-яА-ЯёЁ0-9 _-]'), '_')}.tve';
}
