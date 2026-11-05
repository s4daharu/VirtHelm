import 'models.dart';

/// Local, read-only filters for the currently loaded server task snapshot.
/// No API requests, task state changes or locally persisted search terms.
enum ServerTaskStateFilter { all, running, succeeded, failed, unknown }

List<RecentServerTask> visibleServerTasks(
  List<RecentServerTask> tasks, {
  String search = '',
  String node = '',
  ServerTaskStateFilter status = ServerTaskStateFilter.all,
}) {
  final needle = search.trim().toLowerCase();
  return List<RecentServerTask>.unmodifiable(
    tasks.where((task) {
      if (node.isNotEmpty && task.node != node) return false;
      if (status != ServerTaskStateFilter.all &&
          task.stateLabel != status.name) {
        return false;
      }
      if (needle.isEmpty) return true;
      return <String>[
        task.operation,
        task.operationLabel,
        task.node,
        task.resourceId ?? '',
        task.upid,
      ].any((value) => value.toLowerCase().contains(needle));
    }),
  );
}
