# 排障案例归档（2026-11-22 前）

> 从 TROUBLESHOOTING.md 移出的历史案例复盘，仅供追溯；当前有效的方法与坑见 TROUBLESHOOTING.md。

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

## 手机强制缩放覆盖 Windows 不生效 → 改 Windows 权威（2026-11-22）

**现象**：手机「安全」组选 125%/150% 缩放，开防窥后画面没变大，手机 UI 与实际不符。
**根因**：主机 `on_privacy_display_ready` 每次防窥 commit 都强制套用手机端存储的缩放档位
（DisplayConfig -4 set），把用户在 Windows 显示设置里手动改的值覆盖掉；手机档位与 Windows
实际推荐值/驱动 clamp 不一致时观感「不生效」。两套权威打架。
**修（用户拍板：Windows 设置权威）**：
1. 手机 `uu_chrome.dart`：删「显示缩放」ListTile（100/125/150/175 弹窗＋`scale:` 命令）与
   `_migrateScaleDefault()` 125% 一次性迁移；保留「虚拟屏分辨率」行。
2. 主机 `host_controls.rs`：`on_privacy_display_ready` 改**只读**——记录设备名＋轮询
   `dpi_scale::get` 记一条当前缩放日志（`Virtual display … DPI …%; left to Windows Settings`），
   不再 set；`on_privacy_display_gone` 只清设备名；删 `set_dpi_scale`/`scale:` 命令分支/
   `State.dpi_scale` 字段/`dpi_scale::set`＋SET 结构常量（保留 get 供日志读回）。
**效果**：虚拟屏初始缩放回到 Windows 推荐值（1080p 通常 100%），用户在 Windows 显示设置里改；
Windows 热插拔会恢复手动值，重连后保持。**需重编主机 DLL＋重启服务**（删主机强制是必要的，
否则下次防窥 commit 又覆盖 Windows 手动值）。

## 「启用按键映射」开关无接线 → 导航二级页＋真总开关（2026-11-22）

**现象**：手机「启用按键映射」开关只翻 map/legacy 键盘模式（`_keyboardMapRow`），不驱动悬浮键；
切换映射方案被当成开关用。
**修（用户拍板：导航入口＋整组迁入＋真总开关）**：
1. `uu_chrome.dart`：删 `_keyboardMapRow`/`_keyboardMapSupported`/`_keyboardMap`/`_loadKeyboardMode`；
   「外设」组首项改导航行「启用按键映射」→二级页 `_keymapPage`，含 虚拟按键方案（→schemes）/
   按键放大/点击按键时震动（三项从外设组迁入）；外设组只剩 手势与触摸。抽屉返回改层级
   `_parentPage`：schemes→keymap→menu、gestures→menu。
2. **真总开关**：`uu_state.dart` 新增持久化 `keyMapEnabled`（默认 true，load `!=false`、save 写回）；
   二级页顶部 `SwitchListTile`「启用按键映射」直接翻它；`uu_floating_keys.dart` 渲染门改
   `if ((scheme.keys.isEmpty || !uuState.keyMapEnabled.value) && !edit) return SizedBox.shrink()`。
   关掉即隐藏全部悬浮键，切换方案只换键位、不当开关。

## 防窥物理关屏成功但手机按钮状态切不过去 → 链已读通，待复现诊断（2026-11-22）

**现象**：电脑屏幕实际断电（防窥 commit 成功），手机收不到成功消息，按钮状态 20s 后回滚不翻 ON。
**主机日志取证**（`RustDesk_rCURRENT.log` 00:30 一次防窥，旧 APK）：
- `00:30:09` 提交成功：禁用多余屏 DISPLAY20/21 → `Virtual display DPI already at 125%`
  （`on_privacy_display_ready` 跑到 win_virtual_display.rs:639）→ `switch due to privacy mode changed`
  → capturer privacy id 803。说明 `turn_on_privacy` 返回 `Ok(true)`，主机**应已发 PrvOnSucceeded**。
- `00:30:26` `Failed to plug out virtual display 0: This only virtual display cannot be plugged out`
  ＝手机 `_privacyFailTimer`（20s）触发后去插拔虚拟屏 → 证明手机 `PrivacyModeState` 这 20s 一直为空。
