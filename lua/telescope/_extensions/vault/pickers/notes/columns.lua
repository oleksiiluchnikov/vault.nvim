---@class vault.TelescopeNotesColumnSpec
---@field key? string Built-in column id or `note.data` field name fallback.
---@field text? fun(note: vault.Note, ctx: vault.telescope.notes.RenderContext): string|number|nil Custom text renderer.
---@field hl? string|fun(note: vault.Note, ctx: vault.telescope.notes.RenderContext, text: string): string|nil Highlight group.
---@field width? integer|"auto" Fixed width or auto-fit to measured content.
---@field min_width? integer Minimum width after shrinking.
---@field max_width? integer Maximum width after growth/auto-fit.
---@field flex? integer Share of remaining results width.
---@field enabled? boolean Whether the column is rendered.

---@class vault.telescope.notes.RenderContext
---@field colors string[]|nil
---@field hl_name string
---@field link_counts table<string, vault.telescope.NoteLinkCounts>
---@field steps integer
---@field ui_width integer
---@field layout table

local M = {}

---@type vault.telescope.NoteLinkCounts
local ZERO_COUNTS = {
    outlinks = 0,
    inlinks = 0,
    dangling = 0,
}

---@type (string|vault.TelescopeNotesColumnSpec)[]
local DEFAULT_COLUMNS = {
    "color",
    "outlinks",
    "inlinks",
    "dangling",
    { key = "directory", min_width = 1, max_width = 8 },
    { key = "stem", flex = 1, min_width = 12 },
}

---@param note vault.Note
---@return string
local function stem_text(note)
    return vim.fn.fnamemodify(note.data.path or "", ":t:r")
end

---@param note vault.Note
---@return string
local function directory_text(note)
    return vim.fn.fnamemodify(note.data.slug or "", ":h")
end

---@param text string
---@return integer
local function display_width(text)
    return vim.fn.strdisplaywidth(text)
end

