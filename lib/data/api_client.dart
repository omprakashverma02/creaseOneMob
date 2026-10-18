import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/config.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.data});
  final String message;
  final int? statusCode;
  final dynamic data;
  @override
  String toString() => message;
}

/// Thin Dio wrapper: attaches the JWT, normalises errors into [ApiException].
class ApiClient {
  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiBase,
      validateStatus: (s) => s != null && s >= 200 && s < 300,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 40),
      headers: {'Accept': 'application/json'},
    ));
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
      options.baseUrl = AppConfig.apiBase;
      final t = _token ?? await readToken();
      if (t != null && t.isNotEmpty) options.headers['Authorization'] = 'Bearer $t';
      handler.next(options);
    }));
  }

  static const _tokenKey = 'creaseone_jwt_v1';
  final _storage = const FlutterSecureStorage();
  late final Dio _dio;
  String? _token;

  /// Called when the server rejects our token (401) so the app can sign out.
  void Function()? onUnauthorized;

  String? get token => _token;

  Future<String?> readToken() async {
    _token ??= await _storage.read(key: _tokenKey);
    return _token;
  }

  Future<void> saveToken(String token) async {
    _token = token;
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<void> clearToken() async {
    _token = null;
    await _storage.delete(key: _tokenKey);
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _wrap(() => _dio.get(path, queryParameters: _clean(query)));

  Future<dynamic> post(String path, {dynamic data, Map<String, dynamic>? query}) =>
      _wrap(() => _dio.post(path, data: data, queryParameters: _clean(query)));

  Future<dynamic> put(String path, {dynamic data}) => _wrap(() => _dio.put(path, data: data));

  Future<dynamic> patch(String path, {dynamic data}) => _wrap(() => _dio.patch(path, data: data));

  Future<dynamic> delete(String path, {Map<String, dynamic>? query, dynamic data}) =>
      _wrap(() => _dio.delete(path, queryParameters: _clean(query), data: data));

  Future<String> uploadImage(File file, {String folder = 'misc'}) async {
    final form = FormData.fromMap({
      'image': await MultipartFile.fromFile(file.path, filename: file.uri.pathSegments.last),
      'folder': folder,
    });
    final res = await _wrap(() => _dio.post('/upload', data: form));
    if (res is Map) {
      final url = res['url'] ?? res['imageUrl'] ?? res['publicUrl'] ?? res['path'];
      if (url != null) return url.toString();
    }
    throw ApiException('Upload succeeded but no URL was returned');
  }

  /// Multipart upload of an arbitrary file (Excel imports, scorecard images…).
  Future<dynamic> uploadFile(String path, File file, {String field = 'file', Map<String, dynamic>? fields}) async {
    final form = FormData.fromMap({
      field: await MultipartFile.fromFile(file.path, filename: file.uri.pathSegments.last),
      ...?fields,
    });
    return _wrap(() => _dio.post(path, data: form));
  }

  /// Download raw bytes (templates). Uses POST when [data] is given.
  Future<List<int>> downloadBytes(String path, {dynamic data}) async {
    final res = await _wrap(() => data == null
        ? _dio.get<List<int>>(path, options: Options(responseType: ResponseType.bytes))
        : _dio.post<List<int>>(path, data: data, options: Options(responseType: ResponseType.bytes)));
    if (res is List<int>) return res;
    throw ApiException('Download failed');
  }

  Map<String, dynamic>? _clean(Map<String, dynamic>? q) {
    if (q == null) return null;
    final out = <String, dynamic>{};
    q.forEach((k, v) {
      if (v == null) return;
      if (v is String && v.trim().isEmpty) return;
      out[k] = v;
    });
    return out;
  }

  Future<dynamic> _wrap(Future<Response> Function() call) async {
    try {
      final res = await call();
      return res.data;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      if (status == 401) onUnauthorized?.call();
      String msg;
      if (data is Map && (data['message'] ?? data['error']) != null) {
        msg = (data['message'] ?? data['error']).toString();
      } else if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) {
        msg = 'Could not reach the CreaseOne server. Check your internet connection.';
      } else if (e.type == DioExceptionType.receiveTimeout) {
        msg = 'The server took too long to respond. Please retry.';
      } else {
        msg = status != null ? 'Request failed ($status)' : (e.message ?? 'Request failed');
      }
      throw ApiException(msg, statusCode: status, data: data);
    }
  }
}
