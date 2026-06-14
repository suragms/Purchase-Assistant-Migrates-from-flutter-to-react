import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

const _endpoint =
    'http://127.0.0.1:7675/ingest/d909ff1c-fa09-4705-abcb-59a4ae818305';
const _sessionId = '5843f1';

/// Debug-mode NDJSON logger (local ingest server + console fallback).
void agentDebugLog({
  required String location,
  required String message,
  required String hypothesisId,
  Map<String, dynamic>? data,
  String runId = 'pre-fix',
}) {
  final payload = <String, dynamic>{
    'sessionId': _sessionId,
    'hypothesisId': hypothesisId,
    'location': location,
    'message': message,
    'data': data ?? const {},
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'runId': runId,
  };
  // #region agent log
  unawaited(_postLog(payload));
  debugPrint('[DBG5843f1] ${jsonEncode(payload)}');
  // #endregion
}

Future<void> _postLog(Map<String, dynamic> payload) async {
  try {
    await Dio().post(
      _endpoint,
      data: payload,
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'X-Debug-Session-Id': _sessionId,
        },
        sendTimeout: const Duration(milliseconds: 500),
        receiveTimeout: const Duration(milliseconds: 500),
      ),
    );
  } catch (_) {}
}