- `00:30:51` 防窥又关。
**静态链已读通且为上游正确逻辑**：主机 `turn_on_privacy`（connection.rs:5191）虚拟屏 impl 的
`check_privacy_mode_err` 恒空（privacy_mode.rs:424，只有 WIN_MAG 做真测试）→ 发 `PrvOnSucceeded`；
官方 .so `handle_back_msg_privacy_mode`（io_loop.rs:2738）→ `update_privacy_mode(impl_key,true)`
（io_loop.rs:2698 置 `config.privacy_mode.v=true`、存配置、推 `update_privacy_mode` 事件 flutter.rs:706）
→ Dart `updatePrivacyMode`（model.dart:1811）读 `sessionGetToggleOptionSync('privacy-mode')`
＝`config.privacy_mode.v`（client.rs:3488）→ 置 `PrivacyModeState.find(peerId).value=implKey`。
impl_key 两端一致（`privacy_mode_impl_virtual_display`）。`sessionTogglePrivacyMode` 原生只发
TogglePrivacyMode misc（ui_session_interface.rs:404），**不本地置选项**——选项只在 PrvOnSucceeded 时置。
**结论**：链本身没错，失败是经验性的（消息是否送达/处理、是否被显示切换打断），不能靠猜下修复。
**本轮只埋诊断**（随包出，不猜修）：
- 主机 `connection.rs` `turn_on_privacy` 各分支发送前记 `[uu-diag]`：request impl_key/authed/flag、
  PrvOnFailedDenied、turn_on_res、PrvOnSucceeded/PrvOnFailed(res=false)、back_notification sent；
  `turn_off_privacy_result_to_msg` 记 impl_key＋result。
- Dart `model.dart::updatePrivacyMode` 记 isOn/写入后 state；`uu_chrome.dart` 防窥 worker 记
  PrivacyModeState 每次变化＋pending、requestPrivacy ON、失败定时器触发。
**下一步**：用户复现一次物理关屏，拿主机服务日志＋手机 logcat（`[uu-diag]`），据证据定点修
（若指向显示切换打断/消息丢失，再考虑主机补发或 uu: 反向通道回报防窥态——届时另出计划）。
**编译坑**：诊断日志在 match 把 `impl_key` 移进消息构造后又借用会 E0382；函数开头
`let diag_impl_key = impl_key.clone();` 专供末尾日志，避免移动后借用。

产物：APK `4A243C30`（29,290,782 B，152.1s，00:15）；主机 DLL 无改动仍 `E047F868`、
主机测试包仍 23:35 版 `21CDA2A0`（不重编 DLL、不重启服务）。待真机复测光标无灰罩无重影 + 四修复回归。

## 案例：UU 化七项改造（解锁门控 / 意外断连锁屏 / 音量键 / 双指偏滑动 / 就地展开 / 一步关 IME / 工具球共处）（2026-11-22 02:29）

### 锁屏期 `ChangeDisplaySettingsEx` 被拒 → 防窥先发 `uu:lock?` 确认解锁再提交

**现象**：锁屏时手动开防窥秒跳关；上一轮 T46 物理关屏成功但手机按钮切不过去，怀疑主机 commit 与锁屏时序纠缠。
**根因**：Windows 在 Winlogon 安全桌面拒绝改显示模式，防窥 commit 必失败；客户端 20s 失败定时器无差别把开关翻 OFF，用户看到「还没解锁就关掉」。
**正确写法（闭环回报）**：
- 主机 `connection.rs::toggle_privacy_mode` uu: 分支新增 `cmd=="lock?"` → 读 `crate::platform::windows::lock_screen_state().0`（0/1/2/-1），经 `Misc::set_chat_message` 回 `uu:lock-state:<N>`（复用聊天反向通道，官方 .so 会转 Dart `handleHostMessage`，不改 `src/client/*`）。
- 自动解锁回报跨线程：`handle_command(cmd,on,self.inner.tx.clone())` 透传 `Sender`，`auto_unlock::run()` 结束后按 outcome 前缀（success/done→success、skipped→skipped、其余→failed）用 tx 推 `uu:unlock-state:<status>`；`tx.send` 在连接已 drop 时返回 Err，`let _ =` 忽略。
- 客户端 `_togglePrivacy(true)` 先 `_sendHostCmd('lock?',true)`，`ever(hostLockState)`：state 2 → 置 `_privacyAwaitUnlock`、触发 `uu:unlock:`、起 45s 预算、**不挂失败定时器**；state≠2 → `_commitPrivacyOn()`。`ever(hostUnlockState)` success/skipped → commit，failed → 继续等。失败定时器只在 `_commitPrivacyOn`（已确认解锁）内挂（auto 8s/手动 20s）。旧主机无 `lock?`：3s 探测超时且 `hostLockState==null` → 直接 `_commitPrivacyOn()` 回退旧流程。

