import 'dart:convert';
import 'package:flutter/services.dart';

class ReferenceTemplate {
  const ReferenceTemplate({
    required this.id,
    required this.category,
    required this.gender,
    required this.width,
    required this.height,
    required this.bytes,
    required this.asset,
    required this.sha256,
  });

  final String id;
  final String category;
  final String gender;
  final int width;
  final int height;
  final int bytes;
  final String asset;
  final String sha256;

  Future<Uint8List> loadBytes() async {
    final data = await rootBundle.load(asset);
    return Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }
}

class ReferenceCatalog {
  ReferenceCatalog._(this.templates);

  final List<ReferenceTemplate> templates;
  static ReferenceCatalog? _loaded;

  static Future<ReferenceCatalog> load() async {
    final cached = _loaded;
    if (cached != null) return cached;
    final manifest = jsonDecode(
      await rootBundle.loadString('assets/reference_templates/catalog.json'),
    );
    if (manifest is! Map || manifest['items'] is! List) {
      throw const FormatException('Invalid reference template catalog');
    }
    final templates = <ReferenceTemplate>[];
    final ids = <String>{};
    for (final row in manifest['items'] as List) {
      if (row is! Map) throw const FormatException('Invalid template row');
      final id = row['id'],
          category = row['category'],
          gender = row['gender'],
          width = row['width'],
          height = row['height'],
          bytes = row['bytes'],
          asset = row['asset'],
          sha256 = row['sha256'];
      if (id is! String ||
          !RegExp(
            r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
          ).hasMatch(id) ||
          !ids.add(id) ||
          category is! String ||
          gender is! String ||
          (gender != 'female' && gender != 'male') ||
          width is! int ||
          height is! int ||
          bytes is! int ||
          asset is! String ||
          !asset.startsWith('assets/reference_templates/') ||
          sha256 is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
        throw const FormatException('Invalid template metadata');
      }
      templates.add(
        ReferenceTemplate(
          id: id,
          category: category,
          gender: gender,
          width: width,
          height: height,
          bytes: bytes,
          asset: asset,
          sha256: sha256,
        ),
      );
    }
    return _loaded = ReferenceCatalog._(List.unmodifiable(templates));
  }

  List<ReferenceTemplate> filter({
    String? category,
    String? gender,
    Set<String> favorites = const {},
    bool favoritesOnly = false,
  }) => [
    for (final template in templates)
      if ((category == null || template.category == category) &&
          (gender == null || template.gender == gender) &&
          (!favoritesOnly || favorites.contains(template.id)))
        template,
  ];
}
