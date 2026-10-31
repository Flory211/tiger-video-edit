# Покрытие ТЗ Tiger Video Edit 3.0

Дата ревью: 2026-10-31 — 2026-11-01. Основание: [полное ТЗ](V3_SPEC_RU.md).

Это проверка исходного кода и имеющихся тестов во время интеграции. Она не
подтверждает готовность релиза. Ветка меняется параллельно; найденные дефекты
переданы ведущему разработчику сразу. После исправлений нужны свежие проверки.
Наличие workflow, тестового файла или APK не означает успешный прогон в GitHub
или на Android-устройстве.

## Что подтверждено отдельным прогоном

В этой рабочей сессии команда
`flutter test --no-pub test/v3_services_test.dart test/service_pages_test.dart test/workspace_shell_test.dart`
завершилась результатом **20/20**. Анализ семи новых сервисных/UI-файлов и трёх
соответствующих тестов завершился без замечаний. Это проверяет перечисленные
сервисы и навигацию, а не всё приложение после последующих изменений.

После исправлений отдельная команда
`flutter test --no-pub test/dashboard_test.dart test/v3_editor_regression_test.dart`
дала **13/13**: light/system-theme и contrast, телефонный dashboard, selection
new/open, немутирующее открытие, legacy/empty copy-paste, оба порядка импорта для
pending template, перенос marker-rules, последовательные settings, экспортные
defaults и SFX duplicate/end/limit. Эти тесты используют временную библиотеку,
fake audio player и оригинальные демоматериалы, не пользовательские файлы.

Финальный объединённый прогон этих пяти файлов (services, service pages,
workspace shell, dashboard, editor regressions) дал **33/33**. Отдельный
`flutter analyze --no-pub lib/dashboard.dart test/dashboard_test.dart test/v3_editor_regression_test.dart`
после последнего форматирования — **No issues found**. Это не подменяет общий
`flutter test` и нативные/device/CI gates.

В `DEVELOPMENT_STATUS.md` результаты 45/45 и прежние нативные прогоны относятся
к исходной версии 2.0. Их нельзя переносить на всю версию 3.0. Текущий общий
результат нужно записать после окончательной интеграции.

## Критерии и доказательства

