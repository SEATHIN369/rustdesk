# 排障手册（Windows 被控端 / 手机端）

这份文档不是功能说明，是「下次遇到问题怎么自己查」的手册。
里面每一条结论都是真机 + 日志 + 探针验出来的，不是推出来的。
功能与测试项在 `CHECKLIST.md`，构建步骤在 `ANDROID_BUILD_NOTES.md`，协作分工在 `COLLABORATION.md`。

约定：文档里不写密码、Peer ID、公网 IP。

---

## 0. 四步法

任何「不好使了」的反馈，按这个顺序走，不要跳步：

1. 取证：先证明代码在跑、命令收到了、走到了哪一行。没有日志就先去埋日志，别猜。
2. 归因：把时间线上的所有症状排在一起看。多个症状经常是同一个原因。
3. 最小修复：只改导致现象的那一处。修完能解释全部症状才算找对了。
4. 复测：给出一条能证伪的验证（日志里应该出现哪一行、界面上应该看到什么）。

反例（这次真踩了）：用户报「自动解锁没行动」，我第一反应是逻辑不对，
实际上一半是判定误报、一半是那次根本不该成功（锁屏期间系统禁止改显示模式）。
如果先取证，两条日志就能定死。

---

## 1. 环境与日志地图

### 进程拓扑（这条决定日志在哪）

- `RustDesk.exe --service`：会话 0，SYSTEM。它负责拉起登录会话里的 server。
- `RustDesk.exe --server`：会话 1（当前登录用户），SYSTEM。**被控端功能代码跑在这里**，
  锁屏输入、显示模式、DPI 缩放都必须是这个进程才有权限。
