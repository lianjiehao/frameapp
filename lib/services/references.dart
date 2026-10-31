import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'reference_store.dart';
export 'reference_store_api.dart';

typedef ReferencePicker = Future<Uint8List?> Function();

Future<Uint8List?> pickReferenceImage({ImagePicker? picker}) async {
  picker ??= ImagePicker();
  XFile? file;
  // Recover only on an explicit import, after consent, if Android killed the
  // previous picker activity. This never opens another permission prompt.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final lost = await picker.retrieveLostData();
    if (lost.exception != null) throw lost.exception!;
    file = lost.files?.firstOrNull ?? lost.file;
  }
  file ??= await picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 1600,
    maxHeight: 1600,
    requestFullMetadata: false,
  );
  if (file == null) return null;
  if (await file.length() > 25 * 1024 * 1024) {
    throw const FormatException('Image too large');
  }
  return file.readAsBytes();
}

class ReferenceLibrary extends ChangeNotifier {
  static const importHintSeenKey = 'frame.pose.importHintSeen';
  ReferenceLibrary({ReferenceStore? store, ReferencePicker? picker})
    : _store = store ?? createReferenceStore(),
      _picker = picker ?? pickReferenceImage;
  final ReferenceStore _store;
  final ReferencePicker _picker;
  List<ReferenceAsset> _assets = [];
  List<ReferenceAsset> get assets => List.unmodifiable(_assets);
  Set<String> _templateFavorites = {};
  Set<String> get templateFavorites => Set.unmodifiable(_templateFavorites);
  ReferenceAsset? selected;
  double opacity = .45;
  bool mirror = false, visible = true, busy = false;
  bool _disposed = false, _loaded = false;
  bool get loaded => _loaded;
  int _epoch = 0;
  String? error;
  bool _importHintSeen = false;

  Future<bool> needsImportHint() async {
    if (_disposed || _importHintSeen) return false;
    try {
      final preferences = await SharedPreferences.getInstance();
      return !_disposed &&
          !_importHintSeen &&
          preferences.getBool(importHintSeenKey) != true;
    } catch (_) {
      return !_disposed && !_importHintSeen;
    }
  }

