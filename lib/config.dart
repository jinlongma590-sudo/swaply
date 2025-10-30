// lib/config.dart

/// 是否走远程数据（新增，供页面判断本地/远程）
const bool kUseRemoteData = true;

/// 配置是否上传到远程服务器
/// 设置为 true 时会上传到 Supabase
/// 设置为 false 时仅存储在本地 ListingStore
const bool kUploadToRemote = true;

/// Supabase 配置
class SupabaseConfig {
  static const String url = 'https://rhckybselarzglkmlyqs.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJoY2t5YnNlbGFyemdsa21seXFzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTUwMTM0NTgsImV4cCI6MjA3MDU4OTQ1OH0.3I0T2DidiF-q9l2tWeHOjB31QogXHDqRtEjDn0RfVbU';
}

/// 应用配置
class AppConfig {
  static const String appName = 'Swaply';
  static const String version = '1.0.0';
  static const String packageName = 'com.swaply.app';

  // OAuth 回调
  static const String oauthRedirectUrl = 'io.supabase.swaply://login-callback/';
  static const String resetPasswordRedirectUrl =
      'io.supabase.swaply://reset-password/';
}

/// 上传配置
class UploadConfig {
  static const int maxImageSize = 5 * 1024 * 1024; // 5MB
  static const int maxImagesPerListing = 10;
  static const List<String> allowedImageTypes = ['jpg', 'jpeg', 'png', 'webp'];
  static const int imageQuality = 80;
}

/// 分页
class PaginationConfig {
  static const int defaultPageSize = 20;
  static const int maxPageSize = 100;
}

/// 缓存
class CacheConfig {
  static const Duration defaultCacheDuration = Duration(minutes: 15);
  static const Duration listingsCacheDuration = Duration(minutes: 10);
  static const Duration profileCacheDuration = Duration(hours: 1);
}

/// 表名
class ApiEndpoints {
  static const String listings = 'listings';
  static const String userProfiles = 'user_profiles';
  static const String favorites = 'favorites';
  static const String purchases = 'purchases';
  static const String listingViews = 'listing_views';
}

/// 存储桶
class StorageBuckets {
  static const String listingImages = 'listing-images';
  static const String avatars = 'avatars';
}

/// 主题
class ThemeConfig {
  static const int primaryColorValue = 0xFF2196F3;
  static const int secondaryColorValue = 0xFF1E88E5;
  static const double borderRadius = 12.0;
  static const double cardElevation = 2.0;
}

/// 环境
class Environment {
  static const bool isProduction = bool.fromEnvironment('dart.vm.product');
  static const bool isDevelopment = !isProduction;
}

/// 调试
class DebugConfig {
  static const bool enableLogging = Environment.isDevelopment;
  static const bool enableNetworkLogging = Environment.isDevelopment;
  static const bool enableErrorReporting = Environment.isProduction;
}
