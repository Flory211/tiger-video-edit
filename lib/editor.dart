import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:file_selector/file_selector.dart';

import 'model.dart';
import 'storage.dart';
import 'platform_media.dart';
import 'media_frames.dart';
import 'beat.dart';
import 'app_settings.dart';
import 'effect_recipes.dart';
import 'sound_library.dart';
import 'edit_templates.dart';

import 'package:media_kit/media_kit.dart';

BeatAnalysis _analyzeEnvelope((List<double>, int, double) input) =>
    detectBeats(input.$1, input.$2, sensitivity: input.$3);

class Editor extends ChangeNotifier {
  final LocalLibrary library;
  final AudioEngine audio;
  final VideoExporter exporter = VideoExporter();
  ProjectHistory history = ProjectHistory(Project());
  Project get project => history.current;
  String? projectPath, error;
  String? _audioPath;
  List<String> recent = [];
  List<double> peaks = [];
  int positionUs = 0, selectedImage = 0;
  String? selectedMarker;
  final Set<int> selectedImages = {};
  AppSettings settings = const AppSettings();
  List<EffectInstance> _copiedEffects = const [];
  Map<String, double> _copiedLegacyEffects = const {};
  int _copiedEffectDuration = 500000;
  bool _hasEffectClipboard = false;
  late final SettingsStore settingsStore = SettingsStore(
    File('${library.root.path}/app_settings.json'),
  );
  Player? _interfacePlayer;
  String? _interfaceSound;
  final Map<String, Player> _clipPlayers = {};
  final Map<String, String> _clipPaths = {};
  final ValueNotifier<AppSettings> settingsNotifier = ValueNotifier(
    const AppSettings(),
  );
  EditTemplate? pendingTemplate;
  double _lastMusicGain = -1;
  double get previewVolume => settings.previewVolume;
  bool playing = false,
      busy = false,
      exporting = false,
      dirty = false,
      countdown = true;
  int countdownValue = 0, autosaveSeconds = 60;
  String markerKey = 'G';
  double progress = 0, zoom = 1;
  bool inspectImage = false;
  BeatAnalysis? beatAnalysis;
  double beatSensitivity = .5;
  final Map<String, EffectPreset> _savedPresets = {};
  Map<String, EffectPreset> get presets => {
    ...builtinEffectPresets,
    ..._savedPresets,
  };
  void applyPreset(String name, {bool all = false}) {
    final preset = presets[name];
    if (preset == null) return;
    if (all) {
      change(
        project.copy(
          images: [
            for (final s in project.images)
              s.copy(
                effects: Map.unmodifiable(preset.effects),
                effectDurationUs: preset.durationUs,
              ),
          ],
        ),
      );
    } else if (selectedImage < project.images.length) {
      updateStill(
        project.images[selectedImage].copy(
          effects: Map.unmodifiable(preset.effects),
          effectDurationUs: preset.durationUs,
        ),
      );
    }
  }

  Future<void> savePreset(String name) async {
    if (name.trim().isEmpty ||
        name.length > 80 ||
        selectedImage >= project.images.length) {
      return;
    }
    final s = project.images[selectedImage];
    _savedPresets[name.trim()] = EffectPreset(
      name: name.trim(),
      effects: Map.unmodifiable(s.effects),
      durationUs: s.effectDurationUs,
    );
    await preferences();
    notifyListeners();
  }

  void setEffectsForAll() {
    if (selectedImage >= project.images.length) return;
    final selected = project.images[selectedImage];
    change(
      project.copy(
        images: [
          for (final s in project.images)
            s.copy(
              effects: selected.effects,
              effectDurationUs: selected.effectDurationUs,
            ),
        ],
      ),
    );
  }

  void upsertCaption(Caption caption) {
    final next = project.copy(
      captions: [...project.captions.where((c) => c.id != caption.id), caption],
    );
    next.validate();
    change(next);
  }

