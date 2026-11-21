# 被控端「电脑真正静音 / 长期关屏」设计（2026-11-21，方案改为内置主机版）

> 目标：手机端一键让**被控电脑**真实静音（系统音量图标变静音），关屏/静音**一次设定长期有效**，并提供「断开后是否恢复」开关。
> 约束（用户拍板）：**不额外装软件**，功能必须做进被控端 RustDesk 本体。

## 1. 结论

官方 RustDesk 1.5.3 协议里没有可用的主机静音通道（§2 取证），键盘模拟也走不通，因此：

- **自编译被控端 RustDesk，替换安装目录里的 `librustdesk.dll`**（Flutter UI/资源仍用官方 1.5.3 的，Dart 接口未变，可直接替换）。
- 主机新增 `src/host_controls.rs`：用 WASAPI `IAudioEndpointVolume::SetMute`（**幂等**）控制默认播放设备，状态落在 `uu-host-state.json`，服务/主机重启后重新应用。
- **控制通道复用既有 `TogglePrivacyMode` 消息的 `impl_key` 字符串**（官方手机端 `.so` 无法发送新协议消息，这是唯一带自由字符串的信道）：
  - `uu:mute` + on/off → 主机静音/取消静音
  - `uu:restore` + on/off → 断开后是否恢复原状态（默认不恢复 = 长期有效）
  - `uu:privacy-persist` + on/off → 断开后是否保留关屏（虚拟屏）
  - `uu:display:WxH` → 设置虚拟屏尺寸（下次开启关屏生效）
- 主机在 `platform_additions` 里上报 `"uu_host_control": true`，手机端据此显示/隐藏这些开关；官方主机不显示。

## 2. 为什么不能用 Windows 静音快捷键

| 路径 | 结论 | 依据 |
|---|---|---|
| 客户端 `KEY_MAP` 发 `VK_VOLUME_MUTE` | 不可用 | `src/client.rs:5100` 没有音量键 |
| 输入面板 `ControlKey::VolumeMute` | 不可用 | 服务端 `translate_keyboard_mode`（src/server/input_service.rs:2262）只处理 Seq/Chr/Unicode/Win2winHotkey，ControlKey 被丢弃；Legacy `KEY_MAP`（input_service.rs:2639）也没有音量键 |
| `sessionHandleFlutterRawKeyEvent` 发 VK 0xAD | 不可用 | Android Map 模式按 `usb_hid` 映射（src/keyboard.rs），而该路径构造的 Event `usb_hid=0`（src/ui_session_interface.rs:975） |
| 即便能发媒体键 | 语义不对 | 媒体键是**切换**语义，无法保证“当前一定静音”，更无法在断开时按原状态恢复 |

## 3. 主机侧实现

### 3.1 静音与持久化 (`src/host_controls.rs`)

- `set_mute(bool)`：首次静音时记录 `prev_mute`，调用 `SetMute`；写入 `uu-host-state.json`。
- `init()`：`--server` 启动时重放持久化的静音状态。
- `on_all_connections_closed()`：
  - `restore_on_disconnect = true` 时恢复 `prev_mute`（没有记录则取消静音）；
  - 默认 `false`，保持静音，长期有效。
- 状态文件位于 RustDesk 配置目录（`Config::path("uu-host-state.json")`）。

### 3.2 关屏（虚拟屏防窥）跨会话保持

- 官方行为：最后一个远控连接断开时 `virtual_display_manager::reset_all()` 会关掉防窥并拔掉所有虚拟屏（这就是“退出软件后又复位”）。
- 现在：若 `privacy_persist` 为真且当前正处于防窥模式，则跳过 `reset_all()`；关屏状态保留到下次会话或用户手动关闭。
- 默认值由手机端在开启关屏时下发（`privacy-persist = !restore`）。
- 注意：主机重启/重启服务后物理屏恢复（虚拟屏驱动随进程卸载），这是有意的安全兜底。

### 3.3 虚拟屏尺寸（替代“125% 缩放”）

- 官方虚拟屏固定 1920×1080@60，Windows 缩放对虚拟屏不生效。
- 现在 `desired_mode` 可配置：`1280×720`（界面最大）/ `1536×864`（约 125%）/ `1920×1080` / `2560×1440`。
- 用于 `default_display_modes()` 和开启防窥后的 `change_resolution()`；选择会持久化，下次开启关屏生效。

### 3.4 手机端 UI

`uu_chrome.dart` 的「被控端」分组，同一卡片、同一 pending 交互：

1. 电脑静音（Switch，1.2s pending）
2. 操控时物理关屏（Switch，带预插虚拟屏流程）
3. 断开后自动恢复（声音与屏幕，Switch，默认关 = 长期有效）
4. 虚拟屏尺寸（弹窗选择，提示“下次开启关屏时生效”）

主机不支持时报「需被控端为本项目编译版 RustDesk」。

## 4. 构建与替换

- 依赖：Rust MSVC 1.100、MSVC 14.51（`D:\soft\BuildTools`）、LLVM/libclang（bindgen）、vcpkg x64-windows-static（aom/libvpx/libyuv/opus/libjpeg-turbo，overlay 端口用本仓库 `res/vcpkg`）。
- 编译：`cargo build --release --lib --features flutter`（产物 `target/release/librustdesk.dll`），替换安装目录同名文件；官方 Flutter UI 资源不变。
- 替换前备份原 DLL；需要重启 RustDesk 服务（管理员）。

## 5. 已知限制

- 静音只作用于**默认播放设备**；切换输出设备后需要重新点一次。
- 断开后恢复的“原状态”在首次静音时采样；若静音是服务重启后重放的，则恢复为“不静音”。
- 关屏保持跨“会话”有效，不跨“主机重启”；虚拟屏分辨率在下次开启关屏时生效。
