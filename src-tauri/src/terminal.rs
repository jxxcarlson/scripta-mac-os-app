use base64::Engine;
use portable_pty::{native_pty_system, CommandBuilder, PtySize};
use std::collections::HashMap;
use std::io::{Read, Write};
use std::sync::Mutex;
use tauri::Emitter;

pub(crate) struct Session {
    writer: Box<dyn Write + Send>,
    master: Box<dyn portable_pty::MasterPty + Send>,
    child: Box<dyn portable_pty::Child + Send + Sync>,
}

#[derive(Default)]
pub struct TerminalState(pub Mutex<HashMap<String, Session>>);

fn resolve_cwd(cwd: &str) -> String {
    if cwd.is_empty() {
        std::env::var("HOME").unwrap_or_else(|_| "/".to_string())
    } else {
        cwd.to_string()
    }
}

/// Remove and kill the session with `id`, if it exists.
fn close_session(
    map: &mut HashMap<String, Session>,
    id: &str,
) {
    if let Some(mut s) = map.remove(id) {
        let _ = s.child.kill();
    }
}

#[tauri::command]
pub fn terminal_open(
    app: tauri::AppHandle,
    state: tauri::State<'_, TerminalState>,
    id: String,
    cwd: String,
    cols: u16,
    rows: u16,
    init_cmd: String,
) -> Result<(), String> {
    // Close any pre-existing session with the same id.
    {
        let mut map = state.0.lock().map_err(|e| e.to_string())?;
        close_session(&mut map, &id);
    }

    let pty = native_pty_system();
    let pair = pty
        .openpty(PtySize {
            rows,
            cols,
            pixel_width: 0,
            pixel_height: 0,
        })
        .map_err(|e| e.to_string())?;

    let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/zsh".to_string());
    let mut cmd = CommandBuilder::new(shell);
    // Tell the shell what terminal it's driving. A GUI app launched from Finder
    // inherits no TERM, and the pty would pass that emptiness through — so zsh's
    // line editor couldn't position the cursor and drew garbled input (typing
    // "a" came out "aabc", stale characters from the redraw). xterm.js emulates
    // xterm-256color, so advertise exactly that.
    cmd.env("TERM", "xterm-256color");
    cmd.env("COLORTERM", "truecolor");
    // Start a LOGIN shell (-l), as Terminal.app and VS Code do, so the macOS
    // login init runs (path_helper, ~/.zprofile, plugin managers, compinit).
    cmd.arg("-l");
    cmd.cwd(resolve_cwd(&cwd));

    let child = pair.slave.spawn_command(cmd).map_err(|e| e.to_string())?;
    let mut reader = pair.master.try_clone_reader().map_err(|e| e.to_string())?;
    let mut writer = pair.master.take_writer().map_err(|e| e.to_string())?;
    if !init_cmd.is_empty() {
        let line = format!("{}\n", init_cmd);
        writer.write_all(line.as_bytes()).map_err(|e| e.to_string())?;
        writer.flush().map_err(|e| e.to_string())?;
    }

    let app_for_thread = app.clone();
    let id_for_thread = id.clone();
    std::thread::spawn(move || {
        let mut buf = [0u8; 8192];
        loop {
            match reader.read(&mut buf) {
                Ok(0) | Err(_) => {
                    let _ = app_for_thread
                        .emit("terminal-exit", serde_json::json!({ "id": id_for_thread }));
                    break;
                }
                Ok(n) => {
                    let data =
                        base64::engine::general_purpose::STANDARD.encode(&buf[..n]);
                    let _ = app_for_thread.emit(
                        "terminal-output",
                        serde_json::json!({ "id": id_for_thread, "data": data }),
                    );
                }
            }
        }
    });

    state
        .0
        .lock()
        .map_err(|e| e.to_string())?
        .insert(id, Session { writer, master: pair.master, child });
    Ok(())
}

#[tauri::command]
pub fn terminal_input(
    state: tauri::State<'_, TerminalState>,
    id: String,
    data: String,
) -> Result<(), String> {
    if let Some(s) = state.0.lock().map_err(|e| e.to_string())?.get_mut(&id) {
        s.writer
            .write_all(data.as_bytes())
            .map_err(|e| e.to_string())?;
        s.writer.flush().map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
pub fn terminal_resize(
    state: tauri::State<'_, TerminalState>,
    id: String,
    cols: u16,
    rows: u16,
) -> Result<(), String> {
    if let Some(s) = state.0.lock().map_err(|e| e.to_string())?.get(&id) {
        s.master
            .resize(PtySize {
                rows,
                cols,
                pixel_width: 0,
                pixel_height: 0,
            })
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
pub fn terminal_close(
    state: tauri::State<'_, TerminalState>,
    id: String,
) -> Result<(), String> {
    let mut map = state.0.lock().map_err(|e| e.to_string())?;
    close_session(&mut map, &id);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::resolve_cwd;

    #[test]
    fn resolve_cwd_passes_through_and_falls_back() {
        // A non-empty cwd passes through unchanged.
        assert_eq!(resolve_cwd("/vault/x"), "/vault/x");
        // An empty cwd falls back to $HOME (non-empty on any real system).
        // Do NOT mutate the global HOME env var here: Rust runs tests in parallel
        // and a `set_var("HOME", …)` races with sibling tests (e.g. the Keychain
        // test, whose `security` calls resolve the login keychain via $HOME).
        assert_eq!(resolve_cwd(""), std::env::var("HOME").unwrap_or_else(|_| "/".to_string()));
        assert!(!resolve_cwd("").is_empty());
    }
}
