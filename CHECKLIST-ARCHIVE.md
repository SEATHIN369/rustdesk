# 目标 / 测试清单（共同维护）

约定：你直接加行、改期望、在结果里写现象；我回填状态与证据。不要写密码 / Peer ID / 公网 IP。
状态：⬜ 待测 ｜ 🔄 进行中 ｜ ✅ 通过 ｜ ❌ 失败 ｜ ⏸ 阻塞 ｜ 🗑 废弃
排查思路与 Windows 侧已知坑（A/W 宏、锁屏限制、幽灵屏、DPI、构建校验）在 `TROUBLESHOOTING.md`。

最近更新：2026-11-22 12:34（03:22 四项后又修三项：操作卡重叠根因/手势说明改 UU 页可返回/防窥保守解锁门控；纯客户端）

## 工件与环境

- 分支：`local/1.5.3-android`（本轮 7 项改造代码 + 文档），已推 fork（github.com/kitsuneMori96/rustdesk）
- 主机 DLL：36,243,968 B，SHA256 `1BE43068…645C`，已部署到 `D:\soft\apps\RustDesk`（02:29:39 起服务运行，新 --server 无 panic、`Virtual display mode set to 1920x1080` 只读路径；该 DLL 来自上一轮 UU 化七项 = 防窥解锁门控 `uu:lock?`/`uu:unlock-state:` 回报 + 意外断连锁屏 Drop 补钩；本轮 4 项修正纯客户端未动 DLL；上一版 33CBAF65 备份为 selfbuild-prev.bak）
- 手机 APK：`D:\Download\共享文件夹\rustdesk-uu-android-arm64-2026-11-22-1234.apk`，29,295,827 B，SHA256 `694406ae…b9bf`（12:34 三项修正：①操作卡关掉按键映射仍重叠的**根因**（外层 AnimatedSize+无裁剪卡）改硬条件渲染 ②「查看手势说明」从上游 GestureHelp 弹条改为抽屉内 UU 页、可返回 ③防窥改保守解锁门控——仅主机报 `lock-state==0` 才提交关屏，锁屏/过渡/未知只等待复探、不再因失败直接翻 OFF；旧 0322 APK 已删）
- 主机 DLL：本轮**未变**，仍 `1BE43068`（36,243,968 B，02:29 部署运行）；主机测试包仍 02:29 版 `FD973798`（12:34 三项全在客户端，无需重编 DLL/重打主机包）
- 协作者包：`D:\Download\共享文件夹\rustdesk-host-win64-selfbuild-2026-11-21.zip`，14,621,253 B（18:07 打包）；补丁 8 个文件，已验证能打在 tag 1.5.3 上
- 分发测试包（Windows 便携应用）：`D:\Download\共享文件夹\rustdesk-uu-host-win64-test-2026-11-22-0229.zip`，34,211,636 B，SHA256 `FD973798…1EAB`（02:29 打包，含新 DLL `1BE43068`；README-TEST 已更新解锁门控/意外断连锁屏/哈希；Compress-Archive 压缩率与原包不同体积略大；旧 0103 包已删）
- 构建脚本：`C:\Users\Administrator\AppData\Local\Temp\rd-build\build.bat`（主机）/ `build_apk.bat`（APK）
- 主机安装目录：官方备份 `librustdesk.dll.official-1.5.3.bak`，上一版自编译 `librustdesk.dll.selfbuild-prev.bak`

## 本轮待真机（重点）

### 03:22 四项 UI/行为修正（纯客户端，只装新 APK 即可）

- 音量键控**媒体**音量（T12b 修订）：远控中按手机音量键应调手机媒体音量（看视频/外放那个），不再是「调到别的东西、媒体没动」；电脑音量仍不变
- 抽屉宽度按 UU 比例（T19c 新增）：右滑「操作」抽屉明显收窄到约 23% 屏宽（原 `min(430,…)` 太宽），与 UU 实机侧栏比例对齐；右缘图标列 `right:72` 不变
- 二级/一级菜单不再透明重叠（T18 修订）：「操作」卡「启用按键映射」ON 展开三行、再展开「其他设置」（按键放大滑杆+震动）时，展开体不再压到下方「操作方式/屏幕触控/鼠标指针」行（根因：外层 AnimatedSize 套内层 AnimatedSize，缓存到中途动画高度致溢出；改内层为普通条件渲染）
- 去掉「外设」无用折叠层级（T19 修订）：外设组只剩「手势与触摸」一行，已撤掉该折叠卡，「手势与触摸」直接以普通卡片行呈现；菜单层级变为 显示 / 安全 /（手势与触摸行）/ 更多

### 12:34 三项修正（纯客户端，只装新 APK 即可）