  void deleteCaption(String id) => change(
    project.copy(captions: project.captions.where((c) => c.id != id).toList()),
  );
  Future<void> analyzeBeats({double? sensitivity}) async {
    if (project.audio == null || busy || exporting) return;
    await stop();
    busy = true;
    notifyListeners();
    try {
      beatSensitivity = sensitivity ?? beatSensitivity;
      final envelope = await waveform(
        project.audio!,
        project.durationUs,
        bins: (project.durationUs ~/ 10000).clamp(2000, 500000),
      );
      beatAnalysis = await compute(_analyzeEnvelope, (
        envelope,
        project.durationUs,
        beatSensitivity,
      ));
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void applyBeats() {
    final analysis = beatAnalysis;
    if (analysis == null) return;
    final times =
        analysis.timesUs
            .where((t) => t > project.startUs && t < project.endUs)
            .toSet()
            .toList()
          ..sort();
    if (times.isEmpty) {
      throw StateError('В отрывке не найдены уверенные звуковые атаки');
    }
    change(
      project.copy(
        markers: [
          for (var i = 0; i < times.length; i++)
            Marker(
              id: 'beat_${DateTime.now().microsecondsSinceEpoch}_$i',
              timeUs: times[i],
            ),
        ],
      ),
    );
    selectedMarker = null;
  }

  Timer? _ticker, _autosave;
  bool _polling = false, _disposed = false;
  Future<void>? _saveInFlight;
  int _generation = 0, _revision = 0;
  Editor(this.library, this.audio) {
    _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) => _poll());
    audio.player.stream.error.listen((message) {
      if (!_disposed) {
        error = 'Аудио: $message';
        notifyListeners();
      }
    });
  }
  Future<void> initialize() async {
    settings = await settingsStore.load();
    settingsNotifier.value = settings;
    await audio.player.setVolume(settings.previewVolume * 100);
    final prefs = await library.loadPreferences();
    for (final raw
        in prefs['presets'] is List ? prefs['presets'] as List : const []) {
      try {
        final p = EffectPreset.fromJson(Map<String, dynamic>.from(raw));
        Project(
          images: [
            Still(
              path: 'preset',
              effects: p.effects,
              effectDurationUs: p.durationUs,
            ),
          ],
        ).validate();
        if (p.name.trim().isNotEmpty && p.name.length <= 80) {
          _savedPresets[p.name] = p;
        }
      } catch (_) {
        /* Ignore invalid saved presets; keep valid project data. */
      }
    }
    markerKey =
        prefs['markerKey'] is String &&
            RegExp(r'^[a-zA-Z0-9]$').hasMatch(prefs['markerKey'] as String)
        ? prefs['markerKey'] as String
        : 'G';
    countdown = prefs['countdown'] is bool ? prefs['countdown'] as bool : true;
    final seconds = prefs['autosaveSeconds'];
    autosaveSeconds =
        (seconds is num && seconds.isFinite ? seconds.toInt() : 60).clamp(
          10,
          600,
        );
    recent = (prefs['recent'] is List ? prefs['recent'] as List : const [])
        .whereType<String>()
        .take(12)
        .toList();
    snapToMarkers = prefs['snapToMarkers'] is bool
        ? prefs['snapToMarkers'] as bool
        : true;
    double width(String name, double fallback) {
      final value = prefs[name];
      return value is num && value.isFinite
          ? value.toDouble().clamp(180, 420)
          : fallback;
    }

    libraryPanelWidth = width('libraryPanelWidth', 238);
    propertiesPanelWidth = width('propertiesPanelWidth', 300);
    _setAutosave();
    notifyListeners();
  }

  Future<void> preferences() async {
    _setAutosave();
    await library.preferences({
      'markerKey': markerKey,
      'countdown': countdown,
      'autosaveSeconds': autosaveSeconds,
      'recent': recent,
      'presets': _savedPresets.values.map((p) => p.toJson()).toList(),
      'snapToMarkers': snapToMarkers,
      'libraryPanelWidth': libraryPanelWidth,
      'propertiesPanelWidth': propertiesPanelWidth,
    });
  }

  void _setAutosave() {
    _autosave?.cancel();
    if (!settings.autosave) return;
    _autosave = Timer.periodic(Duration(seconds: autosaveSeconds), (_) {
      if (dirty && !busy && !exporting) {
        unawaited(guard(() => save(autosave: true)));
      }
    });
  }

  void refresh() => notifyListeners();
  void change(Project next) {
    final removed = project.markers
        .map((m) => m.id)
        .toSet()
        .difference(next.markers.map((m) => m.id).toSet());
    if (removed.isNotEmpty) {
      next = next.copy(
        globalEffects: [
          for (final l in next.globalEffects)
            l.copy(
              markerIds: l.markerIds
                  .where((id) => !removed.contains(id))
                  .toList(),
            ),
        ],
      );
    }
    next.validate();
    selectedImages.removeWhere((i) => i < 0 || i >= next.images.length);
    history.change(next);
    dirty = true;
    _revision++;
    notifyListeners();
  }

  Future<void> undo() async {
    if (busy || exporting || !history.canUndo) return;
    final before = project;
    history.undo();
    dirty = true;
    _revision++;
    await _restoreHistory(before);
  }

  Future<void> redo() async {
    if (busy || exporting || !history.canRedo) return;
    final before = project;
    history.redo();
    dirty = true;
    _revision++;
    await _restoreHistory(before);
  }

