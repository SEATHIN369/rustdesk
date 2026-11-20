import 'dart:convert';

import 'package:flutter/material.dart';

import '../../common.dart';
import '../../consts.dart';
import '../../models/platform_model.dart';

const String _kShortcutPadOption = 'shortcut-pad-items';

class ShortcutItem {
  final String id;
  final String key;
  final bool ctrl;
  final bool alt;
  final bool shift;
  final bool meta;
  final bool primary;
  final String desc;

  const ShortcutItem(
    this.id,
    this.key, {
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
    this.meta = false,
    this.primary = false,
    this.desc = '',
  });

  String label(bool isMac) {
    final parts = <String>[];
    if (primary) parts.add(isMac ? 'Cmd' : 'Ctrl');
    if (ctrl) parts.add('Ctrl');
    if (alt) parts.add('Alt');
    if (shift) parts.add('Shift');
    if (meta) parts.add(isMac ? 'Cmd' : 'Win');
    parts.add(_keyLabel(key));
    return parts.join('+');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'key': key,
        'ctrl': ctrl,
        'alt': alt,
        'shift': shift,
        'meta': meta,
        'primary': primary,
        'desc': desc,
      };

  factory ShortcutItem.fromJson(Map<String, dynamic> json) => ShortcutItem(
        (json['id'] ?? DateTime.now().microsecondsSinceEpoch.toString())
            .toString(),
        json['key']?.toString() ?? 'VK_ESCAPE',
        ctrl: json['ctrl'] == true,
        alt: json['alt'] == true,
        shift: json['shift'] == true,
        meta: json['meta'] == true,
        primary: json['primary'] == true,
        desc: json['desc']?.toString() ?? '',
      );

  ShortcutItem copyWith({String? id}) => ShortcutItem(
        id ?? this.id,
        key,
        ctrl: ctrl,
        alt: alt,
        shift: shift,
        meta: meta,
        primary: primary,
        desc: desc,
      );
}

String _keyLabel(String key) {
  if (!key.startsWith('VK_')) return key;
  final name = key.substring(3);
  const special = {
    'ESCAPE': 'Esc',
    'RETURN': 'Enter',
    'BACK': 'Backspace',
    'DELETE': 'Del',
    'INSERT': 'Ins',
    'PAGEUP': 'PgUp',
    'PAGEDOWN': 'PgDn',
    'SPACE': 'Space',
    'LEFT': '←',
    'RIGHT': '→',
    'UP': '↑',
    'DOWN': '↓',
  };
  return special[name] ?? name;
}

const List<ShortcutItem> _defaults = [
  ShortcutItem('d01', 'VK_C', primary: true, desc: '复制'),
  ShortcutItem('d02', 'VK_V', primary: true, desc: '粘贴'),
  ShortcutItem('d03', 'VK_X', primary: true, desc: '剪切'),
  ShortcutItem('d04', 'VK_Z', primary: true, desc: '撤销'),
  ShortcutItem('d05', 'VK_Y', primary: true, desc: '重做'),
  ShortcutItem('d06', 'VK_A', primary: true, desc: '全选'),
  ShortcutItem('d07', 'VK_S', primary: true, desc: '保存'),
  ShortcutItem('d08', 'VK_F', primary: true, desc: '查找'),
  ShortcutItem('d09', 'VK_B', primary: true, desc: '加粗'),
  ShortcutItem('d10', 'VK_I', primary: true, desc: '斜体'),
  ShortcutItem('d11', 'VK_U', primary: true, desc: '下划线'),
  ShortcutItem('d12', 'VK_T', primary: true, desc: '新标签'),
  ShortcutItem('d13', 'VK_W', primary: true, desc: '关标签'),
  ShortcutItem('d14', 'VK_TAB', alt: true, desc: '切换窗口'),
  ShortcutItem('d15', 'VK_F4', alt: true, desc: '关闭窗口'),
  ShortcutItem('d16', 'VK_ESCAPE', ctrl: true, shift: true, desc: '任务管理'),
  ShortcutItem('d17', 'VK_ESCAPE', desc: '退出'),
  ShortcutItem('d18', 'VK_TAB', desc: '切焦点'),
  ShortcutItem('d19', 'VK_RETURN', desc: '确认'),
  ShortcutItem('d20', 'VK_BACK', desc: '退格'),
  ShortcutItem('d21', 'VK_DELETE', desc: '删除'),
  ShortcutItem('d22', 'VK_F2', desc: '重命名'),
  ShortcutItem('d23', 'VK_F5', desc: '刷新'),
  ShortcutItem('d24', 'VK_F11', desc: '全屏'),
  ShortcutItem('d25', 'VK_LEFT', desc: '左'),
  ShortcutItem('d26', 'VK_UP', desc: '上'),
  ShortcutItem('d27', 'VK_DOWN', desc: '下'),
  ShortcutItem('d28', 'VK_RIGHT', desc: '右'),
  ShortcutItem('d29', 'VK_HOME', desc: '行首'),
  ShortcutItem('d30', 'VK_END', desc: '行尾'),
  ShortcutItem('d31', 'VK_PAGEUP', desc: '上页'),
  ShortcutItem('d32', 'VK_PAGEDOWN', desc: '下页'),
];

