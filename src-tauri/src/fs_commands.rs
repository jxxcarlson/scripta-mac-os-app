use serde::{Deserialize, Serialize};
use std::path::Path;
use walkdir::WalkDir;

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

/// List all document files (and the dirs containing them) under `root`,
/// returning entries with workspace-relative paths.
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
        let rel = p
            .strip_prefix(root)
            .map_err(|e| e.to_string())?
            .to_string_lossy()
            .replace('\\', "/");
        let mtime = if is_dir { 0 } else { mtime_ms(p) };
        out.push(Entry {
            path: rel,
            name: dent.file_name().to_string_lossy().to_string(),
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
    }
}
