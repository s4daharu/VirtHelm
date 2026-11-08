import 'package:flutter/material.dart';

const Color _seedColor = Color(0xFF00B8AF);

/// Semantic status colors shared by badges, meters and summary cards.
///
/// Status is always paired with text and an icon; these colors supplement the
/// label rather than carrying meaning on their own.
@immutable
class VirtHelmStatusColors extends ThemeExtension<VirtHelmStatusColors> {
  const VirtHelmStatusColors({
    required this.positive,
    required this.warning,
    required this.error,
    required this.neutral,
  });

  final Color positive;
  final Color warning;
  final Color error;
  final Color neutral;

  @override
  VirtHelmStatusColors copyWith({
    Color? positive,
    Color? warning,
    Color? error,
    Color? neutral,
  }) => VirtHelmStatusColors(
    positive: positive ?? this.positive,
    warning: warning ?? this.warning,
    error: error ?? this.error,
    neutral: neutral ?? this.neutral,
  );

  @override
  VirtHelmStatusColors lerp(
    covariant ThemeExtension<VirtHelmStatusColors>? other,
    double t,
  ) {
    if (other is! VirtHelmStatusColors) return this;
    return VirtHelmStatusColors(
      positive: Color.lerp(positive, other.positive, t) ?? positive,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      error: Color.lerp(error, other.error, t) ?? error,
      neutral: Color.lerp(neutral, other.neutral, t) ?? neutral,
    );
  }
}

VirtHelmStatusColors _statusColors(
  ColorScheme scheme,
  bool dark, {
  bool highContrast = false,
}) => VirtHelmStatusColors(
  positive: highContrast
      ? (dark ? const Color(0xFF77F2CE) : const Color(0xFF00634F))
      : (dark ? const Color(0xFF52D6B4) : const Color(0xFF087A64)),
  warning: highContrast
      ? (dark ? const Color(0xFFFFC67A) : const Color(0xFF784000))
      : (dark ? const Color(0xFFF3B26F) : const Color(0xFF9A5A12)),
  error: scheme.error,
  neutral: scheme.onSurfaceVariant,
);

ThemeData virthelmTheme(
  Brightness brightness, {
  bool amoled = false,
  bool highContrast = false,
}) {
  final dark = brightness == Brightness.dark;
  final generatedScheme = ColorScheme.fromSeed(
    seedColor: _seedColor,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
  );
  final scheme = amoled && dark
      ? generatedScheme.copyWith(
          surface: Colors.black,
          surfaceContainerLowest: Colors.black,
          surfaceContainerLow: const Color(0xFF050707),
          surfaceContainer: const Color(0xFF080B0C),
          surfaceContainerHigh: const Color(0xFF0D1112),
          surfaceContainerHighest: const Color(0xFF141A1B),
        )
      : generatedScheme;
  final surface = amoled && dark
      ? Colors.black
      : (dark ? const Color(0xFF0C1417) : const Color(0xFFF4F8F8));
  final cardColor = amoled && dark
      ? const Color(0xFF050707)
      : (dark ? const Color(0xFF162125) : Colors.white);
  final navColor = amoled && dark
      ? Colors.black
      : (dark ? const Color(0xFF111B1E) : Colors.white);
  final border = highContrast
      ? scheme.outline
      : scheme.outlineVariant.withValues(alpha: dark ? 0.32 : 0.55);
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  final textTheme = base.textTheme.copyWith(
    headlineSmall: base.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -0.3,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
    headlineMedium: base.textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -0.4,
    ),
    titleLarge: base.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.1,
    ),
    titleMedium: base.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    ),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.35),
    bodySmall: base.textTheme.bodySmall?.copyWith(
      height: 1.35,
      color: scheme.onSurfaceVariant,
    ),
    labelSmall: base.textTheme.labelSmall?.copyWith(
      letterSpacing: 0.5,
      fontWeight: FontWeight.w600,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: surface,
    textTheme: textTheme,
    extensions: <ThemeExtension<dynamic>>[
      _statusColors(scheme, dark, highContrast: highContrast),
    ],
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: cardColor,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: border),
      shape: const StadiumBorder(),
      backgroundColor: dark ? scheme.surfaceContainerLow : Colors.white,
      selectedColor: scheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      labelStyle: textTheme.labelLarge,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: border),
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      minVerticalPadding: 12,
    ),
    navigationBarTheme: NavigationBarThemeData(
      indicatorColor: scheme.primaryContainer,
      height: 72,
      backgroundColor: navColor,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return textTheme.labelSmall?.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
        );
      }),
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 24),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF243136) : const Color(0xFF203034),
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: cardColor,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: textTheme.bodySmall?.copyWith(color: scheme.onInverseSurface),
    ),
  );
}

enum _StatusTone { positive, warning, error, neutral }

_StatusTone _statusTone(String value) {
  final normalized = value.trim().toLowerCase();
  const positive = {
    'running',
    'online',
    'active',
    'enabled',
    'succeeded',
    'success',
    'ok',
    'healthy',
    'done',
  };
  const warning = {
    'stopped',
    'offline',
    'inactive',
    'paused',
    'pending',
    'warning',
    'degraded',
    'starting',
    'stopping',
  };
  const error = {'failed', 'error', 'disabled', 'unavailable', 'critical'};
  if (positive.contains(normalized)) return _StatusTone.positive;
  if (warning.contains(normalized)) return _StatusTone.warning;
  if (error.contains(normalized)) return _StatusTone.error;
  return _StatusTone.neutral;
}

/// Compact status pill with a text label, icon and semantic color.
///
/// The label is never replaced by color alone, so status remains readable with
/// color-vision deficiencies, in high-contrast mode and through TalkBack.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colors =
        Theme.of(context).extension<VirtHelmStatusColors>() ??
        _statusColors(Theme.of(context).colorScheme, false);
    final tone = _statusTone(status);
    final color = switch (tone) {
      _StatusTone.positive => colors.positive,
      _StatusTone.warning => colors.warning,
      _StatusTone.error => colors.error,
      _StatusTone.neutral => colors.neutral,
    };
    final icon = switch (tone) {
      _StatusTone.positive => Icons.check_circle_rounded,
      _StatusTone.warning => Icons.warning_amber_rounded,
      _StatusTone.error => Icons.error_rounded,
      _StatusTone.neutral => Icons.help_outline_rounded,
    };
    return Semantics(
      label: 'Status: $status',
      container: true,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(50),
            color: color.withValues(alpha: 0.13),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  icon,
                  size: 36,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                body,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              if (action != null) ...[const SizedBox(height: 18), action!],
            ],
          ),
        ),
      ),
    ),
  );
}
