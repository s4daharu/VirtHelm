import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virthelm/core/app_controller.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/profile_repository.dart';
import 'package:virthelm/ui/qemu_create_page.dart';
import 'package:virthelm/ui/template_clone_page.dart';

class _Vault implements CredentialVault {
  @override
  Future<void> store(String id, ApiCredentials credentials) async {}
  @override
  Future<ApiCredentials?> retrieve(String id) async => null;
  @override
  Future<void> remove(String id) async {}
}

class _Controller extends AppController {
  _Controller(ProfileRepository repository) : super(repository: repository);

  int testGeneration = 1;
  int submissions = 0;
  QemuCreateRequest? submitted;
  Completer<int?>? suggestion;

  @override
  int get connectionGeneration => testGeneration;

  void reconnect() {
    testGeneration++;
    notifyListeners();
  }

  void loseInventory() {
    inventory = null;
    notifyListeners();
  }

  @override
  Future<int?> suggestQemuCreateVmid({
    required String profileId,
    required int generation,
  }) async => suggestion?.future ?? 901;

  @override
  Future<int?> suggestTemplateCloneVmid({
    required String profileId,
    required int generation,
    required Guest source,
  }) async => 901;

  @override
  Future<void> runQemuCreate(
    QemuCreateRequest request, {
    required String profileId,
    required int generation,
  }) async {
    if (generation != testGeneration) throw StateError('Stale confirmation');
    submissions++;
    submitted = request.normalized();
  }
}

void main() {
  late _Controller controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    controller = _Controller(ProfileRepository(prefs, _Vault()))
      ..active = const ConnectionProfile(
        id: 'lab',
        name: 'Lab',
        endpoint: 'https://pve.local',
        allowInvalidCertificates: true,
      )
      ..inventory = Inventory.fromResources([
        {'type': 'node', 'node': 'pve1', 'status': 'online'},
        {
          'type': 'qemu',
          'node': 'pve1',
          'vmid': 900,
          'name': 'audit-template',
          'status': 'stopped',
          'template': 1,
        },
      ]);
  });
  tearDown(() => controller.dispose());

  Future<void> open(WidgetTester tester, {bool clone = false}) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => clone
                      ? TemplateClonePage(
                          controller: controller,
                          profileId: 'lab',
                          generation: 1,
                          source: controller.inventory!.guests.single,
                        )
                      : QemuCreatePage(
                          controller: controller,
                          profileId: 'lab',
                          generation: 1,
                        ),
                ),
              ),
              child: const Text('Open provisioning'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open provisioning'));
    await tester.pumpAndSettle();
  }

  Future<void> review(WidgetTester tester, {bool clone = false}) async {
    final key = Key(
      clone ? 'clone-review-submit' : 'qemu-create-review-submit',
    );
    await tester.ensureVisible(find.byKey(key));
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'requires exact typed VMID and submits the reviewed values once',
    (tester) async {
      await open(tester);
      await tester.enterText(
        find.byKey(const Key('qemu-create-name')),
        ' reviewed-vm ',
      );
      await tester.enterText(
        find.byKey(const Key('qemu-create-memory')),
        '4096',
      );
      await review(tester);
      expect(find.textContaining('does not allocate a disk'), findsOneWidget);
      expect(find.textContaining('INSECURE:'), findsOneWidget);
      final submit = find.byKey(const Key('qemu-create-confirm-submit'));
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      await tester.enterText(
        find.byKey(const Key('qemu-create-confirm-vmid')),
        '902',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      await tester.enterText(
        find.byKey(const Key('qemu-create-confirm-vmid')),
        '901',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(controller.submissions, 1);
      expect(controller.submitted!.name, 'reviewed-vm');
      expect(controller.submitted!.memoryMiB, 4096);
      expect(controller.submitted!.onBoot, isFalse);
      expect(find.text('Open provisioning'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancel keeps the form and disposes confirmation text safely', (
    tester,
  ) async {
    await open(tester);
    await review(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Create QEMU VM'), findsOneWidget);
    expect(controller.submissions, 0);
    expect(tester.takeException(), isNull);
  });

  for (final clone in [false, true]) {
    testWidgets(
      '${clone ? 'clone' : 'create'} confirmation redacts on same-profile reconnect',
      (tester) async {
        await open(tester, clone: clone);
        await review(tester, clone: clone);
        final prefix = clone ? 'clone' : 'qemu-create';
        await tester.enterText(find.byKey(Key('$prefix-confirm-vmid')), '901');
        await tester.pump();
        controller.reconnect();
        await tester.pumpAndSettle();
        expect(find.text('Confirmation expired'), findsOneWidget);
        expect(find.byKey(Key('$prefix-confirm-submit')), findsNothing);
        expect(find.byKey(Key('$prefix-confirm-vmid')), findsNothing);
        expect(find.textContaining('audit-template'), findsNothing);
        expect(find.textContaining('vm-901'), findsNothing);
        expect(controller.submissions, 0);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'open confirmation disables submit when live inventory disappears',
    (tester) async {
      await open(tester);
      await review(tester);
      await tester.enterText(
        find.byKey(const Key('qemu-create-confirm-vmid')),
        '901',
      );
      await tester.pump();
      controller.loseInventory();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('qemu-create-confirm-submit')),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.textContaining('Live inventory or target availability changed'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.submissions, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('late VMID suggestion never overwrites manual input', (
    tester,
  ) async {
    final gate = controller.suggestion = Completer<int?>();
    // The suggestion is intentionally pending; avoid settling its progress spinner.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: QemuCreatePage(
          controller: controller,
          profileId: 'lab',
          generation: 1,
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byKey(const Key('qemu-create-vmid')), '902');
    await tester.enterText(
      find.byKey(const Key('qemu-create-name')),
      'manual-vm',
    );
    gate.complete(901);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('qemu-create-vmid')))
          .controller!
          .text,
      '902',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('qemu-create-name')))
          .controller!
          .text,
      'manual-vm',
    );
  });

  testWidgets(
    'create form and typed confirmation fit 320dp at 200 percent text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: QemuCreatePage(
            controller: controller,
            profileId: 'lab',
            generation: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final scroll = find
          .descendant(
            of: find.byKey(const Key('qemu-create-list')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(const Key('qemu-create-review-submit')),
        250,
        scrollable: scroll,
      );
      await tester.ensureVisible(
        find.byKey(const Key('qemu-create-review-submit')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('qemu-create-review-submit')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('qemu-create-review-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Confirm QEMU VM creation'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('qemu-create-confirm-vmid')),
      );
      await tester.enterText(
        find.byKey(const Key('qemu-create-confirm-vmid')),
        '901',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.submissions, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
