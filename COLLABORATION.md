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

- **会话选项**：`sessionToggleOption` 发 Misc.option 立即生效（`lock-after-session-end` 退出锁屏）。
  `disable-audio` 只是被控端**不再向客户端发音频帧**，不会关电脑扬声器；1.5.3 官方协议没有主机静音接口。
  主机静音改为**做进自编译的被控端 RustDesk**（用户要求不装额外软件）：手机端复用
  `sessionTogglePrivacyMode` 的 `impl_key` 走 `uu:mute` / `uu:restore` / `uu:privacy-persist` /
  `uu:display:WxH` 命令；主机 `src/host_controls.rs` 用 WASAPI `SetMute`，状态持久化到
  `uu-host-state.json`，并在 `platform_additions` 上报 `uu_host_control`。详见 `docs/host-mute-helper.md`。
- **主机命令通道**：官方 Android `.so` 无法发送新协议消息，`TogglePrivacyMode.impl_key` 是唯一带自由字符串、
  且手机端 Dart 能直接调用的信道；主机在 `toggle_privacy_mode` 开头拦截 `uu:` 前缀（仍要求已认证远控连接）。
  除 `uu:mute` 外，其它 `uu:` 键不会进入官方防窥逻辑。
- **静音/关屏长期有效**：最后一个远控连接断开时，若 `privacy_persist` 且正在防窥，跳过
  `virtual_display_manager::reset_all()`；静音按 `restore_on_disconnect` 决定是否恢复（默认保持）。
  主机重启后物理屏恢复（安全兜底），静音状态由服务启动时重放。
- **防窥必须走专用接口**：`bind.sessionTogglePrivacyMode(sessionId, implKey, on)`，
  `implKey = 'privacy_mode_impl_virtual_display'`（来自 `pi.platformAdditions['supported_privacy_mode_impl']` 列表）。
  不要用通用 `toggleOption('privacy-mode')`——只发 option 不翻服务端 config。
- **虚拟屏防窥 = 物理关屏**：被控端（Windows 安装版官方 RustDesk 1.5.3 + 服务运行，Win10 19041+）
  用 `ChangeDisplaySettingsExW` 拔掉物理屏、串流切到虚拟屏。Windows 版实现的 IDD 是 **Amyuni usbmmidd**，
  设备名 “USB Mobile Monitor Virtual Display”；**不存在 “RustDeskIddDriver Device”**（那是另一种 impl）。
  服务端 `turn_on` 只等虚拟屏 5s，而 Amyuni 插入后要约 6s 才 ACTIVE，直接开防窥会报
  “No virtual displays”。客户端流程：先 `sessionToggleVirtualDisplay(index: 0, on: true)` 预插 →
  4s 后发防窥 on → 12s 无变化重发 → 20s 仍失败则回滚预插并提示。开防窥时 `restore()` 会拔掉全部虚拟屏，
  关防窥即恢复物理屏，不需要再手动减屏。**自编译主机版**额外支持：断开后保持关屏（`uu:privacy-persist`）、
  虚拟屏尺寸预设 `1280×720 / 1536×864（≈125%）/ 1920×1080 / 2560×1440`（`uu:display:WxH`，下次开启生效）。
- **IME 弹窗**：远控页常驻 `FLAG_ALT_FOCUSABLE_IM`（`remote_page.dart` 的 `enable_soft_keyboard(false)`），
  设置页里的 TextField 因此唤不出系统键盘。`uu_chrome.dart` 的 `_withIme()` 在弹窗前临时放行、关闭后恢复，
  已覆盖方案重命名/新建/Windows 登录密码三个输入框。
- **自动解锁**：无原生接口，Dart 实现。密码存 local option `uu-auto-unlock:<peerId>`（JSON `{on,pwd}`），
  首帧后 2s 一次性 `sessionInputString(pwd)`（Seq 通道，锁屏唯一可靠路径；逐字符 `inputKey` 走 Chr 通道，
  锁屏收不到），400ms 后 `VK_RETURN`，每个会话一次。**只在电脑锁屏时打开**，否则密码会打进焦点窗口。
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

## 8. 当前迭代任务分工（2026-11-21）

| 归属 | 任务 | 涉及文件 | 状态 |
|---|---|---|---|
| A（kitsuneMori96） | 横屏方向翻转、自动解锁改 Seq 通道、防窥预插虚拟屏、静音文案澄清 | `remote_page.dart`、`uu_chrome.dart` | 已提交 80861b9，待真机验证 |
| A | 打包、构建笔记、被控端日志排查 | — | 进行中 |
| B（SEA369） | **手势引擎重构**：滚动/缩放意图判定 + 动态灵敏度（见 8.1、8.2） | `common/widgets/remote_input.dart`（必要时 `gestures.dart`） | 待开工，分支 `feat/gesture-intent` |
| B | **操作页信息架构重构**（见 8.3） | `mobile/pages/uu_chrome.dart` 的 `_menuPage` / `_settingsPage` | 待开工，分支 `refactor/action-drawer` |

