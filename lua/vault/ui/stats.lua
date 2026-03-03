--- vault.ui.stats — Progress dashboard showing vault health metrics.
---
--- Opens a centered floating window with key statistics:
--- total notes, tagged %, with-status %, orphans %, leaves %, etc.
---
--- Usage:
---   require("vault.ui.stats").open()
---
--- @module vault.ui.stats

local log = require("vault.log").scope("ui.stats")

local M = {}

--- Compute vault statistics.
---@return table stats
local function compute_stats()
  local Notes = require("vault.notes")
  local Tags = require("vault.tags")

  local all = Notes()
  local total = all:count()

  -- Tagged: notes that appear as tag sources
  local tag_sources = Tags():sources()
  local tagged = 0
  for slug, _ in pairs(all.map) do
    if tag_sources[slug] then tagged = tagged + 1 end
  end

  -- With status: notes that have a "status" frontmatter field
  local with_status = 0
  local shared = require("vault.bases.views.shared")
  for _, note in pairs(all.map) do
    local fm = shared.read_frontmatter_fields(note.data.path, { "status" })
    if fm.status and fm.status ~= "" then
      with_status = with_status + 1
    end
  end

  -- Orphans
  local orphan_set = Notes():orphans()
  local orphan_count = orphan_set:count()

  -- Leaves
  local leaf_set = Notes():leaves()
  local leaf_count = leaf_set:count()

  -- Content stats (from existing Stats class)
  local Stats = require("vault.notes.stats")
  local stats_obj = Stats(all)
  local avg_content = stats_obj:average_content_length()
  local word_count = stats_obj:word_count()
  local created_week = stats_obj:created_this_week()

  return {
    total = total,
    tagged = tagged,
    with_status = with_status,
    orphans = orphan_count,
    leaves = leaf_count,
    avg_content = avg_content,
    word_count = word_count,
    created_week = created_week,
  }
end

---@param n integer
---@param total integer
---@return string
local function pct(n, total)
  if total == 0 then return "0.0%" end
  return string.format("%.1f%%", (n / total) * 100)
end

---@param n integer
---@return string
local function fmt_num(n)
  local s = tostring(n)
  local result = ""
  local len = #s
  for i = 1, len do
    if i > 1 and (len - i + 1) % 3 == 0 then result = result .. "," end
    result = result .. s:sub(i, i)
  end
  return result
end

--- Open the stats dashboard in a floating window.
function M.open()
  -- Compute in a schedule to avoid blocking UI
  vim.schedule(function()
    local ok, stats = pcall(compute_stats)
    if not ok then
      log.error("Failed to compute stats: %s", tostring(stats))
      return
    end

    local lines = {
      " Vault Stats",
      string.rep("\u{2500}", 36),
      string.format(" Total notes:       %8s", fmt_num(stats.total)),
      string.format(" Tagged:            %8s  (%s)", fmt_num(stats.tagged), pct(stats.tagged, stats.total)),
      string.format(" With status:       %8s  (%s)", fmt_num(stats.with_status), pct(stats.with_status, stats.total)),
      string.format(" Orphans:           %8s  (%s)", fmt_num(stats.orphans), pct(stats.orphans, stats.total)),
      string.format(" Leaves:            %8s  (%s)", fmt_num(stats.leaves), pct(stats.leaves, stats.total)),
      string.rep("\u{2500}", 36),
      string.format(" Words:             %8s", fmt_num(stats.word_count)),
      string.format(" Avg content:       %8s chars", fmt_num(math.floor(stats.avg_content))),
      string.format(" Created this week: %8s", fmt_num(stats.created_week)),
      string.rep("\u{2500}", 36),
      " Press q to close",
    }

    local width = 0
    for _, l in ipairs(lines) do
      if #l > width then width = #l end
    end
    width = width + 2  -- padding
    local height = #lines

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype = "vault-stats"

    local ui = vim.api.nvim_list_uis()[1] or { width = 120, height = 40 }
    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = width,
      height = height,
      col = math.floor((ui.width - width) / 2),
      row = math.floor((ui.height - height) / 2),
      style = "minimal",
      border = "rounded",
      title = " Vault ",
      title_pos = "center",
    })

    -- Highlights
    local ns = vim.api.nvim_create_namespace("vault_stats")
    vim.api.nvim_buf_add_highlight(buf, ns, "Title", 0, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, ns, "Comment", 1, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, ns, "Comment", 7, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, ns, "Comment", 11, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, ns, "NonText", #lines - 1, 0, -1)

    -- Close keymaps
    local close = function()
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    end
    vim.keymap.set("n", "q", close, { buffer = buf, silent = true })
    vim.keymap.set("n", "<Esc>", close, { buffer = buf, silent = true })

    -- Auto-close on leave
    vim.api.nvim_create_autocmd("BufLeave", {
      buffer = buf,
      once = true,
      callback = close,
    })
  end)
end

return M
