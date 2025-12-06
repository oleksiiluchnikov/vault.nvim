--- @class telescope_popup_options.vault.cluster: telescope_popup_options
--- @field path? string Path to note to open build cluster from
--- @field notes? vault.Notes Notes instance to use
--- @field depth? number Depth of cluster to build

--- Open picker for |vault.Notes.Cluster| from provided `vault.Note`. Default is current buffer.
--- @param opts table
--- @return Picker
return function(opts)
    opts = opts or {}
    opts.notes = opts.notes or require("vault.notes")()
    opts.path = opts.path or vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
    opts.depth = opts.depth or 0
    local note = require("vault.notes.note")(opts.path)

    local notes_cluster = require("vault.notes.cluster")(opts.notes, note, opts.depth)
    if next(notes_cluster.map) == nil then
        error("No notes found in cluster")
    end
    return require("telescope._extensions.vault.pickers.notes")(opts)
end
