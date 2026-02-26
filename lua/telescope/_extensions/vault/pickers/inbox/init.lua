--- TODO: Make action that will search for notes with similar tags that selected note has
--- If we have note with tags: status/TODO, class/Action, class/Action/Project
--- We could search for notes containing tags: status/TODO, class/Action, class/Action/Project
--- With mode "all" or "any"

--- Search for notes in Inbox directory
--- @param opts? telescope_popup_options.vault.Notes
--- @return Picker
return function(opts)
    local config = require("vault.config")
    local inbox_dir = config.options.dirs.inbox or config.options.root
    if not inbox_dir or vim.fn.isdirectory(inbox_dir) == 0 then
        error("Inbox directory does not exist")
    end

    opts = opts or {}
    opts.notes = opts.notes or require("vault.notes")()
    local utils = require("vault.utils")
    for _, note_path in
        ipairs(utils.safe_globpath(inbox_dir, "**/*" .. config.options.ext, true, true))
    do
        opts.notes:push(require("vault.notes.note")(note_path))
    end

    return require("telescope._extensions.vault.pickers.notes")(opts)
end
