//! Host-side controls driven from the mobile client through the privacy-mode
//! message channel (`impl_key` values prefixed with `uu:`).
//!
//! The Android client reuses the official 1.5.3 librustdesk.so, which cannot
//! send any message this fork adds, so the only reachable channel with a free
//! string payload is `TogglePrivacyMode.impl_key`.

use hbb_common::config::Config;
use serde::{Deserialize, Serialize};
use std::sync::Mutex;

lazy_static::lazy_static! {
    static ref STATE: Mutex<State> = Mutex::new(State::load());
}

#[derive(Serialize, Deserialize, Default, Clone)]
pub struct State {
    #[serde(default)]
    pub mute: bool,
    #[serde(default)]
    pub restore_on_disconnect: bool,
    #[serde(default)]
    pub privacy_persist: bool,
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

fn path() -> std::path::PathBuf {
    Config::path("uu-host-state.json")
}

impl State {
    fn load() -> Self {
        std::fs::read_to_string(path())
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default()
    }

    fn save(&self) {
        let p = path();
        if let Some(dir) = p.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        match serde_json::to_string_pretty(self) {
            Ok(s) => {
                if let Err(e) = std::fs::write(&p, s) {
                    log::error!("Failed to save host control state: {e}");
                }
            }
            Err(e) => log::error!("Failed to encode host control state: {e}"),
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

/// Applies the persisted mute state when the host server starts.
pub fn init() {
    let (mute, width, height) = {
        let s = STATE.lock().unwrap();
        (s.mute, s.display_width, s.display_height)
    };
    crate::privacy_mode::set_virtual_display_mode(width, height);
    if mute {
        if let Err(e) = set_system_mute(true) {
            log::error!("Failed to re-apply host mute: {e}");
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
            log::error!("Failed to set host mute {mute}: {e}");
        } else {
            log::info!("Host mute set to {mute}");
        }
    });
}

pub fn set_restore_on_disconnect(restore: bool) {
    with_state(|s| s.restore_on_disconnect = restore);
    log::info!("Host mute restore-on-disconnect set to {restore}");
}

pub fn set_privacy_persist(persist: bool) {
    with_state(|s| s.privacy_persist = persist);
    log::info!("Host privacy persist set to {persist}");
}

pub fn privacy_persist() -> bool {
    STATE.lock().unwrap().privacy_persist
}

/// Called when the last remote connection goes away.
pub fn on_all_connections_closed() {
    let (restore, mute) = {
        let s = STATE.lock().unwrap();
        (s.restore_on_disconnect, s.mute)
    };
    if restore && mute {
        let prev = with_state(|s| {
            let prev = s.prev_mute.take();
            s.mute = prev.unwrap_or(false);
            prev
        });
        let target = prev.unwrap_or(false);
        if let Err(e) = set_system_mute(target) {
            log::error!("Failed to restore host mute {target}: {e}");
        } else {
            log::info!("Host mute restored to {target} after session end");
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
        "restore" => {
            set_restore_on_disconnect(on);
            true
        }
        "privacy-persist" => {
            set_privacy_persist(on);
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
            false
        }
    }
}
