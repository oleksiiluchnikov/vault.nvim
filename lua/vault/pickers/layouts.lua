local Layouts = {}

function Layouts.mini()
	return {
		layout_strategy = "vertical",
		layout_config = {
			height = 0.9,
			width = 0.3,
			prompt_position = "top",
		},
		sorting_strategy = "ascending",
		scroll_strategy = "cycle",
	}
end

function Layouts.notes()
	local bufheight = vim.o.lines - 4
	local bufwidth = vim.o.columns - 4

	return {
		sorting_strategy = "ascending",
		layout_config = {
			height = bufheight,
			width = bufwidth,
			preview_width = 0.4,
		},
	}
end

function Layouts.tags()
	local bufheight = vim.o.lines - 4
	local bufwidth = vim.o.columns - 4
	local preview_width = 0.7

	return {
		sorting_strategy = "ascending",
		layout_config = {
			height = bufheight,
			width = bufwidth,
			preview_width = preview_width,
		},
	}
end

return Layouts