分工边界：A 不碰 `remote_input.dart`，B 不改防窥/自动解锁逻辑；两边都要动 `uu_chrome.dart` 时先在 issue 里对齐。
各自切分支、PR 回 `local/1.5.3-android`，不要直接推主线。

### 8.1 手势引擎：滚动 vs 缩放

现状不足：只用 focalPoint 漂移 + `d.scale` 阈值 0.06 判缩放，两指同向但指尖有平行漂移时会误锁缩放；滚轮固定 `dy/4` 一格，快慢手感一致。

目标实现：

1. 数据源：画布外层挂 `Listener`（onPointerDown/Move/Up），用 pointer id 记录每根手指的坐标；现有 Scale 回调只负责 pan/缩放。
2. 初始窗口：第二根手指按下后 100ms 内，分别求两指相对各自按下点的位移向量 v1、v2。
3. 判定（一旦锁定，本次手势内不再切换，沿用 `_twoFingerMode` 状态机）：
   - 单帧两指位移都 ≥ 8px 才计入采样；
   - θ = angle(v1, v2) < **30°** 的采样点 ≥ 6 个 → 锁**滚动**；
   - v1·v2 < 0（等价 θ > 150°）的采样点 ≥ 6 个 → 锁**缩放**；
   - 100ms 窗口结束证据不足时最多观察到 160ms，仍不足默认锁滚动（误触缩放代价更大）；
   - 按下后前 3 帧（约 48ms）不采样，避开触点抖动。
4. `pinchZoom=false` 时永不进缩放模式，全部按滚动处理。
5. 水平方向可先留 TODO，只做垂直滚动。

参考依据：Google Android 手势指南「滚动量随手势速度变化（drag/swipe/fling）」；专利 CN113986109B 的双指夹角阈值 0~35° + 至少 6 对采样点；Android 常见 pinch 判定为「两指位移分量相乘为负」。

### 8.2 动态滚动灵敏度

- 每次滚动更新取 `focalPointDelta.dy`，维护 EMA 速度 `v = 0.7*v + 0.3*(dy/dt)`；150ms 无事件后 v 衰减归零。
- 按 |v| 查表换「每格像素」：`<300 px/s → 60px/格`、`300–1200 → 线性 60→35`、`>1200 → 20px/格`，单帧最多 2 格。
- 积分器保留小数（现有 `_mouseScrollIntegral`），松手清零；参数提成 const 便于真机微调。
- 验收：galgame 快进连点与浏览器长页面各试一次，慢速能停在指定行，快速甩动不丢步。

### 8.3 操作页 IA 重构（按 UU 实机面板重设计，2026-11-21 补）

参照素材：UU 操作面板截屏（右缘 rail「操作/键盘/显示桌面/显示所有窗口」，点「操作」后的全高面板）。
现状问题：一级菜单平铺「操控方案 / 其他设置 / 会话设置 / 更多操作 / 手势与触摸模式 / 断开」，
手势开关藏在「其他设置」，与「手势与触摸模式」帮助项割裂；且 UU 顶部动作条、分组卡片结构完全没复刻。

**面板结构（自上而下，全高可滚动；右缘 rail 不变，仅「操作」高亮）**

#### A. 顶部动作条：5 个等宽方块（icon 28~32 + 11px 标签，间距 8）

| # | 按钮 | 激活态 | 1.5.3 接线 |
|---|---|---|---|
| 1 | 退出远控 | — | `clientClose(gFFI.sessionId, gFFI)` |
| 2 | 旋转屏幕 | 蓝=已旋转 | **无远端接口**：RustDesk 1.5.3 没有旋转被控端显示的 API；一期置灰/隐藏并说明「Windows 被控端暂不支持」 |
| 3 | 声音 | 蓝=正在串流声音 | `optionOn('disable-audio')` 取反显示；点击 `sessionToggleOption('disable-audio')`（语义见第 6 节：只影响串流） |
| 4 | 仅观看 | 蓝=开启 | `sessionToggleOption(kOptionToggleViewOnly)` + `gFFI.ffiModel.setViewOnly(id, v)`；读取 `ffiModel.viewOnly` |
| 5 | 小窗模式 | 蓝=画中画中 | **二期**：Android PiP。manifest 给 MainActivity 加 `supportsPictureInPicture`，MethodChannel 调 `enterPictureInPictureMode()`（API≥26，minSdk 22 需版本守卫），退出时 `setPictureInPictureParams` 可省 |

#### B.「操作」区（小标题 + 一张卡片，3 行）

- **启用按键映射**（A 图标 + Switch）：`sessionGetKeyboardMode(id)` 是否为 `'map'`；切换用
  `sessionSetKeyboardMode(id, value: 'map' | 'legacy')`（注释掉的 `changePhysicalKeyboardInputMode` 就是现成实现，见 remote_page.dart ~1032）。
