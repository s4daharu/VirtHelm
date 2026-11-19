import 'package:flutter/material.dart';

import '../core/capacity_review.dart';
import '../core/models.dart';
import 'components.dart';

/// Non-interactive and never shown as live advice for stale/partial reads.
class CapacityReviewSection extends StatelessWidget {
  const CapacityReviewSection({
    super.key,
    required this.inventory,
    required this.storages,
    required this.isTrusted,
  });

  final Inventory inventory;
  final List<StoragePool> storages;
  final bool isTrusted;

  @override
  Widget build(BuildContext context) {
    final review = isTrusted
        ? CapacityReview.evaluate(inventory: inventory, storages: storages)
        : null;
    final theme = Theme.of(context);
    return Column(
      key: const Key('capacity-review'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeading(
          title: 'Capacity review',
          trailing: 'LOCAL • READ ONLY',
        ),
        const SizedBox(height: 10),
        if (review == null)
          const MessageCard(
            text:
                'Capacity review is unavailable until a fresh, complete '
                'foreground inventory and storage read succeeds. '
                'Cached or partial data cannot establish current usage.',
          )
        else ...[
          Text(
            'Snapshot-only indicators at 85% usage or above. '
            'No trend, forecast, storage aggregation or automatic action.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            review.usableMeasurements.toString() +
                ' usable measurements • ' +
                review.missingMeasurements.toString() +
                ' missing or ambiguous' +
                (review.truncated ? ' • candidate scan capped' : ''),
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 8),
          if (review.usableMeasurements == 0)
            const MessageCard(
              text:
                  'No usable capacity measurements in this snapshot. '
                  'Missing metrics must not be treated as healthy.',
            )
          else if (review.signals.isEmpty)
            const MessageCard(
              text:
                  'No elevated usage in the usable measurements. '
                  'This is not a health assessment or a prediction; '
                  'unavailable and unscanned resources are unknown.',
            )
          else ...[
            for (var index = 0; index < review.signals.length; index++) ...[
              Card(
                key: Key('capacity-signal-' + index.toString()),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        review.signals[index].metric.label +
                            ' • ' +
                            review.signals[index].resource,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        review.signals[index].percentage +
                            ' used in this snapshot. Review the '
                                'resource manually; no action was taken.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
          ],
        ],
      ],
    );
  }
}
