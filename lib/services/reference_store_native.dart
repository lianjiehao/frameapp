import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'reference_store_api.dart';
export 'reference_store_api.dart';

ReferenceStore createReferenceStore({Directory? directory}) =>
    _FileReferenceStore(directory);

class _FileReferenceStore implements ReferenceStore {
  _FileReferenceStore(this.directory);
  final Directory? directory;
  Future<Directory> get _directory async => directory != null
      ? directory!.create(recursive: true)
      : Directory(
          '${(await getApplicationSupportDirectory()).path}/references',
        ).create(recursive: true);
  bool _validId(String id) => RegExp(r'^[a-f0-9]{64}$').hasMatch(id);
  bool _validTemplateId(String id) => RegExp(
    r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
  ).hasMatch(id);

  @override
  Future<List<ReferenceAsset>> load() async {
    final dir = await _directory;
    final index = File('${dir.path}/index.json');
    if (!await index.exists()) return [];
    final data = jsonDecode(await index.readAsString()) as List;
    final result = <ReferenceAsset>[];
    for (final row in data.take(20)) {
      if (row is! Map || row['id'] is! String || !_validId(row['id'])) continue;
      final id = row['id'] as String, file = File('${dir.path}/$id.png');
      if (await file.exists() && await file.length() <= 12 * 1024 * 1024) {
        result.add(
          ReferenceAsset(
            id,
            await file.readAsBytes(),
            saved: row['saved'] == true,
          ),
        );
      }
    }
    return result;
  }

  @override
  Future<void> write(List<ReferenceAsset> assets) async {
    final dir = await _directory;
    for (final asset in assets) {
      if (!_validId(asset.id)) throw const FormatException('Invalid asset ID');
      final file = File('${dir.path}/${asset.id}.png');
      if (!await file.exists()) {
        await file.writeAsBytes(asset.bytes, flush: true);
      }
    }
    final staging = File('${dir.path}/index.tmp');
    await staging.writeAsString(
      jsonEncode([
        for (final a in assets) {'id': a.id, 'saved': a.saved},
      ]),
      flush: true,
    );
    await staging.rename('${dir.path}/index.json');
    final keep = {
      for (final a in assets) '${a.id}.png',
      'index.json',
      'template-favorites.json',
    };
    await for (final file in dir.list()) {
      if (file is File && !keep.contains(file.uri.pathSegments.last)) {
        try {
          await file.delete();
        } on FileSystemException {
          /* Retry cleanup on next write. */
        }
      }
    }
  }

  @override
  Future<Set<String>> loadTemplateFavorites() async {
    final file = File('${(await _directory).path}/template-favorites.json');
    if (!await file.exists()) return {};
    final data = jsonDecode(await file.readAsString());
    if (data is! List) return {};
    return {
      for (final id in data)
        if (id is String && _validTemplateId(id)) id,
    };
  }

  @override
  Future<void> writeTemplateFavorites(Set<String> ids) async {
    if (ids.any((id) => !_validTemplateId(id))) {
      throw const FormatException('Invalid template ID');
    }
    final dir = await _directory;
    final staging = File('${dir.path}/template-favorites.tmp');
    await staging.writeAsString(jsonEncode(ids.toList()..sort()), flush: true);
    await staging.rename('${dir.path}/template-favorites.json');
  }
}
