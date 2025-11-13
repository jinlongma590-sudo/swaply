// lib/services/listing_events_bus.dart
import 'dart:async';

/// 发布成功事件（可带新商品ID，便于后续做插入动画/定位）
class ListingPublishedEvent {
  final String? listingId;
  ListingPublishedEvent([this.listingId]);
}

/// 轻量全局事件总线：广播“发布成功”，Home 收到后强制刷新（绕过缓存）
class ListingEventsBus {
  ListingEventsBus._();
  static final ListingEventsBus instance = ListingEventsBus._();

  final _controller = StreamController<dynamic>.broadcast();

  /// 外部只读流（Home 订阅）
  Stream<dynamic> get stream => _controller.stream;

  /// 发布完成后调用：ListingEventsBus.instance.emitPublished(newId);
  void emitPublished([String? listingId]) {
    // 可留一条简单的调试日志，现场排查用
    // ignore: avoid_print
    print('[ListingEventsBus] emit ListingPublishedEvent id=$listingId');
    _controller.add(ListingPublishedEvent(listingId));
  }

  void dispose() {
    _controller.close();
  }
}
