import 'dart:convert';
import 'dart:io';

enum AppTheme { system, dark, light }

enum PreviewQuality { low, medium, high }

enum ExportQuality { standard, high, maximum }

/// Persisted independently of projects so upgrades never rewrite project data.
class AppSettings {
  final bool animations, reducedMotion, autosave, interfaceSounds;
  final AppTheme theme;
  final String language;
  final double previewVolume;
  final PreviewQuality previewQuality;
  final ExportQuality exportQuality;
  final int exportHeight, exportFps;
  final Set<String> favoriteEffects;
  final List<String> recentEffects;
  final bool autoCheckUpdates, updateNotifications;

  const AppSettings({
    this.animations = true,
    this.reducedMotion = false,
    this.autosave = true,
    this.interfaceSounds = false,
    this.theme = AppTheme.dark,
    this.language = 'ru',
    this.previewVolume = 1,
    this.previewQuality = PreviewQuality.medium,
    this.exportQuality = ExportQuality.high,
    this.exportHeight = 1080,
    this.exportFps = 30,
    this.favoriteEffects = const {},
    this.recentEffects = const [],
    this.autoCheckUpdates = true,
    this.updateNotifications = true,
  });

  bool animationsAllowed({bool systemReducedMotion = false}) =>
      animations && !reducedMotion && !systemReducedMotion;

  AppSettings copyWith({
    bool? animations,
    bool? reducedMotion,
    bool? autosave,
    bool? interfaceSounds,
    AppTheme? theme,
    String? language,
    double? previewVolume,
    PreviewQuality? previewQuality,
    ExportQuality? exportQuality,
    int? exportHeight,
    int? exportFps,
    Set<String>? favoriteEffects,
    List<String>? recentEffects,
    bool? autoCheckUpdates,
    bool? updateNotifications,
  }) => AppSettings.fromJson({
    ...toJson(),
    'animations': ?animations,
    'reducedMotion': ?reducedMotion,
    'autosave': ?autosave,
    'interfaceSounds': ?interfaceSounds,
    if (theme != null) 'theme': theme.name,
    'language': ?language,
    'previewVolume': ?previewVolume,
    if (previewQuality != null) 'previewQuality': previewQuality.name,
    if (exportQuality != null) 'exportQuality': exportQuality.name,
    'exportHeight': ?exportHeight,
    'exportFps': ?exportFps,
    if (favoriteEffects != null) 'favoriteEffects': favoriteEffects.toList(),
    'recentEffects': ?recentEffects,
    'autoCheckUpdates': ?autoCheckUpdates,
    'updateNotifications': ?updateNotifications,
  });

  Map<String, dynamic> toJson() => {
    'schema': 1,
    'animations': animations,
    'reducedMotion': reducedMotion,
    'autosave': autosave,
    'interfaceSounds': interfaceSounds,
    'theme': theme.name,
    'language': language,
    'previewVolume': previewVolume,
    'previewQuality': previewQuality.name,
    'exportQuality': exportQuality.name,
    'exportHeight': exportHeight,
    'exportFps': exportFps,
    'favoriteEffects': favoriteEffects.toList(),
    'recentEffects': recentEffects,
    'autoCheckUpdates': autoCheckUpdates,
    'updateNotifications': updateNotifications,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    T choice<T extends Enum>(String key, List<T> values, T fallback) =>
        values.where((v) => v.name == json[key]).firstOrNull ?? fallback;
    bool flag(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;
    List<String> strings(String key) => json[key] is List
        ? (json[key] as List)
              .whereType<String>()
              .where((s) => s.length <= 128)
              .toSet()
              .take(100)
              .toList()
        : [];
    final volume = json['previewVolume'];
    return AppSettings(
      animations: flag('animations', true),
      reducedMotion: flag('reducedMotion', false),
      autosave: flag('autosave', true),
      interfaceSounds: flag('interfaceSounds', false),
      theme: choice('theme', AppTheme.values, AppTheme.dark),
      language: ['ru', 'en'].contains(json['language'])
          ? json['language'] as String
          : 'ru',
      previewVolume: volume is num && volume.isFinite
          ? volume.toDouble().clamp(0, 1)
          : 1,
      previewQuality: choice(
        'previewQuality',
        PreviewQuality.values,
        PreviewQuality.medium,
      ),
      exportQuality: choice(
        'exportQuality',
        ExportQuality.values,
        ExportQuality.high,
      ),
      exportHeight: [480, 720, 1080].contains(json['exportHeight'])
          ? json['exportHeight'] as int
          : 1080,
      exportFps: [24, 30, 60].contains(json['exportFps'])
          ? json['exportFps'] as int
          : 30,
      favoriteEffects: Set.unmodifiable(strings('favoriteEffects')),
      recentEffects: List.unmodifiable(strings('recentEffects').take(20)),
      autoCheckUpdates: flag('autoCheckUpdates', true),
      updateNotifications: flag('updateNotifications', true),
    );
  }
}

class SettingsStore {
  final File file;
  Future<void> _pending = Future.value();
  SettingsStore(this.file);

  Future<AppSettings> load() async {
    for (final candidate in [file, File('${file.path}.bak')]) {
      try {
        if (await candidate.length() > 1024 * 1024) continue;
        return AppSettings.fromJson(
          jsonDecode(await candidate.readAsString()) as Map<String, dynamic>,
        );
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    return const AppSettings();
  }

  Future<void> save(AppSettings settings) {
    final result = _pending.then(
      (_) => atomicWriteBytes(file, utf8.encode(jsonEncode(settings.toJson()))),
    );
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

/// Stage in the same directory; retain the previous file and roll back failed
/// replacement. The caller serializes concurrent writes to the same destination.
Future<void> atomicWriteBytes(File destination, List<int> bytes) async {
  await destination.parent.create(recursive: true);
  final stage = File(
    '${destination.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    await stage.writeAsBytes(bytes, flush: true);
    await replaceStagedFile(stage, destination);
  } finally {
    if (await stage.exists()) await stage.delete();
  }
}

Future<void> replaceStagedFile(File stage, File destination) async {
  final backup = File('${destination.path}.bak');
  final existed = await destination.exists();
  if (existed) {
    if (await backup.exists()) await backup.delete();
    await destination.rename(backup.path);
  }
  try {
    await stage.rename(destination.path);
  } catch (_) {
    if (existed && await backup.exists() && !await destination.exists()) {
      await backup.rename(destination.path);
    }
    rethrow;
  }
}
