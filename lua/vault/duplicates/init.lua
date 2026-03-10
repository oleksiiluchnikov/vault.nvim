local M = {}

local config = require("vault.config")
local log = require("vault.log").scope("duplicates")
local state_store = require("vault.core.state")
local utils = require("vault.utils")
local merge = require("vault.merge")

local REVIEW_STATE_KEY = "vault.duplicates.review"

--- Duplicate-detection kind discriminator.
---@alias vault.duplicates.Kind string

---@class vault.duplicates.Item
---@field a_path vault.path
---@field b_path vault.path
---@field a_rel vault.relpath
---@field b_rel vault.relpath
---@field kind vault.duplicates.Kind
---@field recommended "a"|"b"
---@field recommended_reason string
---@field score number
---@field original_unique_lines integer
---@field copy_unique_lines integer
---@field related_score? number
---@field related_slug_sim? number
---@field related_tag_overlap? number
---@field related_bucket? string

---@class vault.duplicates.ReviewPlan
---@field which "a"|"b"
---@field target_path vault.path
---@field source_path vault.path
---@field body_strategy string
---@field plan vault.merge.Plan|nil
---@field error string|nil

---@class vault.duplicates.FileAnalysis
---@field frontmatter table<string, boolean>
---@field body string
---@field lines table<string, boolean>

---@class vault.duplicates.PresetSpec
---@field description? string
---@field root? vault.path
---@field dirs? vault.relpath[]
---@field tags? string[]
---@field kind? vault.duplicates.Kind[]

---@class vault.duplicates.ResolvedPreset
---@field name string
---@field description string
---@field root vault.path|nil
---@field dirs vault.relpath[]
---@field tags string[]
---@field kind_tokens vault.duplicates.Kind[]
---@field summary? string

local function read_text(path)
    local ok, lines = pcall(vim.fn.readfile, path)
    if not ok then
        return nil
    end
    return table.concat(lines, "\n")
end

---@return string[]
local function stem_suffix_patterns()
    local configured = config.options.duplicates and config.options.duplicates.stem_suffix_patterns
        or {}
    if type(configured) ~= "table" or vim.tbl_isempty(configured) then
        return { [[\s\+\d\+$]], [[_\d\+$]] }
    end
    return configured
end

---@param value string
---@return string
local function strip_copy_suffix(value)
    local trimmed = vim.trim(value)
    local normalized = trimmed
    for _, pattern in ipairs(stem_suffix_patterns()) do
        if type(pattern) == "string" and pattern ~= "" then
            normalized = vim.fn.substitute(normalized, pattern, "", "")
        end
    end
    normalized = vim.trim(normalized)
    return normalized ~= "" and normalized or trimmed
end

local function split_frontmatter(text)
    local lines = vim.split(text:gsub("\r\n", "\n"), "\n", { plain = true })
    if #lines >= 3 and lines[1] == "---" then
        local frontmatter = {}
        for i = 2, #lines do
            if lines[i] == "---" then
                local body = {}
                for j = i + 1, #lines do
                    table.insert(body, lines[j])
                end
                return frontmatter, body
            end
            table.insert(frontmatter, lines[i])
        end
    end
    return {}, lines
end

local function normalize_frontmatter_line(line)
    local stripped = line:gsub("%s+$", "")
    if stripped == "" then
        return nil
    end
    if not stripped:find(":", 1, true) then
        return stripped
    end
    local key, value = stripped:match("^([%w_%-]+):%s*(.*)$")
    if not key then
        return stripped
    end
    local ignored = config.options.duplicates and config.options.duplicates.ignored_frontmatter_keys
        or {}
    for _, ignored_key in ipairs(ignored) do
        if key == ignored_key then
            return nil
        end
    end
    local normalizers = config.options.duplicates
            and config.options.duplicates.frontmatter_normalizers
        or {}
    local normalizer = normalizers[key]
    if type(normalizer) == "function" then
        local ok, normalized = pcall(normalizer, value, key)
        if ok and type(normalized) == "string" then
            value = normalized
        elseif not ok then
            log.warn("duplicates frontmatter_normalizers.%s failed: %s", key, tostring(normalized))
        end
    end
    if key == "title" then
        local quote = ""
        if value:match('^".*"$') then
            quote = '"'
            value = value:sub(2, -2)
        elseif value:match("^'.*'$") then
            quote = "'"
            value = value:sub(2, -2)
        end
        value = strip_copy_suffix(value)
        value = quote ~= "" and (quote .. value .. quote) or value
    end
    return string.format("%s: %s", key, vim.trim(value))
end

local function normalize_frontmatter(lines)
    local result = {}
    for _, line in ipairs(lines) do
        local normalized = normalize_frontmatter_line(line)
        if normalized then
            result[normalized] = true
        end
    end
    return result
end

local function normalize_body(path, lines)
    local normalized = {}
    for _, line in ipairs(lines) do
        local trimmed = line:gsub("%s+$", "")
        table.insert(normalized, trimmed)
    end
    for i, line in ipairs(normalized) do
        if line:match("%S") then
            if line:match("^# ") then
                local stem = vim.fn.fnamemodify(path, ":t:r")
                local base = strip_copy_suffix(stem)
                normalized[i] = "# " .. base
            end
            break
        end
    end
    return vim.trim(table.concat(normalized, "\n"))
end

local function meaningful_line_set(text)
    local result = {}
    for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
        local trimmed = vim.trim(line)
        if trimmed ~= "" then
            result[trimmed] = true
        end
    end
    return result
end

---@param path string
---@param cache table<string, vault.duplicates.FileAnalysis>
---@return vault.duplicates.FileAnalysis|nil
local function analyze_file(path, cache)
    local cached = cache[path]
    if cached then
        return cached
    end
    if vim.fn.filereadable(path) == 0 then
        return nil
    end

    local text = read_text(path)
    if not text then
        return nil
    end

    local frontmatter_lines, body_lines = split_frontmatter(text)
    local analysis = {
        frontmatter = normalize_frontmatter(frontmatter_lines),
        body = normalize_body(path, body_lines),
        lines = {},
    }
    analysis.lines = meaningful_line_set(analysis.body)
    cache[path] = analysis
    return analysis
end

local function set_diff_count(a, b)
    local count = 0
    for line, _ in pairs(a) do
        if not b[line] then
            count = count + 1
        end
    end
    return count
end

local function path_kind_weight(path)
    local rel = utils.path_to_relpath(path)
    local preferred = config.options.duplicates and config.options.duplicates.preferred_dirs or {}
    local total = #preferred
    for index, dir in ipairs(preferred) do
        if rel:match("^" .. vim.pesc(dir) .. "/") or rel == dir .. ".md" then
            return total - index + 2
        end
    end
    return 1
end

local function has_copy_suffix(path)
    local stem = vim.fn.fnamemodify(path, ":t:r")
    return strip_copy_suffix(stem) ~= vim.trim(stem)
end

local function order_pair_paths(a_path, b_path)
    local a_copy = has_copy_suffix(a_path)
    local b_copy = has_copy_suffix(b_path)
    if a_copy ~= b_copy then
        return a_copy and b_path or a_path, a_copy and a_path or b_path
    end
    if a_path <= b_path then
        return a_path, b_path
    end
    return b_path, a_path
end

---@param item vault.duplicates.Item
---@return string
local function item_key(item)
    return item.a_path .. "\0" .. item.b_path
end

---@param items vault.duplicates.Item[]
---@param current_key string|nil
---@return integer
local function find_item_index(items, current_key)
    if not current_key or current_key == "" then
        return 1
    end
    for index, item in ipairs(items) do
        if item_key(item) == current_key then
            return index
        end
    end
    return 1
end

---@param paths table<string, table>
---@return table<string, integer>
local function build_stem_counts(paths)
    local counts = {}
    for _, entry in pairs(paths or {}) do
        local stem = vim.fn.fnamemodify(entry.path, ":t:r")
        counts[stem] = (counts[stem] or 0) + 1
    end
    return counts
end

local KIND_FILTER_ALIASES = {
    exact = { "exact" },
    a_subset = { "a_subset" },
    b_subset = { "b_subset" },
    metadata = { "metadata" },
    ["metadata-only"] = { "metadata" },
    subset = { "a_subset", "b_subset" },
    body = { "a_subset", "b_subset", "divergent" },
    changed = { "a_subset", "b_subset", "divergent" },
    ["body-differs"] = { "a_subset", "b_subset", "divergent" },
    divergent = { "divergent" },
    same = { "exact", "metadata" },
    all = { "exact", "metadata", "a_subset", "b_subset", "divergent" },
}

