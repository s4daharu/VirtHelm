import 'package:flutter_test/flutter_test.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/task_history_filter.dart';

void main() {
  const tasks = <RecentServerTask>[
    RecentServerTask(
      node: 'pve1',
      upid: 'UPID:pve1:1:2:3:qmstart:101:user@pve:',
      operation: 'qmstart',
      resourceId: '101',
      status: 'stopped',
      exitStatus: 'OK',
    ),
    RecentServerTask(
      node: 'pve2',
      upid: 'UPID:pve2:1:2:3:vzshutdown:202:user@pve:',
      operation: 'vzshutdown',
      resourceId: '202',
      status: 'stopped',
      exitStatus: 'command failed',
    ),
    RecentServerTask(
      node: 'pve1',
      upid: 'UPID:pve1:1:2:3:qmstop:103:user@pve:',
      operation: 'qmstop',
      resourceId: '103',
      status: 'stopped',
    ),
    RecentServerTask(
      node: 'pve3',
      upid: 'UPID:pve3:1:2:3:qmreboot:104:user@pve:',
      operation: 'qmreboot',
      resourceId: '104',
      status: 'running',
    ),
  ];

  test('default view preserves backend ordering without modifying inputs', () {
    final visible = visibleServerTasks(tasks);
    expect(visible, orderedEquals(tasks));
    expect(identical(visible, tasks), isFalse);
    expect(() => visible.clear(), throwsUnsupportedError);
    expect(tasks.length, 4);
  });

  test(
    'search trims and matches operation labels, raw types, nodes and ids',
    () {
      expect(
        visibleServerTasks(
          tasks,
          search: '  START VM  ',
        ).map((t) => t.resourceId),
        ['101'],
      );
      expect(
        visibleServerTasks(
          tasks,
          search: 'vzshutdown',
        ).map((t) => t.resourceId),
        ['202'],
      );
      expect(
        visibleServerTasks(tasks, search: 'PVE1').map((t) => t.resourceId),
        ['101', '103'],
      );
      expect(
        visibleServerTasks(tasks, search: '202').map((t) => t.resourceId),
        ['202'],
      );
      expect(visibleServerTasks(tasks, search: 'not-present'), isEmpty);
    },
  );

  test('state filters distinguish failed and unknown terminal outcomes', () {
    for (final (filter, expectedId) in [
      (ServerTaskStateFilter.succeeded, '101'),
      (ServerTaskStateFilter.failed, '202'),
      (ServerTaskStateFilter.unknown, '103'),
      (ServerTaskStateFilter.running, '104'),
    ]) {
      expect(
        visibleServerTasks(tasks, status: filter).single.resourceId,
        expectedId,
      );
    }
  });

  test('node, state and text compose without restoring hidden tasks', () {
    expect(
      visibleServerTasks(
        tasks,
        node: 'pve1',
        search: '103',
        status: ServerTaskStateFilter.unknown,
      ).map((task) => task.resourceId),
      ['103'],
    );
    expect(
      visibleServerTasks(
        tasks,
        node: 'pve2',
        status: ServerTaskStateFilter.succeeded,
      ),
      isEmpty,
    );
    expect(visibleServerTasks(tasks, node: 'pve404'), isEmpty);
  });
}
