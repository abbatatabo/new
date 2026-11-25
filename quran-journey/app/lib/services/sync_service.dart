import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../data/user_db.dart';

class SyncResult {
  final int pushed;
  final int pulled;
  final int conflicts;
  final String? error;
  const SyncResult({this.pushed = 0, this.pulled = 0, this.conflicts = 0, this.error});
}

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

/// Optional account + sync with the self-hosted backend (docs/CONTRACTS.md §5).
/// The app is fully usable without it.
class SyncService {
  final UserDb userDb;
  final http.Client client;
  final FlutterSecureStorage _secure;
  static const _tokenKey = 'qj_auth_token';
  String? _token;

  SyncService(this.userDb, {http.Client? client, FlutterSecureStorage? secure})
    : client = client ?? http.Client(),
      _secure = secure ?? const FlutterSecureStorage();

  Future<String?> loadToken() async {
    try {
      _token = await _secure.read(key: _tokenKey);
    } catch (_) {
      _token = null;
    }
    return _token;
  }

  bool get signedIn => _token != null;

  Uri _u(String base, String path, [Map<String, String>? q]) {
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final uri = Uri.parse('$b$path');
    if (uri.scheme != 'https' && uri.host != 'localhost' && uri.host != '10.0.2.2') {
      throw ApiException(0, 'The server address must use https://');
    }
    return q == null ? uri : uri.replace(queryParameters: q);
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  Future<Map<String, dynamic>> _json(http.Response r) async {
    final body = r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode >= 400) {
      throw ApiException(r.statusCode, (body['error'] as String?) ?? 'Request failed (${r.statusCode})');
    }
    return body;
  }

  Future<String> authenticate(String base, String email, String password, {required bool register}) async {
    final r = await client
        .post(_u(base, register ? '/api/auth/register' : '/api/auth/login'),
            headers: _headers, body: jsonEncode({'email': email, 'password': password}))
        .timeout(const Duration(seconds: 20));
    final j = await _json(r);
    _token = j['token'] as String;
    await _secure.write(key: _tokenKey, value: _token);
    return ((j['user'] as Map)['email'] as String?) ?? email;
  }

  Future<void> signOut() async {
    _token = null;
    await _secure.delete(key: _tokenKey);
    await userDb.kvSet('sync_since', null);
  }

  Future<void> deleteAccount(String base, String password) async {
    final req = http.Request('DELETE', _u(base, '/api/account'))
      ..headers.addAll(_headers)
      ..body = jsonEncode({'password': password});
    final r = await http.Response.fromStream(await client.send(req));
    if (r.statusCode != 204) await _json(r);
    await signOut();
  }

  Future<SyncResult> sync(String base) async {
    if (_token == null || base.isEmpty) return const SyncResult(error: 'Not signed in');
    try {
      final since = await userDb.kvGet('sync_since');
      final changes = await userDb.unsyncedChanges();
      final r = await client
          .post(_u(base, '/api/sync'), headers: _headers, body: jsonEncode({'since': since, 'changes': changes}))
          .timeout(const Duration(seconds: 30));
      final j = await _json(r);
      await userDb.markSynced(changes);
      final incoming = (j['changes'] as List? ?? const []).cast<Map>();
      for (final c in incoming) {
        await userDb.applyRemote(c.cast<String, dynamic>());
      }
      final conflicts = (j['conflicts'] as List? ?? const []).cast<Map>();
      for (final c in conflicts) {
        final server = (c['server'] as Map?)?.cast<String, dynamic>();
        if (server != null) await userDb.applyRemote(server);
      }
      await userDb.kvSet('sync_since', j['server_time'] as String?);
      return SyncResult(pushed: changes.length, pulled: incoming.length, conflicts: conflicts.length);
    } on ApiException catch (e) {
      if (e.status == 401) await signOut();
      return SyncResult(error: e.message);
    } catch (e) {
      return SyncResult(error: 'Offline or server unreachable. Your data is safe on this device.');
    }
  }

  /// Published, approved study content (no account needed).
  Future<int> fetchPublishedContent(String base) async {
    if (base.isEmpty) return 0;
    try {
      final since = await userDb.kvGet('content_since');
      final r = await client
          .get(_u(base, '/api/content/published', {'since': since ?? ''}))
          .timeout(const Duration(seconds: 30));
      final j = await _json(r);
      final items = (j['items'] as List? ?? const []).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
      // Defence in depth: never store anything that is not published.
      items.removeWhere((e) => e['status'] != 'published');
      final groupings = (j['groupings'] as List? ?? const []).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
      groupings.removeWhere((e) => e['status'] != 'published');
      final removed = (j['removed_ids'] as List? ?? const []).cast<String>();
      await userDb.upsertContent(items, removed);
      await userDb.upsertGroupings(groupings);
      for (final k in ['sources', 'scholars']) {
        final incoming = (j[k] as List? ?? const []).cast<Map>();
        if (incoming.isEmpty) continue;
        final prev = await userDb.kvGet('cms_$k');
        final merged = <String, Map>{
          for (final e in (prev == null ? const [] : jsonDecode(prev) as List).cast<Map>()) e['id'] as String: e,
        };
        for (final e in incoming) {
          merged[e['id'] as String] = e;
        }
        await userDb.kvSet('cms_$k', jsonEncode(merged.values.toList()));
      }
      await userDb.kvSet('content_since', j['server_time'] as String?);
      return items.length;
    } catch (_) {
      return -1;
    }
  }
}
