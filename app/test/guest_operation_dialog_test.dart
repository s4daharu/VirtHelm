import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virthelm/core/app_controller.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/profile_repository.dart';
import 'package:virthelm/ui/guest_page.dart';

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

  int generation = 0;
  @override
  int get connectionGeneration => generation;

  Completer<GuestRestorePlanPreflight?>? restoreGate;

  @override
  Future<GuestBackupArchiveInventory?> inspectGuestBackupArchives({
    required String profileId,
    required int generation,
    required Guest guest,
    required String storage,
  }) async => GuestBackupArchiveInventory(
    storage: storage,
    archives: [
      GuestBackupArchive(
        node: guest.node,
        storage: storage,
        volid: '$storage:backup/vzdump-qemu-101-synthetic.vma.zst',
        kind: guest.kind,
        vmid: guest.vmid,
      ),
    ],
  );

  @override
  Future<GuestRestorePlanPreflight?> inspectGuestRestorePlan({
    required String profileId,
    required int generation,
    required Guest guest,
    required GuestBackupArchive archive,
    required GuestRestorePlanRequest request,
  }) async => restoreGate?.future;
}

Future<_Controller> _openGuest(
  WidgetTester tester, {
  bool largeText = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final controller = _Controller(ProfileRepository(prefs, _Vault()));
  addTearDown(controller.dispose);
  controller.active = const ConnectionProfile(
    id: 'a',
    name: 'Synthetic connection',
    endpoint: 'https://pve.example:8006',
    allowInvalidCertificates: true,
  );
  controller.inventory = Inventory.fromResources([
    {'type': 'node', 'node': 'pve1', 'status': 'online'},
    {'type': 'node', 'node': 'pve2', 'status': 'online'},
    {
      'type': 'qemu',
      'node': 'pve1',
      'vmid': 101,
      'name': 'Web',
      'status': 'stopped',
    },
  ]);
  controller.storages = const [
    StoragePool(
      node: 'pve1',
      id: 'backup',
      type: 'dir',
      enabled: true,
      active: true,
      contentTypes: ['backup'],
    ),
    StoragePool(
      node: 'pve1',
      id: 'local-lvm',
      type: 'lvmthin',
      enabled: true,
      active: true,
      contentTypes: ['images'],
    ),
  ];
  await tester.pumpWidget(
    MaterialApp(
      builder: largeText
          ? (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            )
          : null,
      home: GuestPage(
        controller: controller,
        guest: controller.inventory!.guests.single,
        profileId: 'a',
        generation: controller.connectionGeneration,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _openDialog(WidgetTester tester, String operation) async {
  if (operation == 'migration' || operation == 'destination') {
    await tester.tap(find.byKey(const Key('guest-migrate')));
    await tester.pumpAndSettle();
    if (operation == 'destination') return;
    await tester.tap(find.byKey(const Key('guest-migration-target-pve2')));
  } else if (operation == 'delete') {
    await tester.tap(find.byKey(const Key('guest-delete')));
  } else {
    await tester.tap(find.byKey(const Key('guest-recovery-tab')));
    await tester.pumpAndSettle();
    final scrollable = find.descendant(
      of: find.byKey(const Key('guest-recovery-list')),
      matching: find.byType(Scrollable),
    );
    final key = operation == 'snapshot'
        ? 'guest-create-snapshot'
        : operation == 'backup'
        ? 'guest-start-backup'
        : 'guest-load-backup-archives';
    await tester.scrollUntilVisible(
      find.byKey(Key(key)),
      120,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(key)));
    if (operation == 'restore') {
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('guest-plan-restore-0')),
        180,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('guest-plan-restore-0')),
      );
    }
  }
  await tester.pumpAndSettle();
}

void main() {
  for (final operation in [
    'snapshot',
    'backup',
    'delete',
    'migration',
    'destination',
    'restore',
  ]) {
    for (final change in ['reconnect', 'profile switch', 'guest removal']) {
      testWidgets('$operation dialog redacts on $change', (tester) async {
        final controller = await _openGuest(tester);
        await _openDialog(tester, operation);
        expect(find.byType(Dialog), findsOneWidget);
        if (operation != 'destination') {
          expect(
            find.textContaining('INSECURE: server certificate verification'),
            findsOneWidget,
          );
          expect(
            find.textContaining('Connection: Synthetic connection'),
            findsOneWidget,
          );
        }
        if (change == 'reconnect') {
          controller.generation++;
        } else if (change == 'profile switch') {
          controller.active = const ConnectionProfile(
            id: 'b',
            name: 'Other',
            endpoint: 'https://other.example:8006',
          );
        } else {
          controller.inventory = Inventory.fromResources([]);
        }
        controller.notifyListeners();
        await tester.pumpAndSettle();
        expect(find.text('Confirmation expired'), findsOneWidget);
        final dialog = find.byType(Dialog);
        expect(
          find.descendant(of: dialog, matching: find.textContaining('Web')),
          findsNothing,
        );
        expect(
          find.descendant(of: dialog, matching: find.textContaining('pve2')),
          findsNothing,
        );
        expect(
          find.descendant(of: dialog, matching: find.byType(FilledButton)),
          findsNothing,
        );
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(controller.tasks, isEmpty);
      });
    }
  }

  for (final operation in ['snapshot', 'migration', 'delete']) {
    testWidgets(
      '$operation typed dialog cancels without disposed-controller errors',
      (tester) async {
        await _openGuest(tester);
        await _openDialog(tester, operation);
        final key = operation == 'snapshot'
            ? 'guest-snapshot-name'
            : operation == 'migration'
            ? 'guest-migration-confirmation'
            : 'guest-delete-confirmation';
        final input = find.byKey(Key(key));
        await tester.ensureVisible(input);
        await tester.pumpAndSettle();
        await tester.enterText(
          input,
          operation == 'snapshot'
              ? 'audit'
              : operation == 'migration'
              ? '101'
              : 'DELETE Web 101',
        );
        await tester.pump();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('large-text deletion starts on the warning and expires safely', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await _openGuest(tester, largeText: true);
    await _openDialog(tester, 'delete');

    final dialog = find.byType(AlertDialog);
    final target = find.text('QEMU • pve1 • VMID 101');
    final warning = find.textContaining('This permanently destroys the guest');
    final input = find.byKey(const Key('guest-delete-confirmation'));
    final checkbox = find.byKey(const Key('guest-delete-backup-ack'));
    final submit = find.byKey(const Key('guest-delete-submit'));
    final cancel = find.text('Cancel');
    expect(tester.testTextInput.isVisible, isFalse);
    expect(target.hitTestable(), findsOneWidget);
    expect(
      tester.getTopLeft(warning).dy,
      lessThan(tester.getTopLeft(cancel).dy),
    );
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    await tester.ensureVisible(input);
    await tester.pumpAndSettle();
    await tester.enterText(input, 'DELETE Web 101');
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final acknowledgement = find.descendant(
      of: checkbox,
      matching: find.byType(Checkbox),
    );
    await Scrollable.ensureVisible(
      tester.element(acknowledgement),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    expect(acknowledgement.hitTestable(), findsOneWidget);
    await tester.tap(acknowledgement);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);

    final inventory = controller.inventory!;
    controller.inventory = Inventory(
      nodes: inventory.nodes,
      guests: inventory.guests,
      fetchedAt: DateTime.now().subtract(const Duration(minutes: 3)),
    );
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: dialog,
        matching: find.text(
          'A fresh inventory is required — actions are disabled.',
        ),
      ),
      findsOneWidget,
    );
    expect(submit, findsNothing);
    expect(cancel.hitTestable(), findsOneWidget);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refreshing archives discards an in-flight restore plan result', (
    tester,
  ) async {
    final controller = await _openGuest(tester);
    controller.restoreGate = Completer<GuestRestorePlanPreflight?>();
    await _openDialog(tester, 'restore');
    await tester.enterText(
      find.byKey(const Key('guest-restore-target-vmid')),
      '901',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('guest-restore-plan-submit')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    final scrollable = find.descendant(
      of: find.byKey(const Key('guest-recovery-list')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('guest-load-backup-archives')),
      -180,
      scrollable: scrollable,
    );
    await tester.tap(find.byKey(const Key('guest-load-backup-archives')));
    await tester.pumpAndSettle();
    controller.restoreGate!.complete(
      const GuestRestorePlanPreflight(
        sourceArchive: GuestBackupArchive(
          node: 'pve1',
          storage: 'backup',
          volid: 'backup:backup/vzdump-qemu-101-synthetic.vma.zst',
          kind: 'qemu',
          vmid: 101,
        ),
        targetNode: 'pve1',
        targetVmid: 901,
        targetStorage: 'local-lvm',
        status: GuestRestorePlanStatus.preflightComplete,
        sourceArchiveVisible: true,
        sourceStorageUsable: true,
        targetNodeOnline: true,
        targetVmidAvailable: true,
        targetStorageUsable: true,
        vmAllocateAvailable: true,
        datastoreAllocateSpaceAvailable: true,
        storageReadComplete: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Preflight complete'), findsNothing);
    expect(find.byKey(const Key('guest-restore-plan-preflight')), findsNothing);
  });
}
