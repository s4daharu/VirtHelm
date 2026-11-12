import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_controller.dart';
import 'core/app_preferences.dart';
import 'core/device_connectivity.dart';
import 'core/notification_navigation.dart';
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
  const VirtHelmApp({
    super.key,
    required this.repository,
    this.incidentNavigation,
  });

  final ProfileRepository repository;
  final IncidentNotificationNavigation? incidentNavigation;

  @override
  State<VirtHelmApp> createState() => _VirtHelmAppState();
}

class _VirtHelmAppState extends State<VirtHelmApp> with WidgetsBindingObserver {
  late final AppController controller;
  late final ValueNotifier<AppThemePreference> _themePreference;
  late final ValueNotifier<bool> _highContrast;
  late final ValueNotifier<bool> _reduceMotion;
  late final StreamSubscription<DeviceNetworkState> _networkSubscription;
  late final IncidentNotificationNavigation _incidentNavigation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller = AppController(repository: widget.repository);
    _incidentNavigation =
        widget.incidentNavigation ??
        const AndroidIncidentNotificationNavigation();
    _incidentNavigation.listen(controller.requestIncidentCenter);
    unawaited(_consumePendingIncidentNavigation());
    _themePreference = ValueNotifier(controller.themePreference);
    _highContrast = ValueNotifier(controller.highContrast);
    _reduceMotion = ValueNotifier(controller.reduceMotion);
    controller.addListener(_syncVisualPreferences);
    _networkSubscription = deviceNetworkChanges().listen(
      controller.setDeviceNetworkState,
      onError: (Object _) =>
          controller.setDeviceNetworkState(DeviceNetworkState.unknown),
    );
    unawaited(controller.initialize());
  }

  Future<void> _consumePendingIncidentNavigation() async {
    if (await _incidentNavigation.takePendingIncidentIntent()) {
      controller.requestIncidentCenter();
    }
  }

  // Keep the MaterialApp rebuild scoped to rare theme changes. Inventory,
  // task and incident notifications rebuild only the active shell subtree.
  void _syncVisualPreferences() {
    if (_themePreference.value != controller.themePreference) {
      _themePreference.value = controller.themePreference;
    }
    if (_highContrast.value != controller.highContrast) {
      _highContrast.value = controller.highContrast;
    }
    if (_reduceMotion.value != controller.reduceMotion) {
      _reduceMotion.value = controller.reduceMotion;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    controller.setForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) {
      unawaited(_consumePendingIncidentNavigation());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_syncVisualPreferences);
    _themePreference.dispose();
    _highContrast.dispose();
    _reduceMotion.dispose();
    unawaited(_networkSubscription.cancel());
    _incidentNavigation.dispose();
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
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<AppThemePreference>(
    valueListenable: _themePreference,
    builder: (context, themePreference, _) => ValueListenableBuilder<bool>(
      valueListenable: _highContrast,
      builder: (context, highContrast, _) => ValueListenableBuilder<bool>(
        valueListenable: _reduceMotion,
        builder: (context, reduceMotion, _) {
          final amoled = themePreference == AppThemePreference.amoled;
          return MaterialApp(
            title: 'VirtHelm',
            debugShowCheckedModeBanner: false,
            theme: virthelmTheme(Brightness.light, highContrast: highContrast),
            darkTheme: virthelmTheme(
              Brightness.dark,
              amoled: amoled,
              highContrast: highContrast,
            ),
            highContrastTheme: virthelmTheme(
              Brightness.light,
              highContrast: true,
            ),
            highContrastDarkTheme: virthelmTheme(
              Brightness.dark,
              amoled: amoled,
              highContrast: true,
            ),
            themeAnimationDuration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 200),
            themeMode: switch (themePreference) {
              AppThemePreference.system => ThemeMode.system,
              AppThemePreference.light => ThemeMode.light,
              AppThemePreference.dark => ThemeMode.dark,
              AppThemePreference.amoled => ThemeMode.dark,
            },
            builder: (context, child) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(
                  disableAnimations: media.disableAnimations || reduceMotion,
                ),
                child: child!,
              );
            },
            home: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => _home(),
            ),
          );
        },
      ),
    ),
  );
}
