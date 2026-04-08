local utils = require("vault.utils")
local config = require("vault.config")
local state = require("vault.core.state")

-- Load classes
local Tag = require("vault.tags.tag")
local Wikilink = require("vault.wikilinks.wikilink")
local Task = require("vault.tasks.task")
local Dir = require("vault.dirs.dir")
local Property = require("vault.properties.property")
local PropertyValue = require("vault.properties.property.value")

local log = require("vault.log").scope("scanner")
local progress = require("vault.progress")
local PROCESS_SAVE_DEPTH_KEY = "vault.process_save_depth"

---@class vault.Scanner
---@field paths fun(opts?: { ignore: boolean|string[] }): table<string, table>
---@field slugs fun(): table<string, string>
---@field tags fun(opts?: { ignore: boolean|string[] }): table<string, vault.Tag>
---@field wikilinks fun(opts?: { ignore: boolean|string[] }): table<string, vault.Wikilink>
---@field tasks fun(opts?: { ignore: boolean|string[] }): table<string, vault.Task>
---@field links fun(opts?: { ignore: boolean|string[] }): table
---@field fields fun(opts?: { ignore: boolean|string[] }): table
---@field properties fun(opts?: { ignore: boolean|string[] }): table<string, vault.Property>
---@field dirs fun(opts?: { ignore: boolean|string[] }): table<string, vault.Dir>
---@field lines fun(opts?: { ignore: boolean|string[] }): table<string, vault.Line>

---@type vault.Scanner
local Scanner = {}

function Scanner.invalidate_notes_cache()
    state.set_global_key("cache.notes.paths", nil)
    state.set_global_key("cache.notes.slugs", nil)
    state.set_global_key("cache.notes.basename_index", nil)
end

--- Helper to determine root and ignore patterns based on options
--- @param opts? { ignore: boolean|string[] }
--- @return string root, string[] ignores
local function get_scan_args(opts)
    opts = opts or {}
    local root = vim.fn.expand(config.options.root)
    local ignores

    if opts.ignore == false then
        -- User explicitly requested NO ignores (e.g. for a "find all" command)
        ignores = {}
    elseif type(opts.ignore) == "table" then
        -- User provided specific custom ignores for this scan
        ignores = opts.ignore
    else
        -- Default: Use the global config
        ignores = config.options.ignore or {}
    end

    return root, ignores
end

--- @param opts? { ignore: boolean|string[] }
--- @return table<string, table>
function Scanner.paths(opts)
    local core = require("vault_core")
    local root, ignores = get_scan_args(opts)

    local save_depth = tonumber(state.get_global_key(PROCESS_SAVE_DEPTH_KEY) or 0) or 0
    if save_depth > 0 then
        local cached = state.get_global_key("cache.notes.paths")
        if type(cached) == "table" then
            log.debug("Scanning notes: using cached paths during process save")
            return cached
        end
    end

    local handle = progress.start("Scanning notes", "Reading vault…")
    local map = core.paths(root, ignores)

    local count = 0
    for _ in pairs(map) do count = count + 1 end
    handle:finish(("%d notes"):format(count))

    if not opts then
        state.set_global_key("cache.notes.paths", map)
    end

    return map
end

--- @return table<string, string>
function Scanner.slugs()
    local core = require("vault_core")
    local root, ignores = get_scan_args()

    local handle = progress.start("Scanning slugs")
    local slugs = core.slugs(root, ignores)
    local count = 0
    for _ in pairs(slugs) do count = count + 1 end
    handle:finish(("%d slugs"):format(count))

    state.set_global_key("cache.notes.slugs", slugs)
    state.set_global_key("cache.notes.basename_index", nil)
    return slugs
end