- 操作卡重叠**根因**修复（T18 再修订）：启用按键映射 OFF 时，之前「切换操控方案/当前方案:GalGame/其他设置」几行仍会压在「操作方式/屏幕触控/鼠标指针」上——上轮只拆了**内层** AnimatedSize，**外层** `AnimatedSize+Align(heightFactor)` 折叠后布局高度变小但子内容仍继续绘制，且该卡容器（`_card`）无裁剪，于是溢出到下一行。本轮改成硬条件渲染：开关 OFF 时展开体**根本不进树**，彻底不画。
- 手势说明改 UU 抽屉内页（T19e 新增）：「手势与触摸」二级页里的「查看手势说明」不再弹上游 RustDesk 的 GestureHelp 底部条（原来打开后没有返回入口、退不出来），改为进入抽屉内「手势说明」页，左上角返回回到「手势与触摸」，上级页链正确。
- 防窥改保守解锁门控（T45/T46 再修订）：开防窥时先探测解锁状态；**只有主机回报「未锁屏(0)」才提交关屏**；锁屏(2)/过渡(1)/未知(-1) 一律进入「等待被控端解锁」显示，每 4s 复探、最长 10 分钟，期间不会因一次失败或一直锁着就把开关翻回 OFF；超时才提示「解锁后请重新开启」。未知时不重试直接回退旧流程（兼容旧 DLL）。

### UU 化七项（02:29，主机 DLL + APK 都需最新）

- 需求1 按键映射就地展开（T18/T19）：「操作」卡顶部「启用按键映射」总开关，ON 就地展开三行（切换操控方案/编辑当前方案/其他设置→按键放大滑杆+点击震动），关则隐藏悬浮键但保留方案配置；外设组只剩「手势与触摸」；不再有独立二级页、无中间返回层
- 需求2 工具球一步直达 + 共处（T19b）：点最小化工具球一步展开「操作」抽屉；抽屉展开时右缘 操作/键盘/显示桌面/所有窗口 仍可见可点；键盘面板与右缘图标共存不互挡
- 需求3 防窥先确认解锁再关屏（T45/T46）：锁屏时手动开防窥不再秒跳关，显示「等待被控端解锁后自动开启」，解锁后自动完成关屏；未锁屏开防窥正常；旧 DLL 主机 3s 探测超时回退旧流程不卡死
- 需求4 意外断开也锁屏（T32）：勾「退出远控时锁定电脑」后，正常退出锁屏（回归）；网络波动/拔网线致最后连接消失也锁屏；波动后成功重连不误锁
- 需求5 IME 点外一步关（T12）：键盘面板点画布外一步关闭（不再点两次）；抽屉开着时点外只关抽屉不吞键盘
- 需求6 音量键只控手机（T12b）：远控中按手机音量键只改手机音量、电脑音量不变
- 需求7 双指偏滑动（T10b）：双手双指滑动稳定滚动不误判为缩放；刻意反向张手捏合仍能缩放（可关「双指缩放」使其恒滚动）
- 回归：光标无灰罩无重影、解锁提速、静音查询、普通聊天收发、悬浮键点击/拖动/震动
- 先装 02:29 主机包 + 02:25 APK（主机 DLL 与 APK 本轮都变，两边都要最新；主机服务已重启运行新 DLL，若 RustDesk 界面被本次部署关掉请重新打开）

## 1. 产品目标

- G1 UU 1:1 手机外壳 + 操作页 IA → ✅（T16–T19 通过）
- G2 双指竖直滑 = 远端滚轮 → ✅（T5–T7）
- G3 捏合缩放 → ✅（T8 已修）
- G4 快速滚动跟手 → ✅（T6）
- G5 键盘面板 + 悬浮键 → ✅（T11–T15）
- G6 被控端静音 → ✅（T20 / T21）
- G7 断开后恢复声音开关 → ✅（T22 / T23），物理屏断开一律还原
- G8 虚拟屏缩放 → 🔄 改 Windows 显示设置权威（手机不再设缩放，主机只读回），待真机（T26）
- G9 虚拟屏分辨率四档 → ⬜ 待真机（T27）
- G10 防窥流程稳健 → 🔄 已做「先确认解锁再关屏」门控（`uu:lock?`/`uu:unlock-state:` 回报），待真机（T45/T46）
- G11 自动解锁（含空格密码） → 🔄 闭环版已就绪，待真机（T29–T44）
- G12 设置页弹窗可唤 IME → ✅（T31）
- G13 主机 DLL 交付协作者 → ✅（见上面协作者包）
- G14 小窗模式 PiP → ⏸ 未开工（P1）
- G15 顶部动作条 → ✅ 第五格 = 画质
- G16 退出远控锁定电脑 → 🔄 正常退出已 ✅；本轮补意外断连锁屏（Drop 补钩），待真机（T32）
- G17 音量键只控手机 / 双指手势偏滑动 / 工具球一步直达共处 → 🔄 本轮新增，待真机（T12b/T10b/T19b）

## 2. 真机测试清单

### 2.1 连接与画布

- T1 手机连本机：进入远控页、横屏 → ✅
- T2 关系统自动旋转后左右翻转：保持横屏并换左右 → ✅
- T3 四周黑边：纯黑 → ✅
- T4 单指拖动 / 双指平移：跟手，松手吸附 1:1 或贴边 24px → ✅

