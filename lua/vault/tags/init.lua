local Object = require("vault.core.object")
local state = require("vault.core.state")
local utils = require("vault.utils")
local Filter = require("vault.filter")
local fetcher = require("vault.fetcher")

-- Aliases
--- @alias vault.Tags.map table<string, vault.Tag> - Map of tags.
--- @alias vault.Tags.list table<integer, vault.Tag> - Map of tags.

--- @alias VaultMap.tags.sources table<string, table> - Map of tags sources.

--- @alias VaultTagsGroup vault.Tags - Tags that have children.

--- VaultTags class represents a collection of tags loaded from vault.
--- @class vault.Tags: vault.Object - Retrieve tags from vault.
--- @field map vault.Tags.map - Map of tags.
--- @field nested VaultTagsGroup -- Tags that have children.
--- @field sources fun(self: vault.Tags): VaultMap.tags.sources - Get all sources from tags.
--- @field list fun(self: vault.Tags): vault.Tags.list - Return `VaultTags` as a `VaultArray`.
local Tags = Object("VaultTags")

--- Initializes the VaultTags object by fetching all tags from the vault.
--- Sets the tags map and registers the tags globally.
--- @return nil
function Tags:init()
    self.map = fetcher.tags()
    state.set_global_key("tags", self)
end

--- Returns the number of tags in the tags map.
--- @return integer Number of tags
function Tags:count()
    return #vim.tbl_keys(self.map)
end

--- Filters the tags based on the provided filter options.
---
--- Removes any tags that don't match the include rules or match the exclude rules.
---
--- @param opts vault.Filter.option.tags|vault.Filter.option.tags[] Filter options
--- @return vault.Tags Updated VaultTags object with filtered tags
function Tags:filter(opts)
    if not opts then
        error("invalid argument: must be a table: " .. vim.inspect(opts))
    end

    if not opts.class then
        -- opts = Filter(opts, "tags").opts
        opts = Filter(opts, "tags").opts
    end

    -- opts = opts.opts

    --- Applies include filters to tags.
    --- Removes tags that don't match any include rules.
    --- @param tag_name string Tag name
    --- @param queries vault.List List of query strings
    --- @param match_result boolean
    --- @param match_opt vault.enum.MatchOpts.key Match option
    --- @param case_sensitive boolean Case sensitive
    local function apply_filter(tag_name, queries, match_result, match_opt, case_sensitive)
        if not queries then
            return
        end
        for _, query in ipairs(queries) do
            if utils.match(tag_name, query, match_opt, case_sensitive) == match_result then
                if self.map[tag_name] then
                    self.map[tag_name] = nil
                end
            end
        end
    end

    -- { {
    --     case_sensitive = false,
    --     exclude = {},
    --     include = { "software/obsidian", "software", "software/bettertouchtool", "software/keyboard-maestro", "software/photoshop/layer/blending-mode", "software/bettertouprogramming/language/c
    -- htool", "software/obsidian/vault", "software/obsidian/leaflet", "software/zbrush", "software-development", "software/fusion360", "software/neovim", "software/obsidian/commands", "software/b
    -- lender", "software/neovim/plugin/telescope", "software/alacritty", "software/photoshop", "software/wezterm", "software/neovim/plugin/luasnip", "software/raycast", "software/keyboard-maestro
    -- /macro", "software/obsidian/templater", "software/obsidian/template", "software/obsidian/tags", "software/xbar", "software/cli/crontab", "software/hammerspoon", "software/neovim/plugin", "s
    -- oftware/photoshop-brushes", "software/photoshop/layer", "software/eagle" },
    --     match_opt = "exact",
    --     mode = "any",
    --     search_term = "tags"
    --   } } - FIXME: This filter is returnning an empty table.
    for _, opt in pairs(opts) do
        for tag_name, _ in pairs(self.map) do
            apply_filter(tag_name, opt.include, false, opt.match_opt, opt.case_sensitive)
            apply_filter(tag_name, opt.exclude, true, opt.match_opt, opt.case_sensitive)
        end
    end

    return self
end

--- Return a list of values for a key from tags.
---
--- @param key string Key to get values for
--- @return any[] Values for the key
--- @see VaultTag
function Tags:get_values_by_key(key)
    local values = {}
    for _, tag in pairs(self.map) do
        if tag.data[key] then
            table.insert(values, tag.data[key])
        end
    end
    return values
end

--- Return `VaultTags` as a `VaultArray`.
--- string
--- @return vault.Tags.list
function Tags:list()
    --- @type vault.Tags.list
    return vim.tbl_values(self.map)
end

--- @return vault.Tag
function Tags:get_random_tag()
    local tags = self:list()
    local random_tag = tags[math.random(#tags)]
    return random_tag
end

--- @param key string - The key to filter by.
--- | "'name'" # Filter by tag name.
--- | "'notes_paths'" # Filter by notes paths.
--- @param value? string - The value to filter by.
--- @param match_opt? string - The match option to use.
--- @return vault.Tags.map
function Tags:by(key, value, match_opt)
    if not key then
        error("missing `key` argument: string")
    end
    match_opt = match_opt or "exact"
    local tags = self:list()
    local tags_by = {}
    for _, tag in pairs(tags) do
        if tag.data[key] and not value then
            tags_by[tag.data.name] = tag
        elseif tag.data[key] and value then
            if utils.match(tag.data[key], value, match_opt) then
                tags_by[tag.data.name] = tag
            end
        end
    end
    self.map = tags_by
    return self
end

--- Return a map of all sources from tags.
---
--- @return VaultMap.tags.sources
function Tags:sources()
    local tags = self:list()
    --- @type VaultMap.tags.sources
    local sources_map = {}

    for _, tag in pairs(tags) do
        for slug, _ in pairs(tag.data.sources) do
            if not sources_map[slug] then
                sources_map[slug] = {}
            end
            if not sources_map[slug][tag.data.name] then
                sources_map[slug][tag.data.name] = tag
            end
        end
    end

    return sources_map
end

function Tags:reset()
    state.clear_all()
    self:init()
end

--- @alias VaultTags.constructor fun(filter_opts?: table): vault.Tags
--- @type VaultTags.constructor|vault.Tags
local VaultTags = Tags

state.set_global_key("class.vault.Tags", VaultTags)
return VaultTags