--- @param opts? { ignore: boolean|string[] }
--- @return table<string, vault.Tag>
function Scanner.tags(opts)
    local core = require("vault_core")
    local root, ignores = get_scan_args(opts)

    local handle = progress.start("Scanning tags")
    local raw_tags = core.tags(root, ignores)

    -- Convert raw tag data to Tag objects
    local tags_map = {}
    for tag_name, tag_data in pairs(raw_tags) do
        tags_map[tag_name] = Tag({
            name = tag_data.name,
            root = tag_data.root,
            is_nested = tag_data.is_nested,
            sources = tag_data.sources,
            count = tag_data.count,
        })
    end

    local count = 0
    for _ in pairs(tags_map) do count = count + 1 end
    handle:finish(("%d tags"):format(count))

    return tags_map
end

--- @param opts? { ignore: boolean|string[] }
--- @return table<string, vault.Wikilink>
function Scanner.wikilinks(opts)
    local core = require("vault_core")
    local root, ignores = get_scan_args(opts)

    local handle = progress.start("Scanning wikilinks")
    local raw_wikilinks = core.wikilinks(root, ignores)

    -- Convert raw wikilink data to Wikilink objects
    local wikilinks_map = {}
    for stem, wikilink_data in pairs(raw_wikilinks) do
        -- Create wikilink with minimal data - it will resolve target on access
        local ok, wl = pcall(Wikilink, {
            raw = "[[" .. stem .. "]]",
            sources = wikilink_data.sources,
        })

        if not ok then
            -- Skip malformed wikilinks returned by the Rust scanner
            log.debug("Skipped malformed wikilink: [[%s]] — %s", stem, tostring(wl))
            goto continue
        end

        -- Copy additional data from Rust
        wl.data.stem = wikilink_data.stem
        wl.data.count = wikilink_data.count
        wl.data.embedded = wikilink_data.embedded
        wl.data.suggestions = wikilink_data.suggestions or {}

        wikilinks_map[wl.data.slug] = wl
        ::continue::
    end

    local wl_count = 0
    for _ in pairs(wikilinks_map) do wl_count = wl_count + 1 end
    handle:finish(("%d wikilinks"):format(wl_count))

    return wikilinks_map
end

--- @param opts? { ignore: boolean|string[] }
--- @return table<string, vault.Task>
function Scanner.tasks(opts)
    local core = require("vault_core")
    local root, ignores = get_scan_args(opts)

    local handle = progress.start("Scanning tasks")
    local raw_tasks = core.tasks(root, ignores)

    -- Convert raw task data to Task objects
    local tasks_map = {}
    for description, task_data in pairs(raw_tasks) do
        tasks_map[description] = Task({
            line = task_data.description or description,
            status = task_data.status,
            sources = task_data.sources,
        })
        tasks_map[description].data.count = task_data.count
    end

    local task_count = 0
    for _ in pairs(tasks_map) do task_count = task_count + 1 end
    handle:finish(("%d tasks"):format(task_count))

    return tasks_map
end

--- @param opts? { ignore: boolean|string[] }
--- @return table
function Scanner.links(opts)
    local core = require("vault_core")
    local root, ignores = get_scan_args(opts)

    local handle = progress.start("Scanning links")
    local result = core.links(root, ignores)
    local count = 0
    for _ in pairs(result) do count = count + 1 end
    handle:finish(("%d links"):format(count))

    return result
end

--- @param opts? { ignore: boolean|string[] }
--- @return table
function Scanner.fields(opts)
    local core = require("vault_core")
    local root, ignores = get_scan_args(opts)

    local handle = progress.start("Scanning fields")
    local result = core.fields(root, ignores)
    local count = 0
    for _ in pairs(result) do count = count + 1 end
    handle:finish(("%d fields"):format(count))

    return result
end

--- @param opts? { ignore: boolean|string[] }
--- @return table<string, vault.Property>
function Scanner.properties(opts)
    local core = require("vault_core")
    local root, ignores = get_scan_args(opts)

    local handle = progress.start("Scanning properties")
    local raw_properties = core.properties(root, ignores)

    -- Convert raw property data to Property objects with PropertyValue children
    local properties_map = {}
    for prop_name, prop_data in pairs(raw_properties) do
        local property = Property({
            name = prop_data.name,
            sources = prop_data.sources,
            count = prop_data.count,
            values = {},
        })

        -- Convert values to PropertyValue objects
        for value_name, value_data in pairs(prop_data.values) do
            property.data.values[value_name] = PropertyValue({
                name = value_data.name,
                count = value_data.count,
                sources = value_data.sources,
            })
        end

        properties_map[prop_name] = property
    end

    local prop_count = 0
    for _ in pairs(properties_map) do prop_count = prop_count + 1 end
    handle:finish(("%d properties"):format(prop_count))

    return properties_map
