import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'custom_tunnel.dart';

/// Stockage local des tunnels custom — SharedPreferences + JSON.
/// Clé dédiée `custom_tunnels_v1`, aucun réseau (zéro coût).
/// Repli mémoire si SharedPreferences indisponible (tests widget).
class CustomTunnelStore {
  CustomTunnelStore._(this._prefs, this._mem);

  final SharedPreferences? _prefs;
  final Map<String, Object> _mem;

  static const storageKey = 'custom_tunnels_v1';

  static Future<CustomTunnelStore> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return CustomTunnelStore._(prefs, const {});
    } catch (_) {
      return CustomTunnelStore._(null, {storageKey: '[]'});
    }
  }

  /// Fabrique mémoire pour tests / previews.
  factory CustomTunnelStore.inMemory([List<CustomTunnel> seed = const []]) {
    return CustomTunnelStore._(null, {
      storageKey: jsonEncode(seed.map((t) => t.toJson()).toList()),
    });
  }

  String get _raw {
    final p = _prefs;
    if (p != null) return p.getString(storageKey) ?? '[]';
    return _mem[storageKey] as String? ?? '[]';
  }

  Future<void> _writeRaw(String value) async {
    final p = _prefs;
    if (p != null) {
      await p.setString(storageKey, value);
    } else {
      _mem[storageKey] = value;
    }
  }

  /// Tous les tunnels sauvegardés (ignore les entrées corrompues).
  List<CustomTunnel> get tunnels {
    try {
      final decoded = jsonDecode(_raw) as List;
      return decoded
          .whereType<Map>()
          .map((e) => CustomTunnel.fromJson(
              e.map((k, v) => MapEntry(k.toString(), v as Object?))))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> add(CustomTunnel tunnel) async {
    final all = [...tunnels, tunnel];
    await _writeRaw(
        jsonEncode(all.map((t) => t.toJson()).toList()));
  }

  Future<void> clear() => _writeRaw('[]');
}
