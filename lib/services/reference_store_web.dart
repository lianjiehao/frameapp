import 'reference_store_api.dart';
export 'reference_store_api.dart';

// Practice references live only in this browser session.
ReferenceStore createReferenceStore() => _MemoryReferenceStore();

class _MemoryReferenceStore implements ReferenceStore {
  List<ReferenceAsset> _assets = [];
  Set<String> _templateFavorites = {};
  @override
  Future<List<ReferenceAsset>> load() async => List.of(_assets);
  @override
  Future<void> write(List<ReferenceAsset> assets) async {
    _assets = List.of(assets);
  }

  @override
  Future<Set<String>> loadTemplateFavorites() async =>
      Set.of(_templateFavorites);

  @override
  Future<void> writeTemplateFavorites(Set<String> ids) async {
    _templateFavorites = Set.of(ids);
  }
}
