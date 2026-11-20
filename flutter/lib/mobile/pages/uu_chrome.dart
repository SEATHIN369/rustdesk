import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../common/widgets/dialog.dart';
import '../../models/platform_model.dart';
import '../../models/uu_state.dart';
import 'remote_page.dart';

class UuChrome extends StatefulWidget {
  final String id;
  final VoidCallback onToggleGestureHelp;
  final VoidCallback onShowActions;

  const UuChrome(
      {Key? key,
      required this.id,
      required this.onToggleGestureHelp,
      required this.onShowActions})
      : super(key: key);

  @override
  State<UuChrome> createState() => _UuChromeState();
}

class _UuChromeState extends State<UuChrome> {
  Timer? _hideTimer;
  Timer? _fadeTimer;
  Worker? _railWorker;
  bool _faded = false;

  @override
  void initState() {
    super.initState();
    _railWorker = ever(uuState.railOpen, (bool open) {
      _hideTimer?.cancel();
      if (open) {
        _hideTimer = Timer(const Duration(seconds: 6), () {
          uuState.railOpen.value = false;
        });
      } else {
        _poke();
      }
    });
    _poke();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _fadeTimer?.cancel();
    _railWorker?.dispose();
    super.dispose();
  }

  // Idle edge button fades out after a few seconds without interaction.
  void _poke() {
    _fadeTimer?.cancel();
    if (_faded) setState(() => _faded = false);
    _fadeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _faded = true);
    });
  }

  void _sendWinCombo(String key) {
    final input = gFFI.inputModel;
    final oldCommand = input.command;
    input.command = true;
    input.inputKey(key);
    input.command = oldCommand;
  }

  void _openKeyboard() {
    uuState.railOpen.value = false;
    uuState.keyboardOpen.value = true;
  }

  void _openDrawer(String page) {
    uuState.railOpen.value = false;
    uuState.drawerPage.value = page;
  }

  Widget _railItem(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 26),
          const SizedBox(height: 6),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _edgeButton(Size size) {
    final px =
        (uuState.railX * size.width).clamp(0.0, size.width - 56).toDouble();
    final py =
        (uuState.railY * size.height).clamp(0.0, size.height - 56).toDouble();
    return Positioned(
      left: px,
      top: py,
      child: GestureDetector(
        onTap: () {
          _poke();
          uuState.railOpen.value = true;
        },
        onPanStart: (_) => _poke(),
        onPanUpdate: (d) {
          setState(() {
            final nx =
                (px + d.delta.dx).clamp(0.0, size.width - 56).toDouble();
            final ny =
                (py + d.delta.dy).clamp(0.0, size.height - 56).toDouble();
            uuState.railX = nx / size.width;
            uuState.railY = ny / size.height;
          });
        },
        onPanEnd: (_) {
          uuState.save();
          _poke();
        },
        child: AnimatedOpacity(
          opacity: _faded ? 0.15 : 0.55,
          duration: const Duration(milliseconds: 600),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withOpacity(0.55),
            ),
            child: const Icon(Icons.tune, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }

  // UU-style expanded rail: no background panel, four items spread over the
  // full right edge; tapping anywhere else collapses it.
  Widget _rail() {
    final isPeerAndroid = gFFI.ffiModel.isPeerAndroid;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => uuState.railOpen.value = false,
          ),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: 72,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _railItem(Icons.tune, '操作', () => _openDrawer('menu')),
              _railItem(Icons.keyboard, '键盘', _openKeyboard),
              _railItem(Icons.desktop_windows, '显示桌面',
                  () => _sendWinCombo('VK_D')),
              _railItem(
                  isPeerAndroid ? Icons.build : Icons.grid_view,
                  isPeerAndroid ? '更多操作' : '所有窗口',
                  () => isPeerAndroid
                      ? gFFI.dialogManager.toggleMobileActionsOverlay(ffi: gFFI)
                      : _sendWinCombo('VK_TAB')),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (uuState.keyboardOpen.value || uuState.editLayout.value) {
        return const SizedBox.shrink();
      }
      if (uuState.drawerPage.value != null) {
        return _drawer(context);
      }
      if (uuState.railOpen.value) {
        return _rail();
      }
      return _edgeButton(MediaQuery.of(context).size);
    });
  }

  Widget _drawer(BuildContext context) {
    final page = uuState.drawerPage.value ?? 'menu';
    final width = min(430.0, MediaQuery.of(context).size.width * 0.55);
    final titles = {
      'menu': '操作',
      'schemes': '操控方案',
      'settings': '其他设置',
    };
    return Stack(
      children: [
        // Tapping outside the drawer equals Back (one level up).
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              uuState.drawerPage.value = page == 'menu' ? null : 'menu';
            },
          ),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: width,
          child: Material(
        color: const Color(0xF22C2C2E),
        child: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      page == 'menu' ? Icons.close : Icons.chevron_left,
                      color: Colors.white70,
                    ),
                    onPressed: () {
                      uuState.drawerPage.value = page == 'menu' ? null : 'menu';
                    },
                  ),
                  Expanded(
                    child: Text(titles[page] ?? '',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const Divider(height: 1, color: Colors.white12),
              Expanded(
                child: page == 'menu'
                    ? _menuPage(context)
                    : page == 'schemes'
                        ? _schemesPage(context)
                        : _settingsPage(context),
              ),
            ],
          ),
        ),
          ),
        ),
      ],
    );
  }

  Widget _menuPage(BuildContext context) {
    Widget tile(IconData icon, String label, VoidCallback onTap,
        {Color? color}) {
      return ListTile(
        leading: Icon(icon, color: color ?? Colors.white70, size: 22),
        title: Text(label,
            style: TextStyle(color: color ?? Colors.white, fontSize: 14)),
        onTap: onTap,
      );
    }

    return ListView(
      children: [
        tile(Icons.keyboard, '操控方案', () => uuState.drawerPage.value = 'schemes'),
        tile(Icons.tune, '其他设置', () => uuState.drawerPage.value = 'settings'),
        tile(Icons.tv, '会话设置', () {
          uuState.drawerPage.value = null;
          showOptions(context, widget.id, gFFI.dialogManager);
        }),
        tile(Icons.more_vert, '更多操作', () {
          uuState.drawerPage.value = null;
          widget.onShowActions();
        }),
        tile(Icons.touch_app, '手势与触摸模式', () {
          uuState.drawerPage.value = null;
          widget.onToggleGestureHelp();
        }),
        const Divider(color: Colors.white12),
        tile(Icons.clear, '断开连接', () {
          clientClose(gFFI.sessionId, gFFI);
        }, color: Colors.redAccent),
      ],
    );
  }

  Widget _schemesPage(BuildContext context) {
    return Obx(() {
      final schemes = uuState.schemes;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('点按卡片切换方案',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.5), fontSize: 11)),
                ),
                TextButton.icon(
                  onPressed: () => _newScheme(context),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('新建'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: schemes.length,
              itemBuilder: (ctx, index) {
                final scheme = schemes[index];
                final active = scheme.name == uuState.activeName.value;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A3A3C),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: active ? MyTheme.accent : Colors.transparent),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.keyboard, color: Colors.white70),
                    title: Text(scheme.name,
                        style: TextStyle(
                            color: active ? MyTheme.accent : Colors.white,
                            fontSize: 14)),
                    subtitle: Text('${scheme.keys.length} 个悬浮键',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11)),
                    onTap: () {
                      uuState.activeName.value = scheme.name;
                      uuState.save();
                    },
                    trailing: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert,
                          color: Colors.white54, size: 20),
                      onSelected: (v) => _schemeAction(v, index),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('编辑布局')),
                        PopupMenuItem(value: 'rename', child: Text('重命名')),
                        PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    });
  }

  Future<void> _schemeAction(String action, int index) async {
    final scheme = uuState.schemes[index];
    switch (action) {
      case 'edit':
        uuState.activeName.value = scheme.name;
        uuState.drawerPage.value = null;
        uuState.keyboardOpen.value = false;
        uuState.editLayout.value = true;
        uuState.save();
        break;
      case 'rename':
        final controller = TextEditingController(text: scheme.name);
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
        if (uuState.schemes.any((s) => s.name == name && s != scheme)) return;
        setState(() {
          if (uuState.activeName.value == scheme.name) {
            uuState.activeName.value = name;
          }
          scheme.name = name;
        });
        uuState.save();
        break;
      case 'delete':
        if (uuState.schemes.length <= 1) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('删除方案'),
            content: Text('确定删除「${scheme.name}」？'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('取消')),
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('删除')),
            ],
          ),
        );
        if (confirm != true || !mounted) return;
        setState(() {
          uuState.schemes.removeAt(index);
          if (uuState.activeName.value == scheme.name) {
            uuState.activeName.value = uuState.schemes.first.name;
          }
        });
        uuState.save();
        break;
    }
  }

  Future<void> _newScheme(BuildContext context) async {
    final controller = TextEditingController(text: '新方案');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建方案'),
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
    if (uuState.schemes.any((s) => s.name == name)) return;
    setState(() {
      uuState.schemes.add(UuScheme(name: name));
      uuState.activeName.value = name;
    });
    uuState.save();
  }

  Widget _sliderRow(String label, double value, double min, double max,
      ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: (v) {
                setState(() => onChanged(v));
              },
              onChangeEnd: (_) => uuState.save(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleRow(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(label,
          style: const TextStyle(color: Colors.white, fontSize: 13)),
      value: value,
      onChanged: (v) {
        setState(() => onChanged(v));
        uuState.save();
      },
    );
  }

  Widget _settingsPage(BuildContext context) {
    final scheme = uuState.active;
    final sessionId = gFFI.sessionId;
    bool optionOn(String option) =>
        bind.sessionGetToggleOptionSync(sessionId: sessionId, arg: option);
    void toggleOption(String option) {
      bind.sessionToggleOption(sessionId: sessionId, value: option);
      setState(() {});
    }

    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Text('基础设置',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
        ),
        _sliderRow('键位透明度', scheme.opacity, 0.1, 0.9, (v) {
          scheme.opacity = v;
        }),
        _sliderRow('按键放大', scheme.keyScale, 0.7, 1.6, (v) {
          scheme.keyScale = v;
        }),
        _toggleRow('双指缩放', scheme.pinchZoom, (v) {
          scheme.pinchZoom = v;
        }),
        _toggleRow('点击按键时震动', scheme.haptics, (v) {
          scheme.haptics = v;
        }),
        const Divider(color: Colors.white12),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Text('被控端',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
        ),
        _toggleRow('被控端静音运行', optionOn('disable-audio'), (v) {
          toggleOption('disable-audio');
        }),
        _toggleRow('被控端防窥模式（关闭显示器）', optionOn('privacy-mode'), (v) {
          toggleOption('privacy-mode');
        }),
      ],
    );
  }
}