local Engine = require("vault.scanner.engine")
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

local Scanner = {}

function Scanner.paths()
    local core = require("vault_core")
    local root = vim.fn.expand(config.options.root)
    local map = core.paths(root)
    state.set_global_key("cache.notes.paths", map)
    return map
end

function Scanner.slugs()
    local core = require("vault_core")
    local root = vim.fn.expand(config.options.root)
    local slugs = core.slugs(root)
    state.set_global_key("cache.notes.slugs", slugs)
    return slugs
end

function Scanner.tags()
    local core = require("vault_core")
    local root = vim.fn.expand(config.options.root)
    local raw_tags = core.tags(root)

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

    return tags_map
end

function Scanner.wikilinks()
    local core = require("vault_core")
    local root = vim.fn.expand(config.options.root)
    local raw_wikilinks = core.wikilinks(root)

    -- Convert raw wikilink data to Wikilink objects
    local wikilinks_map = {}
    for stem, wikilink_data in pairs(raw_wikilinks) do
        -- Create wikilink with minimal data - it will resolve target on access
        local wl = Wikilink({
            raw = "[[" .. stem .. "]]",
            sources = wikilink_data.sources,
        })

        -- Copy additional data from Rust
        wl.data.stem = wikilink_data.stem
        wl.data.count = wikilink_data.count
        wl.data.embedded = wikilink_data.embedded

        wikilinks_map[stem] = wl
    end

    return wikilinks_map
end

function Scanner.tasks()
    local core = require("vault_core")
    local root = vim.fn.expand(config.options.root)
    local raw_tasks = core.tasks(root)

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

    return tasks_map
end

function Scanner.links()
    local core = require("vault_core")
    local root = vim.fn.expand(config.options.root)
    -- External links are already in simple format, no object wrapping needed
    return core.links(root)
end

function Scanner.fields()
    local core = require("vault_core")
    local root = vim.fn.expand(config.options.root)
    -- Fields are already in the right format (nested map structure)
    return core.fields(root)
end

function Scanner.properties()
    local core = require("vault_core")
    local root = vim.fn.expand(config.options.root)
    local raw_properties = core.properties(root)

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

    return properties_map
end

function Scanner.dirs()
    local core = require("vault_core")
    local root = vim.fn.expand(config.options.root)
    local raw_dirs = core.dirs(root)

    -- Convert raw dir data to Dir objects
    local dirs_map = {}
    for relpath, _ in pairs(raw_dirs) do
        local path = utils.relpath_to_path(relpath)
        dirs_map[relpath] = Dir({
            path = path,
            relpath = relpath,
        })
    end

    state.set_global_key("dirs", dirs_map)
    return dirs_map
end

function Scanner.refresh()
    -- clear cache and state
    state.clear_all()
end
-- refresh all data

return Scanner
