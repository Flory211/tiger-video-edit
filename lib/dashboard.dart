import 'package:flutter/material.dart';

import 'app_info.dart';

class TigerDashboard extends StatelessWidget {
  final VoidCallback onCreate,
      onProjects,
      onTemplates,
      onMusic,
      onSounds,
      onUpdates,
      onSettings;
  final VoidCallback? onContinue;
  final String? lastProject;
  final bool reduceMotion;
  const TigerDashboard({
    super.key,
    required this.onCreate,
    required this.onProjects,
    required this.onTemplates,
    required this.onMusic,
    required this.onSounds,
    required this.onUpdates,
    required this.onSettings,
    this.onContinue,
    this.lastProject,
    this.reduceMotion = false,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    final colors = Theme.of(context).colorScheme;
    final reduce = reduceMotion || MediaQuery.disableAnimationsOf(context);
    final cards =
        <({IconData icon, String title, String detail, VoidCallback? tap})>[
          (
            icon: Icons.add_circle_outline,
            title: 'Новый проект',
            detail: 'Музыка, кадры и твой ритм',
            tap: onCreate,
          ),
          (
            icon: Icons.play_circle_outline,
            title: 'Продолжить проект',
            detail: lastProject ?? 'Сначала создай или открой проект',
            tap: onContinue,
          ),
          (
            icon: Icons.folder_open_outlined,
            title: 'Мои проекты',
            detail: 'Поиск и последние .tve',
            tap: onProjects,
          ),
          (
            icon: Icons.auto_awesome_outlined,
            title: 'Шаблоны',
            detail: 'Основа монтажа за один шаг',
            tap: onTemplates,
          ),
          (
            icon: Icons.library_music_outlined,
            title: 'Музыка',
            detail: 'Локальная библиотека офлайн',
            tap: onMusic,
          ),
          (
            icon: Icons.graphic_eq,
            title: 'Звуки',
            detail: 'Акценты и переходы',
            tap: onSounds,
          ),
          (
            icon: Icons.system_update_alt,
            title: 'Обновления',
            detail: 'Версия $appVersion',
            tap: onUpdates,
          ),
          (
            icon: Icons.tune,
            title: 'Настройки',
            detail: 'Сделай редактор удобным',
            tap: onSettings,
          ),
        ];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(compact ? 20 : 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Icon(
                          Icons.movie_filter_outlined,
                          color: colors.onPrimary,
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Text(
                          'TIGER',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 6,
                            fontSize: 26,
                          ),
                        ),
                      ),
                      Text(
                        appVersion,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                  SizedBox(height: compact ? 32 : 54),
                  Text(
                    'Поймай ритм.\nСоздай своё.',
                    style: TextStyle(
                      fontSize: compact ? 36 : 58,
                      fontWeight: FontWeight.w800,
                      height: 1.08,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Музыкальные эдиты на твоём устройстве. Монтаж, эффекты и экспорт работают без интернета.',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 16,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 32),
                  LayoutBuilder(
                    builder: (context, box) => GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: cards.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: box.maxWidth > 900
                            ? 4
                            : box.maxWidth > 470
                            ? 3
                            : 2,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        mainAxisExtent: 190,
                      ),
                      itemBuilder: (context, index) {
                        final card = cards[index];
                        return TweenAnimationBuilder<double>(
                          tween: Tween(begin: reduce ? 1 : 0, end: 1),
                          duration: reduce
                              ? Duration.zero
                              : Duration(milliseconds: 240 + index * 45),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) => Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, 18 * (1 - value)),
                              child: child,
                            ),
                          ),
                          child: _HomeCard(
                            icon: card.icon,
                            title: card.title,
                            detail: card.detail,
                            onTap: card.tap,
                            reduce: reduce,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Tiger Video Edit • Windows / Android • Проекты .tve',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeCard extends StatefulWidget {
  final IconData icon;
  final String title, detail;
  final VoidCallback? onTap;
  final bool reduce;
  const _HomeCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    required this.reduce,
  });
  @override
  State<_HomeCard> createState() => _HomeCardState();
}

class _HomeCardState extends State<_HomeCard> {
  bool hover = false;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: AnimatedScale(
        scale: hover && widget.onTap != null ? 1.025 : 1,
        duration: widget.reduce
            ? Duration.zero
            : const Duration(milliseconds: 130),
        child: AnimatedContainer(
          duration: widget.reduce
              ? Duration.zero
              : const Duration(milliseconds: 130),
          decoration: BoxDecoration(
            color: hover
                ? colors.surfaceContainerHigh
                : colors.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: hover
                  ? Theme.of(context).colorScheme.primary
                  : colors.outlineVariant,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(17),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      widget.icon,
                      color: widget.onTap == null
                          ? colors.onSurface.withValues(alpha: .38)
                          : colors.primary,
                      size: 28,
                    ),
                    const Spacer(),
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: widget.onTap == null
                            ? colors.onSurface.withValues(alpha: .38)
                            : colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      widget.detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
