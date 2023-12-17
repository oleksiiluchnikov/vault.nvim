local Object = require("vault.core.object")
local state = require("vault.core.state")
local utils = require("vault.utils")
local Filter = require("vault.filter")
local fetcher = require("vault.fetcher")

---@alias VaultRipGrepMatch {type: string, data: {absolute_offset: number, line_number: number, lines: {text: string}, path: {text: string}, submatches: {match: {text: string}, start: number, end: number}}}

---@alias VaultMap.tags table<string, VaultTag> - Map of tags.
---@alias VaultArray.tags table<integer, VaultTag> - Map of tags.

---@alias VaultMap.tags.sources table<string, table> - Map of tags sources.

---@alias VaultTagsGroup VaultTags - Tags that have children.

---@class VaultTags: VaultObject - Retrieve tags from vault.
---@field map VaultMap.tags - Map of tags.
---@field nested VaultTagsGroup -- Tags that have children.
---@field sources fun(self: VaultTags): VaultMap.tags.sources - Get all sources from tags.
---@field list fun(self: VaultTags): VaultArray.tags - Return `VaultTags` as a `VaultArray`.
local Tags = Object("VaultTags")

--- Retrieve all tags names from your vault.
function Tags:init()
    self.map = fetcher.tags()
    state.set_global_key("tags", self)
end

--- Filter tags with `VaultFilter.options.tags`
---
---@param opts VaultFilter.option.tags|VaultFilter.option.tags[]
---@return VaultTagsGroup
function Tags:filter(opts)
    if not opts then
        error("invalid argument: must be a table: " .. vim.inspect(opts))
    end
    if not opts.class then
        opts = Filter(opts, "tags")
    end
    opts = opts.opts
    for _, opt in ipairs(opts) do
        for tag_name, _ in pairs(self.map) do
            for _, query in ipairs(opt.include) do
                if utils.match(tag_name, query, opt.match_opt, opt.case_sensitive) == false then
                    if self.map[tag_name] then
                        self.map[tag_name] = nil
                    end
                end
            end

            for _, query in ipairs(opt.exclude) do
                if utils.match(tag_name, query, opt.match_opt, opt.case_sensitive) == true then
                    if self.map[tag_name] then
                        self.map[tag_name] = nil
                    end
                end
            end
        end
    end
    return self
end

--- Return a list of key values from tags.
---
---@param key string - The key to get values for.
---@return string[] - The values for the key.
---@see VaultTag
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
---string
---@return VaultArray.tags
function Tags:list()
    ---@type VaultArray.tags
    return vim.tbl_values(self.map)
end

---@return VaultTag
function Tags:get_random_tag()
    local tags = self:list()
    local random_tag = tags[math.random(#tags)]
    return random_tag
end

---@param key string - The key to filter by.
---| "'name'" # Filter by tag name.
---| "'notes_paths'" # Filter by notes paths.
---@param value string? - The value to filter by.
---@param match_opt? string - The match option to use.
---@return VaultMap.tags
function Tags:by(key, value, match_opt)
    assert(key, "missing `key` argument: string")
    local tags = self:list()
    local tags_by = {}
    for _, tag in pairs(tags) do
        if tag[key] and not value then
            table.insert(tags_by, tag)
        elseif tag[key] and value then
            if utils.match(tag[key], value, match_opt) then
                table.insert(tags_by, tag)
            end
        end
    end
    return tags_by
end

--- Return a map of all sources from tags.
---
---@return VaultMap.tags.sources
function Tags:sources()
    local tags = self:list()
    ---@type VaultMap.tags.sources
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

---@alias VaultTags.constructor fun(filter_opts?: table): VaultTags
---@type VaultTags.constructor|VaultTags
local VaultTags = Tags

state.set_global_key("_class.VaultTags", VaultTags)
return VaultTags
