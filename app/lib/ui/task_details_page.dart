import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';

/// Task logs are fetched on demand per page; nothing is persisted.
class TaskDetailsPage extends StatefulWidget {
  const TaskDetailsPage({
    super.key,
    required this.controller,
    required this.profileId,
    required this.generation,
    required this.node,
    required this.upid,
    required this.title,
  });

  final AppController controller;
  final String profileId;
  final int generation;
  final String node;
  final String upid;
  final String title;

  @override
  State<TaskDetailsPage> createState() => _TaskDetailsPageState();
}

class _TaskDetailsPageState extends State<TaskDetailsPage> {
  late Future<TaskInspection?> _inspection;
  int _pageStart = 0;

  Future<TaskInspection?> _readPage(int start) => widget.controller.inspectTask(
    profileId: widget.profileId,
    generation: widget.generation,
    node: widget.node,
    upid: widget.upid,
    logStart: start,
  );

  @override
  void initState() {
    super.initState();
    _inspection = _readPage(0);
  }

  // Each page navigation or explicit refresh performs fresh, read-only GETs.
  // Never concatenate sensitive log pages in long-lived controller state.
  void _showPage(int start) {
    if (start < 0 || start > 400 || start % 100 != 0) return;
    if (widget.controller.active?.id != widget.profileId ||
        widget.controller.connectionGeneration != widget.generation) {
      return;
    }
    setState(() {
      _pageStart = start;
      _inspection = _readPage(start);
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final current =
          widget.controller.active?.id == widget.profileId &&
          widget.controller.connectionGeneration == widget.generation;
      return Scaffold(
        appBar: AppBar(title: const Text('Task details')),
        body: !current
            ? const Center(
                child: Text(
                  'Connection changed. Task details are unavailable.',
                ),
              )
            : FutureBuilder<TaskInspection?>(
                future: _inspection,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final detail = snapshot.data;
                  if (detail == null) {
                    return const Center(
                      child: Text('Task details are no longer available.'),
                    );
                  }
                  final status = detail.status;
                  final label = status == null
                      ? 'Unavailable'
                      : !status.isDone
                      ? status.status
                      : status.succeeded
                      ? 'Succeeded'
                      : status.exitStatus == null
                      ? 'Unknown'
                      : 'Failed';
                  final logs = detail.log?.entries ?? const <TaskLogEntry>[];
                  final pageFilled =
                      detail.log != null &&
                      logs.length + detail.log!.malformedRecords == 100;
                  return ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text('Node: ${widget.node}'),
                      const SizedBox(height: 6),
                      SelectableText('UPID: ${widget.upid}'),
                      const SizedBox(height: 18),
                      Text(
                        'Current status',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(label),
                      if (status?.exitStatus != null)
                        Text('Exit: ${status!.exitStatus}'),
                      if (detail.statusError != null) Text(detail.statusError!),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _showPage(_pageStart),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh status and log'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Task log (lines ${_pageStart + 1}–${_pageStart + 100}; max 500)',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Server logs may contain sensitive information. '
                        'VirtHelm does not save or upload them.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (detail.logError != null) Text(detail.logError!),
                      if (detail.log != null && logs.isEmpty)
                        const Text('No task log lines available.'),
                      if (detail.log != null &&
                          detail.log!.malformedRecords > 0)
                        Text(
                          'Ignored ${detail.log!.malformedRecords} malformed log lines.',
                        ),
                      for (final entry in logs)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('${entry.number}: ${entry.text}'),
                        ),
                      if (_pageStart > 0 || (pageFilled && _pageStart < 400))
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Wrap(
                            spacing: 8,
                            children: [
                              if (_pageStart > 0)
                                OutlinedButton(
                                  onPressed: () => _showPage(_pageStart - 100),
                                  child: const Text('Previous 100'),
                                ),
                              if (pageFilled && _pageStart < 400)
                                OutlinedButton(
                                  onPressed: () => _showPage(_pageStart + 100),
                                  child: const Text('Next 100'),
                                ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
      );
    },
  );
}
