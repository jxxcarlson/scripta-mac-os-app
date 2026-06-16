use notify::{RecommendedWatcher, RecursiveMode, Watcher};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use tauri::Emitter;
use tauri::Manager;
use walkdir::WalkDir;

#[derive(Default)]
pub struct WatcherState(pub Mutex<Option<RecommendedWatcher>>);

#[derive(Clone, Serialize)]
struct FileChanged {
    path: String,
    mtime: u64,
}

#[tauri::command]
pub fn watch_workspace(
    app: tauri::AppHandle,
    state: tauri::State<'_, WatcherState>,
    root: String,
) -> Result<(), String> {
    let root_path = PathBuf::from(&root);
    let app_handle = app.clone();
    let root_for_cb = root_path.clone();

    let mut watcher = notify::recommended_watcher(move |res: notify::Result<notify::Event>| {
        if let Ok(event) = res {
            for p in event.paths {
                if !has_doc_ext(&p) {
                    continue;
                }
                if let Ok(rel) = p.strip_prefix(&root_for_cb) {
                    let payload = FileChanged {
                        path: rel.to_string_lossy().replace('\\', "/"),
                        mtime: mtime_ms(&p),
                    };
                    let _ = app_handle.emit("file-changed", payload);
                }
            }
        }
    })
    .map_err(|e| e.to_string())?;

    watcher
        .watch(&root_path, RecursiveMode::Recursive)
        .map_err(|e| e.to_string())?;

    *state.0.lock().map_err(|e| e.to_string())? = Some(watcher);
    Ok(())
}

/// One entry in the workspace tree, as sent to Elm.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Entry {
    /// Path relative to the workspace root, using '/' separators. This is the node id.
    pub path: String,
    pub name: String,
    pub is_dir: bool,
    /// Modification time in milliseconds since epoch (0 for dirs).
    pub mtime: u64,
}

const EXTS: [&str; 3] = ["scripta", "tex", "md"];

fn has_doc_ext(p: &Path) -> bool {
    p.extension()
        .and_then(|e| e.to_str())
        .map(|e| EXTS.contains(&e.to_lowercase().as_str()))
        .unwrap_or(false)
}

/// List every directory and every document file (extension scripta/tex/md)
/// under `root`, returning entries with workspace-relative, '/'-separated paths.
/// Entries are sorted by path. Non-UTF-8 paths are skipped.
pub fn list_workspace_impl(root: &Path) -> Result<Vec<Entry>, String> {
    let mut out = Vec::new();
    for dent in WalkDir::new(root).into_iter().filter_map(|e| e.ok()) {
        let p = dent.path();
        if p == root {
            continue;
        }
        let is_dir = dent.file_type().is_dir();
        if !is_dir && !has_doc_ext(p) {
            continue;
        }
        let rel = match p.strip_prefix(root).ok().and_then(|r| r.to_str()) {
            Some(s) => s.replace('\\', "/"),
            None => continue,
        };
        let name = match dent.file_name().to_str() {
            Some(s) => s.to_string(),
            None => continue,
        };
        let mtime = if is_dir { 0 } else { mtime_ms(p) };
        out.push(Entry {
            path: rel,
            name,
            is_dir,
            mtime,
        });
    }
    out.sort_by(|a, b| a.path.cmp(&b.path));
    Ok(out)
}

