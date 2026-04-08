local Layouts = {}

--- Get UI dimensions with fallback for headless/startup race
--- @return integer height
--- @return integer width
function Layouts.ui_size()
    local uis = vim.api.nvim_list_uis()
    if uis[1] then
        return uis[1].height, uis[1].width
    end
    return vim.o.lines or 24, vim.o.columns or 80
end

function Layouts.mini()
    return {
        layout_strategy = "vertical",
        layout_config = {
            height = 0.3,
            width = 0.3,
            prompt_position = "top",
        },
        sorting_strategy = "ascending",
        scroll_strategy = "cycle",
    }
end

function Layouts.notes()
    local h, w = Layouts.ui_size()
    return {
        sorting_strategy = "ascending",
        layout_config = {
            height = h - 4,
            width = w - 4,
            preview_width = 0.4,
        },
    }
end

function Layouts.tags()
    local h, w = Layouts.ui_size()
    return {
        sorting_strategy = "ascending",
        layout_config = {
            height = h - 4,
            width = w - 4,
            preview_width = 0.7,
        },
    }
end

function Layouts.bases()
    local h, w = Layouts.ui_size()
    return {
        sorting_strategy = "ascending",
        layout_config = {
            height = h - 4,
            width = w - 4,
            preview_width = 0.4,
        },
    }
end

return Layouts
