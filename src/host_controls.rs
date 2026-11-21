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
}

fn default_width() -> u32 {
    1920
}

fn default_height() -> u32 {
    1080
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
pub fn system_is_muted() -> Option<bool> {
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

/// Per-monitor scaling through the same undocumented DisplayConfig device info
/// types the Settings app uses (`-3` get / `-4` set, relative to the scale
/// Windows recommends for the monitor).
#[cfg(windows)]
mod dpi_scale {
    use windows::Win32::Devices::Display::{
        DisplayConfigGetDeviceInfo, GetDisplayConfigBufferSizes,
        QueryDisplayConfig, DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME,
        DISPLAYCONFIG_DEVICE_INFO_HEADER, DISPLAYCONFIG_DEVICE_INFO_TYPE, DISPLAYCONFIG_MODE_INFO,
        DISPLAYCONFIG_PATH_INFO, DISPLAYCONFIG_SOURCE_DEVICE_NAME, DISPLAYCONFIG_TOPOLOGY_ID,
        QDC_ONLY_ACTIVE_PATHS,
    };
    use windows::Win32::Foundation::{LUID, ERROR_SUCCESS};

    const DPI_VALUES: [u32; 12] = [100, 125, 150, 175, 200, 225, 250, 300, 350, 400, 450, 500];
    const GET_SOURCE_DPI_SCALE: DISPLAYCONFIG_DEVICE_INFO_TYPE =
        DISPLAYCONFIG_DEVICE_INFO_TYPE(-3);

    #[repr(C)]
    struct SourceDpiScaleGet {
        header: DISPLAYCONFIG_DEVICE_INFO_HEADER,
        min_scale_rel: i32,
        cur_scale_rel: i32,
        max_scale_rel: i32,
    }

    fn header(
        ty: DISPLAYCONFIG_DEVICE_INFO_TYPE,
        size: usize,
        adapter: LUID,
        id: u32,
    ) -> DISPLAYCONFIG_DEVICE_INFO_HEADER {
        DISPLAYCONFIG_DEVICE_INFO_HEADER {
            r#type: ty,
            size: size as u32,
            adapterId: adapter,
            id,
        }
    }

    fn active_paths() -> Option<Vec<DISPLAYCONFIG_PATH_INFO>> {
        unsafe {
            let mut npaths = 0u32;
            let mut nmodes = 0u32;
            if GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &mut npaths, &mut nmodes)
                != ERROR_SUCCESS
                || npaths == 0
            {
                return None;
            }
            let mut paths = vec![DISPLAYCONFIG_PATH_INFO::default(); npaths as usize];
            let mut modes = vec![DISPLAYCONFIG_MODE_INFO::default(); nmodes as usize];
            if QueryDisplayConfig(
                QDC_ONLY_ACTIVE_PATHS,
                &mut npaths,
                paths.as_mut_ptr(),
                &mut nmodes,
                modes.as_mut_ptr(),
                None::<*mut DISPLAYCONFIG_TOPOLOGY_ID>,
            ) != ERROR_SUCCESS
            {
                return None;
            }
            paths.truncate(npaths as usize);
            Some(paths)
        }
    }

    fn find_source(device: &str) -> Option<(LUID, u32)> {
        for path in active_paths()? {
            let mut name = DISPLAYCONFIG_SOURCE_DEVICE_NAME::default();
            name.header = header(
                DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME,
                std::mem::size_of::<DISPLAYCONFIG_SOURCE_DEVICE_NAME>(),
                path.sourceInfo.adapterId,
                path.sourceInfo.id,
            );
            if unsafe { DisplayConfigGetDeviceInfo(&mut name.header) } != 0 {
                continue;
            }
            let len = name
                .viewGdiDeviceName
                .iter()
                .position(|&c| c == 0)
                .unwrap_or(name.viewGdiDeviceName.len());
            let gdi = String::from_utf16_lossy(&name.viewGdiDeviceName[..len]);
            if gdi.eq_ignore_ascii_case(device) {
                return Some((path.sourceInfo.adapterId, path.sourceInfo.id));
            }
        }
        None
    }

    fn get_source_scale(adapter: LUID, id: u32) -> Option<SourceDpiScaleGet> {
        let mut req = SourceDpiScaleGet {
            header: header(
                GET_SOURCE_DPI_SCALE,
                std::mem::size_of::<SourceDpiScaleGet>(),
                adapter,
                id,
            ),
            min_scale_rel: 0,
            cur_scale_rel: 0,
            max_scale_rel: 0,
        };
        match unsafe { DisplayConfigGetDeviceInfo(&mut req.header) } {
            0 => Some(req),
            _ => None,
        }
    }

    fn recommended_index(min_scale_rel: i32) -> Option<i32> {
        let idx = -min_scale_rel;
        (0..DPI_VALUES.len() as i32).contains(&idx).then_some(idx)
    }

    /// Returns (current percent, recommended percent) for an active display.
    pub fn get(device: &str) -> Option<(u32, u32)> {
        let (adapter, id) = find_source(device)?;
        let info = get_source_scale(adapter, id)?;
        let rec = recommended_index(info.min_scale_rel)?;
        let cur = rec + info.cur_scale_rel;
        Some((*DPI_VALUES.get(cur as usize)?, DPI_VALUES[rec as usize]))
    }
}

#[cfg(not(windows))]
mod dpi_scale {
    pub fn get(_device: &str) -> Option<(u32, u32)> {
        None
    }
}

lazy_static::lazy_static! {
    /// GDI name of the virtual display currently used by privacy mode.
    static ref PRIVACY_DISPLAY: Mutex<Option<String>> = Mutex::new(None);
}

/// Called once privacy mode committed its display layout. Scaling is left to
/// Windows Settings (the user adjusts it there during the session); we only
/// record the device and log the current scale for diagnostics.
pub fn on_privacy_display_ready(device: &str) {
    let device = device.trim_end_matches('\0');
    *PRIVACY_DISPLAY.lock().unwrap() = Some(device.to_owned());
    let mut info = None;
    for _ in 0..10 {
        if let Some(v) = dpi_scale::get(device) {
            info = Some(v);
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(200));
    }
    match info {
        Some((cur, recommended)) => hbb_common::log::info!(
            "Virtual display {device} ready, DPI {cur}% (recommended {recommended}%); left to Windows Settings"
        ),
        None => hbb_common::log::warn!("Virtual display {device} not found; DPI scale not queried"),
    }
}

pub fn on_privacy_display_gone() {
    *PRIVACY_DISPLAY.lock().unwrap() = None;
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
/// `tx` is the calling connection's outbound channel, used to report the
/// auto-unlock outcome back to that client over the reverse chat channel.
pub fn handle_command(
    key: &str,
    on: bool,
    tx: Option<crate::server::Sender>,
) -> bool {
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
            if let Some(encoded) = key.strip_prefix("unlock:") {
                match crate::common::decode64(encoded)
                    .ok()
                    .and_then(|bytes| String::from_utf8(bytes).ok())
                {
                    Some(password) => crate::auto_unlock::request_unlock(password, tx),
                    None => hbb_common::log::warn!("Auto unlock: invalid payload"),
                }
                return true;
            }
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
            false
        }
    }
}
