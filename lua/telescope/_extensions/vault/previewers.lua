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
-- Previewer for bases: show filter tree, formulas, views, and properties
M.bases = previewers.new_buffer_previewer({
    --- @param self table
    --- @param entry { value: vault.Base }
    define_preview = function(self, entry)
        --- @type vault.Base
        local base = entry.value
        --- @type string[]
        local lines = {}

        -- Header
        table.insert(lines, "# " .. base.data.name)
        table.insert(lines, "")

        -- Filters
        if base:has_filters() then
            table.insert(lines, "## Filters")
            table.insert(lines, "```yaml")
            local filter_str = vim.inspect(base.data.filters)
            for _, line in ipairs(vim.split(filter_str, "\n")) do
                table.insert(lines, line)
            end
            table.insert(lines, "```")
            table.insert(lines, "")
        else
            table.insert(lines, "## Filters")
            table.insert(lines, "_No filters defined_")
            table.insert(lines, "")
        end

        -- Formulas
        if base:has_formulas() then
            table.insert(lines, "## Formulas")
            for name, expr in pairs(base.data.formulas) do
                table.insert(lines, string.format("- **%s**: `%s`", name, expr))
            end
            table.insert(lines, "")
        end

        -- Views
        local view_count = base:view_count()
        if view_count > 0 then
            table.insert(lines, "## Views (" .. tostring(view_count) .. ")")
            for i, view in ipairs(base.data.views) do
                local view_name = view.name or view.type or ("view " .. tostring(i))
                local view_type = view.type or "table"
                table.insert(lines, string.format("- **%s** (%s)", view_name, view_type))
            end
            table.insert(lines, "")
        end

        -- Properties
        if base.data.properties and next(base.data.properties) then
            table.insert(lines, "## Properties")
            for key, prop in pairs(base.data.properties) do
                if type(prop) == "table" and prop.displayName then
                    table.insert(lines, string.format("- **%s** → %s", key, prop.displayName))
                else
                    table.insert(lines, string.format("- %s", key))
                end
            end
            table.insert(lines, "")
        end

        -- File info
        table.insert(lines, "---")
        table.insert(lines, "Path: " .. (base.data.relpath or ""))

        --- @type integer
        local bufnr = self.state.bufnr
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        vim.api.nvim_set_option_value("filetype", "markdown", {
            buf = bufnr,
            scope = "local",
        })
    end,
})

return M