### 2.2 手势

- T5 双指竖直慢滑：慢速档，可停在指定行 → ✅
- T6 双指快速大甩：明显加速、不丢步 → ✅
- T7 双指斜滑约 45°：不误触发滚动 → ✅
- T8 常规幅度捏合：立即缩放 → ✅ 已修采样门控
- T9 关掉「双指缩放」后捏合：不再缩放 → ✅
- T10 三指下滑：交给系统截屏 → ✅
- T10b 双手双指滑动不误判缩放：稳定判为滚动；刻意反向张手捏合仍能缩放 → 🔄 待真机。引擎（SEA369-owned `remote_input.dart`）温和收紧：`_kTwoFingerIntentMinSpreadPx` 10→16、`_kTwoFingerIntentZoomAngleDeg` 130→140，投票条件由 OR 改 AND（`angle>140 && spreadDelta>=16` 才投缩放票），近平行滑动即使自然张开也判滚动；`MinSamples=4`、终局默认滚动 tie-break 不变

### 2.3 键盘与悬浮键

- T11 打开键盘面板切输入法：IME 弹出、画布不缩 → ✅
- T12 IME 开着点画布外：一步关闭键盘面板（不再两段式先收 IME 再点外）→ 🔄 待真机（用户：关掉点外退出防误触）。已改：点画布外 `onTap` 直接 `keyboardOpen=false`+`_hideIme()`，一步关面板；抽屉打开时点外语义交给抽屉 barrier（`drawerPage!=null` 不渲染键盘 barrier）；barrier 与键盘 sheet 均收窄 `right:72` 不挡右缘图标列
- T12b 音量键：远控中按手机物理音量键只改手机**媒体**音量、电脑音量不变 → 🔄 待真机。Kotlin `MainActivity.dispatchKeyEvent` 在 `super`（会进 Flutter→转发主机）之前拦截 `KEYCODE_VOLUME_UP/DOWN/MUTE`，用本机 `VolumeController`（`STREAM_MUSIC`，03:22 由 `STREAM_SYSTEM` 改——上一版控的是 STREAM_SYSTEM 通知/系统流，用户反馈「调到的是别的东西、媒体音量没动」）调音量并 `return true` 消费，音量键不再进 Flutter 管线
- T13 悬浮键点击：按压反馈 → ✅
- T14 按住 Gal 预设 Ctrl：远端按住 / 松开 → ✅
- T15 拖动悬浮键：可移位并持久化 → ✅

### 2.4 右缘与操作面板

- T16 点右缘圆钮：竖排菜单、4s 淡出、点外收起 → ✅
- T17 顶部五格：退出远控 / 画质 / 声音 / 仅观看 / 小窗 → 🔄 待真机（用户：驳回，放键盘完全无意义）。第五格已改「画质」，可选 原画 / 高 / 中 / 低
- T18 屏幕触控 / 鼠标指针：逐一有效 → ✅；官方白色鼠标按键已隐藏（拍板），「显示鼠标按键」开关移除。按键映射改回 UU 就地展开式：「操作」卡顶部总开关 `keyMapEnabled`（关掉即隐藏悬浮键，切换方案不当开关），ON 时就地 AnimatedSize 展开三行（切换操控方案→`schemes` 页、编辑当前方案→内联编辑、其他设置→展开「按键放大」滑杆 + 「点击按键时震动」）。撤销上一轮的 `_keymapPage` 独立二级页。**03:22 修透明重叠**：「其他设置」展开体原用嵌套 AnimatedSize，外层缓存到内层中途动画高度致溢出压住下方「操作方式」行；改内层为普通 `if (moreOpen)` 条件渲染，只剩外层一个 AnimatedSize 测真实最终高度，不再重叠。**12:34 再修（OFF 仍重叠）**：上轮只拆内层；外层 `AnimatedSize+Align(heightFactor)` 折叠后布局高度变小但子内容照样绘制，而该卡容器（`_card`）无 `clipBehavior`，所以 OFF 时三行仍压在「操作方式」行上（截图复现）。本轮把展开体改为硬条件渲染——`if (uuState.keyMapEnabled.value) _keymapExpanded()`，OFF 时根本不进 widget 树，彻底不画
- T19 折叠组 显示 / 安全 / 更多：默认收起、展开正常 → ✅；**03:22 去掉「外设」无用折叠层级**——外设组只剩「手势与触摸」一行，已撤掉该折叠卡，「手势与触摸」改以普通 `_card(_navRow(...))` 行直接呈现（`_peripheralRows()` 已删）；抽屉返回层级 方案→菜单（不再有 按键映射 中间层）
- T19b 工具球一步直达 + 共处：点最小化工具球一步展开「操作」抽屉（不再先亮图标列再点）；抽屉展开时右缘 操作/键盘/显示桌面/所有窗口 图标列仍可见可点，键盘面板与右缘图标共存不互挡 → 🔄 待真机。已改：`build` Stack 优先级 `editLayout>drawer>rail>球`，keyboardOpen 不再一票否决隐藏 chrome，`_edgeButton` onTap→`_openDrawer('menu')`，`_railColumn` 去自带全屏 barrier，抽屉/键盘区域让位 `right:72`，`_openKeyboard` 进入即清 `drawerPage`

