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
                if !is_text_ext(&p) && !is_image_ext(&p) {
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

/// Whether a path has a recognized text-document extension. Classification is
/// by EXTENSION ONLY — we must never open a file during a directory walk, because
/// the vault lives on iCloud Drive where reading a dataless file forces a
/// synchronous on-demand download (reading every file would hang the app).
fn is_text_ext(p: &Path) -> bool {
    const TEXT_EXTS: &[&str] = &[
        "scripta", "tex", "md", "markdown", "txt", "text", "csv", "tsv", "json",
        "yaml", "yml", "toml", "ini", "cfg", "conf", "xml", "html", "htm", "css",
        "js", "ts", "elm", "rs", "py", "sh", "bash", "rb", "go", "c", "h", "sql",
        "log", "org", "rst",
    ];
    p.extension()
        .and_then(|e| e.to_str())
        .map(|e| TEXT_EXTS.contains(&e.to_lowercase().as_str()))
        .unwrap_or(false)
}

fn is_image_ext(p: &Path) -> bool {
    const IMG: [&str; 5] = ["jpg", "jpeg", "png", "gif", "webp"];
    p.extension()
        .and_then(|e| e.to_str())
        .map(|e| IMG.contains(&e.to_lowercase().as_str()))
        .unwrap_or(false)
}

fn is_hidden(entry: &walkdir::DirEntry) -> bool {
    entry
        .file_name()
        .to_str()
        .map(|s| s.starts_with('.'))
        .unwrap_or(false)
}

/// List every directory and every text or image file
/// under `root`, returning entries with workspace-relative, '/'-separated paths.
/// Entries are sorted by path. Non-UTF-8 paths and dotfiles/dot-directories are skipped.
pub fn list_workspace_impl(root: &Path) -> Result<Vec<Entry>, String> {
    let mut out = Vec::new();
    for dent in WalkDir::new(root)
        .into_iter()
        .filter_entry(|e| e.depth() == 0 || !is_hidden(e))
        .filter_map(|e| e.ok())
    {
        let p = dent.path();
        if p == root {
            continue;
        }
        let is_dir = dent.file_type().is_dir();
        if !is_dir && !(is_text_ext(p) || is_image_ext(p)) {
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

fn image_mime(p: &Path) -> &'static str {
    match p
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_lowercase())
        .as_deref()
    {
        Some("png") => "image/png",
        Some("jpg") | Some("jpeg") => "image/jpeg",
        Some("gif") => "image/gif",
        Some("webp") => "image/webp",
        _ => "application/octet-stream",
    }
}

pub fn read_image_impl(root: &Path, rel: &str) -> Result<String, String> {
    use base64::Engine;
    let abs = root.join(rel);
    let bytes = std::fs::read(&abs).map_err(|e| e.to_string())?;
    let b64 = base64::engine::general_purpose::STANDARD.encode(&bytes);
    Ok(format!("data:{};base64,{}", image_mime(&abs), b64))
}

#[tauri::command]
pub fn read_image(root: String, path: String) -> Result<String, String> {
    read_image_impl(Path::new(&root), &path)
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

/// Clean a Markdown link target: trim, strip surrounding `<…>`, and percent-decode.
pub fn clean_target(target: &str) -> String {
    let t = target.trim();
    let t = if t.len() >= 2 && t.starts_with('<') && t.ends_with('>') {
        &t[1..t.len() - 1]
    } else {
        t
    };
    percent_encoding::percent_decode_str(t)
        .decode_utf8_lossy()
        .into_owned()
}

/// Resolve a relative link `target` (from document `doc_rel`) to the vault-relative
/// path of the document to open. Folders resolve to their `_index.md`. Confined to
/// `root`. Errors if missing / not a file / escaping the vault.
pub fn resolve_doc_link_impl(root: &Path, doc_rel: &str, target: &str) -> Result<String, String> {
    let t = clean_target(target);
    let doc_abs = root.join(doc_rel);
    let base = doc_abs
        .parent()
        .ok_or_else(|| "document has no parent directory".to_string())?;
    let mut canon = base
        .join(&t)
        .canonicalize()
        .map_err(|e| format!("cannot resolve link target: {}", e))?;
    if canon.is_dir() {
        canon = canon
            .join("_index.md")
            .canonicalize()
            .map_err(|e| format!("folder has no _index.md: {}", e))?;
    }
    let root_canon = root.canonicalize().map_err(|e| e.to_string())?;
    if !canon.starts_with(&root_canon) {
        return Err("link target is outside the vault".to_string());
    }
    if !canon.is_file() {
        return Err("link target is not a file".to_string());
    }
    let rel = canon.strip_prefix(&root_canon).map_err(|e| e.to_string())?;
    Ok(rel.to_string_lossy().replace('\\', "/"))
}

#[tauri::command]
pub fn resolve_doc_link(root: String, doc: String, target: String) -> Result<String, String> {
    resolve_doc_link_impl(Path::new(&root), &doc, &target)
}

/// Resolve a markdown link `target` relative to the directory of the document
/// `doc_rel` (vault-relative), confined to `root`. Canonicalization requires the
/// target to exist; a target escaping the vault is rejected.
pub fn resolve_link_target(root: &Path, doc_rel: &str, target: &str) -> Result<PathBuf, String> {
    let doc_abs = root.join(doc_rel);
    let base = doc_abs
        .parent()
        .ok_or_else(|| "document has no parent directory".to_string())?;
    let canon = base
        .join(clean_target(target))
        .canonicalize()
        .map_err(|e| format!("cannot resolve link target: {}", e))?;
    let root_canon = root.canonicalize().map_err(|e| e.to_string())?;
    if !canon.starts_with(&root_canon) {
        return Err("link target is outside the vault".to_string());
    }
    Ok(canon)
}

/// Only http/https/mailto URLs may be opened externally.
pub fn validate_external_url(url: &str) -> Result<(), String> {
    if url.starts_with("http://") || url.starts_with("https://") || url.starts_with("mailto:") {
        Ok(())
    } else {
        Err(format!("refusing to open non-web URL: {}", url))
    }
}

#[tauri::command]
pub fn open_path(root: String, doc: String, target: String) -> Result<(), String> {
    let abs = resolve_link_target(Path::new(&root), &doc, &target)?;
    std::process::Command::new("open")
        .arg(&abs)
        .spawn()
        .map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
pub fn open_url(url: String) -> Result<(), String> {
    validate_external_url(&url)?;
    std::process::Command::new("open")
        .arg(&url)
        .spawn()
        .map_err(|e| e.to_string())?;
    Ok(())
}

/// From a process's argv, return the first argument that is a document to open:
/// one that already exists OR has a recognized doc extension (scripta/tex/md).
/// The program name (argv[0]) and flags (starting with '-') are ignored.
pub fn launch_file_from_args(args: &[String]) -> Option<String> {
    const DOC_EXTS: [&str; 3] = ["scripta", "tex", "md"];
    fn has_doc_ext_local(p: &Path) -> bool {
        p.extension()
            .and_then(|e| e.to_str())
            .map(|e| DOC_EXTS.contains(&e.to_lowercase().as_str()))
            .unwrap_or(false)
    }
    args.iter()
        .skip(1)
        .find(|a| {
            if a.starts_with('-') {
                return false;
            }
            let p = Path::new(a);
            p.is_file() || has_doc_ext_local(p)
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

const AI_KEYCHAIN_SERVICE: &str = "MacScriptaViewer-AI";

/// Store (or update) `key` for `account` under `service` in the login Keychain.
pub fn set_api_key_impl(service: &str, account: &str, key: &str) -> Result<(), String> {
    let out = std::process::Command::new("security")
        .args(["add-generic-password", "-U", "-s", service, "-a", account, "-w", key])
        .output()
        .map_err(|e| e.to_string())?;
    if out.status.success() {
        Ok(())
    } else {
        Err(String::from_utf8_lossy(&out.stderr).trim().to_string())
    }
}

/// Read the key for `account`. Errors if not found.
pub fn read_api_key_impl(service: &str, account: &str) -> Result<String, String> {
    let out = std::process::Command::new("security")
        .args(["find-generic-password", "-s", service, "-a", account, "-w"])
        .output()
        .map_err(|e| e.to_string())?;
    if out.status.success() {
        Ok(String::from_utf8_lossy(&out.stdout).trim_end_matches('\n').to_string())
    } else {
        Err(String::from_utf8_lossy(&out.stderr).trim().to_string())
    }
}

/// Delete the key for `account`. Treats "not found" as success.
pub fn delete_api_key_impl(service: &str, account: &str) -> Result<(), String> {
    let out = std::process::Command::new("security")
        .args(["delete-generic-password", "-s", service, "-a", account])
        .output()
        .map_err(|e| e.to_string())?;
    if out.status.success() {
        return Ok(());
    }
    let stderr = String::from_utf8_lossy(&out.stderr);
    if stderr.contains("could not be found") {
        Ok(())
    } else {
        Err(stderr.trim().to_string())
    }
}

#[tauri::command]
pub fn set_api_key(provider: String, key: String) -> Result<(), String> {
    set_api_key_impl(AI_KEYCHAIN_SERVICE, &provider, &key)
}

#[tauri::command]
pub fn delete_api_key(provider: String) -> Result<(), String> {
    delete_api_key_impl(AI_KEYCHAIN_SERVICE, &provider)
}

/// Read the stored API key for `provider` from the AI Keychain service.
pub fn read_provider_key(provider: &str) -> Result<String, String> {
    read_api_key_impl(AI_KEYCHAIN_SERVICE, provider)
}

/// A concise, human-readable error from a latexmk/pdflatex run for the UI banner:
/// the first LaTeX error line ("! ...") through the source-location line
/// ("l.<n> ...") and the line after it (which shows where on that line the engine
/// choked), so the user can see the offending source. Falls back to a tail of the
/// output when there is no "! " error line.
pub fn latex_error_summary(output: &str) -> String {
    let lines: Vec<&str> = output.lines().collect();
    match lines.iter().position(|l| l.starts_with("! ")) {
        Some(start) => {
            let mut collected: Vec<&str> = Vec::new();
            let mut just_saw_location = false;
            for line in &lines[start..] {
                collected.push(line);
                if just_saw_location {
                    break; // include one line after "l.<n> ..." then stop
                }
                let is_location = line.starts_with("l.")
                    && line[2..].chars().next().is_some_and(|c| c.is_ascii_digit());
                if is_location {
                    just_saw_location = true;
                } else if collected.len() >= 8 {
                    break; // cap when no location line is found
                }
            }
            collected.join("\n").trim_end().to_string()
        }
        None => {
            let mut tail: Vec<&str> = lines.iter().rev().take(8).cloned().collect();
            tail.reverse();
            tail.join("\n")
        }
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
        let log = std::fs::read_to_string(dir.path().join("document.log")).unwrap_or_default();
        let errors = latex_errors(&log, &tex);
        return Err(if errors.is_empty() {
            let combined = format!(
                "{}\n{}",
                String::from_utf8_lossy(&out.stdout),
                String::from_utf8_lossy(&out.stderr)
            );
            format!("PDF generation failed:\n{}", latex_error_summary(&combined))
        } else {
            format_error_report(&errors)
        });
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

/// A single LaTeX error, mapped back to the Scripta source where possible.
#[derive(Debug, PartialEq)]
pub struct LatexError {
    pub source_line: Option<u32>, // Scripta source line (via %%% Line marker)
    pub latex_line: Option<u32>,  // .tex input line (from "l.<n>")
    pub message: String,          // e.g. "Missing $ inserted."
    pub snippet: String,          // offending LaTeX text at the error point
}

/// Scripta source line for `.tex` input line `n` (1-based): the last `%%% Line K`
/// marker at or before line `n`.
fn source_line_for(tex_lines: &[&str], n: u32) -> Option<u32> {
    let upto = (n as usize).min(tex_lines.len());
    tex_lines[..upto]
        .iter()
        .rev()
        .find_map(|l| l.strip_prefix("%%% Line ").and_then(|s| s.trim().parse::<u32>().ok()))
}

/// Parse a latexmk/xelatex log + the `.tex` source into structured errors. Each
/// `! …` line starts an error; the following `l.<n> …` line gives the `.tex`
/// line and the offending snippet; `%%% Line` markers map it to the source line.
pub fn latex_errors(log: &str, tex: &str) -> Vec<LatexError> {
    let tex_lines: Vec<&str> = tex.lines().collect();
    let log_lines: Vec<&str> = log.lines().collect();
    let mut errors = Vec::new();
    let mut i = 0;
    while i < log_lines.len() {
        if let Some(msg) = log_lines[i].strip_prefix("! ") {
            let message = msg.trim().to_string();
            let mut latex_line = None;
            let mut snippet = String::new();
            let mut j = i + 1;
            while j < log_lines.len() && j < i + 12 {
                if log_lines[j].starts_with("! ") {
                    break; // next error begins; stop looking for this one's location
                }
                if let Some(rest) = log_lines[j].strip_prefix("l.") {
                    let digits: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
                    if let Ok(n) = digits.parse::<u32>() {
                        latex_line = Some(n);
                        snippet = rest[digits.len()..].trim().to_string();
                        break;
                    }
                }
                j += 1;
            }
            let source_line = latex_line.and_then(|n| source_line_for(&tex_lines, n));
            errors.push(LatexError { source_line, latex_line, message, snippet });
            // Advance past the location line if found; otherwise only past the error line,
            // so a following "! " error in the window isn't skipped.
            i = if latex_line.is_some() { j + 1 } else { i + 1 };
        } else {
            i += 1;
        }
    }
    errors
}

/// Human-readable report for the in-app panel; "" when there are no errors.
pub fn format_error_report(errors: &[LatexError]) -> String {
    if errors.is_empty() {
        return String::new();
    }
    let n = errors.len();
    let mut report = format!(
        "PDF generation failed — {} error{}:\n",
        n,
        if n == 1 { "" } else { "s" }
    );
    for e in errors {
        let loc = match (e.source_line, e.latex_line) {
            (Some(s), _) => format!("Source line {}", s),
            (None, Some(l)) => format!("LaTeX line {}", l),
            (None, None) => "Error".to_string(),
        };
        report.push_str(&format!("\n• {}: {}", loc, e.message));
        if !e.snippet.is_empty() {
            report.push_str(&format!("\n    {}", e.snippet));
        }
    }
    report
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn lists_text_image_and_dir_files_with_relative_paths() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        fs::create_dir(root.join("sub")).unwrap();
        fs::write(root.join("a.scripta"), "hello").unwrap();
        fs::write(root.join("sub/b.tex"), "x").unwrap();
        // Classification is by extension only (never reads content), so a file with
        // an image extension is listed regardless of its bytes.
        fs::write(root.join("corrupt.png"), [0u8, 1, 2, 3]).unwrap();

        let entries = list_workspace_impl(root).unwrap();
        let paths: Vec<&str> = entries.iter().map(|e| e.path.as_str()).collect();

        assert!(paths.contains(&"a.scripta"));
        assert!(paths.contains(&"sub"));
        assert!(paths.contains(&"sub/b.tex"));
        // corrupt.png is listed by its image extension (content is never inspected).
        assert!(paths.iter().any(|p| p.contains("corrupt.png")));

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
    fn latex_error_summary_includes_location_and_following_line() {
        let log = "preamble noise\n! Missing $ inserted.\n<inserted text> \n                $\nl.247 This is \\pi\n               trailing source\nmore log after";
        let s = latex_error_summary(log);
        assert!(s.starts_with("! Missing $ inserted."));
        assert!(s.contains("l.247 This is \\pi"));
        assert!(s.contains("trailing source"));
        assert!(!s.contains("more log after"));
    }

    #[test]
    fn latex_error_summary_without_location_keeps_bang_line() {
        let log = "x\n! Some error.\ndetail one\ndetail two";
        let s = latex_error_summary(log);
        assert!(s.starts_with("! Some error."));
        assert!(s.contains("detail one"));
    }

    #[test]
    fn latex_error_summary_falls_back_to_tail() {
        let log = "alpha\nbeta\ngamma";
        let s = latex_error_summary(log);
        assert!(!s.is_empty());
        assert!(s.contains("gamma"));
    }

    #[test]
    fn latex_errors_maps_to_source_line() {
        let tex = "preamble\n%%% Line 5\n\\section{X}\nbody\nmore\nmore\n$s^2$\n";
        let log = "junk\n! Missing $ inserted.\n<inserted text>\nl.7 $s^2 = 2GM/c\n           more\n";
        let errs = latex_errors(log, tex);
        assert_eq!(errs.len(), 1);
        assert_eq!(errs[0].source_line, Some(5));
        assert_eq!(errs[0].latex_line, Some(7));
        assert!(errs[0].message.contains("Missing $ inserted"));
        assert!(errs[0].snippet.contains("s^2"));
    }

    #[test]
    fn latex_errors_two_errors_map_to_nearest_marker() {
        let tex = "%%% Line 1\na\n%%% Line 9\nb\n";
        let log = "! First bad.\nl.2 a\n! Second bad.\nl.4 b\n";
        let errs = latex_errors(log, tex);
        assert_eq!(errs.len(), 2);
        assert_eq!(errs[0].source_line, Some(1));
        assert_eq!(errs[1].source_line, Some(9));
    }

    #[test]
    fn latex_errors_no_marker_gives_none() {
        let errs = latex_errors("! Bad.\nl.2 b\n", "a\nb\nc\n");
        assert_eq!(errs[0].source_line, None);
        assert_eq!(errs[0].latex_line, Some(2));
    }

    #[test]
    fn latex_errors_ignores_boilerplate() {
        let log = "LaTeX Font Info: blah\n(/usr/local/texlive/x.sty)\nOverfull \\hbox\n";
        assert!(latex_errors(log, "x\n").is_empty());
    }

    #[test]
    fn latex_errors_first_without_location_does_not_swallow_next() {
        // First "! " has no l.<n>; the second error must still be parsed correctly.
        let log = "! First with no location.\n(noise)\n(noise)\n! Second bad.\nl.3 x\n";
        let tex = "a\nb\n%%% Line 4\nx\n";
        let errs = latex_errors(log, tex);
        assert_eq!(errs.len(), 2);
        assert_eq!(errs[1].latex_line, Some(3));
        assert_eq!(errs[1].source_line, Some(4));
    }

    #[test]
    fn format_error_report_empty_is_blank() {
        assert_eq!(format_error_report(&[]), "");
    }

    #[test]
    fn format_error_report_renders_source_line_and_snippet() {
        let errs = vec![LatexError {
            source_line: Some(17),
            latex_line: Some(7),
            message: "Missing $ inserted.".to_string(),
            snippet: "s^2".to_string(),
        }];
        let r = format_error_report(&errs);
        assert!(r.contains("Source line 17"));
        assert!(r.contains("Missing $ inserted."));
        assert!(r.contains("s^2"));
    }

    #[test]
    fn clean_target_strips_and_decodes() {
        assert_eq!(clean_target("<a b.pdf>"), "a b.pdf");
        assert_eq!(clean_target("a%20b.pdf"), "a b.pdf");
        assert_eq!(clean_target("  plain.md  "), "plain.md");
        assert_eq!(clean_target("Bar/_index.md"), "Bar/_index.md");
    }

    #[test]
    fn resolve_doc_link_sibling_and_subdir() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        std::fs::create_dir_all(root.join("A")).unwrap();
        std::fs::write(root.join("A/doc.md"), "x").unwrap();
        std::fs::write(root.join("A/other.md"), "y").unwrap();
        assert_eq!(resolve_doc_link_impl(root, "A/doc.md", "other.md").unwrap(), "A/other.md");
        std::fs::create_dir_all(root.join("A/B")).unwrap();
        std::fs::write(root.join("A/B/deep.scripta"), "z").unwrap();
        assert_eq!(resolve_doc_link_impl(root, "A/doc.md", "B/deep.scripta").unwrap(), "A/B/deep.scripta");
    }

    #[test]
    fn resolve_doc_link_folder_to_index() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        std::fs::write(root.join("doc.md"), "x").unwrap();
        std::fs::create_dir_all(root.join("Bar")).unwrap();
        std::fs::write(root.join("Bar/_index.md"), "i").unwrap();
        assert_eq!(resolve_doc_link_impl(root, "doc.md", "Bar").unwrap(), "Bar/_index.md");
        assert_eq!(resolve_doc_link_impl(root, "doc.md", "Bar/_index.md").unwrap(), "Bar/_index.md");
    }

    #[test]
    fn resolve_doc_link_decodes_and_strips() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        std::fs::write(root.join("doc.md"), "x").unwrap();
        std::fs::write(root.join("a b.md"), "y").unwrap();
        assert_eq!(resolve_doc_link_impl(root, "doc.md", "a%20b.md").unwrap(), "a b.md");
        assert_eq!(resolve_doc_link_impl(root, "doc.md", "<a b.md>").unwrap(), "a b.md");
    }

    #[test]
    fn resolve_doc_link_rejects_escape_and_missing() {
        let base = tempfile::tempdir().unwrap();
        let root = base.path().join("vault");
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(root.join("doc.md"), "x").unwrap();
        std::fs::write(base.path().join("outside.md"), "o").unwrap();
        assert!(resolve_doc_link_impl(&root, "doc.md", "../outside.md").is_err());
        assert!(resolve_doc_link_impl(&root, "doc.md", "nope.md").is_err());
    }

    #[test]
    fn resolve_link_target_cleans_target() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        std::fs::write(root.join("doc.md"), "x").unwrap();
        std::fs::write(root.join("a b.pdf"), "p").unwrap();
        let p = resolve_link_target(root, "doc.md", "<a b.pdf>").unwrap();
        assert_eq!(p, root.join("a b.pdf").canonicalize().unwrap());
        let p2 = resolve_link_target(root, "doc.md", "a%20b.pdf").unwrap();
        assert_eq!(p2, root.join("a b.pdf").canonicalize().unwrap());
    }

    #[test]
    fn resolve_link_sibling() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        std::fs::write(root.join("doc.md"), "x").unwrap();
        std::fs::write(root.join("file.pdf"), "x").unwrap();
        let p = resolve_link_target(root, "doc.md", "file.pdf").unwrap();
        assert_eq!(p, root.join("file.pdf").canonicalize().unwrap());
    }

    #[test]
    fn resolve_link_in_subdir() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        std::fs::create_dir_all(root.join("a/b")).unwrap();
        std::fs::write(root.join("a/b/_index.md"), "x").unwrap();
        std::fs::write(root.join("a/b/pic.pdf"), "x").unwrap();
        let p = resolve_link_target(root, "a/b/_index.md", "pic.pdf").unwrap();
        assert_eq!(p, root.join("a/b/pic.pdf").canonicalize().unwrap());
    }

    #[test]
    fn resolve_link_rejects_escape() {
        let base = tempfile::tempdir().unwrap();
        let root = base.path().join("vault");
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(root.join("doc.md"), "x").unwrap();
        std::fs::write(base.path().join("secret.pdf"), "x").unwrap();
        assert!(resolve_link_target(&root, "doc.md", "../secret.pdf").is_err());
    }

    #[test]
    fn resolve_link_missing_file_errors() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("doc.md"), "x").unwrap();
        assert!(resolve_link_target(dir.path(), "doc.md", "nope.pdf").is_err());
    }

    #[test]
    fn external_url_scheme_validation() {
        assert!(validate_external_url("https://example.com").is_ok());
        assert!(validate_external_url("http://example.com").is_ok());
        assert!(validate_external_url("mailto:a@b.c").is_ok());
        assert!(validate_external_url("file:///etc/passwd").is_err());
        assert!(validate_external_url("javascript:alert(1)").is_err());
    }

    #[test]
    fn is_text_ext_recognizes_text_extensions() {
        use std::path::Path;
        for n in ["a.txt", "a.md", "a.scripta", "a.tex", "a.json", "a.csv", "A.MD"] {
            assert!(is_text_ext(Path::new(n)), "{}", n);
        }
        for n in ["a.pdf", "a.png", "a.bin", "a.zip", "noext"] {
            assert!(!is_text_ext(Path::new(n)), "{}", n);
        }
    }

    #[test]
    fn keychain_set_get_delete_round_trip() {
        let service = "MacScriptaViewer-AI-test-rt";
        let _ = delete_api_key_impl(service, "anthropic");
        set_api_key_impl(service, "anthropic", "sk-test-1234").unwrap();
        assert_eq!(read_api_key_impl(service, "anthropic").unwrap(), "sk-test-1234");
        set_api_key_impl(service, "anthropic", "sk-test-5678").unwrap();
        assert_eq!(read_api_key_impl(service, "anthropic").unwrap(), "sk-test-5678");
        delete_api_key_impl(service, "anthropic").unwrap();
        delete_api_key_impl(service, "anthropic").unwrap();
        assert!(read_api_key_impl(service, "anthropic").is_err());
    }

    #[test]
    fn is_image_ext_recognizes_images() {
        use std::path::Path;
        for n in ["a.png", "a.JPG", "a.jpeg", "a.gif", "a.webp"] {
            assert!(is_image_ext(Path::new(n)), "{}", n);
        }
        assert!(!is_image_ext(Path::new("a.txt")));
        assert!(!is_image_ext(Path::new("a.pdf")));
    }

    #[test]
    fn read_image_returns_png_data_url() {
        use base64::Engine;
        let dir = tempfile::tempdir().unwrap();
        let bytes = [0x89u8, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]; // PNG signature
        std::fs::write(dir.path().join("pic.png"), bytes).unwrap();
        let url = read_image_impl(dir.path(), "pic.png").unwrap();
        assert!(url.starts_with("data:image/png;base64,"));
        let b64 = url.strip_prefix("data:image/png;base64,").unwrap();
        let decoded = base64::engine::general_purpose::STANDARD.decode(b64).unwrap();
        assert_eq!(decoded, bytes);
    }

    #[test]
    fn list_includes_text_and_images_excludes_binary_and_dotfiles() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        std::fs::write(root.join("note.txt"), "hi").unwrap();
        std::fs::write(root.join("pic.png"), [1u8, 2, 3]).unwrap();
        std::fs::write(root.join("doc.scripta"), "x").unwrap();
        // Excluded purely by extension — content is never read (iCloud-safe).
        std::fs::write(root.join("blob.bin"), [0u8, 1, 2]).unwrap();
        std::fs::write(root.join("paper.pdf"), [0x25u8, 0x50, 0x44, 0x46]).unwrap();
        // A text extension is listed regardless of content (no sniff)...
        std::fs::write(root.join("weird.txt"), [0u8, 1, 2]).unwrap();
        // ...and a non-listed extension is excluded even if its content is text.
        std::fs::write(root.join("data.dat"), "plain text").unwrap();
        std::fs::write(root.join(".DS_Store"), "x").unwrap();
        std::fs::create_dir_all(root.join(".git")).unwrap();
        std::fs::write(root.join(".git/config"), "x").unwrap();
        let entries = list_workspace_impl(root).unwrap();
        let names: Vec<&str> = entries.iter().map(|e| e.path.as_str()).collect();
        assert!(names.contains(&"note.txt"));
        assert!(names.contains(&"pic.png"));
        assert!(names.contains(&"doc.scripta"));
        assert!(names.contains(&"weird.txt"));
        assert!(!names.contains(&"blob.bin"));
        assert!(!names.contains(&"paper.pdf"));
        assert!(!names.contains(&"data.dat"));
        assert!(!names.iter().any(|n| n.starts_with(".DS_Store")));
        assert!(!names.iter().any(|n| n.starts_with(".git")));
    }
}
