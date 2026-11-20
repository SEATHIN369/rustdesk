import 'package:flutter/material.dart';

import '../../common.dart';
import '../../consts.dart';

void showMobileShortcutPad(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1F1F1F),
    builder: (_) => const MobileShortcutPad(),
  );
}

class MobileShortcutPad extends StatefulWidget {
  const MobileShortcutPad({Key? key}) : super(key: key);

  @override
  State<MobileShortcutPad> createState() => _MobileShortcutPadState();
}

class _Combo {
  final String label;
  final String key;
  final bool ctrl;
  final bool alt;
  final bool shift;
  final bool meta;
  final bool primary;

  const _Combo(this.label, this.key,
      {this.ctrl = false,
      this.alt = false,
      this.shift = false,
      this.meta = false,
      this.primary = false});
}

const List<_Combo> _editCombos = [
  _Combo('Ctrl+C', 'VK_C', primary: true),
  _Combo('Ctrl+V', 'VK_V', primary: true),
  _Combo('Ctrl+X', 'VK_X', primary: true),
  _Combo('Ctrl+Z', 'VK_Z', primary: true),
  _Combo('Ctrl+Y', 'VK_Y', primary: true),
  _Combo('Ctrl+A', 'VK_A', primary: true),
  _Combo('Ctrl+S', 'VK_S', primary: true),
  _Combo('Ctrl+F', 'VK_F', primary: true),
  _Combo('Ctrl+B', 'VK_B', primary: true),
  _Combo('Ctrl+I', 'VK_I', primary: true),
  _Combo('Ctrl+U', 'VK_U', primary: true),
  _Combo('Ctrl+P', 'VK_P', primary: true),
  _Combo('Ctrl+H', 'VK_H', primary: true),
  _Combo('Ctrl+N', 'VK_N', primary: true),
  _Combo('Ctrl+T', 'VK_T', primary: true),
  _Combo('Ctrl+W', 'VK_W', primary: true),
];

const List<_Combo> _systemCombos = [
  _Combo('Alt+Tab', 'VK_TAB', alt: true),
  _Combo('Alt+F4', 'VK_F4', alt: true),
  _Combo('Ctrl+Shift+Esc', 'VK_ESCAPE', ctrl: true, shift: true),
  _Combo('Win+D', 'VK_D', meta: true),
  _Combo('Win+E', 'VK_E', meta: true),
  _Combo('Win+L', 'VK_L', meta: true),
  _Combo('Win+R', 'VK_R', meta: true),
  _Combo('Esc', 'VK_ESCAPE'),
  _Combo('Tab', 'VK_TAB'),
  _Combo('Enter', 'VK_RETURN'),
  _Combo('Backspace', 'VK_BACK'),
  _Combo('Delete', 'VK_DELETE'),
  _Combo('F2', 'VK_F2'),
  _Combo('F5', 'VK_F5'),
  _Combo('F11', 'VK_F11'),
];

const List<_Combo> _navCombos = [
  _Combo('←', 'VK_LEFT'),
  _Combo('↑', 'VK_UP'),
  _Combo('↓', 'VK_DOWN'),
  _Combo('→', 'VK_RIGHT'),
  _Combo('Home', 'VK_HOME'),
  _Combo('End', 'VK_END'),
  _Combo('PgUp', 'VK_PAGEUP'),
  _Combo('PgDn', 'VK_PAGEDOWN'),
];

class _MobileShortcutPadState extends State<MobileShortcutPad> {
  bool get _isMac => gFFI.ffiModel.pi.platform == kPeerPlatformMacOS;

  void _send(_Combo combo) {
    final input = gFFI.inputModel;
    final oldCtrl = input.ctrl;
    final oldAlt = input.alt;
    final oldShift = input.shift;
    final oldMeta = input.command;
    final primaryMeta = combo.primary && _isMac;
    input
      ..ctrl = combo.primary ? !_isMac : combo.ctrl
      ..alt = combo.alt
      ..shift = combo.shift
      ..command = combo.meta || primaryMeta;
    input.inputKey(combo.key);
    input
      ..ctrl = oldCtrl
      ..alt = oldAlt
      ..shift = oldShift
      ..command = oldMeta;
  }

  Widget _section(String title, List<_Combo> combos) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(title,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final combo in combos)
              OutlinedButton(
                onPressed: () => _send(combo),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withOpacity(0.25)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(combo.label, style: const TextStyle(fontSize: 13)),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final input = gFFI.inputModel;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Row(
                children: [
                  const Expanded(
                    child: Text('快捷键',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                  ),
                  Text('修饰键可配合软键盘使用',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 11)),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _modifier('Ctrl', input.ctrl,
                      (v) => setState(() => input.ctrl = v)),
                  _modifier('Alt', input.alt,
                      (v) => setState(() => input.alt = v)),
                  _modifier('Shift', input.shift,
                      (v) => setState(() => input.shift = v)),
                  _modifier(_isMac ? 'Cmd' : 'Win', input.command,
                      (v) => setState(() => input.command = v)),
                ],
              ),
              _section('编辑', _editCombos),
              _section('系统与功能键', _systemCombos),
              _section('方向与翻页', _navCombos),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modifier(String label, bool active, ValueChanged<bool> onChanged) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: active,
      onSelected: onChanged,
      labelStyle: TextStyle(color: active ? Colors.black : Colors.white),
      selectedColor: MyTheme.accent,
      backgroundColor: Colors.transparent,
      side: BorderSide(color: Colors.white.withOpacity(0.3)),
      visualDensity: VisualDensity.compact,
    );
  }
}