fn mtime_ms(p: &Path) -> u64 {
    std::fs::metadata(p)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

#[tauri::command]
pub fn list_workspace(root: String) -> Result<Vec<Entry>, String> {
    list_workspace_impl(Path::new(&root))
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileContent {
    pub content: String,
    pub mtime: u64,
}

pub fn read_file_impl(root: &Path, rel: &str) -> Result<FileContent, String> {
    let abs = root.join(rel);
    let content = std::fs::read_to_string(&abs).map_err(|e| e.to_string())?;
    Ok(FileContent { content, mtime: mtime_ms(&abs) })
}

#[tauri::command]
pub fn read_file(root: String, path: String) -> Result<FileContent, String> {
    read_file_impl(Path::new(&root), &path)
}

pub fn write_file_impl(root: &Path, rel: &str, content: &str) -> Result<u64, String> {
    let abs = root.join(rel);
    if let Some(parent) = abs.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    std::fs::write(&abs, content).map_err(|e| e.to_string())?;
    Ok(mtime_ms(&abs))
}

#[tauri::command]
pub fn write_file(root: String, path: String, content: String) -> Result<u64, String> {
    write_file_impl(Path::new(&root), &path, &content)
}

pub fn create_dir_impl(root: &Path, rel: &str) -> Result<(), String> {
    std::fs::create_dir_all(root.join(rel)).map_err(|e| e.to_string())
}

pub fn create_file_impl(root: &Path, rel: &str, content: &str) -> Result<u64, String> {
    let abs = root.join(rel);
    if abs.exists() {
        return Err(format!("{} already exists", rel));
    }
    write_file_impl(root, rel, content)
}

pub fn rename_impl(root: &Path, rel: &str, new_rel: &str) -> Result<(), String> {
    let to = root.join(new_rel);
    if let Some(parent) = to.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    std::fs::rename(root.join(rel), to).map_err(|e| e.to_string())
}

pub fn delete_impl(root: &Path, rel: &str) -> Result<(), String> {
    trash::delete(root.join(rel)).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn create_dir(root: String, path: String) -> Result<(), String> {
    create_dir_impl(Path::new(&root), &path)
}

#[tauri::command]
pub fn create_file(root: String, path: String, content: String) -> Result<u64, String> {
    create_file_impl(Path::new(&root), &path, &content)
}

#[tauri::command]
pub fn rename(root: String, path: String, new_path: String) -> Result<(), String> {
    rename_impl(Path::new(&root), &path, &new_path)
}

#[tauri::command]
pub fn delete(root: String, path: String) -> Result<(), String> {
    delete_impl(Path::new(&root), &path)
}

/// Opens a native folder-picker dialog and returns the chosen path as a UTF-8 string,
/// or `None` if the user cancels.
///
/// API deviation from the task snippet: we use `blocking_pick_folder()` instead of the
/// callback + `std::sync::mpsc::channel` pattern. The blocking variant is purpose-built
/// for async Tauri commands (it must NOT run on the main thread, which is guaranteed
/// here because `#[tauri::command] async fn` is dispatched on the async runtime).
/// `FilePath` is converted to `String` via its `Display` impl (`p.display()` for the
/// `Path` variant, or the URL string for the `Url` variant).
#[tauri::command]
pub async fn pick_workspace(app: tauri::AppHandle) -> Result<Option<String>, String> {
    use tauri_plugin_dialog::DialogExt;
    let chosen = app.dialog().file().blocking_pick_folder();
    Ok(chosen.map(|p| p.to_string()))
}

/// Opens a native Save dialog pre-populated with `default_name`, writes `content` to the
/// chosen path, and returns the absolute path as a UTF-8 string, or `None` if the user
/// cancels.
///
/// Save-dialog API used: `app.dialog().file().set_file_name(&default_name).blocking_save_file()`
/// (from `tauri_plugin_dialog` v2, `DialogExt` trait).
///
/// Path conversion: `FilePath::into_path()` (returns `Result<PathBuf, tauri_plugin_fs::Error>`)
/// — this handles both the `FilePath::Path(PathBuf)` variant (returned on desktop/macOS)
/// and the `FilePath::Url(url::Url)` variant (mobile/content URIs) by calling
/// `url::Url::to_file_path` on the latter.
#[tauri::command]
pub async fn export_save(
    app: tauri::AppHandle,
    default_name: String,
    content: String,
) -> Result<Option<String>, String> {
    use tauri_plugin_dialog::DialogExt;
    let chosen = app
        .dialog()
        .file()
        .set_file_name(&default_name)
        .blocking_save_file();
    match chosen {
        Some(path) => {
            let pb = path
                .into_path()
                .map_err(|e| e.to_string())?;
            std::fs::write(&pb, content).map_err(|e| e.to_string())?;
            Ok(Some(pb.to_string_lossy().to_string()))
        }
        None => Ok(None),
    }
}

/// From a process's argv, return the first argument that is a document to open:
/// one that already exists OR has a recognized doc extension (scripta/tex/md).
/// The program name (argv[0]) and flags (starting with '-') are ignored.
pub fn launch_file_from_args(args: &[String]) -> Option<String> {
    args.iter()
        .skip(1)
        .find(|a| {
            if a.starts_with('-') {
                return false;
            }
            let p = Path::new(a);
            p.is_file() || has_doc_ext(p)
        })
        .cloned()
}

/// The file path requested at launch (from argv), pulled once by the frontend.
#[derive(Default)]
pub struct LaunchFile(pub Mutex<Option<String>>);

#[tauri::command]
pub fn take_launch_file(state: tauri::State<'_, LaunchFile>) -> Result<Option<String>, String> {
    let mut guard = state.0.lock().map_err(|e| e.to_string())?;
    Ok(guard.take())
}

/// Read the remembered last-vault path from `file`; None if absent or blank.
pub fn read_last_vault(file: &Path) -> Option<String> {
    match std::fs::read_to_string(file) {
        Ok(s) => {
            let t = s.trim();
            if t.is_empty() {
                None
            } else {
                Some(t.to_string())
            }
        }
        Err(_) => None,
    }
}

/// Persist `vault` to `file`, creating parent directories as needed.
pub fn write_last_vault(file: &Path, vault: &str) -> std::io::Result<()> {
    if let Some(parent) = file.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(file, vault)
}

fn last_vault_file(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let dir = app.path().app_config_dir().map_err(|e| e.to_string())?;
    Ok(dir.join("last_vault.txt"))
}

/// The remembered last-used vault path, if any.
#[tauri::command]
pub fn get_last_vault(app: tauri::AppHandle) -> Result<Option<String>, String> {
    Ok(read_last_vault(&last_vault_file(&app)?))
}

/// Remember `vault` as the last-used vault.
#[tauri::command]
pub fn set_last_vault(app: tauri::AppHandle, vault: String) -> Result<(), String> {
    write_last_vault(&last_vault_file(&app)?, &vault).map_err(|e| e.to_string())
}

/// A concise, human-readable error from a latexmk/pdflatex run for the UI banner:
/// the first LaTeX error line ("! ...") plus the following line, else a tail of the output.
pub fn latex_error_summary(output: &str) -> String {
    let lines: Vec<&str> = output.lines().collect();
    if let Some(i) = lines.iter().position(|l| l.starts_with("! ")) {
        let mut msg = lines[i].to_string();
        if let Some(next) = lines.get(i + 1) {
            if !next.trim().is_empty() {
                msg.push('\n');
                msg.push_str(next);
            }
        }
        msg
    } else {
        let mut tail: Vec<&str> = lines.iter().rev().take(8).cloned().collect();
        tail.reverse();
        tail.join("\n")
    }
}

/// PATH for invoking TeX tools, augmented with common install dirs so the engine
/// resolves even when the app is launched from Finder (minimal PATH).
fn tex_path_env() -> String {
    let extra = "/Library/TeX/texbin:/usr/local/bin:/opt/homebrew/bin";
    match std::env::var("PATH") {
        Ok(p) if !p.is_empty() => format!("{extra}:{p}"),
        _ => extra.to_string(),
    }
}

/// Compile the given LaTeX source to PDF with latexmk, then save via a dialog.
#[tauri::command]
pub async fn export_pdf(
    app: tauri::AppHandle,
    default_name: String,
    tex: String,
) -> Result<Option<String>, String> {
    use tauri_plugin_dialog::DialogExt;

    let dir = tempfile::tempdir().map_err(|e| e.to_string())?;
    let tex_path = dir.path().join("document.tex");
    std::fs::write(&tex_path, &tex).map_err(|e| e.to_string())?;

    // xelatex (not pdflatex): the Scripta LaTeX export can contain literal Unicode
    // (e.g. π), which pdflatex cannot typeset without inputenc setup; xelatex is a
    // Unicode engine and compiles the same preamble cleanly.
    let out = std::process::Command::new("latexmk")
        .args(["-xelatex", "-interaction=nonstopmode", "-halt-on-error", "document.tex"])
        .current_dir(dir.path())
        .env("PATH", tex_path_env())
        .output()
        .map_err(|e| format!("Could not run latexmk (is MacTeX installed?): {e}"))?;

    let pdf_path = dir.path().join("document.pdf");
    if !pdf_path.exists() {
        let combined = format!(
            "{}\n{}",
            String::from_utf8_lossy(&out.stdout),
            String::from_utf8_lossy(&out.stderr)
        );
        return Err(format!("PDF generation failed:\n{}", latex_error_summary(&combined)));
    }

    let chosen = app
        .dialog()
        .file()
        .set_file_name(&default_name)
        .blocking_save_file();
    match chosen {
        Some(path) => {
            let dest = path.into_path().map_err(|e| e.to_string())?;
            std::fs::copy(&pdf_path, &dest).map_err(|e| e.to_string())?;
            Ok(Some(dest.to_string_lossy().to_string()))
        }
        None => Ok(None),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn lists_only_doc_files_with_relative_paths() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        fs::create_dir(root.join("sub")).unwrap();
        fs::write(root.join("a.scripta"), "hello").unwrap();
        fs::write(root.join("sub/b.tex"), "x").unwrap();
        fs::write(root.join("ignore.png"), "x").unwrap();

        let entries = list_workspace_impl(root).unwrap();
        let paths: Vec<&str> = entries.iter().map(|e| e.path.as_str()).collect();

        assert!(paths.contains(&"a.scripta"));
        assert!(paths.contains(&"sub"));
        assert!(paths.contains(&"sub/b.tex"));
        assert!(!paths.iter().any(|p| p.contains("ignore.png")));

        let sub_entry = entries.iter().find(|e| e.path == "sub").unwrap();
        assert!(sub_entry.is_dir);
        assert_eq!(sub_entry.mtime, 0);

        let scripta_entry = entries.iter().find(|e| e.path == "a.scripta").unwrap();
        assert!(!scripta_entry.is_dir);
        assert!(scripta_entry.mtime > 0);
    }

    #[test]
    fn reads_file_content_and_mtime() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        fs::write(root.join("a.scripta"), "# Title\nbody").unwrap();

        let fc = read_file_impl(root, "a.scripta").unwrap();
        assert_eq!(fc.content, "# Title\nbody");
        assert!(fc.mtime > 0);
    }

    #[test]
    fn read_missing_file_errors() {
        let dir = tempdir().unwrap();
        assert!(read_file_impl(dir.path(), "nope.scripta").is_err());
    }

    #[test]
    fn writes_file_and_returns_new_mtime() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        let mt = write_file_impl(root, "a.scripta", "new content").unwrap();
        assert!(mt > 0);
        assert_eq!(fs::read_to_string(root.join("a.scripta")).unwrap(), "new content");
    }

    #[test]
    fn writes_file_creating_parent_dirs() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        write_file_impl(root, "nested/deep/a.scripta", "x").unwrap();
        assert!(root.join("nested/deep/a.scripta").exists());
    }

    #[test]
    fn creates_file_and_dir() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        create_dir_impl(root, "newdir").unwrap();
        create_file_impl(root, "newdir/x.scripta", "").unwrap();
        assert!(root.join("newdir/x.scripta").exists());
    }

    #[test]
    fn create_file_refuses_to_overwrite() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        create_file_impl(root, "a.scripta", "first").unwrap();
        assert!(create_file_impl(root, "a.scripta", "second").is_err());
    }

    #[test]
    fn renames_path() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        fs::write(root.join("a.scripta"), "x").unwrap();
        rename_impl(root, "a.scripta", "b.scripta").unwrap();
        assert!(!root.join("a.scripta").exists());
        assert!(root.join("b.scripta").exists());
    }

    #[test]
    fn delete_moves_to_trash_not_hard_delete() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        fs::write(root.join("a.scripta"), "x").unwrap();
        delete_impl(root, "a.scripta").unwrap();
        assert!(!root.join("a.scripta").exists());
    }

    #[test]
    fn launch_file_picks_existing_doc_path() {
        let dir = tempdir().unwrap();
        let f = dir.path().join("a.scripta");
        fs::write(&f, "x").unwrap();
        let prog = "/Applications/App.app/Contents/MacOS/app".to_string();
        let args = vec![prog, f.to_string_lossy().to_string()];
        assert_eq!(launch_file_from_args(&args), Some(f.to_string_lossy().to_string()));
    }

    #[test]
    fn launch_file_none_when_only_program() {
        let args = vec!["/path/to/app".to_string()];
        assert_eq!(launch_file_from_args(&args), None);
    }

    #[test]
    fn launch_file_ignores_flags_and_nondoc() {
        let args = vec![
            "/path/to/app".to_string(),
            "-psn_0_12345".to_string(),
            "notes.txt".to_string(),
        ];
        assert_eq!(launch_file_from_args(&args), None);
    }

    #[test]
    fn launch_file_accepts_doc_extension_even_if_missing() {
        let args = vec!["/path/to/app".to_string(), "/tmp/x/ghost.scripta".to_string()];
        assert_eq!(
            launch_file_from_args(&args),
            Some("/tmp/x/ghost.scripta".to_string())
        );
    }

    #[test]
    fn last_vault_round_trips_and_creates_parent() {
        let dir = tempdir().unwrap();
        let f = dir.path().join("sub/last_vault.txt");
        write_last_vault(&f, "/Users/me/My Vault").unwrap();
        assert_eq!(read_last_vault(&f), Some("/Users/me/My Vault".to_string()));
    }

    #[test]
    fn last_vault_missing_file_is_none() {
        let dir = tempdir().unwrap();
        assert_eq!(read_last_vault(&dir.path().join("nope.txt")), None);
    }

    #[test]
    fn last_vault_whitespace_only_is_none() {
        let dir = tempdir().unwrap();
        let f = dir.path().join("last_vault.txt");
        write_last_vault(&f, "   \n").unwrap();
        assert_eq!(read_last_vault(&f), None);
    }

    #[test]
    fn latex_error_summary_extracts_bang_line() {
        let log = "noise\n! Undefined control sequence.\nl.42 \\foo\ntrailing";
        assert_eq!(
            latex_error_summary(log),
            "! Undefined control sequence.\nl.42 \\foo"
        );
    }

    #[test]
    fn latex_error_summary_falls_back_to_tail() {
        let log = "alpha\nbeta\ngamma";
        let s = latex_error_summary(log);
        assert!(!s.is_empty());
        assert!(s.contains("gamma"));
    }
}
