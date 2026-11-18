import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'app_settings.dart';
import 'jamendo.dart';
import 'music_library.dart';

class JamendoMusicPage extends StatefulWidget {
  final File configFile;
  final Directory workingDirectory;
  final Future<void> Function(MusicTrack track) onUse;
  final JamendoProvider? provider;
  final Player Function()? playerFactory;
  final double volume;
  const JamendoMusicPage({
    super.key,
    required this.configFile,
    required this.workingDirectory,
    required this.onUse,
    this.provider,
    this.playerFactory,
    this.volume = 1,
  });
  @override
  State<JamendoMusicPage> createState() => _JamendoMusicPageState();
}

class _JamendoMusicPageState extends State<JamendoMusicPage> {
  final query = TextEditingController();
  late JamendoProvider provider =
      widget.provider ??
      JamendoProvider(
        clientId: const String.fromEnvironment('TVE_JAMENDO_CLIENT_ID'),
        editingApproved: const bool.fromEnvironment(
          'TVE_JAMENDO_EDITING_APPROVED',
        ),
      );
  List<OnlineMusicTrack> tracks = [];
  bool loading = false, hasMore = false, searched = false, reusableOnly = false;
  bool selecting = false,
      committing = false,
      cancelled = false,
      previewLoading = false,
      configuring = true;
  int page = 1, generation = 0, downloadedBytes = 0;
  String genre = '', submitted = '', submittedGenre = '', error = '';
  String? playing;
  Player? player;
  JamendoPreview? relay;
  StreamSubscription<String>? playerErrors;
  StreamSubscription<bool>? playerCompleted;
  StreamSubscription<Duration>? playerPosition;
  Completer<void>? ready;
  int previewGeneration = 0;
  final favorites = <String, OnlineMusicTrack>{};
  final history = <String, OnlineMusicTrack>{};
  String collection = 'search';
  Future<void> pendingSave = Future.value();
  File get savedFile => File('${widget.configFile.path}.library.json');
  static const genres = {
    '': 'Все жанры',
    'electronic': 'Электроника',
    'hiphop': 'Хип-хоп',
    'rock': 'Рок',
    'pop': 'Поп',
    'classical': 'Классика',
    'jazz': 'Джаз',
    'soundtrack': 'Саундтрек',
    'relaxation': 'Спокойная музыка',
  };

  @override
  void initState() {
    super.initState();
    unawaited(_loadConfig());
  }

  Future<void> _loadConfig() async {
    try {
      if (widget.provider == null &&
          await widget.configFile.exists() &&
          await widget.configFile.length() < 4096) {
        final json = jsonDecode(await widget.configFile.readAsString()) as Map;
        final id = json['clientId'];
        if (id is String && id.isNotEmpty) {
          provider = JamendoProvider(
            clientId: id,
            editingApproved: provider.editingApproved,
          );
        }
      }
    } catch (_) {
      /* A malformed local connection never prevents local editing. */
    }
    try {
      if (await savedFile.exists() &&
          await savedFile.length() < 2 * 1024 * 1024) {
        final saved = jsonDecode(await savedFile.readAsString()) as Map;
        for (final (key, target) in [
          ('favorites', favorites),
          ('history', history),
        ]) {
          for (final entry in (saved[key] as List? ?? []).take(200)) {
            final track = OnlineMusicTrack.fromJson(
              Map<String, dynamic>.from(entry as Map),
            );
            if (JamendoProvider.safeAudio(track.previewUrl)) {
              target[track.id] = track;
            }
          }
        }
      }
    } catch (_) {
      /* Saved titles never block online search. */
    }
    if (mounted) setState(() => configuring = false);
  }

