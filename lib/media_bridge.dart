import 'dart:io';

import 'package:flutter/services.dart';

const nativeMedia = MethodChannel('tiger/media');
String mediaTool(String name) {
  final bundled = File(
    '${File(Platform.resolvedExecutable).parent.path}/tools/$name.exe',
  );
  return bundled.existsSync() ? bundled.path : name;
}
