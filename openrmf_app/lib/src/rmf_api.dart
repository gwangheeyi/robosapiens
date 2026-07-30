import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';

class RmfApiException implements Exception {
  const RmfApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class RmfApi {
  RmfApi({required String baseUrl, required this.token, http.Client? client})
    : baseUri = Uri.parse(baseUrl.replaceFirst(RegExp(r'/$'), '')),
      _client = client ?? http.Client();

  final Uri baseUri;
  final String token;
  final http.Client _client;
  Map<String, String> get _headers =>
      token.isEmpty ? const {} : {'Authorization': 'Bearer $token'};

  Future<RmfBuildingMap> getBuildingMap() async =>
      RmfBuildingMap.fromJson(await _getObject('/building_map'));

  Future<List<RmfRobot>> getRobots() async =>
      RmfRobot.fromFleetList(await _getList('/fleets'));

  Future<List<RmfTask>> getTasks() async =>
      (await _getList('/tasks'))
          .whereType<Map>()
          .map((json) => RmfTask.fromJson(Map<String, dynamic>.from(json)))
          .toList()
        ..sort((a, b) {
          final left = a.requestedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final right = b.requestedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return right.compareTo(left);
        });

  Future<Uint8List> getBytes(String location) async {
    final uri = resolve(location);
    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 5));
    _check(response, uri);
    return response.bodyBytes;
  }

  Uri resolve(String location) {
    final parsed = Uri.parse(location);
    if (parsed.hasScheme) {
      if (parsed.host == 'localhost' || parsed.host == '127.0.0.1') {
        return parsed.replace(host: baseUri.host, port: baseUri.port);
      }
      return parsed;
    }
    return baseUri.resolve(location);
  }

  Future<Map<String, dynamic>> _getObject(String path) async {
    final uri = baseUri.resolve(path);
    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 5));
    _check(response, uri);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) throw RmfApiException('$path 응답 형식이 올바르지 않습니다.');
    return Map<String, dynamic>.from(decoded);
  }

  Future<List<dynamic>> _getList(String path) async {
    final uri = baseUri.resolve(path);
    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 5));
    _check(response, uri);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) throw RmfApiException('$path 응답 형식이 올바르지 않습니다.');
    return decoded;
  }

  void _check(http.Response response, Uri uri) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw RmfApiException('${uri.path} 요청 실패 (${response.statusCode})');
  }

  void close() => _client.close();
}
