# 被控端「电脑真正静音」设计（2026-11-21）

> 目标：手机端一键让**被控电脑的扬声器/耳机**真实静音（系统音量图标变静音），而不只是断开串流音频。
> 被控端保持官方 RustDesk 1.5.3 安装版，不重编、不替换。

## 1. 结论先行

RustDesk 1.5.3 协议里**没有**可用的主机静音通道（下方取证）。因此采用：

**主机侧常驻小工具「UU 静音助手」 + 手机端发送罕见组合键触发**

- 助手用 Windows Core Audio API `IAudioEndpointVolume::SetMute` 做幂等开/关，状态由助手持有；
- 手机端只发 `Ctrl+Alt+Shift+F9`（静音开）/ `Ctrl+Alt+Shift+F10`（静音关），走现有键盘通道；
- 零网络端口、不需要主机管理员权限、不需要改 RustDesk。

## 2. 为什么不能用键盘模拟静音键

| 路径 | 结论 | 依据 |
|---|---|---|
| `inputKey('VK_VOLUME_MUTE')` | 不可用 | 客户端 `KEY_MAP`（src/client.rs:5100）没有音量键 |
| Flutter 音量键通路 `tapHidKey` | 不可用 | 服务端 `ControlKey::VolumeMute` 在 Translate 模式被丢弃（src/server/input_service.rs:2262 的 match 无 ControlKey 分支）；Legacy 模式的 `KEY_MAP`（input_service.rs:2639）同样没有它 |
| `sessionHandleFlutterRawKeyEvent` 发 VK 0xAD | 不可用 | Android 侧 Map 模式用 `usb_hid` 映射（keyboard.rs:1410+），而该路径构造的 Event `usb_hid = 0`（ui_session_interface.rs:975） |
| 即便能发 `VK_VOLUME_MUTE` | 语义不对 | 系统媒体键是**切换**语义，无法保证“当前一定是静音”，会与用户本机操作不同步 |

## 3. 方案对比

| 方案 | 需要装东西 | 确定性 | 安全性 | 结论 |
|---|---|---|---|---|
| **热键助手（选定）** | 主机一个自启小工具 | 高（助手持有状态，开=开） | 高（无端口、只认本机热键） | ✅ |
| Windows 终端通道 | 无 | 高 | 中（shell 权限面大） | 备选：1.5.3 FFI 有 terminal，但需终端授权 + 手机端终端 UI，重 |
| 主机自编译 RustDesk 打补丁 | 换主机程序 | 高 | 中 | 不选：违背“官方安装版被控端”约束 |
| 剪贴板暗号 + 助手轮询 | 主机小工具 | 中 | 中（污染剪贴板） | 仅作 v2 回执通道备选 |

## 4. 交互设计（手机端）

落位按 `COLLABORATION.md` §8.3 的新操作面板：

1. **操作面板顶部「声音」按钮**
   - 单击：切换「电脑声音不传到手机」（`disable-audio`，只影响串流）
   - **长按 600ms**：切换「电脑真正静音」，松手后 Toast：「已请求电脑静音 / 已解除电脑静音」；
     若 1.5s 内没有……（无回执，见 §7）则直接显示乐观状态。
2. **外设分组**新增正式开关：
   - 标题：「电脑真正静音（主机扬声器）」
   - 副标题：「需在被控端安装 UU 静音助手」
   - 开关状态存本地 `uuState`（`uu-host-mute`），与串流静音互不影响；
   - `仅观看` 模式下置灰。
3. 首次打开时弹一次说明卡：助手下载/安装位置、热点键表、未安装时无反应。

文案必须把两个静音拆开：

| 开关 | 作用范围 |
|---|---|
| 电脑声音不传到手机 | 只停串流音频，电脑照常发声 |
| 电脑真正静音 | 设置主机默认输出设备 Mute，本机和串流都无声 |

## 5. 热键表