local RELATED_FILTER_ALIASES = {
    likely = { "likely" },
    maybe = { "maybe" },
    weak = { "weak" },
    all = { "likely", "maybe", "weak" },
}

local RELATED_BUCKET_ORDER = {
    likely = 1,
    maybe = 2,
    weak = 3,
}

local NOISY_RELATED_TOKENS = {
    ["and"] = true,
    ["for"] = true,
    ["the"] = true,
    ["with"] = true,
    ["from"] = true,
    ["into"] = true,
    ["note"] = true,
}

---@return table<string, vault.duplicates.PresetSpec>
local function duplicate_presets()
    local configured = config.options.duplicates and config.options.duplicates.presets or {}
    if type(configured) ~= "table" then
        return {}
    end
    return configured
end

---@param values string[]|nil
---@return string[]
local function sorted_string_list(values)
    local result = vim.deepcopy(values or {})
    table.sort(result)
    return result
end

---@param tokens string[]|nil
---@return table<string, boolean>|nil, string|nil
local function resolve_kind_filter(tokens)
    if not tokens or vim.tbl_isempty(tokens) then
        return nil, nil
    end

    local kinds = {}
    for _, token in ipairs(tokens) do
        local alias = KIND_FILTER_ALIASES[string.lower(token)]
        if not alias then
            return nil, string.format("Unknown duplicate kind filter: %s", token)
        end
        for _, kind in ipairs(alias) do
            kinds[kind] = true
        end
    end

    return kinds, nil
end

---@param tokens string[]|nil
---@return table<string, boolean>|nil, string|nil
local function resolve_related_filter(tokens)
    if not tokens or vim.tbl_isempty(tokens) then
        return nil, nil
    end

    local buckets = {}
    for _, token in ipairs(tokens) do
        local alias = RELATED_FILTER_ALIASES[string.lower(token)]
        if not alias then
            return nil, string.format("Unknown related duplicate filter: %s", token)
        end
        for _, bucket in ipairs(alias) do
            buckets[bucket] = true
        end
    end

    return buckets, nil
end

---@param name string
---@return vault.duplicates.ResolvedPreset|nil, string|nil
local function resolve_preset(name)
    local spec = duplicate_presets()[name]
    if type(spec) ~= "table" then
        return nil, string.format("Unknown duplicate preset: %s", name)
    end

    local dirs = sorted_string_list(spec.dirs)
    local tags = sorted_string_list(spec.tags)
    local kind_tokens = sorted_string_list(spec.kind)
    if not vim.tbl_isempty(kind_tokens) then
        local _, err = resolve_kind_filter(kind_tokens)
        if err then
            return nil, string.format("Invalid duplicate preset %s: %s", name, err)
        end
    end

    return {
        name = name,
        description = spec.description or "",
        root = spec.root,
        dirs = dirs,
        tags = tags,
        kind_tokens = kind_tokens,
    },
        nil
end

---@return string[]
local function preset_names()
    local names = vim.tbl_keys(duplicate_presets())
    table.sort(names)
    return names
end

