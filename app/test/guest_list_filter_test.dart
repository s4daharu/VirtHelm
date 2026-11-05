import 'package:flutter_test/flutter_test.dart';
import 'package:virthelm/core/guest_list_filter.dart';
import 'package:virthelm/core/models.dart';

void main() {
  const guests = <Guest>[
    Guest(
      node: 'pve1',
      vmid: 101,
      kind: 'qemu',
      name: 'Web',
      status: 'running',
      tags: ['prod', 'web'],
      cpu: 0.35,
      mem: 1024,
    ),
    Guest(
      node: 'pve1',
      vmid: 102,
      kind: 'lxc',
      name: 'cache',
      status: 'stopped',
      tags: ['prod', 'cache'],
    ),
    Guest(
      node: 'pve2',
      vmid: 99,
      kind: 'qemu',
      name: 'web',
      status: 'running',
      tags: ['lab'],
      cpu: 0.8,
      mem: 2048,
    ),
    Guest(
      node: 'pve2',
      vmid: 101,
      kind: 'lxc',
      name: 'Web',
      status: 'unknown',
      mem: 4096,
    ),
    Guest(
      node: 'pve1',
      vmid: 104,
      kind: 'qemu',
      name: 'Backup',
      status: 'running',
      cpu: -1,
      mem: -1,
    ),
  ];

  bool favorite(Guest guest) => guest.kind == 'qemu' && guest.vmid == 101;
  String identity(Guest guest) => '${guest.kind}/${guest.node}/${guest.vmid}';

  test('default highlights favorites and breaks duplicate-name ties', () {
    final result = visibleGuests(guests, isFavorite: favorite);
    expect(result.first, same(guests.first));
    expect(result.skip(1).map(identity).toList(), [
      'qemu/pve1/104',
      'lxc/pve1/102',
      'qemu/pve2/99',
      'lxc/pve2/101',
    ]);
    expect(guests.first, same(result.first));
  });

  test('search is trimmed, case-insensitive and includes node and VMID', () {
    expect(
      visibleGuests(guests, isFavorite: favorite, search: ' WEB ').length,
      3,
    );
    expect(
      visibleGuests(guests, isFavorite: favorite, search: 'pve2').length,
      2,
    );
    expect(
      visibleGuests(guests, isFavorite: favorite, search: '101').length,
      2,
    );
    expect(
      visibleGuests(
        guests,
        isFavorite: favorite,
        search: ' LAB ',
      ).map(identity),
      ['qemu/pve2/99'],
    );
  });

  test('exact tag filter composes with node, type and status filters', () {
    expect(
      visibleGuests(
        guests,
        isFavorite: favorite,
        tag: 'PROD',
      ).map(identity),
      ['qemu/pve1/101', 'lxc/pve1/102'],
    );
    expect(
      visibleGuests(
        guests,
        isFavorite: favorite,
        tag: 'prod',
        kind: GuestKindFilter.lxc,
        node: 'pve1',
        status: 'stopped',
      ).map(identity),
      ['lxc/pve1/102'],
    );
    expect(
      visibleGuests(guests, isFavorite: favorite, tag: 'missing'),
      isEmpty,
    );
  });

  test('kind, node and status filters compose without changing writes', () {
    final result = visibleGuests(
      guests,
      isFavorite: favorite,
      kind: GuestKindFilter.qemu,
      node: 'pve2',
      status: 'running',
    );
    expect(result.map(identity), ['qemu/pve2/99']);
    expect(
      visibleGuests(
        guests,
        isFavorite: favorite,
        kind: GuestKindFilter.lxc,
        status: 'stopped',
      ).map(identity),
      ['lxc/pve1/102'],
    );
    expect(
      visibleGuests(
        guests,
        isFavorite: favorite,
        status: 'favorites',
      ).map(identity),
      ['qemu/pve1/101'],
    );
    expect(
      visibleGuests(guests, isFavorite: favorite, status: 'stopped').length,
      1,
    );
    expect(
      visibleGuests(guests, isFavorite: favorite, node: 'not-visible'),
      isEmpty,
    );
  });

  test('numeric VMID and metric sorts are stable with absent telemetry', () {
    expect(
      visibleGuests(
        guests,
        isFavorite: favorite,
        sort: GuestSort.vmid,
      ).map(identity),
      [
        'qemu/pve2/99',
        'lxc/pve2/101',
        'qemu/pve1/101',
        'lxc/pve1/102',
        'qemu/pve1/104',
      ],
    );
    expect(
      visibleGuests(
        guests,
        isFavorite: favorite,
        sort: GuestSort.cpu,
      ).map(identity),
      [
        'qemu/pve2/99',
        'qemu/pve1/101',
        'qemu/pve1/104',
        'lxc/pve1/102',
        'lxc/pve2/101',
      ],
    );
    expect(
      visibleGuests(
        guests,
        isFavorite: favorite,
        sort: GuestSort.memory,
      ).map(identity),
      [
        'lxc/pve2/101',
        'qemu/pve2/99',
        'qemu/pve1/101',
        'qemu/pve1/104',
        'lxc/pve1/102',
      ],
    );
    expect(
      visibleGuests(
        guests,
        isFavorite: favorite,
        sort: GuestSort.name,
      ).map(identity).first,
      'qemu/pve1/104',
    );
  });
}
