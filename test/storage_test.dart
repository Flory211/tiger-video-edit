import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiger_video_edit/model.dart';
import 'package:tiger_video_edit/storage.dart';

void main() {
  test(
    'Windows rebrand retains existing library without moving media',
    () async {
      final dir = await Directory.systemTemp.createTemp('tiger_library_');
      try {
        final current = Directory('${dir.path}/Tiger Video Edit');
        expect(
          (await LocalLibrary.windowsLibraryRoot(current)).path,
          current.path,
        );
        final legacy = await Directory('${dir.path}/Leos Fast Video Edit')
            .create();
        expect(
          (await LocalLibrary.windowsLibraryRoot(current)).path,
          legacy.path,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'Tiger project defaults to tve and reads legacy leos projects',
    () async {
      final dir = await Directory.systemTemp.createTemp('tiger_format_');
      try {
        final library = LocalLibrary(dir);
        expect(library.projectPath('Edit'), endsWith('.tve'));
        final old = '${dir.path}/legacy.leos';
        await ProjectStore.save(old, Project(name: 'Legacy'));
        expect((await ProjectStore.read(old)).name, 'Legacy');
        final next = '${dir.path}/new.tve';
        await ProjectStore.save(next, Project(name: 'Tiger'));
        expect((await ProjectStore.read(next)).name, 'Tiger');
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test('save preserves previous valid backup; autosave separate; corrupt read fails', () async {
    final dir = await Directory.systemTemp.createTemp('leos_storage_');
    try {
      final path = '${dir.path}/тест.leos';
      await ProjectStore.save(path, Project(name: 'one'));
      await ProjectStore.save(path, Project(name: 'two'));
      expect((await ProjectStore.read('$path.bak')).name, 'one');
      await ProjectStore.save('$path.autosave', Project(name: 'three'));
      expect((await ProjectStore.read(path)).name, 'two');
      await File(path).writeAsString('{broken');
      await expectLater(ProjectStore.read(path), throwsFormatException);
      expect((await ProjectStore.read('$path.bak')).name, 'one');
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
