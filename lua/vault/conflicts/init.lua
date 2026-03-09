local M = {}

local log = require("vault.log").scope("conflicts")
local utils = require("vault.utils")
local Resolver = require("vault.ui.resolver")
local Wikilink = require("vault.wikilinks.wikilink")
local merge = require("vault.merge")

local COPY_SUFFIX_RE = "^(.-) (%d+)$"

---@class vault.conflicts.Item
---@field kind string
---@field keep string
---@field candidate string
---@field original_unique_lines integer
---@field copy_unique_lines integer

---@param path string
---@return string|nil
local function read_text(path)
    local ok, lines = pcall(vim.fn.readfile, path)
    if not ok then
        return nil
    end
    return table.concat(lines, "\n")
end

---@param text string
---@return string
local function normalize_text(text)
    local lines = vim.split(text:gsub("\r\n", "\n"), "\n", { plain = true })
    for i, line in ipairs(lines) do
        lines[i] = line:gsub("%s+$", "")
    end
    return vim.trim(table.concat(lines, "\n"))
end

---@param value string
---@return string
local function strip_copy_suffix(value)
    local trimmed = vim.trim(value)
    local base = trimmed:match(COPY_SUFFIX_RE)
    return base or trimmed
end

---@param text string
---@return string[] frontmatter_lines, string[] body_lines
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

---@param line string
---@return string|nil
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
    if key == "modified" or key == "committed" then
        return nil
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

---@param lines string[]
---@return table<string, boolean>
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

---@param path string
---@param lines string[]
---@return string
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
                local base = stem:match(COPY_SUFFIX_RE) or stem
                normalized[i] = "# " .. base
            end
            break
        end
    end
    return vim.trim(table.concat(normalized, "\n"))
end

---@param text string
---@return table<string, boolean>
local function meaningful_line_set(text)
    local result = {}
    for _, line in ipairs(vim.split(normalize_text(text), "\n", { plain = true })) do
        local trimmed = vim.trim(line)
        if trimmed ~= "" then
            result[trimmed] = true
        end
    end
    return result
end

---@param original string
---@param copy string
---@return boolean
local function is_daily_pair(original, copy)
    return vim.fn.fnamemodify(original, ":h:t") == "Daily"
        and vim.fn.fnamemodify(copy, ":h") == vim.fn.fnamemodify(original, ":h")
end

---@param path string
---@param frontmatter_lines string[]
---@return boolean
local function daily_created_matches_filename(path, frontmatter_lines)
    local stem = vim.fn.fnamemodify(path, ":t:r")
    local base = stem:match(COPY_SUFFIX_RE) or stem
    local y, m, d = base:match("^(%d%d%d%d)%-(%d%d)%-(%d%d) ")
    if not y then
        return false
    end
    local expected = y .. m .. d .. "000000"
    for _, line in ipairs(frontmatter_lines) do
        local value = line:match("^created:%s*(.*)$")
        if value then
            value = vim.trim(value):gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
            return value == expected
        end
    end
    return false
end

