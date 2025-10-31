// lib/pages/search_results_page.dart
import 'package:flutter/material.dart';
import 'package:swaply/services/listing_service.dart';
import 'package:swaply/pages/product_detail_page.dart';

class SearchResultsPage extends StatefulWidget {
  final String keyword; // 由首页传入
  final String? location; // 可选：城市筛选（'All Zimbabwe' 表示不过滤）

  const SearchResultsPage({
    Key? key,
    required this.keyword,
    this.location,
  }) : super(key: key);

  @override
  State<SearchResultsPage> createState() => _SearchResultsPageState();
}

class _SearchResultsPageState extends State<SearchResultsPage> {
  final List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _items.clear();
    });

    try {
      final kw = widget.keyword.trim();
      if (kw.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      final city = (widget.location != null &&
              widget.location!.isNotEmpty &&
              widget.location != 'All Zimbabwe')
          ? widget.location
          : null;

      // 只云端搜索：后端 title/description ilike，已对齐你项目的 API
      final rows = await ListingService.search(
        keyword: kw,
        city: city,
        limit: 100,
        offset: 0,
      );

      _items.addAll(rows.map(_mapRowToCard));
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _mapRowToCard(Map<String, dynamic> r) {
    final num? priceNum = r['price'] is num ? (r['price'] as num) : null;
    final priceText = priceNum != null
        ? '\$${priceNum.toStringAsFixed(0)}'
        : (r['price']?.toString() ?? '');

    // 统一读取图片（兼容 images / image_urls）
    final imgs = ListingService.readImages(r);

    return {
      'id': r['id'],
      'title': r['title'] ?? '',
      'price': priceText,
      'location': r['city'] ?? '',
      'images': imgs,
      'postedDate': r['created_at'] ?? r['posted_at'],
      'full': r,
    };
  }

  void _openDetail(Map<String, dynamic> item) {
    final full = (item['full'] as Map?) ?? {};
    final images = (item['images'] as List?) ?? [];

    final pdData = {
      'id': item['id'],
      'title': item['title'],
      'price': item['price'],
      'location': item['location'],
      'images': images,
      'postedDate': item['postedDate'] ?? full['created_at'],
      'description': full['description'] ?? '',
      'sellerName': full['name'] ?? '',
      'sellerPhone': full['phone'] ?? '',
      'category': full['category'] ?? '',
    };

    // ✅ 跳转逻辑保持不变
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailPage(
          productId: item['id']?.toString(),
          productData: pdData,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = 'Results for "${widget.keyword}"';

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: const Color(0xFF2196F3),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text('Load failed: $_error',
                      style: const TextStyle(color: Colors.red)),
                )
              : _items.isEmpty
                  ? const Center(child: Text('No results'))
                  : Column(
                      children: [
                        Container(
                          alignment: Alignment.centerLeft,
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          color: Colors.grey[50],
                          child: Text(
                            '${_items.length} ads found',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 14),
                          ),
                        ),
                        Expanded(
                          child: GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.75,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                            itemCount: _items.length,
                            itemBuilder: (_, i) {
                              final p = _items[i];
                              return GestureDetector(
                                onTap: () => _openDetail(p),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withAlpha(20),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                  top: Radius.circular(14)),
                                          child: _thumb(p),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              p['price']?.toString() ?? '',
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              p['title']?.toString() ?? '',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style:
                                                  const TextStyle(fontSize: 14),
                                            ),
                                            const SizedBox(height: 3),
                                            Row(
                                              children: [
                                                const Icon(Icons.location_on,
                                                    size: 12,
                                                    color: Colors.grey),
                                                const SizedBox(width: 2),
                                                Expanded(
                                                  child: Text(
                                                    p['location']?.toString() ??
                                                        '',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _thumb(Map<String, dynamic> p) {
    final imgs = p['images'];
    if (imgs is List && imgs.isNotEmpty) {
      final first = imgs.first.toString();
      if (first.startsWith('http')) {
        return Image.network(first,
            fit: BoxFit.cover, errorBuilder: (_, __, ___) => _imgPlaceholder());
      } else {
        return Image.asset(first,
            fit: BoxFit.cover, errorBuilder: (_, __, ___) => _imgPlaceholder());
      }
    }
    return _imgPlaceholder();
  }

  Widget _imgPlaceholder() => Container(
        color: Colors.grey[300],
        child: const Icon(Icons.image, size: 50, color: Colors.grey),
      );
}
