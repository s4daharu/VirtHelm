import 'package:flutter/services.dart';

/// Availability of Android's default network, not PVE endpoint reachability.
enum DeviceNetworkState { unknown, available, unavailable }

const _deviceNetworkEvents = EventChannel(
  'com.s4daharu.virthelm/device_network',
);

/// Missing/unsupported native information is UNKNOWN, never "offline".
Stream<DeviceNetworkState> deviceNetworkChanges() =>
    _deviceNetworkEvents.receiveBroadcastStream().map((value) {
      if (value == true) return DeviceNetworkState.available;
      if (value == false) return DeviceNetworkState.unavailable;
      return DeviceNetworkState.unknown;
    });
