//! Closed-loop lock-screen unlock driven by the mobile client through the
//! privacy-mode command channel (`uu:unlock:<base64 password>`).
//!
//! The client can only type blind: it does not know whether the peer is locked,
//! whether the injection landed, or whether the desktop was ready. This module
//! keeps that decision on the host, where the lock screen can be detected and
//! the result verified.

#[cfg(windows)]
use hbb_common::log;

#[cfg(windows)]
use std::{
    sync::atomic::{AtomicBool, Ordering},
    time::{Duration, Instant},
};

#[cfg(windows)]
static RUNNING: AtomicBool = AtomicBool::new(false);

#[cfg(windows)]
pub fn request_unlock(password: String) {
    if password.is_empty() {
        return;
    }
    if RUNNING.swap(true, Ordering::SeqCst) {
        log::info!("Auto unlock: already running");
        return;
    }
    std::thread::spawn(move || {
        let outcome = run(&password);
        log::info!("Auto unlock: {outcome}");
        RUNNING.store(false, Ordering::SeqCst);
    });
}

#[cfg(not(windows))]
pub fn request_unlock(_password: String) {}

#[cfg(windows)]
fn run(password: &str) -> String {
    use crate::platform::windows;

    const ATTEMPTS: u32 = 3;
    const UNLOCK_WAIT: Duration = Duration::from_secs(4);

    if !windows::is_lock_screen_active() {
        return "skipped, not at the lock screen".into();
    }
    let mut units: Vec<u16> = password.encode_utf16().collect();
    let mut success: Option<String> = None;
    for attempt in 1..=ATTEMPTS {
        if !windows::ensure_input_desktop() {
            log::warn!("Auto unlock: attempt {attempt}, cannot select the input desktop");
            std::thread::sleep(Duration::from_millis(300));
            continue;
        }
        // Give Winlogon a moment to settle after the desktop switch.
        std::thread::sleep(Duration::from_millis(200));
        if !windows::is_lock_screen_active() {
            success = Some(format!("done on attempt {attempt}, already unlocked"));
            break;
        }
        if attempt > 1 {
            // A failed attempt may have left a partial password in the field.
            windows::inject_backspaces(units.len() + 16);
            std::thread::sleep(Duration::from_millis(200));
        }
        let sent = windows::inject_unicode_text(&units);
        windows::inject_enter();
        log::info!(
            "Auto unlock: attempt {attempt}, injected {sent}/{} characters",
            units.len()
        );
        let start = Instant::now();
        while start.elapsed() < UNLOCK_WAIT {
            std::thread::sleep(Duration::from_millis(120));
            if !windows::is_lock_screen_active() {
                success = Some(format!(
                    "success on attempt {attempt} after {} ms",
                    start.elapsed().as_millis()
                ));
                break;
            }
        }
        if success.is_some() {
            break;
        }
        log::warn!("Auto unlock: attempt {attempt} did not leave the lock screen");
    }
    units.fill(0);
    success.unwrap_or_else(|| format!("failed after {ATTEMPTS} attempts"))
}