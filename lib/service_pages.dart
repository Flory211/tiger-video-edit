import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app_settings.dart';
import 'music_library.dart';
import 'sound_library.dart';
import 'update_service.dart';

void _showError(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$error')));

Widget _pageBody(Widget child) => Align(
  alignment: Alignment.topCenter,
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 900),
    child: child,
  ),
);

String _duration(Duration duration) => duration == Duration.zero
    ? 'Длительность неизвестна'
    : '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

class SettingsPage extends StatefulWidget {
  final AppSettings settings;
  final Future<void> Function(AppSettings) onChanged;
  const SettingsPage({
    super.key,
    required this.settings,
    required this.onChanged,
  });
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late AppSettings settings = widget.settings;
  late AppSettings committed = widget.settings;
  bool saving = false;
  Future<void> _apply(AppSettings value) async {
    final previous = committed;
    setState(() {
      settings = value;
      saving = true;
    });
    try {
      await widget.onChanged(value);
      committed = value;
    } catch (error) {
      if (mounted) {
        setState(() => settings = previous);
        _showError(context, error);
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget _switch(
    String label,
    String subtitle,
    bool value,
    AppSettings Function(bool) update,
  ) => SwitchListTile(
    title: Text(label),
    subtitle: Text(subtitle),
    value: value,
    onChanged: saving ? null : (next) => _apply(update(next)),
  );
  Widget _choice<T>(
    String label,
    T value,
    Map<T, String> choices,
    AppSettings Function(T) update,
  ) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: DropdownButtonFormField<T>(
      key: ValueKey('$label-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: choices.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: saving
          ? null
          : (next) {
              if (next != null) _apply(update(next));
            },
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Настройки')),
    body: _pageBody(
      ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (saving) const LinearProgressIndicator(),
          _choice('Тема', settings.theme, {
            AppTheme.system: 'Как в системе',
            AppTheme.dark: 'Тёмная',
            AppTheme.light: 'Светлая',
          }, (v) => settings.copyWith(theme: v)),
          const ListTile(
            title: Text('Язык: Русский'),
            subtitle: Text(
              'Перевод интерфейса на английский пока не завершён.',
            ),
          ),
          _switch(
            'Анимации интерфейса',
            'Переходы и появление элементов',
            settings.animations,
            (v) => settings.copyWith(animations: v),
          ),
          _switch(
            'Уменьшить анимации',
            'Системное уменьшение движения учитывается всегда',
            settings.reducedMotion,
            (v) => settings.copyWith(reducedMotion: v),
          ),
          _switch(
            'Автосохранение',
            'Восстанавливать изменения после прерывания работы',
            settings.autosave,
            (v) => settings.copyWith(autosave: v),
          ),
          _switch(
            'Звуки интерфейса',
            'Короткий отклик при действиях',
            settings.interfaceSounds,
            (v) => settings.copyWith(interfaceSounds: v),
          ),
          ListTile(
            title: const Text('Громкость предпросмотра'),
            subtitle: Slider(
              value: settings.previewVolume,
              label: '${(settings.previewVolume * 100).round()}%',
              onChanged: saving
                  ? null
                  : (v) => setState(
                      () => settings = settings.copyWith(previewVolume: v),
                    ),
              onChangeEnd: (v) => _apply(settings.copyWith(previewVolume: v)),
            ),
          ),
          _choice('Качество предпросмотра', settings.previewQuality, {
            PreviewQuality.low: 'Низкое',
            PreviewQuality.medium: 'Среднее',
            PreviewQuality.high: 'Высокое',
          }, (v) => settings.copyWith(previewQuality: v)),
          _choice('Качество экспорта по умолчанию', settings.exportQuality, {
            ExportQuality.standard: 'Стандартное',
            ExportQuality.high: 'Высокое',
            ExportQuality.maximum: 'Максимальное',
          }, (v) => settings.copyWith(exportQuality: v)),
          _choice('Высота экспорта по умолчанию', settings.exportHeight, {
            480: '480p',
            720: '720p',
            1080: '1080p',
          }, (v) => settings.copyWith(exportHeight: v)),
          _choice('Частота кадров по умолчанию', settings.exportFps, {
            24: '24 fps',
            30: '30 fps',
            60: '60 fps',
          }, (v) => settings.copyWith(exportFps: v)),
          _switch(
            'Проверять обновления автоматически',
            'Не чаще одного раза в сутки при запуске',
            settings.autoCheckUpdates,
            (v) => settings.copyWith(autoCheckUpdates: v),
          ),
          _switch(
            'Уведомления об обновлениях',
            'Сообщать о новой совместимой версии',
            settings.updateNotifications,
            (v) => settings.copyWith(updateNotifications: v),
          ),
          ListTile(
            title: Text(
              'Избранные эффекты: ${settings.favoriteEffects.length}',
            ),
            trailing: settings.favoriteEffects.isEmpty
                ? null
                : TextButton(
                    onPressed: saving
                        ? null
                        : () => _apply(settings.copyWith(favoriteEffects: {})),
                    child: const Text('Очистить'),
                  ),
          ),
          ListTile(
            title: Text('Недавние эффекты: ${settings.recentEffects.length}'),
            trailing: settings.recentEffects.isEmpty
                ? null
                : TextButton(
                    onPressed: saving
                        ? null
                        : () => _apply(settings.copyWith(recentEffects: [])),
                    child: const Text('Очистить'),
                  ),
          ),
        ],
      ),
    ),
  );
}

/// The preview player is lazy and independent of the editor's music player.
mixin _AudioPreview<T extends StatefulWidget> on State<T> {
  Player? _player;
  String? previewPath;
  double get previewVolume => 1;
  Player get previewPlayer => _player ??= Player();
  Future<Duration> probe(String path) async {
    await previewPlayer.open(Media(path), play: false);
    final duration = previewPlayer.state.duration;
    return duration > Duration.zero
        ? duration
        : await previewPlayer.stream.duration
              .firstWhere((value) => value > Duration.zero)
              .timeout(const Duration(seconds: 20));
  }

  Future<void> preview(String path) async {
    try {
      if (!await File(path).exists()) {
        throw const FileSystemException('Аудиофайл не найден');
      }
      if (previewPath == path) {
        await stopPreview();
        return;
      }
      await previewPlayer.setVolume(previewVolume.clamp(0, 1) * 100);
      await previewPlayer.open(Media(path));
      if (mounted) setState(() => previewPath = path);
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Future<void> stopPreview() async {
    await _player?.stop();
    if (mounted) setState(() => previewPath = null);
  }

  @override
  void dispose() {
    unawaited(_player?.dispose());
    super.dispose();
  }
}

class MusicLibraryPage extends StatefulWidget {
  final MusicLibrary library;
  final Future<void> Function(MusicTrack) onUse;
  final String language;
  final double previewVolume;
  const MusicLibraryPage({
    super.key,
    required this.library,
    required this.onUse,
    this.language = 'ru',
    this.previewVolume = 1,
  });
  @override
  State<MusicLibraryPage> createState() => _MusicLibraryPageState();
}

class _MusicLibraryPageState extends State<MusicLibraryPage>
    with _AudioPreview {
  bool loading = true,
      importing = false,
      favoritesOnly = false,
      historyOnly = false;
  String query = '', genre = '';
  @override
  double get previewVolume => widget.previewVolume;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await widget.library.load();
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _import() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Аудио',
            extensions: ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'opus'],
          ),
        ],
      );
      if (file == null || !mounted) return;
      setState(() => importing = true);
      await stopPreview();
      final duration = await probe(file.path);
      if (!mounted) return;
      final title = TextEditingController(text: file.name);
      final artist = TextEditingController(), genre = TextEditingController();
      final dialog = DialogRoute<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Импорт музыки'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Название'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: artist,
                  decoration: const InputDecoration(labelText: 'Исполнитель'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: genre,
                  decoration: const InputDecoration(labelText: 'Жанр'),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Импортируй музыку, на использование которой у тебя есть права. '
                  'Локальный файл сам по себе не подтверждает право публиковать видео с этой музыкой.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Импортировать'),
            ),
          ],
        ),
      );
      try {
        final accepted = await Navigator.of(context).push(dialog);
        if (accepted == true) {
          await widget.library.importFile(
            file.path,
            title: title.text,
            artist: artist.text,
            genre: genre.text,
            duration: duration,
          );
        }
      } finally {
        // Controllers live until the route's reverse animation is finished.
        await dialog.completed;
        title.dispose();
        artist.dispose();
        genre.dispose();
      }
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Future<void> _use(MusicTrack track) async {
    try {
      await stopPreview();
      await widget.onUse(track);
      await widget.library.recordUse(track.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Музыка добавлена в проект')),
        );
      }
    } catch (error) {
      if (mounted) _showError(context, error);
    }
    if (mounted) setState(() {});
  }

  Future<void> _favorite(String id) async {
    try {
      await widget.library.toggleFavorite(id);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    var tracks = widget.library.search(
      query,
      genre: genre,
      favoritesOnly: favoritesOnly,
    );
    if (historyOnly) {
      final ids = widget.library.history;
      tracks = tracks.where((t) => ids.contains(t.id)).toList()
        ..sort((a, b) => ids.indexOf(a.id).compareTo(ids.indexOf(b.id)));
    }
    final genres =
        widget.library.tracks
            .map((t) => t.genre)
            .where((g) => g.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('Музыка')),
      body: _pageBody(
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text(MusicSources.jamendoUnavailableReasonRu),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Название, исполнитель или жанр',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() => query = value),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: importing ? null : _import,
                        icon: const Icon(Icons.file_upload_outlined),
                        label: Text(
                          importing ? 'Импорт…' : 'Импортировать музыку',
                        ),
                      ),
                      FilterChip(
                        label: const Text('Избранное'),
                        selected: favoritesOnly,
                        onSelected: (v) => setState(() => favoritesOnly = v),
                      ),
                      FilterChip(
                        label: const Text('История'),
                        selected: historyOnly,
                        onSelected: (v) => setState(() => historyOnly = v),
                      ),
                      if (genres.isNotEmpty)
                        DropdownButton<String>(
                          value: genre,
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Все жанры'),
                            ),
                            ...genres.map(
                              (g) => DropdownMenuItem(value: g, child: Text(g)),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => genre = value ?? ''),
                        ),
                      if (previewPath != null)
                        TextButton.icon(
                          onPressed: stopPreview,
                          icon: const Icon(Icons.stop),
                          label: const Text('Стоп'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (loading || importing) const LinearProgressIndicator(),
            Expanded(
              child: tracks.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Здесь появится твоя музыка. Импортируй аудиофайл или измени условия поиска.',
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: tracks.length,
                      itemBuilder: (context, index) {
                        final track = tracks[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 5,
                          ),
                          child: ExpansionTile(
                            title: Text(track.title),
                            subtitle: Text(
                              [
                                track.artist,
                                track.genre,
                                _duration(track.duration),
                              ].where((s) => s.isNotEmpty).join(' • '),
                            ),
                            leading: IconButton(
                              tooltip: previewPath == track.path
                                  ? 'Остановить'
                                  : 'Прослушать',
                              onPressed: () => preview(track.path),
                              icon: Icon(
                                previewPath == track.path
                                    ? Icons.stop_circle_outlined
                                    : Icons.play_circle_outline,
                              ),
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  12,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SelectableText(
                                      'Лицензия: ${track.license.name}',
                                    ),
                                    if (track.license.attribution.isNotEmpty)
                                      SelectableText(
                                        'Авторство: ${track.license.attribution}',
                                      ),
                                    if (track.license.url != null &&
                                        track.license.url.toString().isNotEmpty)
                                      SelectableText('${track.license.url}'),
                                    if (!track.license.synchronizationAllowed)
                                      const Text(
                                        'Право использования в опубликованном видео необходимо проверить.',
                                      ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        FilledButton.icon(
                                          onPressed: () => _use(track),
                                          icon: const Icon(Icons.add),
                                          label: const Text('В проект'),
                                        ),
                                        TextButton.icon(
                                          onPressed: () => _favorite(track.id),
                                          icon: Icon(
                                            widget.library.favorites.contains(
                                                  track.id,
                                                )
                                                ? Icons.favorite
                                                : Icons.favorite_border,
                                          ),
                                          label: const Text('Избранное'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class SoundLibraryPage extends StatefulWidget {
  final SoundLibrary library;
  final void Function(SoundEffect sound, bool atMarkers) onAdd;
  final String language;
  final double previewVolume;
  const SoundLibraryPage({
    super.key,
    required this.library,
    required this.onAdd,
    this.language = 'ru',
    this.previewVolume = 1,
  });
  @override
  State<SoundLibraryPage> createState() => _SoundLibraryPageState();
}

class _SoundLibraryPageState extends State<SoundLibraryPage>
    with _AudioPreview {
  late final Future<List<SoundEffect>> sounds = widget.library.generate();
  @override
  double get previewVolume => widget.previewVolume;
  Future<void> _add(SoundEffect sound, bool atMarkers) async {
    try {
      await stopPreview();
      widget.onAdd(sound, atMarkers);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              atMarkers
                  ? '${sound.name}: добавлено на маркеры'
                  : '${sound.name}: добавлено на таймлайн',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Звуковые эффекты')),
    body: _pageBody(
      FutureBuilder<List<SoundEffect>>(
        future: sounds,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: SelectableText(
                'Не удалось создать звуки: ${snapshot.error}',
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                '10 оригинальных синтезированных звуков. Добавь акцент в текущую позицию '
                'или на маркеры проекта. Громкость, обрезка и Fade доступны на таймлайне.',
              ),
              const SizedBox(height: 16),
              for (final sound in snapshot.data!)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Прослушать ${sound.name}',
                              onPressed: () => preview(sound.path),
                              icon: Icon(
                                previewPath == sound.path
                                    ? Icons.stop_circle_outlined
                                    : Icons.play_circle_outline,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                sound.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Text('${sound.duration.inMilliseconds} мс'),
                          ],
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: () => _add(sound, false),
                              icon: const Icon(Icons.add),
                              label: const Text('На таймлайн'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _add(sound, true),
                              icon: const Icon(Icons.multitrack_audio),
                              label: const Text('На маркеры'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              const Text(SoundLibrary.licenseNotice),
            ],
          );
        },
      ),
    ),
  );
}

class UpdatesPage extends StatefulWidget {
  final UpdateService service;
  final String currentVersion;
  final UpdatePlatform? platform;
  final Directory? downloadDirectory;
  final Future<void> Function(File)? onOpenDownloaded;
  const UpdatesPage({
    super.key,
    required this.service,
    required this.currentVersion,
    this.platform,
    this.downloadDirectory,
    this.onOpenDownloaded,
  });
  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  UpdateCheck? result;
  bool checking = false, downloading = false, opening = false;
  int received = 0, total = 0;
  File? verified;
  DownloadCancellation? cancellation;
  String? downloadMessage;
  Future<void> _check() async {
    setState(() {
      checking = true;
      downloadMessage = null;
      verified = null;
    });
    final check = await widget.service.check(
      currentVersion: widget.currentVersion,
      platform:
          widget.platform ??
          (Platform.isAndroid
              ? UpdatePlatform.androidArm64
              : UpdatePlatform.windowsX64),
      force: true,
    );
    if (mounted) {
      setState(() {
        result = check;
        checking = false;
      });
    }
  }

  Future<void> _download() async {
    final asset = result?.asset;
    if (asset == null) return;
    try {
      File destination;
      if (Platform.isWindows) {
        final target = await getSaveLocation(
          suggestedName: asset.name,
          acceptedTypeGroups: [
            const XTypeGroup(label: 'Установщик', extensions: ['exe']),
          ],
        );
        if (target == null || !mounted) return;
        destination = File(target.path);
      } else {
        final directory =
            widget.downloadDirectory ??
            Directory('${widget.service.cacheFile.parent.path}/updates');
        destination = File('${directory.path}/${asset.name}');
      }
      cancellation = DownloadCancellation();
      setState(() {
        downloading = true;
        verified = null;
        downloadMessage = null;
        received = 0;
        total = asset.size;
      });
      final file = await widget.service.download(
        asset,
        destination,
        cancellation: cancellation,
        onProgress: (count, size) {
          if (mounted) {
            setState(() {
              received = count;
              total = size;
            });
          }
        },
      );
      if (mounted) {
        setState(() {
          verified = file;
          downloadMessage = 'SHA-256 проверен. Установщик сохранён.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => downloadMessage = 'Загрузка не завершена: $error');
      }
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  Future<void> _open() async {
    final file = verified, open = widget.onOpenDownloaded;
    if (file == null || open == null) return;
    setState(() => opening = true);
    try {
      await open(file);
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  void dispose() {
    cancellation?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Обновления')),
    body: _pageBody(
      ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Tiger Video Edit ${widget.currentVersion}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          const Text(
            'Публичные обновления GitHub. Проверка не требует входа в аккаунт.',
          ),
          const SizedBox(height: 12),
          SelectableText(widget.service.configurationMessage),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: checking || downloading ? null : _check,
              icon: const Icon(Icons.refresh),
              label: Text(checking ? 'Проверяем…' : 'Проверить обновления'),
            ),
          ),
          if (checking)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: LinearProgressIndicator(),
            ),
          if (result != null) ...[
            const SizedBox(height: 20),
            Text(
              _status(result!),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (result!.status != UpdateStatus.available &&
                result!.message.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(result!.message),
            ],
            if (result!.release != null) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                title: const Text('Что нового?'),
                childrenPadding: const EdgeInsets.all(16),
                children: [
                  SelectableText(
                    result!.release!.notes.isEmpty
                        ? 'Описание релиза не опубликовано.'
                        : result!.release!.notes,
                  ),
                ],
              ),
              SelectableText('${result!.release!.pageUrl}'),
            ],
            if (result!.asset != null && verified == null) ...[
              const SizedBox(height: 12),
              Text(
                '${result!.asset!.name} • ${(result!.asset!.size / 1048576).toStringAsFixed(1)} МБ',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: downloading ? null : _download,
                    icon: const Icon(Icons.download),
                    label: const Text('Скачать обновление'),
                  ),
                  TextButton(
                    onPressed: downloading
                        ? null
                        : () => setState(() => result = null),
                    child: const Text('Позже'),
                  ),
                ],
              ),
            ],
          ],
          if (downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: total > 0 ? received / total : null),
            Text(
              '${(received / 1048576).toStringAsFixed(1)} / ${(total / 1048576).toStringAsFixed(1)} МБ',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => cancellation?.cancel(),
                child: const Text('Отменить загрузку'),
              ),
            ),
          ],
          if (downloadMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SelectableText(downloadMessage!),
            ),
          if (verified != null) ...[
            const SizedBox(height: 8),
            SelectableText(verified!.path),
            const SizedBox(height: 12),
            const Text(
              'Установка требует твоего подтверждения в системном установщике.',
            ),
            if (widget.onOpenDownloaded != null)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: opening ? null : _open,
                  icon: const Icon(Icons.install_desktop),
                  label: const Text('Открыть системный установщик'),
                ),
              ),
          ],
        ],
      ),
    ),
  );

  String _status(UpdateCheck check) => switch (check.status) {
    UpdateStatus.available =>
      'Доступна новая версия Tiger Video Edit ${check.release!.version}',
    UpdateStatus.upToDate => 'Установлена актуальная версия',
    UpdateStatus.notConfigured => 'Публичный релиз пока не настроен',
    UpdateStatus.noCompatibleAsset =>
      'Совместимый проверяемый установщик не опубликован',
    UpdateStatus.offline => 'Нет соединения с GitHub',
    UpdateStatus.timedOut => 'Превышено время ожидания',
    UpdateStatus.rateLimited => 'Достигнут лимит GitHub. Проверь позже.',
    UpdateStatus.invalidResponse => 'Не удалось проверить данные релиза',
    UpdateStatus.serverError => 'Публичный релиз пока недоступен',
  };
}
