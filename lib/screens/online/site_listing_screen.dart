import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/site_models.dart';
import '../../services/site_adapters/site_adapter.dart';
import '../../services/site_registry.dart';

/// 把异常压成一句话——Dio 的默认 toString 会贴一大段英文和文档链接，
/// 直接显示给用户体验很差。
String _humanizeError(Object e) {
  if (e is DioException) {
    final status = e.response?.statusCode;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '网络超时';
      case DioExceptionType.connectionError:
        return '无法连接到服务器';
      case DioExceptionType.badCertificate:
        return '证书校验失败';
      case DioExceptionType.cancel:
        return '请求已取消';
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        return status != null ? '服务器返回 $status' : '请求失败';
    }
  }
  // Dart 的 Exception.toString() 默认是 "Exception: 内容"，去掉前缀更干净。
  final s = e.toString();
  final cleaned = s.startsWith('Exception: ') ? s.substring(11) : s;
  return cleaned.length > 200 ? '${cleaned.substring(0, 200)}…' : cleaned;
}

class SiteListingScreen extends StatefulWidget {
  const SiteListingScreen({super.key, required this.siteId});

  final String siteId;

  @override
  State<SiteListingScreen> createState() => _SiteListingScreenState();
}

class _SiteListingScreenState extends State<SiteListingScreen> {
  late final SiteAdapter _adapter;
  Future<List<SiteCategory>>? _categoriesFuture;
  final ScrollController _scroll = ScrollController();

  String? _selectedCategory;
  final List<VideoSummary> _items = [];
  int _page = 0; // 已加载到的最大页码；首次 _load() 会推到 1。
  bool _loadingInitial = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;
  // 防止过期请求覆盖：每次 reset 自增；回调里发现 != 当前值就丢弃。
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _adapter = context.read<SiteRegistry>().requireById(widget.siteId);
    _categoriesFuture = _adapter.fetchCategories();
    _scroll.addListener(_onScroll);
    _reset();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    // 距底部 < 400px 触发下一页
    if (p.pixels >= p.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _reset() async {
    _generation++;
    final gen = _generation;
    setState(() {
      _items.clear();
      _page = 0;
      _loadingInitial = true;
      _loadingMore = false;
      _hasMore = true;
      _error = null;
    });
    await _fetch(gen, isInitial: true);
  }

  Future<void> _loadMore() async {
    if (_loadingInitial || _loadingMore || !_hasMore || _error != null) return;
    final gen = _generation;
    setState(() => _loadingMore = true);
    await _fetch(gen, isInitial: false);
  }

  Future<void> _fetch(int gen, {required bool isInitial}) async {
    final nextPage = _page + 1;
    try {
      final newItems = await _adapter.fetchListing(
        categoryId: _selectedCategory,
        page: nextPage,
      );
      if (!mounted || gen != _generation) return;
      setState(() {
        _items.addAll(newItems);
        _page = nextPage;
        _hasMore = newItems.isNotEmpty;
        _loadingInitial = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        if (isInitial) {
          _error = e;
        }
        _loadingInitial = false;
        _loadingMore = false;
        // 加载更多失败不锁死分页：用户可继续滚动重试。但当次不要立刻再次触发，
        // 等用户主动滚或下拉刷新。
      });
    }
  }

  void _selectCategory(String? id) {
    if (id == _selectedCategory) return;
    setState(() => _selectedCategory = id);
    _reset();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(
          _adapter.info.name,
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () =>
                context.push('/online/site/${widget.siteId}/search'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _reset,
          ),
        ],
      ),
      body: Column(
        children: [
          _CategoryBar(
            future: _categoriesFuture,
            selected: _selectedCategory,
            onSelect: _selectCategory,
          ),
          const Divider(height: 1, color: Colors.white10),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loadingInitial) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error != null && _items.isEmpty) {
      return _Error(
        message: '加载失败：${_humanizeError(_error!)}',
        onRetry: _reset,
      );
    }
    if (_items.isEmpty) {
      return _Error(message: '没拉到内容', onRetry: _reset);
    }
    return RefreshIndicator(
      onRefresh: _reset,
      child: GridView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(8),
        gridDelegate: _gridDelegate(_adapter.cardAspectRatio),
        // 多加 1 个 cell 给底部 footer（加载中/到底了）。
        itemCount: _items.length + 1,
        itemBuilder: (ctx, i) {
          if (i == _items.length) {
            return _GridFooter(
              loading: _loadingMore,
              hasMore: _hasMore,
            );
          }
          final v = _items[i];
          return _VideoCard(
            summary: v,
            thumbHeaders: _adapter.thumbHeaders(),
            aspectRatio: _adapter.cardAspectRatio,
            imageFit: _adapter.cardImageFit,
            onTap: () => context.push(
              '/online/site/${widget.siteId}/detail',
              extra: v,
            ),
          );
        },
      ),
    );
  }
}

