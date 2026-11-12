import 'package:flutter/services.dart';

typedef IncidentNavigationHandler = void Function();

abstract class IncidentNotificationNavigation {
  Future<bool> takePendingIncidentIntent();
  void listen(IncidentNavigationHandler handler);
  void dispose();
}

class AndroidIncidentNotificationNavigation
    implements IncidentNotificationNavigation {
  const AndroidIncidentNotificationNavigation();

  static const MethodChannel _channel = MethodChannel(
    'com.s4daharu.virthelm/incident_navigation',
  );

  @override
  Future<bool> takePendingIncidentIntent() async {
    try {
      return await _channel.invokeMethod<bool>('takePendingIncidentIntent') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  void listen(IncidentNavigationHandler handler) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openIncidents') {
        handler();
        return true;
      }
      return null;
    });
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
  }
}