---@param original_path string
---@param copy_path string
---@return vault.conflicts.Item|nil
local function classify_pair(original_path, copy_path)
    if vim.fn.filereadable(original_path) == 0 then
        return {
            kind = "missing_original",
            keep = utils.path_to_relpath(original_path),
            candidate = utils.path_to_relpath(copy_path),
            original_unique_lines = 0,
            copy_unique_lines = 0,
        }
    end

    local original_text = read_text(original_path)
    local copy_text = read_text(copy_path)
    if not original_text or not copy_text then
        return nil
    end

    local original_frontmatter_lines, original_body_lines = split_frontmatter(original_text)
    local copy_frontmatter_lines, copy_body_lines = split_frontmatter(copy_text)

    local original_frontmatter = normalize_frontmatter(original_frontmatter_lines)
    local copy_frontmatter = normalize_frontmatter(copy_frontmatter_lines)
    local original_body = normalize_body(original_path, original_body_lines)
    local copy_body = normalize_body(copy_path, copy_body_lines)
    local original_lines = meaningful_line_set(original_body)
    local copy_lines = meaningful_line_set(copy_body)

    local function set_diff_count(a, b)
        local count = 0
        for line, _ in pairs(a) do
            if not b[line] then
                count = count + 1
            end
        end
        return count
    end

    local kind
    if original_text == copy_text then
        kind = "exact_raw"
    elseif original_body == copy_body then
        local same_frontmatter = vim.deep_equal(original_frontmatter, copy_frontmatter)
        if same_frontmatter then
            kind = "exact_semantic"
        elseif
            is_daily_pair(original_path, copy_path)
            and daily_created_matches_filename(original_path, original_frontmatter_lines)
            and not daily_created_matches_filename(copy_path, copy_frontmatter_lines)
        then
            kind = "copy_has_extra_metadata"
        else
            local original_subset = true
            for line, _ in pairs(original_frontmatter) do
                if not copy_frontmatter[line] then
                    original_subset = false
                    break
                end
            end
            local copy_subset = true
            for line, _ in pairs(copy_frontmatter) do
                if not original_frontmatter[line] then
                    copy_subset = false
                    break
                end
            end
            if original_subset and not copy_subset then
                kind = "copy_has_extra_metadata"
            elseif copy_subset and not original_subset then
                kind = "original_has_extra_metadata"
            else
                kind = "conflicting_metadata"
            end
        end
    else
        local copy_is_subset = true
        for line, _ in pairs(copy_lines) do
            if not original_lines[line] then
                copy_is_subset = false
                break
            end
        end
        local original_is_subset = true
        for line, _ in pairs(original_lines) do
            if not copy_lines[line] then
                original_is_subset = false
                break
            end
        end
        if copy_is_subset and not original_is_subset then
            kind = "copy_subset"
        elseif original_is_subset and not copy_is_subset then
            kind = "original_subset"
        else
            kind = "divergent"
        end
    end

    return {
        kind = kind,
        keep = utils.path_to_relpath(original_path),
        candidate = utils.path_to_relpath(copy_path),
        original_unique_lines = set_diff_count(original_lines, copy_lines),
        copy_unique_lines = set_diff_count(copy_lines, original_lines),
    }
end

---@param root string
---@return vault.conflicts.Item[]
function M.scan(root)
    local items = {}
    local absolute_root = root
    if not absolute_root:match("^/") then
        absolute_root = utils.relpath_to_path(root)
    end
    absolute_root = vim.fn.fnamemodify(absolute_root, ":p")

    local paths = vim.fn.globpath(absolute_root, "**/*.md", false, true)
    table.sort(paths)
    for _, path in ipairs(paths) do
        local stem = vim.fn.fnamemodify(path, ":t:r")
        local base = stem:match(COPY_SUFFIX_RE)
        if base then
            local original_path = vim.fn.fnamemodify(path, ":h") .. "/" .. base .. ".md"
            local item = classify_pair(original_path, path)
            if item then
                table.insert(items, item)
            end
        end
    end

    local order = {
        copy_subset = 1,
        original_subset = 2,
        conflicting_metadata = 3,
        divergent = 4,
        missing_original = 5,
        exact_raw = 6,
        exact_semantic = 7,
        copy_has_extra_metadata = 8,
        original_has_extra_metadata = 9,
    }
    table.sort(items, function(a, b)
        local oa = order[a.kind] or 99
        local ob = order[b.kind] or 99
        if oa ~= ob then
            return oa < ob
        end
        return a.keep < b.keep
    end)
    return items
end

---@param root string
function M.review(root)
    local items = M.scan(root)
    if vim.tbl_isempty(items) then
        log.info("No conflict copies found in %s", root)
        return
    end

    local state = {
        index = 1,
        items = items,
    }

    local open_current
    local function next_item()
        state.index = math.min(state.index + 1, #state.items + 1)
        if state.index > #state.items then
            log.info("Conflict review complete")
            return
        end
        open_current()
    end

    open_current = function()
        local item = state.items[state.index]
        if not item then
            log.info("Conflict review complete")
            return
        end

        local a = Wikilink({ raw = "[[" .. utils.relpath_to_slug(item.keep) .. "]]" })
        local b = Wikilink({ raw = "[[" .. utils.relpath_to_slug(item.candidate) .. "]]" })

        log.info("[%d/%d] %s — %s", state.index, #state.items, item.kind, item.keep)
        Resolver.open({
            a = a,
            b = b,
            on_done = function()
                vim.schedule(function()
                    if state.index <= #state.items then
                        open_current()
                    end
                end)
            end,
        })
    end

    vim.api.nvim_create_user_command("VaultConflictNext", next_item, { force = true })
    vim.keymap.set("n", "]r", next_item, { silent = true, desc = "Next conflict" })
    open_current()
end

return M
