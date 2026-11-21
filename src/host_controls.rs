//! Host-side controls driven from the mobile client through the privacy-mode
//! message channel (`impl_key` values prefixed with `uu:`).
//!
//! The Android client reuses the official 1.5.3 librustdesk.so, which cannot
//! send any message this fork adds, so the only reachable channel with a free
//! string payload is `TogglePrivacyMode.impl_key`.

use hbb_common::config::Config;
use serde_derive::{Deserialize, Serialize};
use std::sync::Mutex;

lazy_static::lazy_static! {
    static ref STATE: Mutex<State> = Mutex::new(State::load());
}

#[derive(Serialize, Deserialize, Clone)]
pub struct State {
    #[serde(default)]
    pub mute: bool,
    /// Restore the speaker to its pre-session state on disconnect.
    #[serde(default)]
    pub restore_audio: bool,
    /// Legacy combined flag; migrated into restore_audio on load.
    #[serde(default, skip_serializing)]
    pub restore_on_disconnect: bool,
    /// Endpoint mute state before we changed it, restored only when it is Some.
    #[serde(default)]
    pub prev_mute: Option<bool>,
    #[serde(default = "default_width")]
    pub display_width: u32,
    #[serde(default = "default_height")]
    pub display_height: u32,
    /// True DPI scaling of the virtual display, in percent (100/125/150/175).
    #[serde(default = "default_scale")]
    pub dpi_scale: u32,
}

fn default_width() -> u32 {
    1920
}

fn default_height() -> u32 {
    1080
}

fn default_scale() -> u32 {
    125
}

impl Default for State {
    fn default() -> Self {
        Self {
            mute: false,
            restore_audio: false,
            restore_on_disconnect: false,
            prev_mute: None,
            display_width: default_width(),
            display_height: default_height(),
            dpi_scale: default_scale(),
        }
    }
}

fn path() -> std::path::PathBuf {
    Config::path("uu-host-state.json")
}

impl State {
    fn load() -> Self {
        let mut s: Self = std::fs::read_to_string(path())
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default();
        if s.restore_on_disconnect {
            s.restore_audio = true;
            s.restore_on_disconnect = false;
        }
        s
    }

    fn save(&self) {
        let p = path();
        if let Some(dir) = p.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        match serde_json::to_string_pretty(self) {
            Ok(s) => {
                if let Err(e) = std::fs::write(&p, s) {
                    hbb_common::log::error!("Failed to save host control state: {e}");
                }
            }
            Err(e) => hbb_common::log::error!("Failed to encode host control state: {e}"),
        }
    }
}

fn with_state<T>(f: impl FnOnce(&mut State) -> T) -> T {
    let mut guard = STATE.lock().unwrap();
    let res = f(&mut guard);
    guard.save();
    res
}

#[cfg(windows)]
fn set_system_mute(mute: bool) -> hbb_common::ResultType<()> {
    use windows::core::GUID;
    use windows::Win32::Media::Audio::Endpoints::IAudioEndpointVolume;
    use windows::Win32::Media::Audio::{eMultimedia, eRender, MMDeviceEnumerator};
    use windows::Win32::System::Com::{
        CoCreateInstance, CoInitializeEx, CLSCTX_ALL, COINIT_MULTITHREADED,
    };
    unsafe {
        // The caller thread may already be in a different apartment; either way
        // the endpoint object can still be created.
        let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
        let enumerator: windows::Win32::Media::Audio::IMMDeviceEnumerator =
            CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)?;
        let device = enumerator.GetDefaultAudioEndpoint(eRender, eMultimedia)?;
        let volume: IAudioEndpointVolume =
            device.Activate(CLSCTX_ALL, None)?;
        volume.SetMute(mute, std::ptr::null::<GUID>())?;
    }
    Ok(())
}

#[cfg(not(windows))]
fn set_system_mute(_mute: bool) -> hbb_common::ResultType<()> {
    Ok(())
}

#[cfg(windows)]
fn system_is_muted() -> Option<bool> {
    use windows::core::GUID;
    use windows::Win32::Media::Audio::Endpoints::IAudioEndpointVolume;
    use windows::Win32::Media::Audio::{eMultimedia, eRender, MMDeviceEnumerator};
    use windows::Win32::System::Com::{
        CoCreateInstance, CoInitializeEx, CLSCTX_ALL, COINIT_MULTITHREADED,
    };
    unsafe {
        let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
        let enumerator: windows::Win32::Media::Audio::IMMDeviceEnumerator =
            CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL).ok()?;
        let device = enumerator.GetDefaultAudioEndpoint(eRender, eMultimedia).ok()?;
        let volume: IAudioEndpointVolume = device
            .Activate(CLSCTX_ALL, None)
            .ok()?;
        volume.GetMute().ok().map(|b| b.as_bool())
    }
}

