local config = require("vault.config")
local log = require("vault.log").scope("local_graph")

local M = {}

local function graph_config()
    local views = config.options.views or {}
    return views.local_graph or {}
end

local function sort_keys(t)
    local keys = {}
    for key, _ in pairs(t or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

local function path_for_slug(index, slug)
    local entry = index.paths and index.paths[slug]
    return entry and entry.path or nil
end

local function title_for_slug(index, slug)
    local entry = index.paths and index.paths[slug]
    if entry then
        return entry.title or entry.stem or entry.basename or slug
    end
    return slug
end

local function shorten(text, max_len)
    text = tostring(text or "")
    if #text <= max_len then
        return text
    end
    if max_len <= 1 then
        return text:sub(1, max_len)
    end
    return text:sub(1, max_len - 1) .. "…"
end

local function node_label(index, slug, max_len, glyph)
    local title = title_for_slug(index, slug)
    return glyph .. " " .. shorten(title, max_len - 2)
end

local function add_line(lines, line_slugs, text, slug)
    lines[#lines + 1] = text
    if slug then
        line_slugs[tostring(#lines)] = { any = slug }
    end
end

local function collect_graph(note)
    local index = require("vault.notes.link_index").get()
    local slug = note.data.slug
    local outlinks = index.outlinks_by_source[slug] or {}
    local inlinks = index.inlinks_by_target[slug] or {}
    local outgoing = {}
    local unresolved = {}
    local backlinks = {}

    for _, link_slug in ipairs(sort_keys(outlinks)) do
        local link = outlinks[link_slug]
        local data = link.data or {}
        local target = data.target
        if type(target) == "string" and target ~= "" then
            outgoing[#outgoing + 1] = target
        else
            unresolved[#unresolved + 1] = data.slug or link_slug
        end
    end

    for _, source in ipairs(sort_keys(inlinks)) do
        backlinks[#backlinks + 1] = source
    end

    return index, slug, outgoing, backlinks, unresolved
end

local function build_canvas(note, width)
    local index, slug, outgoing, backlinks, unresolved = collect_graph(note)
    local lines = {}
    local line_slugs = {}

    add_line(lines, line_slugs, "Local Graph")
    add_line(lines, line_slugs, string.rep("=", 11))
    add_line(
        lines,
        line_slugs,
        string.format("out %d  in %d  unresolved %d", #outgoing, #backlinks, #unresolved)
    )
    add_line(lines, line_slugs, "")

    local left_w = math.max(12, math.floor(width * 0.28))
    local mid_w = math.max(14, math.floor(width * 0.34))
    local right_w = math.max(12, width - left_w - mid_w - 8)
    local center = node_label(index, slug, mid_w, "◉")
    local rows = math.max(#backlinks, #outgoing + #unresolved, 1)
    local center_row = math.ceil(rows / 2)
    local right_nodes = {}

    for _, target in ipairs(outgoing) do
        right_nodes[#right_nodes + 1] =
            { slug = target, label = node_label(index, target, right_w, "◯") }
    end
    for _, target in ipairs(unresolved) do
        right_nodes[#right_nodes + 1] =
            { slug = target, label = "◌ " .. shorten(target .. " ?", right_w - 2) }
    end

    for row = 1, rows do
        local left_slug = backlinks[row]
        local right = right_nodes[row]
        local left = left_slug and node_label(index, left_slug, left_w, "◯") or ""
        local left_cell = string.format("%-" .. left_w .. "s", left)
        local right_label = right and right.label or ""
        local right_slug = right and right.slug or nil

        if row == center_row then
            local text = left_cell .. " ── " .. center .. " ── " .. right_label
            add_line(lines, line_slugs, text)
            line_slugs[tostring(#lines)] = {
                left = left_slug,
                center = slug,
                right = right_slug,
                left_end = left_w,
                center_start = left_w + 4,
                center_end = left_w + 4 + #center,
            }
        elseif row < center_row then
            local text = left_cell
                .. " ╲  "
                .. string.rep(" ", #center)
                .. " ╱  "
                .. right_label
            add_line(lines, line_slugs, text)
            line_slugs[tostring(#lines)] = {
                left = left_slug,
                right = right_slug,
                left_end = left_w,
                center_start = left_w + 4,
            }
        else
            local text = left_cell
                .. " ╱  "
                .. string.rep(" ", #center)
                .. " ╲  "
                .. right_label
            add_line(lines, line_slugs, text)
            line_slugs[tostring(#lines)] = {
                left = left_slug,
                right = right_slug,
                left_end = left_w,
                center_start = left_w + 4,
            }
        end
    end

    if rows == 1 and #backlinks == 0 and #right_nodes == 0 then
        lines[#lines] = string.rep(" ", left_w + 4) .. center
        line_slugs[tostring(#lines)] = { any = slug }
    end

    add_line(lines, line_slugs, "")
    if #backlinks == 0 then
        add_line(lines, line_slugs, "◯ no backlinks")
    end
    if #outgoing == 0 then
        add_line(lines, line_slugs, "◯ no outgoing links")
    end
    if #unresolved > 0 then
        add_line(lines, line_slugs, "◌ unresolved links shown with ?")
    end
    add_line(lines, line_slugs, "")
    add_line(lines, line_slugs, "<CR>/o open   r refresh   q close")

    return lines, line_slugs
end

local function find_graph_win(name)
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == name then
            return win, buf
        end
    end
    return nil, nil
end

local function open_slug(buf)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1]
    local col = cursor[2]
    local slugs = vim.b[buf].vault_local_graph_slugs or {}
    local data = slugs[tostring(line)] or slugs[line]
    local slug = nil
    if type(data) == "table" then
        if data.any then
            slug = data.any
        elseif data.left and col <= (data.left_end or 0) then
            slug = data.left
        elseif
            data.center
            and col >= (data.center_start or 0)
            and col <= (data.center_end or 0)
        then
            slug = data.center
        elseif data.right and col >= (data.center_start or 0) then
            slug = data.right
        else
            slug = data.left or data.center or data.right
        end
    elseif type(data) == "string" then
        slug = data
    end
    if not slug then
        return
    end

    local index = require("vault.notes.link_index").get()
    local path = path_for_slug(index, slug)
    if not path then
        path = require("vault.notes.create").create(slug, { open = false })
        require("vault.scanner").invalidate_notes_cache()
        log.info("Created unresolved link note: %s", slug)
    end

    local source_win = vim.b[buf].vault_local_graph_source_win
    if type(source_win) == "number" and vim.api.nvim_win_is_valid(source_win) then
        vim.api.nvim_set_current_win(source_win)
    end
    vim.cmd("edit " .. vim.fn.fnameescape(path))

    local ok, Note = pcall(require, "vault.notes.note")
    if ok then
        M.open(Note(path), { enter = false, buf = buf })
    end
end

local function set_keymaps(buf, note)
    local opts = { buffer = buf, silent = true }
    vim.keymap.set("n", "q", function()
        local win = vim.fn.bufwinid(buf)
        if win ~= -1 then
            vim.api.nvim_win_close(win, true)
        end
    end, opts)
    vim.keymap.set("n", "r", function()
        M.open(note, { enter = true })
    end, opts)
    vim.keymap.set("n", "<CR>", function()
        open_slug(buf)
    end, opts)
    vim.keymap.set("n", "o", function()
        open_slug(buf)
    end, opts)
end

--- Open an Obsidian-like local graph sidebar for a note.
--- @param note vault.Note
--- @param opts? { enter?: boolean, buf?: integer }
function M.open(note, opts)
    opts = opts or {}
    local cfg = graph_config()
    local width = tonumber(cfg.width) or 54
    local previous_win = vim.api.nvim_get_current_win()
    local name = "vault://local-graph/" .. note.data.slug
    local win, buf

    if type(opts.buf) == "number" and vim.api.nvim_buf_is_valid(opts.buf) then
        buf = opts.buf
        local buf_win = vim.fn.bufwinid(buf)
        if buf_win ~= -1 and vim.api.nvim_win_is_valid(buf_win) then
            win = buf_win
        end
    end

    if not win then
        win, buf = find_graph_win(name)
    end

    if not win then
        vim.cmd("botright vertical " .. width .. "new")
        win = vim.api.nvim_get_current_win()
        buf = vim.api.nvim_get_current_buf()
    else
        vim.api.nvim_set_current_win(win)
    end

    if vim.api.nvim_buf_get_name(buf) ~= name then
        vim.api.nvim_buf_set_name(buf, "")
        vim.api.nvim_buf_set_name(buf, name)
    end

    vim.api.nvim_win_set_width(win, width)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = "vault-local-graph"
    vim.bo[buf].modifiable = true

    local lines, line_slugs = build_canvas(note, width)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    if previous_win ~= win and vim.api.nvim_win_is_valid(previous_win) then
        vim.b[buf].vault_local_graph_source_win = previous_win
    end
    vim.b[buf].vault_local_graph_slugs = line_slugs
    vim.bo[buf].modifiable = false
    vim.bo[buf].readonly = true
    vim.wo[win].wrap = false
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].foldcolumn = "0"

    set_keymaps(buf, note)

    if not opts.enter and vim.api.nvim_win_is_valid(previous_win) then
        vim.api.nvim_set_current_win(previous_win)
    end
end

return M