const List<String> _pickerKeys = [
  'VK_A', 'VK_B', 'VK_C', 'VK_D', 'VK_E', 'VK_F', 'VK_G', 'VK_H', 'VK_I',
  'VK_J', 'VK_K', 'VK_L', 'VK_M', 'VK_N', 'VK_O', 'VK_P', 'VK_Q', 'VK_R',
  'VK_S', 'VK_T', 'VK_U', 'VK_V', 'VK_W', 'VK_X', 'VK_Y', 'VK_Z',
  'VK_0', 'VK_1', 'VK_2', 'VK_3', 'VK_4', 'VK_5', 'VK_6', 'VK_7', 'VK_8',
  'VK_9',
  'VK_ESCAPE', 'VK_TAB', 'VK_RETURN', 'VK_BACK', 'VK_DELETE', 'VK_INSERT',
  'VK_SPACE', 'VK_HOME', 'VK_END', 'VK_PAGEUP', 'VK_PAGEDOWN',
  'VK_LEFT', 'VK_UP', 'VK_DOWN', 'VK_RIGHT',
  'VK_F1', 'VK_F2', 'VK_F3', 'VK_F4', 'VK_F5', 'VK_F6', 'VK_F7', 'VK_F8',
  'VK_F9', 'VK_F10', 'VK_F11', 'VK_F12',
];

List<ShortcutItem> _loadItems() {
  try {
    final raw = bind.mainGetLocalOption(key: _kShortcutPadOption);
    if (raw.isEmpty) return List<ShortcutItem>.from(_defaults);
    final decoded = json.decode(raw);
    if (decoded is List) {
      final items = decoded
          .whereType<Map>()
          .map((e) => ShortcutItem.fromJson(e.cast<String, dynamic>()))
          .toList();
      if (items.isNotEmpty) return items;
    }
  } catch (_) {}
  return List<ShortcutItem>.from(_defaults);
}

Future<void> _saveItems(List<ShortcutItem> items) async {
  await bind.mainSetLocalOption(
    key: _kShortcutPadOption,
    value: json.encode(items.map((e) => e.toJson()).toList()),
  );
}

class MobileShortcutPad extends StatefulWidget {
  const MobileShortcutPad({Key? key}) : super(key: key);

  @override
  State<MobileShortcutPad> createState() => _MobileShortcutPadState();
}

class _MobileShortcutPadState extends State<MobileShortcutPad> {
  late List<ShortcutItem> _items;
  bool _editing = false;

  bool get _isMac => gFFI.ffiModel.pi.platform == kPeerPlatformMacOS;

  @override
  void initState() {
    super.initState();
    _items = _loadItems();
  }

