use globset::{Glob, GlobSet, GlobSetBuilder};
use mlua::prelude::*;
use once_cell::sync::Lazy;
use rayon::prelude::*;
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::fs::{self, File};
use std::io::{self, BufRead};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::SystemTime;
use strsim::{jaro_winkler, normalized_levenshtein};
use walkdir::{DirEntry, WalkDir};

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
struct LineItem {
    line: usize,
    content: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ParsedNote {
    path: String,
    title: Option<String>,
    frontmatter: Option<serde_json::Value>,
    lines: Vec<LineItem>,
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
        let mut lines = Vec::new();

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

            // Strip inline code spans so we don't extract wikilinks/tags from
            // backtick-enclosed content (e.g. `[[not a link]]`, `#not-a-tag`).
            let stripped = strip_inline_code(&line);

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

            // Extract list-like lines (matches Lua's ^%s*%- )
            if line.trim_start().starts_with("- ") {
                let content = line.trim().to_string();
                if !content.is_empty() {
                    lines.push(LineItem {
                        line: line_num,
                        content,
                    });
                }
            }

            // Extract wikilinks (from stripped line to skip inline code)
            for caps in RE_WIKILINK.captures_iter(&stripped) {
                let raw_content = &caps[2];
                // Reject bash-style [[ ... ]] (leading/trailing whitespace)
                if !is_valid_wikilink_content(raw_content) {
                    continue;
                }
                let embedded = !caps[1].is_empty();
                wikilinks.push(LinkItem {
                    line: line_num,
                    target: raw_content.to_string(),
                    embedded,
                });
            }

            // Extract tags (from stripped line to skip inline code)
            for caps in RE_TAG.captures_iter(&stripped) {
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

            // Extract URLs (from stripped line to skip inline code)
            for caps in RE_URL.captures_iter(&stripped) {
                urls.push(ExternalLinkItem {
                    line: line_num,
                    text: caps[1].to_string(),
                    url: caps[2].to_string(),
                });
            }

            // Extract fields (from stripped line to skip inline code)
            for caps in RE_FIELD.captures_iter(&stripped) {
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
            lines,
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

#[derive(Debug, Clone, Serialize, Deserialize)]
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

#[derive(Debug, Clone, Serialize, Deserialize)]
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

#[derive(Debug, Clone, Serialize, Deserialize)]
struct TagData {
    name: String,
    count: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    root: Option<String>,
    is_nested: bool,
    sources: HashMap<String, HashMap<usize, SourceOccurrence>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SuggestionCandidate {
    slug: String,
    score: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct WikilinkData {
    stem: String,
    count: usize,
    embedded: bool,
    sources: HashMap<String, HashMap<usize, SourceOccurrence>>,
    #[serde(skip_serializing_if = "HashMap::is_empty")]
    suggestions: HashMap<String, Vec<SuggestionCandidate>>,
    #[serde(skip)]
    embedded_count: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct TaskData {
    description: String,
    status: String,
    count: usize,
    sources: HashMap<String, HashMap<usize, SourceOccurrence>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct LineData {
    content: String,
    count: usize,
    sources: HashMap<String, HashMap<usize, SourceOccurrence>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ExternalLinkData {
    line: String,
    text: String,
    url: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct FieldValueData {
    key: String,
    value: String,
    count: usize,
    sources: HashMap<String, HashMap<usize, SourceOccurrence>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct PropertyValueData {
    name: String,
    count: usize,
    sources: HashMap<String, HashMap<usize, bool>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
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

/// Returns true if the raw wikilink content (the text between `[[` and `]]`)
/// looks like a valid Obsidian wikilink rather than bash `[[ ... ]]` syntax.
///
/// Key heuristic: Obsidian wikilinks never have leading or trailing whitespace
/// inside the brackets, while bash test expressions always do:
///   `[[note name]]`       -> valid (no leading/trailing space)
///   `[[ -d "$path" ]]`    -> invalid (leading space after `[[`)
fn is_valid_wikilink_content(raw: &str) -> bool {
    if raw.is_empty() {
        return false;
    }
    // Reject if the raw captured content starts or ends with whitespace.
    // Bash conditionals: [[ -d "$path" ]] -> captured " -d \"$path\" " has leading space.
    // Obsidian wikilinks: [[note name]] -> captured "note name" has no leading/trailing space.
    if raw.starts_with(char::is_whitespace) || raw.ends_with(char::is_whitespace) {
        return false;
    }
    true
}

/// Strip inline code spans (backtick-enclosed text) from a line by replacing
/// their content with spaces. This prevents false-positive extraction of
/// wikilinks, tags, etc. from within inline code.
///
/// Handles both single backticks (`code`) and multi-backtick sequences
/// (`` `code` ``). Preserves line length so character positions remain valid.
fn strip_inline_code(line: &str) -> String {
    let bytes = line.as_bytes();
    let len = bytes.len();
    let mut result = line.to_string();
    let mut i = 0;

    while i < len {
        if bytes[i] == b'`' {
            // Count the opening backtick run length
            let tick_start = i;
            let mut tick_len = 0;
            while i < len && bytes[i] == b'`' {
                tick_len += 1;
                i += 1;
            }

            // Find the matching closing backtick run of the same length
            let content_start = i;
            let mut found_close = false;
            while i < len {
                if bytes[i] == b'`' {
                    let _close_start = i;
                    let mut close_len = 0;
                    while i < len && bytes[i] == b'`' {
                        close_len += 1;
                        i += 1;
                    }
                    if close_len == tick_len {
                        // Found matching close — blank out everything from
                        // opening backticks through closing backticks (inclusive)
                        let blank: String = " ".repeat(i - tick_start);
                        result.replace_range(tick_start..i, &blank);
                        found_close = true;
                        break;
                    }
                    // Not matching length, continue searching
                } else {
                    i += 1;
                }
            }

            if !found_close {
                // No matching close found; leave as-is, move past the opening ticks
                i = content_start;
            }
        } else {
            i += 1;
        }
    }

    result
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

// ============================================================================
// Incremental Scan Cache
// ============================================================================

/// Cached parse result for a single file, tagged with its mtime.
#[derive(Debug, Clone)]
struct CachedNote {
    mtime: SystemTime,
    note: ParsedNote,
}

/// Global scan cache: holds the last full scan result keyed by file path.
/// On subsequent scans, only files with changed mtime are re-parsed.
struct ScanCache {
    root: String,
    ignores_hash: u64,
    generation: u64,
    entries: HashMap<PathBuf, CachedNote>,
    paths_map: HashMap<String, PathInfo>,
    wikilinks_map_no_suggest: HashMap<String, WikilinkData>,
    last_diff_from_generation: u64,
    last_paths_updated: HashMap<String, PathInfo>,
    last_paths_removed: Vec<String>,
    last_wikilinks_updated: HashMap<String, WikilinkData>,
    last_wikilinks_removed: Vec<String>,
}

static SCAN_CACHE: Lazy<Mutex<Option<ScanCache>>> = Lazy::new(|| Mutex::new(None));

fn cached_paths_and_wikilinks_response<'lua>(
    lua: &'lua Lua,
    generation: u64,
    changed: bool,
    full: bool,
    paths: Option<&HashMap<String, PathInfo>>,
    wikilinks: Option<&HashMap<String, WikilinkData>>,
    paths_updated: Option<&HashMap<String, PathInfo>>,
    paths_removed: Option<&Vec<String>>,
    wikilinks_updated: Option<&HashMap<String, WikilinkData>>,
    wikilinks_removed: Option<&Vec<String>>,
) -> LuaResult<LuaValue<'lua>> {
    let table = lua.create_table()?;
    table.set("generation", generation)?;
    table.set("changed", changed)?;
    table.set("full", full)?;

    if let Some(paths) = paths {
        table.set("paths", lua.to_value(paths)?)?;
    }
    if let Some(wikilinks) = wikilinks {
        table.set("wikilinks", lua.to_value(wikilinks)?)?;
    }
    if let Some(paths_updated) = paths_updated {
        table.set("paths_updated", lua.to_value(paths_updated)?)?;
    }
    if let Some(paths_removed) = paths_removed {
        table.set("paths_removed", lua.to_value(paths_removed)?)?;
    }
    if let Some(wikilinks_updated) = wikilinks_updated {
        table.set("wikilinks_updated", lua.to_value(wikilinks_updated)?)?;
    }
    if let Some(wikilinks_removed) = wikilinks_removed {
        table.set("wikilinks_removed", lua.to_value(wikilinks_removed)?)?;
    }

    Ok(LuaValue::Table(table))
}

/// Simple hash for ignore patterns so we can detect config changes.
fn hash_ignores(ignores: &[String]) -> u64 {
    let mut h: u64 = 0xcbf29ce484222325; // FNV offset basis
    for s in ignores {
        for b in s.bytes() {
            h ^= b as u64;
            h = h.wrapping_mul(0x100000001b3); // FNV prime
        }
        h ^= 0xff;
        h = h.wrapping_mul(0x100000001b3);
    }
    h
}

/// Incremental scan: reuse cached ParsedNotes for unchanged files.
/// When `collect_notes` is false, the cache is refreshed without rebuilding an
/// owned `Vec<ParsedNote>` from the cache.
fn scan_all_notes_cached(
    root: &str,
    ignore_patterns: Vec<String>,
    collect_notes: bool,
) -> Option<Vec<ParsedNote>> {
    let root_path = Path::new(root);
    if !root_path.exists() {
        return if collect_notes {
            Some(Vec::new())
        } else {
            None
        };
    }

    let ignores_hash = hash_ignores(&ignore_patterns);
    let glob_set = build_ignore_set(ignore_patterns);

    // Collect all current .md files with their mtimes
    let current_files: Vec<(PathBuf, SystemTime)> = WalkDir::new(root)
        .into_iter()
        .filter_entry(|e| {
            if is_hidden(e) {
                return false;
            }
            let path = e.path();
            if let Ok(rel_path) = path.strip_prefix(root) {
                if glob_set.is_match(rel_path) {
                    return false;
                }
            }
            true
        })
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().map_or(false, |ext| ext == "md"))
        .filter_map(|e| {
            let path = e.path().to_path_buf();
            let mtime = fs::metadata(&path).ok()?.modified().ok()?;
            Some((path, mtime))
        })
        .collect();

    let mut cache = SCAN_CACHE.lock().unwrap();

    // Check if cache is valid (same root and ignore config)
    let cache_valid = cache
        .as_ref()
        .map_or(false, |c| c.root == root && c.ignores_hash == ignores_hash);

    if !cache_valid {
        // Cold start: parse everything in parallel, populate cache
        let parsed: Vec<(PathBuf, SystemTime, ParsedNote)> = current_files
            .par_iter()
            .filter_map(|(path, mtime)| {
                ParsedNote::from_path(path).map(|note| (path.clone(), mtime.clone(), note))
            })
            .collect();

        let mut entries = HashMap::with_capacity(parsed.len());
        let mut paths_map = HashMap::with_capacity(parsed.len());
        let mut wikilinks_map_no_suggest = HashMap::new();
        let mut notes = if collect_notes {
            Some(Vec::with_capacity(parsed.len()))
        } else {
            None
        };

        for (path, mtime, note) in parsed {
            if let Some(collected) = notes.as_mut() {
                collected.push(note.clone());
            }

            entries.insert(
                path,
                CachedNote {
                    mtime,
                    note: note.clone(),
                },
            );

            insert_note_path(&mut paths_map, &note, root);
            insert_note_wikilinks_no_suggest(&mut wikilinks_map_no_suggest, &note, root);
        }

        *cache = Some(ScanCache {
            root: root.to_string(),
            ignores_hash: ignores_hash,
            generation: 1,
            entries,
            paths_map,
            wikilinks_map_no_suggest,
            last_diff_from_generation: 0,
            last_paths_updated: HashMap::new(),
            last_paths_removed: Vec::new(),
            last_wikilinks_updated: HashMap::new(),
            last_wikilinks_removed: Vec::new(),
        });

        return notes;
    }

    // Warm path: incremental update
    let sc = cache.as_mut().unwrap();
    let current_set: HashMap<&PathBuf, &SystemTime> =
        current_files.iter().map(|(p, m)| (p, m)).collect();

    // Find changed and new files
    let to_reparse: Vec<&PathBuf> = current_files
        .iter()
        .filter(|(path, mtime)| {
            sc.entries
                .get(path)
                .map_or(true, |cached| cached.mtime != *mtime)
        })
        .map(|(path, _)| path)
        .collect();

    let previous_generation = sc.generation;
    let mut changed = false;
    let mut dirty_path_keys: HashSet<String> = HashSet::new();
    let mut dirty_wikilink_keys: HashSet<String> = HashSet::new();

    // Remove deleted files from cache and incremental maps
    let deleted_paths: Vec<PathBuf> = sc
        .entries
        .keys()
        .filter(|path| !current_set.contains_key(*path))
        .cloned()
        .collect();
    for path in deleted_paths {
        if let Some(cached) = sc.entries.remove(&path) {
            dirty_path_keys.insert(path_to_slug(&cached.note.path, root));
            mark_note_wikilink_stems(&cached.note, &mut dirty_wikilink_keys);
            remove_note_path(&mut sc.paths_map, &cached.note, root);
            remove_note_wikilinks_no_suggest(&mut sc.wikilinks_map_no_suggest, &cached.note, root);
            changed = true;
        }
    }

    // Re-parse changed/new files in parallel
    if !to_reparse.is_empty() {
        let reparsed: Vec<(PathBuf, CachedNote)> = to_reparse
            .par_iter()
            .filter_map(|path| {
                let note = ParsedNote::from_path(path)?;
                let mtime = fs::metadata(path).ok()?.modified().ok()?;
                Some((path.to_path_buf(), CachedNote { mtime, note }))
            })
            .collect();

        for (path, cached) in reparsed {
            if let Some(previous) = sc.entries.get(&path) {
                dirty_path_keys.insert(path_to_slug(&previous.note.path, root));
                mark_note_wikilink_stems(&previous.note, &mut dirty_wikilink_keys);
                remove_note_path(&mut sc.paths_map, &previous.note, root);
                remove_note_wikilinks_no_suggest(
                    &mut sc.wikilinks_map_no_suggest,
                    &previous.note,
                    root,
                );
            }

            dirty_path_keys.insert(path_to_slug(&cached.note.path, root));
            mark_note_wikilink_stems(&cached.note, &mut dirty_wikilink_keys);
            insert_note_path(&mut sc.paths_map, &cached.note, root);
            insert_note_wikilinks_no_suggest(&mut sc.wikilinks_map_no_suggest, &cached.note, root);
            sc.entries.insert(path, cached);
            changed = true;
        }
    }

    if changed {
        let mut last_paths_updated = HashMap::new();
        let mut last_paths_removed = Vec::new();
        for slug in dirty_path_keys {
            if let Some(info) = sc.paths_map.get(&slug) {
                last_paths_updated.insert(slug, info.clone());
            } else {
                last_paths_removed.push(slug);
            }
        }

        let mut last_wikilinks_updated = HashMap::new();
        let mut last_wikilinks_removed = Vec::new();
        for stem in dirty_wikilink_keys {
            if let Some(info) = sc.wikilinks_map_no_suggest.get(&stem) {
                last_wikilinks_updated.insert(stem, info.clone());
            } else {
                last_wikilinks_removed.push(stem);
            }
        }

        last_paths_removed.sort();
        last_wikilinks_removed.sort();
        sc.last_diff_from_generation = previous_generation;
        sc.last_paths_updated = last_paths_updated;
        sc.last_paths_removed = last_paths_removed;
        sc.last_wikilinks_updated = last_wikilinks_updated;
        sc.last_wikilinks_removed = last_wikilinks_removed;
        sc.generation = sc.generation.wrapping_add(1);
    }

    if collect_notes {
        Some(sc.entries.values().map(|c| c.note.clone()).collect())
    } else {
        None
    }
}

/// Clear the scan cache (called from Lua when the watcher detects changes
/// or when the user explicitly requests a refresh).
fn clear_scan_cache() {
    let mut cache = SCAN_CACHE.lock().unwrap();
    *cache = None;
}

fn build_paths_map(notes: &[ParsedNote], root: &str) -> HashMap<String, PathInfo> {
    let mut paths_map = HashMap::with_capacity(notes.len());
    for note in notes {
        insert_note_path(&mut paths_map, note, root);
    }
    paths_map
}

fn build_path_info(note: &ParsedNote, root: &str) -> (String, PathInfo) {
    let slug = path_to_slug(&note.path, root);
    let info = PathInfo {
        path: note.path.clone(),
        slug: slug.clone(),
        relpath: path_to_relpath(&note.path, root),
        basename: path_to_basename(&note.path),
        frontmatter: note.frontmatter.clone(),
        title: note.title.clone(),
    };

    (slug, info)
}

fn insert_note_path(paths_map: &mut HashMap<String, PathInfo>, note: &ParsedNote, root: &str) {
    let (slug, info) = build_path_info(note, root);
    paths_map.insert(slug, info);
}

fn remove_note_path(paths_map: &mut HashMap<String, PathInfo>, note: &ParsedNote, root: &str) {
    let slug = path_to_slug(&note.path, root);
    paths_map.remove(&slug);
}

fn mark_note_wikilink_stems(note: &ParsedNote, dirty_stems: &mut HashSet<String>) {
    for link_item in &note.wikilinks {
        dirty_stems.insert(extract_wikilink_stem(&link_item.target));
    }
}

fn insert_note_wikilinks_no_suggest(
    wikilinks_map: &mut HashMap<String, WikilinkData>,
    note: &ParsedNote,
    root: &str,
) {
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
                suggestions: HashMap::new(),
                embedded_count: 0,
            });

        entry.count += 1;
        if link_item.embedded {
            entry.embedded_count += 1;
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

fn remove_note_wikilinks_no_suggest(
    wikilinks_map: &mut HashMap<String, WikilinkData>,
    note: &ParsedNote,
    root: &str,
) {
    let slug = path_to_slug(&note.path, root);

    for link_item in &note.wikilinks {
        let stem = extract_wikilink_stem(&link_item.target);
        let mut remove_entry = false;

        if let Some(entry) = wikilinks_map.get_mut(&stem) {
            entry.count = entry.count.saturating_sub(1);
            if link_item.embedded {
                entry.embedded_count = entry.embedded_count.saturating_sub(1);
            }

            if let Some(source_occurrences) = entry.sources.get_mut(&slug) {
                source_occurrences.remove(&link_item.line);
                if source_occurrences.is_empty() {
                    entry.sources.remove(&slug);
                }
            }

            entry.embedded = entry.embedded_count > 0;
            remove_entry = entry.count == 0 || entry.sources.is_empty();
        }

        if remove_entry {
            wikilinks_map.remove(&stem);
        }
    }
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

// ============================================================================
// Suggestion Strategies
// ============================================================================

/// Helper: score, sort, truncate, and convert to SuggestionCandidate vec.
fn top_n(scored: Vec<(String, f64)>, limit: usize, threshold: f64) -> Vec<SuggestionCandidate> {
    let mut filtered: Vec<(String, f64)> = scored
        .into_iter()
        .filter(|(_, s)| *s >= threshold)
        .collect();
    filtered.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
    filtered.truncate(limit);
    filtered
        .into_iter()
        .map(|(slug, score)| SuggestionCandidate { slug, score })
        .collect()
}

/// Jaro-Winkler fuzzy similarity (compares full slug and basename).
fn strategy_jaro_winkler(
    query: &str,
    all_slugs: &[&str],
    limit: usize,
    threshold: f64,
) -> Vec<SuggestionCandidate> {
    let query_lower = query.to_lowercase();
    let query_base = query.rsplit('/').next().unwrap_or(query).to_lowercase();
    let scored: Vec<(String, f64)> = all_slugs
        .iter()
        .map(|slug| {
            let sl = slug.to_lowercase();
            let sb = slug.rsplit('/').next().unwrap_or(slug).to_lowercase();
            let score = jaro_winkler(&query_lower, &sl).max(jaro_winkler(&query_base, &sb));
            (slug.to_string(), score)
        })
        .collect();
    top_n(scored, limit, threshold)
}

/// Normalized Levenshtein distance (0..1, higher = more similar).
fn strategy_levenshtein(
    query: &str,
    all_slugs: &[&str],
    limit: usize,
    threshold: f64,
) -> Vec<SuggestionCandidate> {
    let query_lower = query.to_lowercase();
    let query_base = query.rsplit('/').next().unwrap_or(query).to_lowercase();
    let scored: Vec<(String, f64)> = all_slugs
        .iter()
        .map(|slug| {
            let sl = slug.to_lowercase();
            let sb = slug.rsplit('/').next().unwrap_or(slug).to_lowercase();
            let score = normalized_levenshtein(&query_lower, &sl)
                .max(normalized_levenshtein(&query_base, &sb));
            (slug.to_string(), score)
        })
        .collect();
    top_n(scored, limit, threshold)
}

/// Substring / contains match. Score = len(query) / len(slug) so longer matches rank higher.
fn strategy_contains(query: &str, all_slugs: &[&str], limit: usize) -> Vec<SuggestionCandidate> {
    let query_lower = query.to_lowercase();
    let scored: Vec<(String, f64)> = all_slugs
        .iter()
        .filter_map(|slug| {
            let sl = slug.to_lowercase();
            if sl.contains(&query_lower) || query_lower.contains(&sl) {
                let score =
                    query_lower.len().min(sl.len()) as f64 / query_lower.len().max(sl.len()) as f64;
                Some((slug.to_string(), score))
            } else {
                // Also check basename
                let sb = slug.rsplit('/').next().unwrap_or(slug).to_lowercase();
                let qb = query.rsplit('/').next().unwrap_or(query).to_lowercase();
                if sb.contains(&qb) || qb.contains(&sb) {
                    let score = qb.len().min(sb.len()) as f64 / qb.len().max(sb.len()) as f64;
                    Some((slug.to_string(), score))
                } else {
                    None
                }
            }
        })
        .collect();
    top_n(scored, limit, 0.0)
}

/// Prefix match: slug or basename starts with the query (or vice versa).
fn strategy_prefix(query: &str, all_slugs: &[&str], limit: usize) -> Vec<SuggestionCandidate> {
    let query_lower = query.to_lowercase();
    let query_base = query.rsplit('/').next().unwrap_or(query).to_lowercase();
    let scored: Vec<(String, f64)> = all_slugs
        .iter()
        .filter_map(|slug| {
            let sl = slug.to_lowercase();
            let sb = slug.rsplit('/').next().unwrap_or(slug).to_lowercase();
            let is_match = sl.starts_with(&query_lower)
                || query_lower.starts_with(&sl)
                || sb.starts_with(&query_base)
                || query_base.starts_with(&sb);
            if is_match {
                // Score = ratio of shorter / longer (exact prefix = 1.0)
                let score =
                    query_lower.len().min(sl.len()) as f64 / query_lower.len().max(sl.len()) as f64;
                Some((slug.to_string(), score))
            } else {
                None
            }
        })
        .collect();
    top_n(scored, limit, 0.0)
}

/// Compute suggestions for a single unresolved stem across all strategies.
/// Returns a map: strategy_name → Vec<SuggestionCandidate>.
fn suggest_all_strategies(
    query: &str,
    all_slugs: &[&str],
    limit: usize,
) -> HashMap<String, Vec<SuggestionCandidate>> {
    let mut map = HashMap::new();

    let jw = strategy_jaro_winkler(query, all_slugs, limit, 0.75);
    if !jw.is_empty() {
        map.insert("jaro_winkler".to_string(), jw);
    }

    let lev = strategy_levenshtein(query, all_slugs, limit, 0.55);
    if !lev.is_empty() {
        map.insert("levenshtein".to_string(), lev);
    }

    let cont = strategy_contains(query, all_slugs, limit);
    // Filter out very low-quality substring matches
    let cont: Vec<_> = cont.into_iter().filter(|c| c.score >= 0.25).collect();
    if !cont.is_empty() {
        map.insert("contains".to_string(), cont);
    }

    let pre = strategy_prefix(query, all_slugs, limit);
    let pre: Vec<_> = pre.into_iter().filter(|c| c.score >= 0.25).collect();
    if !pre.is_empty() {
        map.insert("prefix".to_string(), pre);
    }

    map
}

// ============================================================================
// Standalone scoring APIs (exposed to Lua)
// ============================================================================

/// Standalone suggest: expose suggest_all_strategies to Lua.
fn vault_suggest(
    lua: &Lua,
    (query, slugs, limit): (String, Vec<String>, usize),
) -> LuaResult<LuaValue> {
    let slug_refs: Vec<&str> = slugs.iter().map(|s| s.as_str()).collect();
    let result = suggest_all_strategies(&query, &slug_refs, limit);
    lua.to_value(&result)
}

#[derive(Debug, Deserialize)]
struct MergeCandidate {
    slug: String,
    #[serde(default)]
    tags: Vec<String>,
}

#[derive(Debug, Serialize)]
struct MergeScore {
    slug: String,
    score: f64,
    slug_sim: f64,
    tag_overlap: f64,
}

/// Compute tag Jaccard similarity: |A∩B| / |A∪B|.
fn tag_jaccard(tags_a: &[String], tags_b: &[String]) -> f64 {
    if tags_a.is_empty() && tags_b.is_empty() {
        return 0.0;
    }
    let set_a: std::collections::HashSet<&str> = tags_a.iter().map(|s| s.as_str()).collect();
    let set_b: std::collections::HashSet<&str> = tags_b.iter().map(|s| s.as_str()).collect();
    let intersection = set_a.intersection(&set_b).count() as f64;
    let union = set_a.union(&set_b).count() as f64;
    if union == 0.0 {
        0.0
    } else {
        intersection / union
    }
}

/// Best slug similarity score across all 4 strategies.
fn best_slug_similarity(query: &str, slug: &str) -> f64 {
    let q = query.to_lowercase();
    let qb = query.rsplit('/').next().unwrap_or(query).to_lowercase();
    let s = slug.to_lowercase();
    let sb = slug.rsplit('/').next().unwrap_or(slug).to_lowercase();

    // Jaro-Winkler
    let jw = jaro_winkler(&q, &s).max(jaro_winkler(&qb, &sb));

    // Levenshtein
    let lev = normalized_levenshtein(&q, &s).max(normalized_levenshtein(&qb, &sb));

    // Contains
    let contains = if s.contains(&q) || q.contains(&s) {
        q.len().min(s.len()) as f64 / q.len().max(s.len()) as f64
    } else if sb.contains(&qb) || qb.contains(&sb) {
        qb.len().min(sb.len()) as f64 / qb.len().max(sb.len()) as f64
    } else {
        0.0
    };

    // Prefix
    let prefix =
        if s.starts_with(&q) || q.starts_with(&s) || sb.starts_with(&qb) || qb.starts_with(&sb) {
            q.len().min(s.len()) as f64 / q.len().max(s.len()) as f64
        } else {
            0.0
        };

    jw.max(lev).max(contains).max(prefix)
}

/// Score merge candidates: slug similarity + tag Jaccard, combined.
/// Returns top N candidates sorted by combined score.
fn vault_score_merge_candidates<'a>(
    lua: &'a Lua,
    (query_slug, query_tags, candidates_val, limit): (String, Vec<String>, LuaValue<'a>, usize),
) -> LuaResult<LuaValue<'a>> {
    // Deserialize candidates from Lua table
    let candidates: Vec<MergeCandidate> = lua.from_value(candidates_val)?;

    // Score in parallel with rayon
    let mut scored: Vec<MergeScore> = candidates
        .par_iter()
        .map(|c| {
            let slug_sim = best_slug_similarity(&query_slug, &c.slug);
            let tag_overlap = tag_jaccard(&query_tags, &c.tags);
            let score = 0.5 * slug_sim + 0.5 * tag_overlap;
            MergeScore {
                slug: c.slug.clone(),
                score,
                slug_sim,
                tag_overlap,
            }
        })
        .collect();

    // Sort descending by score, filter low scores
    scored.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    scored.retain(|s| s.score > 0.05);
    scored.truncate(limit);

    lua.to_value(&scored)
}

/// Build wikilinks map WITHOUT computing fuzzy suggestions for unresolved links.
/// Much faster than `build_wikilinks_map` — suitable for display/counting use cases
/// (e.g. telescope picker link stats) where suggestions aren't needed.
fn build_wikilinks_map_no_suggest(
    notes: &[ParsedNote],
    root: &str,
) -> HashMap<String, WikilinkData> {
    let mut wikilinks_map: HashMap<String, WikilinkData> = HashMap::new();

    for note in notes {
        insert_note_wikilinks_no_suggest(&mut wikilinks_map, note, root);
    }

    wikilinks_map
}

fn build_wikilinks_map(notes: &[ParsedNote], root: &str) -> HashMap<String, WikilinkData> {
    let mut wikilinks_map: HashMap<String, WikilinkData> = HashMap::new();

    // Collect all known slugs for resolution and suggestion
    let slugs_set: HashMap<String, bool> = notes
        .iter()
        .map(|note| (path_to_slug(&note.path, root), true))
        .collect();

    // Build basename → slug index for Obsidian-style resolution
    let mut basename_to_slug: HashMap<String, String> = HashMap::new();
    for slug in slugs_set.keys() {
        let basename = slug.rsplit('/').next().unwrap_or(slug).to_string();
        basename_to_slug
            .entry(basename)
            .or_insert_with(|| slug.clone());
    }

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
                    suggestions: HashMap::new(),
                    embedded_count: 0,
                });

            entry.count += 1;
            if link_item.embedded {
                entry.embedded = true;
                entry.embedded_count += 1;
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

    // Post-process: for each unresolved wikilink, compute Jaro-Winkler suggestions.
    // A wikilink is "unresolved" if its stem doesn't match any slug (exact or basename).
    let all_slugs: Vec<&str> = slugs_set.keys().map(|s| s.as_str()).collect();

    // Collect unresolved stems first, then compute suggestions in parallel
    let unresolved_stems: Vec<String> = wikilinks_map
        .keys()
        .filter(|stem| {
            // Check exact slug match
            if slugs_set.contains_key(*stem) {
                return false;
            }
            // Check basename match
            let basename = stem.rsplit('/').next().unwrap_or(stem);
            if basename_to_slug.contains_key(basename) {
                return false;
            }
            true
        })
        .cloned()
        .collect();

    let suggestions_map: Vec<(String, HashMap<String, Vec<SuggestionCandidate>>)> =
        unresolved_stems
            .par_iter()
            .map(|stem| {
                let strategies = suggest_all_strategies(stem, &all_slugs, 5);
                (stem.clone(), strategies)
            })
            .collect();

    for (stem, suggestions) in suggestions_map {
        if let Some(entry) = wikilinks_map.get_mut(&stem) {
            entry.suggestions = suggestions;
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

fn build_lines_map(notes: &[ParsedNote], root: &str) -> HashMap<String, LineData> {
    let mut lines_map: HashMap<String, LineData> = HashMap::new();

    for note in notes {
        let slug = path_to_slug(&note.path, root);

        for line_item in &note.lines {
            let entry = lines_map
                .entry(line_item.content.clone())
                .or_insert_with(|| LineData {
                    content: line_item.content.clone(),
                    count: 0,
                    sources: HashMap::new(),
                });

            entry.count += 1;
            entry
                .sources
                .entry(slug.clone())
                .or_insert_with(HashMap::new)
                .insert(
                    line_item.line,
                    SourceOccurrence {
                        lnum: line_item.line,
                        line: None,
                        col: Some(1),
                        end_lnum: Some(line_item.line),
                        end_col: None,
                    },
                );
        }
    }

    lines_map
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

// ============================================================================
// Base File Scanning (.base YAML files for Obsidian Bases)
// ============================================================================

#[derive(Debug, Serialize)]
struct BaseFile {
    path: String,
    relpath: String,
    name: String,
    filters: Option<serde_json::Value>,
    formulas: Option<serde_json::Value>,
    properties: Option<serde_json::Value>,
    views: Option<serde_json::Value>,
}

/// Convert a serde_yaml::Value to serde_json::Value for mlua serialization.
fn yaml_to_json(yaml: serde_yaml::Value) -> serde_json::Value {
    match yaml {
        serde_yaml::Value::Null => serde_json::Value::Null,
        serde_yaml::Value::Bool(b) => serde_json::Value::Bool(b),
        serde_yaml::Value::Number(n) => {
            if let Some(i) = n.as_i64() {
                serde_json::Value::Number(i.into())
            } else if let Some(u) = n.as_u64() {
                serde_json::Value::Number(u.into())
            } else if let Some(f) = n.as_f64() {
                serde_json::Number::from_f64(f)
                    .map(serde_json::Value::Number)
                    .unwrap_or(serde_json::Value::Null)
            } else {
                serde_json::Value::Null
            }
        }
        serde_yaml::Value::String(s) => serde_json::Value::String(s),
        serde_yaml::Value::Sequence(seq) => {
            serde_json::Value::Array(seq.into_iter().map(yaml_to_json).collect())
        }
        serde_yaml::Value::Mapping(map) => {
            let mut obj = serde_json::Map::new();
            for (k, v) in map {
                let key = match k {
                    serde_yaml::Value::String(s) => s,
                    serde_yaml::Value::Number(n) => n.to_string(),
                    serde_yaml::Value::Bool(b) => b.to_string(),
                    _ => continue,
                };
                obj.insert(key, yaml_to_json(v));
            }
            serde_json::Value::Object(obj)
        }
        serde_yaml::Value::Tagged(tagged) => yaml_to_json(tagged.value),
    }
}

/// Parse a single .base file and return its structured data.
fn parse_base_file(path: &Path, root: &str) -> Option<BaseFile> {
    let content = std::fs::read_to_string(path).ok()?;
    let yaml: serde_yaml::Value = serde_yaml::from_str(&content).ok()?;

    let mapping = yaml.as_mapping()?;

    let filters = mapping
        .get(&serde_yaml::Value::String("filters".to_string()))
        .map(|v| yaml_to_json(v.clone()));

    let formulas = mapping
        .get(&serde_yaml::Value::String("formulas".to_string()))
        .map(|v| yaml_to_json(v.clone()));

    let properties = mapping
        .get(&serde_yaml::Value::String("properties".to_string()))
        .map(|v| yaml_to_json(v.clone()));

    let views = mapping
        .get(&serde_yaml::Value::String("views".to_string()))
        .map(|v| yaml_to_json(v.clone()));

    let path_str = path.to_string_lossy().to_string();
    let relpath = path_to_relpath(&path_str, root);
    let name = path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_string();

    Some(BaseFile {
        path: path_str,
        relpath,
        name,
        filters,
        formulas,
        properties,
        views,
    })
}

/// Scan the vault directory for .base files and parse them in parallel.
fn scan_base_files(root: &str, ignore_patterns: Vec<String>, ext: &str) -> Vec<BaseFile> {
    let root_path = Path::new(root);
    if !root_path.exists() {
        return Vec::new();
    }

    let glob_set = build_ignore_set(ignore_patterns);
    let root_owned = root.to_string();

    WalkDir::new(root)
        .into_iter()
        .filter_entry(move |e| {
            if is_hidden(e) {
                return false;
            }
            let path = e.path();
            if let Ok(rel_path) = path.strip_prefix(root) {
                if glob_set.is_match(rel_path) {
                    return false;
                }
            }
            true
        })
        .par_bridge()
        .filter_map(|e| e.ok())
        .filter(|e| {
            e.path()
                .extension()
                .and_then(|x| x.to_str())
                .map_or(false, |x| {
                    let expected = ext.trim_start_matches('.');
                    x == expected
                })
        })
        .filter_map(|e| parse_base_file(e.path(), &root_owned))
        .collect()
}

fn vault_base_files(
    lua: &Lua,
    (root, ignores, ext): (String, Vec<String>, String),
) -> LuaResult<LuaValue> {
    let bases = scan_base_files(&root, ignores, &ext);
    lua.to_value(&bases)
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

fn run_scanner_cached<T, F>(
    lua: &Lua,
    (root, ignores): (String, Vec<String>),
    builder: F,
) -> LuaResult<LuaValue>
where
    T: Serialize,
    F: FnOnce(&[ParsedNote], &str) -> T,
{
    let notes = scan_all_notes_cached(&root, ignores, true).unwrap_or_default();
    let data = builder(&notes, &root);
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
            run_scanner_cached(lua, (root, ignores), build_tags_map)
        })?,
    )?;
    exports.set(
        "wikilinks",
        lua.create_function(|lua, (root, ignores): (String, Vec<String>)| {
            run_scanner_cached(lua, (root, ignores), build_wikilinks_map)
        })?,
    )?;
    exports.set(
        "tasks",
        lua.create_function(|lua, (root, ignores): (String, Vec<String>)| {
            run_scanner(lua, (root, ignores), build_tasks_map)
        })?,
    )?;
    exports.set(
        "lines",
        lua.create_function(|lua, (root, ignores): (String, Vec<String>)| {
            run_scanner_cached(lua, (root, ignores), build_lines_map)
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
            run_scanner_cached(lua, (root, ignores), build_properties_map)
        })?,
    )?;
    exports.set(
        "dirs",
        lua.create_function(|lua, (root, ignores): (String, Vec<String>)| {
            run_scanner(lua, (root, ignores), build_dirs_map)
        })?,
    )?;

    // wikilinks_no_suggest: same as wikilinks but skips fuzzy suggestion computation
    exports.set(
        "wikilinks_no_suggest",
        lua.create_function(|lua, (root, ignores): (String, Vec<String>)| {
            run_scanner_cached(lua, (root, ignores), build_wikilinks_map_no_suggest)
        })?,
    )?;

    // paths_and_wikilinks: single scan_all_notes call, returns both paths and wikilinks
    // (without suggestions). Avoids reading every file twice.
    exports.set(
        "paths_and_wikilinks",
        lua.create_function(
            |lua, (root, ignores): (String, Vec<String>)| -> LuaResult<LuaValue> {
                let notes = scan_all_notes(&root, ignores);
                let paths = build_paths_map(&notes, &root);
                let wikilinks = build_wikilinks_map_no_suggest(&notes, &root);

                let table = lua.create_table()?;
                table.set("paths", lua.to_value(&paths)?)?;
                table.set("wikilinks", lua.to_value(&wikilinks)?)?;
                Ok(LuaValue::Table(table))
            },
        )?,
    )?;

    // paths_and_wikilinks_cached: uses mtime-based incremental scan cache.
    // First call is same speed as paths_and_wikilinks. Subsequent calls only
    // re-parse files whose mtime changed — typically <100ms for a 10k note vault.
    exports.set(
        "paths_and_wikilinks_cached",
        lua.create_function(
            |lua,
             (root, ignores, known_generation): (String, Vec<String>, Option<u64>)|
             -> LuaResult<LuaValue> {
                let ignores_hash = hash_ignores(&ignores);
                scan_all_notes_cached(&root, ignores, false);

                let cache = SCAN_CACHE.lock().unwrap();
                let Some(sc) = cache.as_ref() else {
                    let empty_paths: HashMap<String, PathInfo> = HashMap::new();
                    let empty_wikilinks: HashMap<String, WikilinkData> = HashMap::new();
                    return cached_paths_and_wikilinks_response(
                        lua,
                        0,
                        true,
                        true,
                        Some(&empty_paths),
                        Some(&empty_wikilinks),
                        None,
                        None,
                        None,
                        None,
                    );
                };

                if sc.root != root || sc.ignores_hash != ignores_hash {
                    let empty_paths: HashMap<String, PathInfo> = HashMap::new();
                    let empty_wikilinks: HashMap<String, WikilinkData> = HashMap::new();
                    return cached_paths_and_wikilinks_response(
                        lua,
                        0,
                        true,
                        true,
                        Some(&empty_paths),
                        Some(&empty_wikilinks),
                        None,
                        None,
                        None,
                        None,
                    );
                }

                if known_generation == Some(sc.generation) {
                    return cached_paths_and_wikilinks_response(
                        lua,
                        sc.generation,
                        false,
                        false,
                        None,
                        None,
                        None,
                        None,
                        None,
                        None,
                    );
                }

                if known_generation == Some(sc.last_diff_from_generation) {
                    return cached_paths_and_wikilinks_response(
                        lua,
                        sc.generation,
                        true,
                        false,
                        None,
                        None,
                        Some(&sc.last_paths_updated),
                        Some(&sc.last_paths_removed),
                        Some(&sc.last_wikilinks_updated),
                        Some(&sc.last_wikilinks_removed),
                    );
                }

                cached_paths_and_wikilinks_response(
                    lua,
                    sc.generation,
                    true,
                    true,
                    Some(&sc.paths_map),
                    Some(&sc.wikilinks_map_no_suggest),
                    None,
                    None,
                    None,
                    None,
                )
            },
        )?,
    )?;

    // clear_cache: invalidate the incremental scan cache
    exports.set(
        "clear_cache",
        lua.create_function(|_, ()| -> LuaResult<()> {
            clear_scan_cache();
            Ok(())
        })?,
    )?;

    exports.set("scan", lua.create_function(vault_scan_raw)?)?;
    exports.set("base_files", lua.create_function(vault_base_files)?)?;

    // Scoring / suggestion APIs
    exports.set("suggest", lua.create_function(vault_suggest)?)?;
    exports.set(
        "score_merge_candidates",
        lua.create_function(vault_score_merge_candidates)?,
    )?;

    Ok(exports)
}
