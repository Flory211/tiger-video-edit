import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:file_selector/file_selector.dart';

import 'model.dart';
import 'storage.dart';
import 'platform_media.dart';
import 'media_frames.dart';
import 'beat.dart';

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
      beatAnalysis = detectBeats(
        envelope,
        project.durationUs,
        sensitivity: beatSensitivity,
      );
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
    final prefs = await library.loadPreferences();
    for (final raw in (prefs['presets'] as List?) ?? []) {
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
    markerKey = (prefs['markerKey'] as String?) ?? 'G';
    countdown = (prefs['countdown'] as bool?) ?? true;
    autosaveSeconds = ((prefs['autosaveSeconds'] as num?)?.toInt() ?? 60).clamp(
      10,
      600,
    );
    recent = (prefs['recent'] as List? ?? [])
        .whereType<String>()
        .take(12)
        .toList();
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
    });
  }

  void _setAutosave() {
    _autosave?.cancel();
    _autosave = Timer.periodic(Duration(seconds: autosaveSeconds), (_) {
      if (dirty && !busy && !exporting) {
        unawaited(guard(() => save(autosave: true)));
      }
    });
  }

  void refresh() => notifyListeners();
  void change(Project next) {
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
      if (!_disposed) notifyListeners();
    } finally {
      _polling = false;
    }
  }

  Future<void> stop() async {
    _generation++;
    countdownValue = 0;
    await audio.player.pause();
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
    final list = [...project.images];
    if (newIndex > oldIndex) newIndex--;
    final image = list.removeAt(oldIndex);
    list.insert(newIndex, image);
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
    history = ProjectHistory(Project(name: name));
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
    await stop();
    busy = true;
    notifyListeners();
    try {
      final path = await library.importFile(picked.path);
      final duration = await _openAudio(path);
      change(
        project.copy(
          audio: path,
          durationUs: duration,
          startUs: 0,
          endUs: duration,
          markers: [],
          captions: [],
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
    busy = true;
    notifyListeners();
    try {
      final list = [...project.images];
      for (final file in picked) {
        final info = await inspectMedia(file.path);
        list.add(
          Still(
            path: await library.importFile(file.path),
            durationUs: info.durationUs,
          ),
        );
      }
      change(project.copy(images: list));
    } finally {
      busy = false;
      notifyListeners();
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
    super.dispose();
  }
}
