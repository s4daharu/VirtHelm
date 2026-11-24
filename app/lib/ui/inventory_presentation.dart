import '../core/app_controller.dart';
import '../core/device_connectivity.dart';

extension InventoryPresentation on AppController {
  bool get isDeviceOffline =>
      deviceNetworkState == DeviceNetworkState.unavailable;

  String get inventoryLabel => inventory == null
      ? 'No live snapshot'
      : isInventoryFresh
      ? 'Live snapshot'
      : 'Last observed snapshot';

  String? get inventoryNotice => isDeviceOffline
      ? 'No default network. Check Wi-Fi or VPN.'
      : inventory != null && !isInventoryFresh
      ? 'Refresh inventory for current data.'
      : null;

  String utilizationLabel({required bool hasTarget}) => !hasTarget
      ? 'Utilization unavailable'
      : isInventoryFresh
      ? 'Live utilization'
      : 'Last observed utilization';
}