- `RustDesk.exe --tray` / 前台 UI：会话 1，用户权限。
- 只有 `--server` 的日志进 `C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\log\server\`。
  你在 `%APPDATA%\RustDesk\log\` 里翻不到被控端行为是正常的，那里只有 UI 和 `cm`（剪贴板/文件）。

### 日志路径速查

- 被控端（服务）：`C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\log\server\RustDesk_rCURRENT.log`
- 桌面 UI：`%APPDATA%\RustDesk\log\RustDesk_rCURRENT.log`
- 剪贴板 / 文件传输：`%APPDATA%\RustDesk\log\cm\`

### 「部署生效」怎么判定（别信 cp 成功）

已加载的 DLL 可以直接改名替换（本机验证过），但老进程仍跑旧镜像。所以：

1. 覆盖：当前 DLL 改名成 `.old` → 拷新的进去 → 删 `.old`（不要直接 `cp` 覆盖，可能被占用失败）。
2. `Restart-Service rustdesk`，让 `--service` 重新拉起 `--server`。
3. 证据 = 新 `--server` 进程 + 它的日志起始时间在你拷贝之后。
   `Get-CimInstance Win32_Process -Filter "Name='RustDesk.exe'" | Select ProcessId,SessionId,CommandLine`
4. 只看到服务 Running 不够，`--service` 在会话 0，跑旧镜像的往往是会话 1 那个没换。

### 文件被占用

装过 UU远程 / 托盘常驻的 RustDesk.exe 会锁住 DLL；用 QQ 传过的 APK 也会锁住导致 `packageRelease` 失败。
查占用用 Restart Manager（`rstrtmgr`，`RmGetList`），别乱 `kill`，先问用户。

---

## 2. 通用套路

### 2.1 先证明「收到」，再证明「收到后做了什么」

命令通道两端各埋一行日志，行号 + 关键入参的**特征**（不要写明文）。
一条消息「没反应」，先分清是没收到、还是收到了被前面的分支拦掉。

### 2.2 把布尔判定拆成多状态

`is_lock_screen() -> bool` 出问题时你只能猜。改成带状态码 + 把判据本身打进日志：

    -1 打不开输入桌面
     0 输入桌面不是 Winlogon（顺带记桌面名）
     1 是 Winlogon 但桌面里没有 LogonUI 窗口（UAC 安全桌面 / 切换瞬间）
     2 真锁屏

日志里那句 `skipped, state 0 desktop "Default"` 直接把根因指到「桌面名对不上」，
而原来那句 `skipped, not at the lock screen` 只会把人引向「代码逻辑错了」。

### 2.3 别信直觉，用探针独立验证 API 语义

不确定 Win32 API 在你这个编译单元里到底是 A 版还是 W 版、返回什么编码？
写个十几行的 P/Invoke 探针（`pwsh.exe`，不要用 PowerShell 5.1）直接调一次，看返回值。
这次就是探针打出 `desktop=Default`，才确认 `GetUserObjectInformation` 走的是 A 版。

探针脚本放系统临时目录，用完删掉，别留进仓库。

### 2.4 时间线对齐

把所有症状的时间戳抄到一行一行对照，再和日志、和用户操作顺序对。
本次对齐后的结论：22:07:24–29 防窥 commit 连环失败 + 22:07:29 解锁判「未锁屏」+ 22:07:51 `Desktop switched`
→ 电脑当时**确实锁着**，所以防窥必然开不起来，而解锁判定是误报。
症状「我的隐私屏设置又被改成关闭了」其实是「那次开启从没成功」，不是设置被写坏。
这一步省掉了至少一轮错误修复。

### 2.5 重试要有前提：失败原因是否会自己消失

- 会消失（锁屏期间禁止改显示模式、驱动刚插还没 ACTIVE）→ 轮询等待 / 延后重试，重试期间不打扰用户（不弹框、不 toast）。
- 不会消失（版本不支持、没权限）→ 干净失败 + 明确提示，别做 machinery 硬撑。
- 重试链路里**不要重复非幂等的动作**。`plug_in_monitor` 有数量上限、重复插会弹错误框，
  所以客户端要记住「这次会话已经预插过了」。

### 2.6 新旧版本共存用能力位

手机端会连到旧主机（官方 DLL / 旧自编译 DLL）。任何新协议都必须：

- 主机在 `platform_additions` 里报能力位（例如 `uu_auto_unlock`）；
- 客户端先查能力位，缺就走旧路径（旧的一次性盲输），不能让旧主机收到看不懂的命令。

反例：`uu:unlock:` 复用防窥 `impl_key` 通道，旧主机收到会当成隐私模式实现键处理，行为不可预期。

### 2.7 版本号混搭会直接崩

原生层复用官方 1.5.3 的 `librustdesk.so`，Dart/Kotlin 必须基于 tag `1.5.3`。
master 的 Kotlin 调了 1.5.3 里没有的 JNI（`setInputServiceOpen` 等），混搭是 `UnsatisfiedLinkError` 闪退。
所以「升级上游」和「换原生层」必须一起做，不能只换一边。

---

## 3. Windows 侧已知坑（现象 / 根因 / 正确写法）

### 3.1 A/W 宏陷阱：没定义 UNICODE，A/W 后缀函数会走 A 版

- 现象：桌面名比较永远不相等；文本处理看起来「什么都没发生」。
- 根因：`src/platform/windows.cc` 这个编译单元没有定义 `UNICODE`，
  于是 `GetUserObjectInformation`、`GetTextMetrics` 这类不带显式后缀的调用解析到 **A 版**，
  返回 **ANSI**。既有代码本来就用 `char[] + strcmp`，不是随便写的。
- 错误写法：`WCHAR name[256]` + `_wcsicmp(name, L"Winlogon")` → 永远 false。
- 正确写法：`char name[256]` + `_stricmp(name, "Winlogon")`。
- 通用规则：改这个文件之前先看邻居代码用什么类型；要用 W 版就显式写 `...W`。

### 3.2 虚拟屏设备名的 NUL 填充

- 现象：明明只插一块屏，DisplayConfig 里查不到 / 匹配不上；缩放「设了没生效」。
- 根因：`DISPLAY_DEVICEW.DeviceName` 是 `[WCHAR; 32]`，剩下全是 NUL。直接拿整串去匹配必然失败。
- 正确写法：按第一个 NUL 截断，再喂给 DisplayConfig / `change_resolution`。

### 3.3 锁屏（Winlogon 安全桌面）

四条都踩过，合起来才解释得通「密码对，但报密码错」：

1. 输入注入必须先把当前线程切到输入桌面：`SwitchDesktop`（我们的封装 `try_change_desktop()`）。
   只给 Chr 路径切了、Seq 路径没切 → 密码落到用户桌面被丢弃。
2. 通道选择：锁屏密码框只认 **Seq** 通道（`sessionInputString`）；
   逐字符 `inputKey` 走 Chr 路径会被丢。
3. `ChangeDisplaySettingsEx` 在锁屏期间被拒绝：`ret: -1`，`GetLastError: 0`。
   所以防窥在锁屏下必然开不起来，别当成驱动/NUL 回归去修。
4. LogonUI 会吞掉第一击（用来收起锁屏浮层）。注入密码前先 tap 一个无文本效果的修饰键（VK_SHIFT）。
5. 锁屏 vs UAC 安全桌面：两者桌面名都是 Winlogon。
   靠 `EnumDesktopWindows` 里有没有 `LogonUI.exe` 的窗口区分
   （`QueryFullProcessImageNameW` 取文件名比对）。判错会把密码注进 UAC 提示框。

### 3.4 `CDS_RESET` 会点亮别人的残留屏

- 现象：调分辨率/缩放之后，Windows 设置里冒出一堆虚拟屏。
- 根因：`ChangeDisplaySettingsExW` 的 `CDS_RESET` 提交会把其它 IDD 驱动下
  「attached 但没有模式」的显示器一并激活（本机 UU/GameViewer 有 9 个、Amyuni 2 个）。
- 正确写法：提交后主动用 `CDS_UPDATEREGISTRY | CDS_NORESET` 把多余的活动屏禁掉。
  日志行 `Privacy mode disabled extra display ...` 就是这段在工作。
- 顺带：`EnumDisplayDevicesW` 第 2 个参数传设备名字符串指针 = 按该设备过滤，传 NULL 才是全枚举。

### 3.5 Amyuni usbmmidd 虚拟屏

- `plug_in_monitor` **非幂等**、有数量上限，超了返回「already plugged」并弹客户端消息框。
  重试链路必须记住已预插（我们的 `_privacyPreplugged`）。
- 插入后约 6 秒才 ACTIVE，服务端只等 5 秒会误判失败。客户端节奏：预插 → 4s 发 on → 12s 重试 → 20s 回滚。

### 3.6 DPI 缩放

- 写注册表 `PerMonitorSettings` **无效**：系统缓存，要注销才生效（真机实测仍 100%）。
- 正确做法：DisplayConfig 的未公开设备信息类型 `-3`（GET_SOURCE_DPI_SCALE）/ `-4`（SET_SOURCE_DPI_SCALE），
  直接 `DisplayConfigGetDeviceInfo` / `DisplayConfigSetDeviceInfo`。
- 必须在**登录会话的 `--server` 进程**里调。会话 0 的服务进程查询返回 0 条路径（探针实测）。
- 用户可能手动改过缩放：系统仍是推荐值 → 套用存储值；用户改过 → 保留并写回状态。别覆盖用户选择。

### 3.7 音频

- 协议的 `disable-audio` 只停串流，不关电脑扬声器。
- 1.5.3 官方主机没有主机侧静音通道（KEY_MAP 无音量键、`VolumeMute` 在 Translate 模式被丢弃、媒体键是切换语义）。
  要真静音只能自编译主机里用 WASAPI `IAudioEndpointVolume::SetMute`（幂等）。
- 状态要落盘并在服务启动时重放（`uu-host-state.json`），否则重启电脑后静音丢失/残留。

### 3.8 自定义命令怎么发（官方 .so 不能加消息类型）

复用 `TogglePrivacyMode.impl_key`，内容以 `uu:` 前缀，在 `connection.rs::toggle_privacy_mode` 里拦截，
要求 `is_authed_remote_conn()`，拦截后**不要**真的切隐私模式。已有：
`uu:mute` / `uu:restore-audio` / `uu:display:WxH` / `uu:scale:<pct>` / `uu:unlock:<base64 密码>`。
载荷解码用 `crate::common::decode64`（这个 crate 没有可直接用的 base64 依赖）。

### 3.9 敏感数据

- 密码只在内存里 `Vec<u16>`，用完 `fill(0)`；日志只记次数和长度，绝不记明文。
- 手机端密码存 Android Keystore（AES-GCM，alias `uu_auto_unlock_v1`），
  本地 option 只存 `{on, enc}`；旧版本存的明文首次加载时自动迁移。
- 文档/清单/提交信息里不写密码、Peer ID、公网 IP。

---

## 4. 手机端（Flutter）常见坑

- 官方 `.so` 提供的 `bind.session*` 是上限：新交互只能在 Dart/Kotlin 侧做，别指望发新协议消息。
- `SessionID` 是 `UuidValue` 不是 int：写 `sid == 0` / `int sid` 直接编不过。
- 沉浸式全屏用 `MainActivity` 的 `WindowInsetsController` 原生隐藏系统栏；
  Flutter 的 `immersiveSticky` 在部分 ROM 上无效。
- 远控页常驻 `FLAG_ALT_FOCUSABLE_IM`，要弹系统输入法的窗口前用 `_withIme()` 放行；
  点画布外第一次点击只收键盘、不透传鼠标。
- 打开键盘面板时画布**不缩小**（旧的上移缩小方案被否），靠 `ensureCursorVisible()` 做最小平移保证光标可见。
- 效果类问题一定要实测再改：捏合被采样门控饿死、Overlay 缓存子树不重建这类，静态看代码看不出来。

---

## 5. 构建 / 打包 / 校验

### 命令与耗时基线

- 主机 DLL：`C:\Users\Administrator\AppData\Local\Temp\rd-build\build.bat`
  （vcvars64 → `cargo build --release --lib --features flutter`，写 `dll.log`，末尾打 `BUILD_EXIT=`）
  实测增量 3m46s–4m14s。工具链：Rust MSVC（`C:\Users\Administrator\.cargo\bin`，PATH 里没有）、
  MSVC 14.51 `D:\soft\BuildTools`、LLVM 20+ 取 libclang、vcpkg `D:\soft\vcpkg` + `res/vcpkg-win`，triplet `x64-windows-static`。
- APK：`build_apk.bat`（Flutter 3.24.5 + JDK17，写 `apk.log`），Gradle 约 145s。
  `flutter/android/gradle.properties` 必须 `org.gradle.jvmargs=-Xmx2048M`，
  否则 `:app:packageRelease` 在 `IncrementalSplitter` 抛 OOM（1G 时）。

### 成功判据

- 构建后先看 `BUILD_EXIT=` / Gradle 的 `BUILD SUCCESSFUL`，再读产物大小和哈希；
  管道尾巴（`| tail`）会把失败掩盖掉。
- 报「已修好」之前，必须有：产物哈希 + 部署证据（新进程/新日志）+ 一条可证伪的复测项。

### 工件一致性

- 任何一次代码改动，DLL / APK / 主机分发 zip 三处都要重打，只换一边测不出来。
- 构建进行中如果又来了新反馈：**先停构建**，攒齐改动再一次性打包，别出过时的包。
- Git Bash 里没有 `zip`，用 `/c/Windows/System32/tar.exe -a -c -f 目标.zip 内容...`。
- 重打之后要**全文扫一遍旧数字**：清单和 README 里过时的哈希、字节数、提交号、时间点，
  一次清干净，别只改被点到的那一行。被取代的中间包删掉，不留两个「最新」。
- 临时目录用固定命名（`rd-build`、`rd-dist-NNNN`），删除只写字面路径，不用 `mktemp` / 命令替换。

---

## 6. 复测项怎么写（能证伪）

每项包含：动作 → 期望现象 → 期望日志行 → 状态。

    - T40 未锁屏时连接：主机跳过注入（日志 `skipped, state 0 desktop "Default"`），鼠标键盘正常 → ⬜

状态只允许：⬜ 待测 ｜ 🔄 进行中 ｜ ✅ 通过 ｜ ❌ 失败 ｜ ⏸ 阻塞 ｜ 🗑 废弃。
「静态检查过」不是通过；只有真机验证过才打 ✅。
失败时把日志原文抄进条目里（截图也行），别只写「不行」。
负面结论也要记：本次「不是 NUL 截断回归、不是虚拟屏驱动冲突、不是 hwcodec 缺失、不是 Defender 拦的」
都是花时间排除出来的，写下来能防止下次重走。

---

## 7. 案例复盘：22:07 自动解锁「主机没行动」

时间线：

    22:07:24–29  防窥 commit 连续 4 次失败（ret -1 / GetLastError 0）
    22:07:29.108 收到 uu:unlock → 记 skipped, not at the lock screen
    22:07:41.932 再次收到 → 同上
    22:07:51     Desktop switched（用户手动解锁）

归因（两条独立，各自成立）：

1. 解锁：`GetUserObjectInformation` 是 A 版返回 ANSI，代码却用 `WCHAR + _wcsicmp` 比较
   → 桌面名永远不等于 "Winlogon" → 判定恒假 → 收到命令却跳过。探针确认 A 版返回 `Default`。
2. 防窥：当时电脑锁着，Windows 拒绝在锁屏改显示模式 → 开启失败 → 手机端开关显示为关。
   用户看到的「设置被改回关闭」= 那次开启从未成功，不是状态被覆盖。

修复：

- 判定改回 `char[] + _stricmp`，状态细分 0/1/2/-1 并把桌面名写进日志；
- 收到命令后最多轮询 12s 等锁屏出现（服务刚切桌面时瞬时判 0 不算失败）；
- 注入前 tap VK_SHIFT 唤醒锁屏；
- 手机端防窥意图在解锁后自动重试（auto 模式失败不弹提示，时间预算约 60s，期间开关保持开启不跳关），
  并用 `_privacyPreplugged` 避免重复预插（auto 失败会重置它以便下轮按需重新预插）。

经验：一个「看起来像逻辑 bug」的问题，实际是编码假设错误 + 系统限制两件事叠加。
先取证、再拆状态、再对齐时间线，三步走完根因自己会跳出来。

## 案例：真机五问题（解锁慢 / 防窥跳关 / 看不到光标 / 静音失同步 / 缩放不生效）

22:26 主机包 + 22:20 APK 真机复测后用户报五个问题。读主机运行日志 + 代码取证，根因各自坐实：

1. **解锁等待太长**：`auto_unlock.rs` 每次失败 attempt 要空等满 `UNLOCK_WAIT=4s` 才判失败。
   日志：attempt 1 注入 → 4s 后才放弃，attempt 2 仅 ~122ms 就成功。
   修：`UNLOCK_WAIT` 4s→2s，唤醒 settle 300→200ms、退格 settle 200→150ms。
   成功离开 Winlogon 实测 ~120ms，2s 足够；最坏空等从 ~13.5s 降到 ~6s。检测窗 12s 保留。
2. **解锁后防窥开关被关**：手机端在还锁屏时就抢着开防窥 → Winlogon 拒绝 display commit →
   `PrvOnFailed` → `_privacyWorker` 立刻清 `_privacyPendingOn` → 开关跳「关」；
   旧 `_restorePrivacyIntent` 20 次计数预算被 2s/4s 双链快速耗尽。
   修：加 `_privacyAutoRecovering` 标志，恢复期间即便 pending 清空、state 为空，tile 仍显示 ON
   （`value: pending ?? (recovering || on)`）；预算改 60s 时间基；auto 失败重置 `_privacyPreplugged`。
   手动路径完全不变。
3. **手机看不到光标**（用户纠正：当初默认关是因为画了两个光标有重影）：
   重影只发生在触控模式（本地手指指示 + 滞后远端光标）；指针模式本地系统光标隐藏
   （`SystemMouseCursors.none`），画远端光标只有一个。旧代码全局默认 `showRemoteCursor=false`
   把指针模式也关了 → 完全无光标。另：光标位置来自主机 NAME_POS，仅 `show_remote_cursor` 开时订阅。
   修：按模式区分——绘制门 `!touchMode || showRemoteCursor`（指针恒画、触控仅手动开）；
   首帧强制 `show-remote-cursor=Y` 让主机发位置；`showRemoteCursor` 语义改为触控覆盖（默认 false 不变）；
   「显示远端光标」开关仅触控模式可见。**不是**一刀切默认开。
4. **静音状态失同步**：手机纯本地 bool 缓存，主机 `set_system_mute` fire-and-forget 无上报；
   用户手动改 Windows 静音 → 手机显示与实际不符。修（用户拍板轻量方案）：仅连接 / 回前台查询，
   主机 `mute?` 读 `system_is_muted()` 回聊天 `uu:mute-state:<0/1>`，Dart 拦截刷新。不做持续监听。
5. **缩放不生效**：`on_privacy_display_ready` 只要 `cur != recommended` 就走 else 用 Windows 当前值
   **覆盖**手机存的 `dpi_scale`（日志 `kept at Windows setting 125% (recommended 100%)`）。
   Windows 热插拔按注册表恢复手动缩放 → 用户手动改过一次后 `uu:scale` 永远被丢弃。
   修：始终套用存储值（权威意图）＋ set 后回读校验，被 clamp/失败记 warn；删 else 覆盖分支。

**硬约束（反向通道）**：Android 复用官方 1.5.3 `librustdesk.so`，`src/client/*` 改不动。
主机→手机唯一干净带字符串载荷的反向通道是**聊天消息**：主机发 `Misc.chat_message` →
官方 .so 转 `chat_client_mode` 事件 → Dart `model.dart` 在此加薄钩子拦截 `uu:` 前缀（不进 chatModel、
不计未读、不响铃）。`back_notification.privacy_mode_state` **不可用**：官方 .so 会弹 Privacy mode 框
＋改写 privacy-mode 选项，污染隐私状态。零新协议。

**构建坑（这次踩到）**：Git Bash 里 `cmd.exe /c "build.bat"` 的 `/c` 会被 MSYS 路径转换吃掉，
cmd 进交互壳即 EOF 退出，bat 根本没跑——任务通知还报 exit 0。靠核对产物 mtime 抓出来
（dll.log/APK 全是旧时间戳，stdout 只有 cmd 横幅没有 BUILD_EXIT）。
修：`MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' cmd.exe /c "..."`。
教训：后台构建报成功前必须读产物新 mtime＋日志 `Finished`/`✓ Built`＋BUILD_EXIT，别信 wrapper 退出码。

产物：DLL `E047F868`（36,245,504 B，4m22s）部署＋服务重启核实运行期；APK `83517080`（29,291,364 B）；
主机测试包 23:35 版 `21CDA2A0`。五项均待真机复测。

## 案例：指针模式全屏灰罩（2026-11-22 00:15，光标改动整体回退）

**现象**：23:35 APK 真机——解锁提速生效，但指针模式下整个远控画面被一层半透明灰罩盖住，
内容几乎看不清。差分测试：① 切触控模式灰罩消失；② 电脑本机画面正常；③ 连上瞬间就有、重连不恢复。

**用户关键纠正**：前几个版本光标本来正常——不消失、不重影、也没有错误遮罩。
所以不是「需要新光标方案」，而是两轮光标改动把本来好好的功能改坏了。方向应是**回退**而非再设计。

**git 取证**（`8305598ff` 之前 = 用户认可的正常版）：
- 正常版绘制门恒画：`if (showCursorPaint) { paints.add(CursorPaint(widget.id)); }`，不碰任何选项；
  首帧回调里没有任何光标代码。
- 正常版 UU 面板「显示远端光标」翻的是真正的 `show-remote-cursor` 会话选项
  （`ShowRemoteCursorState` + `bind.sessionToggleOption`），默认关。

**坏的两步**：
1. `8305598ff`（拖影修复）把恒画改成 `uuState.showRemoteCursor`（默认 false）门控 → 光标默认消失
   （上一轮「看不见鼠标」抱怨的来源）。「拖影」前提本身被用户否定。
2. `76a1f71db`（fix 3）首帧**强制 `show-remote-cursor=Y`** + 指针模式恒画。强制选项让主机额外启动
   `mouse_cursor` 服务（NAME_CURSOR）——运行日志 `23:42:33.845 ERROR mouse_cursor service: 拒绝访问
   (os error 5)` 正是它，在锁屏/切桌面瞬间崩溃并画出全屏灰罩。正常版从不强制该选项（键盘权限已让主机
   随路发送光标位置/形状，connection.rs `peer_keyboard_enabled() || show_remote_cursor`），故无此服务、无灰罩。

**排除的静态嫌疑**（都不是灰罩来源）：`decode_cursor_data` 光标上限 MAX_CURSOR_SIZE=512；
`ImagePainter` 用 `canvas.scale + drawImage(Offset)` 按自然尺寸画、不拉伸；画布底色纯黑
（kColorCanvas/MyTheme.canvasColor=0xFF000000）；Android 视频 bgra8888 不透明；Dart 侧无全屏白罩
（BlockableOverlay 中层透明、emptyOverlay 底层不透明黑、点外 barrier 是透明 GestureDetector）。
决定性证据是用户触控差分 + git 正常版形态 + 主机 mouse_cursor 服务 os-error-5 崩溃日志三者吻合。

**修**（仅客户端 Dart 4 处，主机 DLL 不动）：
1. `remote_page.dart` 首帧：删掉强制 `show-remote-cursor` 整段 + `uuState.showRemoteCursor.value=false`。
2. `remote_page.dart` 移动端绘制门：恢复上游 `if (showCursorPaint) { paints.add(CursorPaint(widget.id)); }`。
3. `uu_chrome.dart::_displayRows`：「显示远端光标」还原为翻会话选项（不再按 touchMode 门控）。
4. `uu_state.dart`：删 `showRemoteCursor` 字段与 resetSessionUi 里的重置；保留 imeVisible/hostStateVersion/
   handleHostMessage/uuHostIntentKey（fix 2/4 仍用）。
其余四修复（解锁提速/防窥不跳关/静音查询/缩放权威值）与去解锁 toast 保留不动。

**教训**：① 用户说「以前是好的」时，先 git 取证回到已知良好形态，别在坏前提上继续叠加新方案。
② 强制 `show-remote-cursor=Y` 会启动主机 mouse_cursor 服务，该服务锁屏期崩溃画灰罩——
光标恒画 + 选项默认关才是正常态，不要自动强制该选项。③ 灰罩这类「画面被盖住」先做模式差分
（指针 vs 触控）定位是哪条绘制/服务路径，再对照 git 历史，比纯静态读码更快收敛。

产物：APK `4A243C30`（29,290,782 B，152.1s，00:15）；主机 DLL 无改动仍 `E047F868`、
主机测试包仍 23:35 版 `21CDA2A0`（不重编 DLL、不重启服务）。待真机复测光标无灰罩无重影 + 四修复回归。