  Future<void> _saveCollections() {
    final bytes = utf8.encode(
      jsonEncode({
        'favorites': favorites.values.map((t) => t.toJson()).toList(),
        'history': history.values.map((t) => t.toJson()).toList(),
      }),
    );
    final file = savedFile;
    final task = pendingSave.then((_) => atomicWriteBytes(file, bytes));
    pendingSave = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  Future<void> _favorite(OnlineMusicTrack track) async {
    final old = Map<String, OnlineMusicTrack>.from(favorites);
    setState(() {
      if (favorites.containsKey(track.id)) {
        favorites.remove(track.id);
      } else if (favorites.length < 200) {
        favorites[track.id] = track;
      }
    });
    try {
      await _saveCollections();
    } catch (_) {
      if (mounted) {
        setState(() {
          favorites
            ..clear()
            ..addAll(old);
        });
      }
      _error('Не удалось сохранить избранное.');
    }
  }

  Future<void> _remember(OnlineMusicTrack track) async {
    history.remove(track.id);
    final previous = history.values.toList();
    history
      ..clear()
      ..[track.id] = track;
    for (final item in previous.take(49)) {
      history[item.id] = item;
    }
    try {
      await _saveCollections();
    } catch (_) {
      _error('Не удалось сохранить историю прослушивания.');
    }
  }

  void _error(String value) {
    if (mounted) setState(() => error = value);
  }

  Future<void> _connect() async {
    final controller = TextEditingController(text: provider.clientId);
    final route = DialogRoute<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Подключить Jamendo'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Client ID из Jamendo Developer Portal. Client Secret не нужен. Идентификатор сохраняется только на этом устройстве.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'Client ID'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    try {
      final id = await Navigator.of(context).push(route);
      if (id == null || !mounted) return;
      final next = JamendoProvider(
        clientId: id,
        editingApproved: provider.editingApproved,
      );
      if (next.unavailableReason != null) {
        _error(
          'Проверь Client ID: нужны 4–128 латинских букв, цифр, «-» или «_».',
        );
        return;
      }
      try {
        await atomicWriteBytes(
          widget.configFile,
          utf8.encode(jsonEncode({'clientId': id})),
        );
        if (!mounted) return;
        setState(() => provider = next);
        _error('');
      } catch (_) {
        _error('Не удалось сохранить настройки Jamendo.');
      }
    } finally {
      await route.completed;
      controller.dispose();
    }
  }