end

--- @param opts? { ignore: boolean|string[] }
--- @return table<string, vault.Dir>
function Scanner.dirs(opts)
    local core = require("vault_core")
    local root, ignores = get_scan_args(opts)

    local handle = progress.start("Scanning directories")
    local raw_dirs = core.dirs(root, ignores)

    -- Convert raw dir data to Dir objects
    local dirs_map = {}
    for relpath, _ in pairs(raw_dirs) do
        local path = utils.relpath_to_path(relpath)
        dirs_map[relpath] = Dir({
            path = path,
            relpath = relpath,
        })
    end

    local dir_count = 0
    for _ in pairs(dirs_map) do dir_count = dir_count + 1 end
    handle:finish(("%d directories"):format(dir_count))

    state.set_global_key("dirs", dirs_map)
    return dirs_map
end

--- Scan for .base files (Obsidian Bases) in the vault.
--- Returns raw parsed data from the Rust scanner (array of tables).
--- Each table has: path, relpath, name, filters, formulas, properties, views.
--- @param opts? { ignore: boolean|string[] }
--- @return table[] raw_bases
function Scanner.base_files(opts)
    local core = require("vault_core")
    local root, ignores = get_scan_args(opts)
    local ext = config.options.bases and config.options.bases.ext or ".base"

    local handle = progress.start("Scanning bases")
    local raw = core.base_files(root, ignores, ext)
    handle:finish(("%d bases"):format(#raw))

    if not opts then
        state.set_global_key("cache.bases.raw", raw)
    end

    return raw
end


--- Scan all vault notes for dash-prefixed lines using the Rust backend.
--- Returns a map keyed by line content, each value is a Line object.
--- @param opts? { ignore: boolean|string[] }
--- @return table<string, vault.Line>
function Scanner.lines(opts)
    local Line = require("vault.lines.line")
    local core = require("vault_core")
    local root, ignores = get_scan_args(opts)

    local handle = progress.start("Scanning lines")
    local lines_map = {} --- @type table<string, vault.Line>
    local raw_lines = core.lines(root, ignores)

    for content, line_data in pairs(raw_lines) do
        lines_map[content] = Line({
            content = line_data.content,
            sources = line_data.sources,
        })
    end

    local line_count = 0
    for _ in pairs(lines_map) do line_count = line_count + 1 end
    handle:finish(("%d unique lines"):format(line_count))

    return lines_map
end

--- Scan wikilinks WITHOUT computing fuzzy suggestions (faster).
--- Suitable for display/counting use cases (e.g. telescope picker link stats)
--- where suggestions aren't needed.
--- @param opts? { ignore: boolean|string[] }
--- @return table<string, vault.Wikilink>
function Scanner.wikilinks_no_suggest(opts)
    local core = require("vault_core")
    local root, ignores = get_scan_args(opts)

    local handle = progress.start("Scanning wikilinks (no suggest)")
    local raw_wikilinks = core.wikilinks_no_suggest(root, ignores)

    local wikilinks_map = {}
    for stem, wikilink_data in pairs(raw_wikilinks) do
        local ok, wl = pcall(Wikilink, {
            raw = "[[" .. stem .. "]]",
            sources = wikilink_data.sources,
        })

        if not ok then
            log.debug("Skipped malformed wikilink: [[%s]] — %s", stem, tostring(wl))
            goto continue
        end

        wl.data.stem = wikilink_data.stem
        wl.data.count = wikilink_data.count
        wl.data.embedded = wikilink_data.embedded
        wl.data.suggestions = {}

        wikilinks_map[wl.data.slug] = wl
        ::continue::
    end

    local wl_count = 0
    for _ in pairs(wikilinks_map) do wl_count = wl_count + 1 end
    handle:finish(("%d wikilinks"):format(wl_count))

    return wikilinks_map
end

--- Single-pass scan returning both paths and wikilinks (without suggestions).
--- Reads every .md file ONCE instead of twice when paths() and wikilinks()
--- are called separately.
--- @param opts? { ignore: boolean|string[] }
--- @return table<string, table> paths, table<string, vault.Wikilink> wikilinks_map
function Scanner.paths_and_wikilinks(opts)
    local core = require("vault_core")
    local root, ignores = get_scan_args(opts)

    local handle = progress.start("Scanning paths + wikilinks")
    local result = core.paths_and_wikilinks(root, ignores)

    local raw_paths = result.paths or {}
    local raw_wikilinks = result.wikilinks or {}

    -- Count paths
    local path_count = 0
    for _ in pairs(raw_paths) do path_count = path_count + 1 end

    -- Wrap wikilinks in Wikilink objects
    local wikilinks_map = {}
    for stem, wikilink_data in pairs(raw_wikilinks) do
        local ok, wl = pcall(Wikilink, {
            raw = "[[" .. stem .. "]]",
            sources = wikilink_data.sources,
        })

        if not ok then
            log.debug("Skipped malformed wikilink: [[%s]] — %s", stem, tostring(wl))
            goto continue
        end

        wl.data.stem = wikilink_data.stem
        wl.data.count = wikilink_data.count
        wl.data.embedded = wikilink_data.embedded
        wl.data.suggestions = {}

        wikilinks_map[wl.data.slug] = wl
        ::continue::
    end

    local wl_count = 0
    for _ in pairs(wikilinks_map) do wl_count = wl_count + 1 end
    handle:finish(("%d notes, %d wikilinks"):format(path_count, wl_count))

    return raw_paths, wikilinks_map
end

--- Single-pass cached scan returning both paths and wikilinks.
--- First call: full scan (~1.6s for 10k notes). Subsequent calls: incremental
--- mtime check, only re-parses changed files (~50ms for 10k notes, 0 changed).
--- @param opts? { ignore: boolean|string[] }
--- @return table<string, table> paths, table<string, vault.Wikilink> wikilinks_map
function Scanner.paths_and_wikilinks_cached(opts)
    local core = require("vault_core")
    local root, ignores = get_scan_args(opts)

    local handle = progress.start("Scanning paths + wikilinks (cached)")
    local result = core.paths_and_wikilinks_cached(root, ignores)

    local raw_paths = result.paths or {}
    local raw_wikilinks = result.wikilinks or {}

    local path_count = 0
    for _ in pairs(raw_paths) do path_count = path_count + 1 end

    local wikilinks_map = {}
    for stem, wikilink_data in pairs(raw_wikilinks) do
        local ok, wl = pcall(Wikilink, {
            raw = "[[" .. stem .. "]]",
            sources = wikilink_data.sources,
        })

        if not ok then
            log.debug("Skipped malformed wikilink: [[%s]] — %s", stem, tostring(wl))
            goto continue
        end

        wl.data.stem = wikilink_data.stem
        wl.data.count = wikilink_data.count
        wl.data.embedded = wikilink_data.embedded
        wl.data.suggestions = {}

        wikilinks_map[wl.data.slug] = wl
        ::continue::
    end

    local wl_count = 0
    for _ in pairs(wikilinks_map) do wl_count = wl_count + 1 end
    handle:finish(("%d notes, %d wikilinks"):format(path_count, wl_count))

    return raw_paths, wikilinks_map
end

--- Clear the Rust-side incremental scan cache.
--- Call this when the watcher detects filesystem changes or the user
--- explicitly requests a refresh.
--- @return nil
function Scanner.clear_rust_cache()
    local ok, core = pcall(require, "vault_core")
    if ok and core.clear_cache then
        core.clear_cache()
    end
end

function Scanner.refresh()
    -- clear cache and state
    Scanner.clear_rust_cache()
    state.clear_all()
end
-- refresh all data

return Scanner
