import 'dart:typed_data';

class ReferenceAsset {
  const ReferenceAsset(this.id, this.bytes, {this.saved = false});
  final String id;
  final Uint8List bytes;
  final bool saved;
  ReferenceAsset withSaved(bool value) =>
      ReferenceAsset(id, bytes, saved: value);
}

abstract interface class ReferenceStore {
  Future<List<ReferenceAsset>> load();
  Future<void> write(List<ReferenceAsset> assets);
  Future<Set<String>> loadTemplateFavorites();
  Future<void> writeTemplateFavorites(Set<String> ids);
}