  void _persist() {
    _saveItems(_items);
  }

  void _send(ShortcutItem item) {
    final input = gFFI.inputModel;
    final oldCtrl = input.ctrl;
    final oldAlt = input.alt;
    final oldShift = input.shift;
    final oldMeta = input.command;
    final primaryMeta = item.primary && _isMac;
    input
      ..ctrl = item.primary ? !_isMac : item.ctrl
      ..alt = item.alt
      ..shift = item.shift
      ..command = item.meta || primaryMeta;
    input.inputKey(item.key);
    input
      ..ctrl = oldCtrl
      ..alt = oldAlt
      ..shift = oldShift
      ..command = oldMeta;
  }

  // UU-style browse grid: left "编辑" entry plus large two-line buttons.
  Widget _viewBody() {
    return LayoutBuilder(builder: (context, constraints) {
      final columns = (constraints.maxWidth / 130).floor().clamp(4, 9);
      return GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.6,
        ),
        itemCount: _items.length + 1,
        itemBuilder: (ctx, index) {
          if (index == 0) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _editing = true),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.edit, color: MyTheme.accent, size: 20),
                  const SizedBox(height: 4),
                  Text('编辑',
                      style: TextStyle(color: MyTheme.accent, fontSize: 13)),
                ],
              ),
            );
          }
          final item = _items[index - 1];
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _send(item),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF4A4D52),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(item.label(_isMac),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  if (item.desc.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(item.desc,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ],
                ],
              ),
            ),
          );
        },
      );
    });
  }

  Widget _editBody(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _items.length,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex -= 1;
                final item = _items.removeAt(oldIndex);
                _items.insert(newIndex, item);
              });
              _persist();
            },
            itemBuilder: (ctx, index) {
              final item = _items[index];
              return Material(
                key: ValueKey(item.id),
                color: Colors.transparent,
                child: ListTile(
                  dense: true,
                  leading: ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle, color: Colors.white54),
                  ),
                  title: Text(item.label(_isMac),
                      style:
                          const TextStyle(color: Colors.white, fontSize: 14)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.white54, size: 20),
                    onPressed: () {
                      setState(() => _items.removeAt(index));
                      _persist();
                    },
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              TextButton(
                onPressed: () => setState(() => _editing = false),
                child: Text('完成',
                    style: TextStyle(color: MyTheme.accent, fontSize: 13)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _addItem(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加组合键'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  setState(() =>
                      _items = List<ShortcutItem>.from(_defaults));
                  _persist();
                },
                child: const Text('恢复默认',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _addItem(BuildContext context) async {
    String selectedKey = 'VK_B';
    bool ctrl = true, alt = false, shift = false, meta = false;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('添加组合键'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  children: [
                    FilterChip(
                      label: const Text('Ctrl'),
                      selected: ctrl,
                      onSelected: (v) => setDialogState(() => ctrl = v),
                    ),
                    FilterChip(
                      label: const Text('Alt'),
                      selected: alt,
                      onSelected: (v) => setDialogState(() => alt = v),
                    ),
                    FilterChip(
                      label: const Text('Shift'),
                      selected: shift,
                      onSelected: (v) => setDialogState(() => shift = v),
                    ),
                    FilterChip(
                      label: const Text('Win'),
                      selected: meta,
                      onSelected: (v) => setDialogState(() => meta = v),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButton<String>(
                  isExpanded: true,
                  value: selectedKey,
                  items: [
                    for (final key in _pickerKeys)
                      DropdownMenuItem(
                          value: key, child: Text(_keyLabel(key))),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => selectedKey = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('确定')),
          ],
        ),
      ),
    );
    if (result != true || !mounted) return;
    setState(() {
      _items.add(ShortcutItem(
        DateTime.now().microsecondsSinceEpoch.toString(),
        selectedKey,
        ctrl: ctrl,
        alt: alt,
        shift: shift,
        meta: meta,
      ));
    });
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    return _editing ? _editBody(context) : _viewBody();
  }
}