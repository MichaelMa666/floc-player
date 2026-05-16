import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/site_models.dart';
import '../../services/site_adapters/site_adapter.dart';
import '../../services/site_registry.dart';

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
  final s = e.toString();
  final cleaned = s.startsWith('Exception: ') ? s.substring(11) : s;
  return cleaned.length > 200 ? '${cleaned.substring(0, 200)}…' : cleaned;
}

class SiteSearchScreen extends StatefulWidget {
  const SiteSearchScreen({super.key, required this.siteId});

  final String siteId;

  @override
  State<SiteSearchScreen> createState() => _SiteSearchScreenState();
}

class _SiteSearchScreenState extends State<SiteSearchScreen> {
  late final SiteAdapter _adapter;
  final _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  Timer? _debounce;

  String _query = '';
  final List<VideoSummary> _items = [];
  int _page = 0;
  bool _loadingInitial = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _adapter = context.read<SiteRegistry>().requireById(widget.siteId);
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    if (p.pixels >= p.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _trigger(value));
  }

  void _trigger(String value) {
    final q = value.trim();
    if (q == _query) return;
    _query = q;
    _reset();
  }

  Future<void> _reset() async {
    _generation++;
    final gen = _generation;
    setState(() {
      _items.clear();
      _page = 0;
      _hasMore = true;
      _error = null;
      _loadingMore = false;
      _loadingInitial = _query.isNotEmpty;
    });
    if (_query.isEmpty) return;
    await _fetch(gen, isInitial: true);
  }

  Future<void> _loadMore() async {
    if (_loadingInitial || _loadingMore || !_hasMore || _error != null) return;
    if (_query.isEmpty) return;
    final gen = _generation;
    setState(() => _loadingMore = true);
    await _fetch(gen, isInitial: false);
  }

  Future<void> _fetch(int gen, {required bool isInitial}) async {
    final nextPage = _page + 1;
    try {
      final newItems = await _adapter.search(_query, page: nextPage);
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
        if (isInitial) _error = e;
        _loadingInitial = false;
        _loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: _trigger,
          decoration: InputDecoration(
            hintText: '在 ${_adapter.info.name} 内搜索',
            border: InputBorder.none,
            suffixIcon: _ctrl.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _ctrl.clear();
                      _trigger('');
                    },
                  ),
          ),
          style: const TextStyle(fontSize: 16),
        ),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_query.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '输入关键词搜索 ${_adapter.info.name}',
            style: const TextStyle(color: Colors.white54),
          ),
        ),
      );
    }
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '搜索失败：${_humanizeError(_error!)}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54),
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('没找到相关内容', style: TextStyle(color: Colors.white54)),
        ),
      );
    }
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(8),
      gridDelegate: _gridDelegate(_adapter.cardAspectRatio),
      itemCount: _items.length + 1,
      itemBuilder: (ctx, i) {
        if (i == _items.length) {
          return _GridFooter(loading: _loadingMore, hasMore: _hasMore);
        }
        final v = _items[i];
        return _SearchCard(
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
    );
  }
}

SliverGridDelegateWithMaxCrossAxisExtent _gridDelegate(double thumbAspect) {
  final isLandscape = thumbAspect >= 1.0;
  final maxExtent = isLandscape ? 220.0 : 140.0;
  const textPx = 44.0; // 搜索卡只有标题，没有副标题
  final thumbHeight = maxExtent / thumbAspect;
  final cellAspect = maxExtent / (thumbHeight + textPx);
  return SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: maxExtent,
    mainAxisSpacing: 10,
    crossAxisSpacing: 8,
    childAspectRatio: cellAspect,
  );
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({
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