  Future<void> _search({int nextPage = 1, bool submit = false}) async {
    if (loading || selecting || configuring) return;
    final request = ++generation;
    final requestedQuery = submit ? query.text.trim() : submitted;
    final requestedGenre = submit ? genre : submittedGenre;
    collection = 'search';
    setState(() {
      loading = true;
      error = '';
    });
    try {
      await _stop();
      final result = await provider.searchPage(
        requestedQuery,
        genre: requestedGenre,
        page: nextPage,
      );
      if (!mounted || request != generation) return;
      setState(() {
        tracks = result.tracks;
        hasMore = result.hasMore;
        page = nextPage;
        submitted = requestedQuery;
        submittedGenre = requestedGenre;
        searched = true;
      });
    } catch (e) {
      if (mounted && request == generation) setState(() => hasMore = false);
      if (request == generation) {
        _error(
          e is JamendoException ? e.message : 'Поиск Jamendo не выполнен.',
        );
      }
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  Future<void> _stop({bool keepLoading = false}) async {
    final stopToken = ++previewGeneration;
    final pending = ready;
    ready = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(
        const JamendoException('Прослушивание остановлено.'),
      );
    }
    final oldRelay = relay;
    relay = null;
    final old = player;
    player = null;
    final oldErrors = playerErrors;
    playerErrors = null;
    final oldCompleted = playerCompleted;
    playerCompleted = null;
    final oldPosition = playerPosition;
    playerPosition = null;
    await oldRelay?.close();
    await oldErrors?.cancel();
    await oldCompleted?.cancel();
    await oldPosition?.cancel();
    try {
      await old?.dispose();
    } catch (_) {
      /* Stop also resets UI after a lost stream. */
    }
    if (mounted && stopToken == previewGeneration) {
      setState(() {
        playing = null;
        if (!keepLoading) previewLoading = false;
      });
    }
  }

  Future<void> _preview(OnlineMusicTrack track) async {
    if (previewLoading || selecting) return;
    if (playing == track.id) {
      await _stop();
      return;
    }
    setState(() {
      previewLoading = true;
      error = '';
      playing = null;
    });
    var token = previewGeneration;
    try {
      final stopped = _stop(keepLoading: true);
      token = previewGeneration;
      await stopped;
      if (!mounted || token != previewGeneration) return;
      final activePlayer =
          widget.playerFactory?.call() ??
          Player(
            configuration: const PlayerConfiguration(
              protocolWhitelist: ['http', 'tcp'],
            ),
          );
      player = activePlayer;
      final playback = Completer<void>();
      ready = playback;
      unawaited(playback.future.catchError((Object _) {}));
      playerErrors = activePlayer.stream.error.listen((_) {
        if (token != previewGeneration) return;
        _error(
          'Не удалось воспроизвести трек. Попробуй другой или проверь интернет.',
        );
        unawaited(_stop());
      });
      playerCompleted = activePlayer.stream.completed.listen((ended) {
        if (ended && token == previewGeneration) unawaited(_stop());
      });
      playerPosition = activePlayer.stream.position.listen((position) {
        if (token == previewGeneration &&
            position > Duration.zero &&
            !playback.isCompleted) {
          playback.complete();
        }
      });
      final native = activePlayer.platform;
      if (native is NativePlayer) {
        await native.setProperty('cache-on-disk', 'no');
        await native.setProperty('demuxer', 'lavf');
        await native.setProperty('demuxer-lavf-format', 'mp3');
        if (await native.getProperty('options/cache-on-disk') != 'no' ||
            await native.getProperty('options/demuxer-lavf-format') != 'mp3' ||
            await native.getProperty('options/demuxer') != 'lavf') {
          throw const JamendoException(
            'Проигрыватель не поддерживает защищённое прослушивание MP3.',
          );
        }
      }
      final handle = await provider.openPreview(track);
      if (!mounted || token != previewGeneration) {
        await handle.close();
        return;
      }
      relay = handle;
      final currentTrack = handle.track;
      setState(() {
        tracks = tracks
            .map((t) => t.id == currentTrack.id ? currentTrack : t)
            .toList();
        if (favorites.containsKey(currentTrack.id)) {
          favorites[currentTrack.id] = currentTrack;
        }
      });
      await activePlayer.setVolume(widget.volume.clamp(0, 1) * 100);
      await activePlayer
          .open(Media(handle.uri.toString()))
          .timeout(const Duration(seconds: 25));
      await playback.future.timeout(const Duration(seconds: 25));
      if (mounted && token == previewGeneration) {
        setState(() => playing = track.id);
        await _remember(currentTrack);
      }
    } catch (problem) {
      if (mounted && token == previewGeneration) {
        _error(
          problem is JamendoException
              ? problem.message
              : 'Не удалось воспроизвести трек. Проверь интернет.',
        );
        await _stop();
      }
    } finally {
      if (mounted && token == previewGeneration) {
        setState(() => previewLoading = false);
      }
    }
  }

  Future<void> _use(OnlineMusicTrack track) async {
    if (selecting || !track.canDownload || !provider.editingApproved) return;
    setState(() {
      selecting = true;
      cancelled = false;
      downloadedBytes = 0;
      error = '';
    });
    File? temporary;
    try {
      await _stop();
      final (file, fresh) = await provider.prepareForEditing(
        track,
        widget.workingDirectory,
        cancelled: () => cancelled || !mounted,
        onProgress: (count) {
          if (mounted) setState(() => downloadedBytes = count);
        },
      );
      temporary = file;
      if (!mounted || cancelled) return;
      setState(() => committing = true);
      await widget.onUse(
        MusicTrack(
          id: 'jamendo:${fresh.id}',
          providerId: 'jamendo',
          title: fresh.title,
          artist: fresh.artist,
          genre: fresh.genre,
          path: file.path,
          duration: fresh.duration,
          license: fresh.license,
          importedAt: DateTime.now(),
        ),
      );
    } catch (e) {
      _error(
        e is JamendoException
            ? e.message
            : 'Не удалось добавить музыку в проект.',
      );
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
      if (mounted) {
        setState(() {
          selecting = false;
          committing = false;
        });
      }
    }
  }

  String _reason(OnlineMusicTrack track) {
    if (!track.license.downloadAllowed) {
      return 'Автор разрешил только прослушивание.';
    }
    if (!track.license.synchronizationAllowed) {
      return 'Для монтажа здесь поддерживаются только CC BY и CC0. Этот трек можно слушать.';
    }
    if (!provider.editingApproved) {
      return 'Лицензия подходит. Добавление в монтаж ожидает подтверждения Jamendo для нашего приложения.';
    }
    return 'Файл будет использован как материал проекта, без добавления в офлайн-каталог.';
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Скопировано')));
    }
  }