### 2.5 被控端功能（需自编译 DLL）

- T20 开「电脑静音」：主机扬声器静音 → ✅
- T21 关「电脑静音」：恢复原状态 → ✅
- T22 开「断开后恢复声音」→ 静音 → 断开：自动恢复 → ✅
- T23 关「断开后恢复声音」→ 静音 → 断开：保持静音，重连仍静音 → ✅
- T24 开防窥后直接断开：物理屏必亮 → 🗑 已并入其他项
- T25 防窥中重连：断开还原、重连自动重新关屏 → 🔄 待真机（用户：启动前先报失败又报成功；进入隐式模式提示去掉，每次连接都打扰）。已改：commit 4 次重试；进入 / 退出提示与失败弹窗全删，失败只 toast
- T26 缩放改 Windows 权威：手机「安全」组删「显示缩放」行；远控中在 Windows 显示设置改虚拟屏缩放→画面真变大、重连保持 → 🔄 待真机。此前两轮（DisplayConfig -3/-4、修虚拟屏名 NUL）手机强制套用始终与 Windows 实际不符，本轮改 Windows 设置权威：主机 `on_privacy_display_ready` 只读回日志不再 set，删 `set_dpi_scale`/`scale:` 命令/`dpi_scale` 字段。虚拟屏初始缩放回 Windows 推荐值（1080p 通常 100%），用户自行在 Windows 调大。另：防窥 commit 会激活其他驱动残留的「已挂载无模式」虚拟屏（本机 UU/GameViewer 有 9 个），commit 后禁用多余活动屏，日志 `Privacy mode disabled extra display …`
- T27 分辨率 1536x864（虚拟屏分辨率行保留）＋ Windows 手动缩放：两者独立生效 → ⬜ 待真机
- T28 防窥开关全过程：立即转圈、4s 预插、失败回滚 → 🔄 待真机（用户：同上）。重试与去提示见 T25
- T29 自动解锁（密码 = 单个空格）：锁屏后自动输密码 + 回车成功 → 🔄 待真机（22:07 真机：主机收到命令但判为非锁屏）。根因：`GetUserObjectInformation` 在本编译单元是 **A 版**，返回 ANSI，上一版却用 `WCHAR[] + _wcsicmp` 比较，桌面名永远对不上「Winlogon」。已修：改回 ANSI 比较；判定细分 0/1/2/-1 并记日志；收到命令后最多轮询 12s 等锁屏出现。日志 `Auto unlock: lock screen detected` / `skipped, state … desktop …`
- T30 全角空格密码：保存时黄字警告 → ⬜
- T31 方案重命名 / 新建：能唤 IME 并改名 → ✅
- T32 勾「退出远控时锁定电脑」后断开：主机会话锁定 → ✅；本轮补：手机意外退出（网络波动/拔网线致最后连接消失）也锁屏 → 🔄 待真机。根因：网络掉线走 `stream.send` 失败→`on_close(&err,false)` 不加锁。改法（Rust）：`handle_option` 收到 `lock_after_session_end==Yes`（且有 keyboard 权限）记入会话级 `LOCK_ON_DISCONNECT_INTENT`（每个新 Remote 连接 `AuthedConnID::new` 清零）；在 `AuthedConnID::Drop` 的 `remote_count==0` 分支 `swap(false)` 消费该标志并 `lock_screen()`。优雅退出路径的 `on_close` 锁屏块先 `store(false)` 消费，Drop 不再二次锁（避免双锁）。重连会在旧连接 Drop 前注册新连接→`remote_count` 不归 0→不误锁
- T40 未锁屏时连接：主机跳过注入（日志 `skipped, state 0 desktop "Default"`），鼠标键盘正常 → ⬜
- T41 错误密码：主机重试 3 次后放弃，锁屏不被搞乱，手机可手动输入 → ⬜
- T42 锁屏 + 正确密码连测 10 次：每次都能解锁 → ⬜
- T43 旧版主机（18:59 包）配新版 APK：能力位缺失，自动退回旧的一次性输入方式 → ⬜
- T44 解锁页「立即尝试解锁」按钮：连上后锁屏才出现时手动触发 → ⬜
- T45 锁屏中开防窥：先探测再决定——`uu:lock?`→`uu:lock-state:N`，锁屏（state 2）时显示「等待被控端解锁后自动开启」、不挂会翻 OFF 的失败定时器，收到解锁回报（`uu:unlock-state:success|skipped` 或 lock-state 转 0/1）后才走关屏提交；45s 内仍未解锁→翻 OFF + toast「被控端仍处于锁屏，防窥已取消」→ 🔄 待真机。旧主机（无 `lock?`）3s 探测超时回退旧 direct 流程不卡死
- T46 防窥成功状态：本轮已从「仅诊断」升级为**解锁门控**——失败定时器只在确认解锁后挂起，锁屏期的 `ChangeDisplaySettingsEx` 拒绝不再误翻开关；`[uu-diag]` 诊断日志保留，若仍切不过去据 logcat+服务日志定位 → 🔄 待真机