#[cfg(windows)]
fn active_user_sid() -> Option<String> {
    use windows::Win32::Foundation::{CloseHandle, HLOCAL, HANDLE};
    use windows::Win32::Security::Authorization::ConvertSidToStringSidW;
    use windows::Win32::Security::{GetTokenInformation, TokenUser, TOKEN_USER};
    use windows::Win32::System::RemoteDesktop::{WTSGetActiveConsoleSessionId, WTSQueryUserToken};
    unsafe {
        let session = WTSGetActiveConsoleSessionId();
        if session == u32::MAX {
            return None;
        }
        let mut token = HANDLE::default();
        if WTSQueryUserToken(session, &mut token).is_err() {
            return None;
        }
        let sid = (|| {
            let mut len = 0u32;
            let _ = GetTokenInformation(token, TokenUser, None, 0, &mut len);
            if len == 0 {
                return None;
            }
            // u64 words keep the buffer 8-byte aligned for TOKEN_USER.
            let mut buf = vec![0u64; (len as usize).div_ceil(8)];
            GetTokenInformation(
                token,
                TokenUser,
                Some(buf.as_mut_ptr() as *mut core::ffi::c_void),
                (buf.len() * 8) as u32,
                &mut len,
            )
            .ok()?;
            let user = &*(buf.as_ptr() as *const TOKEN_USER);
            let mut pwstr = windows::core::PWSTR::null();
            ConvertSidToStringSidW(user.User.Sid, &mut pwstr).ok()?;
            let s = pwstr.to_string().ok();
            let _ = windows::Win32::Foundation::LocalFree(Some(HLOCAL(pwstr.0 as *mut core::ffi::c_void)));
            s
        })();
        let _ = CloseHandle(token);
        sid
    }
}

/// Writes the DPI value of every known Amyuni virtual-monitor entry in the
/// active user's hive. Windows re-reads these on monitor hotplug, which is
/// exactly when privacy mode plugs the virtual display in.
#[cfg(windows)]
fn write_per_monitor_dpi(scale: u32) -> usize {
    use windows::core::{PCWSTR, PWSTR};
    use windows::Win32::System::Registry::{
        RegCloseKey, RegEnumKeyExW, RegOpenKeyExW, RegSetValueExW, HKEY, HKEY_USERS, KEY_READ,
        KEY_WOW64_64KEY, KEY_WRITE, REG_DWORD,
    };
    let Some(sid) = active_user_sid() else {
        hbb_common::log::warn!("No active console user; DPI scale not applied");
        return 0;
    };
    let index: u32 = match scale {
        125 => 1,
        150 => 2,
        175 => 3,
        200 => 4,
        _ => 0,
    };
    let mut count = 0usize;
    unsafe {
        let sub = format!("{sid}\\Control Panel\\Desktop\\PerMonitorSettings");
        let sub_w: Vec<u16> = sub.encode_utf16().chain(std::iter::once(0)).collect();
        let mut root = HKEY::default();
        let rc = RegOpenKeyExW(
            HKEY_USERS,
            PCWSTR(sub_w.as_ptr()),
            Some(0),
            KEY_READ | KEY_WRITE | KEY_WOW64_64KEY,
            &mut root,
        );
        if !rc.is_ok() {
            hbb_common::log::warn!("Open PerMonitorSettings failed: {:?}", rc);
            return 0;
        }
        let mut i = 0u32;
        loop {
            let mut name = [0u16; 256];
            let mut len = name.len() as u32;
            let rc = RegEnumKeyExW(
                root,
                i,
                Some(PWSTR(name.as_mut_ptr())),
                &mut len,
                None,
                None,
                None,
                None,
            );
            if !rc.is_ok() {
                break;
            }
            i += 1;
            let key_name = String::from_utf16_lossy(&name[..len as usize]);
            // The Amyuni USB virtual monitor exposes no EDID (vendor 0x1414),
            // so Windows names its per-monitor key NOEDID_1414_008B_*.
            if !key_name.starts_with("NOEDID_1414_") {
                continue;
            }
            let kn: Vec<u16> = key_name.encode_utf16().chain(std::iter::once(0)).collect();
            let mut subkey = HKEY::default();
            let rc = RegOpenKeyExW(
                root,
                PCWSTR(kn.as_ptr()),
                Some(0),
                KEY_WRITE | KEY_WOW64_64KEY,
                &mut subkey,
            );
            if !rc.is_ok() {
                continue;
            }
            let data = index.to_le_bytes();
            let rc = RegSetValueExW(
                subkey,
                windows::core::w!("DpiValue"),
                None,
                REG_DWORD,
                Some(&data),
            );
            let _ = RegCloseKey(subkey);
            if rc.is_ok() {
                count += 1;
                hbb_common::log::info!("DPI scale {scale}% written to {key_name}");
            } else {
                hbb_common::log::warn!("Failed to write DpiValue for {key_name}: {:?}", rc);
            }
        }
        let _ = RegCloseKey(root);
    }
    count
}

