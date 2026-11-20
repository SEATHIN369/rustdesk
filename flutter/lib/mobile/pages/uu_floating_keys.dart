import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../models/uu_state.dart';

const List<String> _singleKeyOptions = [
  'VK_CONTROL', 'VK_MENU', 'VK_SHIFT', 'Meta',
  'VK_ESCAPE', 'VK_RETURN', 'VK_SPACE', 'VK_TAB', 'VK_BACK', 'VK_DELETE',
  'VK_UP', 'VK_DOWN', 'VK_LEFT', 'VK_RIGHT',
  'VK_HOME', 'VK_END', 'VK_PAGEUP', 'VK_PAGEDOWN',
  'VK_F2', 'VK_F5', 'VK_F11', 'VK_SNAPSHOT',
];

const List<String> _comboKeyOptions = [
  'VK_A', 'VK_B', 'VK_C', 'VK_D', 'VK_E', 'VK_F', 'VK_G', 'VK_H', 'VK_I',
  'VK_J', 'VK_K', 'VK_L', 'VK_M', 'VK_N', 'VK_O', 'VK_P', 'VK_Q', 'VK_R',
  'VK_S', 'VK_T', 'VK_U', 'VK_V', 'VK_W', 'VK_X', 'VK_Y', 'VK_Z',
  'VK_0', 'VK_1', 'VK_2', 'VK_3', 'VK_4', 'VK_5', 'VK_6', 'VK_7', 'VK_8',
  'VK_9',
  'VK_F1', 'VK_F2', 'VK_F3', 'VK_F4', 'VK_F5', 'VK_F6', 'VK_F7', 'VK_F8',
  'VK_F9', 'VK_F10', 'VK_F11', 'VK_F12',
  'VK_ESCAPE', 'VK_TAB', 'VK_RETURN', 'VK_SPACE',
];

String _optionLabel(String key) {
  const names = {
    'VK_CONTROL': 'Ctrl',
    'VK_MENU': 'Alt',
    'VK_SHIFT': 'Shift',
    'Meta': 'Win',
    'VK_ESCAPE': 'Esc',
    'VK_RETURN': 'Enter',
    'VK_SPACE': 'Space',
    'VK_TAB': 'Tab',
    'VK_BACK': 'Backspace',
    'VK_DELETE': 'Del',
    'VK_SNAPSHOT': 'PrtScr',
    'VK_PAGEUP': 'PgUp',
    'VK_PAGEDOWN': 'PgDn',
  };
  if (names.containsKey(key)) return names[key]!;
  if (key.startsWith('VK_')) return key.substring(3);
  return key;
}

class UuFloatingKeysOverlay extends StatefulWidget {
  const UuFloatingKeysOverlay({Key? key}) : super(key: key);

  @override
  State<UuFloatingKeysOverlay> createState() => _UuFloatingKeysOverlayState();
}

class _UuFloatingKeysOverlayState extends State<UuFloatingKeysOverlay> {
  List<UuFloatingKey>? _snapshot;
  Worker? _editWorker;
  Timer? _fadeTimer;
  bool _faded = false;
  UuFloatingKey? _dragKey;
  Offset _dragStart = Offset.zero;
  Offset _dragOrigin = Offset.zero;
  bool _dragMoved = false;

  @override
  void initState() {
    super.initState();
    _editWorker = ever(uuState.editLayout, (bool editing) {
      if (editing) {
        _snapshot = uuState.active.keys
            .map((e) => UuFloatingKey.fromJson(e.toJson()))
            .toList();
      }
    });
    _poke();
  }

  @override
  void dispose() {
    _editWorker?.dispose();
    _fadeTimer?.cancel();
    super.dispose();
  }