  @override
  void dispose() {
    generation++;
    cancelled = true;
    query.dispose();
    unawaited(_stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final candidates = collection == 'favorites'
        ? favorites.values
        : collection == 'history'
        ? history.values
        : tracks;
    final visible = candidates
        .where(
          (t) =>
              !reusableOnly ||
              (t.license.synchronizationAllowed && t.license.downloadAllowed),
        )
        .toList();
    return PopScope(
      canPop: !committing,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Онлайн • Jamendo'),
          actions: [
            IconButton(
              tooltip: 'Подключение Jamendo',
              onPressed: selecting || loading ? null : _connect,
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        provider.unavailableReason ?? 'Поиск и прослушивание онлайн. Локальная музыка остаётся в разделе «Музыка».',
                      ),
                      if (provider.unavailableReason != null)
                        TextButton(
                          onPressed: configuring ? null : _connect,
                          child: const Text('Подключить Jamendo'),
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: query,
                        onSubmitted: (_) => _search(submit: true),
                        maxLength: 200,
                        decoration: const InputDecoration(
                          labelText: 'Название, исполнитель или настроение',
                          prefixIcon: Icon(Icons.search),
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          DropdownButton<String>(
                            value: genre,
                            items: genres.entries
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e.key,
                                    child: Text(e.value),
                                  ),
                                )
                                .toList(),
                            onChanged: loading || selecting
                                ? null
                                : (value) =>
                                      setState(() => genre = value ?? ''),
                          ),
                          FilledButton.icon(
                            onPressed:
                                loading ||
                                    selecting ||
                                    configuring ||
                                    provider.unavailableReason != null
                                ? null
                                : () => _search(submit: true),
                            icon: const Icon(Icons.search),
                            label: const Text('Найти'),
                          ),
                          FilterChip(
                            label: const Text('CC BY / CC0'),
                            selected: reusableOnly,
                            onSelected: (value) =>
                                setState(() => reusableOnly = value),
                          ),
                          FilterChip(
                            label: const Text('Избранное'),
                            selected: collection == 'favorites',
                            onSelected: (v) => setState(
                              () => collection = v ? 'favorites' : 'search',
                            ),
                          ),
                          FilterChip(
                            label: const Text('История'),
                            selected: collection == 'history',
                            onSelected: (v) => setState(
                              () => collection = v ? 'history' : 'search',
                            ),
                          ),
                          if (playing != null || previewLoading)
                            TextButton.icon(
                              onPressed: _stop,
                              icon: const Icon(Icons.stop),
                              label: const Text('Стоп'),
                            ),
                        ],
                      ),
                      if (error.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            error,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (loading || configuring || selecting)
                  const LinearProgressIndicator(),
                if (selecting)
                  ListTile(
                    title: Text(
                      committing
                          ? 'Добавление в проект…'
                          : cancelled
                          ? 'Отмена загрузки…'
                          : 'Подготовка трека: ${(downloadedBytes / 1024).round()} КБ',
                    ),
                    trailing: TextButton(
                      onPressed: committing || cancelled
                          ? null
                          : () => setState(() => cancelled = true),
                      child: const Text('Отменить'),
                    ),
                  ),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              searched
                                  ? 'По этим условиям ничего не найдено. Измени запрос, фильтр или страницу.'
                                  : 'Введи запрос и нажми «Найти». До этого приложение не обращается к Jamendo.',
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final t = visible[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 5,
                              ),
                              child: ExpansionTile(
                                title: Text(t.title),
                                trailing: IconButton(
                                  tooltip: 'В избранное',
                                  onPressed: () => _favorite(t),
                                  icon: Icon(
                                    favorites.containsKey(t.id)
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                  ),
                                ),
                                subtitle: Text(
                                  '${t.artist} • ${t.duration.inMinutes}:${(t.duration.inSeconds % 60).toString().padLeft(2, '0')} • ${t.license.name}',
                                ),
                                leading: IconButton(
                                  tooltip: playing == t.id
                                      ? 'Остановить'
                                      : 'Прослушать',
                                  onPressed: previewLoading || selecting
                                      ? null
                                      : () => _preview(t),
                                  icon: Icon(
                                    playing == t.id
                                        ? Icons.stop_circle_outlined
                                        : Icons.play_circle_outline,
                                  ),
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (t.genre.isNotEmpty) Text(t.genre),
                                        SelectableText(t.license.attribution),
                                        const SizedBox(height: 8),
                                        Text(_reason(t)),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            FilledButton.icon(
                                              onPressed:
                                                  selecting ||
                                                      !provider
                                                          .editingApproved ||
                                                      !t.canDownload
                                                  ? null
                                                  : () => _use(t),
                                              icon: const Icon(Icons.add),
                                              label: const Text('В проект'),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  _copy(t.license.attribution),
                                              child: const Text(
                                                'Копировать авторство',
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  _copy(t.sourceUrl.toString()),
                                              child: const Text(
                                                'Копировать ссылку',
                                              ),
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
                if (searched && collection == 'search')
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: 'Предыдущая страница',
                          onPressed: loading || selecting || page <= 1
                              ? null
                              : () => _search(nextPage: page - 1),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text('Страница $page'),
                        IconButton(
                          tooltip: 'Следующая страница',
                          onPressed: loading || selecting || !hasMore
                              ? null
                              : () => _search(nextPage: page + 1),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
