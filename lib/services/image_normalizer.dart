// lib/services/image_normalizer.dart
//
// 统一把选中的图片转换成“最长边<=1440、质量=85% 的 JPG”以便跨端展示。
// - iOS / Android：使用 flutter_image_compress 在本地转成 JPG；
// - Web：大多数情况下浏览器给到就是 jpg/png，保持原样；若真是 HEIC，建议后端转或提示用户。
// 使用：
//   final res = await ImageNormalizer.normalizeXFile(xfile);
//   final bytes = res.bytes;        // 处理后的 JPG 字节
//   final fileNameExt = res.ext;    // "jpg"
//   final mime = res.mimeType;      // "image/jpeg"

import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:cross_file/cross_file.dart';

class NormalizedImageResult {
  final Uint8List bytes;
  final String ext;       // 一律 "jpg"
  final String mimeType;  // 一律 "image/jpeg"
  const NormalizedImageResult(this.bytes) : ext = 'jpg', mimeType = 'image/jpeg';
}

class ImageNormalizer {
  static const int _maxDim = 1440;   // 最长边
  static const int _quality = 85;    // 压缩质量

  static bool _isHeicExt(String? pathOrName) {
    final p = (pathOrName ?? '').toLowerCase();
    return p.endsWith('.heic') || p.endsWith('.heif');
  }

  static bool _isPngWebpBmp(String? pathOrName) {
    final p = (pathOrName ?? '').toLowerCase();
    return p.endsWith('.png') || p.endsWith('.webp') || p.endsWith('.bmp');
  }

  /// 统一入口：从 XFile 转成 JPG（iOS/Android 生效；Web 基本原样返回）
  static Future<NormalizedImageResult> normalizeXFile(XFile file) async {
    final path = file.path;
    final rawBytes = await file.readAsBytes();

    // Web：flutter_image_compress 在 Web 支持有限，通常直接返回原始（多数已是 jpg/png）
    if (kIsWeb) {
      if (_isHeicExt(path)) {
        // 可选：你也可以在这里直接抛出提示，要求用户转码再上传。
        // 这里保守：原样返回，后端/展示端请不要使用 heic 直链。
        return NormalizedImageResult(rawBytes);
      }
      // png/webp 在 web 端通常也能被浏览器解码；你若想统一，也可改成：compressWithList(...)
      return NormalizedImageResult(await _tryCompressBytes(rawBytes));
    }

    // 移动端：凡不是 jpg 的，统统转成 jpg
    if (_isHeicExt(path) || _isPngWebpBmp(path) || !path.toLowerCase().endsWith('.jpg') && !path.toLowerCase().endsWith('.jpeg')) {
      final out = await _compressFileToJpeg(path);
      return NormalizedImageResult(out);
    }

    // 已是 jpg：做一次有损压缩以控制尺寸（可按需关闭）
    final out = await _tryCompressFile(path);
    return NormalizedImageResult(out);
  }

  /// 原始 bytes -> JPG bytes（移动端/部分平台都能跑；web 也可用但兼容性取决于浏览器）
  static Future<Uint8List> normalizeBytesToJpeg(Uint8List bytes) async {
    return await _tryCompressBytes(bytes);
  }

  // ---------------- internal helpers ----------------

  static Future<Uint8List> _compressFileToJpeg(String path) async {
    // iOS/Android：把任意格式文件转成 JPG
    final out = await FlutterImageCompress.compressWithFile(
      path,
      minWidth: _maxDim,
      minHeight: _maxDim,
      quality: _quality,
      format: CompressFormat.jpeg,
      keepExif: true,
    );
    if (out == null) throw Exception('Image compress failed for $path');
    return out;
  }

  static Future<Uint8List> _tryCompressFile(String path) async {
    final out = await FlutterImageCompress.compressWithFile(
      path,
      minWidth: _maxDim,
      minHeight: _maxDim,
      quality: _quality,
      format: CompressFormat.jpeg,
      keepExif: true,
    );
    return out ?? await _fallbackRead(path);
  }

  static Future<Uint8List> _tryCompressBytes(Uint8List bytes) async {
    final out = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: _maxDim,
      minHeight: _maxDim,
      quality: _quality,
      format: CompressFormat.jpeg,
      keepExif: true,
    );
    return out;
  }

  // 仅在 compressWithFile 失败（理论上很少）时兜底读文件；这里不实现，保持简单。
  static Future<Uint8List> _fallbackRead(String path) async {
    // 由调用方自己读；当前调用链不会进入这里
    throw UnimplementedError('_fallbackRead should not be reached.');
  }
}
