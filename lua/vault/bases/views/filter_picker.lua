--- vault.bases.views.filter_picker — Interactive multi-step filter builder for vault grids/kanbans.
---
--- Presents a structured picker flow:
---   1. Select field (from grid/kanban columns)
---   2. Select operator (eq, neq, contains, gt, etc.)
---   3. Enter value
---   4. Apply filter to pipeline; optionally add another filter
---
--- Uses vim.ui.select / vim.ui.input (enhanced by dressing.nvim if installed).
---
--- @module vault.bases.views.filter_picker

local log = require("vault.log").scope("bases.views.filter_picker")

local M = {}

--- Operator display names and their pipeline MatchOp values.
---@type { label: string, op: string }[]
local OPERATORS = {
  { label = "= (equals)",            op = "eq" },
  { label = "!= (not equals)",       op = "neq" },
  { label = "contains",              op = "contains" },
  { label = "starts with",           op = "startswith" },
  { label = "ends with",             op = "endswith" },
  { label = "> (greater than)",      op = "gt" },
  { label = ">= (greater or equal)", op = "gte" },
  { label = "< (less than)",         op = "lt" },
  { label = "<= (less or equal)",    op = "lte" },
  { label = "regex (Lua pattern)",   op = "regex" },
}

--- Open the interactive filter picker.
---
--- @param view table  Grid or Board instance (must have :pipeline(), :set_pipeline(), :clear_pipeline())
--- @param fields string[]  Field names available for filtering
function M.open(view, fields)
  if not fields or #fields == 0 then
    log.warn("No fields available for filtering")
    return
  end

  local Pipeline = require("vimtable.pipeline")

  -- Step 1: Pick field
  vim.ui.select(fields, {
    prompt = "Filter field:",
  }, function(field)
    if not field then return end

    -- Step 2: Pick operator
    local op_labels = {}
    for _, o in ipairs(OPERATORS) do
      op_labels[#op_labels + 1] = o.label
    end

    vim.ui.select(op_labels, {
      prompt = field .. " — operator:",
    }, function(op_choice, op_idx)
      if not op_choice or not op_idx then return end
      local op = OPERATORS[op_idx].op

      -- Step 3: Enter value
      vim.ui.input({
        prompt = string.format("%s %s: ", field, op),
      }, function(value)
        if not value then return end

        -- Coerce numeric values
        local num = tonumber(value)
        if num then value = num end

        -- Build or extend pipeline
        local current = view:pipeline()
        local p = current and current:filter(field, value, op)
          or Pipeline.new():filter(field, value, op)

        view:set_pipeline(p)
        log.info("Filter applied: %s", p:describe())

        -- Step 4: Done or add another?
        vim.ui.select({ "Done", "Add another filter" }, {
          prompt = "Pipeline: " .. p:describe(),
        }, function(action)
          if action == "Add another filter" then
            M.open(view, fields)
          end
        end)
      end)
    end)
  end)
end

return M