### 2.6 回滚 / 异常

- T33 连官方 DLL 主机：显示「需被控端为编译版」，不崩 → ⬜
- T34 关屏保持 → 🗑 废弃（断开必还原）
- T35 防窥失败路径：20s 回滚并提示 → ⬜
- T36 鼠标指针模式下移动：只有单个远端光标跟手可见，没有拖影 → 🔄 待真机（已回退上游恒画：撤销首帧强制 show-remote-cursor 与按模式门控，修复全屏灰罩回归）
- T37 面板开着在画布拖动 / 点空白：鼠标能动、点空白收起 → ✅
- T38 关一次防窥 → 重连：不恢复；开启过 → 重连自动关 → ✅
- T39 密码框单个空格：显示 U+0020；全角 U+3000 黄字 → 🔄 待真机（存入格式已改为系统密钥库加密）。同时验证：升级后旧明文密码自动迁移、重启 App 后仍能解锁

## 3. 已知问题 / 风险

- 自编译 DLL 未开 hwcodec：UI 硬件加速不可用（预期，不影响功能）。
- 缩放权威改 Windows 显示设置：主机 `on_privacy_display_ready` 只读回当前缩放记日志（`left to Windows Settings`），不再强制套用手机档位（删 DisplayConfig -4 set 路径）；用户在 Windows 显示设置里改虚拟屏缩放，热插拔恢复手动值、重连保持。手机不再有「显示缩放」行。
- DPI 只改虚拟屏，物理屏缩放不动（现由 Windows 设置管，主机不主动改）。
- 虚拟屏初始缩放回 Windows 推荐值（1080p 通常 100%），需用户自行在 Windows 调大；旧 125% 一次性迁移已删。
- 断开后物理屏一定恢复；重连自动关屏靠手机端记住意图。
- 重启 RustDesk 服务会断开当前会话。
- 手动输密码后偶发卡锁屏帧（旧问题，未稳定复现）。
- 自动解锁注入的是账户密码：若电脑只配了 PIN / Windows Hello 且锁屏默认 PIN 框，输入会进 PIN 框而失败；需在锁屏切到「密码」登录。
- 自动解锁的锁屏识别与注入只在服务模式（SYSTEM 会话）下可靠；便携用户模式受 UIPI 限制。
- 锁屏期间 Windows 拒绝改显示模式，防窥开启必然失败（日志 `Privacy mode display commit attempt … failed`）；本轮根治：手机端开防窥前先 `uu:lock?` 查主机锁屏态，锁屏（state 2）时不挂会翻 OFF 的失败定时器、等主机确认解锁（`uu:unlock-state:success|skipped` 或 lock-state 转 0/1）后才提交关屏，未解锁超 45s 才翻 OFF + 提示；旧主机无 `lock?` 支持则 3s 探测超时回退直接开启流程。
- 退出远控锁屏改用「最后连接消失」补钩：`handle_option` 收到 `lock_after_session_end==Yes`（且有 keyboard 权限）写入会话级 `LOCK_ON_DISCONNECT_INTENT`（每个新 Remote `AuthedConnID::new` 清零）；`AuthedConnID::Drop` 的 `remote_count==0` 分支消费该标志并 `lock_screen()`，覆盖网络掉线（`on_close(lock=false)` 不锁的盲区）；优雅退出的 `on_close` 锁屏块先消费标志避免双锁；重连在旧连接 Drop 前注册新连接故 `remote_count` 不归 0、不误锁。已知限制：意图是主机级全局近似，单手机控单主机正确，并发多会话精确归属留后续。
- 手机音量键：官方 .so 经 Flutter key 管线把 `KEYCODE_VOLUME_*` 转发主机；Kotlin `MainActivity.dispatchKeyEvent` 在 `super` 前拦截并用本机 `VolumeController`（`STREAM_MUSIC`，03:22 由 `STREAM_SYSTEM` 改——STREAM_SYSTEM 控的是系统/通知流，媒体播放音量不动，用户反馈「调到别的东西」）调音量后 `return true`，音量键不再进 Flutter、不回传电脑。只作用于手机自身音量键（USB-OTG 外接键盘音量仍走 `InputService` 原路径）。
- 双指缩放/滑动判定（SEA369-owned `remote_input.dart`）：投票条件由 OR 改 AND（`angle>140° && spreadDelta>=16px` 才投缩放票，`angle<30°` 投滚动票），阈值 130→140、10→16；双手滑动时即使手指自然张开也判滚动。慢速/小幅捏合可能被判滚动，可关「双指缩放」使手势恒滚动。
- 光标恒画（上游形态）：`showCursorPaint`（非安卓对端、非内嵌光标、非相对鼠标模式）为真即画单个远端光标，不碰任何会话选项；键盘权限已让主机随路发送光标位置/形状，故无重影、无灰罩。「显示远端光标」开关翻的是真正的 `show-remote-cursor` 会话选项（默认关，两种模式可见可手动开）。教训：首帧强制 `show-remote-cursor=Y` 会让主机额外启动 `mouse_cursor` 服务，该服务在锁屏/切桌面瞬间崩溃（`os error 5`）并画出全屏灰罩——正常版从不强制该选项。
- 静音只在连接 / App 回前台时查询主机真实状态（`uu:mute?` → 聊天回 `uu:mute-state`，Dart 拦截 `uu:` 前缀）；会话中手动改 Windows 静音要到下次查询才同步——轻量方案的固有取舍，不做持续监听。
- 手机发自动解锁命令不再弹底部 toast（桌面画面从锁屏变桌面即反馈）。