  Future<void> _restoreHistory(Project before) async {
    selectedImages.clear();
    selectedImage = selectedImage.clamp(0, mathMaxImageIndex());
    if (!project.markers.any((m) => m.id == selectedMarker)) {
      selectedMarker = null;
    }
    if (before.audio != project.audio) {
      beatAnalysis = null;
      busy = true;
      notifyListeners();
      try {
        await stop();
        peaks = [];
        if (project.audio != null) {
          await _openAudio(project.audio!);
          await seek(positionUs.clamp(project.startUs, project.endUs));
          try {
            peaks = await waveform(project.audio!, project.durationUs);
          } catch (e) {
            error = 'Звуковая волна: $e';
          }
        } else {
          positionUs = 0;
        }
      } finally {
        busy = false;
      }
    } else if (project.audio != null &&
        (positionUs < project.startUs || positionUs > project.endUs)) {
      await seek(positionUs);
    }
    if (!_disposed) notifyListeners();
  }

  int mathMaxImageIndex() =>
      project.images.isEmpty ? 0 : project.images.length - 1;

  Future<void> guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      error = e.toString();
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _poll() async {
    if (_polling || !playing || _disposed) return;
    _polling = true;
    try {
      positionUs = await audio.positionUs();
      if (positionUs >= project.endUs) {
        await audio.player.pause();
        playing = false;
        positionUs = project.endUs;
      }
      try {
        await _syncClipAudio();
      } catch (err) {
        if (!_disposed) error = 'Дополнительный звук: $err';
      }
      if (!_disposed) notifyListeners();
    } finally {
      _polling = false;
    }
  }

  Future<void> stop() async {
    _generation++;
    countdownValue = 0;
    await audio.player.pause();
    await Future.wait(_clipPlayers.values.map((p) => p.pause()));
    playing = false;
    positionUs = await audio.positionUs();
    notifyListeners();
  }

  Future<int> _openAudio(String path) async {
    _audioPath = null;
    final duration = await audio.open(path);
    _audioPath = path;
    return duration;
  }

  Future<void> toggle() async {
    if (project.audio == null || busy || exporting) return;
    if (playing || countdownValue > 0) {
      await stop();
      return;
    }
    final token = ++_generation;
    inspectImage = false;
    busy = true;
    notifyListeners();
    try {
      if (_audioPath != project.audio) await _openAudio(project.audio!);
      await previewImages.prepare(
        project.segments
            .map((s) => project.images[s.imageIndex])
            .where((s) => s.kind == 'image')
            .map((s) => s.path),
      );
    } finally {
      busy = false;
      notifyListeners();
    }
    if (token != _generation || _disposed) return;
    if (countdown) {
      for (var i = 3; i > 0; i--) {
        countdownValue = i;
        notifyListeners();
        await Future<void>.delayed(const Duration(seconds: 1));
        if (token != _generation || _disposed) return;
      }
    }
    countdownValue = 0;
    if (positionUs < project.startUs || positionUs >= project.endUs) {
      await seek(project.startUs);
    }
    await audio.player.play();
    playing = true;
    notifyListeners();
  }

  Future<void> seek(int timeUs) async {
    inspectImage = false;
    positionUs = timeUs.clamp(project.startUs, project.endUs);
    await audio.player.seek(Duration(microseconds: positionUs));
    await _syncClipAudio();
    notifyListeners();
  }

  Future<void> capture() async {
    if (!playing || exporting || busy) return;
    final time = await audio.positionUs();
    addMarker(time);
  }

  void addMarker(int timeUs) {
    if (project.audio == null) return;
    final marker = Marker(
      id: '${DateTime.now().microsecondsSinceEpoch}_${project.markers.length}',
      timeUs: timeUs.clamp(project.startUs, project.endUs),
    );
    selectedMarker = marker.id;
    change(project.copy(markers: [...project.markers, marker]));
    _playInterfaceSound();
  }

  void moveMarker(String id, int timeUs) {
    change(
      project.copy(
        markers: [
          for (final m in project.markers)
            if (m.id == id)
              Marker(id: id, timeUs: timeUs.clamp(0, project.durationUs))
            else
              m,
        ],
      ),
    );
  }

  void deleteMarker() {
    change(
      project.copy(
        markers: project.markers.where((m) => m.id != selectedMarker).toList(),
      ),
    );
    selectedMarker = null;
  }

