local Collection = require("vault.core.collection")
local state = require("vault.core.state")
local utils = require("vault.utils")
local Filter = require("vault.filter")
local function scanner()
    return require("vault.scanner")
end

-- Aliases
--- @alias vault.Tags.map table<string, vault.Tag> - Map of tags.
--- @alias vault.Tags.list table<integer, vault.Tag> - Map of tags.

--- @alias vault.Map.tags.sources vault.Sources.map - Map of sources.

--- @alias vault.TagsGroup vault.Tags - Tags that have children.

--- VaultTags class represents a collection of tags loaded from vault.
--- @class vault.Tags: vault.Object - Retrieve tags from vault.
--- @field map vault.Tags.map - Map of tags.
--- @field nested vault.TagsGroup -- Tags that have children.
--- @field sources fun(self: vault.Tags): vault.Map.tags.sources - Get all sources from tags.
--- @field list fun(self: vault.Tags): vault.Tags.list - Return `VaultTags` as a `VaultArray`.
local Tags = Collection:extend("VaultTags")

--- Initializes the VaultTags object by scanning all tags from the vault.
--- Sets the tags map and registers the tags globally.
--- @return nil
function Tags:init()
    self.map = scanner().tags()
    state.set_global_key("tags", self)
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

--- @alias VaultTags.constructor fun(filter_opts?: table): vault.Tags
--- @type VaultTags.constructor|vault.Tags
local VaultTags = Tags

state.set_global_key("class.vault.Tags", VaultTags)
return VaultTags
