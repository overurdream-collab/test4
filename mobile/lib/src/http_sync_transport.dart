import 'dart:convert';
import 'dart:io';

import 'offline_store.dart';
import 'sync_coordinator.dart';

typedef AccessTokenProvider = Future<String> Function();

class HttpSyncTransport implements SyncTransport {
  HttpSyncTransport({
    required this.baseUri,
    required this.accessTokenProvider,
    HttpClient? httpClient,
    this.requestTimeout = const Duration(seconds: 20),
  }) : _httpClient = httpClient ?? HttpClient() {
    if (baseUri.scheme != 'https' && baseUri.scheme != 'http') {
      throw ArgumentError.value(baseUri, 'baseUri', 'Only HTTP(S) is supported');
    }
  }

  final Uri baseUri;
  final AccessTokenProvider accessTokenProvider;
  final Duration requestTimeout;
  final HttpClient _httpClient;

  Uri _endpoint(
    List<String> segments, {
    Map<String, String>? queryParameters,
  }) {
    final prefix = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    final suffix = segments.map(Uri.encodeComponent).join('/');
    return baseUri.replace(
      path: '$prefix/$suffix',
      queryParameters: queryParameters,
    );
  }

  Future<Map<String, Object?>> _requestJson({
    required String method,
    required Uri uri,
    Map<String, Object?>? body,
  }) async {
    final token = await accessTokenProvider();
    if (token.isEmpty) {
      throw const SyncPermanentFailure('authentication_required');
    }

    final request = await _httpClient.openUrl(method, uri);
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
      ..contentType = ContentType.json
      ..accept = ContentType.json;
    if (body != null) request.write(jsonEncode(body));

    final response = await request.close().timeout(requestTimeout);
    final responseText = await utf8.decoder
        .bind(response)
        .join()
        .timeout(requestTimeout);
    Map<String, Object?> decoded = {};
    if (responseText.isNotEmpty) {
      final value = jsonDecode(responseText);
      if (value is Map) decoded = Map<String, Object?>.from(value);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error']?.toString() ?? 'http_${response.statusCode}';
      if (response.statusCode == 409) throw SyncConflictException(error);
      if (response.statusCode == 401 ||
          response.statusCode == 403 ||
          response.statusCode == 404 ||
          response.statusCode == 422) {
        throw SyncPermanentFailure(error);
      }
      throw HttpException(error, uri: uri);
    }
    return decoded;
  }

  @override
  Future<SyncAcceptance> submitOperation(OfflineOperation operation) async {
    final uri = _endpoint([
      'v1',
      'relationships',
      operation.relationshipId,
      'operations',
    ]);
    final response = await _requestJson(
      method: 'POST',
      uri: uri,
      body: {
        'operationId': operation.operationId,
        'operationType': operation.operationType,
        'schemaVersion': 1,
        'baseVersion': operation.baseServerVersion,
        'payload': operation.payload,
        'clientCreatedAt': operation.clientCreatedAt.toUtc().toIso8601String(),
      },
    );

    return SyncAcceptance(
      outcome: response['outcome']! as String,
      businessState: response['businessState']! as String,
      serverVersion: (response['serverVersion']! as num).toInt(),
      serverSequence: (response['serverSequence']! as num).toInt(),
    );
  }

  @override
  Future<SyncEventPage> pullEvents({
    required String relationshipId,
    required int after,
    required int limit,
  }) async {
    final uri = _endpoint(
      ['v1', 'relationships', relationshipId, 'events'],
      queryParameters: {'after': '$after', 'limit': '$limit'},
    );
    final response = await _requestJson(method: 'GET', uri: uri);
    final rawEvents = response['events'] as List? ?? const [];
    final events = rawEvents.map((raw) {
      final event = Map<String, Object?>.from(raw as Map);
      return SyncEvent(
        relationshipId: relationshipId,
        serverSequence: (event['serverSequence']! as num).toInt(),
        eventId: event['eventId']! as String,
        operationId: event['operationId']! as String,
        eventType: event['eventType']! as String,
        payload: Map<String, Object?>.from(event['payload']! as Map),
        createdAt: DateTime.parse(event['createdAt']! as String).toUtc(),
      );
    }).toList();

    return SyncEventPage(
      events: events,
      nextCursor: (response['nextCursor']! as num).toInt(),
      hasMore: response['hasMore']! as bool,
    );
  }

  void close() => _httpClient.close(force: true);
}
