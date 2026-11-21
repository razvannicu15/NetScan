import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/i18n.dart';
import '../models/device.dart';

/// Tiny JSON-file persistence for settings and known devices.
class Storage {
  Storage._();
  static final Storage instance = Storage._();

  Directory? _dir;

  Future<File> _file(String name) async {
    _dir ??= await getApplicationSupportDirectory();
    if (!await _dir!.exists()) await _dir!.create(recursive: true);
    return File('${_dir!.path}${Platform.pathSeparator}$name');
  }

  Future<Map<String, dynamic>> readJson(String name) async {
    try {
      final f = await _file(name);
      if (!await f.exists()) return {};
      final v = jsonDecode(await f.readAsString());
      return v is Map<String, dynamic> ? v : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> writeJson(String name, Map<String, dynamic> data) async {
    try {
      final f = await _file(name);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(data), flush: true);
      await tmp.rename(f.path);
    } catch (_) {}
  }
}

class AppSettings extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.system;
  String language = 'system';
  bool usePing = true;
  bool scanPorts = true;
  int probeTimeoutMs = 700;
  String customStart = '';
  String customEnd = '';
  bool useCustomRange = false;
  int portConcurrency = 64;

  Future<void> load() async {
    final j = await Storage.instance.readJson('settings.json');
    themeMode = ThemeMode.values.firstWhere(
        (m) => m.name == j['themeMode'],
        orElse: () => ThemeMode.system);
    language = j['language'] as String? ?? 'system';
    setLanguage(language);
    usePing = j['usePing'] as bool? ?? true;
    scanPorts = j['scanPorts'] as bool? ?? true;
    probeTimeoutMs = (j['probeTimeoutMs'] as int? ?? 700).clamp(200, 3000);
    customStart = j['customStart'] as String? ?? '';
    customEnd = j['customEnd'] as String? ?? '';
    useCustomRange = j['useCustomRange'] as bool? ?? false;
    portConcurrency = (j['portConcurrency2'] as int? ?? 64).clamp(8, 256);
    notifyListeners();
  }

  Future<void> _pending = Future<void>.value();

  Future<void> update(void Function(AppSettings s) change) {
    change(this);
    setLanguage(language);
    notifyListeners();
    return _pending = _pending.then((_) => _save());
  }

  Future<void> _save() async {
    await Storage.instance.writeJson('settings.json', {
      'themeMode': themeMode.name,
      'language': language,
      'usePing': usePing,
      'scanPorts': scanPorts,
      'probeTimeoutMs': probeTimeoutMs,
      'customStart': customStart,
      'customEnd': customEnd,
      'useCustomRange': useCustomRange,
      'portConcurrency2': portConcurrency,
    });
  }
}

/// Devices seen in the past, per network.
class DeviceHistory {
  final Map<String, Map<String, Device>> _byNetwork = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final j = await Storage.instance.readJson('devices.json');
    j.forEach((net, value) {
      if (value is Map<String, dynamic>) {
        final m = <String, Device>{};
        value.forEach((k, v) {
          if (v is Map<String, dynamic>) {
            try {
              m[k] = Device.fromJson(v);
            } catch (_) {}
          }
        });
        _byNetwork[net] = m;
      }
    });
  }

  Map<String, Device> forNetwork(String net) =>
      _byNetwork.putIfAbsent(net, () => {});

  bool get isEmpty => _byNetwork.values.every((m) => m.isEmpty);

  Future<void> _pendingSave = Future<void>.value();

  /// Saves are queued so two writes never overlap.
  Future<void> save() => _pendingSave = _pendingSave.then((_) => _write());

  Future<void> _write() async {
    await Storage.instance.writeJson('devices.json', {
      for (final e in _byNetwork.entries)
        e.key: {for (final d in e.value.entries) d.key: d.value.toJson()},
    });
  }

  Future<void> clear() async {
    _byNetwork.clear();
    await save();
  }
}