### `on_close(lock=false)` 不锁 → `AuthedConnID::Drop` remote_count==0 补锁

**现象**：勾了「退出远控锁定电脑」，正常退出会锁；网络波动/拔网线致手机掉线则不锁。
**根因**：只有显式 Close 走 `on_close(.., lock=true)`；写失败路径 `conn.stream.send` 报错走 `on_close(&err, false)` 不加锁。
**正确写法**：`handle_option` 收到 `lock_after_session_end==Yes` 且 `self.keyboard` → 写会话级 `static LOCK_ON_DISCONNECT_INTENT: AtomicBool`（每个新 Remote `AuthedConnID::new` 先 `store(false)`，防跨会话残留）；`AuthedConnID::Drop` 的 `remote_count==0` windows 块 `swap(false)` 消费该标志并 `crate::platform::lock_screen()`。优雅退出的 `on_close` 锁屏块先 `store(false)` 消费，避免与 Drop 双锁。**竞态安全**：重连在旧连接 Drop 前注册新连接 → `remote_count` 不归 0 → 不误锁。限制：意图为全局近似（单手机控单主机正确，并发多会话精确归属留后续）。

### 音量键经 Flutter 管线转发主机 → Kotlin `dispatchKeyEvent` 本地拦截

**现象**：远控中按手机音量键改的是电脑音量。
**根因**：`KEYCODE_VOLUME_*` 进 Flutter key 管线→`input_model` 恒 handled→转发主机；`InputService.kt` 的 `tryHandleVolumeKeyEvent`/`VolumeController` 只覆盖 USB-OTG 外接键盘。
**正确写法**：`MainActivity.dispatchKeyEvent` 在 `super`（会路由给 Flutter）之前拦截 ACTION_DOWN `VOLUME_UP/DOWN/MUTE`，用本机 `VolumeController(getSystemService(AUDIO_SERVICE) as AudioManager)` 调 `raiseVolume/lowerVolume/toggleMute(null,true,STREAM_SYSTEM)` 后 `return true`，事件不再进 Flutter。

### 双指缩放 OR 判定在双手滑动时误判 → 改 AND + 提阈值

**现象**：双手做滑动动作常被误判成缩放。
**根因**：投票条件 `angle>zoomAngle || spreadDelta>=minSpread`，滑动时两指自然张开（spreadDelta 达标）即投缩放票。
**正确写法**（SEA369-owned `remote_input.dart`）：改 AND `angle>140 && spreadDelta>=16` 才投缩放票、`angle<30` 投滚动票；阈值 `minSpread` 10→16、`zoomAngle` 130→140（温和收紧）。`MinSamples=4` 与终局默认滚动 tie-break 不变。改前需同步 SEA369。

### 首屏/工具球 IA：就地展开、一步直达共处、一步关 IME

- **按键映射改回就地展开**：撤销上一轮 `_keymapPage` 独立二级页；「操作」卡顶部 `keyMapEnabled` 总开关，ON 用 `AnimatedSize` 就地展开三行（切方案/编辑/其他设置→放大滑杆+震动），外设组只剩手势与触摸，抽屉返回层级 schemes→menu。
- **工具球一步直达 + 与右缘图标共处**：`build` Stack 优先级 `editLayout>drawer>rail>球`，`keyboardOpen` 不再一票否决隐藏 chrome；`_edgeButton.onTap`→`_openDrawer('menu')`（一步展开，不再先亮图标列）；`_railColumn` 去掉自带全屏 barrier；抽屉与键盘 sheet 区域让位 `right:72` 不挡图标列；`_openKeyboard` 进入即清 `drawerPage`（修关键盘后旧抽屉重弹）。
- **IME 一步关**：`remote_page` 键盘点外 barrier 去掉「先收 IME 再点才关」两段式，`onTap` 直接 `keyboardOpen=false`+`_hideIme()`；`drawerPage!=null` 时不渲染键盘 barrier（点外语义交给抽屉），区域收窄 `right:72`、保持 `opaque`。

### 编译坑（本轮 DLL 首编 5 错）

