local previewers = require("telescope.previewers")
local state = require("vault.core.state")
local M = {}

M.notes = previewers.vim_buffer_vimgrep.new({
    get_buffer_by_name = function(_, entry)
        local bufnr = vim.api.nvim_create_buf(false, true)
        if type(bufnr) ~= "number" then
            error("bufnr is not a number")
        end

        local lines = vim.fn.readfile(entry.filename)

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        vim.api.nvim_set_option_value("filetype", "markdown", {
            win = vim.api.nvim_get_current_win(),
            scope = "local",
        })

        return bufnr
    end,
})

-- TODO: Optimize this previewer
M.tags = previewers.new_buffer_previewer({
    --- @param self table
    --- @param entry { value: vault.Tag }
    define_preview = function(self, entry)
        local utils = require("vault.utils")
        --- @type vault.Tag
        local tag = entry.value
        local sources = tag.data.sources
        --- @type string[]
        local lines = {}
        --- @type vault.Tag.Documentation
        local documentation = tag.data.documentation:content()

        --- TODO: Implement documentation to previewer
        if documentation and documentation ~= "" then
            local doc_lines = vim.split(documentation, "\n")
            for _, doc_line in ipairs(doc_lines) do
                table.insert(lines, doc_line)
            end
            local separator = string.rep("-", 80)
            table.insert(lines, separator)
        end

        local seen_notes_paths = {}
        for slug, _ in pairs(sources) do
            local relpath = utils.slug_to_relpath(slug)
            if not seen_notes_paths[relpath] then
                seen_notes_paths[relpath] = true
                table.insert(lines, relpath)
            end
        end
        --- @type integer
        local bufnr = self.state.bufnr
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        vim.api.nvim_set_option_value("filetype", "markdown", {
            buf = bufnr,
            scope = "local",
        })
        return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    end,
})
return M