| Критерий ТЗ | Код / проверяемые доказательства | Состояние и остатки |
|---|---|---|
| Существующее приложение расширено, данные сохранены | `lib/editor.dart`, `storage.dart`, `model.dart`; `test/editor_test.dart`, `storage_test.dart`, `v2_model_test.dart` | Архитектура v2 сохранена. Старые функции продолжают использоваться, не заменены заглушками. Общий регрессионный прогон после интеграции обязателен. |
| Название, версия, Windows x64 / Android ARM64, `.tve` | `lib/app_info.dart`, `main.dart`, `pubspec.yaml`, `installer/windows.iss`, Android Gradle/manifest | Идентичность обновляется в существующем приложении. Проверить метаданные именно свежих бинарников, а не старого пакета. |
| Открытие схем v1/v2 без изменения оригинала | `Project.fromJson`, `ProjectStore.read`; `test/v3_effects_test.dart` — проверка немутирующей миграции; `editor_test.dart` — `.leos` сохраняется в соседний `.tve` | Чтение не пишет файл; legacy-карта эффектов сохраняется. При ручном сохранении старого `.tve` схема становится v3, предыдущая версия остаётся в `.bak`; отдельная копия исходника полезна для приёмки. |
| Новая схема проекта | `model.dart`, `effects.dart`, `audio_clip.dart`; round-trip и validation в `v3_effects_test.dart`, `audio_clip_test.dart` | Стеки, ключи, глобальные эффекты, аудио- и визуальные клипы, экспортные параметры сериализуются. Выбранный/ожидающий шаблон как отдельное состояние проекта не сериализуется. |
| Пути дополнительных медиа и поиск отсутствующих файлов | `ProjectStore.read/missing` в `storage.dart`, `test/storage_test.dart` | Разрешаются относительные пути основного аудио, изображений, SFX и визуальных слоёв. Нужен общий сценарий переноса/восстановления проекта. |
| Git и история | Локальный Git, `.gitignore`, план `V3_IMPLEMENTATION_PLAN.md` | Локальная работа подготовлена. Публикация исходников/истории требует отдельного подтверждения владельца и финального просмотра staged/history. |
| Публичный репозиторий | `workspace_shell.dart` использует проверенный профиль `GushinetsN` и запланированный `tiger-video-edit` | Публичный репозиторий и remote/release не созданы этими сервисами. Не выдавать выбранное имя за опубликованный адрес. |
| Независимые сборки GitHub Actions | `.github/workflows/windows.yml`, `android.yml`; `tools/bootstrap-ci-windows.ps1`, `verify-windows-payload.ps1`, `test_release_tools.py` | YAML и локальные вспомогательные проверки подготовлены. Успех GitHub runner не подтверждён. В CI нужен чистый прогон обеих платформ. |
| Проверяемые Releases | `.github/workflows/release.yml`, `tools/release_integrity.py`, `scan_secrets.py`, `docs/CI_RELEASE.md` | Публикация имеет внешние approval/license/device gates; нужны production signing secrets. Проверить наличие точного `docs/RELEASE_NOTES_3.0.md`, используемого workflow. Ничего не опубликовано. |
| Проверка обновлений без GitHub-логина | `update_service.dart`, `workspace_shell.dart`; `v3_services_test.dart` | Semantic versioning, стабильные релизы, выбор совместимого asset, кэш 24 ч, manual force, offline/timeout/rate/HTTP-ошибки проверены fake-транспортом. Реальный сервер/реальный опубликованный asset не проверены; 404 честно показывает отсутствие релиза. |
| Безопасная загрузка и системная установка | `UpdateService.download`, `UpdatesPage`; Android `MainActivity.kt`, manifest, `res/xml/update_paths.xml` | SHA-256, лимиты, HTTPS/репозиторий/redirect allowlist, staging, cancel и сохранение прежнего файла проверены локально. Запуск только отдельной кнопкой. FileProvider ограничен `filesDir/updates`; Android source permission требует повторного нажатия. Реальная установка/upgrade pending. |
| Новое главное меню и возврат к монтажу | `dashboard.dart`, `workspace_shell.dart`, `service_pages.dart`; `dashboard_test.dart`, `workspace_shell_test.dart` | Действительные create/continue/projects/templates/music/sounds/updates/settings. Постоянный IndexedStack сохраняет EditorScreen. Проверены телефонный размер и возврат к несохранённому сеансу. |
| Reduced motion / доступность | `AppSettings.animationsAllowed`, dashboard, effect preview, root theme | Настройки и системное уменьшение движения участвуют в анимациях. Требуется финальная проверка всех route/панельных анимаций после theme-интеграции. |
| Глобальные эффекты на всей композиции | `GlobalAdjustmentLayer`, `compositor.paintFrame`, `V3Panel`; `compositor_test.dart`, `v3_effects_test.dart`, `v3_panel_test.dart` | Всегда / каждый маркер / выбранные / смена кадра / диапазон, enable/bypass и настройки реализованы. Глобальная обработка идёт после визуальных слоёв и текста. Нативный экспорт всей композиции проверяется отдельно. |
| 29 именованных стилей | `effect_recipes.dart`, `effects.dart`, `compositor.dart`, `docs/V3_EFFECTS.md` | Это 29 редактируемых комбинаций ограниченного набора Canvas-примитивов, а не 29 независимых физических/нейросетевых алгоритмов. Pixel Stretch, VHS, Lens Flare — стилизованные комбинации. UI не должен обещать больше. |
| Поиск/популярные/недавние/избранные/пресеты | `showEffectLibrary`, `v2_panel.dart`, `SettingsStore`; `v3_panel_test.dart` | Реальные категории, поиск и сохранение настроек. Старые v2-пресеты используют отдельную legacy-карту; нужна проверка совместимости команды копирования. |
| Плавные ключевые анимации и график | `AnimationTrack`, `Keyframe`, `v3_panel.dart`; interpolation и form-тесты | Есть x/y/scale/rotation/opacity, числовые ключи, график, linear/easeInOut/Bezier/back/bounce/elastic. Отдельные ease-in/ease-out пункты отсутствуют; соответствующие формы можно задать Bezier. Parallax — ручное сочетание слоёв, не автоматическая оценка глубины. |
| Реальные переходы | `compositor.dart`, decoder previous-frame paths в `main.dart` / `platform_media.dart`; pixel-тесты | Используется предыдущий источник. Глобальный переход не сохраняет полную прошлую композицию с её историческими надписями/всеми слоями. Соответствие preview/export при FPS и смешанном видео требует финального прогона. |
| Локальная музыка офлайн | `music_library.dart`, `MusicLibraryPage`; `v3_services_test.dart`, `service_pages_test.dart` | Копирование файла, реальная длительность из media-kit, поиск, жанры, избранное, история использования, сведения об авторстве/правах. Удаление исходника не ломает копию. История использования не выдаётся за журнал онлайн-скачиваний. |
| Законная онлайн-музыка | `OnlineMusicProvider`, `MusicLicense`, `MusicSources`, `docs/V3_SERVICES.md` с официальными источниками | Включён разрешённый ТЗ fallback: работающая локальная библиотека и расширяемый интерфейс. Живого каталога нет. Jamendo agreement/client-ID и права offline/download/synchronization не получены; тестовый client ID и фиктивные результаты не используются. |
| 10 коротких оригинальных SFX | `sound_library.dart`, `SoundLibraryPage`; WAV/determinism-тест и телефонные callbacks | Реальные собственные WAV, 80–1600 мс, прослушивание и добавление в позицию/на маркеры. Лицензия публичного распространения оригинальных ассетов не выбрана за владельца. |
| SFX move/trim/copy/delete/volume/fades | `audio_clip.dart`, `timeline_tracks.dart`, Editor audio methods; `audio_clip_test.dart`, `audio_mixer_test.dart`, `v3_editor_regression_test.dart` | Числовое редактирование, drag, дорожка, source offset, gain/fades есть. Исправлены и проверены duplicate на конце проекта и обработка лимита 1024. |
| Дополнительные визуальные/аудиодорожки | `VisualClip`, `TimelineTracks`, `MediaFrameSource`, `paintFrame`, `prepareAudioMix` | Визуальные слои накладываются по track/opacity; аудио суммируется offline. Model теперь ограничивает 16 активных перекрывающихся SFX и 16 visual layers: старое молчаливое отбрасывание лишнего preview не считается поддержкой неограниченного числа слоёв. Нужны UI-сообщение и нагрузочная приёмка этого предела. |
| Групповое выделение и массовые эффекты | `Editor.selectedImages`, `_targets`, `applyEffectRecipe`, `pasteEffects`, UI Ctrl-click/Ctrl+A; `v3_editor_regression_test.dart` | Реализовано для изображений. Нельзя объявлять произвольное групповое редактирование всех типов клипов. Проверены reset new/open, legacy-copy, duration и empty-paste clearing. Перестановки/многовыбор всех типов клипов требуют отдельной проверки. |
| Привязка, зум, Undo/Redo | `snapTime`, `TimelineTracks`, main timeline, `ProjectHistory`, Editor history sync | Маркеры/кандидаты битов, прокрутка/зум и история есть. `snapToMarkers` и расположение панелей не сохраняются как полноценный workspace layout. Нужны mouse/touch/device drag-проверки. |
| Шаблоны: save/import/export/copy/rename/delete | `edit_templates.dart`, `template_page.dart`, `Editor.applyTemplate`; `template_page_test.dart`, `v3_editor_regression_test.dart` | Собственные JSON-шаблоны не копируют пути пользовательского медиа. Built-in защищены UI от удаления. Перенос global selected-marker правил исправлен очисткой конкретных source IDs и проверен при новой beat-сетке. |
| Auto Edit: BPM/атаки/маркеры/профили | `beat.dart`, `analyzeBeats`, `applyTemplate`, `builtinEditTemplates`, `v2_panel.dart` | Настоящий offline-анализ и шесть именованных профилей с разными recipes/beatStep. Молчание не подменяется выдуманной сеткой. Автоматические SFX-правила в профилях не реализованы; ручное «на маркеры» отдельно. |
| Шаблон до импорта медиа | `pendingTemplate`, `useAudioPath`, `useMediaPaths`; `v3_editor_regression_test.dart` | После замечания добавлено автоматическое применение в обоих порядках импорта и reset new/open; оба сценария прошли. Ожидающий шаблон пока не переживает сохранение/reopen. |
| Настройки приложения реально действуют | `app_settings.dart`, `SettingsPage`, Editor settings notifier, `main.dart`, export adapter | Поддерживаемые choices сужены до 24/30/60 FPS и 480/720/1080p. Проверены сохранение последнего settings и defaults нового проекта. System/light/dark dashboard и контраст прошли. Preview quality/FPS связаны кодом; нужна нативная приёмка. Android quality передаётся через videoBitrate/Media3 encoder settings, Windows использует CRF. Отличие всех уровней качества и результат на устройстве нужно подтвердить. Русский есть; полного English UI нет. |
| MP4 действительно включает v3 эффекты/слои/звук | `VideoExporter`, `paintFrame`, `prepareAudioMix`; `native_test/integration_test/v3_export_test.dart` | Native-тест написан: H.264/AAC, 24 FPS, trim, global flash, overlay, caption glyphs, frame MAE, SFX и cancel. Здесь успешный запуск этого нового нативного теста не утверждается только по наличию файла; его результат нужно записать отдельно. |
| Экспорт и обычное редактирование без сети | Локальные декодеры/FFmpeg/Media3, библиотека и Canvas | Сеть не требуется для основной работы. Нет DRM-обхода. Бандлинг runtime проверяется отдельным payload-тестом; clean-machine/device остаются gates. |
| Подтверждение ухода/закрытия | `unsaved.dart`, `WorkspaceShell`, root Windows close handler | Save/cancel-save и keep-unsaved-home проверены shell-тестами. Android back/system installer и настоящий WM_CLOSE требуют нативной проверки. Кнопка отмены экспорта также должна сохранять прежний destination на финальном staging. |
| Производительность и ресурсы | Ограниченный image-cache, decoder frame sources, disk PCM mix + isolate, disposal paths | Большое видео не читается целиком в RAM. Animated export создаёт PNG каждого кадра на диск: нужна проверка длинного проекта/места на диске. Аппаратное ускорение Canvas/MediaCodec не означает доказанный real-time для всех стеков. |

