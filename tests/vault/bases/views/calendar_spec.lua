describe("calendar view adapter (unit)", function()
  local Config
  local cal
  local tmp_root

  local function clear_modules()
    package.loaded["vault.views.calendar"] = nil
    package.loaded["vault.views.shared"] = nil
    package.loaded["vault.config"] = nil
  end

  local function write_file(path, lines)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    vim.fn.writefile(lines, path)
  end

  before_each(function()
    clear_modules()
    Config = require("vault.config")
    Config.reset()
    tmp_root = vim.fn.tempname() .. "_vault_calendar"
    vim.fn.mkdir(tmp_root, "p")
    Config.setup({
      root = tmp_root,
      ext = ".md",
      features = {
        cmp = false,
        commands = false,
        watcher = false,
      },
    })
    cal = require("vault.views.calendar")
  end)

  after_each(function()
    if tmp_root and tmp_root ~= "" then
      vim.fn.delete(tmp_root, "rf")
    end
    clear_modules()
  end)

  it("extracts ISO date from daily-note wikilink", function()
    assert.are.equal("2026-03-10", cal._extract_iso_date("[[2026-03-10 Tuesday]]"))
  end)

  it("formats due dates as daily-note wikilinks", function()
    local out = cal._format_calendar_date_for_field("due", "2026-03-10")
    assert.are.equal("[[2026-03-10 Tuesday]]", out)
  end)

  it("keeps non-linked date fields plain by default", function()
    local out = cal._format_calendar_date_for_field("start", "2026-03-10")
    assert.are.equal("2026-03-10", out)
  end)

  it("respects configured link_date_fields", function()
    Config.setup({
      calendar = {
        link_date_fields = { "due", "start" },
      },
    })
    local out = cal._format_calendar_date_for_field("start", "2026-03-10")
    assert.are.equal("[[2026-03-10 Tuesday]]", out)
  end)

  it("flatten_notes parses due wikilink into calendar ISO date", function()
    local task_path = tmp_root .. "/Tasks/T-20260306120000 Task.md"
    write_file(task_path, {
      "---",
      'title: "Task"',
      'due: "[[2026-03-06 Friday]]"',
      "---",
      "",
      "# Task",
    })

    local notes_map = {
      ["Tasks/T-20260306120000 Task"] = {
        data = {
          path = task_path,
          title = "Task",
        },
      },
    }

    local records = cal._flatten_notes(notes_map, "due", "title", nil, nil)
    assert.are.equal(1, #records)
    assert.are.equal("2026-03-06", records[1].due)
  end)

  it("flatten_notes supports file.name date extraction for daily notes", function()
    local daily_path = tmp_root .. "/Daily/2026-03-06 Friday.md"
    write_file(daily_path, {
      "# 2026-03-06 Friday",
    })

    local notes_map = {
      ["Daily/2026-03-06 Friday"] = {
        data = {
          path = daily_path,
          basename = "2026-03-06 Friday",
          title = "2026-03-06 Friday",
        },
      },
    }

    local records = cal._flatten_notes(notes_map, "file.name", "title", nil, nil)
    assert.are.equal(1, #records)
    assert.are.equal("2026-03-06", records[1]["file.name"])
  end)
end)