  void reorder(int oldIndex, int newIndex) {
    final selected = selectedImages
        .where((i) => i < project.images.length)
        .map((i) => project.images[i])
        .toSet();
    final list = [...project.images];
    if (newIndex > oldIndex) newIndex--;
    final image = list.removeAt(oldIndex);
    list.insert(newIndex, image);
    selectedImages
      ..clear()
      ..addAll([
        for (var i = 0; i < list.length; i++)
          if (selected.contains(list[i])) i,
      ]);
    selectedImage = newIndex;
    change(project.copy(images: list));
  }

  void updateStill(Still image) {
    inspectImage = true;
    if (selectedImage >= project.images.length) return;
    final list = [...project.images];
    list[selectedImage] = image;
    change(project.copy(images: list));
  }

  Future<void> newProject(String name) async {
    await _saveInFlight;
    await stop();
    _revision++;
    history = ProjectHistory(
      Project(
        name: name,
        frameRate: settings.exportFps,
        resolution: settings.exportHeight,
        videoCrf: _crf(settings.exportQuality),
      ),
    );
    selectedImages.clear();
    pendingTemplate = null;
    beatAnalysis = null;
    projectPath = null;
    dirty = false;
    positionUs = 0;
    peaks = [];
    selectedMarker = null;
    selectedImage = 0;
    notifyListeners();
  }