## Результат замечаний и исправлений

Все замечания передавались сразу; приложение исправлял владелец соответствующих
файлов. Регрессионный файл добавлен независимо от реализации.

| Замечание | Проверенный результат |
|---|---|
| Cancel/rollback final Windows export | Код теперь повторно проверяет cancel после copy, выполняет короткий синхронный commit с rollback и удаляет pending. Статически подтверждено; нативный fault/cancel-прогон отдельно. |
| Старое групповое выделение при new/open | Оба regression-теста прошли; исходный `.tve` при open остался побайтно неизменным. |
| Legacy effect copy и empty-paste | Пройдены отдельные проверки переноса карты+duration и очистки стека пустым clipboard. |
| Concrete markerIds в переиспользуемом шаблоне | Проверен перенос на новую beat-сетку без source marker IDs, `Project.validate` проходит. |
| Pending template только показывал обещание | Сначала тест был красным для images→audio; после исправления обе последовательности прошли. |
| SFX duplicate за концом и у лимита | Проверены слышимый overlap внутри trim, valid end и сохранение 1024 существующих клипов без необработанного исключения. |
| Несогласованные settings / FPS30 / system colors | Choices приведены к model, defaults и ordered-save проверены. Light/system dashboard контраст до исправления был ~1.03:1; после palette-правки тест требует ≥4.5:1 и проходит. Нативные FPS/quality adapter проверки отдельно. |
| Параллельные SettingsStore | Editor теперь хранит один store; rapid last-choice regression проходит. |
| Больше 16 одновременных SFX | Добавлен общий concurrency-limit в validation; это явное ограничение, а не обещание произвольного числа дорожек. |