## 4. 已拍板

- 小窗模式 PiP：后续再做。
- 屏幕旋转：无上游接口；第五格改「画质」。
- 官方白色悬浮鼠标按键：直接隐藏，不做改造。
- 显示缩放：Windows 显示设置权威，手机不再设缩放（删手机档位行＋主机强制套用）；虚拟屏分辨率四档保留。
- 按键映射：改回 UU 就地展开式——「操作」卡顶部真总开关 `keyMapEnabled`（驱动悬浮键显隐），ON 就地展开 切换方案/编辑当前方案/其他设置（放大+震动）；撤销上一轮的 `_keymapPage` 独立二级页，切换方案不当开关。
- 音量键：只控手机**媒体**音量（`STREAM_MUSIC`），不转发电脑。
- 抽屉宽度：按 UU 实机比例收窄到约 23% 屏宽（`min(300, (屏宽-72)*0.6)`），右缘图标列 `right:72` 保留。
- 「外设」折叠层级：只剩一行故废弃该分组，「手势与触摸」直接以普通卡片行呈现。
- 双指手势：往滑动温和收紧（OR→AND + 提阈值），减少双手滑动误判为缩放。
- 「显示鼠标按键」开关：本期省略（无鼠标键叠加层目标，放了是死控件），完整鼠标键簇留后续。
- 保持关屏：废弃，断开必定还原物理屏。

## 5. 变更记录

