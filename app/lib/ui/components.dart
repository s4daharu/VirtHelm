import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../core/models.dart';
import 'theme.dart';

/// Section title used by scrollable screens.
class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.title,
    this.trailing = '',
    this.action,
  });

  final String title;
  final String trailing;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 12,
    runSpacing: 4,
    children: [
      Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
      ),
      if (action != null)
        action!
      else if (trailing.isNotEmpty)
        Text(
          trailing,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 10,
            letterSpacing: 1,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
    ],
  );
}

enum MessageTone { neutral, warning, error, success }

/// Inline explanation card for partial data, stale state or recoverable errors.
class MessageCard extends StatelessWidget {
  const MessageCard({
    super.key,
    required this.text,
    this.title,
    this.icon,
    this.tone = MessageTone.neutral,
    this.action,
  });

  final String text;
  final String? title;
  final IconData? icon;
  final MessageTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status =
        Theme.of(context).extension<VirtHelmStatusColors>() ??
        const VirtHelmStatusColors(
          positive: Color(0xFF087A64),
          warning: Color(0xFF9A5A12),
          error: Color(0xFFB3261E),
          neutral: Color(0xFF5F6368),
        );
    final color = switch (tone) {
      MessageTone.neutral => scheme.onSurfaceVariant,
      MessageTone.warning => status.warning,
      MessageTone.error => status.error,
      MessageTone.success => status.positive,
    };
    final resolvedIcon =
        icon ??
        switch (tone) {
          MessageTone.neutral => Icons.info_outline_rounded,
          MessageTone.warning => Icons.warning_amber_rounded,
          MessageTone.error => Icons.error_outline_rounded,
          MessageTone.success => Icons.check_circle_outline_rounded,
        };
    return Card(
      color: tone == MessageTone.neutral
          ? null
          : Color.alphaBlend(color.withValues(alpha: 0.07), scheme.surface),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(resolvedIcon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Text(
                      title!,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(text),
                  if (action != null) ...[const SizedBox(height: 10), action!],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Label + value + usage bar used by node and guest detail screens.
class MetricBar extends StatelessWidget {
  const MetricBar({
    super.key,
    required this.label,
    required this.value,
    required this.fraction,
    this.icon,
    this.color,
  });

  final String label;
  final String value;
  final double? fraction;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            UsageBar(
              fraction: fraction,
              color: accent,
              semanticsLabel: '$label $value',
            ),
          ],
        ),
      ),
    );
  }
}

class UsageBar extends StatelessWidget {
  const UsageBar({
    super.key,
    required this.fraction,
    this.color,
    this.height = 7,
    this.semanticsLabel,
  });

  final double? fraction;
  final Color? color;
  final double height;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = fraction?.clamp(0.0, 1.0).toDouble() ?? 0.0;
    final accent = color ?? scheme.primary;
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value,
        minHeight: height,
        backgroundColor: scheme.surfaceContainerHighest,
        color: accent,
      ),
    );
    if (semanticsLabel == null) return bar;
    return Semantics(
      label: semanticsLabel,
      value: fraction == null ? 'unavailable' : '${(value * 100).round()}%',
      child: ExcludeSemantics(child: bar),
    );
  }
}

/// Normalizes optional 0..1 fractions for chart rendering.
List<double> normalizedSamples(Iterable<double?> values) => values
    .whereType<double>()
    .where((value) => value.isFinite && value >= 0 && value <= 1)
    .toList(growable: false);

/// Latest/range text alternative shared by guest and node history cards.
String fractionRangeSummary(List<double> values) {
  if (values.isEmpty) return '';
  final latest = values.last;
  final minimum = values.reduce((left, right) => left < right ? left : right);
  final maximum = values.reduce((left, right) => left > right ? left : right);
  return 'Latest ${formatPercent(latest)} • '
      'Range ${formatPercent(minimum)}–${formatPercent(maximum)}';
}

/// Simple sparkline with visible axes and an accessible data-table alternative.
class SparklineCard extends StatelessWidget {
  const SparklineCard({
    super.key,
    required this.title,
    required this.icon,
    required this.values,
    required this.summary,
    this.timestamps,
    this.secondaryText,
    this.color,
    this.axisLabel = 'Usage (%)',
    this.timeframeLabel,
  }) : assert(timestamps == null || timestamps.length == values.length);

  final String title;
  final IconData icon;
  final List<double> values;
  final String summary;
  final List<DateTime>? timestamps;
  final String? secondaryText;
  final Color? color;
  final String axisLabel;
  final String? timeframeLabel;

  String _timestampLabel(DateTime timestamp) {
    final value = timestamp.toUtc();
    String two(int part) => part.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)} UTC';
  }

  Future<void> _showDataTable(BuildContext context) async {
    final sampleTimes = timestamps;
    if (sampleTimes == null || sampleTimes.length != values.length) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.72,
          child: Column(
            children: [
              ListTile(
                title: Text(
                  '$title data',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                subtitle: Text(
                  '${values.length} samples • $axisLabel'
                  '${timeframeLabel == null ? '' : ' • $timeframeLabel'}',
                ),
                trailing: IconButton(
                  tooltip: 'Close data table',
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  key: ValueKey('sparkline-data-$title'),
                  itemCount: values.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) => Semantics(
                    label:
                        '${_timestampLabel(sampleTimes[index])}, '
                        '${formatPercent(values[index])}',
                    child: ListTile(
                      title: Text(formatPercent(values[index])),
                      subtitle: Text(_timestampLabel(sampleTimes[index])),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: const Text('No usable samples in this response.'),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.primary;
    final tableAvailable =
        timestamps != null && timestamps!.length == values.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(summary),
            if (secondaryText != null) ...[
              const SizedBox(height: 3),
              Text(
                secondaryText!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  axisLabel,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Text(
                  'Time • ${timeframeLabel ?? 'requested range'}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Semantics(
              label:
                  '$title. $summary. '
                  '${secondaryText == null ? '' : '$secondaryText. '}'
                  '${values.length} samples. Vertical axis 0 to 100 percent. '
                  'Horizontal axis is time.',
              child: ExcludeSemantics(
                child: SizedBox(
                  height: 112,
                  width: double.infinity,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 42,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (final label in const ['100%', '50%', '0%'])
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  label,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: SparklinePainter(
                              values: values,
                              color: accent,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (tableAvailable) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: ValueKey('sparkline-table-$title'),
                  onPressed: () => _showDataTable(context),
                  icon: const Icon(Icons.table_rows_outlined),
                  label: const Text('View data table'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SparklinePainter extends CustomPainter {
  const SparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width <= 0 || size.height <= 0) return;
    final gridPaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (final fraction in const [0.0, 0.5, 1.0]) {
      final y = size.height * (1 - fraction);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (values.length == 1) {
      canvas.drawCircle(
        Offset(size.width / 2, size.height * (1 - values.single)),
        2.5,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x = size.width * index / (values.length - 1);
      final y = size.height * (1 - values[index].clamp(0.0, 1.0).toDouble());
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..color = color.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(SparklinePainter oldDelegate) =>
      !listEquals(oldDelegate.values, values) || oldDelegate.color != color;
}