---@param note vault.Note
---@param ctx vault.telescope.notes.RenderContext
---@return string
local function content_hl(note, ctx)
    local hl = "TelescopeResultsNormal"
    if not ctx.colors then
        return hl
    end

    local content = note.data.content or ""
    local index = math.min(math.floor(#content / 16), ctx.steps)
    if index == 0 then
        index = 1
    end
    return ctx.hl_name .. tostring(index)
end

---@param note vault.Note
---@param ctx vault.telescope.notes.RenderContext
---@return vault.telescope.NoteLinkCounts
local function counts_for(note, ctx)
    return ctx.link_counts[note.data.slug] or ZERO_COUNTS
end

---@param note vault.Note
---@return string
local function title_text(note)
    local title = note.data.title
    if type(title) == "string" and title ~= "" then
        return title
    end
    return stem_text(note)
end

---@param note vault.Note
---@return string
local function relpath_text(note)
    local relpath = note.data.relpath
    if type(relpath) == "string" and relpath ~= "" then
        return relpath
    end
    return note.data.path or ""
end

---@type table<string, vault.TelescopeNotesColumnSpec>
local BUILTIN_COLUMNS = {
    color = {
        width = 2,
        text = function()
            return "██"
        end,
        hl = function(note, ctx)
            return content_hl(note, ctx)
        end,
    },
    outlinks = {
        width = "auto",
        text = function(note, ctx)
            local count = counts_for(note, ctx).outlinks
            return count > 0 and string.format("o%d", count) or ""
        end,
        hl = "TelescopeResultsComment",
    },
    inlinks = {
        width = "auto",
        text = function(note, ctx)
            local count = counts_for(note, ctx).inlinks
            return count > 0 and string.format("i%d", count) or ""
        end,
        hl = "TelescopeResultsComment",
    },
    dangling = {
        width = "auto",
        text = function(note, ctx)
            local count = counts_for(note, ctx).dangling
            return count > 0 and string.format("d%d", count) or ""
        end,
        hl = function(note, ctx)
            return counts_for(note, ctx).dangling > 0 and "DiagnosticWarn"
                or "TelescopeResultsComment"
        end,
    },
    directory = {
        width = "auto",
        min_width = 8,
        max_width = 8,
        text = function(note)
            return directory_text(note)
        end,
        hl = "TelescopeResultsComment",
    },
    stem = {
        flex = 1,
        min_width = 12,
        text = function(note)
            return stem_text(note)
        end,
        hl = function(note, ctx)
            return content_hl(note, ctx)
        end,
    },
    basename = {
        flex = 1,
        min_width = 12,
        text = function(note)
            return stem_text(note)
        end,
        hl = function(note, ctx)
            return content_hl(note, ctx)
        end,
    },
    title = {
        flex = 1,
        min_width = 12,
        text = function(note)
            return title_text(note)
        end,
        hl = function(note, ctx)
            return content_hl(note, ctx)
        end,
    },
    slug = {
        flex = 1,
        min_width = 12,
        text = function(note)
            return note.data.slug or ""
        end,
        hl = function(note, ctx)
            return content_hl(note, ctx)
        end,
    },
    path = {
        flex = 1,
        min_width = 12,
        text = function(note)
            return relpath_text(note)
        end,
        hl = "TelescopeResultsComment",
    },
    relpath = {
        flex = 1,
        min_width = 12,
        text = function(note)
            return relpath_text(note)
        end,
        hl = "TelescopeResultsComment",
    },
}

---@param column string|vault.TelescopeNotesColumnSpec
---@return vault.TelescopeNotesColumnSpec?
local function normalize_column(column)
    if type(column) == "string" then
        column = { key = column }
    end
    if type(column) ~= "table" then
        return nil
    end

    local builtin = nil
    if type(column.key) == "string" then
        builtin = BUILTIN_COLUMNS[column.key]
    end

    local resolved = vim.tbl_deep_extend("force", {}, builtin or {}, column)
    if resolved.enabled == false then
        return nil
    end

    if resolved.text == nil and type(resolved.key) == "string" then
        local key = resolved.key
        resolved.text = function(note)
            local value = note.data[key]
            if value == nil then
                return ""
            end
            if type(value) == "string" then
                return value
            end
            return tostring(value)
        end
    end

    if resolved.text == nil then
        return nil
    end

    if resolved.width == nil and not resolved.flex then
        resolved.width = "auto"
    end

    return resolved
end

---@return (string|vault.TelescopeNotesColumnSpec)[]
local function configured_columns()
    local cfg = require("vault.config").options or {}
    local telescope_cfg = cfg.telescope or {}
    local notes_cfg = telescope_cfg.notes or {}
    return notes_cfg.columns or DEFAULT_COLUMNS
end

---@param note vault.Note
---@param column vault.TelescopeNotesColumnSpec
---@param ctx vault.telescope.notes.RenderContext
---@return string
local function column_text(note, column, ctx)
    local value = column.text(note, ctx)
    if value == nil then
        return ""
    end
    if type(value) == "string" then
        return value
    end
    return tostring(value)
end

---@param note vault.Note
---@param column vault.TelescopeNotesColumnSpec
---@param ctx vault.telescope.notes.RenderContext
---@param text string
---@return string?
local function column_hl(note, column, ctx, text)
    if type(column.hl) == "function" then
        return column.hl(note, ctx, text)
    end
    return column.hl
end

---@param columns vault.TelescopeNotesColumnSpec[]
---@param ctx vault.telescope.notes.RenderContext
---@return integer
local function results_width(columns, ctx)
    local layout = ctx.layout or {}
    local layout_config = layout.layout_config or {}
    local picker_width = layout_config.width
    if type(picker_width) ~= "number" then
        picker_width = math.max(1, ctx.ui_width - 4)
    end

    local preview_width = layout_config.preview_width or 0
    if type(preview_width) == "number" and preview_width > 0 and preview_width < 1 then
        preview_width = math.floor(picker_width * preview_width)
    elseif type(preview_width) ~= "number" then
        preview_width = 0
    end

    local budget = picker_width - preview_width
    budget = budget - math.max(0, #columns - 1)
    return math.max(1, budget)
end

---@param results vault.Note[]
---@param columns vault.TelescopeNotesColumnSpec[]
---@param ctx vault.telescope.notes.RenderContext
---@return integer[]
function M.measure(results, columns, ctx)
    local widths = {}
    local mins = {}
    local maxes = {}
    local flex_columns = {}
    local used = 0

    for idx, column in ipairs(columns) do
        local measured = 0
        for _, note in ipairs(results) do
            measured = math.max(measured, display_width(column_text(note, column, ctx)))
        end

        local min_width = column.min_width or (type(column.width) == "number" and column.width or 1)
        local max_width = column.max_width or math.huge
        local width = measured

        if type(column.width) == "number" then
            width = column.width
            min_width = column.width
            max_width = column.width
        else
            width = math.max(min_width, math.min(width, max_width))
            if column.flex and column.flex > 0 then
                width = min_width
                flex_columns[#flex_columns + 1] = idx
            end
        end

        widths[idx] = width
        mins[idx] = min_width
        maxes[idx] = max_width
        used = used + width
    end

    local budget = results_width(columns, ctx)
    local remaining = budget - used
    if remaining > 0 and next(flex_columns) ~= nil then
        local grow = true
        while remaining > 0 and grow do
            grow = false
            local total_flex = 0
            for _, idx in ipairs(flex_columns) do
                local flex = columns[idx].flex or 0
                if widths[idx] < maxes[idx] and flex > 0 then
                    total_flex = total_flex + flex
                end
            end
            if total_flex == 0 then
                break
            end

            for _, idx in ipairs(flex_columns) do
                local flex = columns[idx].flex or 0
                local grow_limit = maxes[idx] - widths[idx]
                if grow_limit > 0 and flex > 0 then
                    local delta = math.max(1, math.floor(remaining * (flex / total_flex)))
                    delta = math.min(delta, grow_limit, remaining)
                    if delta > 0 then
                        widths[idx] = widths[idx] + delta
                        remaining = remaining - delta
                        grow = true
                    end
                end
                if remaining == 0 then
                    break
                end
            end
        end
    elseif remaining < 0 then
        local deficit = -remaining
        while deficit > 0 do
            local shrinkable = {}
            for idx = 1, #columns do
                local room = widths[idx] - mins[idx]
                if room > 0 then
                    shrinkable[#shrinkable + 1] = { idx = idx, room = room }
                end
            end
            if next(shrinkable) == nil then
                break
            end

            table.sort(shrinkable, function(a, b)
                return a.room > b.room
            end)

            for _, item in ipairs(shrinkable) do
                local delta = math.min(item.room, math.max(1, math.floor(deficit / #shrinkable)))
                widths[item.idx] = widths[item.idx] - delta
                deficit = deficit - delta
                if deficit == 0 then
                    break
                end
            end
        end
    end

    return widths
end

---@param columns? (string|vault.TelescopeNotesColumnSpec)[]
---@return vault.TelescopeNotesColumnSpec[]
function M.resolve(columns)
    local raw = columns or configured_columns()
    local resolved = {}
    for _, column in ipairs(raw) do
        local normalized = normalize_column(column)
        if normalized then
            resolved[#resolved + 1] = normalized
        end
    end

    if next(resolved) == nil then
        return M.resolve({ "stem" })
    end

    return resolved
end

---@param columns vault.TelescopeNotesColumnSpec[]
---@param widths integer[]
---@return table[]
function M.items(columns, widths)
    local items = {}
    for idx = 1, #columns do
        items[idx] = { width = widths[idx] }
    end
    return items
end

---@param note vault.Note
---@param columns vault.TelescopeNotesColumnSpec[]
---@param ctx vault.telescope.notes.RenderContext
---@return table[]
function M.cells(note, columns, ctx)
    local cells = {}
    for idx, column in ipairs(columns) do
        local text = column_text(note, column, ctx)
        cells[idx] = { text, column_hl(note, column, ctx, text) }
    end
    return cells
end

return M
