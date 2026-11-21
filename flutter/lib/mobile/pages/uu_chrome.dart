import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../common/shared_state.dart';
import '../../common/widgets/dialog.dart';
import '../../consts.dart';
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
  Timer? _privacyStartTimer;
  Timer? _privacyRetryTimer;
  Timer? _privacyFailTimer;
  bool? _privacyPendingOn;
  bool _mutePending = false;
  Timer? _mutePendingTimer;
  Worker? _privacyWorker;
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
    _privacyWorker = ever(PrivacyModeState.find(widget.id), (String _) {
      if (!mounted || _privacyPendingOn == null) return;
      _privacyStartTimer?.cancel();
      _privacyRetryTimer?.cancel();
      _privacyFailTimer?.cancel();
      setState(() => _privacyPendingOn = null);
    });
    _poke();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _fadeTimer?.cancel();
    _privacyStartTimer?.cancel();
    _privacyRetryTimer?.cancel();
    _privacyFailTimer?.cancel();
    _mutePendingTimer?.cancel();
    _privacyWorker?.dispose();
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
      child: Center(
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
            children: [
              // Each item owns a full quarter of the right edge, not just
              // the small icon area.
              Expanded(
                  child: _railItem(Icons.tune, '操作', () => _openDrawer('menu'))),
              Expanded(child: _railItem(Icons.keyboard, '键盘', _openKeyboard)),
              Expanded(
                  child: _railItem(Icons.desktop_windows, '显示桌面',
                      () => _sendWinCombo('VK_D'))),
              Expanded(
                child: _railItem(
                    isPeerAndroid ? Icons.build : Icons.grid_view,
                    isPeerAndroid ? '更多操作' : '所有窗口',
                    () => isPeerAndroid
                        ? gFFI.dialogManager.toggleMobileActionsOverlay(ffi: gFFI)
                        : _sendWinCombo('VK_TAB')),
              ),
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
        final name = await _withIme(() => showDialog<String>(
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
        ));
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
    final name = await _withIme(() => showDialog<String>(
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
    ));
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

  Widget _toggleRow(String label, bool value, ValueChanged<bool> onChanged,
      {String? subtitle}) {
    return SwitchListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(label,
          style: const TextStyle(color: Colors.white, fontSize: 13)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
      value: value,
      onChanged: (v) {
        setState(() => onChanged(v));
        uuState.save();
      },
    );
  }

  // The remote page permanently holds FLAG_ALT_FOCUSABLE_IM so its hidden
  // TextField can control the IME; that flag also suppresses the system
  // keyboard for dialogs, so lift it only while an input dialog is up.
  Future<T?> _withIme<T>(Future<T?> Function() run) async {
    await gFFI.invokeMethod("enable_soft_keyboard", true);
    try {
      return await run();
    } finally {
      if (mounted) gFFI.invokeMethod("enable_soft_keyboard", false);
    }
  }

  bool get _hostControlSupported =>
      gFFI.ffiModel.pi.platformAdditions.containsKey(
          kPlatformAdditionsUuHostControl);

  // Reuses the privacy-mode message as a command channel: the host side of
  // this fork treats impl keys prefixed with "uu:" as host controls.
  void _sendHostCmd(String cmd, bool on) {
    bind.sessionTogglePrivacyMode(
        sessionId: gFFI.sessionId, implKey: 'uu:$cmd', on: on);
  }

  String _hostIntentKey(String name) => 'uu-host-$name:${widget.id}';

  bool _hostIntent(String name, {bool fallback = false}) {
    final raw = bind.mainGetLocalOption(key: _hostIntentKey(name));
    return raw.isEmpty ? fallback : raw == '1';
  }

  void _setHostIntent(String name, bool on) {
    bind.mainSetLocalOption(key: _hostIntentKey(name), value: on ? '1' : '0');
  }

  String _hostSetting(String name, String fallback) {
    final raw = bind.mainGetLocalOption(key: _hostIntentKey(name));
    return raw.isEmpty ? fallback : raw;
  }

  void _setHostSetting(String name, String value) {
    bind.mainSetLocalOption(key: _hostIntentKey(name), value: value);
  }

  (int, int) _parseDisplayMode(String mode) {
    final parts = mode.split('x');
    if (parts.length == 2) {
      return (int.tryParse(parts[0]) ?? 1920, int.tryParse(parts[1]) ?? 1080);
    }
    return (1920, 1080);
  }

  void _toggleMute(bool on) {
    _mutePendingTimer?.cancel();
    setState(() {
      _mutePending = true;
      _setHostIntent('mute', on);
    });
    _sendHostCmd('mute', on);
    // No ack frame for host controls; give the host a beat, then settle.
    _mutePendingTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _mutePending = false);
    });
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
    final hostControl = _hostControlSupported;
    final muted = _hostIntent('mute');
    final restoreOnDisconnect = _hostIntent('restore');
    final displayMode = _hostSetting('display', '1920x1080');

    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Text('基础设置',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
        ),
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
        Builder(builder: (context) {
          final subtitle = _mutePending
              ? Row(children: [
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white70),
                  ),
                  const SizedBox(width: 8),
                  Text(muted ? '正在静音…' : '正在恢复声音…',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11)),
                ])
              : Text(
                  hostControl
                      ? '静音被控端扬声器（不影响远程串流）'
                      : '需被控端为本项目编译版 RustDesk',
                  style:
                      const TextStyle(color: Colors.white38, fontSize: 11));
          return SwitchListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: const Text('电脑静音',
                style: TextStyle(color: Colors.white, fontSize: 13)),
            subtitle: subtitle,
            value: muted,
            onChanged: _mutePending
                ? null
                : (v) {
                    if (!hostControl) {
                      showToast('需被控端为本项目编译版 RustDesk');
                      return;
                    }
                    _toggleMute(v);
                  },
          );
        }),
        _toggleRow('退出远控时锁定电脑', optionOn('lock-after-session-end'), (v) {
          toggleOption('lock-after-session-end');
        }),
        Obx(() {
          final state = PrivacyModeState.find(widget.id);
          final impls = gFFI.ffiModel.pi
              .platformAdditions[kPlatformAdditionsSupportedPrivacyModeImpl] as List?;
          // UU-style physical screen-off: only the virtual-display impl
          // unplugs the physical monitors; the others just overlay black.
          const vdImpl = 'privacy_mode_impl_virtual_display';
          final supported = impls != null &&
              impls.any((e) => (e as List)[0] == vdImpl);
          final on = state.value.isNotEmpty;
          final pending = _privacyPendingOn;
          final subtitle = pending != null
              ? Row(children: [
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white70),
                  ),
                  const SizedBox(width: 8),
                  Text(pending ? '正在开启…' : '正在关闭…',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11)),
                ])
              : supported
                  ? const Text('断开物理显示器，画面切到虚拟屏',
                      style: TextStyle(color: Colors.white38, fontSize: 11))
                  : const Text('需被控端安装并以服务运行官方 RustDesk',
                      style: TextStyle(color: Colors.white38, fontSize: 11));
          return SwitchListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: const Text('操控时物理关屏（虚拟屏防窥）',
                style: TextStyle(color: Colors.white, fontSize: 13)),
            subtitle: subtitle,
            value: pending ?? on,
            onChanged: (v) {
              if (pending != null) return;
              if (!supported) {
                showToast('被控端不支持虚拟屏防窥（需安装版+服务运行）');
                return;
              }
              if (!on && gFFI.ffiModel.permissions['privacy_mode'] == false) {
                showToast('被控端未授权防窥模式');
                return;
              }
              setState(() => _privacyPendingOn = !on);
              if (hostControl) {
                final (w, h) = _parseDisplayMode(displayMode);
                _sendHostCmd('display:${w}x$h', true);
                _sendHostCmd(
                    'privacy-persist', !on ? !restoreOnDisconnect : false);
              }
              _privacyStartTimer?.cancel();
              _privacyRetryTimer?.cancel();
              _privacyFailTimer?.cancel();
              if (!on) {
                // turn_on only waits 5s for the virtual display to appear, but
                // Amyuni's monitor needs ~6s to reach ACTIVE. Plug it first so
                // the server-side check finds it instead of racing.
                final preplug = gFFI.ffiModel.pi.isAmyuniIdd;
                final hadVirtualDisplay =
                    gFFI.ffiModel.pi.RustDeskVirtualDisplays.isNotEmpty;
                void requestPrivacy() {
                  if (!mounted || _privacyPendingOn != true) return;
                  bind.sessionTogglePrivacyMode(
                      sessionId: sessionId, implKey: vdImpl, on: true);
                }

                if (preplug) {
                  bind.sessionToggleVirtualDisplay(
                      sessionId: sessionId, index: 0, on: true);
                  _privacyStartTimer =
                      Timer(const Duration(seconds: 4), requestPrivacy);
                } else {
                  requestPrivacy();
                }
                _privacyRetryTimer = Timer(const Duration(seconds: 12), () {
                  if (!mounted || _privacyPendingOn != true) return;
                  if (PrivacyModeState.find(widget.id).value.isEmpty) {
                    requestPrivacy();
                  }
                });
                _privacyFailTimer = Timer(const Duration(seconds: 20), () {
                  if (!mounted || _privacyPendingOn != true) return;
                  if (PrivacyModeState.find(widget.id).value.isEmpty) {
                    if (preplug && !hadVirtualDisplay) {
                      bind.sessionToggleVirtualDisplay(
                          sessionId: sessionId, index: 0, on: false);
                    }
                    setState(() => _privacyPendingOn = null);
                    showToast('开启失败：被控端未找到虚拟显示器，驱动刚装好时请重启电脑再试');
                  }
                });
              } else {
                _privacyFailTimer = Timer(const Duration(seconds: 6), () {
                  if (!mounted || _privacyPendingOn != false) return;
                  setState(() => _privacyPendingOn = null);
                  showToast('关闭防窥未响应，请稍后重试');
                });
              }
            },
          );
        });
        _toggleRow('断开后自动恢复（声音与屏幕）',
            hostControl && restoreOnDisconnect, (v) {
          if (!hostControl) return;
          setState(() {
            _setHostIntent('restore', v);
            _sendHostCmd('restore', v);
            if (PrivacyModeState.find(widget.id).value.isNotEmpty) {
              _sendHostCmd('privacy-persist', !v);
            }
          });
        },
            subtitle: hostControl
                ? (restoreOnDisconnect
                    ? '断开后恢复原来的声音和屏幕'
                    : '保持静音/关屏状态，长期有效')
                : '需被控端为本项目编译版 RustDesk'),
        if (hostControl)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: const Text('虚拟屏尺寸',
                style: TextStyle(color: Colors.white, fontSize: 13)),
            subtitle: Text('当前 $displayMode · 下次开启关屏时生效',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
            trailing: const Icon(Icons.chevron_right,
                color: Colors.white54, size: 18),
            onTap: () async {
              const modes = {
                '1280x720': '1280×720（界面最大）',
                '1536x864': '1536×864（约 125%）',
                '1920x1080': '1920×1080（100%）',
                '2560x1440': '2560×1440（更细腻）',
              };
              final picked = await showDialog<String>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: const Text('虚拟屏尺寸'),
                  children: modes.entries
                      .map((e) => SimpleDialogOption(
                            onPressed: () => Navigator.of(ctx).pop(e.key),
                            child: Text(
                                '${e.value}${e.key == displayMode ? '  ✓' : ''}'),
                          ))
                      .toList(),
                ),
              );
              if (picked == null || !mounted) return;
              _setHostSetting('display', picked);
              final (w, h) = _parseDisplayMode(picked);
              _sendHostCmd('display:${w}x$h', true);
              setState(() {});
            },
          ),
        const Divider(color: Colors.white12),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Text('自动解锁（Windows 锁屏）',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
        ),
        Builder(builder: (context) {
          final unlockKey = 'uu-auto-unlock:${widget.id}';
          Map<String, dynamic> cfg = {};
          try {
            final raw = bind.mainGetLocalOption(key: unlockKey);
            if (raw.isNotEmpty) cfg = json.decode(raw) as Map<String, dynamic>;
          } catch (_) {}
          final pwd = cfg['pwd']?.toString() ?? '';
          void store() => bind.mainSetLocalOption(
              key: unlockKey, value: json.encode(cfg));
          return Column(
            children: [
              _toggleRow('连接后自动输入密码解锁', cfg['on'] == true, (v) {
                cfg['on'] = v;
                store();
              }),
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                title: const Text('登录密码',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
                subtitle: Text(pwd.isEmpty ? '未设置' : '已设置',
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 11)),
                trailing: const Icon(Icons.edit,
                    color: Colors.white54, size: 18),
                onTap: () async {
                  final controller = TextEditingController(text: pwd);
                  final ok = await _withIme(() => showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Windows 登录密码'),
                      content: TextField(
                        controller: controller,
                        obscureText: true,
                        autofocus: true,
                        decoration: const InputDecoration(
                            hintText: '仅保存在本机配置中'),
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
                  ));
                  if (ok != true || !mounted) return;
                  setState(() => cfg['pwd'] = controller.text);
                  store();
                },
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('连接建立 2 秒后自动输入密码并回车。仅在电脑处于锁屏时开启；未锁屏时密码会被输入到当前焦点窗口。',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
              ),
            ],
          );
        }),
      ],
    );
  }
}