  Future<void> importAudio() async {
    final picked = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Музыка',
          extensions: ['mp3', 'wav', 'flac', 'ogg'],
        ),
      ],
    );
    if (picked == null) return;
    await useAudioPath(picked.path);
  }

  Future<void> useAudioPath(String sourcePath) async {
    await stop();
    busy = true;
    notifyListeners();
    try {
      final path = await library.importFile(sourcePath);
      final duration = await _openAudio(path);
      change(
        project.copy(
          audio: path,
          durationUs: duration,
          startUs: 0,
          endUs: duration,
          markers: [],
          captions: [],
          audioClips: [],
          visualClips: [],
          globalEffects: [],
        ),
      );
      positionUs = 0;
      beatAnalysis = null;
      peaks = [];
      try {
        peaks = await waveform(path, duration);
      } catch (e) {
        error = 'Аудио загружено, но звуковая волна недоступна: $e';
      }
    } finally {
      busy = false;
      notifyListeners();
    }
    if (pendingTemplate != null &&
        project.audio != null &&
        project.images.isNotEmpty) {
      await applyTemplate(pendingTemplate!);
    }
  }

  Future<void> importImages() async {
    final picked = await openFiles(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Изображения, видео и GIF',
          extensions: [
            'jpg',
            'jpeg',
            'png',
            'webp',
            'gif',
            'mp4',
            'mov',
            'mkv',
            'webm',
            'm4v',
          ],
        ),
      ],
    );
    if (picked.isEmpty) return;
    await useMediaPaths(picked.map((f) => f.path).toList());
  }

  Future<void> useMediaPaths(List<String> sources) async {
    if (sources.isEmpty) return;
    busy = true;
    notifyListeners();
    try {
      final list = [...project.images];
      for (final path in sources) {
        final info = await inspectMedia(path);
        list.add(
          Still(
            path: await library.importFile(path),
            durationUs: info.durationUs,
          ),
        );
      }
      change(project.copy(images: list));
    } finally {
      busy = false;
      notifyListeners();
    }
    if (pendingTemplate != null &&
        project.audio != null &&
        project.images.isNotEmpty) {
      await applyTemplate(pendingTemplate!);
    }
  }

  Future<void> save({bool autosave = false, bool saveAs = false}) async {
    final active = _saveInFlight;
    if (active != null) {
      await active;
      return save(autosave: autosave, saveAs: saveAs);
    }
    final task = _writeProject(autosave: autosave, saveAs: saveAs);
    _saveInFlight = task;
    try {
      await task;
    } finally {
      if (identical(_saveInFlight, task)) _saveInFlight = null;
    }
  }

  Future<void> _writeProject({
    required bool autosave,
    required bool saveAs,
  }) async {
    var path = projectPath;
    // Saving a legacy project creates a new .tve sibling; keep its original.
    if (!autosave && path != null && path.toLowerCase().endsWith('.leos')) {
      path = '${path.substring(0, path.length - 5)}.tve';
    }
    if (saveAs || path == null) {
      if (Platform.isWindows && !autosave) {
        final target = await getSaveLocation(
          suggestedName: '${project.name}.tve',
          acceptedTypeGroups: [
            const XTypeGroup(
              label: 'Tiger Video Edit Project',
              extensions: ['tve'],
            ),
          ],
        );
        if (target == null) return;
        path = target.path;
      } else {
        path = library.projectPath(project.name);
      }
    }
    final snapshot = project, revision = _revision;
    if (autosave && !await File(path).exists()) {
      await ProjectStore.save(path, snapshot);
    }
    await ProjectStore.save(autosave ? '$path.autosave' : path, snapshot);
    projectPath = path;
    if (!autosave && revision == _revision) dirty = false;
    recent = [path, ...recent.where((p) => p != path)].take(12).toList();
    await preferences();
    if (!_disposed) notifyListeners();
  }

  Future<void> openProject([String? path]) async {
    await _saveInFlight;
    if (path == null) {
      final pick = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Tiger Video Edit Project',
            extensions: ['tve', 'leos', 'autosave', 'bak'],
          ),
        ],
      );
      if (pick == null) return;
      path = pick.path;
    }
    final next = await ProjectStore.read(path);
    await stop();
    _revision++;
    history = ProjectHistory(next);
    selectedImages.clear();
    pendingTemplate = null;
    beatAnalysis = null;
    projectPath = path;
    dirty = false;
    selectedImage = 0;
    selectedMarker = null;
    peaks = [];
    positionUs = next.startUs;
    notifyListeners();
    if (next.audio != null && await File(next.audio!).exists()) {
      busy = true;
      notifyListeners();
      try {
        await _openAudio(next.audio!);
        await seek(next.startUs);
        peaks = await waveform(next.audio!, next.durationUs);
      } finally {
        busy = false;
        notifyListeners();
      }
    }
    recent = [path, ...recent.where((p) => p != path)].take(12).toList();
    await preferences();
    final absent = await ProjectStore.missing(next);
    if (absent.isNotEmpty) {
      error =
          'Не найдены исходники (${absent.length}). Используйте «Восстановить пути».';
      notifyListeners();
    }
  }

  Future<void> relink(String old, String replacement) async {
    if (project.audio == old) {
      beatAnalysis = null;
      final duration = await _openAudio(replacement);
      if (duration < project.endUs) {
        throw const FormatException('Новая музыка короче выбранного отрывка');
      }
      change(project.copy(audio: replacement, durationUs: duration));
      peaks = await waveform(replacement, duration);
      await seek(project.startUs);
    } else {
      final info = await inspectMedia(replacement);
      change(
        project.copy(
          images: [
            for (final s in project.images)
              s.path == old
                  ? s.copy(
                      path: replacement,
                      durationUs: info.durationUs,
                      sourceStartUs: 0,
                    )
                  : s,
          ],
        ),
      );
    }
  }

  Future<void> exportVideo() async {
    if (exporting || busy) return;
    if (project.audio == null || project.images.isEmpty) {
      throw StateError('Добавьте музыку и изображения');
    }
    var path = '${project.name}.mp4';
    if (Platform.isWindows) {
      final target = await getSaveLocation(
        suggestedName: path,
        acceptedTypeGroups: [
          const XTypeGroup(label: 'MP4', extensions: ['mp4']),
        ],
      );
      if (target == null) return;
      path = target.path;
    }
    await stop();
    exporting = true;
    progress = 0;
    notifyListeners();
    try {
      await exporter.export(project, path, (value) {
        progress = value;
        notifyListeners();
      });
    } finally {
      exporting = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _ticker?.cancel();
    _autosave?.cancel();
    exporter.cancel();
    unawaited(audio.player.dispose());
    if (_interfacePlayer != null) unawaited(_interfacePlayer!.dispose());
    for (final p in _clipPlayers.values) {
      unawaited(p.dispose());
    }
    super.dispose();
  }

  Future<void> updateSettings(AppSettings next) async {
    final previous = settings;
    settings = next;
    settingsNotifier.value = settings;
    _setAutosave();
    if (next.exportHeight != previous.exportHeight ||
        next.exportFps != previous.exportFps ||
        next.exportQuality != previous.exportQuality) {
      change(
        project.copy(
          frameRate: next.exportFps,
          resolution: next.exportHeight,
          videoCrf: _crf(next.exportQuality),
        ),
      );
    }
    await settingsStore.save(next);
    if (_disposed) return;
    await audio.player.setVolume(
      settings.previewVolume * project.musicVolume * 100,
    );
    _setAutosave();
    notifyListeners();
  }

  void selectAllImages() {
    selectedImages
      ..clear()
      ..addAll(List.generate(project.images.length, (i) => i));
    notifyListeners();
  }

  void clearImageSelection() {
    selectedImages.clear();
    notifyListeners();
  }

  void selectImage(int index, {bool additive = false}) {
    if (index < 0 || index >= project.images.length) return;
    if (!additive) selectedImages.clear();
    if (additive && selectedImages.contains(index)) {
      selectedImages.remove(index);
    } else {
      selectedImages.add(index);
    }
    selectedImage = index;
    inspectImage = true;
    notifyListeners();
  }

  Set<int> _targets(bool all) => all
      ? List.generate(project.images.length, (i) => i).toSet()
      : selectedImages.isEmpty
      ? {selectedImage}
      : Set.of(selectedImages);
  void applyEffectRecipe(EffectRecipe recipe, {bool all = false}) {
    final targets = _targets(all),
        stamp = DateTime.now().microsecondsSinceEpoch;
    change(
      project.copy(
        images: [
          for (var i = 0; i < project.images.length; i++)
            targets.contains(i)
                ? project.images[i].copy(
                    effectStack: [
                      ...project.images[i].effectStack,
                      for (var j = 0; j < recipe.effects.length; j++)
                        recipe.effects[j].copy(id: 'recipe_${stamp}_${i}_$j'),
                    ],
                  )
                : project.images[i],
        ],
      ),
    );
    unawaited(
      guard(
        () => updateSettings(
          settings.copyWith(
            recentEffects: [
              recipe.name,
              ...settings.recentEffects.where((n) => n != recipe.name),
            ].take(30).toList(),
          ),
        ),
      ),
    );
  }

  void copyEffects() {
    if (selectedImage < project.images.length) {
      _copiedEffects = List.of(project.images[selectedImage].effectStack);
      _copiedLegacyEffects = Map.of(project.images[selectedImage].effects);
      _copiedEffectDuration = project.images[selectedImage].effectDurationUs;
      _hasEffectClipboard = true;
    }
    notifyListeners();
  }

  void pasteEffects({bool all = false}) {
    if (!_hasEffectClipboard) return;
    final targets = _targets(all),
        stamp = DateTime.now().microsecondsSinceEpoch;
    change(
      project.copy(
        images: [
          for (var i = 0; i < project.images.length; i++)
            targets.contains(i)
                ? project.images[i].copy(
                    effects: Map.of(_copiedLegacyEffects),
                    effectDurationUs: _copiedEffectDuration,
                    effectStack: [
                      for (var j = 0; j < _copiedEffects.length; j++)
                        _copiedEffects[j].copy(id: 'copy_${stamp}_${i}_$j'),
                    ],
                  )
                : project.images[i],
        ],
      ),
    );
  }

  void addGlobalEffect(
    EffectRecipe recipe, {
    GlobalEffectMode mode = GlobalEffectMode.always,
    int? startUs,
    int? endUs,
    List<String>? markerIds,
  }) {
    if (project.audio == null) throw StateError('Сначала добавьте музыку');
    final ids = markerIds ?? [?selectedMarker];
    if (mode == GlobalEffectMode.selectedMarkers && ids.isEmpty) {
      throw StateError('Выберите маркеры для эффекта');
    }
    final start = (startUs ?? project.startUs).clamp(
          project.startUs,
          project.endUs - 1,
        ),
        end = (endUs ?? project.endUs).clamp(start + 1, project.endUs);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final continuous =
        mode == GlobalEffectMode.always || mode == GlobalEffectMode.range;
    final layer = GlobalAdjustmentLayer(
      id: 'global_$stamp',
      mode: mode,
      startUs: start,
      endUs: end,
      markerIds: ids,
      effects: [
        for (var i = 0; i < recipe.effects.length; i++)
          recipe.effects[i].copy(
            id: 'global_${stamp}_$i',
            durationUs: continuous ? end - start : recipe.effects[i].durationUs,
            endIntensity: continuous
                ? recipe.effects[i].beginIntensity
                : recipe.effects[i].endIntensity,
          ),
      ],
    );
    change(project.copy(globalEffects: [...project.globalEffects, layer]));
  }

  void updateGlobalLayer(GlobalAdjustmentLayer layer) => change(
    project.copy(
      globalEffects: [
        for (final l in project.globalEffects) l.id == layer.id ? layer : l,
      ],
    ),
  );
  void deleteGlobalLayer(String id) => change(
    project.copy(
      globalEffects: project.globalEffects.where((l) => l.id != id).toList(),
    ),
  );
  void setGlobalEffectsEnabled(bool enabled) =>
      change(project.copy(globalEffectsEnabled: enabled));

  void addSound(SoundEffect sound, {bool atMarkers = false}) {
    if (project.audio == null) throw StateError('Сначала добавьте музыку');
    final times = atMarkers
        ? project.markers
              .map((m) => m.timeUs)
              .where((t) => t >= project.startUs && t < project.endUs)
              .toList()
        : [positionUs.clamp(project.startUs, project.endUs - 1)];
    if (atMarkers && times.isEmpty) {
      throw StateError('Сначала добавьте маркеры');
    }
    if (project.audioClips.length + times.length > 1024) {
      throw StateError('В проекте допустимо до 1024 аудиоклипов');
    }
    final stamp = DateTime.now().microsecondsSinceEpoch;
    change(
      project.copy(
        audioClips: [
          ...project.audioClips,
          for (var i = 0; i < times.length; i++)
            AudioClip(
              id: 'sound_${stamp}_$i',
              path: sound.path,
              startUs: times[i],
              durationUs: sound.duration.inMicroseconds.clamp(
                1,
                project.endUs - times[i],
              ),
              fadeOutUs: 0,
              track: 0,
            ),
        ],
      ),
    );
  }

  void updateAudioClip(AudioClip clip) => change(
    project.copy(
      audioClips: [
        for (final c in project.audioClips) c.id == clip.id ? clip : c,
      ],
    ),
  );
  Future<void> importAudioLayer() async {
    if (project.audio == null) {
      throw StateError('Сначала добавьте основную музыку');
    }
    final picked = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Дополнительное аудио',
          extensions: ['mp3', 'wav', 'flac', 'ogg'],
        ),
      ],
    );
    if (picked == null) return;
    await stop();
    busy = true;
    notifyListeners();
    AudioEngine? probe;
    try {
      final path = await library.importFile(picked.path);
      probe = AudioEngine();
      final duration = await probe.open(path);
      addAudioLayer(path, duration);
    } finally {
      await probe?.player.dispose();
      busy = false;
      notifyListeners();
    }
  }

  void addAudioLayer(String path, int durationUs) {
    if (project.audio == null || durationUs <= 0) {
      throw StateError('Добавьте музыку и корректный аудиофайл');
    }
    final start = positionUs.clamp(project.startUs, project.endUs - 1);
    final track = project.audioClips.isEmpty
        ? 0
        : (project.audioClips
                      .map((c) => c.track)
                      .reduce((a, b) => a > b ? a : b) +
                  1)
              .clamp(0, 15);
    change(
      project.copy(
        audioClips: [
          ...project.audioClips,
          AudioClip(
            id: 'audio_${DateTime.now().microsecondsSinceEpoch}',
            path: path,
            startUs: start,
            durationUs: durationUs.clamp(1, project.endUs - start),
            track: track,
            group: 'music',
          ),
        ],
      ),
    );
  }

  void deleteAudioClip(String id) => change(
    project.copy(
      audioClips: project.audioClips.where((c) => c.id != id).toList(),
    ),
  );
  void duplicateAudioClip(AudioClip clip) {
    if (project.audioClips.length >= 1024) {
      error = 'Допустимо до 1024 аудиоклипов';
      notifyListeners();
      return;
    }
    try {
      change(
        project.copy(
          audioClips: [
            ...project.audioClips,
            clip.copy(
              id: 'copy_${DateTime.now().microsecondsSinceEpoch}',
              startUs: (clip.startUs + clip.durationUs).clamp(
                project.startUs,
                (project.endUs - clip.durationUs).clamp(
                  project.startUs,
                  project.endUs,
                ),
              ),
            ),
          ],
        ),
      );
    } on FormatException catch (err) {
      error = err.message;
      notifyListeners();
    }
  }

  int snapTime(int us, {String? excludeMarkerId}) {
    if (!snapToMarkers) return us.clamp(project.startUs, project.endUs);
    final times = [
      project.startUs,
      project.endUs,
      ...project.markers
          .where((m) => m.id != excludeMarkerId)
          .map((m) => m.timeUs),
      ...?beatAnalysis?.timesUs,
    ];
    var value = us;
    for (final t in times) {
      if ((t - us).abs() < 80000 &&
          (value == us || (t - us).abs() < (value - us).abs())) {
        value = t;
      }
    }
    return value.clamp(project.startUs, project.endUs);
  }

  bool snapToMarkers = true;
  double libraryPanelWidth = 238, propertiesPanelWidth = 300;
  void addVisualLayer(int index) {
    if (project.audio == null || index >= project.images.length) return;
    final start = positionUs.clamp(project.startUs, project.endUs - 1),
        duration = (project.endUs - start).clamp(1, 2000000);
    change(
      project.copy(
        visualClips: [
          ...project.visualClips,
          VisualClip(
            id: 'visual_${DateTime.now().microsecondsSinceEpoch}',
            media: project.images[index].copy(
              scale: .4,
              cover: false,
              x: .22,
              y: .22,
            ),
            startUs: start,
            durationUs: duration,
            track: 1,
          ),
        ],
      ),
    );
  }

  void updateVisualClip(VisualClip clip) => change(
    project.copy(
      visualClips: [
        for (final c in project.visualClips) c.id == clip.id ? clip : c,
      ],
    ),
  );
  void deleteVisualClip(String id) => change(
    project.copy(
      visualClips: project.visualClips.where((c) => c.id != id).toList(),
    ),
  );

  Future<void> _syncClipAudio() async {
    final musicGain = settings.previewVolume * project.musicVolume * 100;
    if (musicGain != _lastMusicGain) {
      await audio.player.setVolume(musicGain);
      _lastMusicGain = musicGain;
    }
    final active = playing
        ? project.audioClips
              .where((c) => c.gainAt(positionUs) > 0)
              .take(16)
              .toList()
        : <AudioClip>[];
    final ids = active.map((c) => c.id).toSet();
    for (final entry in _clipPlayers.entries) {
      if (!ids.contains(entry.key) && entry.value.state.playing) {
        await entry.value.pause();
      }
    }
    for (final c in active) {
      var p = _clipPlayers[c.id];
      if (p == null || _clipPaths[c.id] != c.path) {
        if (p != null) await p.dispose();
        p = Player();
        _clipPlayers[c.id] = p;
        _clipPaths[c.id] = c.path;
        await p.open(Media(c.path), play: false);
      }
      final target = c.sourceStartUs + positionUs - c.startUs;
      if (!p.state.playing ||
          (p.state.position.inMicroseconds - target).abs() > 75000) {
        await p.seek(Duration(microseconds: target));
      }
      await p.setVolume(
        c.gainAt(positionUs) *
            (c.group == 'sfx' ? project.soundVolume : 1) *
            settings.previewVolume *
            100,
      );
      if (!p.state.playing) await p.play();
    }
    for (final id
        in _clipPlayers.keys
            .where((id) => !project.audioClips.any((c) => c.id == id))
            .toList()) {
      await _clipPlayers.remove(id)!.dispose();
      _clipPaths.remove(id);
    }
    while (_clipPlayers.length > 16) {
      final inactive = _clipPlayers.keys
          .where((id) => !ids.contains(id))
          .firstOrNull;
      if (inactive == null) break;
      await _clipPlayers.remove(inactive)!.dispose();
      _clipPaths.remove(inactive);
    }
  }

  Future<void> applyAutoEdit(String profile) async {
    final template = builtinEditTemplates.firstWhere(
      (t) => t.profile == profile,
    );
    await applyTemplate(template);
  }

  Future<void> applyTemplate(EditTemplate template) async {
    template.validate();
    if (project.audio == null || project.images.isEmpty) {
      pendingTemplate = template;
      notifyListeners();
      return;
    }
    if (beatAnalysis == null) await analyzeBeats();
    final beats =
        beatAnalysis?.timesUs
            .where((t) => t > project.startUs && t < project.endUs)
            .toList() ??
        [];
    final markers = <Marker>[];
    for (var i = 0; i < beats.length; i += template.beatStep) {
      markers.add(Marker(id: 'auto_${template.id}_$i', timeUs: beats[i]));
    }
    // Silent material retains the current manual cuts, never an invented beat grid.
    final stamp = DateTime.now().microsecondsSinceEpoch;
    change(
      project.copy(
        portrait: template.portrait,
        markers: markers.isEmpty ? project.markers : markers,
        images: [
          for (var i = 0; i < project.images.length; i++)
            project.images[i].copy(
              effectStack: [
                for (var j = 0; j < template.effects.length; j++)
                  template.effects[j].copy(id: 'template_${stamp}_${i}_$j'),
              ],
              animations: template.animations,
            ),
        ],
        globalEffects: [
          for (final g in template.globalEffects)
            g.copy(
              markerIds: const [],
              startUs: project.startUs,
              endUs: project.endUs,
              mode: g.mode == GlobalEffectMode.selectedMarkers
                  ? GlobalEffectMode.everyMarker
                  : g.mode,
            ),
        ],
      ),
    );
    pendingTemplate = null;
  }

  static int _crf(ExportQuality quality) => switch (quality) {
    ExportQuality.standard => 26,
    ExportQuality.high => 20,
    ExportQuality.maximum => 16,
  };
  void _playInterfaceSound() {
    if (!settings.interfaceSounds || _disposed) return;
    unawaited(
      guard(() async {
        if (_interfaceSound == null) {
          final sounds = await SoundLibrary(
            Directory('${library.root.path}/sounds'),
          ).generate();
          _interfaceSound = sounds.firstWhere((s) => s.id == 'click').path;
        }
        if (_disposed) return;
        _interfacePlayer ??= Player();
        await _interfacePlayer!.setVolume(settings.previewVolume * 25);
        await _interfacePlayer!.open(Media(_interfaceSound!), play: true);
      }),
    );
  }
}
