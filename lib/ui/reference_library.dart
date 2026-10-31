import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/reference_catalog.dart';
import '../services/references.dart';
import 'guides.dart';

class ReferenceLibrarySheet extends StatefulWidget {
  const ReferenceLibrarySheet({
    super.key,
    required this.library,
    required this.onSelected,
  });
  final ReferenceLibrary library;
  final VoidCallback onSelected;

  @override
  State<ReferenceLibrarySheet> createState() => _ReferenceLibrarySheetState();
}

class _ReferenceLibrarySheetState extends State<ReferenceLibrarySheet> {
  static const _categories = [
    (null, '全部'),
    ('Selfies', '自拍'),
    ('Mirror pics', '镜自拍'),
    ('Gym', '健身'),
    ('Sitting', '坐姿'),
    ('Standing', '站姿'),
  ];
  late Future<ReferenceCatalog> _catalog;
  String? _category;
  String? _gender;
  bool _favoritesOnly = false;
  final _imagesScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _catalog = ReferenceCatalog.load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.library.load());
    });
  }

  @override
  void dispose() {
    _imagesScroll.dispose();
    super.dispose();
  }

  void _changeFilters(VoidCallback change) {
    setState(change);
    if (_imagesScroll.hasClients) _imagesScroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .82,
      child: ListenableBuilder(
        listenable: widget.library,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 14, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('姿势参考', style: TextStyle(fontSize: 20)),
                  ),
                  TextButton.icon(
                    key: const Key('import-reference'),
                    onPressed: widget.library.busy ? null : _import,
                    style: TextButton.styleFrom(
                      overlayColor: Colors.transparent,
                      splashFactory: NoSplash.splashFactory,
                    ),
                    icon: const Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 18,
                    ),
                    label: const Text('导入图片'),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 22),
              child: Text(
                '选一张参考图，叠在取景画面上对照摆姿。',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ),
            if (widget.library.busy)
              const LinearProgressIndicator(minHeight: 2),
            if (widget.library.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.library.error!,
                        style: const TextStyle(color: acid, fontSize: 12),
                      ),
                    ),
                    if (!widget.library.loaded)
                      TextButton(
                        onPressed: widget.library.busy
                            ? null
                            : widget.library.load,
                        child: const Text('重试'),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: FutureBuilder<ReferenceCatalog>(
                future: _catalog,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: TextButton(
                        onPressed: () =>
                            setState(() => _catalog = ReferenceCatalog.load()),
                        child: const Text('内置图库读取失败，点击重试'),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(
                      child: Text(
                        '正在读取内置图库…',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    );
                  }
                  return _contents(snapshot.data!);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
              child: Text(
                kIsWeb ? '内置照片离线可用 · 个人导入仅在本次会话保留' : '内置照片离线可用 · 个人导入仅存在本机',
                style: const TextStyle(color: muted, fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _section(Widget child) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: child,
    ),
  );

  Widget _contents(ReferenceCatalog catalog) {
    final templates = catalog.filter(
      category: _category,
      gender: _gender,
      favorites: widget.library.templateFavorites,
      favoritesOnly: _favoritesOnly,
    );
    final saved = widget.library.assets.where((asset) => asset.saved).toList();
    return Column(
      children: [
        Padding(
          key: const Key('reference-library-filters'),
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: _filters(templates.length),
        ),
        Expanded(
          child: CustomScrollView(
            key: const Key('reference-library-list'),
            controller: _imagesScroll,
            slivers: [
              if (templates.isEmpty)
                _section(
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 14, 6, 8),
                    child: Text(
                      _favoritesOnly ? '还没有收藏姿势' : '没有符合条件的姿势',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: _templateGrid(templates),
                ),
              _section(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        _heading('我的参考图'),
                        const Spacer(),
                        Text(
                          '${widget.library.assets.length}/20',
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (saved.isNotEmpty) ...[
                _section(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [const SizedBox(height: 2), _subheading('已收藏')],
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: _localGrid(saved),
                ),
              ],
              if (widget.library.assets.isNotEmpty) ...[
                _section(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [const SizedBox(height: 12), _subheading('最近导入')],
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: _localGrid(widget.library.assets),
                ),
              ] else
                _section(
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
                    child: Text(
                      '导入的照片只保存在本机，不会上传。',
                      style: TextStyle(
                        color: muted.withValues(alpha: .8),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filters(int count) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          _heading('内置姿势'),
          const Spacer(),
          Text('$count 张', style: const TextStyle(color: muted, fontSize: 11)),
        ],
      ),
      const SizedBox(height: 2),
      SizedBox(
        height: 42,
        child: ListView.separated(
          key: const Key('reference-category-row'),
          scrollDirection: Axis.horizontal,
          itemCount: _categories.length,
          separatorBuilder: (_, _) => const SizedBox(width: 7),
          itemBuilder: (context, index) {
            final (value, label) = _categories[index];
            return _choice(
              key: ValueKey('reference-category-$index'),
              label: label,
              selected: _category == value,
              onSelected: () => _changeFilters(() => _category = value),
            );
          },
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 42,
        child: SingleChildScrollView(
          key: const Key('reference-gender-row'),
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (value, label) in const [
                (null, '全部'),
                ('male', '男'),
                ('female', '女'),
              ]) ...[
                _choice(
                  key: ValueKey('reference-gender-$label'),
                  label: label,
                  selected: _gender == value,
                  onSelected: () => _changeFilters(() => _gender = value),
                ),
                const SizedBox(width: 7),
              ],
              FilterChip(
                key: const Key('reference-favorites-filter'),
                selected: _favoritesOnly,
                showCheckmark: false,
                avatar: Icon(
                  _favoritesOnly ? Icons.favorite : Icons.favorite_border,
                  size: 16,
                  color: _favoritesOnly ? ink : paper,
                ),
                label: const Text('收藏'),
                onSelected: (value) =>
                    _changeFilters(() => _favoritesOnly = value),
                selectedColor: paper,
                backgroundColor: const Color(0xFF19171D),
                side: BorderSide(
                  color: _favoritesOnly ? paper : const Color(0xFF302D34),
                ),
                labelStyle: TextStyle(
                  color: _favoritesOnly ? ink : paper,
                  fontSize: 12,
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
    ],
  );

  Widget _choice({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) => ChoiceChip(
    key: key,
    label: Text(label),
    selected: selected,
    showCheckmark: false,
    onSelected: (_) => onSelected(),
    selectedColor: paper,
    backgroundColor: const Color(0xFF19171D),
    side: BorderSide(color: selected ? paper : const Color(0xFF302D34)),
    labelStyle: TextStyle(
      color: selected ? ink : paper,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
  );

  Future<void> _import() async {
    final previous = widget.library.selected;
    await widget.library.importImage();
    if (mounted &&
        widget.library.selected != null &&
        widget.library.selected != previous &&
        widget.library.error == null) {
      widget.onSelected();
    }
  }

  Future<void> _selectTemplate(ReferenceTemplate template) async {
    try {
      final bytes = await template.loadBytes();
      if (!mounted) return;
      widget.library.selectTemplate(template.id, bytes);
      widget.onSelected();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('这张姿势照片暂时无法打开')));
      }
    }
  }

  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.only(left: 6, bottom: 8),
    child: Text(title, style: const TextStyle(fontSize: 14)),
  );

  Widget _subheading(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
    child: Text(title, style: const TextStyle(color: muted, fontSize: 11)),
  );

  Widget _templateGrid(List<ReferenceTemplate> templates) => SliverGrid.builder(
    key: const Key('reference-template-grid'),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: .75,
    ),
    itemCount: templates.length,
    itemBuilder: (context, index) {
      final template = templates[index];
      final selected = widget.library.selected?.id == template.id;
      final saved = widget.library.templateFavorites.contains(template.id);
      return Material(
        color: const Color(0xFF242D25),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InkWell(
              key: ValueKey('reference-template-${template.id}'),
              onTap: widget.library.busy
                  ? null
                  : () => _selectTemplate(template),
              child: Image.asset(
                template.asset,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined),
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(7),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .68),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    child: Text(
                      _categoryName(template.category),
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
              ),
            ),
            if (selected)
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: acid, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            Positioned(
              top: 4,
              right: 4,
              child: Material(
                color: Colors.black.withValues(alpha: .48),
                shape: const CircleBorder(),
                child: IconButton(
                  key: ValueKey('template-favorite-${template.id}'),
                  tooltip: saved ? '取消收藏' : '收藏姿势',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 38,
                    height: 38,
                  ),
                  onPressed: widget.library.busy
                      ? null
                      : () => widget.library.setTemplateSaved(
                          template.id,
                          !saved,
                        ),
                  icon: Icon(
                    saved ? Icons.favorite : Icons.favorite_border,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  String _categoryName(String category) => switch (category) {
    'Selfies' => '自拍',
    'Mirror pics' => '镜自拍',
    'Gym' => '健身',
    'Sitting' => '坐姿',
    'Standing' => '站姿',
    _ => category,
  };

  Widget _localGrid(List<ReferenceAsset> assets) => SliverGrid.builder(
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: .75,
    ),
    itemCount: assets.length,
    itemBuilder: (context, index) {
      final asset = assets[index];
      final selected = widget.library.selected?.id == asset.id;
      return Material(
        color: const Color(0xFF242D25),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InkWell(
              key: ValueKey('reference-${asset.id}'),
              onTap: widget.library.busy
                  ? null
                  : () {
                      widget.library.select(asset);
                      widget.onSelected();
                    },
              child: Image.memory(
                asset.bytes,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined),
              ),
            ),
            if (selected)
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: acid, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            Positioned(
              top: 0,
              right: 0,
              child: PopupMenuButton<String>(
                tooltip: '管理参考图',
                enabled: !widget.library.busy,
                icon: const Icon(
                  Icons.more_horiz,
                  color: Colors.white,
                  shadows: [Shadow(blurRadius: 4)],
                ),
                onSelected: (value) async {
                  if (value == 'save') {
                    await widget.library.setSaved(asset, !asset.saved);
                  }
                  if (value == 'delete') {
                    await widget.library.remove(asset);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'save',
                    child: Text(asset.saved ? '取消收藏' : '收藏参考图'),
                  ),
                  const PopupMenuItem(value: 'delete', child: Text('删除参考图')),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
