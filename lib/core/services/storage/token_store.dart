import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStore {
  TokenStore(this._storage);

  static const _key = 'auth_token';

  final FlutterSecureStorage _storage;
  String? _cached;
  bool _loaded = false;

  Future<String?> read() async {
    if (_loaded) return _cached;
    final stored = await _storage.read(key: _key);
    // A write or clear that landed during the read wins.
    if (!_loaded) {
      _cached = stored;
      _loaded = true;
    }
    return _cached;
  }

  Future<void> write(String token) async {
    await _storage.write(key: _key, value: token);
    _cached = token;
    _loaded = true;
  }

  Future<void> clear() async {
    await _storage.delete(key: _key);
    _cached = null;
    _loaded = true;
  }
}