  // Same idle fade as the tool ball: dim after 4s, restore on touch.
  void _poke() {
    _fadeTimer?.cancel();
    if (_faded) setState(() => _faded = false);
    _fadeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _faded = true);
    });
  }

  void _pressDown(UuFloatingKey key) {
    final input = gFFI.inputModel;
    if (uuState.active.haptics) HapticFeedback.lightImpact();
    if (key.isModifier) {
      input.inputKey(key.key, down: true, press: false);
      return;
    }
    final oldCtrl = input.ctrl;
    final oldAlt = input.alt;
    final oldShift = input.shift;
    final oldMeta = input.command;
    input
      ..ctrl = key.ctrl
      ..alt = key.alt
      ..shift = key.shift
      ..command = key.meta;
    input.inputKey(key.key);
    input
      ..ctrl = oldCtrl
      ..alt = oldAlt
      ..shift = oldShift
      ..command = oldMeta;
  }

  void _pressUp(UuFloatingKey key) {
    if (key.isModifier) {
      gFFI.inputModel.inputKey(key.key, down: false, press: false);
    }
  }

  Widget _keyWidget(
      UuFloatingKey key, UuScheme scheme, bool edit, Size screen) {
    final diameter = 48 * scheme.keyScale;
    final left = (key.x * screen.width - diameter / 2)
        .clamp(0.0, screen.width - diameter);
    final top = (key.y * screen.height - diameter / 2)
        .clamp(0.0, screen.height - diameter);
    // Same look as the idle tool ball: plain black circle, white label.
    final ball = Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withOpacity(0.55),
        border: edit
            ? Border.all(color: MyTheme.accent, width: 2)
            : null,
      ),
      child: Center(
        child: Text(
          key.label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12 * scheme.keyScale,
          ),
        ),
      ),
    );
    Widget child;
    if (edit) {
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) {
          setState(() {
            key.x = (key.x + d.delta.dx / screen.width).clamp(0.0, 1.0);
            key.y = (key.y + d.delta.dy / screen.height).clamp(0.0, 1.0);
          });
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ball,
            Positioned(
              top: -6,
              right: -6,
              child: GestureDetector(
                onTap: () {
                  setState(() => uuState.active.keys.remove(key));
                },
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.redAccent,
                  ),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // Tap = press the key; dragging past the threshold repositions the
      // ball instead (same draggable design as the tool ball).
      child = Listener(
        onPointerDown: (e) {
          _poke();
          _dragKey = key;
          _dragStart = e.position;
          _dragOrigin = Offset(key.x, key.y);
          _dragMoved = false;
          if (key.isModifier) _pressDown(key);
        },
        onPointerMove: (e) {
          if (_dragKey != key) return;
          final d = e.position - _dragStart;
          if (!_dragMoved && d.distance > 10) {
            _dragMoved = true;
            _pressUp(key);
          }
          if (_dragMoved) {
            setState(() {
              key.x = (_dragOrigin.dx + d.dx / screen.width).clamp(0.0, 1.0);
              key.y = (_dragOrigin.dy + d.dy / screen.height).clamp(0.0, 1.0);
            });
          }
        },
        onPointerUp: (_) {
          if (_dragKey != key) return;
          _dragKey = null;
          if (_dragMoved) {
            uuState.save();
            _poke();
          } else {
            if (!key.isModifier) _pressDown(key);
            _pressUp(key);
          }
        },
        onPointerCancel: (_) {
          if (_dragKey != key) return;
          _dragKey = null;
          _pressUp(key);
        },
        child: AnimatedOpacity(
          opacity: _faded ? 0.15 : 0.55,
          duration: const Duration(milliseconds: 600),
          child: ball,
        ),
      );
    }
    return Positioned(left: left, top: top, child: child);
  }

  Future<String?> _pickKey(BuildContext context, List<String> options,
      String initial) async {
    var selected = initial;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('选择键位'),
          content: SizedBox(
            width: 320,
            child: DropdownButton<String>(
              isExpanded: true,
              value: selected,
              items: [
                for (final key in options)
                  DropdownMenuItem(value: key, child: Text(_optionLabel(key))),
              ],
              onChanged: (v) {
                if (v != null) setDialogState(() => selected = v);
              },
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(selected),
                child: const Text('确定')),
          ],
        ),
      ),
    );
  }

  Future<void> _addSingle() async {
    final key = await _pickKey(context, _singleKeyOptions, 'VK_CONTROL');
    if (key == null || !mounted) return;
    setState(() {
      uuState.active.keys.add(UuFloatingKey(
        DateTime.now().microsecondsSinceEpoch.toString(),
        key,
        x: 0.5,
        y: 0.4,
      ));
    });
  }

  Future<void> _addCombo() async {
    bool ctrl = true, alt = false, shift = false, meta = false;
    var selected = 'VK_B';
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('添加组合键'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 6,
                  children: [
                    FilterChip(
                        label: const Text('Ctrl'),
                        selected: ctrl,
                        onSelected: (v) => setDialogState(() => ctrl = v)),
                    FilterChip(
                        label: const Text('Alt'),
                        selected: alt,
                        onSelected: (v) => setDialogState(() => alt = v)),
                    FilterChip(
                        label: const Text('Shift'),
                        selected: shift,
                        onSelected: (v) => setDialogState(() => shift = v)),
                    FilterChip(
                        label: const Text('Win'),
                        selected: meta,
                        onSelected: (v) => setDialogState(() => meta = v)),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButton<String>(
                  isExpanded: true,
                  value: selected,
                  items: [
                    for (final k in _comboKeyOptions)
                      DropdownMenuItem(value: k, child: Text(_optionLabel(k))),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => selected = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop({
                      'key': selected,
                      'ctrl': ctrl,
                      'alt': alt,
                      'shift': shift,
                      'meta': meta,
                    }),
                child: const Text('确定')),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      uuState.active.keys.add(UuFloatingKey(
        DateTime.now().microsecondsSinceEpoch.toString(),
        result['key'] as String,
        ctrl: result['ctrl'] == true,
        alt: result['alt'] == true,
        shift: result['shift'] == true,
        meta: result['meta'] == true,
        x: 0.5,
        y: 0.4,
      ));
    });
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: uuState.active.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('方案名称'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('确定')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    setState(() {
      uuState.active.name = name;
      uuState.activeName.value = name;
    });
    uuState.save();
  }

  Widget _editToolbar() {
    Widget button(String label, VoidCallback onPressed, {bool primary = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: primary ? MyTheme.accent : const Color(0xFF3A3A3C),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
      );
    }

    return Positioned(
      top: 8,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.85),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _rename,
                child: Row(
                  children: [
                    Text(uuState.active.name,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14)),
                    const Icon(Icons.edit, color: Colors.white54, size: 14),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              button('+ 单个按键', _addSingle),
              button('+ 组合键', _addCombo),
              button('清空', () {
                setState(() => uuState.active.keys.clear());
              }),
              button('取消', () {
                setState(() {
                  if (_snapshot != null) {
                    uuState.active.keys
                      ..clear()
                      ..addAll(_snapshot!);
                  }
                  uuState.editLayout.value = false;
                });
              }),
              button('保存', () {
                uuState.save();
                uuState.editLayout.value = false;
              }, primary: true),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final scheme = uuState.active;
      final edit = uuState.editLayout.value;
      final screen = MediaQuery.of(context).size;
      if (scheme.keys.isEmpty && !edit) return const SizedBox.shrink();
      return Stack(
        children: [
          for (final key in scheme.keys) _keyWidget(key, scheme, edit, screen),
          if (edit) _editToolbar(),
        ],
      );
    });
  }
}