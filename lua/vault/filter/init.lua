local Object = require("vault.core.object")
local note_data = require("vault.notes.note.data")
local enums = require("vault.utils.enums")
---@class VaultFilter.option: VaultObject
---@field include string[] - Array of tag names to include (optal).
---@field exclude string[] - Array of tag names to exclude (optal).
---@field match_opt VaultMatchOptsKey - Match type for filtering notes (optal). Opts: "exact", "contains", "startswith", "endswith", "regex". "fuzzy"
---@field mode - Behavior for filtering notes (optal). Opts: "all", "any"
---|"'all'"  # Matches all names.
---|"'any'" # Matches any value.
---@field case_sensitive boolean - Whether or not to match case sensitively.

---@class VaultFilter.option.tags: VaultFilter.option

---@class VaultFilter.option.notes: VaultFilter.option
---@field search_term string - Search term to filter on.
---|"'tag'" # Filter on tags.
---|"'slug'" # Filter on slugs.
---|"'title'" # Filter on title.
---|"'body'" # Filter on body.
---|"'status'" # Filter on status.
---|"'type'" # Filter on type.

---@class VaultFilter: VaultObject - Filter tags.
local Filter = Object("VaultFilter")

--- Convert args to opts.
---
---@param opt VaultFilter.option|VaultFilter.option[] - Table of filter opts.
---@return VaultFilter.option
local function args_to_opts(opt)
    local new_opts = {}
    -- try to convert to a table
    for i, v in ipairs(opt) do
        if i == 1 and type(v) == "string" then
            new_opts.search_term = v
        elseif i == 2 then
            if type(v) == "table" or type(v) == "string" then
                new_opts.include = v
            end
        elseif i == 3 then
            if type(v) == "table" or type(v) == "string" then
                new_opts.exclude = v
            end
        elseif i == 4 and type(v) == "string" then
            new_opts.match_opt = v
        elseif i == 5 and type(v) == "string" then
            new_opts.mode = v
        elseif i == 6 and type(v) == "boolean" then
            new_opts.case_sensitive = v
        else
            error("invalid argument: must be a table: " .. vim.inspect(opt))
        end
    end
    return new_opts
end

--- Create a new Filter object.
---
---@param opts VaultFilter.option|VaultFilter.option[] - Table of filter opts.
---@param search_term string? - Search term to filter on.
function Filter:init(opts, search_term)
    -- if not any valid
    if not opts then
        error("invalid argument: must be a table: " .. vim.inspect(opts))
    elseif type(opts) ~= "table" then
        error("invalid argument: must be a table: " .. vim.inspect(opts))
    end

    if vim.tbl_islist(opts) and type(opts[1]) ~= "table" then
        opts = args_to_opts(opts)
    end

    if type(vim.tbl_keys(opts)[1]) == "string" then
        opts = { opts }
    end

    ---@type table<string, VaultFilter.option>
    self.opts = {}
    for k, opt in pairs(opts) do
        -- Validate opts
        if type(opt) ~= "table" then
            error("invalid argument: must be a table: " .. vim.inspect(opt))
        elseif not opt.search_term then
            if not search_term then
                error("invalid argument: must have a search term: " .. vim.inspect(opt))
            end
            opt.search_term = search_term
        elseif type(opt.search_term) ~= "string" then
            error("invalid argument: must be a string: " .. vim.inspect(opt.search_term))
        end

        self.opts[k] = {}

        -- Validate `search_term`
        if type(opt.search_term) ~= "string" or type(opt.search_term) ~= "string" then
            error("invalid argument: must be a string: " .. vim.inspect(opt.search_term))
        elseif not note_data[opt.search_term] then
            error("invalid argument: must be a valid search term: " .. vim.inspect(opt.search_term))
        end
        self.opts[k].search_term = opt.search_term

        -- Validate `include`
        if opt.include and type(opt.include) == "string" then
            opt.include = { opt.include }
        end
        if opt.include and type(opt.include) ~= "table" then
            error("invalid argument: must be a table: " .. vim.inspect(opt.include))
        end
        self.opts[k].include = opt.include or {}

        -- Validate `exclude`
        if opt.exclude and type(opt.exclude) == "string" then
            opt.exclude = { opt.exclude }
        end
        if opt.exclude and type(opt.exclude) ~= "table" then
            error("invalid argument: must be a table: " .. vim.inspect(opt.exclude))
        end
        self.opts[k].exclude = opt.exclude or {}

        -- Verify that `include` and `exclude` both have at least one value
        if next(self.opts[k].include) == nil and next(self.opts[k].exclude) == nil then
            error(
                "invalid argument: must have at least one include or exclude: " .. vim.inspect(opt)
            )
        end

        -- Validate `match_opt`
        if opt.match_opt and type(opt.match_opt) ~= "string" then
            error("invalid argument: must be a string: " .. vim.inspect(opt.match_opt))
        elseif opt.match_opt and not enums.match_opts[opt.match_opt] then
            error("invalid argument: must be a valid match_opt: " .. vim.inspect(opt.match_opt))
        end
        self.opts[k].match_opt = opt.match_opt or "exact"

        -- Validate `mode`
        if opt.mode and type(opt.mode) ~= "string" then
            error("invalid argument: must be a string: " .. vim.inspect(opt.mode))
        elseif opt.mode and not enums.filter_mode[opt.mode] then
            error("invalid argument: must be a valid mode: " .. vim.inspect(opt.mode))
        end
        self.opts[k].mode = opt.mode or "all"

        -- Validate `case_sensitive`
        if opt.case_sensitive and type(opt.case_sensitive) ~= "boolean" then
            error("invalid argument: must be a boolean: " .. vim.inspect(opt.case_sensitive))
        end
        self.opts[k].case_sensitive = opt.case_sensitive or false
    end
end

---@alias VaultFilter.constructor fun(opts: VaultFilter.option|VaultFilter.option[], search_term: string?): VaultFilter
---@type VaultFilter.constructor|VaultFilter
local VaultFilter = Filter

return VaultFilter