| 快捷键 | 动作 |
|---|---|
| `Ctrl+Alt+Shift+F9` | 置为静音（幂等） |
| `Ctrl+Alt+Shift+F10` | 解除静音（幂等） |
| `Ctrl+Alt+Shift+F11` | 切换（可选用，托盘菜单同款） |

选 F9/F10 的原因：客户端 `KEY_MAP` 有 F1–F12；`Ctrl+Alt+Shift` 三修饰键组合在日常软件中几乎不冲突；
服务端 Legacy 模式会原样合成该组合（`legacy_modifiers` + `process_control_key`）。

## 6. 实现规格

### 6.1 手机端（Dart，本人）

```dart
Future<void> _sendHostMute(bool on) async {
  final name = on ? 'F9' : 'F10';
  for (final down in [true, false]) {
    bind.sessionInputKey(
      sessionId: gFFI.sessionId,
      name: name,
      down: down,
      press: false,
      alt: true,
      ctrl: true,
      shift: true,
      command: false,
    );
    if (down) await Future.delayed(const Duration(milliseconds: 80));
  }
}
```

- 长按手势用 `GestureDetector(onLongPress: ...)` 包住顶部「声音」按钮；
- 状态写入 `uuState`，与 `disable-audio` 完全独立；
- `ffiModel.viewOnly == true` 时不发送并 toast 提示。

### 6.2 主机助手（C# / .NET 8，单文件 exe）

- **热键**：`RegisterHotKey(hwnd, id, MOD_CONTROL|MOD_ALT|MOD_SHIFT, VK_F9/F10/F11)`，
  `WM_HOTKEY` 里分发；注册失败（被占用）写日志并在托盘菜单提示，可在配置文件改键。
- **静音**：COM interop
  `IMMDeviceEnumerator.GetDefaultAudioEndpoint(eRender, eConsole)` →
  `IAudioEndpointVolume.SetMute(bool)`；每次调用重新取默认设备，兼容切换耳机/蓝牙。
  不需要管理员权限（按用户默认设备）。
- **托盘**：两态图标（静音/有声），菜单：解除静音 / 开机自启 / 查看日志 / 退出；
  收到热键时图标闪烁一次作为本地反馈。
- **自启**：`HKCU\Software\Microsoft\Windows\CurrentVersion\Run`，无计划任务、无服务。
- **单实例**：命名 Mutex。
- **日志**：`%LOCALAPPDATA%\UUMuteHelper\log.txt`（只记热键与 SetMute 结果）。
- **分发**：`uumute-helper.exe` 单文件，放在共享文件夹；用户双击运行一次即注册自启。

### 6.3 行为边界

- 助手不运行 → 热键落到系统/前台应用，通常无副作用；手机端无回执，UI 文案已说明。
- 断开会话 → 主机保持当前静音状态（符合「静音运行」语义）；需要恢复时托盘点「解除静音」或手机再长按一次。
- 锁屏（安全桌面）→ 助手的热键不触发；此时静音状态保持，不额外处理。
- 用户本机改了音量/静音 → 助手只是下次 SetMute 时纠正到请求值，不做持续抢占。

## 7. 可选 v2：状态回执

v1 无回执（手机不能确认助手是否在线）。若需要：
- 助手收到热键后把 `MUTE:0/1` 写进剪贴板，手机端靠 RustDesk 剪贴板同步读取 → 回填开关。
- 或助手暴露 `127.0.0.1` 的命名管道，但手机无法直连，仍需经剪贴板/终端转发，暂不做。

## 8. 验收清单

1. 主机播放音乐 → 手机长按「声音」→ 主机扬声器立即无声，系统音量图标变静音；
2. 手机再长按 → 恢复有声，且音量值不变（只改 Mute 位）；
3. 重复开/重复关不抖动（幂等）；
4. 切到蓝牙耳机后再次触发仍作用于新的默认设备；
5. 助手退出后触发 → 无异常副作用，手机文案提示需安装/启动助手；
6. 仅观看模式下开关置灰。
