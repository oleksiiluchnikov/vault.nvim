--- TODO: Make action that will search for notes with similar tags that selected note has
--- If we have note with tags: status/TODO, class/Action, class/Action/Project
--- We could search for notes containing tags: status/TODO, class/Action, class/Action/Project
--- With mode "all" or "any"

--- Search for notes in Inbox directory
--- @param opts? telescope_popup_options.vault.Notes
--- @return Picker
return function(opts)
    local config = require("vault.config")
    local dirs = config.options.dirs or {}
    local inbox_dir = dirs.inbox or config.options.root
    if not inbox_dir or vim.fn.isdirectory(inbox_dir) == 0 then
        error("Inbox directory does not exist")
    end

    return require("telescope._extensions.vault.pickers.notes")(
        vim.tbl_extend("force", opts or {}, {
            _dynamic = true,
            _prepare = function()
                local Notes = require("vault.notes")
                local link_index = require("vault.notes.link_index")
                local raw_paths = link_index.paths()
                local inbox_prefix = inbox_dir:gsub("/+$", "") .. "/"
                local inbox_paths = {}

                for slug, data in pairs(raw_paths) do
                    if
                        data.path == inbox_dir
                        or data.path:sub(1, #inbox_prefix) == inbox_prefix
                    then
                        inbox_paths[slug] = data
                    end
                end

                return {
                    notes = Notes.from_paths(inbox_paths),
                    wikilinks_map = link_index.wikilinks(),
                }
            end,
        })
    )
end
