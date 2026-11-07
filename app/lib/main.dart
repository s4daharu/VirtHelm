import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_controller.dart';
import 'core/app_preferences.dart';
import 'core/device_connectivity.dart';
import 'core/profile_repository.dart';
import 'ui/connect_page.dart';
import 'ui/connections_page.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  runApp(
    VirtHelmApp(
      repository: ProfileRepository(preferences, SecureCredentialVault()),
    ),
  );
}

class VirtHelmApp extends StatefulWidget {
  const VirtHelmApp({super.key, required this.repository});
  final ProfileRepository repository;

  @override
  State<VirtHelmApp> createState() => _VirtHelmAppState();
}

class _VirtHelmAppState extends State<VirtHelmApp> with WidgetsBindingObserver {
  late final AppController controller;
  late final ValueNotifier<AppThemePreference> _themePreference;
  late final StreamSubscription<DeviceNetworkState> _networkSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller = AppController(repository: widget.repository);
    _themePreference = ValueNotifier(controller.themePreference);
    controller.addListener(_syncThemePreference);
    _networkSubscription = deviceNetworkChanges().listen(
      controller.setDeviceNetworkState,
      onError: (Object _) =>
          controller.setDeviceNetworkState(DeviceNetworkState.unknown),
    );
    unawaited(controller.initialize());
  }

  // Keep the MaterialApp rebuild scoped to rare theme changes. Inventory,
  // task and incident notifications rebuild only the active shell subtree.
  void _syncThemePreference() {
    if (_themePreference.value != controller.themePreference) {
      _themePreference.value = controller.themePreference;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    controller.setForeground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_syncThemePreference);
    _themePreference.dispose();
    unawaited(_networkSubscription.cancel());
    controller.dispose();
    super.dispose();
  }

  Widget _home() {
    if (!controller.initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (controller.active == null) {
      if (controller.profiles.isNotEmpty) {
        return ConnectionsPage(controller: controller, chooserMode: true);
      }
      return ConnectPage(controller: controller);
    }
    return ShellPage(controller: controller);
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<AppThemePreference>(
        valueListenable: _themePreference,
        builder: (context, themePreference, _) => MaterialApp(
          title: 'VirtHelm',
          debugShowCheckedModeBanner: false,
          theme: virthelmTheme(Brightness.light),
          darkTheme: virthelmTheme(Brightness.dark),
          themeMode: switch (themePreference) {
            AppThemePreference.system => ThemeMode.system,
            AppThemePreference.light => ThemeMode.light,
            AppThemePreference.dark => ThemeMode.dark,
          },
          home: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => _home(),
          ),
        ),
      );
}
