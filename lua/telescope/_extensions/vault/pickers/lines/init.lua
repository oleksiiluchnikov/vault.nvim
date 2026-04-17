return function(opts)
    local entry_display = require("telescope.pickers.entry_display")
    local pickers = require("telescope.pickers")
    local sorters = require("telescope.sorters")
    local telescope_config = require("telescope.config")
    local vault_state = require("vault.core.state")
    local log = require("vault.log").scope("telescope")
    local vault_mappings = require("telescope._extensions.vault.mappings")
    local vault_hl = require("telescope._extensions.vault.highlights")
    local layouts = require("telescope._extensions.vault.layouts")
    local progressive = require("telescope._extensions.vault.pickers.progressive")

    opts = opts or {}

    local function format_metadata(metadata)
        if not metadata or vim.tbl_isempty(metadata) then
            return ""
        end

        local parts = {}
        for k, v in pairs(metadata) do
            parts[#parts + 1] = string.format("%s:%s", k, v)
        end
        return table.concat(parts, " ")
    end

    local function format_list(items)
        if not items or vim.tbl_isempty(items) then
            return ""
        end

        return table.concat(items, " ")
    end

    local function truncate(str, max)
        if #str > max then
            return str:sub(1, max - 3) .. "..."
        end

        return str
    end

    local _, screen_width = layouts.ui_size()
    local max_widths = {
        content = math.min(60, math.floor((screen_width - 13) * 0.5)),
        metadata = math.min(30, math.floor((screen_width - 13) * 0.2)),
        tags = math.min(20, math.floor((screen_width - 13) * 0.15)),
        wikilinks = math.min(20, math.floor((screen_width - 13) * 0.15)),
        count = 5,
    }

    ---@param line vault.Line
    ---@return string
    local function searchable_text(line)
        return table
            .concat({
                tostring(line.data.content or ""),
                format_metadata(line.data.metadata),
                format_list(line.data.tags),
                format_list(line.data.wikilinks),
            }, " ")
            :lower()
    end

    ---@return Sorter
    local function base_sorter()
        local generic_sorter = telescope_config.values and telescope_config.values.generic_sorter
        if type(generic_sorter) == "function" then
            return generic_sorter({})
        end
        return sorters.get_fzy_sorter()
    end

    ---@return { entry_maker: fun(line: vault.Line): table, results: vault.Line[] }
    local function prepare_picker_data()
        local source = type(opts._prepare) == "function" and opts._prepare() or {}
        if type(source) ~= "table" then
            source = {}
        end

        local lines = opts.lines or source.lines
        if not lines and type(opts._lines_provider) == "function" then
            lines = opts._lines_provider()
        end
        if not lines then
            lines = require("vault.lines")()
        end

        local results = source.results or lines:list()
        local steps = math.max(1, math.min(64, vim.tbl_count(results)))
        local hl_name = "VaultLine"
        local colors = vault_hl.setup(hl_name, steps, { "Comment", "Normal", "String" })
        local displayer = entry_display.create({
            separator = " │ ",
            items = {
                { width = max_widths.content },
                { width = max_widths.metadata },
                { width = max_widths.tags },
                { width = max_widths.wikilinks },
                { width = max_widths.count },
            },
        })

        local function make_display(entry)
            local line = entry.value
            local sources_count = line.data.count
            local content_hl = "TelescopeResultsNormal"
            if colors then
                local index = math.min(math.floor(sources_count / 2), steps)
                if index == 0 then
                    index = 1
                end
                content_hl = hl_name .. tostring(index)
            end

            return displayer({
                { truncate(line.data.content, max_widths.content), content_hl },
                { truncate(format_metadata(line.data.metadata), max_widths.metadata), "Comment" },
                { truncate(format_list(line.data.tags), max_widths.tags), "Special" },
                { truncate(format_list(line.data.wikilinks), max_widths.wikilinks), "Type" },
                { tostring(sources_count), "Number" },
            })
        end

        local function entry_maker(line)
            return {
                value = line,
                ordinal = searchable_text(line),
                display = make_display,
            }
        end

        return {
            entry_maker = entry_maker,
            results = results,
        }
    end

    if opts._measure_ready_only == true then
        return prepare_picker_data()
    end

    local session = progressive.new({
        empty_message = "No lines found",
        empty_prompt_limit = opts.empty_prompt_limit,
        loading_message = opts.loading_message or "Collecting lines...",
        prepare = prepare_picker_data,
        prompt_result_limit = opts.prompt_result_limit,
        search_text = searchable_text,
    })
    local base_attach = vault_hl.make_attach_mappings(vault_mappings.lines, "VaultLine", nil)
    local picker
    local picker_opts = {
        prompt_title = "Lines",
        finder = session:finder(),
        sorter = base_sorter(),
        layout_config = { width = screen_width },
        get_status_text = function()
            if session.state ~= "ready" then
                return " collecting"
            end
            if session.count_pending then
                return string.format(" ... / %d", #session.results)
            end
            return string.format(" %d / %d", session.last_matched_count or 0, #session.results)
        end,
        attach_mappings = function(prompt_bufnr, map)
            local attached = base_attach(prompt_bufnr, map)
            session:start(picker, {
                after_refresh = function()
                    if type(opts._on_ready) == "function" then
                        opts._on_ready({
                            result_count = #session.results,
                            state = session.state,
                        })
                    end
                end,
            })
            return attached
        end,
    }

    picker = pickers.new(opts, picker_opts)
    vault_state.set_global_key("picker", picker)
    return picker
end
