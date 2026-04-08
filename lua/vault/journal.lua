local config = require("vault.config")
local obsidian = require("vault.obsidian")

local M = {}

---@class vault.JournalDailySettings
---@field dir string
---@field format string
---@field template string|nil
---@field templates vault.ObsidianTemplatesSettings|nil
---@field source "obsidian"|"legacy"

---@return vault.JournalDailySettings|nil
function M.settings()
    local settings = config.options.obsidian or obsidian.read(config.options.root)
    if settings.daily then
        return {
            dir = settings.daily.folder,
            format = settings.daily.format,
            template = settings.daily.template,
            templates = settings.templates,
            source = "obsidian",
        }
    end

    local daily_dir = config.dir("journal.daily")
    if not daily_dir then
        return nil
    end

    return {
        dir = daily_dir,
        format = "YYYY-MM-DD dddd",
        template = nil,
        templates = nil,
        source = "legacy",
    }
end

---@param iso_or_name? string
---@param settings? vault.JournalDailySettings
---@return string|nil
function M.basename(iso_or_name, settings)
    settings = settings or M.settings()
    if not settings then
        return nil
    end

    if type(iso_or_name) == "string" then
        local ts = obsidian.parse_iso_date(iso_or_name)
        if not ts then
            return iso_or_name
        end
        if settings.source == "obsidian" then
            return obsidian.format_date(settings.format, ts)
        end
        return os.date("%Y-%m-%d %A", ts)
    end

    local now = os.time()
    if settings.source == "obsidian" then
        return obsidian.format_date(settings.format, now)
    end
    return os.date("%Y-%m-%d %A", now)
end

---@param iso_or_name? string
---@param settings? vault.JournalDailySettings
---@return string|nil
function M.path(iso_or_name, settings)
    settings = settings or M.settings()
    if not settings then
        return nil
    end
    local basename = M.basename(iso_or_name, settings)
    if not basename then
        return nil
    end
    return string.format("%s/%s%s", settings.dir, basename, config.options.ext)
end

---@param iso_or_name string
---@param settings vault.JournalDailySettings|nil
---@return string
function M.initial_content(iso_or_name, settings)
    settings = settings or M.settings()
    local basename = M.basename(iso_or_name, settings)
    if type(basename) ~= "string" then
        return ""
    end

    local ts = obsidian.parse_iso_date(iso_or_name) or os.time()
    if settings and settings.source == "obsidian" and settings.template then
        local template_path = obsidian.resolve_template_path(
            config.options.root,
            settings.template,
            settings.templates,
            config.options.ext
        )
        if template_path and vim.fn.filereadable(template_path) == 1 then
            local raw = table.concat(vim.fn.readfile(template_path), "\n")
            if raw ~= "" then
                return obsidian.render_template(raw, {
                    ts = ts,
                    title = basename,
                    templates = settings.templates,
                })
            end
        end
    end

    return "# " .. basename .. "\n"
end

---@param iso_or_name string
---@param settings vault.JournalDailySettings|nil
---@return string|nil, boolean
function M.ensure(iso_or_name, settings)
    settings = settings or M.settings()
    local path = M.path(iso_or_name, settings)
    if not path then
        return nil, false
    end
    if vim.fn.filereadable(path) == 1 then
        return path, false
    end

    local parent = vim.fn.fnamemodify(path, ":h")
    if vim.fn.isdirectory(parent) == 0 then
        vim.fn.mkdir(parent, "p")
    end

    vim.fn.writefile(vim.split(M.initial_content(iso_or_name, settings), "\n"), path)
    return path, true
end

return M
