import 'models.dart';

/// Pure, profile-agnostic presentation rules for a single inventory snapshot.
/// The caller supplies the active profile's favorite set.
enum GuestKindFilter { all, qemu, lxc }

enum GuestSort { favorites, name, vmid, cpu, memory }

extension GuestSortLabel on GuestSort {
  String get label => switch (this) {
    GuestSort.favorites => 'Favorites first',
    GuestSort.name => 'Name',
    GuestSort.vmid => 'VMID',
    GuestSort.cpu => 'CPU (high first)',
    GuestSort.memory => 'Memory (high first)',
  };
}

List<Guest> visibleGuests(
  Iterable<Guest> inventory, {
  required bool Function(Guest) isFavorite,
  String search = '',
  String status = 'all',
  GuestKindFilter kind = GuestKindFilter.all,
  String? node,
  GuestSort sort = GuestSort.favorites,
}) {
  final needle = search.trim().toLowerCase();
  final result = inventory.where((guest) {
    if (needle.isNotEmpty &&
        !guest.name.toLowerCase().contains(needle) &&
        !guest.vmid.toString().contains(needle) &&
        !guest.node.toLowerCase().contains(needle)) {
      return false;
    }
    if (kind != GuestKindFilter.all && guest.kind != kind.name) return false;
    if (node != null && guest.node != node) return false;
    return switch (status) {
      'favorites' => isFavorite(guest),
      'running' => guest.isRunning,
      'stopped' => guest.isStopped,
      _ => true,
    };
  }).toList();

  result.sort((a, b) {
    final primary = switch (sort) {
      GuestSort.favorites =>
        (isFavorite(b) ? 1 : 0) - (isFavorite(a) ? 1 : 0),
      GuestSort.name => _compareName(a, b),
      GuestSort.vmid => a.vmid.compareTo(b.vmid),
      GuestSort.cpu => _compareMetricDescending(a.cpu, b.cpu),
      GuestSort.memory => _compareMetricDescending(a.mem, b.mem),
    };
    if (primary != 0) return primary;
    final byName = _compareName(a, b);
    if (byName != 0) return byName;
    final byVmid = a.vmid.compareTo(b.vmid);
    if (byVmid != 0) return byVmid;
    final byKind = a.kind.compareTo(b.kind);
    if (byKind != 0) return byKind;
    return a.node.compareTo(b.node);
  });
  return result;
}

int _compareName(Guest a, Guest b) =>
    a.name.toLowerCase().compareTo(b.name.toLowerCase());

/// Missing, invalid, and negative telemetry never sorts above valid samples.
int _compareMetricDescending(num? a, num? b) {
  final aValid = a != null && a.isFinite && a >= 0;
  final bValid = b != null && b.isFinite && b >= 0;
  if (!aValid) return bValid ? 1 : 0;
  if (!bValid) return -1;
  return b!.compareTo(a!);
}