  Future<void> markImportHintSeen() async {
    if (_disposed) return;
    _importHintSeen = true;
    try {
      await (await SharedPreferences.getInstance()).setBool(
        importHintSeenKey,
        true,
      );
    } catch (_) {
      // Keep the hint usable if preferences are temporarily unavailable.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    if (_loaded || busy || _disposed) return;
    busy = true;
    final epoch = _epoch;
    _notify();
    try {
      final assets = await _store.load();
      final templateFavorites = await _store.loadTemplateFavorites();
      if (_disposed || epoch != _epoch) return;
      _assets = assets;
      _templateFavorites = templateFavorites;
      _loaded = true;
      error = null;
    } catch (_) {
      if (!_disposed && epoch == _epoch) error = '参考图库读取失败，请重试';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> importImage() async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    final epoch = _epoch;
    _notify();
    try {
      // Finish the first disk read before changing the existing library.
      if (!_loaded) {
        final assets = await _store.load();
        final templateFavorites = await _store.loadTemplateFavorites();
        if (_disposed || epoch != _epoch) return;
        _assets = assets;
        _templateFavorites = templateFavorites;
        _loaded = true;
      }
      if (_disposed || epoch != _epoch) return;
      final bytes = await _picker();
      if (bytes == null || _disposed || epoch != _epoch) return;
      if (bytes.isEmpty || bytes.length > 25 * 1024 * 1024) {
        throw const FormatException('Invalid image');
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      ui.ImageDescriptor? descriptor;
      ui.Codec? codec;
      ui.Image? image;
      late Uint8List normalized;
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        final maxSide = descriptor.width > descriptor.height
            ? descriptor.width
            : descriptor.height;
        final ratio = maxSide > 1600 ? 1600 / maxSide : 1.0;
        codec = await descriptor.instantiateCodec(
          targetWidth: (descriptor.width * ratio).round().clamp(1, 1600),
          targetHeight: (descriptor.height * ratio).round().clamp(1, 1600),
        );
        image = (await codec.getNextFrame()).image;
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw const FormatException('Unable to decode');
        normalized = data.buffer.asUint8List();
      } finally {
        image?.dispose();
        codec?.dispose();
        descriptor?.dispose();
        buffer.dispose();
      }
      if (_disposed || epoch != _epoch) return;
      final id = sha256.convert(normalized).toString();
      final old = _assets.where((a) => a.id == id).firstOrNull;
      final asset = ReferenceAsset(id, normalized, saved: old?.saved ?? false);
      final next = [asset, ..._assets.where((a) => a.id != id)];
      if (next.length > 20) {
        final removable = next.lastIndexWhere((a) => !a.saved && a.id != id);
        if (removable < 0) {
          error = '图库已满，请先删除一张参考图';
          return;
        }
        next.removeAt(removable);
      }
      await _store.write(next);
      if (_disposed || epoch != _epoch) return;
      _assets = next;
      selected = asset;
      mirror = false;
      visible = true;
    } catch (_) {
      if (!_disposed && epoch == _epoch) error = '图片导入失败，请选择有效图片后重试';
    } finally {
      busy = false;
      _notify();
    }
  }

  void select(ReferenceAsset asset) {
    if (busy || _disposed || !_assets.any((a) => a.id == asset.id)) return;
    selected = asset;
    mirror = false;
    visible = true;
    _notify();
  }

  void selectTemplate(String id, Uint8List bytes) {
    if (busy || _disposed || bytes.isEmpty) return;
    selected = ReferenceAsset(
      id,
      bytes,
      saved: _templateFavorites.contains(id),
    );
    mirror = false;
    visible = true;
    _notify();
  }

  Future<void> setTemplateSaved(String id, bool saved) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    final epoch = _epoch;
    _notify();
    final next = Set<String>.of(_templateFavorites);
    if (saved) {
      next.add(id);
    } else {
      next.remove(id);
    }
    try {
      await _store.writeTemplateFavorites(next);
      if (_disposed || epoch != _epoch) return;
      _templateFavorites = next;
      if (selected?.id == id) selected = selected!.withSaved(saved);
    } catch (_) {
      if (!_disposed && epoch == _epoch) error = '图库更新失败，请重试';
    } finally {
      busy = false;
      _notify();
    }
  }

  void setOpacity(double value) {
    if (!value.isFinite || _disposed) return;
    opacity = value.clamp(0, 1);
    _notify();
  }

  void toggleVisible() {
    if (_disposed || selected == null) return;
    visible = !visible;
    _notify();
  }

  void toggleMirror() {
    mirror = !mirror;
    _notify();
  }

  void clearSelection() {
    selected = null;
    _notify();
  }

  Future<void> setSaved(ReferenceAsset asset, bool saved) =>
      _change(asset, saved: saved);
  Future<void> remove(ReferenceAsset asset) => _change(asset, remove: true);
  Future<void> _change(
    ReferenceAsset asset, {
    bool? saved,
    bool remove = false,
  }) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    final epoch = _epoch;
    _notify();
    final next = [
      for (final a in _assets)
        if (!(remove && a.id == asset.id))
          a.id == asset.id && saved != null ? a.withSaved(saved) : a,
    ];
    try {
      await _store.write(next);
      if (_disposed || epoch != _epoch) return;
      _assets = next;
      if (selected?.id == asset.id) {
        if (remove) {
          selected = null;
        } else {
          selected = next.firstWhere((a) => a.id == asset.id);
        }
      }
    } catch (_) {
      if (!_disposed && epoch == _epoch) error = '图库更新失败，请重试';
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    selected = null;
    _assets = [];
    super.dispose();
  }
}
