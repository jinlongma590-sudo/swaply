// lib/pages/main_scaffold.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// 本地化（按你 Step1 的实际位置二选一）
import 'package:swaply/core/l10n/app_localizations.dart';
// import 'package:swaply/l10n/app_localizations.dart';

// 你这页里用到的其它页面/服务（先列常见的，不足再补）
import 'package:swaply/pages/home_page.dart';
import 'package:swaply/pages/sell_form_page.dart';
import 'package:swaply/pages/profile_page.dart';
import 'package:swaply/services/notification_service.dart';
import 'package:swaply/services/auth_service.dart';
import 'package:swaply/models/listing_store.dart';

// 如有：搜索、商品详情等
// import 'package:swaply/pages/product_detail_page.dart';
// import 'package:swaply/pages/search_results_page.dart';