#[cfg(not(windows))]
fn write_per_monitor_dpi(_scale: u32) -> usize {
    0
}

/// Re-applies the persisted DPI scale (idempotent, cheap).
pub fn apply_dpi_scale_to_active_user() {
    let scale = STATE.lock().unwrap().dpi_scale;
    let count = write_per_monitor_dpi(scale);
    if count > 0 {
        hbb_common::log::info!("Virtual display DPI scale {scale}% applied");
    }
}

pub fn set_dpi_scale(scale: u32) {
    let scale = match scale {
        125 | 150 | 175 | 200 => scale,
        _ => 100,
    };
    with_state(|s| s.dpi_scale = scale);
    hbb_common::log::info!("Host DPI scale set to {scale}");
    apply_dpi_scale_to_active_user();
}

/// Applies the persisted mute state when the host server starts.
pub fn init() {
    let (mute, width, height) = {
        let s = STATE.lock().unwrap();
        (s.mute, s.display_width, s.display_height)
    };
    crate::privacy_mode::set_virtual_display_mode(width, height);
    if mute {
        if let Err(e) = set_system_mute(true) {
            hbb_common::log::error!("Failed to re-apply host mute: {e}");
        }
    }
    apply_dpi_scale_to_active_user();
}

pub fn set_mute(mute: bool) {
    with_state(|s| {
        if mute && !s.mute {
            s.prev_mute = system_is_muted();
        }
        s.mute = mute;
        if let Err(e) = set_system_mute(mute) {
            hbb_common::log::error!("Failed to set host mute {mute}: {e}");
        } else {
            hbb_common::log::info!("Host mute set to {mute}");
        }
    });
}

pub fn set_restore_audio(restore: bool) {
    with_state(|s| s.restore_audio = restore);
    hbb_common::log::info!("Host audio restore-on-disconnect set to {restore}");
}

/// Called when the last remote connection goes away.
pub fn on_all_connections_closed() {
    let (restore_audio, mute) = {
        let s = STATE.lock().unwrap();
        (s.restore_audio, s.mute)
    };
    if restore_audio && mute {
        let prev = with_state(|s| {
            let prev = s.prev_mute.take();
            s.mute = prev.unwrap_or(false);
            prev
        });
        let target = prev.unwrap_or(false);
        if let Err(e) = set_system_mute(target) {
            hbb_common::log::error!("Failed to restore host mute {target}: {e}");
        } else {
            hbb_common::log::info!("Host mute restored to {target} after session end");
        }
    }
}

/// Handles `uu:<cmd>` payloads. Returns true when the key was consumed.
pub fn handle_command(key: &str, on: bool) -> bool {
    match key {
        "mute" => {
            set_mute(on);
            true
        }
        "restore" | "restore-audio" => {
            set_restore_audio(on);
            true
        }
        _ => {
            if let Some(size) = key.strip_prefix("display:") {
                if let Some((w, h)) = size.split_once('x') {
                    if let (Ok(w), Ok(h)) = (w.parse::<u32>(), h.parse::<u32>()) {
                        crate::privacy_mode::set_virtual_display_mode(w, h);
                        with_state(|s| {
                            s.display_width = w;
                            s.display_height = h;
                        });
                        return true;
                    }
                }
            }
            if let Some(scale) = key.strip_prefix("scale:") {
                if let Ok(scale) = scale.parse::<u32>() {
                    set_dpi_scale(scale);
                    return true;
                }
            }
            false
        }
    }
}
