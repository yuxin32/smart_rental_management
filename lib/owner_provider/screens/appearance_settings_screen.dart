import 'package:flutter/material.dart';
import '../main.dart';
import '../theme/app_theme.dart';

class AppearanceSettingsScreen extends StatefulWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  State<AppearanceSettingsScreen> createState() => _AppearanceSettingsState();
}

class _AppearanceSettingsState extends State<AppearanceSettingsScreen> {
  bool _saving = false;
  ThemeMode? _unsavedMode;

  Future<void> _select(ThemeMode mode) async {
    final app = AppProviders.of(context);
    final save = app.onSetThemeMode;
    if (_saving || save == null) return;
    if (mode == app.themeMode && _unsavedMode == null) return;

    setState(() {
      _saving = true;
      _unsavedMode = null;
    });
    var saved = false;
    try {
      await save(mode);
      saved = true;
    } catch (_) {
      // The app has already applied the theme in memory.
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _unsavedMode = saved ? null : mode;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppProviders.of(context);
    final theme = Theme.of(context);
    final colors = SemanticColors.of(context);
    final sectionTint = theme.brightness == Brightness.dark
        ? colors.primarySurface
        : colors.primaryBorder;
    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      color: sectionTint,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.palette_outlined,
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Theme',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final stacked = constraints.maxWidth <
                              252 *
                                  (MediaQuery.textScalerOf(context).scale(14) /
                                      14);
                          final options = [
                            for (final mode in const [
                              ThemeMode.light,
                              ThemeMode.dark,
                              ThemeMode.system,
                            ])
                              _ThemeChoice(
                                mode: mode,
                                selected: app.themeMode == mode,
                                stacked: stacked,
                                onTap: _saving || app.onSetThemeMode == null
                                    ? null
                                    : () => _select(mode),
                              ),
                          ];
                          return stacked
                              ? Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (var index = 0;
                                        index < options.length;
                                        index++) ...[
                                      if (index > 0) const SizedBox(height: 8),
                                      options[index],
                                    ],
                                  ],
                                )
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (var index = 0;
                                        index < options.length;
                                        index++) ...[
                                      if (index > 0) const SizedBox(width: 8),
                                      Expanded(child: options[index]),
                                    ],
                                  ],
                                );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: Text(
                        'System follows your device settings.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_unsavedMode case final mode?)
            Center(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      'Couldn’t save theme.',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _select(mode),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    required this.mode,
    required this.selected,
    required this.stacked,
    required this.onTap,
  });

  final ThemeMode mode;
  final bool selected;
  final bool stacked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = SemanticColors.of(context);
    final accent = theme.colorScheme.primary;
    final label = switch (mode) {
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
      ThemeMode.system => 'System',
    };
    final illustration = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: stacked ? 44 : 64,
        child: Row(
          children: [
            if (mode != ThemeMode.dark)
              const Expanded(child: _MiniSurface(dark: false)),
            if (mode != ThemeMode.light)
              const Expanded(child: _MiniSurface(dark: true)),
          ],
        ),
      ),
    );
    final caption = Row(
      mainAxisAlignment:
          stacked ? MainAxisAlignment.start : MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: selected ? accent : colors.textPrimary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
        if (selected) ...[
          const SizedBox(width: 4),
          Icon(Icons.check_circle, size: 15, color: accent),
        ],
      ],
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: selected ? accent : colors.border,
        width: selected ? 2 : 1,
      ),
    );
    return Semantics(
      label: label,
      checked: selected,
      inMutuallyExclusiveGroup: true,
      enabled: onTap != null,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected ? colors.primarySurface : colors.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          excludeFromSemantics: true,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: stacked
                ? Row(
                    children: [
                      SizedBox(width: 78, child: illustration),
                      const SizedBox(width: 12),
                      Expanded(child: caption),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      illustration,
                      const SizedBox(height: 8),
                      caption,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _MiniSurface extends StatelessWidget {
  const _MiniSurface({required this.dark});
  static final _lightTheme = AppTheme.light();
  static final _darkTheme = AppTheme.dark();

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final theme = dark ? _darkTheme : _lightTheme;
    final scheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = constraints.maxWidth < 55 ? 5.0 : 8.0;
        final short = constraints.maxHeight < 50;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: EdgeInsets.all(inset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(
                  widthFactor: .67,
                  child: _stroke(scheme.onSurface, 4),
                ),
                SizedBox(height: short ? 4 : 6),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      border: Border.all(color: scheme.outlineVariant),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          FractionallySizedBox(
                            widthFactor: .75,
                            child: _stroke(scheme.onSurfaceVariant, 3),
                          ),
                          FractionallySizedBox(
                            widthFactor: .55,
                            child: _stroke(scheme.primary, short ? 4 : 7),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _stroke(Color color, double height) => SizedBox(
        height: height,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}
