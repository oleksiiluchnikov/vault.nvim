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
        if view_count > 0 and type(base.data.views) == "table" then
            table.insert(lines, "## Views (" .. tostring(view_count) .. ")")
            for i, view in ipairs(base.data.views) do
                local view_name = view.name or view.type or ("view " .. tostring(i))
                local view_type = view.type or "table"
                table.insert(lines, string.format("- **%s** (%s)", view_name, view_type))
            end
            table.insert(lines, "")
        end

        -- Properties
        if type(base.data.properties) == "table" and next(base.data.properties) then
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

-- Previewer for wikilinks: resolved shows target file, unresolved lists sources
M.wikilinks = previewers.new_buffer_previewer({
    --- @param self table
    --- @param entry { value: vault.Wikilink }
    define_preview = function(self, entry)
        local utils = require("vault.utils")
        --- @type vault.Wikilink
        local wikilink = entry.value
        local data = wikilink.data
        --- @type string[]
        local lines = {}

        local target_slug = data and data.target
        local abs_path = target_slug and utils.slug_to_path(target_slug) or nil
        local resolved = abs_path and vim.fn.filereadable(abs_path) == 1

        if resolved then
            -- Show the target note content (like the notes previewer)
            local ok, file_lines = pcall(vim.fn.readfile, abs_path)
            if ok and file_lines then
                lines = file_lines
            else
                lines = { "(could not read " .. abs_path .. ")" }
            end
        else
            -- Unresolved: show a synthesized summary of all sources
            local slug = data and data.slug or "<unknown>"
            table.insert(lines, "# [[" .. slug .. "]]")
            table.insert(lines, "")
            table.insert(lines, "_Unresolved wikilink — note does not exist yet._")
            table.insert(lines, "")

            local sources = data and data.sources
            if type(sources) == "table" and next(sources) then
                local source_count = vim.tbl_count(sources)
                table.insert(lines, "## Referenced in " .. tostring(source_count) .. " note(s)")
                table.insert(lines, "")

                for source_slug, lnum_map in pairs(sources) do
                    local relpath = utils.slug_to_relpath(source_slug)
                    if type(lnum_map) == "table" then
                        -- Collect line numbers from the sources map
                        local lnums = {}
                        for lnum, _ in pairs(lnum_map) do
                            if type(lnum) == "number" then
                                table.insert(lnums, lnum)
                            end
                        end
                        table.sort(lnums)
                        if #lnums > 0 then
                            local lnum_strs = {}
                            for _, n in ipairs(lnums) do
                                table.insert(lnum_strs, tostring(n))
                            end
                            table.insert(
                                lines,
                                "- " .. relpath .. " (line " .. table.concat(lnum_strs, ", ") .. ")"
                            )
                        else
                            table.insert(lines, "- " .. relpath)
                        end
                    else
                        table.insert(lines, "- " .. relpath)
                    end
                end
            else
                table.insert(lines, "_No source references found._")
            end

            -- Aliases / variants
            if data and type(data.aliases) == "table" and next(data.aliases) then
                table.insert(lines, "")
                table.insert(lines, "## Aliases")
                for alias, _ in pairs(data.aliases) do
                    table.insert(lines, "- " .. alias)
                end
            end
        end

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
