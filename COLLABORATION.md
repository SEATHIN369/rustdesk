# 协作开发说明 —— UU 远程本地替代（RustDesk 二开）

> 本仓是 [rustdesk/rustdesk](https://github.com/rustdesk/rustdesk) 的 fork，用于做一个本地/自建的 UU 远程替代品。
> 主线分支：`local/1.5.3-android`。所有定制只改 **Flutter(Dart) + Android(Kotlin)** 层，原生 Rust 层不重编。

## 1. 项目目标与背景

- 网易 UU 远程自 2026-12-01 起收费，本项目是自用的替代品，用途：办公 + galgame 远程串流，**始终横屏**。
- 手机端 UI/交互按 UU 远程 1:1 复刻（对照素材不随仓库分发），在标准 RustDesk 功能上叠加：
  - 右缘悬浮圆钮 + 竖排菜单（操作/键盘/显示桌面/所有窗口），四个整块可点区域；
  - 三 tab 键盘面板（输入法/快捷键/电脑键盘，唤 IME、快捷键大网格、粘滞修饰键）；
  - 可拖动的半透明虚拟按键（工具球外观，按操控方案持久化）；
  - 双指竖直滑动 = 远端滚轮；点画布外 = 返回；防误触（使用系统输入法时点外不退出）；
  - 被控端功能接线：静音、退出锁屏、自动解锁、**虚拟屏防窥（物理关屏）**；
  - 关自动旋转仍可双向横屏、OLED 纯黑黑边。

## 2. 硬约束（改坏了会直接闪退）

1. **原生层复用官方 1.5.3 arm64 的 `librustdesk.so`**，已入库于
   `flutter/android/app/src/main/jniLibs/arm64-v8a/librustdesk.so`。**不要替换它，也不要从 master 抄 Kotlin/Dart 代码**：
   master 的 Kotlin 调用了 1.5.3 `.so` 里不存在的 JNI（如 `setInputServiceOpen`、`setDocumentLogsEnabled`），混搭会 `UnsatisfiedLinkError` 启动闪退。
2. Dart/Kotlin 侧的 API 以 **tag `1.5.3`** 为准。升级原生层需要重新编译 Rust（涉及 NDK 工具链），当前阶段刻意不做。
3. 只出 **arm64** 包（`--target-platform android-arm64`）。
4. `key.properties`、密钥库、本机路径（`local.properties`）一律不入库。

## 3. 仓库与分支

| remote | 地址 | 用途 |
|---|---|---|
| `fork`（默认克隆目标） | `https://github.com/kitsuneMori96/rustdesk` | 我们的开发主线 |
| `origin` | 上游 rustdesk | 只读参考，不要往上推 |

- 主线：`local/1.5.3-android`（基于 tag `1.5.3`）。
- 协作方式：从主线切 `feat/<功能>` 或 `fix/<问题>`，完成后 PR 回 `local/1.5.3-android`。
- **禁止对共享分支 rebase / force push**；需要同步上游时先说一声，单独处理。

## 4. 快速开始

环境（已验证可用组合）：

- Flutter **3.24.5**（不要用更新的版本，Dart/API 不兼容）
- JDK **17**
- Android SDK（`ANDROID_HOME`），`minSdkVersion 22`，`targetSdkVersion 36`
- 国内网络建议：`PUB_HOSTED_URL=https://pub.flutter-io.cn`、`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`
- 构建机若开着系统代理，请先 `unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy`

```bash
git clone https://github.com/kitsuneMori96/rustdesk.git -b local/1.5.3-android
cd rustdesk/flutter
flutter pub get
flutter build apk --release --target-platform android-arm64
# 产物：build/app/outputs/flutter-apk/app-release.apk
# 包名：com.carriez.flutter_hbb
```

签名：`flutter/android/app/build.gradle` 的 release 读根目录 `key.properties`（`storeFile/storePassword/keyAlias/keyPassword`）。
**每位协作者用自己的 keystore**；换签名后与原包不兼容，需先卸载旧包再装。

本机开发习惯（非强制）：产物构建后拷到 `D:\Download\共享文件夹\rustdesk-uu-1.5.3-arm64.apk`。注意 Windows 下 QQ 文件传输等会**锁住 APK** 导致打包失败（`Device or resource busy`），关掉传输窗口即可。

## 5. 代码地图（只看这几处就能上手）

| 文件 | 职责 |
|---|---|
| `flutter/lib/mobile/pages/remote_page.dart` | 会话页总装：画布手势层 → 浮键层 → 点外 barrier → `UuChrome` → sheet；自动解锁、双向横屏入口 |
| `flutter/lib/mobile/pages/uu_chrome.dart` | 右缘圆钮/竖排菜单/抽屉/设置页（被控端功能开关、自动解锁配置、防窥 pending 状态） |
| `flutter/lib/mobile/pages/uu_keyboard_sheet.dart` | 三 tab 键盘面板（输入法唤 IME、电脑键盘粘滞修饰键） |
| `flutter/lib/mobile/pages/shortcut_pad.dart` | 快捷键网格（按住高亮 + 触感反馈 + 编辑/排序） |
| `flutter/lib/mobile/pages/uu_floating_keys.dart` | 悬浮按键层（工具球外观、可拖动、4s 淡出、按住修饰键） |
| `flutter/lib/models/uu_state.dart` | 按键方案/面板状态的持久化（local option `uu-control-schemes`） |
| `flutter/lib/common/widgets/remote_input.dart` | 双指滚轮（死区已归零，意图锁：滚轮/画布二选一） |
| `flutter/lib/common/widgets/gestures.dart` | 画布手势（吸附、缩放上下限） |
| `flutter/lib/common.dart` | `MyTheme.canvasColor` = 纯黑（OLED 黑边不发光） |
| `flutter/android/.../MainActivity.kt` | 原生沉浸式常驻隐藏系统栏 |
| `flutter/lib/common/shared_state.dart` | 每会话共享状态（`PrivacyModeState`、`BlockInputState` 等，上游文件未改） |

## 6. 关键机制备忘

- **会话选项**：`sessionToggleOption` 发 Misc.option 立即生效（`disable-audio` 静音、`lock-after-session-end` 退出锁屏）。
- **防窥必须走专用接口**：`bind.sessionTogglePrivacyMode(sessionId, implKey, on)`，
  `implKey = 'privacy_mode_impl_virtual_display'`（来自 `pi.platformAdditions['supported_privacy_mode_impl']` 列表）。
  不要用通用 `toggleOption('privacy-mode')`——只发 option 不翻服务端 config。
- **虚拟屏防窥 = 物理关屏**：被控端（Windows 安装版官方 RustDesk 1.5.3 + 服务运行，Win10 19041+）
  用 `ChangeDisplaySettingsExW` 拔掉物理屏、串流切到虚拟屏。Windows 版实现的 IDD 是 **Amyuni usbmmidd**，
  设备名 “USB Mobile Monitor Virtual Display”；**不存在 “RustDeskIddDriver Device”**（那是另一种 impl）。
  首次开启时驱动经 SetupAPI 现场安装，有 8–45s 的枚举竞态 → 客户端做了 4s 自动重试 + 点击即时 pending UI。
- **自动解锁**：无原生接口，Dart 实现。密码存 local option `uu-auto-unlock:<peerId>`（JSON `{on,pwd}`），
  首帧后 2s 逐字符 `inputKey(ch)` + `VK_RETURN`，每个会话一次。**只在电脑锁屏时打开**，否则密码会打进焦点窗口。
- **键盘输入**：单字符键名走 raw char；Win 键在 `inputKey` 里叫 `Meta`；`inputKey(name, down:, press:)` 控制按住。
- **横屏**：默认 `[landscapeLeft, landscapeRight]` 在部分 ROM（关自动旋转时）被钉死；
  现用 `sensors_plus` 读加速度计，持握 |x|≥6 且 |y|≤6 时按 x 符号显式请求单方向横屏（450ms 防抖）。
  显式单方向请求不受系统旋转锁限制。
- **防误触**：barrier 仅在 `keyboardOpen && (tab != 0 || IME 实际可见)` 时拦截点外；
  IME 收起后恢复“点外 = 返回”。

## 7. 修改约定

- commit 用中文，格式 `type(scope): 一句话说为什么改`（如 `fix(android): 防窥开关点击即反馈 pending 状态与失败提示`）。
- 改完必须 `dart analyze` 相关文件 0 error；**不要运行 `dart format`**（会产生大范围无关 diff）。
- 涉及 UI/交互的改动要真机验证后再声称完成；没条件验证时在 PR 里明确标注「未真机验证」。
- 不把测试脚本、日志、构建副本提交进仓库；临时产物放系统临时目录。
- 不要把本机敏感信息（IP、密码、Peer ID、密钥）写进代码或文档。

## 8. 真机测试清单（每版过一遍）

1. 连接后横屏；关掉系统自动旋转，左右翻转手机应保持横屏并切换左右方向。
2. 黑边区域为纯黑（OLED 不发光）。
3. 双指竖直滑 = 滚轮；斜向滑动不误触发滚动；点画布外 = 返回。
4. 键盘面板：tab 切换、唤 IME 立即弹出、IME 开着时点外不退出、IME 收起后点外可返回。
5. 悬浮键：点击有按压反馈/震动；按住 Ctrl 快进（galgame）；拖动可移位并持久化。
6. 右缘：四块区域整块可点；点外收起；闲置 4s 淡出。
7. 设置页：静音 / 退出锁屏 / 自动解锁 / 防窥开关逐一生效；防窥点击瞬间有转圈，「No virtual displays」出现后 4s 自动重试。
8. 退出会话后：被控端物理屏恢复、声音恢复、未勾选时不锁屏。

## 9. 已知问题

- 手动输密码后偶发串流卡在锁屏帧（Winlogon 安全桌面切换），新版未稳定复现，暂时搁置。
- 首次开启虚拟屏防窥的驱动竞态见第 6 节；若多次重试仍失败，重启被控端一次。
- 24H2 上第三方虚拟屏退出后可能无法恢复（上游注释），RustDesk 自带（Amyuni）未观察到。

## 10. 沟通

- 功能/接口有疑问先在 PR 或 issue 里写清场景和期望行为；改共享代码前先对齐。
- 被控端排查日志位置（Windows）：`C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\log\server\RustDesk_rCURRENT.log`。