/// 按缩略图比例返回 grid delegate。
/// 卡片高度 ≈ width / thumbAspect + 文字区（2 行标题 ~32 + 副标题 ~14 + 间距 ~8 = 54）。
/// SliverGridDelegate 拿到的是单元格宽高比，所以反推：
///   cellAspect = width / (width / thumbAspect + textPx)
/// 用 width = maxExtent 估算（实际 width 会更小，留点余量）。
SliverGridDelegateWithMaxCrossAxisExtent _gridDelegate(double thumbAspect) {
  final isLandscape = thumbAspect >= 1.0;
  final maxExtent = isLandscape ? 220.0 : 140.0;
  const textPx = 56.0;
  final thumbHeight = maxExtent / thumbAspect;
  final cellAspect = maxExtent / (thumbHeight + textPx);
  return SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: maxExtent,
    mainAxisSpacing: 10,
    crossAxisSpacing: 8,
    childAspectRatio: cellAspect,
  );
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.future,
    required this.selected,
    required this.onSelect,
  });

  final Future<List<SiteCategory>>? future;
  final String? selected;
  final void Function(String?) onSelect;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SiteCategory>>(
      future: future,
      builder: (context, snap) {
        final cats = snap.data ?? const [];
        if (cats.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            itemCount: cats.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (ctx, i) {
              if (i == 0) {
                return _Chip(
                  label: '全部',
                  selected: selected == null,
                  onTap: () => onSelect(null),
                );
              }
              final c = cats[i - 1];
              return _Chip(
                label: c.name,
                selected: selected == c.id,
                onTap: () => onSelect(c.id),
              );
            },
          ),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.redAccent : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? Colors.white : Colors.white70,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({
    required this.summary,
    required this.thumbHeaders,
    required this.aspectRatio,
    required this.imageFit,
    required this.onTap,
  });

  final VideoSummary summary;
  final Map<String, String> thumbHeaders;
  final double aspectRatio;
  final BoxFit imageFit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 用 contain 时，多出来的区域用卡片底色填充，避免黑边突兀。
    const placeholderColor = Color(0xFF1A1A1A);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: aspectRatio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                color: placeholderColor,
                child: summary.thumb == null
                    ? const Center(
                        child: Icon(Icons.image_not_supported,
                            color: Colors.white24),
                      )
                    : Image.network(
                        summary.thumb!,
                        headers: thumbHeaders,
                        fit: imageFit,
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(Icons.broken_image,
                              color: Colors.white24),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            summary.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, height: 1.2),
          ),
          if (summary.subtitle != null)
            Text(
              summary.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Colors.white54),
            ),
        ],
      ),
    );
  }
}

class _GridFooter extends StatelessWidget {
  const _GridFooter({required this.loading, required this.hasMore});

  final bool loading;
  final bool hasMore;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (!hasMore) {
      return const Center(
        child: Text(
          '— 已经到底了 —',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