Android quality→bitrate policy уже передаётся Dart→Media3 encoder settings;
нужна сборка/приёмка и проверка, что high/max действительно различаются.
Последними дополнительно переданы: проверка `updateNotifications` в момент
показа отложенного уведомления и отсутствующий release-notes файл.
Их окончательное состояние следует подтвердить перед общим финальным прогоном.

## Обязательные внешние gates

- Подтверждение владельца на публичные файлы/историю, название репозитория и
  лицензионное решение. Имеющийся `LICENSE` содержит GPLv3 и сохранён; это не новое
  согласование лицензии и не доказательство выполнения обязательств по точным
  FFmpeg/libmpv-сборкам. См. `PUBLICATION_REVIEW.md` и `THIRD_PARTY.md`.
- Фактические зелёные Windows/Android GitHub Actions на чистых runner; публикация
  Releases не проверена. Локальный smoke installer старого payload не заменяет
  свежую v3 сборку.
- Собственный production Android key и подтверждённая подпись; debug/test APK
  не выдаётся за финальный публичный релиз. Windows Authenticode отдельно.
- Реальный Android ARM64 import/play/edit/touch/SAF/export/save/reopen и системная
  установка обновления; clean Windows 10/11 установка/обновление/удаление.
- Jamendo agreement и track/application rights для живого offline-каталога либо
  сохранение честного локального fallback. Никаких платных соглашений/аккаунтов
  или приватных ключей от имени пользователя автоматически не создавалось.
- Нативный v3 экспорт и проверки preview/export для FPS, trim, marker-boundary,
  v2+v3 stacks, global/visual/caption/audio; длинный файл, отмена, storage-full,
  16 одновременных звуков и понятный отказ при превышении лимита — отдельная приёмка.

Общий итог приёмки: **реализована существенная часть локальной версии 3.0,
публичная production-готовность не подтверждена**. Финальный отчёт должен
обновить эту матрицу по фактическим исправлениям и новым результатам, а не
перенести прежние номера тестов или старые артефакты на новую сборку.
