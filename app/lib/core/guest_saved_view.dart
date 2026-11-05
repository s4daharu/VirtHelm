import 'dart:math';

import 'guest_list_filter.dart';

const int maxSavedGuestViews = 12;
const int maxSavedGuestViewNameLength = 40;
const int maxSavedGuestSearchLength = 120;
const int maxSavedGuestTagLength = 64;

class SavedGuestView {
  const SavedGuestView({
    required this.id,
    required this.name,
    required this.search,
    required this.status,
    required this.kind,
    required this.sort,
    this.node,
    this.tag,
  });

  final String id;
  final String name;
  final String search;
  final String status;
  final GuestKindFilter kind;
  final String? node;
  final String? tag;
  final GuestSort sort;

  factory SavedGuestView.create({
    required String name,
    String search = '',
    String status = 'all',
    GuestKindFilter kind = GuestKindFilter.all,
    String? node,
    String? tag,
    GuestSort sort = GuestSort.favorites,
  }) {
    final normalizedName = _validatedName(name);
    final normalizedSearch = _validatedSearch(search);
    final normalizedNode = _validatedNode(node);
    final normalizedTag = _validatedTag(tag);
    _validateStatus(status);
    return SavedGuestView(
      id:
          '${DateTime.now().microsecondsSinceEpoch}_'
          '${Random.secure().nextInt(0x7fffffff)}',
      name: normalizedName,
      search: normalizedSearch,
      status: status,
      kind: kind,
      node: normalizedNode,
      tag: normalizedTag,
      sort: sort,
    );
  }

  factory SavedGuestView.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final search = json['search'];
    final status = json['status'];
    final kind = json['kind'];
    final node = json['node'];
    final tag = json['tag'];
    final sort = json['sort'];
    if (id is! String || id.trim().isEmpty || id.length > 96) {
      throw const FormatException('Saved view has an invalid identifier.');
    }
    if (name is! String ||
        search is! String ||
        status is! String ||
        kind is! String ||
        sort is! String) {
      throw const FormatException('Saved view contains invalid fields.');
    }
    final parsedKind = _kindFromName(kind);
    final parsedSort = _sortFromName(sort);
    if (parsedKind == null || parsedSort == null) {
      throw const FormatException('Saved view contains unsupported options.');
    }
    _validateStatus(status);
    return SavedGuestView(
      id: id,
      name: _validatedName(name),
      search: _validatedSearch(search),
      status: status,
      kind: parsedKind,
      node: node == null
          ? null
          : node is String
          ? _validatedNode(node)
          : throw const FormatException('Saved view has an invalid node.'),
      tag: tag == null
          ? null
          : tag is String
          ? _validatedTag(tag)
          : throw const FormatException('Saved view has an invalid tag.'),
      sort: parsedSort,
    );
  }

  SavedGuestView withId(String nextId) => SavedGuestView(
    id: nextId,
    name: name,
    search: search,
    status: status,
    kind: kind,
    node: node,
    tag: tag,
    sort: sort,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'search': search,
    'status': status,
    'kind': kind.name,
    'node': node,
    'tag': tag,
    'sort': sort.name,
  };
}

String _validatedName(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.length > maxSavedGuestViewNameLength) {
    throw const FormatException(
      'Saved view name must be between 1 and 40 characters.',
    );
  }
  return normalized;
}

String _validatedSearch(String value) {
  final normalized = value.trim();
  if (normalized.length > maxSavedGuestSearchLength) {
    throw const FormatException('Saved view search is too long.');
  }
  return normalized;
}

String? _validatedNode(String? value) {
  if (value == null) return null;
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.length > 200) {
    throw const FormatException('Saved view has an invalid node.');
  }
  return normalized;
}

String? _validatedTag(String? value) {
  if (value == null) return null;
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized.length > maxSavedGuestTagLength ||
      normalized.contains(';')) {
    throw const FormatException('Saved view has an invalid tag.');
  }
  return normalized;
}

void _validateStatus(String value) {
  if (!const {'all', 'favorites', 'running', 'stopped'}.contains(value)) {
    throw const FormatException('Saved view has an unsupported status filter.');
  }
}

GuestKindFilter? _kindFromName(String name) {
  for (final value in GuestKindFilter.values) {
    if (value.name == name) return value;
  }
  return null;
}

GuestSort? _sortFromName(String name) {
  for (final value in GuestSort.values) {
    if (value.name == name) return value;
  }
  return null;
}
