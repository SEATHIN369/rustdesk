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

const String _kPrivacyVdImpl = 'privacy_mode_impl_virtual_display';

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
  static const _imageQualityLabels = {
    kRemoteImageQualityBest: '清晰',
    kRemoteImageQualityBalanced: '平衡',
    kRemoteImageQualityLow: '流畅',
    kRemoteImageQualityCustom: '自定义',
  };

  Timer? _hideTimer;
  Timer? _fadeTimer;
  Timer? _privacyStartTimer;
  Timer? _privacyRetryTimer;
  Timer? _privacyFailTimer;
  Timer? _mutePendingTimer;
  bool? _privacyPendingOn;
  bool _mutePending = false;
  Worker? _privacyWorker;
  Worker? _railWorker;
  bool _faded = false;
  final Set<String> _expanded = {};
  String? _imageQuality;
  bool _imageQualityLoaded = false;
  bool _keyboardMapSupported = false;
  bool _keyboardMap = false;

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
    _loadKeyboardMode();
    _loadImageQuality();
    _privacyWorker = ever(PrivacyModeState.find(widget.id), (String _) {
      if (!mounted || _privacyPendingOn == null) return;
      _privacyStartTimer?.cancel();
      _privacyRetryTimer?.cancel();
      _privacyFailTimer?.cancel();
      setState(() => _privacyPendingOn = null);
    });
    _migrateScaleDefault();
    _restorePrivacyIntent();
    _poke();
  }

  // 125% is the default for the virtual display: a 1080p/1k stream is
  // unreadable at 100% on a phone. One-time migration from the old default.
  void _migrateScaleDefault() {
    const flag = 'uu-scale-125-migrated';
    if (bind.mainGetLocalOption(key: flag) == '1') return;
    bind.mainSetLocalOption(key: flag, value: '1');
    final stored = _hostSetting('scale', '');
    if (stored.isEmpty || stored == '100') {
      _setHostSetting('scale', '125');
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted || !_hostControlSupported) return;
        _sendHostCmd('scale:125', true);
      });
    }
  }

  // Physical screen-off is an explicit per-peer choice; the host restores
  // the screen on every disconnect, so re-apply it on reconnect.
  void _restorePrivacyIntent() {
    if (!_hostIntent('privacy')) return;
    var attempts = 0;
    void attempt() {
      if (!mounted) return;
      if (PrivacyModeState.find(widget.id).value.isNotEmpty) return;
      if (_privacySupported()) {
        _togglePrivacy(true, auto: true);
        return;
      }
      // Peer info can arrive a few seconds after the page is built.
      if (++attempts < 3) {
        Timer(const Duration(seconds: 3), attempt);
      }
    }

    Future.delayed(const Duration(seconds: 3), attempt);
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

  Future<void> _loadKeyboardMode() async {
    final supported =
        bind.sessionIsKeyboardModeSupported(sessionId: gFFI.sessionId, mode: 'map');
    if (!mounted) return;
    setState(() => _keyboardMapSupported = supported);
    if (!supported) return;
    final mode = await bind.sessionGetKeyboardMode(sessionId: gFFI.sessionId);
    if (!mounted) return;
    setState(() => _keyboardMap = mode == 'map');
  }

  Future<void> _loadImageQuality() async {
    String? quality;
    try {
      quality = await bind.sessionGetImageQuality(sessionId: gFFI.sessionId);
    } catch (_) {
      quality = null;
    }
    if (!mounted) return;
    setState(() {
      _imageQuality = quality;
      _imageQualityLoaded = true;
    });
  }

  // Idle edge button fades out after a few seconds without interaction.
  void _poke() {
    _fadeTimer?.cancel();
    if (_faded) setState(() => _faded = false);
    _fadeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _faded = true);
    });
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

  bool _privacySupported() {
    final impls = gFFI.ffiModel.pi.platformAdditions[
        kPlatformAdditionsSupportedPrivacyModeImpl] as List?;
    return impls != null &&
        impls.any(
            (e) => (e as List).isNotEmpty && e[0] == _kPrivacyVdImpl);
  }

  // `on` is the user's intent, persisted per peer: the host always restores
  // the physical screen on disconnect, so a new session re-applies it.
  void _togglePrivacy(bool next, {bool auto = false}) {
    if (_privacyPendingOn != null) return;
    final cur = PrivacyModeState.find(widget.id).value.isNotEmpty;
    if (cur == next) return;
    if (!_privacySupported()) {
      if (!auto) showToast('被控端不支持虚拟屏防窥（需安装版+服务运行）');
      return;
    }
    if (next && gFFI.ffiModel.permissions['privacy_mode'] == false) {
      if (!auto) showToast('被控端未授权防窥模式');
      return;
    }
    setState(() => _privacyPendingOn = next);
    _setHostIntent('privacy', next);
    _privacyStartTimer?.cancel();
    _privacyRetryTimer?.cancel();
    _privacyFailTimer?.cancel();
    if (!next) {
      bind.sessionTogglePrivacyMode(
          sessionId: gFFI.sessionId, implKey: _kPrivacyVdImpl, on: false);
      _privacyFailTimer = Timer(const Duration(seconds: 6), () {
        if (!mounted || _privacyPendingOn != false) return;
        if (PrivacyModeState.find(widget.id).value.isNotEmpty) {
          setState(() => _privacyPendingOn = null);
          showToast('关闭防窥未响应，请稍后重试');
        }
      });
      return;
    }
    // turn_on only waits 5s for the virtual display to appear, but Amyuni's
    // monitor needs ~6s to reach ACTIVE. Plug it first so the server-side
    // check finds it instead of racing.
    final preplug = gFFI.ffiModel.pi.isAmyuniIdd;
    final hadVirtualDisplay =
        gFFI.ffiModel.pi.RustDeskVirtualDisplays.isNotEmpty;
    void requestPrivacy() {
      if (!mounted || _privacyPendingOn != true) return;
      bind.sessionTogglePrivacyMode(
          sessionId: gFFI.sessionId, implKey: _kPrivacyVdImpl, on: true);
    }

    if (preplug) {
      bind.sessionToggleVirtualDisplay(
          sessionId: gFFI.sessionId, index: 0, on: true);
      _privacyStartTimer = Timer(const Duration(seconds: 4), requestPrivacy);
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
              sessionId: gFFI.sessionId, index: 0, on: false);
        }
        setState(() => _privacyPendingOn = null);
        showToast('开启失败：被控端未找到虚拟显示器，驱动刚装好时请重启电脑再试');
      }
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
    if (page == 'menu') {
      _loadImageQuality();
      _loadKeyboardMode();
    }
  }

  void _setImageQuality(String value) {
    setState(() => _imageQuality = value);
    unawaited(
        bind.sessionSetImageQuality(sessionId: gFFI.sessionId, value: value));
    if (value == kRemoteImageQualityCustom) {
      uuState.drawerPage.value = null;
      customImageQualityDialog(gFFI.sessionId, widget.id, gFFI);
    }
  }

  Future<void> _showQualityPicker() async {
    if (!_imageQualityLoaded) await _loadImageQuality();
    if (!mounted) return;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('画面质量'),
        children: _imageQualityLabels.entries
            .map((e) => SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(e.key),
                  child: Text(
                      '${e.value}${_imageQuality == e.key ? '  ✓' : ''}'),
                ))
            .toList(),
      ),
    );
    if (picked == null || !mounted) return;
    _setImageQuality(picked);
  }

  Widget _imageQualitySection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('画面质量',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final entry in _imageQualityLabels.entries)
                ChoiceChip(
                  label: Text(entry.value,
                      style: TextStyle(
                          color: _imageQuality == entry.key
                              ? Colors.black
                              : Colors.white,
                          fontSize: 12)),
                  selected: _imageQuality == entry.key,
                  showCheckmark: false,
                  selectedColor: MyTheme.accent,
                  backgroundColor: const Color(0xFF3A3A3C),
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => _setImageQuality(entry.key),
                ),
            ],
          ),
        ],
      ),
    );
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
            behavior: HitTestBehavior.translucent,
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
      'gestures': '手势与触摸',
    };
    return Stack(
      children: [
        // Tapping outside the drawer equals Back (one level up).
        // Tapping outside the drawer equals Back (one level up). Translucent so
        // drags still reach the canvas underneath instead of blocking the
        // remote mouse while the panel is open.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
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
                        : _gesturesPage(context),
              ),
            ],
          ),
        ),
          ),
        ),
      ],
    );
  }

  bool _optionOn(String option) =>
      bind.sessionGetToggleOptionSync(sessionId: gFFI.sessionId, arg: option);

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(text,
          style: const TextStyle(color: Colors.white54, fontSize: 11)),
    );
  }

  Widget _card(Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2F2F31),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: child,
    );
  }

  Widget _groupCard(String title, IconData icon, List<Widget> children) {
    final open = _expanded.contains(title);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF2F2F31),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() {
              if (!_expanded.remove(title)) _expanded.add(title);
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  Icon(icon, color: Colors.white70, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14)),
                  ),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.expand_more,
                        color: Colors.white54, size: 20),
                  ),
                ],
              ),
            ),
          ),
          // Keep children mounted while collapsed so their local state
          // survives a collapse/expand cycle.
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            clipBehavior: Clip.hardEdge,
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: open ? 1 : 0,
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navRow(IconData icon, String title, VoidCallback onTap,
      {String? subtitle}) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(icon, color: Colors.white70, size: 20),
      title: Text(title,
          style: const TextStyle(color: Colors.white, fontSize: 13)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
      onTap: onTap,
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    String? tooltip,
    bool active = false,
    bool enabled = true,
    VoidCallback? onTap,
  }) {
    final color = !enabled
        ? Colors.white30
        : active
            ? MyTheme.accent
            : Colors.white;
    Widget tile = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: active
              ? MyTheme.accent.withOpacity(0.16)
              : const Color(0xFF2F2F31),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
    if (tooltip != null) {
      tile = Tooltip(message: tooltip, child: tile);
    }
    return Expanded(child: tile);
  }

  Widget _actionBar() {
    return AnimatedBuilder(
      animation: gFFI.ffiModel,
      builder: (context, _) {
        final audioOn = !_optionOn('disable-audio');
        final viewOnly = gFFI.ffiModel.viewOnly;
        return SizedBox(
          height: 96,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _actionTile(
                icon: Icons.logout,
                label: '退出远控',
                onTap: () => clientClose(gFFI.sessionId, gFFI),
              ),
              _actionTile(
                icon: Icons.high_quality_outlined,
                label: '画质',
                tooltip: '调整远端画面质量',
                onTap: _showQualityPicker,
              ),
              _actionTile(
                icon: audioOn ? Icons.volume_up : Icons.volume_off,
                label: '声音',
                tooltip: '只控制传到手机的声音，电脑扬声器照常发声',
                active: audioOn,
                onTap: () {
                  unawaited(bind.sessionToggleOption(
                      sessionId: gFFI.sessionId, value: 'disable-audio'));
                  setState(() {});
                },
              ),
              _actionTile(
                icon: viewOnly ? Icons.visibility : Icons.visibility_outlined,
                label: '仅观看',
                active: viewOnly,
                onTap: _toggleViewOnly,
              ),
              _actionTile(
                icon: Icons.picture_in_picture_alt,
                label: '小窗模式',
                enabled: false,
                onTap: () => showToast('小窗模式将在下一期支持'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggleViewOnly() async {
    final next = !gFFI.ffiModel.viewOnly;
    await bind.sessionToggleOption(
        sessionId: gFFI.sessionId, value: kOptionToggleViewOnly);
    if (!mounted) return;
    gFFI.ffiModel.setViewOnly(widget.id, next);
    setState(() {});
  }

  Widget _segment(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? MyTheme.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: selected ? MyTheme.accent : Colors.white24),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 12)),
      ),
    );
  }

  void _setTouchMode(bool touch) {
    if (gFFI.ffiModel.touchMode == touch) return;
    gFFI.ffiModel.toggleTouchMode();
    unawaited(bind.mainSetLocalOption(
        key: kOptionTouchMode, value: touch ? 'Y' : 'N'));
    setState(() {});
  }

  Widget _touchPointerRow() {
    return AnimatedBuilder(
      animation: gFFI.ffiModel,
      builder: (context, _) {
        final touch = gFFI.ffiModel.touchMode;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.touch_app_outlined,
                  color: Colors.white70, size: 20),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('操作方式',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
              ),
              _segment('屏幕触控', touch, () => _setTouchMode(true)),
              const SizedBox(width: 8),
              _segment('鼠标指针', !touch, () => _setTouchMode(false)),
            ],
          ),
        );
      },
    );
  }

  Widget _keyboardMapRow() {
    return SwitchListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      secondary: const Icon(Icons.keyboard_alt_outlined,
          color: Colors.white70, size: 20),
      title: const Text('启用按键映射',
          style: TextStyle(color: Colors.white, fontSize: 13)),
      value: _keyboardMap,
      onChanged: (v) async {
        await bind.sessionSetKeyboardMode(
            sessionId: gFFI.sessionId, value: v ? 'map' : 'legacy');
        if (mounted) setState(() => _keyboardMap = v);
      },
    );
  }

  List<Widget> _displayRows() {
    final pi = gFFI.ffiModel.pi;
    final rows = <Widget>[
      _toggleRow('画面缩放吸附', uuState.active.snapZoom, (v) {
        uuState.active.snapZoom = v;
      }, subtitle: '松手后吸附到适应/原始比例'),
    ];
    if (!gFFI.ffiModel.isPeerAndroid &&
        !gFFI.canvasModel.cursorEmbedded &&
        !pi.isWayland) {
      rows.add(Obx(() {
        final state = ShowRemoteCursorState.find(widget.id);
        final lock = ShowRemoteCursorLockState.find(widget.id);
        return _toggleRow('显示远端光标', state.value, (v) async {
          await bind.sessionToggleOption(
              sessionId: gFFI.sessionId, value: 'show-remote-cursor');
          state.value = bind.sessionGetToggleOptionSync(
              sessionId: gFFI.sessionId, arg: 'show-remote-cursor');
          uuState.showRemoteCursor.value = state.value;
        },
            subtitle:
                gFFI.ffiModel.viewOnly || lock.value ? '当前模式下不可用' : null,
            enabled: !gFFI.ffiModel.viewOnly && !lock.value);
      }));
    }
    if (_imageQualityLoaded && _imageQuality != null) {
      rows.add(_imageQualitySection());
    }
    return rows;
  }

  List<Widget> _securityRows() {
    final hostControl = _hostControlSupported;
    final muted = _hostIntent('mute');
    final restoreAudio = _hostIntent('restore-audio');
    final displayMode = _hostSetting('display', '1920x1080');
    return [
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
                style: const TextStyle(color: Colors.white38, fontSize: 11));
        return SwitchListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title:
              const Text('电脑静音', style: TextStyle(color: Colors.white, fontSize: 13)),
          subtitle: subtitle,
          value: hostControl && muted,
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
      Obx(() {
        final state = PrivacyModeState.find(widget.id);
        final on = state.value.isNotEmpty;
        return _PrivacyModeTile(
          on: on,
          pending: _privacyPendingOn,
          supported: _privacySupported(),
          onChanged: _togglePrivacy,
        );
      }),
      _toggleRow('断开后恢复声音', hostControl && restoreAudio, (v) {
        if (!hostControl) return;
        setState(() {
          _setHostIntent('restore-audio', v);
          _sendHostCmd('restore-audio', v);
        });
      },
          subtitle: hostControl
              ? (restoreAudio ? '断开后把扬声器还原成连接前的状态' : '断开后保持静音，长期有效')
              : '需被控端为本项目编译版 RustDesk'),
      if (hostControl)
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: const Text('显示缩放',
              style: TextStyle(color: Colors.white, fontSize: 13)),
          subtitle: Text(
              '当前 ${_hostSetting('scale', '125')}% · 开启关屏后生效，关屏期间调整立即应用',
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
          trailing:
              const Icon(Icons.chevron_right, color: Colors.white54, size: 18),
          onTap: () async {
            const modes = {
              '100': '100%',
              '125': '125%',
              '150': '150%',
              '175': '175%',
            };
            final scale = _hostSetting('scale', '125');
            final picked = await showDialog<String>(
              context: context,
              builder: (ctx) => SimpleDialog(
                title: const Text('显示缩放（虚拟屏）'),
                children: modes.entries
                    .map((e) => SimpleDialogOption(
                          onPressed: () => Navigator.of(ctx).pop(e.key),
                          child: Text(
                              '${e.value}${e.key == scale ? '  ✓' : ''}'),
                        ))
                    .toList(),
              ),
            );
            if (picked == null || !mounted) return;
            setState(() => _setHostSetting('scale', picked));
            _sendHostCmd('scale:$picked', true);
          },
        ),
      if (hostControl)
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: const Text('虚拟屏分辨率',
              style: TextStyle(color: Colors.white, fontSize: 13)),
          subtitle: Text('当前 $displayMode · 下次开启关屏时生效',
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
          trailing:
              const Icon(Icons.chevron_right, color: Colors.white54, size: 18),
          onTap: () async {
            const modes = {
              '1280x720': '1280×720',
              '1536x864': '1536×864',
              '1920x1080': '1920×1080',
              '2560x1440': '2560×1440',
            };
            final picked = await showDialog<String>(
              context: context,
              builder: (ctx) => SimpleDialog(
                title: const Text('虚拟屏分辨率'),
                children: modes.entries
                    .map((e) => SimpleDialogOption(
                          onPressed: () => Navigator.of(ctx).pop(e.key),
                          child: Text('${e.value}${e.key == displayMode ? '  ✓' : ''}'),
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
      _toggleRow('退出远控时锁定电脑', _optionOn('lock-after-session-end'), (v) {
        unawaited(bind.sessionToggleOption(
            sessionId: gFFI.sessionId, value: 'lock-after-session-end'));
      }),
      _AutoUnlockTile(id: widget.id),
    ];
  }

  List<Widget> _peripheralRows() {
    final scheme = uuState.active;
    return [
      _navRow(Icons.gamepad_outlined, '虚拟按键方案', () {
        uuState.drawerPage.value = 'schemes';
      }),
      _sliderRow('按键放大', scheme.keyScale, 0.7, 1.6, (v) {
        scheme.keyScale = v;
      }),
      _toggleRow('点击按键时震动', scheme.haptics, (v) {
        scheme.haptics = v;
      }),
      _navRow(Icons.touch_app_outlined, '手势与触摸', () {
        uuState.drawerPage.value = 'gestures';
      }),
    ];
  }

  List<Widget> _moreRows(BuildContext context) {
    return [
      _navRow(Icons.tv, '会话设置', () {
        uuState.drawerPage.value = null;
        showOptions(context, widget.id, gFFI.dialogManager);
      }),
      _navRow(Icons.more_vert, '更多操作', () {
        uuState.drawerPage.value = null;
        widget.onShowActions();
      }),
    ];
  }

  Widget _menuPage(BuildContext context) {
    final operationRows = <Widget>[
      if (_keyboardMapSupported) _keyboardMapRow(),
      if (!gFFI.ffiModel.isPeerAndroid) _touchPointerRow(),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        _actionBar(),
        const SizedBox(height: 20),
        if (operationRows.isNotEmpty) ...[
          _sectionLabel('操作'),
          _card(Column(children: operationRows)),
          const SizedBox(height: 12),
        ],
        _groupCard('显示', Icons.monitor_outlined, _displayRows()),
        _groupCard('安全', Icons.shield_outlined, _securityRows()),
        _groupCard('外设', Icons.usb, _peripheralRows()),
        _groupCard('更多', Icons.more_horiz, _moreRows(context)),
      ],
    );
  }

  Widget _gesturesPage(BuildContext context) {
    final scheme = uuState.active;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        _card(Column(
          children: [
            _navRow(Icons.help_outline, '查看手势说明', () {
              uuState.drawerPage.value = null;
              widget.onToggleGestureHelp();
            }),
            _toggleRow('双指缩放', scheme.pinchZoom, (v) {
              scheme.pinchZoom = v;
            }, subtitle: '关闭后双指始终按滚动处理'),
            _sliderRow('滚动灵敏度', scheme.scrollSensitivity, 0.5, 3.0, (v) {
              scheme.scrollSensitivity = v;
            }),
          ],
        )),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 12, 4, 0),
          child: Text('灵敏度过高时慢速滑动容易越过目标行，过低时需要反复滑动。',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
        ),
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
      {String? subtitle, bool enabled = true}) {
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
      onChanged: enabled
          ? (v) {
              setState(() => onChanged(v));
              uuState.save();
            }
          : null,
    );
  }

}

class _PrivacyModeTile extends StatelessWidget {
  final bool on;
  final bool? pending;
  final bool supported;
  final ValueChanged<bool> onChanged;

  const _PrivacyModeTile({
    required this.on,
    required this.pending,
    required this.supported,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = pending != null
        ? Row(children: [
            const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white70),
            ),
            const SizedBox(width: 8),
            Text(pending! ? '正在开启…' : '正在关闭…',
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
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
      onChanged: onChanged,
    );
  }
}

class _AutoUnlockTile extends StatefulWidget {
  final String id;

  const _AutoUnlockTile({required this.id});

  @override
  State<_AutoUnlockTile> createState() => _AutoUnlockTileState();
}

class _AutoUnlockTileState extends State<_AutoUnlockTile> {
  Map<String, dynamic> _cfg = {};

  String get _key => 'uu-auto-unlock:${widget.id}';

  @override
  void initState() {
    super.initState();
    try {
      final raw = bind.mainGetLocalOption(key: _key);
      if (raw.isNotEmpty) _cfg = json.decode(raw) as Map<String, dynamic>;
    } catch (_) {}
  }

  void _store() => bind.mainSetLocalOption(key: _key, value: json.encode(_cfg));

  static String _wsCodes(String s) {
    final codes = <String>[];
    for (final r in s.runes) {
      if (String.fromCharCode(r).trim().isEmpty) {
        codes.add('U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}');
      }
    }
    return codes.join(' / ');
  }

  static bool _hasFullWidthSpace(String s) => s.contains('\u3000');

  static String _pwdSummary(String pwd) {
    if (pwd.isEmpty) return '未设置';
    if (_hasFullWidthSpace(pwd)) {
      return '已设置（含全角空格 U+3000，Windows 登录不认，请重设）';
    }
    if (pwd.trim().isEmpty) {
      return '已设置（长度 ${pwd.length}，空格 ${_wsCodes(pwd)}）';
    }
    return '已设置（${pwd.length} 个字符）';
  }

  Future<T?> _withIme<T>(Future<T?> Function() run) async {
    await gFFI.invokeMethod("enable_soft_keyboard", true);
    try {
      return await run();
    } finally {
      if (mounted) gFFI.invokeMethod("enable_soft_keyboard", false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pwd = _cfg['pwd']?.toString() ?? '';
    return Column(
      children: [
        SwitchListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: const Text('连接后自动输入密码解锁',
              style: TextStyle(color: Colors.white, fontSize: 13)),
          value: _cfg['on'] == true,
          onChanged: (v) {
            setState(() => _cfg['on'] = v);
            _store();
          },
        ),
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: const Text('登录密码',
              style: TextStyle(color: Colors.white, fontSize: 13)),
          subtitle: Text(_pwdSummary(pwd),
              style: TextStyle(
                  color: _hasFullWidthSpace(pwd)
                      ? Colors.amber
                      : Colors.white38,
                  fontSize: 11)),
          trailing: const Icon(Icons.edit, color: Colors.white54, size: 18),
          onTap: () async {
            final controller = TextEditingController(text: pwd);
            final ok = await _withIme(() => showDialog<bool>(
              context: context,
              builder: (ctx) => StatefulBuilder(
                builder: (ctx, setDlgState) => AlertDialog(
                  title: const Text('Windows 登录密码'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: controller,
                        obscureText: true,
                        autofocus: true,
                        keyboardType: TextInputType.visiblePassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        smartDashesType: SmartDashesType.disabled,
                        smartQuotesType: SmartQuotesType.disabled,
                        onChanged: (_) => setDlgState(() {}),
                        decoration:
                            const InputDecoration(hintText: '仅保存在本机配置中'),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        OutlinedButton(
                          onPressed: () {
                            controller.text += ' ';
                            setDlgState(() {});
                          },
                          child: const Text('插入空格'),
                        ),
                        const SizedBox(width: 10),
                        Text('长度 ${controller.text.length}',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12)),
                      ]),
                      if (controller.text.isNotEmpty &&
                          controller.text.trim().isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                              controller.text
                                          .codeUnits
                                          .every((c) => c == 0x20)
                                  ? '码点：U+0020（半角空格）'
                                  : '码点：${_wsCodes(controller.text)}（必须为 U+0020）',
                              style: TextStyle(
                                  color: controller.text.codeUnits
                                          .every((c) => c == 0x20)
                                      ? Colors.white54
                                      : Colors.amber,
                                  fontSize: 11)),
                        ),
                    ],
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
            ));
            if (ok != true || !mounted) return;
            setState(() => _cfg['pwd'] = controller.text);
            _store();
          },
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('连接建立 2 秒后自动输入密码并回车。仅在电脑处于锁屏时开启；未锁屏时密码会被输入到当前焦点窗口。',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
        ),
      ],
    );
  }
}