- **屏幕触控 ｜ 鼠标指针**（分段控件，选中项蓝底白字）：`gFFI.ffiModel.toggleTouchMode()` +
  `mainSetLocalOption(kOptionTouchMode, touchMode ? 'Y' : 'N')`（remote_page getGestureHelp 现成写法）。
- **显示鼠标按键**（鼠标图标 + Switch）：`gFFI.ffiModel.virtualMouseMode.toggleVirtualMouse()`，
  本地选项 `show-virtual-mouse` 持久化；打开后画布叠加左/中/右键浮动按钮。

#### C. 折叠分组卡片（每张：图标 + 标题 + `›`，展开后是现有 row；卡片之间 12px）

1. **显示**（monitor 图标）
   - 画面缩放：吸附开关（fit/1:1 松手吸附）
   - 显示远端光标：`show-remote-cursor`（`ShowRemoteCursorState`）
   - 画质档位：能接就接，接不上的隐藏，不放假开关
2. **安全**（盾牌图标）
   - 操控时物理关屏（虚拟屏防窥）：现有 switch + pending/预插逻辑整体搬入（不要复制代码，抽成 widget）
   - 退出远控时锁定电脑：`lock-after-session-end`
   - 自动解锁（Windows 锁屏）：现有密码配置整体搬入
3. **外设**（USB 图标）
   - 虚拟按键方案：现 `schemes` 页入口（点开进二级页）
   - 按键放大：滑条
   - 点击按键时震动：switch
   - 手势与触摸：二级页（手势说明 + 双指缩放开关 + 8.2 的滚动灵敏度滑条）
4. **更多**（more 图标）
   - 会话设置：上游 `showOptions(context, id, gFFI.dialogManager)`
   - 更多操作：`widget.onShowActions()`
   - 文件传输/录制等：有就接，没有不摆

原则：同一概念只出现一处（声音只在顶部按钮，不再在分组里出现）；只搬位置，不改默认值。

**Widget 骨架（供实现参考）**

```dart
ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), children: [
  SizedBox(height: 96, child: Row(children: [for (final a in actions) Expanded(child: _actionTile(a))])),
  const SizedBox(height: 20),
  _sectionLabel('操作'),
  _card(Column(children: [_mapModeRow(), _touchPointerSegmented(), _virtualMouseRow()])),
  const SizedBox(height: 12),
  _groupCard('显示', '显示', children: [...]),
  _groupCard('安全', '安全', children: [...]),
  _groupCard('外设', '外设', children: [...]),
  _groupCard('更多', '更多', children: [...]),
])
```
- 卡片：`Color(0xFF2F2F31)` / 圆角 14 / 内边距上下 4；激活色沿用 `MyTheme.accent`（蓝）。
- 折叠组用 `AnimatedSize` + 本地 `Set<String> _expanded`（默认全收起，和 UU 一致）。
- 现有 `_toggleRow` / `_sliderRow` 保留复用，`_menuPage` 旧 ListTile 列表整体删除。

**分期**：P0 = 纯 UI 重排 + 已有功能接线（A1/A3/A4 + B 三行 + C 四组）；
P1 = 小窗模式 PiP；P2 = 旋转屏幕（需用户拍板：客户端画布旋转 or 直接不做）。
手势引擎（8.1/8.2）独立分支先合，灵敏度滑条挂在 C3「手势与触摸」二级页。

## 9. 真机测试清单（每版过一遍）

1. 连接后横屏；关掉系统自动旋转，左右翻转手机应保持横屏并切换左右方向。
2. 黑边区域为纯黑（OLED 不发光）。
3. 双指竖直滑 = 滚轮；斜向滑动不误触发滚动；点画布外 = 返回。
4. 键盘面板：tab 切换、唤 IME 立即弹出、IME 开着时点外不退出、IME 收起后点外可返回。
5. 悬浮键：点击有按压反馈/震动；按住 Ctrl 快进（galgame）；拖动可移位并持久化。
6. 右缘：四块区域整块可点；点外收起；闲置 4s 淡出。
7. 操作面板：顶部动作条「退出远控/声音/仅观看」状态色正确；按键映射、屏幕触控/鼠标指针、显示鼠标按键生效；防窥、退出锁屏、自动解锁、虚拟按键方案都在对应分组里且逐一生效；防窥点击瞬间有转圈，先预插虚拟屏、约 4s 后开启，失败会回滚并提示。
8. 退出会话后：被控端物理屏恢复、声音恢复、未勾选时不锁屏。

## 10. 已知问题

- 手动输密码后偶发串流卡在锁屏帧（Winlogon 安全桌面切换），新版未稳定复现，暂时搁置。
- 首次开启虚拟屏防窥的驱动竞态见第 6 节；若多次重试仍失败，重启被控端一次。
- 24H2 上第三方虚拟屏退出后可能无法恢复（上游注释），RustDesk 自带（Amyuni）未观察到。

## 11. 沟通

- 功能/接口有疑问先在 PR 或 issue 里写清场景和期望行为；改共享代码前先对齐。
- 被控端排查日志位置（Windows）：`C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\log\server\RustDesk_rCURRENT.log`。
