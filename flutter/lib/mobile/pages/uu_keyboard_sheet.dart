import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../common.dart';
import '../../consts.dart';
import '../../models/input_model.dart';
import '../../models/uu_state.dart';
import 'shortcut_pad.dart';

class UuKeyboardSheet extends StatefulWidget {
  final VoidCallback onClose;
  final VoidCallback onOpenIme;

  const UuKeyboardSheet(
      {Key? key, required this.onClose, required this.onOpenIme})
      : super(key: key);

  @override
  State<UuKeyboardSheet> createState() => _UuKeyboardSheetState();
}

class _UuKeyboardSheetState extends State<UuKeyboardSheet> {
  int _tab = 2;

  Widget _tabButton(int index, String label) {
    final selected = _tab == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _tab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? MyTheme.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? MyTheme.accent : Colors.white70,
              fontSize: 15,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final height =
        MediaQuery.of(context).size.height * kUuKeyboardSheetFraction;
    return Container(
      height: height,
      color: const Color(0xFF313135),
      child: Column(
        children: [
          Row(
            children: [
              _tabButton(0, '输入法'),
              _tabButton(1, '快捷键'),
              _tabButton(2, '电脑键盘'),
              IconButton(
                icon: const Icon(Icons.cancel, color: Colors.white70, size: 22),
                onPressed: widget.onClose,
              ),
            ],
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                _imeTab(),
                const MobileShortcutPad(embedded: true),
                const _PcKeyboard(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imeTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '用系统输入法打字，候选词与联想照常可用',
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: widget.onOpenIme,
            icon: const Icon(Icons.keyboard, size: 18),
            label: const Text('唤起系统输入法'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withOpacity(0.3)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _PcKey {
  final String label;
  final String? upper;
  final String send;
  final IconData? icon;
  final int flex;

  const _PcKey(this.label, this.send,
      {this.upper, this.icon, this.flex = 1});
}

const List<List<_PcKey>> _page1 = [
  [
    _PcKey('1', '1'), _PcKey('2', '2'), _PcKey('3', '3'), _PcKey('4', '4'),
    _PcKey('5', '5'), _PcKey('6', '6'), _PcKey('7', '7'), _PcKey('8', '8'),
    _PcKey('9', '9'), _PcKey('0', '0'),
  ],
  [
    _PcKey('Q', 'q'), _PcKey('W', 'w'), _PcKey('E', 'e'), _PcKey('R', 'r'),
    _PcKey('T', 't'), _PcKey('Y', 'y'), _PcKey('U', 'u'), _PcKey('I', 'i'),
    _PcKey('O', 'o'), _PcKey('P', 'p'),
  ],
  [
    _PcKey('A', 'a'), _PcKey('S', 's'), _PcKey('D', 'd'), _PcKey('F', 'f'),
    _PcKey('G', 'g'), _PcKey('H', 'h'), _PcKey('J', 'j'), _PcKey('K', 'k'),
    _PcKey('L', 'l'), _PcKey('', 'VK_BACK', icon: Icons.backspace, flex: 1),
  ],
  [
    _PcKey('Z', 'z'), _PcKey('X', 'x'), _PcKey('C', 'c'), _PcKey('V', 'v'),
    _PcKey('B', 'b'), _PcKey('N', 'n'), _PcKey('M', 'm'),
    _PcKey('Space', 'VK_SPACE', flex: 2),
    _PcKey('Enter', 'VK_RETURN', flex: 2),
  ],
];

const List<List<_PcKey>> _page2 = [
  [
    _PcKey('-', '-', upper: '_'), _PcKey('=', '=', upper: '+'),
    _PcKey('[', '[', upper: '{'), _PcKey(']', ']', upper: '}'),
    _PcKey('\\', '\\', upper: '|'), _PcKey(';', ';', upper: ':'),
    _PcKey("'", "'", upper: '"'), _PcKey(',', ',', upper: '<'),
    _PcKey('.', '.', upper: '>'), _PcKey('/', '/', upper: '?'),
  ],
  [
    _PcKey('F1', 'VK_F1'), _PcKey('F2', 'VK_F2'), _PcKey('F3', 'VK_F3'),
    _PcKey('F4', 'VK_F4'), _PcKey('PrtScr', 'VK_SNAPSHOT'),
    _PcKey('ScrLK', 'VK_SCROLL'), _PcKey('Pause', 'VK_PAUSE'),
    _PcKey('Esc', 'VK_ESCAPE'), _PcKey('Tab', 'VK_TAB'),
    _PcKey('`', '`', upper: '~'),
  ],
  [
    _PcKey('F5', 'VK_F5'), _PcKey('F6', 'VK_F6'), _PcKey('F7', 'VK_F7'),
    _PcKey('F8', 'VK_F8'), _PcKey('Ins', 'VK_INSERT'), _PcKey('Home', 'VK_HOME'),
    _PcKey('PgUp', 'VK_PRIOR'), _PcKey('Caps', 'VK_CAPITAL'),
    _PcKey('', 'VK_UP', icon: Icons.arrow_drop_up),
  ],
  [
    _PcKey('F9', 'VK_F9'), _PcKey('F10', 'VK_F10'), _PcKey('F11', 'VK_F11'),
    _PcKey('F12', 'VK_F12'), _PcKey('Del', 'VK_DELETE'), _PcKey('End', 'VK_END'),
    _PcKey('PgDn', 'VK_NEXT'),
    _PcKey('', 'VK_LEFT', icon: Icons.arrow_left),
    _PcKey('', 'VK_DOWN', icon: Icons.arrow_drop_down),
    _PcKey('', 'VK_RIGHT', icon: Icons.arrow_right),
  ],
];

class _PcKeyboard extends StatefulWidget {
  const _PcKeyboard({Key? key}) : super(key: key);

  @override
  State<_PcKeyboard> createState() => _PcKeyboardState();
}

class _PcKeyboardState extends State<_PcKeyboard> {
  final _pageController = PageController();
  int _page = 0;

  InputModel get input => gFFI.inputModel;

  UuScheme get scheme => uuState.active;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _tapKey(_PcKey key) {
    if (scheme.haptics) HapticFeedback.lightImpact();
    var send = key.send;
    if (key.upper != null && input.shift) send = key.upper!;
    input.inputKey(send);
  }

  void _setFlag(String name, bool value) {
    switch (name) {
      case 'VK_CONTROL':
        input.ctrl = value;
        break;
      case 'VK_SHIFT':
        input.shift = value;
        break;
      case 'VK_MENU':
        input.alt = value;
        break;
      case 'Meta':
        input.command = value;
        break;
    }
  }

  bool _flag(String name) {
    switch (name) {
      case 'VK_CONTROL':
        return input.ctrl;
      case 'VK_SHIFT':
        return input.shift;
      case 'VK_MENU':
        return input.alt;
      case 'Meta':
        return input.command;
    }
    return false;
  }

  Widget _modifier(String label, String name) {
    final active = _flag(name);
    final latch = scheme.comboLatch;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Listener(
          onPointerDown: latch
              ? null
              : (_) => setState(() => _setFlag(name, true)),
          onPointerUp: latch
              ? null
              : (_) => setState(() => _setFlag(name, false)),
          onPointerCancel: latch
              ? null
              : (_) => setState(() => _setFlag(name, false)),
          child: GestureDetector(
            onTap: latch
                ? () => setState(() => _setFlag(name, !active))
                : null,
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color: active ? MyTheme.accent : const Color(0xFF48484A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: active ? Colors.black : Colors.white,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _modifierRow() {
    final isMac = gFFI.ffiModel.pi.platform == kPeerPlatformMacOS;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() => scheme.comboLatch = !scheme.comboLatch);
              uuState.save();
            },
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: scheme.comboLatch,
                    onChanged: (v) {
                      setState(() => scheme.comboLatch = v ?? true);
                      uuState.save();
                    },
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const Text('组合键模式',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _modifier('Ctrl', 'VK_CONTROL'),
          _modifier('Shift', 'VK_SHIFT'),
          _modifier('Alt', 'VK_MENU'),
          _modifier(isMac ? 'Cmd' : 'Win', 'Meta'),
        ],
      ),
    );
  }

  Widget _keyButton(_PcKey key) {
    return Expanded(
      flex: key.flex,
      child: Padding(
        padding: const EdgeInsets.all(2.5),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _tapKey(key),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF48484A),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: key.icon != null
                  ? Icon(key.icon, color: Colors.white, size: 20)
                  : key.upper != null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(key.upper!,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 9)),
                            Text(key.label,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12)),
                          ],
                        )
                      : Text(key.label,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pageView(List<List<_PcKey>> rows) {
    return Column(
      children: [
        for (final row in rows)
          Expanded(
            child: Row(children: [for (final key in row) _keyButton(key)]),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _modifierRow(),
        Expanded(
          child: PageView(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _page = i),
            children: [_pageView(_page1), _pageView(_page2)],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 2; i++)
                Container(
                  width: 22,
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: _page == i
                        ? Colors.white70
                        : Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}