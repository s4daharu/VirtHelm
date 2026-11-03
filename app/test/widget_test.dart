import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virthelm/core/app_controller.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/profile_repository.dart';
import 'package:virthelm/ui/connect_page.dart';

class _EmptyVault implements CredentialVault {
  @override
  Future<void> store(String id, ApiCredentials credentials) async {}
  @override
  Future<ApiCredentials?> retrieve(String id) async => null;
  @override
  Future<void> remove(String id) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('onboarding shows HTTPS and token fields', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = AppController(repository: ProfileRepository(prefs, _EmptyVault()));
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: ConnectPage(controller: controller)));
    expect(find.text('Your infrastructure.\nIn your hands.'), findsOneWidget);
    expect(find.text('Server URL'), findsOneWidget);
    expect(find.text('API token identifier'), findsOneWidget);
    expect(find.text('API token secret'), findsOneWidget);
    expect(find.text('Connect securely'), findsOneWidget);
  });
}
