import 'dart:convert';

import 'package:get/get.dart';

import 'platform_model.dart';

const String kUuSchemesOption = 'uu-control-schemes';

// Fraction of the screen height occupied by the UU-style keyboard sheet;
// the remote canvas re-fits into the remaining top area while it is open.
const double kUuKeyboardSheetFraction = 0.56;

class UuFloatingKey {
  String id;
  String key;
  bool ctrl;
  bool alt;
  bool shift;
  bool meta;
  // Normalized screen coordinates (0..1) of the key center.
  double x;
  double y;

  UuFloatingKey(
    this.id,
    this.key, {
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
    this.meta = false,
    this.x = 0.1,
    this.y = 0.5,
  });

  bool get isModifier =>
      key == 'VK_CONTROL' || key == 'VK_MENU' || key == 'VK_SHIFT' || key == 'Meta';

  String get label {
    if (isModifier) {
      const names = {
        'VK_CONTROL': 'Ctrl',
        'VK_MENU': 'Alt',
        'VK_SHIFT': 'Shift',
        'Meta': 'Win',
      };
      return names[key] ?? key;
    }
    final parts = <String>[];
    if (ctrl) parts.add('Ctrl');
    if (alt) parts.add('Alt');
    if (shift) parts.add('Shift');
    if (meta) parts.add('Win');
    parts.add(key.startsWith('VK_') ? key.substring(3) : key);
    return parts.join('+');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'key': key,
        'ctrl': ctrl,
        'alt': alt,
        'shift': shift,
        'meta': meta,
        'x': x,
        'y': y,
      };

  factory UuFloatingKey.fromJson(Map<String, dynamic> json) => UuFloatingKey(
        (json['id'] ?? DateTime.now().microsecondsSinceEpoch.toString())
            .toString(),
        json['key']?.toString() ?? 'VK_ESCAPE',
        ctrl: json['ctrl'] == true,
        alt: json['alt'] == true,
        shift: json['shift'] == true,
        meta: json['meta'] == true,
        x: (json['x'] as num?)?.toDouble() ?? 0.1,
        y: (json['y'] as num?)?.toDouble() ?? 0.5,
      );
}

class UuScheme {
  String name;
  List<UuFloatingKey> keys;
  double opacity;
  double keyScale;
  bool haptics;
  bool pinchZoom;
  bool comboLatch;

  UuScheme({
    required this.name,
    List<UuFloatingKey>? keys,
    this.opacity = 0.45,
    this.keyScale = 1.0,
    this.haptics = true,
    this.pinchZoom = true,
    this.comboLatch = true,
  }) : keys = keys ?? [];

  Map<String, dynamic> toJson() => {
        'name': name,
        'keys': keys.map((e) => e.toJson()).toList(),
        'opacity': opacity,
        'keyScale': keyScale,
        'haptics': haptics,
        'pinchZoom': pinchZoom,
        'comboLatch': comboLatch,
      };

  factory UuScheme.fromJson(Map<String, dynamic> json) => UuScheme(
        name: json['name']?.toString() ?? '默认方案',
        keys: (json['keys'] as List? ?? [])
            .whereType<Map>()
            .map((e) => UuFloatingKey.fromJson(e.cast<String, dynamic>()))
            .toList(),
        opacity: (json['opacity'] as num?)?.toDouble() ?? 0.45,
        keyScale: (json['keyScale'] as num?)?.toDouble() ?? 1.0,
        haptics: json['haptics'] != false,
        pinchZoom: json['pinchZoom'] != false,
        comboLatch: json['comboLatch'] != false,
      );
}

List<UuScheme> _defaultSchemes() => [
      UuScheme(name: '默认方案'),
      UuScheme(
        name: 'Gal',
        keys: [UuFloatingKey('gal-ctrl', 'VK_CONTROL', x: 0.06, y: 0.5)],
        opacity: 0.35,
        pinchZoom: false,
      ),
    ];

class UuState {
  final schemes = <UuScheme>[].obs;
  final activeName = ''.obs;
  final railOpen = false.obs;
  final keyboardOpen = false.obs;
  // null = closed, otherwise 'menu' / 'schemes' / 'settings'
  final drawerPage = RxnString();
  final editLayout = false.obs;

  UuScheme get active {
    final name = activeName.value;
    for (final s in schemes) {
      if (s.name == name) return s;
    }
    if (schemes.isNotEmpty) return schemes.first;
    final fallback = UuScheme(name: '默认方案');
    schemes.add(fallback);
    return fallback;
  }

  void load() {
    List<UuScheme> loaded = [];
    var active = '';
    try {
      final raw = bind.mainGetLocalOption(key: kUuSchemesOption);
      if (raw.isNotEmpty) {
        final decoded = json.decode(raw);
        if (decoded is Map) {
          loaded = (decoded['schemes'] as List? ?? [])
              .whereType<Map>()
              .map((e) => UuScheme.fromJson(e.cast<String, dynamic>()))
              .toList();
          active = decoded['active']?.toString() ?? '';
        }
      }
    } catch (_) {}
    if (loaded.isEmpty) loaded = _defaultSchemes();
    schemes.assignAll(loaded);
    activeName.value =
        loaded.any((s) => s.name == active) ? active : loaded.first.name;
  }

  void save() {
    bind.mainSetLocalOption(
      key: kUuSchemesOption,
      value: json.encode({
        'active': activeName.value,
        'schemes': schemes.map((e) => e.toJson()).toList(),
      }),
    );
  }

  void resetSessionUi() {
    railOpen.value = false;
    keyboardOpen.value = false;
    drawerPage.value = null;
    editLayout.value = false;
  }
}

final uuState = UuState();