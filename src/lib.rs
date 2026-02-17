use globset::{Glob, GlobSet, GlobSetBuilder};
use mlua::prelude::*;
use once_cell::sync::Lazy;
use rayon::prelude::*;
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs::File;
use std::io::{self, BufRead};
use std::path::{Path, PathBuf};
use walkdir::{DirEntry, WalkDir}; // <--- Add this

fn is_hidden(entry: &DirEntry) -> bool {
    entry
        .file_name()
        .to_str()
        .map(|s| s.starts_with('.'))
        .unwrap_or(false)
}

// ============================================================================
// Raw Parsing Structures
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
struct TaskItem {
    line: usize,
    status: String,
    content: String,
    raw: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct LinkItem {
    line: usize,
    target: String,
    embedded: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct TagItem {
    line: usize,
    name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ExternalLinkItem {
    line: usize,
    text: String,
    url: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct FieldItem {
    line: usize,
    key: String,
    value: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ParsedNote {
    path: String,
    title: Option<String>,
    frontmatter: Option<serde_json::Value>,
    tasks: Vec<TaskItem>,
    wikilinks: Vec<LinkItem>,
    tags: Vec<TagItem>,
    urls: Vec<ExternalLinkItem>,
    fields: Vec<FieldItem>,
}

impl ParsedNote {
    fn from_path(path: &Path) -> Option<Self> {
        let file = File::open(path).ok()?;
        let reader = io::BufReader::new(file);

        static RE_WIKILINK: Lazy<Regex> =
            Lazy::new(|| Regex::new(r"(!?)\[\[([^\]\|]+)(?:\|[^\]]+)?\]\]").unwrap());
        static RE_TAG: Lazy<Regex> =
            Lazy::new(|| Regex::new(r"(?:\s|^)#([a-zA-Z0-9_/-]+)").unwrap());
        static RE_TASK: Lazy<Regex> = Lazy::new(|| Regex::new(r"^\s*-\s*\[(.)\]\s*(.+)$").unwrap());
        static RE_H1: Lazy<Regex> = Lazy::new(|| Regex::new(r"^#\s+(.+)$").unwrap());
        static RE_URL: Lazy<Regex> =
            Lazy::new(|| Regex::new(r"\[([^\]]+)\]\((https?://[^\)]+)\)").unwrap());
        static RE_FIELD: Lazy<Regex> =
            Lazy::new(|| Regex::new(r"([a-zA-Z0-9_-]+)::\s*(.+)").unwrap());

        let mut tasks = Vec::new();
        let mut wikilinks = Vec::new();
        let mut tags = Vec::new();
        let mut urls = Vec::new();
        let mut fields = Vec::new();
        let mut title = None;

        let mut frontmatter_lines = Vec::new();
        let mut in_frontmatter = false;
        let mut has_frontmatter = false;
        let mut in_code_block = false;

        for (i, line_result) in reader.lines().enumerate() {
            let line = line_result.ok()?;
            let line_num = i + 1;

            // Handle code blocks
            if line.trim_start().starts_with("```") {
                in_code_block = !in_code_block;
                continue;
            }

            // Handle frontmatter
            if line_num == 1 && line.trim() == "---" {
                in_frontmatter = true;
                has_frontmatter = true;
                continue;
            }
            if in_frontmatter {
                if line.trim() == "---" {
                    in_frontmatter = false;
                } else {
                    frontmatter_lines.push(line.clone());
                }
                continue;
            }

            // Skip content inside code blocks
            if in_code_block {
                continue;
            }

            // Extract title
            if title.is_none() {
                if let Some(caps) = RE_H1.captures(&line) {
                    title = Some(caps[1].to_string());
                }
            }

            // Extract tasks
            if let Some(caps) = RE_TASK.captures(&line) {
                tasks.push(TaskItem {
                    line: line_num,
                    status: caps[1].to_string(),
                    content: caps[2].to_string(),
                    raw: line.clone(),
                });
            }

            // Extract wikilinks
            for caps in RE_WIKILINK.captures_iter(&line) {
                let embedded = !caps[1].is_empty();
                wikilinks.push(LinkItem {
                    line: line_num,
                    target: caps[2].to_string(),
                    embedded,
                });
            }

            // Extract tags
            for caps in RE_TAG.captures_iter(&line) {
                // Skip tags inside markdown links
                let tag_with_hash = format!("#{}", &caps[1]);
                if line.contains(&format!("[{}]", tag_with_hash)) {
                    continue;
                }
                tags.push(TagItem {
                    line: line_num,
                    name: caps[1].to_string(),
                });
            }

            // Extract URLs
            for caps in RE_URL.captures_iter(&line) {
                urls.push(ExternalLinkItem {
                    line: line_num,
                    text: caps[1].to_string(),
                    url: caps[2].to_string(),
                });
            }

            // Extract fields
            for caps in RE_FIELD.captures_iter(&line) {
                fields.push(FieldItem {
                    line: line_num,
                    key: caps[1].to_string(),
                    value: caps[2].to_string(),
                });
            }
        }

        let frontmatter = if has_frontmatter {
            let yaml_str = frontmatter_lines.join("\n");
            serde_yaml::from_str(&yaml_str).ok()
        } else {
            None
        };

        Some(ParsedNote {
            path: path.to_string_lossy().to_string(),
            title,
            frontmatter,
            tasks,
            wikilinks,
            tags,
            urls,
            fields,
        })
    }
}

// ============================================================================
// Aggregated Data Structures (matching Fetcher output)
// ============================================================================

#[derive(Debug, Serialize, Deserialize)]
struct PathInfo {
    path: String,
    slug: String,
    relpath: String,
    basename: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    frontmatter: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    title: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct SourceOccurrence {
    lnum: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    line: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    col: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    end_lnum: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    end_col: Option<usize>,
}

#[derive(Debug, Serialize, Deserialize)]
struct TagData {
    name: String,
    count: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    root: Option<String>,
    is_nested: bool,
    sources: HashMap<String, HashMap<usize, SourceOccurrence>>,
}

#[derive(Debug, Serialize, Deserialize)]
struct WikilinkData {
    stem: String,
    count: usize,
    embedded: bool,
    sources: HashMap<String, HashMap<usize, SourceOccurrence>>,
}

#[derive(Debug, Serialize, Deserialize)]
struct TaskData {
    description: String,
    status: String,
    count: usize,
    sources: HashMap<String, HashMap<usize, SourceOccurrence>>,
}

#[derive(Debug, Serialize, Deserialize)]
struct ExternalLinkData {
    line: String,
    text: String,
    url: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct FieldValueData {
    key: String,
    value: String,
    count: usize,
    sources: HashMap<String, HashMap<usize, SourceOccurrence>>,
}

#[derive(Debug, Serialize, Deserialize)]
struct PropertyValueData {
    name: String,
    count: usize,
    sources: HashMap<String, HashMap<usize, bool>>,
}

#[derive(Debug, Serialize, Deserialize)]
struct PropertyData {
    name: String,
    count: usize,
    sources: HashMap<String, HashMap<usize, SourceOccurrence>>,
    values: HashMap<String, PropertyValueData>,
}

// ============================================================================
// Helper Functions
// ============================================================================

fn path_to_slug(path: &str, root: &str) -> String {
    let path = path.trim_start_matches(root).trim_start_matches('/');
    path.trim_end_matches(".md").to_string()
}

fn path_to_relpath(path: &str, root: &str) -> String {
    path.trim_start_matches(root)
        .trim_start_matches('/')
        .to_string()
}

fn path_to_basename(path: &str) -> String {
    Path::new(path)
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_string()
}

fn extract_wikilink_stem(target: &str) -> String {
    // Remove alias (everything after |)
    let without_alias = target.split('|').next().unwrap_or(target);
    // Remove header (everything after #)
    let without_header = without_alias.split('#').next().unwrap_or(without_alias);
    // Remove block reference (everything after ^)
    let without_block = without_header.split('^').next().unwrap_or(without_header);
    without_block.trim().to_string()
}

// ============================================================================
// Main Scanning and Aggregation Functions
// ============================================================================

fn build_ignore_set(patterns: Vec<String>) -> GlobSet {
    let mut builder = GlobSetBuilder::new();
    for pat in patterns {
        // Add the original pattern (e.g. ".git/*")
        if let Ok(glob) = Glob::new(&pat) {
            builder.add(glob);
        }

        // AUTO-FIX: If pattern ends in "/*", also add the directory itself
        // so we don't even enter it.
        // ".git/*" -> add ".git"
        if pat.ends_with("/*") {
            let dir_pat = &pat[..pat.len() - 2];
            if let Ok(glob) = Glob::new(dir_pat) {
                builder.add(glob);
            }
        }
    }
    builder.build().unwrap_or_else(|_| GlobSet::empty())
}

fn scan_all_notes(root: &str, ignore_patterns: Vec<String>) -> Vec<ParsedNote> {
    let root_path = Path::new(root);
    if !root_path.exists() {
        return Vec::new();
    }

    // Build the matcher
    let glob_set = build_ignore_set(ignore_patterns);

    WalkDir::new(root)
        .into_iter()
        .filter_entry(move |e| {
            // 1. Standard hidden file check
            if is_hidden(e) {
                return false;
            }

            // 2. Glob ignore check
            // We match against the path relative to the root for gitignore-style behavior
            let path = e.path();
            if let Ok(rel_path) = path.strip_prefix(root) {
                // If it matches a glob, we return false (do not process/descend)
                if glob_set.is_match(rel_path) {
                    return false;
                }
            }

            true
        })
        .par_bridge() // Parallelism kicks in after filtering
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().map_or(false, |ext| ext == "md"))
        .filter_map(|e| ParsedNote::from_path(e.path()))
        .collect()
}

fn build_paths_map(notes: &[ParsedNote], root: &str) -> HashMap<String, PathInfo> {
    notes
        .iter()
        .map(|note| {
            let slug = path_to_slug(&note.path, root);
            (
                slug.clone(),
                PathInfo {
                    path: note.path.clone(),
                    slug,
                    relpath: path_to_relpath(&note.path, root),
                    basename: path_to_basename(&note.path),
                    frontmatter: note.frontmatter.clone(),
                    title: note.title.clone(),
                },
            )
        })
        .collect()
}

fn build_tags_map(notes: &[ParsedNote], root: &str) -> HashMap<String, TagData> {
    let mut tags_map: HashMap<String, TagData> = HashMap::new();

    for note in notes {
        let slug = path_to_slug(&note.path, root);

        // Process inline tags
        for tag_item in &note.tags {
            let tag_name = &tag_item.name;
            let entry = tags_map.entry(tag_name.clone()).or_insert_with(|| {
                let is_nested = tag_name.contains('/');
                let root_tag = if is_nested {
                    tag_name.split('/').next().map(|s| s.to_string())
                } else {
                    Some(tag_name.clone())
                };

                TagData {
                    name: tag_name.clone(),
                    count: 0,
                    root: root_tag,
                    is_nested,
                    sources: HashMap::new(),
                }
            });

            entry.count += 1;
            entry
                .sources
                .entry(slug.clone())
                .or_insert_with(HashMap::new)
                .insert(
                    tag_item.line,
                    SourceOccurrence {
                        lnum: tag_item.line,
                        line: None,
                        col: Some(1),
                        end_lnum: Some(tag_item.line),
                        end_col: None,
                    },
                );
        }

        // Process frontmatter tags
        if let Some(frontmatter) = &note.frontmatter {
            if let Some(tags_value) = frontmatter.get("tags") {
                let tag_names: Vec<String> = match tags_value {
                    serde_json::Value::String(s) => vec![s.clone()],
                    serde_json::Value::Array(arr) => arr
                        .iter()
                        .filter_map(|v| v.as_str().map(|s| s.to_string()))
                        .collect(),
                    _ => vec![],
                };

                for tag_name in tag_names {
                    let clean_name = tag_name.trim_matches(|c| c == '"' || c == '\'');
                    let entry = tags_map.entry(clean_name.to_string()).or_insert_with(|| {
                        let is_nested = clean_name.contains('/');
                        let root_tag = if is_nested {
                            clean_name.split('/').next().map(|s| s.to_string())
                        } else {
                            Some(clean_name.to_string())
                        };

                        TagData {
                            name: clean_name.to_string(),
                            count: 0,
                            root: root_tag,
                            is_nested,
                            sources: HashMap::new(),
                        }
                    });

                    entry.count += 1;
                    entry
                        .sources
                        .entry(slug.clone())
                        .or_insert_with(HashMap::new)
                        .insert(
                            1,
                            SourceOccurrence {
                                lnum: 1,
                                line: None,
                                col: Some(1),
                                end_lnum: Some(1),
                                end_col: None,
                            },
                        );
                }
            }
        }
    }

    tags_map
}

fn build_wikilinks_map(notes: &[ParsedNote], root: &str) -> HashMap<String, WikilinkData> {
    let mut wikilinks_map: HashMap<String, WikilinkData> = HashMap::new();

    for note in notes {
        let slug = path_to_slug(&note.path, root);

        for link_item in &note.wikilinks {
            let stem = extract_wikilink_stem(&link_item.target);

            let entry = wikilinks_map
                .entry(stem.clone())
                .or_insert_with(|| WikilinkData {
                    stem: stem.clone(),
                    count: 0,
                    embedded: false,
                    sources: HashMap::new(),
                });

            entry.count += 1;
            if link_item.embedded {
                entry.embedded = true;
            }

            entry
                .sources
                .entry(slug.clone())
                .or_insert_with(HashMap::new)
                .insert(
                    link_item.line,
                    SourceOccurrence {
                        lnum: link_item.line,
                        line: None,
                        col: None,
                        end_lnum: Some(link_item.line),
                        end_col: None,
                    },
                );
        }
    }

    wikilinks_map
}

fn build_tasks_map(notes: &[ParsedNote], root: &str) -> HashMap<String, TaskData> {
    let mut tasks_map: HashMap<String, TaskData> = HashMap::new();

    for note in notes {
        let slug = path_to_slug(&note.path, root);

        for task_item in &note.tasks {
            let entry = tasks_map
                .entry(task_item.content.clone())
                .or_insert_with(|| TaskData {
                    description: task_item.content.clone(),
                    status: task_item.status.clone(),
                    count: 0,
                    sources: HashMap::new(),
                });

            entry.count += 1;

            entry
                .sources
                .entry(slug.clone())
                .or_insert_with(HashMap::new)
                .insert(
                    task_item.line,
                    SourceOccurrence {
                        lnum: task_item.line,
                        line: Some(task_item.raw.clone()),
                        col: None,
                        end_lnum: Some(task_item.line),
                        end_col: None,
                    },
                );
        }
    }

    tasks_map
}

fn build_links_map(
    notes: &[ParsedNote],
    root: &str,
) -> HashMap<String, HashMap<usize, ExternalLinkData>> {
    let mut links_map: HashMap<String, HashMap<usize, ExternalLinkData>> = HashMap::new();

    for note in notes {
        let slug = path_to_slug(&note.path, root);

        for url_item in &note.urls {
            links_map
                .entry(slug.clone())
                .or_insert_with(HashMap::new)
                .insert(
                    url_item.line,
                    ExternalLinkData {
                        line: url_item.line.to_string(),
                        text: url_item.text.clone(),
                        url: url_item.url.clone(),
                    },
                );
        }
    }

    links_map
}

fn build_fields_map(
    notes: &[ParsedNote],
    root: &str,
) -> HashMap<String, HashMap<String, FieldValueData>> {
    let mut fields_map: HashMap<String, HashMap<String, FieldValueData>> = HashMap::new();

    for note in notes {
        let slug = path_to_slug(&note.path, root);

        for field_item in &note.fields {
            let key_entry = fields_map
                .entry(field_item.key.clone())
                .or_insert_with(HashMap::new);

            let value_entry = key_entry
                .entry(field_item.value.clone())
                .or_insert_with(|| FieldValueData {
                    key: field_item.key.clone(),
                    value: field_item.value.clone(),
                    count: 0,
                    sources: HashMap::new(),
                });

            value_entry.count += 1;

            value_entry
                .sources
                .entry(slug.clone())
                .or_insert_with(HashMap::new)
                .insert(
                    field_item.line,
                    SourceOccurrence {
                        lnum: field_item.line,
                        line: None,
                        col: None,
                        end_lnum: Some(field_item.line),
                        end_col: None,
                    },
                );
        }
    }

    fields_map
}

fn build_properties_map(notes: &[ParsedNote], root: &str) -> HashMap<String, PropertyData> {
    let mut properties_map: HashMap<String, PropertyData> = HashMap::new();

    for note in notes {
        let slug = path_to_slug(&note.path, root);

        if let Some(frontmatter) = &note.frontmatter {
            if let serde_json::Value::Object(map) = frontmatter {
                for (key, value) in map {
                    let property =
                        properties_map
                            .entry(key.clone())
                            .or_insert_with(|| PropertyData {
                                name: key.clone(),
                                count: 0,
                                sources: HashMap::new(),
                                values: HashMap::new(),
                            });

                    property.count += 1;
                    property
                        .sources
                        .entry(slug.clone())
                        .or_insert_with(HashMap::new)
                        .insert(
                            1,
                            SourceOccurrence {
                                lnum: 1,
                                line: None,
                                col: None,
                                end_lnum: None,
                                end_col: None,
                            },
                        );

                    // Handle property values
                    let values: Vec<String> = match value {
                        serde_json::Value::String(s) => vec![s.clone()],
                        serde_json::Value::Array(arr) => arr
                            .iter()
                            .map(|v| match v {
                                serde_json::Value::String(s) => s.clone(),
                                _ => v.to_string(),
                            })
                            .collect(),
                        _ => vec![value.to_string()],
                    };

                    for val_str in values {
                        let val_entry =
                            property.values.entry(val_str.clone()).or_insert_with(|| {
                                PropertyValueData {
                                    name: val_str.clone(),
                                    count: 0,
                                    sources: HashMap::new(),
                                }
                            });

                        val_entry.count += 1;
                        val_entry
                            .sources
                            .entry(slug.clone())
                            .or_insert_with(HashMap::new)
                            .insert(1, true);
                    }
                }
            }
        }
    }

    properties_map
}

fn build_dirs_map(notes: &[ParsedNote], root: &str) -> HashMap<String, bool> {
    let mut dirs_set: std::collections::HashSet<String> = std::collections::HashSet::new();
    let root_path = PathBuf::from(root);

    for note in notes {
        if let Some(parent) = Path::new(&note.path).parent() {
            if parent != root_path {
                if let Ok(relpath) = parent.strip_prefix(&root_path) {
                    if let Some(relpath_str) = relpath.to_str() {
                        if !relpath_str.is_empty() {
                            dirs_set.insert(relpath_str.to_string());
                        }
                    }
                }
            }
        }
    }

    dirs_set.into_iter().map(|d| (d, true)).collect()
}

fn build_slugs_set(notes: &[ParsedNote], root: &str) -> HashMap<String, bool> {
    notes
        .iter()
        .map(|note| (path_to_slug(&note.path, root), true))
        .collect()
}

// // ============================================================================
// // Lua Module Exports
// // ============================================================================
//
// fn vault_paths(lua: &Lua, (root, ignores): (String, Vec<String>)) -> LuaResult<LuaValue> {
//     let notes = scan_all_notes(&root, ignores);
//     let paths_map = build_paths_map(&notes, &root);
//     lua.to_value(&paths_map)
// }
//
// fn vault_slugs(lua: &Lua, (root, ignores): (String, Vec<String>)) -> LuaResult<LuaValue> {
//     let notes = scan_all_notes(&root, ignores);
//     let slugs_set = build_slugs_set(&notes, &root);
//     lua.to_value(&slugs_set)
// }
//
// fn vault_tags(lua: &Lua, (root, ignores): (String, Vec<String>)) -> LuaResult<LuaValue> {
//     let notes = scan_all_notes(&root, ignores);
//     let tags_map = build_tags_map(&notes, &root);
//     lua.to_value(&tags_map)
// }
//
// fn vault_wikilinks(lua: &Lua, root: String) -> LuaResult<LuaValue> {
//     let notes = scan_all_notes(&root);
//     let wikilinks_map = build_wikilinks_map(&notes, &root);
//     lua.to_value(&wikilinks_map)
// }
//
// fn vault_tasks(lua: &Lua, root: String) -> LuaResult<LuaValue> {
//     let notes = scan_all_notes(&root);
//     let tasks_map = build_tasks_map(&notes, &root);
//     lua.to_value(&tasks_map)
// }
//
// fn vault_links(lua: &Lua, root: String) -> LuaResult<LuaValue> {
//     let notes = scan_all_notes(&root);
//     let links_map = build_links_map(&notes, &root);
//     lua.to_value(&links_map)
// }
//
// fn vault_fields(lua: &Lua, root: String) -> LuaResult<LuaValue> {
//     let notes = scan_all_notes(&root);
//     let fields_map = build_fields_map(&notes, &root);
//     lua.to_value(&fields_map)
// }
//
// fn vault_properties(lua: &Lua, root: String) -> LuaResult<LuaValue> {
//     let notes = scan_all_notes(&root);
//     let properties_map = build_properties_map(&notes, &root);
//     lua.to_value(&properties_map)
// }
//
// fn vault_dirs(lua: &Lua, root: String) -> LuaResult<LuaValue> {
//     let notes = scan_all_notes(&root);
//     let dirs_map = build_dirs_map(&notes, &root);
//     lua.to_value(&dirs_map)
// }
// ============================================================================
// Lua Module Exports
// ============================================================================

/// Generic helper to reduce boilerplate.
/// It takes Lua args, scans the notes, applies the specific `builder` function,
/// and converts the result back to Lua.
fn run_scanner<T, F>(
    lua: &Lua,
    (root, ignores): (String, Vec<String>), // Standardize inputs
    builder: F,
) -> LuaResult<LuaValue>
where
    T: Serialize,
    F: FnOnce(&[ParsedNote], &str) -> T,
{
    // 1. Heavy lifting: Scan the filesystem
    let notes = scan_all_notes(&root, ignores);

    // 2. Build the specific map/set using the provided function
    let data = builder(&notes, &root);

    // 3. Serialize to Lua
    lua.to_value(&data)
}

// 1. Define this helper function if you haven't already,
//    or just use a closure in the module definition.
fn vault_scan_raw(lua: &Lua, (root, ignores): (String, Vec<String>)) -> LuaResult<LuaValue> {
    let notes = scan_all_notes(&root, ignores);
    lua.to_value(&notes)
}

#[mlua::lua_module]
fn vault_core(lua: &Lua) -> LuaResult<LuaTable> {
    let exports = lua.create_table()?;

    // exports.set("paths", lua.create_function(vault_paths)?)?;
    // exports.set("slugs", lua.create_function(vault_slugs)?)?;
    // exports.set("tags", lua.create_function(vault_tags)?)?;
    // exports.set("wikilinks", lua.create_function(vault_wikilinks)?)?;
    // exports.set("tasks", lua.create_function(vault_tasks)?)?;
    // exports.set("links", lua.create_function(vault_links)?)?;
    // exports.set("fields", lua.create_function(vault_fields)?)?;
    // exports.set("properties", lua.create_function(vault_properties)?)?;
    // exports.set("dirs", lua.create_function(vault_dirs)?)?;

    exports.set(
        "paths",
        lua.create_function(|lua, (root, ignores): (String, Vec<String>)| {
            run_scanner(lua, (root, ignores), build_paths_map)
        })?,
    )?;
    exports.set(
        "slugs",
        lua.create_function(|lua, (root, ignores): (String, Vec<String>)| {
            run_scanner(lua, (root, ignores), build_slugs_set)
        })?,
    )?;
    exports.set(
        "tags",
        lua.create_function(|lua, (root, ignores): (String, Vec<String>)| {
            run_scanner(lua, (root, ignores), build_tags_map)
        })?,
    )?;
    exports.set(
        "wikilinks",
        lua.create_function(|lua, (root, ignores): (String, Vec<String>)| {
            run_scanner(lua, (root, ignores), build_wikilinks_map)
        })?,
    )?;
    exports.set(
        "tasks",
        lua.create_function(|lua, (root, ignores): (String, Vec<String>)| {
            run_scanner(lua, (root, ignores), build_tasks_map)
        })?,
    )?;
    exports.set(
        "links",
        lua.create_function(|lua, (root, ignores): (String, Vec<String>)| {
            run_scanner(lua, (root, ignores), build_links_map)
        })?,
    )?;
    exports.set(
        "fields",
        lua.create_function(|lua, (root, ignores): (String, Vec<String>)| {
            run_scanner(lua, (root, ignores), build_fields_map)
        })?,
    )?;
    exports.set(
        "properties",
        lua.create_function(|lua, (root, ignores): (String, Vec<String>)| {
            run_scanner(lua, (root, ignores), build_properties_map)
        })?,
    )?;
    exports.set(
        "dirs",
        lua.create_function(|lua, (root, ignores): (String, Vec<String>)| {
            run_scanner(lua, (root, ignores), build_dirs_map)
        })?,
    )?;

    exports.set("scan", lua.create_function(vault_scan_raw)?)?;

    Ok(exports)
}
