local Object = require("vault.core.object")
--- @type vault.StateManager
local state = require("vault.core.state")
--- @type vault.Note.data.constructor|vault.Note.Data
local NoteData = state.get_global_key("class.vault.Note.data") or require("vault.notes.note.data")
local enums = require("vault.utils.enums")

--- @class vault.Filter.option: vault.Object
--- Array of query terms to include.
--- @field include string[]
--- Array of tag names to exclude.
--- @field exclude string[]
--- @field match_opt vault.enums.match_opts
--- @field mode vault.FilterOpts.mode
--- Whether or not to match case sensitively.
--- @field case_sensitive boolean

--- @class vault.Filter.option.tags: vault.Filter.option

--- @class vault.Filter.option.notes: vault.Filter.option
--- Search term to filter on.
--- @field search_term vault.FilterOpts.search_term

--- Filter tags.
--- @class vault.Filter: vault.Object
--- This module provides functionality for filtering notes based on various criteria.
--- It defines a `VaultFilter` class and related types for specifying filter options.
--- ```lua
--- local filter = require("vault.filter")
--- local opts = {
---    {
---        search_term = "tags",
---        include = { "foo" },
---        exclude = { "bar" },
---        match_opt = "exact",
---        mode = "all",
---        case_sensitive = false,
---    },
---    {
---        search_term = "tags",
---        include = { "baz" },
---        exclude = { "qux" },
---        match_opt = "exact",
---        mode = "all",
---        case_sensitive = false,
---    },
--- }
--- local filtered_notes = notes:filter(opts)
--- ```
local Filter = Object("VaultFilter")

--- Convert args to opts.
---
--- Table of filter opts.
--- @param opt vault.Filter.option|vault.Filter.option[]
--- @return vault.Filter.option
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
--- Table of filter opts.
--- @param opts vault.Filter.option|vault.Filter.option[]
--- Search term to filter on.
--- @param search_term? string
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

    --- @type table<string, vault.Filter.option>
    self.opts = {}
    for k, opt in pairs(opts) do
        -- Validate opts
        if type(opt) ~= "table" then
            error("invalid argument: must be a table: " .. vim.inspect(opt))
        elseif not opt.search_term then
            if not search_term then
                error("invalid argument: must have a search term: " .. vim.inspect(opt))
            end
            --- @diagnostic disable-next-line: inject-field
            opt.search_term = search_term
        elseif type(opt.search_term) ~= "string" then
            error("invalid argument: must be a string: " .. vim.inspect(opt.search_term))
        end

        self.opts[k] = {}

        -- Validate `search_term`
        if type(opt.search_term) ~= "string" or type(opt.search_term) ~= "string" then
            error("invalid argument: must be a string: " .. vim.inspect(opt.search_term))
        elseif not NoteData[opt.search_term] then
            error("invalid argument: must be a valid search term: " .. vim.inspect(opt.search_term))
        end
        self.opts[k].search_term = opt.search_term

        -- Validate `include`
        if opt.include and type(opt.include) == "string" then
            --- @diagnostic disable-next-line: assign-type-mismatch
            opt.include = { opt.include }
        end
        if opt.include and type(opt.include) ~= "table" then
            error("invalid argument: must be a table: " .. vim.inspect(opt.include))
        end
        self.opts[k].include = opt.include or {}

        -- Validate `exclude`
        if opt.exclude and type(opt.exclude) == "string" then
            --- @diagnostic disable-next-line: assign-type-mismatch
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
    -- Store last filter to state
    state.set_global_key("recent.filter", self)
end

-- Invert filter options
function Filter:invert()
    for k, opt in pairs(self.opts) do
        opt.include = vim.tbl_filter(function(v)
            return not vim.tbl_contains(opt.exclude, v)
        end, opt.include)
        opt.exclude = vim.tbl_filter(function(v)
            return not vim.tbl_contains(opt.include, v)
        end, opt.exclude)
    end
    -- Store last filter to state
    state.set_global_key("recent.filter", self)
    return self
end

--- Filter
--- @alias vault.Filter.constructor fun(opts:
--- @type vault.Filter.constructor|vault.Filter
local M = Filter

return M
