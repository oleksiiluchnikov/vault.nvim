use mlua::prelude::*;
use rayon::prelude::*;
use std::fs;
use std::path::Path;
use walkdir::{DirEntry, WalkDir};

// Helper: Check if file/dir is hidden (starts with dot)
fn is_hidden(entry: &DirEntry) -> bool {
    entry
        .file_name()
        .to_str()
        .map(|s| s.starts_with('.'))
        .unwrap_or(false)
}

struct NoteData {
    path: String,
    frontmatter: Option<String>,
}

impl NoteData {
    fn from_path(path: &Path) -> Option<Self> {
        // Skip reading if file is huge (safety check)
        // let metadata = fs::metadata(path).ok()?;
        // if metadata.len() > 1_000_000 { return None; } // Skip files > 1MB

        let content = fs::read_to_string(path).ok()?;

        let frontmatter = if content.starts_with("---") {
            content.split("---").nth(1).map(|s| s.to_string())
        } else {
            None
        };

        Some(NoteData {
            path: path.to_string_lossy().to_string(),
            frontmatter,
        })
    }
}

fn scan_vault(lua: &Lua, root: String) -> LuaResult<LuaTable> {
    // 1. Validate path
    let root_path = Path::new(&root);
    if !root_path.exists() {
        return Err(mlua::Error::RuntimeError(format!(
            "Path does not exist: {}",
            root
        )));
    }

    // 2. Walk with filtering (The Fix for the Freeze)
    let walker = WalkDir::new(&root).into_iter();

    // Use parallel iterator
    let notes: Vec<NoteData> = walker
        .filter_entry(|e| !is_hidden(e)) // 🛑 STOP descending into .git/.obsidian
        .par_bridge()
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().map_or(false, |ext| ext == "md"))
        .filter_map(|e| NoteData::from_path(e.path()))
        .collect();

    // 3. Convert to Lua
    let table = lua.create_table()?;
    for (i, note) in notes.iter().enumerate() {
        let note_tbl = lua.create_table()?;
        note_tbl.set("path", note.path.clone())?;

        if let Some(fm) = &note.frontmatter {
            note_tbl.set("frontmatter", fm.clone())?;
        }
        table.set(i + 1, note_tbl)?;
    }

    Ok(table)
}

#[mlua::lua_module]
fn vault_core(lua: &Lua) -> LuaResult<LuaTable> {
    let exports = lua.create_table()?;
    exports.set("scan", lua.create_function(scan_vault)?)?;
    Ok(exports)
}