---@param preset vault.duplicates.ResolvedPreset
---@return string
local function preset_summary(preset)
    local parts = {}
    if not vim.tbl_isempty(preset.kind_tokens) then
        parts[#parts + 1] = "kind: " .. table.concat(preset.kind_tokens, ", ")
    end
    if not vim.tbl_isempty(preset.dirs) then
        parts[#parts + 1] = "dir: " .. table.concat(preset.dirs, ", ")
    end
    if not vim.tbl_isempty(preset.tags) then
        parts[#parts + 1] = "tags: " .. table.concat(preset.tags, ", ")
    end
    if preset.root and preset.root ~= "" then
        parts[#parts + 1] = "root: " .. preset.root
    end
    return #parts > 0 and table.concat(parts, "  |  ") or "full vault review"
end

---@param path string|nil
---@return string
local function resolve_root_path(path)
    local absolute_root = path
    if not absolute_root or absolute_root == "" then
        absolute_root = require("vault.config").options.root
    elseif not absolute_root:match("^/") then
        if absolute_root == "vault" then
            absolute_root = require("vault.config").options.root
        else
            absolute_root = utils.relpath_to_path(absolute_root)
        end
    end
    return vim.fn.fnamemodify(absolute_root, ":p")
end

---@param absolute_root string
---@param path_index table<string, table>
---@return string[]
local function collect_paths_under_root(absolute_root, path_index)
    local paths = {}
    for _, entry in pairs(path_index or {}) do
        local path = type(entry) == "table" and entry.path or nil
        if type(path) == "string" then
            local absolute_path = vim.fn.fnamemodify(path, ":p")
            if absolute_path:sub(1, #absolute_root) == absolute_root then
                paths[#paths + 1] = absolute_path
            end
        end
    end
    table.sort(paths)
    return paths
end

---@param path string
---@return string
local function normalized_related_stem(path)
    local stem = strip_copy_suffix(vim.fn.fnamemodify(path, ":t:r")):lower()
    stem = stem:gsub("[^%w]+", " ")
    return vim.trim(stem)
end

---@param path string
---@return string[]
local function related_tokens(path)
    local seen = {}
    local tokens = {}
    for token in normalized_related_stem(path):gmatch("[%w_]+") do
        if #token >= 3 and not NOISY_RELATED_TOKENS[token] and not seen[token] then
            seen[token] = true
            tokens[#tokens + 1] = token
        end
    end
    return tokens
end

---@param path string
---@param excluded string[]
---@return boolean
local function path_is_excluded_from_dirs(path, excluded)
    local relpath = utils.path_to_relpath(path)
    for _, dir in ipairs(excluded) do
        if relpath == dir or relpath:sub(1, #dir + 1) == (dir .. "/") then
            return true
        end
    end
    return false
end

---@param path string
---@param excluded string[]
---@return boolean
local function path_is_excluded_from_files(path, excluded)
    local name = vim.fn.fnamemodify(path, ":t")
    for _, filename in ipairs(excluded) do
        if name == filename then
            return true
        end
    end
    return false
end

---@param path string
---@param patterns string[]
---@return boolean
local function path_is_excluded_from_patterns(path, patterns)
    local relpath = utils.path_to_relpath(path)
    local name = vim.fn.fnamemodify(path, ":t")
    for _, pattern in ipairs(patterns) do
        if type(pattern) == "string" and pattern ~= "" then
            if vim.fn.match(relpath, pattern) >= 0 or vim.fn.match(name, pattern) >= 0 then
                return true
            end
        end
    end
    return false
end

---@param path string
---@return boolean
local function review_path_is_excluded(path)
    local excluded = config.options.duplicates and config.options.duplicates.review_excluded_dirs
        or {}
    local files = config.options.duplicates and config.options.duplicates.review_excluded_files
        or {}
    local patterns = config.options.duplicates
            and config.options.duplicates.review_excluded_patterns
        or {}
    return path_is_excluded_from_dirs(path, excluded)
        or path_is_excluded_from_files(path, files)
        or path_is_excluded_from_patterns(path, patterns)
end

---@param path string
---@return boolean
local function related_path_is_excluded(path)
    local excluded = config.options.duplicates and config.options.duplicates.related_excluded_dirs
        or {}
    local files = config.options.duplicates and config.options.duplicates.related_excluded_files
        or {}
    local patterns = config.options.duplicates
            and config.options.duplicates.related_excluded_patterns
        or {}
    return path_is_excluded_from_dirs(path, excluded)
        or path_is_excluded_from_files(path, files)
        or path_is_excluded_from_patterns(path, patterns)
end

---@param tokens_a string[]
---@param tokens_b string[]
---@param shared_count integer
---@return boolean
local function should_score_related_pair(tokens_a, tokens_b, shared_count)
    if shared_count >= 2 then
        return true
    end
    if shared_count <= 0 then
        return false
    end
    if math.min(#tokens_a, #tokens_b) <= 1 then
        local a = tokens_a[1] or ""
        local b = tokens_b[1] or ""
        return #a >= 6 and a == b
    end
    return false
end

---@param slug_sim number
---@return string|nil
local function related_bucket_for(slug_sim)
    if slug_sim >= 0.92 then
        return "likely"
    end
    if slug_sim >= 0.82 then
        return "maybe"
    end
    if slug_sim >= 0.7 then
        return "weak"
    end
    return nil
end

---@param item vault.duplicates.Item
---@param opts? { allowed_paths?: table<string, boolean>, path_filters?: table<string, table<string, boolean>>, kinds?: table<string, boolean>, related_buckets?: table<string, boolean> }
---@return boolean
local function item_matches_filters(item, opts)
    opts = opts or {}
    if
        opts.allowed_paths
        and not opts.allowed_paths[item.a_path]
        and not opts.allowed_paths[item.b_path]
    then
        return false
    end
    if opts.path_filters then
        for _, allowed in pairs(opts.path_filters) do
            if allowed and not allowed[item.a_path] and not allowed[item.b_path] then
                return false
            end
        end
    end
    if opts.kinds and not opts.kinds[item.kind] then
        return false
    end
    if opts.related_buckets and not opts.related_buckets[item.related_bucket or ""] then
        return false
    end
    return true
end

---@param session table
---@param source_path string
---@param target_path string
---@return integer
local function estimate_rewrite_count(session, source_path, target_path)
    local wikilinks = session.wikilinks or {}
    local old_slug = utils.path_to_slug(source_path)
    local old_stem = vim.fn.fnamemodify(source_path, ":t:r")
    local new_stem = vim.fn.fnamemodify(target_path, ":t:r")
    local affected = {}

    local function collect(slug)
        local wl = wikilinks[slug]
        if not wl or type(wl.data.sources) ~= "table" then
            return
        end
        for source_slug, _ in pairs(wl.data.sources) do
            affected[source_slug] = true
        end
    end

    collect(old_slug)
    if
        (session.stem_counts or {})[old_stem] == 1
        and old_stem ~= old_slug
        and old_stem ~= new_stem
    then
        collect(old_stem)
    end

    local count = 0
    for _ in pairs(affected) do
        count = count + 1
    end
    return count
end

---@param items vault.duplicates.Item[]
---@param blocked_paths table<string, boolean>
---@return vault.duplicates.Item[]
local function filter_items(items, blocked_paths)
    if not blocked_paths or vim.tbl_isempty(blocked_paths) then
        return items
    end
    local filtered = {}
    for _, item in ipairs(items) do
        if not blocked_paths[item.a_path] and not blocked_paths[item.b_path] then
            filtered[#filtered + 1] = item
        end
    end
    return filtered
end

---@param winner "a"|"b"
---@return string
local function winner_label(winner)
    return winner == "a" and "A" or "B"
end

local function choose_recommended(a_path, b_path, a_frontmatter, b_frontmatter, a_lines, b_lines)
    local a_weight = path_kind_weight(a_path)
    local b_weight = path_kind_weight(b_path)
    if a_weight ~= b_weight then
        local winner = a_weight > b_weight and "a" or "b"
        return winner, string.format("%s is in the preferred folder", winner_label(winner))
    end
    local a_meta = vim.tbl_count(a_frontmatter)
    local b_meta = vim.tbl_count(b_frontmatter)
    if a_meta ~= b_meta then
        local winner = a_meta >= b_meta and "a" or "b"
        return winner, string.format("%s keeps richer frontmatter", winner_label(winner))
    end
    local a_count = vim.tbl_count(a_lines)
    local b_count = vim.tbl_count(b_lines)
    if a_count ~= b_count then
        local winner = a_count >= b_count and "a" or "b"
        return winner, string.format("%s keeps more unique body lines", winner_label(winner))
    end
    local winner = a_path <= b_path and "a" or "b"
    return winner, string.format("%s wins the stable path tiebreak", winner_label(winner))
end

---@param a_path string
---@param b_path string
---@param analysis_cache table<string, vault.duplicates.FileAnalysis>
---@return vault.duplicates.Item|nil
local function classify_pair(a_path, b_path, analysis_cache)
    local a_analysis = analyze_file(a_path, analysis_cache)
    local b_analysis = analyze_file(b_path, analysis_cache)
    if not a_analysis or not b_analysis then
        return nil
    end

    local a_frontmatter = a_analysis.frontmatter
    local b_frontmatter = b_analysis.frontmatter
    local a_body = a_analysis.body
    local b_body = b_analysis.body
    local a_lines = a_analysis.lines
    local b_lines = b_analysis.lines

    local kind
    if a_body == b_body then
        if vim.deep_equal(a_frontmatter, b_frontmatter) then
            kind = "exact"
        else
            kind = "metadata"
        end
    else
        local a_subset = true
        for line, _ in pairs(a_lines) do
            if not b_lines[line] then
                a_subset = false
                break
            end
        end
        local b_subset = true
        for line, _ in pairs(b_lines) do
            if not a_lines[line] then
                b_subset = false
                break
            end
        end
        if a_subset and not b_subset then
            kind = "a_subset"
        elseif b_subset and not a_subset then
            kind = "b_subset"
        else
            kind = "divergent"
        end
    end

    local recommended, recommended_reason =
        choose_recommended(a_path, b_path, a_frontmatter, b_frontmatter, a_lines, b_lines)
    local score = 1.0
    if kind == "divergent" then
        local overlap = 0
        for line, _ in pairs(a_lines) do
            if b_lines[line] then
                overlap = overlap + 1
            end
        end
        local denom = math.max(vim.tbl_count(a_lines), vim.tbl_count(b_lines), 1)
        score = overlap / denom
    end

    return {
        a_path = a_path,
        b_path = b_path,
        a_rel = utils.path_to_relpath(a_path),
        b_rel = utils.path_to_relpath(b_path),
        kind = kind,
        recommended = recommended,
        recommended_reason = recommended_reason,
        score = score,
        original_unique_lines = set_diff_count(a_lines, b_lines),
        copy_unique_lines = set_diff_count(b_lines, a_lines),
    }
end

local function dedupe_key(a_path, b_path)
    if a_path < b_path then
        return a_path .. "\0" .. b_path
    end
    return b_path .. "\0" .. a_path
end

---@param root string|nil
---@param path_index? table<string, table>
---@param opts? { allowed_paths?: table<string, boolean>, path_filters?: table<string, table<string, boolean>>, kinds?: table<string, boolean> }
---@return vault.duplicates.Item[]
function M.scan(root, path_index, opts)
    opts = opts or {}
    local absolute_root = resolve_root_path(root)

    local scanner = require("vault.scanner")
    path_index = path_index or scanner.paths()
    local paths = collect_paths_under_root(absolute_root, path_index)

    local by_stem = {}
    for _, path in ipairs(paths) do
        if review_path_is_excluded(path) then
            goto continue
        end
        local stem = strip_copy_suffix(vim.fn.fnamemodify(path, ":t:r")):lower()
        by_stem[stem] = by_stem[stem] or {}
        table.insert(by_stem[stem], path)
        ::continue::
    end

    local items = {}
    local seen = {}
    local analysis_cache = {}
    for _, group in pairs(by_stem) do
        if #group > 1 then
            for i = 1, #group do
                for j = i + 1, #group do
                    local a_path, b_path = group[i], group[j]
                    local key = dedupe_key(a_path, b_path)
                    if not seen[key] then
                        seen[key] = true
                        local left_path, right_path = order_pair_paths(a_path, b_path)
                        local item = classify_pair(left_path, right_path, analysis_cache)
                        if item and item_matches_filters(item, opts) then
                            table.insert(items, item)
                        end
                    end
                end
            end
        end
    end

    local order = {
        exact = 1,
        metadata = 2,
        a_subset = 3,
        b_subset = 4,
        divergent = 5,
    }
    table.sort(items, function(a, b)
        local oa = order[a.kind] or 99
        local ob = order[b.kind] or 99
        if oa ~= ob then
            return oa < ob
        end
        if a.recommended ~= b.recommended then
            return a.recommended == "a"
        end
        return a.a_rel < b.a_rel
    end)
    return items
end

---@class vault.duplicates.RelatedEntry
---@field path string
---@field slug string
---@field tags string[]
---@field tokens string[]
---@field stem string

---@param root string|nil
---@param path_index? table<string, table>
---@param opts? { allowed_paths?: table<string, boolean>, path_filters?: table<string, table<string, boolean>>, kinds?: table<string, boolean>, related_buckets?: table<string, boolean> }
---@return vault.duplicates.Item[]
function M.scan_related(root, path_index, opts)
    opts = opts or {}
    local absolute_root = resolve_root_path(root)
    local scanner = require("vault.scanner")
    path_index = path_index or scanner.paths()
    local paths = collect_paths_under_root(absolute_root, path_index)
    local notes_map = require("vault.notes")().map or {}
    local tags_by_path = {}
    for _, note in pairs(notes_map) do
        if note and note.data and type(note.data.path) == "string" then
            tags_by_path[note.data.path] = vim.tbl_keys(note.data.tags or {})
        end
    end

    ---@type vault.duplicates.RelatedEntry[]
    local entries = {}
    local token_index = {}
    for _, path in ipairs(paths) do
        if related_path_is_excluded(path) then
            goto continue
        end

        local tokens = related_tokens(path)
        if #tokens > 0 then
            local entry = {
                path = path,
                slug = utils.path_to_slug(path),
                tags = tags_by_path[path] or {},
                tokens = tokens,
                stem = normalized_related_stem(path),
            }
            local entry_index = #entries + 1
            entries[entry_index] = entry
            for _, token in ipairs(tokens) do
                token_index[token] = token_index[token] or {}
                token_index[token][#token_index[token] + 1] = entry_index
            end
        end
        ::continue::
    end

    local analysis_cache = {}
    local seen = {}
    local items = {}
    local scoring = require("vault.scoring")
    for index, entry in ipairs(entries) do
        local shared = {}
        for _, token in ipairs(entry.tokens) do
            for _, other_index in ipairs(token_index[token] or {}) do
                if other_index ~= index then
                    shared[other_index] = (shared[other_index] or 0) + 1
                end
            end
        end

        local candidates = {}
        local order = {}
        for other_index, shared_count in pairs(shared) do
            local other = entries[other_index]
            if other and entry.stem ~= other.stem then
                local pair_key = dedupe_key(entry.path, other.path)
                if
                    not seen[pair_key]
                    and should_score_related_pair(entry.tokens, other.tokens, shared_count)
                then
                    order[#order + 1] = { index = other_index, shared = shared_count }
                end
            end
        end

        table.sort(order, function(a, b)
            if a.shared ~= b.shared then
                return a.shared > b.shared
            end
            return entries[a.index].slug < entries[b.index].slug
        end)

        for i = 1, math.min(#order, 24) do
            local other = entries[order[i].index]
            candidates[#candidates + 1] = {
                slug = other.slug,
                tags = other.tags,
                path = other.path,
            }
        end

        local scored =
            scoring.score_merge_candidates(entry.slug, entry.tags, candidates, { limit = 8 })
        for _, candidate in ipairs(scored) do
            local other_path = candidate.path
            local bucket = related_bucket_for(candidate.slug_sim or 0)
            if other_path and bucket then
                local pair_key = dedupe_key(entry.path, other_path)
                if not seen[pair_key] then
                    local a_path, b_path = order_pair_paths(entry.path, other_path)
                    local item = classify_pair(a_path, b_path, analysis_cache)
                    if item then
                        item.related_score = candidate.score
                        item.related_slug_sim = candidate.slug_sim
                        item.related_tag_overlap = candidate.tag_overlap
                        item.related_bucket = bucket
                        if item_matches_filters(item, opts) then
                            seen[pair_key] = true
                            items[#items + 1] = item
                        end
                    end
                end
            end
        end
    end

    table.sort(items, function(a, b)
        local oa = RELATED_BUCKET_ORDER[a.related_bucket or "weak"] or 99
        local ob = RELATED_BUCKET_ORDER[b.related_bucket or "weak"] or 99
        if oa ~= ob then
            return oa < ob
        end
        local sa = a.related_slug_sim or 0
        local sb = b.related_slug_sim or 0
        if sa ~= sb then
            return sa > sb
        end
        return a.a_rel < b.a_rel
    end)
    return items
end

local NS = vim.api.nvim_create_namespace("vault_duplicates_review")

local function setup_highlights()
    local hl = vim.api.nvim_set_hl
    hl(0, "VaultDuplicateLabel", { link = "Title", default = true })
    hl(0, "VaultDuplicateDim", { link = "Comment", default = true })
    hl(0, "VaultDuplicateAction", { link = "Function", default = true })
    hl(0, "VaultDuplicateActionKey", { link = "Keyword", default = true })
    hl(0, "VaultDuplicateRecommended", { link = "DiagnosticOk", default = true })
    hl(0, "VaultDuplicateCountGood", { link = "DiffAdd", default = true })
    hl(0, "VaultDuplicateCountWarn", { link = "DiagnosticWarn", default = true })
    hl(0, "VaultDuplicateCountInfo", { link = "Identifier", default = true })
    hl(0, "VaultDuplicatePath", { link = "Directory", default = true })
    hl(0, "VaultDuplicateSeparator", { link = "FloatBorder", default = true })
    hl(0, "VaultDuplicateChangeA", { link = "DiffDelete", default = true })
    hl(0, "VaultDuplicateChangeB", { link = "DiffAdd", default = true })
    hl(0, "VaultDuplicateText", { link = "DiffText", default = true })
end

---@param width integer
---@return string
local function pad_right(text, width)
    local display_width = vim.fn.strdisplaywidth(text)
    if display_width >= width then
        return text
    end
    return text .. string.rep(" ", width - display_width)
end

---@return table
local function compute_layout()
    local ui = vim.api.nvim_list_uis()[1] or { width = vim.o.columns, height = vim.o.lines }
    local total_w = ui.width
    local total_h = ui.height - 2
    local margin = 2
    local usable_w = total_w - margin * 2
    local usable_h = math.min(total_h - margin * 2, 40)

    local center_w = math.max(56, math.floor(usable_w * 0.32))
    local preview_w = math.floor((usable_w - center_w - 2) / 2)
    local top = margin
    local center_col = margin + preview_w + 1

    return {
        a_preview = {
            relative = "editor",
            width = preview_w,
            height = usable_h,
            row = top,
            col = margin,
            style = "minimal",
            border = "rounded",
        },
        center = {
            relative = "editor",
            width = center_w,
            height = usable_h,
            row = top,
            col = center_col,
            style = "minimal",
            border = "rounded",
        },
        b_preview = {
            relative = "editor",
            width = preview_w,
            height = usable_h,
            row = top,
            col = center_col + center_w + 1,
            style = "minimal",
            border = "rounded",
        },
    }
end

---@param name string
---@return integer
local function make_buf(name)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    pcall(vim.api.nvim_buf_set_name, buf, name)
    return buf
end

---@param path string
---@return string[]
local function read_lines(path)
    local ok, lines = pcall(vim.fn.readfile, path, "", 200)
    if ok and type(lines) == "table" then
        return lines
    end
    return { "(missing note)" }
end

---@param a_text string
---@param b_text string
---@return integer, integer, integer, integer
local function intraline_spans(a_text, b_text)
    local prefix = 0
    local max_prefix = math.min(#a_text, #b_text)
    while prefix < max_prefix and a_text:byte(prefix + 1) == b_text:byte(prefix + 1) do
        prefix = prefix + 1
    end

    local a_suffix = #a_text
    local b_suffix = #b_text
    while
        a_suffix > prefix
        and b_suffix > prefix
        and a_text:byte(a_suffix) == b_text:byte(b_suffix)
    do
        a_suffix = a_suffix - 1
        b_suffix = b_suffix - 1
    end

    return prefix, a_suffix, prefix, b_suffix
end

---@class vault.duplicates.Highlight
---@field line integer
---@field start_col integer
---@field end_col integer
---@field group string

---@class vault.duplicates.Hunk
---@field a_line integer
---@field b_line integer

---@param a_lines string[]
---@param b_lines string[]
---@return vault.duplicates.Highlight[], vault.duplicates.Highlight[], vault.duplicates.Hunk[]
local function build_preview_highlights(a_lines, b_lines)
    local a_hls = {}
    local b_hls = {}
    local hunk_positions = {}
    local hunks = vim.diff(table.concat(a_lines, "\n"), table.concat(b_lines, "\n"), {
        result_type = "indices",
        algorithm = "histogram",
    }) or {}

    local function add_line_marks(target, start_line, count, group, lines)
        for i = 0, count - 1 do
            local idx = start_line + i
            local text = lines[idx] or ""
            target[#target + 1] = {
                line = idx - 1,
                start_col = 0,
                end_col = #text,
                group = group,
            }
        end
    end

    for _, hunk in ipairs(hunks) do
        local a_start = hunk[1]
        local a_count = hunk[2]
        local b_start = hunk[3]
        local b_count = hunk[4]

        hunk_positions[#hunk_positions + 1] = {
            a_line = math.max(1, a_start),
            b_line = math.max(1, b_start),
        }

        add_line_marks(a_hls, a_start, a_count, "VaultDuplicateChangeA", a_lines)
        add_line_marks(b_hls, b_start, b_count, "VaultDuplicateChangeB", b_lines)

        local paired = math.min(a_count, b_count)
        for i = 0, paired - 1 do
            local a_line_nr = a_start + i
            local b_line_nr = b_start + i
            local a_text = a_lines[a_line_nr] or ""
            local b_text = b_lines[b_line_nr] or ""
            local a_from, a_to, b_from, b_to = intraline_spans(a_text, b_text)
            if a_to > a_from then
                a_hls[#a_hls + 1] = {
                    line = a_line_nr - 1,
                    start_col = a_from,
                    end_col = a_to,
                    group = "VaultDuplicateText",
                }
            end
            if b_to > b_from then
                b_hls[#b_hls + 1] = {
                    line = b_line_nr - 1,
                    start_col = b_from,
                    end_col = b_to,
                    group = "VaultDuplicateText",
                }
            end
        end
    end

    return a_hls, b_hls, hunk_positions
end

---@param bufnr integer
---@param lines string[]
local function load_preview(bufnr, lines)
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modifiable = false
    vim.bo[bufnr].filetype = "markdown"
end

---@param bufnr integer
---@param highlights vault.duplicates.Highlight[]
local function apply_buffer_highlights(bufnr, highlights)
    vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
    for _, hl in ipairs(highlights) do
        vim.api.nvim_buf_add_highlight(bufnr, NS, hl.group, hl.line, hl.start_col, hl.end_col)
    end
end

---@param item vault.duplicates.Item
---@return string, string
local function describe_kind(item)
    if item.kind == "exact" then
        return "Same note", "Normalized body and frontmatter match."
    end
    if item.kind == "metadata" then
        return "Metadata only", "Body matches; only frontmatter differs."
    end
    if item.kind == "a_subset" then
        return "B has more body", "B contains everything visible in A plus extra content."
    end
    if item.kind == "b_subset" then
        return "A has more body", "A contains everything visible in B plus extra content."
    end
    return "Both changed", "Both notes have content the other does not."
end

---@param item vault.duplicates.Item
---@param which "a"|"b"
---@return string
local function body_strategy_for(item, which)
    if item.kind == "exact" or item.kind == "metadata" then
        return "keep_target"
    end
    if item.kind == "a_subset" then
        return which == "b" and "keep_target" or "append_source"
    end
    if item.kind == "b_subset" then
        return which == "a" and "keep_target" or "append_source"
    end
    return "append_source"
end

---@param item vault.duplicates.Item
---@param which "a"|"b"
---@return vault.duplicates.ReviewPlan
local function build_review_plan(item, which)
    local target_path = which == "a" and item.a_path or item.b_path
    local source_path = which == "a" and item.b_path or item.a_path
    local body_strategy = body_strategy_for(item, which)
    local plan, err = merge.plan(target_path, source_path, {
        body_strategy = body_strategy,
    })
    return {
        which = which,
        target_path = target_path,
        source_path = source_path,
        body_strategy = body_strategy,
        plan = plan,
        error = err,
    }
end

---@param values string[]
---@param fallback string
---@return string
local function summarize_keys(values, fallback)
    if #values == 0 then
        return fallback
    end
    if #values <= 4 then
        return table.concat(values, ", ")
    end
    local preview = { table.unpack(values, 1, 4) }
    return table.concat(preview, ", ") .. string.format(" +%d", #values - 4)
end

---@param review_plan vault.duplicates.ReviewPlan
---@return string
local function describe_body_strategy(review_plan)
    if review_plan.body_strategy == "keep_target" then
        return "keep winner body only"
    end
    return "keep both bodies (loser appended)"
end

---@param review_plan vault.duplicates.ReviewPlan
---@param rewrite_count integer
---@return string
local function summarize_choice(review_plan, rewrite_count)
    local plan = review_plan.plan
    if not plan then
        return "plan unavailable"
    end
    local adds = #plan.added_fields + #plan.extended_fields
    local conflicts = #plan.conflicts
    return string.format(
        "%d rewrites, %d metadata adds, %d conflicts, %s",
        rewrite_count,
        adds,
        conflicts,
        describe_body_strategy(review_plan)
    )
end

---@param review_plan vault.duplicates.ReviewPlan
---@return integer, integer
local function choice_counts(review_plan)
    local plan = review_plan.plan
    if not plan then
        return 0, 0
    end
    return #plan.added_fields + #plan.extended_fields, #plan.conflicts
end

---@param item vault.duplicates.Item
---@param session table
---@return string[], table[]
local function build_center_lines(item, session)
    local lines = {}
    local hls = {}
    local kind_title, kind_detail = describe_kind(item)
    local keep_label = winner_label(item.recommended)
    local trash_label = item.recommended == "a" and "B" or "A"
    local review_plan = build_review_plan(item, item.recommended)
    local merge_plan = review_plan.plan
    local plan_a = build_review_plan(item, "a")
    local plan_b = build_review_plan(item, "b")
    local rewrites_a = estimate_rewrite_count(session, item.b_path, item.a_path)
    local rewrites_b = estimate_rewrite_count(session, item.a_path, item.b_path)
    local summary_a = summarize_choice(plan_a, rewrites_a)
    local summary_b = summarize_choice(plan_b, rewrites_b)
    local adds_a, conflicts_a = choice_counts(plan_a)
    local adds_b, conflicts_b = choice_counts(plan_b)

    local function add(line)
        lines[#lines + 1] = line
        return #lines - 1
    end

    local function mark(line, start_col, end_col, group)
        hls[#hls + 1] = {
            line = line,
            start_col = start_col,
            end_col = end_col,
            group = group,
        }
    end

    local line = add("A  " .. item.a_rel)
    mark(line, 0, 1, "VaultDuplicateLabel")
    mark(line, 3, #lines[#lines], "VaultDuplicatePath")

    line = add("B  " .. item.b_rel)
    mark(line, 0, 1, "VaultDuplicateLabel")
    mark(line, 3, #lines[#lines], "VaultDuplicatePath")

    line = add("Kind")
    mark(line, 0, #lines[#lines], "VaultDuplicateLabel")
    line = add("  " .. kind_title)
    mark(line, 2, #lines[#lines], "VaultDuplicateAction")
    line = add("  " .. kind_detail)
    mark(line, 0, #lines[#lines], "VaultDuplicateDim")

    line = add("Recommendation")
    mark(line, 0, #lines[#lines], "VaultDuplicateLabel")
    line = add(string.format("  Keep %s, trash %s", keep_label, trash_label))
    mark(line, 2, #lines[#lines], "VaultDuplicateRecommended")
    line = add("  " .. item.recommended_reason)
    mark(line, 0, #lines[#lines], "VaultDuplicateDim")
    line = add(
        string.format(
            "  Similarity %.2f   Unique lines A+%d  B+%d",
            item.score,
            item.original_unique_lines,
            item.copy_unique_lines
        )
    )
    mark(line, 0, #lines[#lines], "VaultDuplicateDim")
    if item.related_bucket then
        line = add(
            string.format(
                "  Related %s   Rust slug %.2f   tags %.2f   score %.2f",
                item.related_bucket,
                item.related_slug_sim or 0,
                item.related_tag_overlap or 0,
                item.related_score or 0
            )
        )
        mark(line, 0, #lines[#lines], "VaultDuplicateDim")
    end
    if merge_plan then
        local added_count = #merge_plan.added_fields + #merge_plan.extended_fields
        local conflict_count = #merge_plan.conflicts
        local ignored_count = #merge_plan.ignored_fields
        line = add(
            string.format(
                "  Outcome: keep %s, add %d metadata fields, %d conflicts, ignore %d noisy fields",
                keep_label,
                added_count,
                conflict_count,
                ignored_count
            )
        )
        mark(line, 0, #lines[#lines], "VaultDuplicateDim")
    end
    line = add(
        string.format(
            "  Action: merge %s into %s, rewrite links, move loser to .trash/",
            trash_label,
            keep_label
        )
    )
    mark(line, 0, #lines[#lines], "VaultDuplicateDim")
    line = add(string.format("  Batch queue: %d pending decision(s)", #(session.pending or {})))
    mark(
        line,
        0,
        #lines[#lines],
        #(session.pending or {}) > 0 and "VaultDuplicateAction" or "VaultDuplicateDim"
    )

    line = add("Choices")
    mark(line, 0, #lines[#lines], "VaultDuplicateLabel")
    line = add(
        string.format(
            "  a: keep A at %s%s",
            item.a_rel,
            item.recommended == "a" and "  [recommended]" or ""
        )
    )
    mark(
        line,
        0,
        #lines[#lines],
        item.recommended == "a" and "VaultDuplicateRecommended" or "VaultDuplicateDim"
    )
    line = add(string.format("     %s", summary_a))
    mark(line, 0, #lines[#lines], "VaultDuplicateDim")
    local line_text = lines[#lines]
    local rewrites_token = tostring(rewrites_a) .. " rewrites"
    local adds_token = tostring(adds_a) .. " metadata adds"
    local conflicts_token = tostring(conflicts_a) .. " conflicts"
    local rewrites_start = line_text:find(rewrites_token, 1, true)
    if rewrites_start then
        mark(
            line,
            rewrites_start - 1,
            rewrites_start - 1 + #rewrites_token,
            rewrites_a > 0 and "VaultDuplicateCountInfo" or "VaultDuplicateDim"
        )
    end
    local adds_start = line_text:find(adds_token, 1, true)
    if adds_start then
        mark(
            line,
            adds_start - 1,
            adds_start - 1 + #adds_token,
            adds_a > 0 and "VaultDuplicateCountGood" or "VaultDuplicateCountInfo"
        )
    end
    local conflicts_start = line_text:find(conflicts_token, 1, true)
    if conflicts_start then
        mark(
            line,
            conflicts_start - 1,
            conflicts_start - 1 + #conflicts_token,
            conflicts_a > 0 and "VaultDuplicateCountWarn" or "VaultDuplicateCountInfo"
        )
    end
    line = add(
        string.format(
            "  b: keep B at %s%s",
            item.b_rel,
            item.recommended == "b" and "  [recommended]" or ""
        )
    )
    mark(
        line,
        0,
        #lines[#lines],
        item.recommended == "b" and "VaultDuplicateRecommended" or "VaultDuplicateDim"
    )
    line = add(string.format("     %s", summary_b))
    mark(line, 0, #lines[#lines], "VaultDuplicateDim")
    line_text = lines[#lines]
    rewrites_token = tostring(rewrites_b) .. " rewrites"
    adds_token = tostring(adds_b) .. " metadata adds"
    conflicts_token = tostring(conflicts_b) .. " conflicts"
    rewrites_start = line_text:find(rewrites_token, 1, true)
    if rewrites_start then
        mark(
            line,
            rewrites_start - 1,
            rewrites_start - 1 + #rewrites_token,
            rewrites_b > 0 and "VaultDuplicateCountInfo" or "VaultDuplicateDim"
        )
    end
    adds_start = line_text:find(adds_token, 1, true)
    if adds_start then
        mark(
            line,
            adds_start - 1,
            adds_start - 1 + #adds_token,
            adds_b > 0 and "VaultDuplicateCountGood" or "VaultDuplicateCountInfo"
        )
    end
    conflicts_start = line_text:find(conflicts_token, 1, true)
    if conflicts_start then
        mark(
            line,
            conflicts_start - 1,
            conflicts_start - 1 + #conflicts_token,
            conflicts_b > 0 and "VaultDuplicateCountWarn" or "VaultDuplicateCountInfo"
        )
    end

    line = add("Merge plan")
    mark(line, 0, #lines[#lines], "VaultDuplicateLabel")
    if merge_plan then
        line = add("  Add from loser: " .. summarize_keys(merge_plan.added_fields, "nothing"))
        mark(line, 0, #lines[#lines], "VaultDuplicateDim")
        line = add("  Extend lists: " .. summarize_keys(merge_plan.extended_fields, "nothing"))
        mark(line, 0, #lines[#lines], "VaultDuplicateDim")
        local conflict_fields = {}
        for _, conflict in ipairs(merge_plan.conflicts) do
            conflict_fields[#conflict_fields + 1] = conflict.field
        end
        line = add("  Conflicts: " .. summarize_keys(conflict_fields, "none"))
        mark(
            line,
            0,
            #lines[#lines],
            #conflict_fields > 0 and "VaultDuplicateAction" or "VaultDuplicateDim"
        )
        line = add("  Ignore noise: " .. summarize_keys(merge_plan.ignored_fields, "nothing"))
        mark(line, 0, #lines[#lines], "VaultDuplicateDim")
        line = add("  Body: " .. describe_body_strategy(review_plan))
        mark(line, 0, #lines[#lines], "VaultDuplicateDim")
    else
        line = add("  " .. tostring(review_plan.error or "Could not compute merge plan"))
        mark(line, 0, #lines[#lines], "VaultDuplicateDim")
    end

    line = add(string.rep("─", 44))
    mark(line, 0, #lines[#lines], "VaultDuplicateSeparator")

    line = add("Actions")
    mark(line, 0, #lines[#lines], "VaultDuplicateLabel")

    local actions = {
        { key = "a", text = "Apply keep A" },
        { key = "b", text = "Apply keep B" },
        { key = "A", text = "Queue keep A for batch apply" },
        { key = "B", text = "Queue keep B for batch apply" },
        { key = "<CR>", text = string.format("Apply recommendation  (keep %s)", keep_label) },
        {
            key = "X",
            text = string.format("Apply queued batch  (%d pending)", #(session.pending or {})),
        },
        { key = "pa", text = "Preview result if keeping A" },
        { key = "pb", text = "Preview result if keeping B" },
        { key = "[c", text = "Previous changed region" },
        { key = "]c", text = "Next changed region" },
        { key = "s", text = "Skip this pair  (leave files unchanged)" },
        { key = "]d", text = "Move to next pair" },
        { key = "q", text = "Quit review  (resume later)" },
    }

    for _, action in ipairs(actions) do
        line = add(string.format("  %-4s %s", pad_right(action.key, 4), action.text))
        mark(line, 2, 2 + #action.key, "VaultDuplicateActionKey")
    end

    line = add(
        "  apply: a b <CR>   queue: A B X   preview: pa pb p   hunks: [c ]c   move: s ]d   quit: q"
    )
    mark(line, 2, 7, "VaultDuplicateActionKey")
    mark(line, 22, 27, "VaultDuplicateActionKey")
    mark(line, 37, 44, "VaultDuplicateActionKey")
    mark(line, 55, 60, "VaultDuplicateActionKey")
    mark(line, 69, 73, "VaultDuplicateActionKey")

    return lines, hls
end

---@param title string
---@param lines string[]
---@param preview_opts? { footer?: string, on_confirm?: fun(), on_close?: fun(integer, integer) }
---@return integer, integer
local function open_text_preview(title, lines, preview_opts)
    preview_opts = preview_opts or {}
    local buf = make_buf("vault://duplicates/merge-preview")
    vim.bo[buf].modifiable = true
    local display_lines = vim.deepcopy(lines)
    if preview_opts.footer and preview_opts.footer ~= "" then
        display_lines[#display_lines + 1] = ""
        display_lines[#display_lines + 1] = preview_opts.footer
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, display_lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].filetype = "markdown"

    local ui = vim.api.nvim_list_uis()[1] or { width = vim.o.columns, height = vim.o.lines }
    local width = math.min(ui.width - 8, 140)
    local height = math.min(ui.height - 6, 40)
    local row = math.max(1, math.floor((ui.height - height) / 2) - 1)
    local col = math.max(1, math.floor((ui.width - width) / 2))

    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        row = row,
        col = col,
        width = width,
        height = height,
        style = "minimal",
        border = "rounded",
        title = " " .. title .. " ",
        title_pos = "center",
    })

    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].wrap = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].winhighlight = "NormalFloat:Normal,FloatBorder:FloatBorder"

    local map_opts = { buffer = buf, silent = true, nowait = true }
    vim.keymap.set("n", "q", function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end, map_opts)
    vim.keymap.set("n", "<Esc>", function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end, map_opts)
    if preview_opts.on_confirm then
        vim.keymap.set("n", "<CR>", function()
            if vim.api.nvim_win_is_valid(win) then
                vim.api.nvim_win_close(win, true)
            end
            vim.schedule(preview_opts.on_confirm)
        end, map_opts)
    end
    if preview_opts.on_close then
        vim.api.nvim_create_autocmd("WinClosed", {
            once = true,
            pattern = tostring(win),
            callback = function()
                vim.schedule(function()
                    preview_opts.on_close(buf, win)
                end)
            end,
        })
    end
    return buf, win
end

---@param root string|nil
---@param opts? { allowed_paths?: table<string, boolean>, path_filters?: table<string, table<string, boolean>>, kinds?: table<string, boolean>, related_buckets?: table<string, boolean>, filter_spec?: table, mode?: string }
function M.review(root, opts)
    opts = opts or {}
    setup_highlights()
    local resume = state_store.get_global_key(REVIEW_STATE_KEY)
    local scanner = require("vault.scanner")
    local session_root = root
        or (resume and resume.root)
        or vim.fn.expand(require("vault.config").options.root)
    local paths = scanner.paths()
    local filter_spec = vim.deepcopy(opts.filter_spec or {})
    local resume_matches = resume
        and resume.root == session_root
        and vim.deep_equal(resume.filters or {}, filter_spec)
    local scan_fn = opts.mode == "related" and M.scan_related or M.scan
    local items = scan_fn(session_root, paths, opts)
    if vim.tbl_isempty(items) then
        log.info(
            opts.mode == "related" and "No related duplicate candidates found"
                or "No duplicate candidates found"
        )
        state_store.set_global_key(REVIEW_STATE_KEY, nil)
        return
    end

    local wikilinks = scanner.wikilinks()

    local pending = {}
    local pending_paths = {}
    if resume_matches and type(resume.pending) == "table" then
        for _, spec in ipairs(resume.pending) do
            if
                type(spec) == "table"
                and type(spec.target_path) == "string"
                and type(spec.source_path) == "string"
            then
                pending[#pending + 1] = spec
                pending_paths[spec.target_path] = true
                pending_paths[spec.source_path] = true
            end
        end
    end

    items = filter_items(items, pending_paths)
    local start_index = find_item_index(items, resume_matches and resume.current_key or nil)

    local state = {
        items = items,
        index = start_index,
        bufs = {},
        wins = {},
        preview_buf = nil,
        preview_win = nil,
        hunks = {},
        hunk_index = 0,
        paths = paths,
        wikilinks = wikilinks,
        stem_counts = build_stem_counts(paths),
        pending = pending,
        pending_paths = pending_paths,
        root = session_root,
        filter_spec = filter_spec,
    }

    local function save_session_state()
        local current = state.items[state.index]
        state_store.set_global_key(REVIEW_STATE_KEY, {
            root = state.root,
            filters = vim.deepcopy(state.filter_spec),
            current_key = current and item_key(current) or nil,
            pending = vim.deepcopy(state.pending),
        })
    end

    local function clear_session_state()
        state_store.set_global_key(REVIEW_STATE_KEY, nil)
    end

    local function close_ui()
        for _, win in pairs(state.wins) do
            if win and vim.api.nvim_win_is_valid(win) then
                pcall(vim.api.nvim_win_close, win, true)
            end
        end
        for _, buf in pairs(state.bufs) do
            if buf and vim.api.nvim_buf_is_valid(buf) then
                pcall(vim.api.nvim_buf_delete, buf, { force = true })
            end
        end
        state.wins = {}
        state.bufs = {}
        state.preview_buf = nil
        state.preview_win = nil
        state.hunks = {}
        state.hunk_index = 0
    end

    local function next_item()
        state.index = state.index + 1
        if state.index > #state.items then
            close_ui()
            clear_session_state()
            log.info("Duplicate review complete")
            return
        end
        save_session_state()
    end

    local open_current
    local remove_related_items
    local refresh_path_metadata
    local flush_pending

    local function apply_keep(which)
        local item = state.items[state.index]
        if not item then
            return
        end
        close_ui()
        local target = which == "a" and item.a_path or item.b_path
        local source = which == "a" and item.b_path or item.a_path
        local body_strategy = body_strategy_for(item, which)
        merge.merge(target, source, {
            body_strategy = body_strategy,
            paths = state.paths,
            on_done = function()
                local ok_slug, source_slug = pcall(utils.path_to_slug, source)
                if ok_slug and source_slug and state.paths then
                    state.paths[source_slug] = nil
                end
                remove_related_items(target, source)
                refresh_path_metadata()
                save_session_state()
                vim.schedule(function()
                    if #state.items == 0 then
                        clear_session_state()
                        log.info("Duplicate review complete")
                    else
                        open_current()
                    end
                end)
            end,
        })
    end

    ---@param which "a"|"b"
    local function preview_merge_result(which)
        local item = state.items[state.index]
        if not item then
            return
        end
        local review_plan = build_review_plan(item, which)
        if not review_plan.plan then
            log.warn("%s", tostring(review_plan.error or "Could not compute merge preview"))
            return
        end
        local buf, win = open_text_preview(
            string.format("Merged preview: keep %s", winner_label(which)),
            review_plan.plan.merged_lines,
            {
                footer = string.format(
                    "[q/<Esc>] back   [<CR>] apply keep %s",
                    winner_label(which)
                ),
                on_confirm = function()
                    apply_keep(which)
                end,
                on_close = function()
                    state.preview_buf = nil
                    state.preview_win = nil
                    if state.wins.center and vim.api.nvim_win_is_valid(state.wins.center) then
                        vim.api.nvim_set_current_win(state.wins.center)
                    end
                end,
            }
        )
        state.preview_buf = buf
        state.preview_win = win
    end

    ---@param direction integer
    local function jump_hunk(direction)
        if #state.hunks == 0 then
            log.info("No changed regions in this pair")
            return
        end
        if state.hunk_index == 0 then
            state.hunk_index = 1
        else
            state.hunk_index = math.max(1, math.min(#state.hunks, state.hunk_index + direction))
        end
        local hunk = state.hunks[state.hunk_index]
        if state.wins.a_preview and vim.api.nvim_win_is_valid(state.wins.a_preview) then
            vim.api.nvim_win_set_cursor(state.wins.a_preview, { hunk.a_line, 0 })
        end
        if state.wins.b_preview and vim.api.nvim_win_is_valid(state.wins.b_preview) then
            vim.api.nvim_win_set_cursor(state.wins.b_preview, { hunk.b_line, 0 })
        end
        if state.wins.center and vim.api.nvim_win_is_valid(state.wins.center) then
            vim.api.nvim_set_current_win(state.wins.center)
        end
    end

    ---@param target_path string
    ---@param source_path string
    remove_related_items = function(target_path, source_path)
        local blocked = {
            [target_path] = true,
            [source_path] = true,
        }
        local filtered = {}
        for index, entry in ipairs(state.items) do
            if index ~= state.index and not blocked[entry.a_path] and not blocked[entry.b_path] then
                filtered[#filtered + 1] = entry
            end
        end
        state.items = filtered
        if state.index > #state.items then
            state.index = #state.items
        end
    end

    refresh_path_metadata = function()
        state.stem_counts = build_stem_counts(state.paths)
    end

    flush_pending = function(on_done)
        if vim.tbl_isempty(state.pending) then
            if on_done then
                on_done()
            end
            return
        end
        close_ui()
        local result = merge.absorb_many(state.pending, {
            paths = state.paths,
        })
        for _, spec in ipairs(state.pending) do
            local ok_slug, source_slug = pcall(utils.path_to_slug, spec.source_path)
            if ok_slug and source_slug then
                state.paths[source_slug] = nil
            end
            state.pending_paths[spec.source_path] = nil
            state.pending_paths[spec.target_path] = nil
        end
        state.pending = {}
        refresh_path_metadata()
        if result.applied > 0 then
            state.wikilinks = scanner.wikilinks()
        end
        if on_done then
            on_done()
            return
        end
        save_session_state()
        vim.schedule(function()
            if #state.items == 0 then
                clear_session_state()
                log.info("Duplicate review complete")
            else
                open_current()
            end
        end)
    end

    ---@param which "a"|"b"
    local function queue_keep(which)
        local item = state.items[state.index]
        if not item then
            return
        end
        local review_plan = build_review_plan(item, which)
        if not review_plan.plan then
            log.warn("%s", tostring(review_plan.error or "Could not queue merge"))
            return
        end
        local biased_resolved, unresolved_conflicts =
            merge.resolve_conflicts_with_biases(review_plan.plan.conflicts)
        if #unresolved_conflicts > 0 then
            merge.open_conflict_picker(
                review_plan.plan.target_slug,
                review_plan.plan.source_slug,
                unresolved_conflicts,
                function(resolved)
                    local resolved_plan =
                        merge.plan(review_plan.target_path, review_plan.source_path, {
                            resolved = vim.tbl_extend("force", biased_resolved, resolved),
                            body_strategy = review_plan.body_strategy,
                        })
                    if not resolved_plan then
                        log.warn("Could not queue resolved merge")
                        return
                    end
                    state.pending[#state.pending + 1] = {
                        target_path = review_plan.target_path,
                        source_path = review_plan.source_path,
                        merged_lines = resolved_plan.merged_lines,
                    }
                    state.pending_paths[review_plan.target_path] = true
                    state.pending_paths[review_plan.source_path] = true
                    remove_related_items(review_plan.target_path, review_plan.source_path)
                    save_session_state()
                    vim.schedule(function()
                        if #state.items == 0 then
                            flush_pending()
                        else
                            open_current()
                        end
                    end)
                end
            )
            return
        end

        if not vim.tbl_isempty(biased_resolved) then
            local resolved_plan = merge.plan(review_plan.target_path, review_plan.source_path, {
                resolved = biased_resolved,
                body_strategy = review_plan.body_strategy,
            })
            if not resolved_plan then
                log.warn("Could not queue biased merge")
                return
            end
            review_plan.plan = resolved_plan
        end

        state.pending[#state.pending + 1] = {
            target_path = review_plan.target_path,
            source_path = review_plan.source_path,
            merged_lines = review_plan.plan.merged_lines,
        }
        state.pending_paths[review_plan.target_path] = true
        state.pending_paths[review_plan.source_path] = true
        remove_related_items(review_plan.target_path, review_plan.source_path)
        save_session_state()
        if #state.items == 0 then
            flush_pending()
            return
        end
        open_current()
    end

    open_current = function()
        local item = state.items[state.index]
        if not item then
            log.info("Duplicate review complete")
            return
        end

        close_ui()
        local layout = compute_layout()
        local lines, hls = build_center_lines(item, state)

        state.bufs.a_preview = make_buf("vault://duplicates/preview-a")
        state.bufs.center = make_buf("vault://duplicates/center")
        state.bufs.b_preview = make_buf("vault://duplicates/preview-b")

        state.wins.a_preview = vim.api.nvim_open_win(state.bufs.a_preview, false, layout.a_preview)
        state.wins.center = vim.api.nvim_open_win(state.bufs.center, true, layout.center)
        state.wins.b_preview = vim.api.nvim_open_win(state.bufs.b_preview, false, layout.b_preview)

        local a_lines = read_lines(item.a_path)
        local b_lines = read_lines(item.b_path)
        local a_hls, b_hls, hunk_positions = build_preview_highlights(a_lines, b_lines)
        state.hunks = hunk_positions
        state.hunk_index = #hunk_positions > 0 and 1 or 0

        load_preview(state.bufs.a_preview, a_lines)
        load_preview(state.bufs.b_preview, b_lines)
        apply_buffer_highlights(state.bufs.a_preview, a_hls)
        apply_buffer_highlights(state.bufs.b_preview, b_hls)

        vim.bo[state.bufs.center].modifiable = true
        vim.api.nvim_buf_set_lines(state.bufs.center, 0, -1, false, lines)
        vim.bo[state.bufs.center].modifiable = false

        for _, win in pairs(state.wins) do
            vim.wo[win].number = false
            vim.wo[win].relativenumber = false
            vim.wo[win].signcolumn = "no"
            vim.wo[win].wrap = true
            vim.wo[win].winhighlight = "NormalFloat:Normal,FloatBorder:FloatBorder"
        end
        vim.wo[state.wins.center].cursorline = true

        pcall(vim.api.nvim_win_set_config, state.wins.a_preview, {
            title = string.format(" A %d/%d ", state.index, #state.items),
            title_pos = "center",
        })
        pcall(vim.api.nvim_win_set_config, state.wins.center, {
            title = " Duplicate review ",
            title_pos = "center",
        })
        pcall(vim.api.nvim_win_set_config, state.wins.b_preview, {
            title = string.format(" B %d/%d ", state.index, #state.items),
            title_pos = "center",
        })

        if #state.hunks > 0 then
            jump_hunk(0)
        end

        apply_buffer_highlights(state.bufs.center, hls)

        local keymap_opts = { buffer = state.bufs.center, silent = true, nowait = true }
        vim.keymap.set("n", "a", function()
            apply_keep("a")
        end, vim.tbl_extend("force", keymap_opts, { desc = "Keep A" }))
        vim.keymap.set("n", "b", function()
            apply_keep("b")
        end, vim.tbl_extend("force", keymap_opts, { desc = "Keep B" }))
        vim.keymap.set("n", "A", function()
            queue_keep("a")
        end, vim.tbl_extend("force", keymap_opts, { desc = "Queue keep A" }))
        vim.keymap.set("n", "B", function()
            queue_keep("b")
        end, vim.tbl_extend("force", keymap_opts, { desc = "Queue keep B" }))
        vim.keymap.set("n", "<CR>", function()
            apply_keep(item.recommended)
        end, vim.tbl_extend("force", keymap_opts, { desc = "Apply recommended" }))
        vim.keymap.set("n", "X", function()
            flush_pending()
        end, vim.tbl_extend("force", keymap_opts, { desc = "Apply queued batch" }))
        vim.keymap.set("n", "pa", function()
            preview_merge_result("a")
        end, vim.tbl_extend("force", keymap_opts, { desc = "Preview keep A result" }))
        vim.keymap.set("n", "pb", function()
            preview_merge_result("b")
        end, vim.tbl_extend("force", opts, { desc = "Preview keep B result" }))
        vim.keymap.set("n", "p", function()
            preview_merge_result(item.recommended)
        end, vim.tbl_extend("force", opts, { desc = "Preview recommended result" }))
        vim.keymap.set("n", "]c", function()
            jump_hunk(1)
        end, vim.tbl_extend("force", opts, { desc = "Next changed region" }))
        vim.keymap.set("n", "[c", function()
            jump_hunk(-1)
        end, vim.tbl_extend("force", opts, { desc = "Previous changed region" }))
        vim.keymap.set("n", "s", function()
            close_ui()
            vim.schedule(function()
                next_item()
                open_current()
            end)
        end, vim.tbl_extend("force", opts, { desc = "Skip duplicate" }))
        vim.keymap.set("n", "q", function()
            close_ui()
            save_session_state()
            log.info("Duplicate review paused at %d/%d", state.index, #state.items)
        end, vim.tbl_extend("force", opts, { desc = "Quit duplicate review" }))
        vim.keymap.set("n", "]d", function()
            close_ui()
            vim.schedule(function()
                next_item()
                open_current()
            end)
        end, vim.tbl_extend("force", opts, { desc = "Next duplicate" }))

        vim.api.nvim_create_autocmd("BufLeave", {
            buffer = state.bufs.center,
            once = true,
            callback = function()
                vim.schedule(function()
                    local cur_buf = vim.api.nvim_get_current_buf()
                    if state.preview_buf and cur_buf == state.preview_buf then
                        return
                    end
                    for _, buf in pairs(state.bufs) do
                        if buf == cur_buf then
                            return
                        end
                    end
                    close_ui()
                end)
            end,
        })
    end

    save_session_state()
    if #state.items == 0 and not vim.tbl_isempty(state.pending) then
        flush_pending()
        return
    end
    open_current()
end

---@param root string|nil
---@param opts? table
function M.review_related(root, opts)
    opts = vim.tbl_extend("force", { mode = "related" }, opts or {})
    return M.review(root, opts)
end

M._analyze_file = analyze_file
M.kind_filter_names = function()
    local names = vim.tbl_keys(KIND_FILTER_ALIASES)
    table.sort(names)
    return names
end
M.resolve_kind_filter = resolve_kind_filter
M.preset_names = function(prefix)
    prefix = prefix or ""
    return vim.tbl_filter(function(name)
        return name:find(prefix, 1, true) == 1
    end, preset_names())
end
M.presets = function()
    local result = {}
    for _, name in ipairs(preset_names()) do
        local preset, _ = resolve_preset(name)
        if preset then
            preset.summary = preset_summary(preset)
            result[#result + 1] = preset
        end
    end
    return result
end
M.resolve_preset = resolve_preset
M.preset_summary = preset_summary
M.related_filter_names = function()
    local names = vim.tbl_keys(RELATED_FILTER_ALIASES)
    table.sort(names)
    return names
end
M.resolve_related_filter = resolve_related_filter

return M