1. `crate::server::connection::Sender` 报 E0603「module connection is private」——`src/server.rs` 用 `mod connection; pub use connection::*;`，对外路径是 **`crate::server::Sender`**。
2. `self.tx` 报 E0609「no field tx on Connection」——`tx` 是 `ConnInner` 的字段，Connection 经 `self.inner` 持有 → 用 **`self.inner.tx.clone()`**（同文件 send_block_input_error/1819/4124 均如此）。
3. Sender 元组 `Instant` 报 E0308 类型不符——`connection.rs` 的 `Instant` 是 **`hbb_common::tokio::time::Instant`**（非 std），`report_status` 里 `Instant::now()` 必须用 tokio 版。
教训重申：wrapper `echo BUILD_EXIT=%ERRORLEVEL%` 后 `> file 2>&1` 的 Git Bash 调用返回 0 是**假象**，必须读 `dll.log` 的 `BUILD_EXIT=`/`error[` 才是真判据（本轮首次「成功」即被 dll.log 打脸）。

产物：主机 DLL `1BE43068`（36,243,968 B，4m37s）已部署并 02:29:39 重启服务无 panic；APK `78466A18`（29,293,498 B，175.9s，02:25）；主机测试包 02:29 版 `FD973798`（34,211,636 B）。部署遇两个 RustDesk.exe 界面进程（7016/11984）锁 `librustdesk.dll`——`Stop-Service` 不杀 GUI，需先 `Stop-Process` 这两个再拷 DLL（本机流程，经用户确认）。

## 案例：03:22 四项 UI/行为修正（纯客户端，DLL 不变）

**音量键调到「别的东西」**：上一轮在 `MainActivity.dispatchKeyEvent` 拦 `KEYCODE_VOLUME_*` 后调 `VolumeController`，但用的是 `AudioManager.STREAM_SYSTEM`（系统/通知流）。媒体播放走的是 `STREAM_MUSIC`，于是用户按音量键「确实动了某个音量、但外放/视频音量没变」。修：`raiseVolume/lowerVolume/toggleMute` 三处 `STREAM_SYSTEM`→`STREAM_MUSIC`。教训：音量键「有没有反应」不等于「控对了流」，Android 多音频流要按用途选 `STREAM_*`。

**二级菜单压住一级菜单（透明重叠）**：「操作」卡里 `keyMapEnabled` 的展开用外层 `AnimatedSize(Align heightFactor)`，而展开体 `_keymapExpanded` 内「其他设置」又嵌一个 `AnimatedSize(Align heightFactor)`。嵌套时外层 `AnimatedSize` 在子高变化帧里缓存到的是内层「动画中途」的小高度，于是外层只让出中途高度、内层内容却继续长到最终高度，溢出画到下方的「操作方式/屏幕触控/鼠标指针」行上（看着像半透明叠字）。修：删内层 `AnimatedSize`，「其他设置」展开体改普通 `if (moreOpen) _sliderRow(...)` 条件渲染——内层高度瞬时变化，外层单个 `AnimatedSize` 在同一帧测到真实最终高度，动画正常、不溢出。教训：**AnimatedSize 不要套 AnimatedSize**；需要「折叠里再折叠」时只保留一层动画，内层用条件渲染。

**抽屉太宽**：`_drawer` 宽度 `min(430, (屏宽-72)*0.6)` 在大屏上恒取 430 逻辑 px，相对 UU 实机侧栏（约 23% 屏宽）明显偏宽。对照 `uu远程素材/原生素材` 的横屏截图量得侧栏≈屏宽 23%、右缘图标列≈15%，把上限降到 `min(300, (屏宽-72)*0.6)`。教训：复刻第三方 App 的「比例」要拿实机截图按屏宽百分比量，别凭逻辑像素拍脑袋定上限。

**「外设」空壳分组**：按键映射迁入「操作」卡就地展开后，外设组只剩「手势与触摸」一行，折叠一层纯属多余。撤掉 `_groupCard('外设',…)`，把该行改回普通 `_card(_navRow(...))` 直接呈现，删 `_peripheralRows()`。教训：IA 重构后回看每个分组是否还有 ≥2 项，单项折叠卡应平铺掉。

产物：APK `ee75e3c3`（29,293,324 B，167.3s，03:22）；本轮全在 Dart/Kotlin，主机 DLL 仍 `1BE43068`、主机包仍 `FD973798` 不重编不重打，真机只需装新 APK。
