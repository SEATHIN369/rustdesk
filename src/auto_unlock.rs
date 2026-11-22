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
pub fn request_unlock(password: String, tx: Option<crate::server::Sender>) {
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
        let status = if outcome.starts_with("success") || outcome.starts_with("done") {
            "success"
        } else if outcome.starts_with("skipped") {
            "skipped"
        } else {
            "failed"
        };
        report_status(&tx, status);
        RUNNING.store(false, Ordering::SeqCst);
    });
}

/// Push `uu:unlock-state:<status>` back over the originating connection's chat
/// channel. The connection may already be gone (client disconnected mid-unlock),
/// in which case the send fails; that is expected, so the error is ignored.
#[cfg(windows)]
fn report_status(tx: &Option<crate::server::Sender>, status: &str) {
    use base::message_proto::{ChatMessage, Message, Misc};
    use hbb_common::tokio::time::Instant;
    use std::sync::Arc;

    let Some(tx) = tx else { return };
    let mut misc = Misc::new();
    misc.set_chat_message(ChatMessage {
        text: format!("uu:unlock-state:{status}"),
        ..Default::default()
    });
    let mut msg_out = Message::new();
    msg_out.set_misc(misc);
    // The connection can drop while we type; tolerate the send error.
    let _ = tx.send((Instant::now(), Arc::new(msg_out)));
}

#[cfg(not(windows))]
pub fn request_unlock(_password: String, _tx: Option<crate::server::Sender>) {}

#[cfg(windows)]
fn run(password: &str) -> String {
    use crate::platform::windows;

    const ATTEMPTS: u32 = 3;
    // Leaving Winlogon after a correct password takes ~120 ms, but slow
    // transitions have taken up to ~1.9 s, so keep the 2 s ceiling.
    const UNLOCK_WAIT: Duration = Duration::from_secs(2);
    // The client asks right after the first frame; the lock can land a moment
    // later (or Winlogon can still be settling), so poll before giving up.
    const LOCK_DETECT_WAIT: Duration = Duration::from_secs(12);

    let mut state = windows::lock_screen_state();
    let deadline = Instant::now() + LOCK_DETECT_WAIT;
    while state.0 != 2 && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(250));
        state = windows::lock_screen_state();
    }
    if state.0 != 2 {
        return format!("skipped, state {} desktop {:?}", state.0, state.1);
    }
    log::info!("Auto unlock: lock screen detected, desktop {:?}", state.1);
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
            std::thread::sleep(Duration::from_millis(150));
        } else {
            // The lock screen swallows the first keystroke while dismissing
            // its overlay; give it longer than one animation frame before
            // typing, otherwise the whole attempt is lost.
            windows::inject_wake_tap();
            std::thread::sleep(Duration::from_millis(450));
        }
        let sent = windows::inject_unicode_text(&units);
        windows::inject_enter();
        log::info!(
            "Auto unlock: attempt {attempt}, injected {sent}/{} characters",
            units.len()
        );
        let start = Instant::now();
        let mut second_enter = false;
        while start.elapsed() < UNLOCK_WAIT {
            std::thread::sleep(Duration::from_millis(60));
            if !windows::is_lock_screen_active() {
                success = Some(format!(
                    "success on attempt {attempt} after {} ms",
                    start.elapsed().as_millis()
                ));
                break;
            }
            // The overlay can eat the first Enter while the password text
            // landed; submit again before declaring the attempt lost.
            if attempt == 1 && !second_enter && start.elapsed().as_millis() >= 600 {
                second_enter = true;
                windows::inject_enter();
                log::info!(
                    "Auto unlock: attempt 1 second Enter at {} ms",
                    start.elapsed().as_millis()
                );
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