- 2026-11-21 15:40 创建清单。
- 16:20 打包推送第一轮修正（DLL `BA20BEE2`、APK `6D737A76`、协作者包 7 文件补丁）。
- 17:13 第二轮：真 DPI（DisplayConfig）、防窥重试去提示、锁屏文本切桌面、第五格画质、隐藏鼠标按键、gradle 堆 2G（DLL `6DA63C9C`、APK `F7FFEBA1`）。
- 17:30 清单改为列表式，清理过时数字与文案。
- 18:06 真机复测反馈（缩放生效但出现一堆虚拟屏）：定位到虚拟屏名字尾随 NUL 导致 DisplayConfig 匹配失败（自动缩放从未生效），并确认本机另有 UU/GameViewer IDD 残留 9 个已挂载幽灵屏；commit 后新增多余活动屏禁用逻辑，分辨率下发改用正确设备名。DLL `ABC99FC7` 已部署。
- 19:02 按用户要求打分发用 Windows 测试包（便携 zip，32.5 MB），README-TEST.txt 内含 DLL 校验、运行方式与反馈要求。
- 21:58 自动解锁升级（P0–P3）：把判断权挪到被控端——新增 `uu:unlock:<base64>` 命令（复用防窥通道，`uu_auto_unlock` 能力位区分新旧主机）；主机侧识别真锁屏（Winlogon 桌面 + LogonUI 进程，避开 UAC）、切输入桌面、SendInput 注入、轮询验证、最多 3 次重试并退格清场，全程不落明文密码；旧 Seq 注入补 `Seq input` 特征日志。手机侧密码改 Android Keystore AES-GCM 存本机（旧明文自动迁移）、解锁页新增手动触发。DLL `F3B1859C`、APK `714F62E9`，主机测试包 33.4 MB 重打。
- 22:16 真机复测（22:07 那次「主机没行动」）：根因是锁屏判定误报——`GetUserObjectInformation` 在本编译单元是 A 版（ANSI），被写成 WCHAR 比较后桌面名永不匹配。改回 ANSI 比较、判定细分 0/1/2/-1 并记桌面名日志、收到命令后 12s 轮询等锁屏。同一时刻的防窥 commit 失败是锁屏期间系统拒绝改显示模式所致（非 NUL 回归），客户端改为解锁后按意图自动重试（auto 模式不弹提示、不重复预插虚拟屏）。DLL `18FB5AD4` 部署，APK `D84BAA57` 出包。
- 22:24 追加修复：LogonUI 会吞掉锁屏的第一击，注入前先 tap 一次 VK_SHIFT 唤醒。最终 DLL `45AEC95B`（36,244,992 B）已部署、主机测试包重打为 22:26 版 `EF0AC652`；22:20 的中间包已删。
- 23:35 真机反馈五问题最小修复：① 解锁提速 `UNLOCK_WAIT` 4s→2s、唤醒/退格 settle 收紧；② 防窥 auto 恢复加 `_privacyAutoRecovering`，锁屏失败开关保持 ON 不跳关、预算改 60s 时间基、auto 失败重置预插；③ 光标按模式（指针恒画单光标、触控默认隐藏可手动开），首帧强制 `show-remote-cursor=Y`；④ 静音连接/回前台查询（主机 `mute?`→聊天 `uu:mute-state`，Dart 拦 `uu:`）；⑤ 缩放手机值为准（`on_privacy_display_ready` 始终套用存储值＋回读，删 else 覆盖）。另去掉手机发解锁命令的底部 toast。主机→手机反向通道复用聊天消息（官方 .so 转 `chat_client_mode`），不改 `src/client/*`。DLL `E047F868`（36,245,504 B，4m22s）部署＋服务重启（新 --server PID 12684，23:33:29 启动无 panic）；APK `83517080`（29,291,364 B，156s）；主机测试包 23:35 版 `21CDA2A0`（33,446,385 B），旧 2220/2226 包已清。五项均待真机复测。
- 2026-11-22 00:15 光标改动整体回退（修全屏灰罩回归）：23:35 APK 真机指针模式整个画面被半透明灰罩盖住（切触控消失、本机正常、连上瞬间就有重连不恢复）。用户纠正前几个版本光标本来正常→回退而非再设计。git 取证 `8305598ff` 之前恒画 `if (showCursorPaint)`、首帧无光标代码、面板翻真 `show-remote-cursor` 选项（默认关）= 正常版；坏两步是 `8305598ff` 改 `uuState.showRemoteCursor` 门控（默认 false→光标消失）与 `76a1f71db` 首帧强制 `show-remote-cursor=Y`→主机启 `mouse_cursor` 服务锁屏期崩溃 `os error 5` 画灰罩。修（仅 Dart 4 处）：首帧删强制选项段、绘制门恢复上游恒画、面板开关还原翻会话选项、删 `uuState.showRemoteCursor` 字段+重置（留 imeVisible/hostStateVersion/handleHostMessage/uuHostIntentKey）。其余四修复+去 toast 保留。纯客户端，主机 DLL 不变仍 `E047F868`、主机包仍 23:35 版 `21CDA2A0`（不重编不重启）。APK `4A243C30`（29,290,782 B，152.1s）→ 共享文件夹 0015 版，旧 2335 APK 已删。代码提交 `e95a55a6c`。待真机：光标无灰罩无重影（T36）+ 四修复回归。
- 2026-11-22 01:03 去手机缩放＋按键映射二级目录/真总开关＋防窥成功状态诊断：① 缩放改 Windows 显示设置权威——手机删「显示缩放」行＋125% 迁移，主机 `on_privacy_display_ready` 改只读回日志、删 `set_dpi_scale`/`scale:` 命令/`State.dpi_scale` 字段/`dpi_scale::set`（保留 get），虚拟屏初始缩放回 Windows 推荐值，用户自行在 Windows 调大、重连保持。② 「启用按键映射」改导航入口→二级页 `_keymapPage`（虚拟按键方案/按键放大/点击震动从外设组迁入），外设组只剩手势与触摸，抽屉返回层级 schemes→keymap→menu；新增持久化真总开关 `uuState.keyMapEnabled`（默认开）接线到 `uu_floating_keys.dart` 渲染门，关掉隐藏悬浮键、切换方案不当开关。③ 防窥物理关屏成功但手机按钮状态切不过去（T46）：静态链已读通且上游正确（00:30 日志取证主机 commit 成功应已发 PrvOnSucceeded、手机 PrivacyModeState 20s 为空），本轮只埋诊断不猜修——主机 `connection.rs::turn_on_privacy` 各分支＋Dart `model.dart::updatePrivacyMode`/`uu_chrome.dart` 防窥 worker 加 `[uu-diag]` 日志，待用户复现拿主机服务日志＋手机 logcat 下一轮定点修。编译坑：诊断日志在 match 移走 `impl_key` 后又借用致 E0382，函数开头克隆 `diag_impl_key` 修复（首轮 DLL 编译失败、wrapper 退出码 0 是假象，读 dll.log 才发现）。主机 DLL `33CBAF65`（36,241,920 B，3m36s）部署＋服务重启（新 --server 01:02:09 启动无 panic、`Virtual display mode set to 1920x1080` 只读路径）；APK `08D962D6`（29,290,745 B，141.6s）；主机测试包 01:03 版 `A9AB9F54`（34,210,191 B，Compress-Archive 重打），旧 0015 APK/2335 zip 已清。待真机：缩放走 Windows（T26）、按键映射二级页+总开关（T18/T19）、防窥复现给日志（T46）+ 光标/解锁/静音回归。代码提交 `ac8709e7f`（已推 fork）。
- 2026-11-22 02:29 UU 化七项改造：① 需求1 按键映射改回 UU 就地展开——「操作」卡顶部总开关 `keyMapEnabled`，ON 就地 AnimatedSize 展开三行（切换操控方案/编辑当前方案/其他设置→放大滑杆+点击震动），删上一轮的 `_keymapPage` 独立二级页，外设组只剩手势与触摸，抽屉返回层级 schemes→menu。② 需求2 工具球一步直达 + 共处：`uu_chrome.build` Stack 优先级 editLayout>drawer>rail>球、keyboardOpen 不再一票否决隐藏 chrome，`_edgeButton` onTap→`_openDrawer('menu')`，`_railColumn` 去自带全屏 barrier，抽屉/键盘区域让位 `right:72`，`_openKeyboard` 进入即清 `drawerPage`。③ 需求3 防窥先确认解锁再关屏：主机 `connection.rs` 新增 `uu:lock?`→`uu:lock-state:N` 同步查询、`host_controls::handle_command`/`auto_unlock::request_unlock` 加 `tx: Option<crate::server::Sender>`（`self.inner.tx.clone()`），run() 后按 outcome 映射推 `uu:unlock-state:success|skipped|failed` 跨线程 Misc chat；Dart `uu_state` 增 `hostLockState/hostUnlockState` + `uu:lock-state:`/`uu:unlock-state:` 分支，`uu_chrome` 防窥 ON 改事件机（探测锁屏→锁屏则等解锁/触发自动解锁+45s 预算→确认解锁才挂 8/20s 失败定时器，旧主机 3s 探测超时回退）。④ 需求4 意外断开也锁屏：`handle_option` 记 `LOCK_ON_DISCONNECT_INTENT`（新 Remote 清零）、`AuthedConnID::Drop` remote_count==0 消费补锁、优雅退出 `on_close` 先消费避免双锁。⑤ 需求5 IME 点外一步关（`remote_page` 键盘 barrier 去两段式、drawerPage 开时不渲染、收窄 right:72）。⑥ 需求6 音量键控手机（Kotlin `MainActivity.dispatchKeyEvent` super 前拦 `KEYCODE_VOLUME_*` 用 `VolumeController` STREAM_SYSTEM）。⑦ 需求7 双指偏滑动（`remote_input.dart` OR→AND、minSpread 10→16、zoomAngle 130→140）。编译坑：首轮 DLL 5 错——`crate::server::connection::Sender` 模块私有（改 `crate::server::Sender`）、`self.tx` 应为 `self.inner.tx`、Sender 元组 `Instant` 是 `hbb_common::tokio::time::Instant` 非 std；wrapper 退出码 0 是假象读 dll.log 才发现，二轮 BUILD_EXIT=0 通过。主机 DLL `1BE43068`（36,243,968 B，4m37s）部署（部署遇两 RustDesk.exe 界面进程锁 DLL，经用户同意结束后拷入 + 服务 02:29:39 重启无 panic）；APK `78466A18`（29,293,498 B，175.9s，02:25 出包）；主机测试包 02:29 版 `FD973798`（34,211,636 B，README-TEST 更新解锁门控/意外断连锁屏/哈希），旧 0103 APK/zip 已删。七项均待真机（T10b/T12/T12b/T18/T19/T19b/T32/T45/T46）。
- 2026-11-22 03:22 四项 UI/行为修正（纯客户端，DLL/主机包不变，只装新 APK）：据用户真机反馈。① 音量键改控**媒体**音量流——上一版 `MainActivity.dispatchKeyEvent` 拦音量键后调 `STREAM_SYSTEM`（系统/通知流），用户反馈「调到的是别的东西、媒体音量没动」，三处 `STREAM_SYSTEM`→`STREAM_MUSIC`。② 抽屉按 UU 比例收窄——`_drawer` 宽度 `min(430,(屏宽-72)*0.6)`→`min(300,…)`（对照 UU 实机侧栏约 23% 屏宽），用户嫌「整体画的太宽」。③ 修二级/一级菜单透明重叠——「操作」卡「其他设置」展开体原是嵌套 AnimatedSize（外层 AnimatedSize 套内层 AnimatedSize），外层缓存到内层中途动画高度致溢出压住下方「操作方式」行；删内层 AnimatedSize 改普通 `if (moreOpen)` 条件渲染，只留外层一个 AnimatedSize 测真实最终高度。④ 去掉「外设」无用折叠层级——外设组只剩「手势与触摸」一行，撤掉该 `_groupCard`，「手势与触摸」改以 `_card(_navRow(...))` 直接呈现，删 `_peripheralRows()`。`dart analyze` 通过；APK `ee75e3c3`（29,293,324 B，167.3s，03:22 出包）→ 共享文件夹 0322 版，旧 0225 APK 已删；主机 DLL 仍 `1BE43068`、主机包仍 02:29 版 `FD973798` 不变。四项均待真机（T12b 媒体音量 / T19c 抽屉宽度 / T18 无重叠 / T19 去外设）。