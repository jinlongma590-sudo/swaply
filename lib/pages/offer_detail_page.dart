// lib/pages/offer_detail_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/services/message_service.dart';
import 'package:swaply/services/offer_service.dart';
import 'package:swaply/models/offer.dart';
// ✅ 关键操作守卫：未验证则引导验证
import 'package:swaply/services/verification_guard.dart';

class OfferDetailPage extends StatefulWidget {
  final String offerId;
  final Map<String, dynamic>? offerData;

  const OfferDetailPage({
    Key? key,
    required this.offerId,
    this.offerData,
  }) : super(key: key);

  @override
  State<OfferDetailPage> createState() => _OfferDetailPageState();
}

class _OfferDetailPageState extends State<OfferDetailPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Map<String, dynamic>? _offerDetails;
  List<Map<String, dynamic>> _messages = [];
  bool _isLoadingMessages = true;
  bool _isSendingMessage = false;
  String? _currentUserId;
  RealtimeChannel? _messageChannel;

  // ====== 新增：屏蔽状态 ======
  bool _iBlockedOther = false; // 我屏蔽了对方
  bool _otherBlockedMe = false; // 对方屏蔽了我
  bool get _blockedEitherWay => _iBlockedOther || _otherBlockedMe;

  @override
  void initState() {
    super.initState();
    _currentUserId = Supabase.instance.client.auth.currentUser?.id;
    _loadOfferDetails();
    _loadMessages();
    _subscribeToMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _unsubscribeFromMessages();
    super.dispose();
  }

  /// 加载报价详情
  Future<void> _loadOfferDetails() async {
    try {
      // 如果有预设数据就先用，同时异步加载完整数据
      if (widget.offerData != null) {
        setState(() => _offerDetails = widget.offerData);
        _refreshBlockStatus(); // 预置数据足够判断对方ID时，先查一次屏蔽状态
      }

      final details = await OfferService.getOfferDetails(widget.offerId);
      if (details != null && mounted) {
        setState(() => _offerDetails = details);
        _refreshBlockStatus(); // 详情返回后再查一次，确保准确
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading offer details: $e');
      }
    }
  }

  /// 加载消息历史
  Future<void> _loadMessages() async {
    try {
      setState(() => _isLoadingMessages = true);

      final messages = await MessageService.getOfferMessages(
        offerId: widget.offerId,
      );

      if (mounted) {
        setState(() {
          _messages = messages;
          _isLoadingMessages = false;
        });

        // 标记消息为已读
        if (_currentUserId != null) {
          await MessageService.markMessagesAsRead(
            offerId: widget.offerId,
            receiverId: _currentUserId!,
          );
        }

        // 滚动到底部
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading messages: $e');
      }
      if (mounted) {
        setState(() => _isLoadingMessages = false);
      }
    }
  }

  /// 订阅实时消息
  void _subscribeToMessages() {
    if (_messageChannel != null) return;

    _messageChannel = MessageService.subscribeToOfferMessages(
      offerId: widget.offerId,
      onMessageReceived: (message) {
        if (kDebugMode) {
          print('Received realtime message: ${message['message']}');
        }

        if (mounted) {
          setState(() {
            _messages.add(message);
          });

          // 如果是接收到的消息，标记为已读
          if (message['receiver_id'] == _currentUserId) {
            MessageService.markMessagesAsRead(
              offerId: widget.offerId,
              receiverId: _currentUserId!,
            );
          }

          // 滚动到底部
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottom();
          });
        }
      },
    );
  }

  /// 取消订阅消息
  void _unsubscribeFromMessages() {
    if (_messageChannel != null) {
      MessageService.unsubscribeFromMessages(_messageChannel!);
      _messageChannel = null;
    }
  }

  /// 新增：根据报价详情里的 buyer/seller 计算对方ID
  String? _getPeerId() {
    if (_offerDetails == null || _currentUserId == null) return null;
    final buyerId = _offerDetails!['buyer_id'] as String?;
    final sellerId = _offerDetails!['seller_id'] as String?;
    if (buyerId == null || sellerId == null) return null;
    return _currentUserId == buyerId ? sellerId : buyerId;
  }

  /// 新增：刷新屏蔽状态
  Future<void> _refreshBlockStatus() async {
    try {
      final me = _currentUserId;
      final peer = _getPeerId();
      if (me == null || peer == null) return;

      final status = await OfferService.getBlockStatusBetween(a: me, b: peer);
      if (!mounted) return;
      setState(() {
        _iBlockedOther = status.iBlockedOther;
        _otherBlockedMe = status.otherBlockedMe;
      });
    } catch (e) {
      if (kDebugMode) {
        print('[OfferDetailPage] Error refreshing block status: $e');
      }
    }
  }

  /// 发送消息（关键操作：未验证会被引导去验证；屏蔽会拦截）
  Future<void> _sendMessage() async {
    // ✅ 守卫：未登录/未验证则弹出引导并中断
    final allowed = await VerificationGuard.ensureVerifiedOrPrompt(
      context,
      feature: AppFeature.makeOffer,
    );
    if (!allowed) return;

    // ✅ 屏蔽拦截（双方任一方屏蔽即可拦截）
    if (_blockedEitherWay) {
      _showSnackBar(
        _otherBlockedMe
            ? 'You can’t send messages because this user has blocked you.'
            : 'You blocked this user. Unblock to send messages.',
        isError: true,
      );
      return;
    }

    final message = _messageController.text.trim();
    if (message.isEmpty || _isSendingMessage) return;

    if (_currentUserId == null || _offerDetails == null) return;

    setState(() => _isSendingMessage = true);

    try {
      // 确定接收者ID
      final buyerId = _offerDetails!['buyer_id'];
      final sellerId = _offerDetails!['seller_id'];
      final receiverId = _currentUserId == buyerId ? sellerId : buyerId;

      final result = await MessageService.sendMessage(
        offerId: widget.offerId,
        receiverId: receiverId,
        message: message,
      );

      if (result != null) {
        _messageController.clear();
        // 实时订阅会自动添加消息，这里不需要手动添加
      } else {
        _showSnackBar('发送消息失败，请重试', isError: true);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error sending message: $e');
      }
      _showSnackBar('发送消息时出现错误', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSendingMessage = false);
      }
    }
  }

  /// 滚动到底部
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// 显示提示信息
  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_rounded,
              color: Colors.white,
              size: 16.sp,
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(
                message,
                style: TextStyle(fontSize: 13.sp),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
        margin: EdgeInsets.all(12.w),
      ),
    );
  }

  /// 构建报价信息卡片
  Widget _buildOfferInfo() {
    if (_offerDetails == null) {
      return Card(
        margin: EdgeInsets.all(12.w),
        child: SizedBox(
          height: 120.h,
          child: Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667EEA)),
              strokeWidth: 2.5.w,
            ),
          ),
        ),
      );
    }

    final listing = _offerDetails!['listings'] as Map<String, dynamic>? ?? {};
    final offerAmount = _offerDetails!['offer_amount']?.toString() ?? '0';
    final originalPrice = listing['price']?.toString() ?? '0';
    final title = listing['title']?.toString() ?? 'Unknown Item';
    final status = _offerDetails!['status']?.toString() ?? 'pending';
    final offerStatus = OfferStatus.fromString(status);

    // 计算百分比
    final offer = double.tryParse(offerAmount) ?? 0;
    final original = double.tryParse(originalPrice.replaceAll('\$', '')) ?? 0;
    final percentage = original > 0 ? ((offer / original) * 100).round() : 0;

    return Card(
      margin: EdgeInsets.all(12.w),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 商品标题和状态 + 菜单
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 状态标签
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: Color(offerStatus.color).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(
                      color: Color(offerStatus.color).withOpacity(0.3),
                      width: 1.w,
                    ),
                  ),
                  child: Text(
                    offerStatus.displayText,
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                      color: Color(offerStatus.color),
                    ),
                  ),
                ),
                SizedBox(width: 6.w),
                // ⋯ 菜单（举报/屏蔽）
                _buildMoreMenu(),
              ],
            ),
            SizedBox(height: 12.h),

            // 报价信息
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Offer Amount',
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        '\$$offerAmount',
                        style: TextStyle(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF667EEA),
                        ),
                      ),
                    ],
                  ),
                  if (original > 0) ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Original Price',
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              '\$$original',
                              style: TextStyle(
                                fontSize: 14.sp,
                                color: Colors.grey.shade600,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                            SizedBox(width: 8.w),
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 6.w, vertical: 2.h),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(10.r),
                              ),
                              child: Text(
                                '$percentage%',
                                style: TextStyle(
                                  fontSize: 10.sp,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 新增：右上角 ⋯ 菜单
  Widget _buildMoreMenu() {
    final canToggleBlock = _getPeerId() != null && _currentUserId != null;
    return PopupMenuButton<int>(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      onSelected: _onMenuAction,
      itemBuilder: (context) => <PopupMenuEntry<int>>[
        PopupMenuItem<int>(
          value: 1,
          child: Row(
            children: [
              Icon(Icons.flag_outlined, size: 18.w),
              SizedBox(width: 8.w),
              const Text('Report user'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<int>(
          enabled: canToggleBlock,
          value: 2,
          child: Row(
            children: [
              Icon(_iBlockedOther ? Icons.lock_open : Icons.block, size: 18.w),
              SizedBox(width: 8.w),
              Text(_iBlockedOther ? 'Unblock' : 'Block'),
            ],
          ),
        ),
      ],
    );
  }

  /// 新增：菜单动作
  Future<void> _onMenuAction(int value) async {
    switch (value) {
      case 1:
        _showReportSheet();
        break;
      case 2:
        await _toggleBlock();
        break;
    }
  }

  /// 新增：举报底部单
  void _showReportSheet() {
    final peerId = _getPeerId();
    if (peerId == null) {
      _showSnackBar('Unable to report: user not found', isError: true);
      return;
    }

    String type = 'Spam';
    final TextEditingController descCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16.r))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16.w,
            right: 16.w,
            top: 16.h,
            bottom: 16.h + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
              ),
              SizedBox(height: 12.h),
              Text('Report user',
                  style:
                      TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
              SizedBox(height: 12.h),
              DropdownButtonFormField<String>(
                value: type,
                items: const [
                  DropdownMenuItem(value: 'Spam', child: Text('Spam')),
                  DropdownMenuItem(value: 'Scam', child: Text('Scam/Fraud')),
                  DropdownMenuItem(
                      value: 'Harassment', child: Text('Harassment/Abuse')),
                  DropdownMenuItem(value: 'Other', child: Text('Other')),
                ],
                onChanged: (v) => type = v ?? 'Spam',
                decoration: const InputDecoration(labelText: 'Type'),
              ),
              SizedBox(height: 8.h),
              TextField(
                controller: descCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Describe the issue (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 12.h),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final ok = await OfferService.submitReport(
                      reportedId: peerId,
                      type: type,
                      description: descCtrl.text.trim().isEmpty
                          ? null
                          : descCtrl.text.trim(),
                      offerId: widget.offerId,
                      listingId: _offerDetails?['listing_id'] as String?,
                    );
                    Navigator.of(ctx).pop();
                    if (ok) {
                      _showSnackBar(
                          'Report submitted. Thank you for keeping the community safe.');
                    } else {
                      _showSnackBar('Failed to submit report', isError: true);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF667EEA),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r)),
                  ),
                  child: const Text('Submit'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 新增：切换屏蔽/取消屏蔽
  Future<void> _toggleBlock() async {
    final peerId = _getPeerId();
    if (peerId == null) return;

    bool ok = false;
    if (_iBlockedOther) {
      ok = await OfferService.unblockUser(blockedId: peerId);
      if (ok) _showSnackBar('Unblocked successfully');
    } else {
      ok = await OfferService.blockUser(blockedId: peerId);
      if (ok) _showSnackBar('User has been blocked');
    }

    if (ok) {
      await _refreshBlockStatus();
      setState(() {}); // 刷新菜单文字/输入区域
    } else {
      _showSnackBar('Operation failed, please try again', isError: true);
    }
  }

  /// 构建系统消息
  Widget _buildSystemMessage(Map<String, dynamic> message) {
    final messageText = message['message']?.toString() ?? '';

    return Center(
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 8.h),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: Colors.amber.shade200, width: 1.w),
        ),
        child: Text(
          messageText,
          style: TextStyle(
            fontSize: 12.sp,
            color: Colors.amber.shade800,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  /// 构建聊天消息气泡
  Widget _buildChatMessage(Map<String, dynamic> message, bool isMyMessage) {
    final messageText = message['message']?.toString() ?? '';
    final createdAt = message['created_at']?.toString() ?? '';

    // 格式化时间
    String timeText = 'Now';
    if (createdAt.isNotEmpty) {
      try {
        final date = DateTime.parse(createdAt);
        final now = DateTime.now();
        final difference = now.difference(date);

        if (difference.inMinutes < 1) {
          timeText = 'Now';
        } else if (difference.inMinutes < 60) {
          timeText = '${difference.inMinutes}m';
        } else if (difference.inHours < 24) {
          timeText = '${difference.inHours}h';
        } else {
          timeText = '${date.day}/${date.month}';
        }
      } catch (e) {
        timeText = 'Now';
      }
    }

    return Align(
      alignment: isMyMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 4.h),
        child: Column(
          crossAxisAlignment:
              isMyMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75),
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: isMyMessage
                    ? const Color(0xFF667EEA)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(18.r).copyWith(
                  bottomRight: isMyMessage
                      ? Radius.circular(4.r)
                      : Radius.circular(18.r),
                  bottomLeft: isMyMessage
                      ? Radius.circular(18.r)
                      : Radius.circular(4.r),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4.r,
                    offset: Offset(0, 1.h),
                  ),
                ],
              ),
              child: Text(
                messageText,
                style: TextStyle(
                  color: isMyMessage ? Colors.white : Colors.grey.shade800,
                  fontSize: 14.sp,
                  height: 1.3,
                ),
              ),
            ),
            SizedBox(height: 2.h),
            Text(
              timeText,
              style: TextStyle(
                fontSize: 10.sp,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建消息列表
  Widget _buildMessageList() {
    if (_isLoadingMessages) {
      return Expanded(
        child: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667EEA)),
            strokeWidth: 2.5.w,
          ),
        ),
      );
    }

    if (_messages.isEmpty) {
      return Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 64.w,
                color: Colors.grey.shade400,
              ),
              SizedBox(height: 16.h),
              Text(
                'No messages yet',
                style: TextStyle(
                  fontSize: 16.sp,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                'Start the conversation!',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 屏蔽提示条（出现在消息列表顶部）
    final List<Widget> children = [];
    if (_blockedEitherWay) {
      children.add(_buildBlockBanner());
    }

    children.add(
      Expanded(
        child: ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
          itemCount: _messages.length,
          itemBuilder: (context, index) {
            final message = _messages[index];
            final isMyMessage = message['sender_id'] == _currentUserId;
            final messageType = message['message_type'] ?? 'text';

            if (messageType == 'system') {
              return _buildSystemMessage(message);
            }

            return _buildChatMessage(message, isMyMessage);
          },
        ),
      ),
    );

    return Expanded(
      child: Column(
        children: children,
      ),
    );
  }

  /// 新增：屏蔽提示条
  Widget _buildBlockBanner() {
    final text = _otherBlockedMe
        ? 'You can’t send messages because this user has blocked you.'
        : 'You blocked this user. Unblock to continue chatting.';
    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(12.w, 0, 12.w, 6.h),
      padding: EdgeInsets.all(10.w),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: Colors.red.shade200, width: 1.w),
      ),
      child: Row(
        children: [
          Icon(Icons.block, size: 16.w, color: Colors.red.shade700),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.red.shade700, fontSize: 12.sp),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建输入区域
  Widget _buildInputArea() {
    final disabled = _blockedEitherWay;

    return Container(
      padding: EdgeInsets.fromLTRB(
          12.w, 8.h, 12.w, 8.h + MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4.r,
            offset: Offset(0, -1.h),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: disabled ? Colors.grey.shade200 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(25.r),
                ),
                child: TextField(
                  controller: _messageController,
                  enabled: !disabled,
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  style: TextStyle(fontSize: 14.sp),
                  decoration: InputDecoration(
                    hintText: disabled
                        ? (_otherBlockedMe
                            ? 'You are blocked by this user'
                            : 'You blocked this user')
                        : 'Type a message...',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 14.sp,
                    ),
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                  ),
                ),
              ),
            ),
            SizedBox(width: 8.w),
            Opacity(
              opacity: disabled ? 0.4 : 1,
              child: IgnorePointer(
                ignoring: disabled,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _isSendingMessage ? null : _sendMessage,
                      borderRadius: BorderRadius.circular(25.r),
                      child: SizedBox(
                        width: 50.w,
                        height: 50.h,
                        child: _isSendingMessage
                            ? Padding(
                                padding: EdgeInsets.all(12.w),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.w,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                ),
                              )
                            : Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 24.w,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          'Offer Details',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18.sp,
          ),
        ),
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white, size: 20.w),
      ),
      body: Column(
        children: [
          _buildOfferInfo(),
          _buildMessageList(),
          _buildInputArea(),
        ],
      ),
    );
  }
}
