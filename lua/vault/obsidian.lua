local M = {}

---@class vault.ObsidianAppSettings
---@field new_file_location string|nil
---@field new_file_folder string|nil
---@field attachment_folder string|nil
---@field always_update_links boolean|nil
---@field use_markdown_links boolean|nil

---@class vault.ObsidianTemplatesSettings
---@field folder string
---@field folder_raw string|nil
---@field date_format string|nil
---@field time_format string|nil

---@class vault.ObsidianDailySettings
---@field source "daily-notes"|"app"
---@field format string
---@field folder string
---@field folder_raw string|nil
---@field template string|nil

---@class vault.ObsidianPeriodicEntry
---@field enabled boolean|nil
---@field format string|nil
---@field folder string|nil
---@field folder_raw string|nil
---@field template string|nil

---@class vault.ObsidianSettings
---@field app vault.ObsidianAppSettings
---@field templates vault.ObsidianTemplatesSettings|nil
---@field daily vault.ObsidianDailySettings|nil
---@field periodic table<string, vault.ObsidianPeriodicEntry>|nil

---@type string[]
local TOKEN_ORDER = {
    "YYYY",
    "dddd",
    "MMMM",
    "MMM",
    "MM",
    "DD",
    "ddd",
    "YY",
    "M",
    "D",
    "HH",
    "H",
    "mm",
    "m",
    "ss",
    "s",
}

---@type table<string, fun(ts: integer): string>
local TOKEN_FORMATTERS = {
    YYYY = function(ts)
        return os.date("%Y", ts)
    end,
    YY = function(ts)
        return os.date("%y", ts)
    end,
    MMMM = function(ts)
        return os.date("%B", ts)
    end,
    MMM = function(ts)
        return os.date("%b", ts)
    end,
    MM = function(ts)
        return os.date("%m", ts)
    end,
    M = function(ts)
        return tostring(tonumber(os.date("%m", ts)))
    end,
    DD = function(ts)
        return os.date("%d", ts)
    end,
    D = function(ts)
        return tostring(tonumber(os.date("%d", ts)))
    end,
    dddd = function(ts)
        return os.date("%A", ts)
    end,
    ddd = function(ts)
        return os.date("%a", ts)
    end,
    HH = function(ts)
        return os.date("%H", ts)
    end,
    H = function(ts)
        return tostring(tonumber(os.date("%H", ts)))
    end,
    mm = function(ts)
        return os.date("%M", ts)
    end,
    m = function(ts)
        return tostring(tonumber(os.date("%M", ts)))
    end,
    ss = function(ts)
        return os.date("%S", ts)
    end,
    s = function(ts)
        return tostring(tonumber(os.date("%S", ts)))
    end,
}

---@param path string
---@return table|nil
local function read_json_file(path)
    if vim.fn.filereadable(path) == 0 then
        return nil
    end
    local raw = table.concat(vim.fn.readfile(path), "\n")
    if raw == "" then
        return nil
    end
    local ok, decoded = pcall(vim.json.decode, raw)
    if not ok then
        ok, decoded = pcall(vim.fn.json_decode, raw)
    end
    if not ok or type(decoded) ~= "table" then
        return nil
    end
    return decoded
end

---@param value unknown
---@return string|nil
local function as_string(value)
    if type(value) == "string" then
        return value
    end
    return nil
end

---@param value unknown
---@return boolean|nil
local function as_boolean(value)
    if type(value) == "boolean" then
        return value
    end
    return nil
end

---@param root string
---@param folder unknown
---@return string
function M.normalize_folder(root, folder)
    if type(folder) ~= "string" then
        return vim.fs.normalize(root)
    end
    local trimmed = folder:gsub("^/+", ""):gsub("/+$", "")
    if trimmed == "" then
        return vim.fs.normalize(root)
    end
    return vim.fs.normalize(root .. "/" .. trimmed)
end

---@param iso_date string
---@return integer|nil
function M.parse_iso_date(iso_date)
    local year, month, day = iso_date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not year then
        return nil
    end
    return os.time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = 12,
    })
end

---@param format string
---@param ts integer
---@return string
function M.format_date(format, ts)
    local parts = {} ---@type string[]
    local i = 1
    while i <= #format do
        local ch = format:sub(i, i)
        if ch == "[" then
            local close = format:find("]", i + 1, true)
            if close then
                parts[#parts + 1] = format:sub(i + 1, close - 1)
                i = close + 1
            else
                parts[#parts + 1] = ch
                i = i + 1
            end
        else
            local matched = false
            for _, token in ipairs(TOKEN_ORDER) do
                if format:sub(i, i + #token - 1) == token then
                    parts[#parts + 1] = TOKEN_FORMATTERS[token](ts)
                    i = i + #token
                    matched = true
                    break
                end
            end
            if not matched then
                parts[#parts + 1] = ch
                i = i + 1
            end
        end
    end
    return table.concat(parts)
end

---@param root string
---@param template_name unknown
---@param templates vault.ObsidianTemplatesSettings|nil
---@param ext string
---@return string|nil
function M.resolve_template_path(root, template_name, templates, ext)
    if type(template_name) ~= "string" or template_name == "" then
        return nil
    end
    ext = ext or ".md"
    local rel = template_name:gsub("^/+", "")
    if not rel:match(vim.pesc(ext) .. "$") then
        rel = rel .. ext
    end
    if rel:find("/", 1, true) then
        return vim.fs.normalize(root .. "/" .. rel)
    end
    if templates and type(templates.folder_raw) == "string" and templates.folder_raw ~= "" then
        return vim.fs.normalize(templates.folder .. "/" .. rel)
    end
    return vim.fs.normalize(root .. "/" .. rel)
end

---@param root string
---@return vault.ObsidianSettings
function M.read(root)
    local app_raw = read_json_file(root .. "/.obsidian/app.json") or {}
    local templates_raw = read_json_file(root .. "/.obsidian/templates.json")
    local daily_raw = read_json_file(root .. "/.obsidian/daily-notes.json")
    local periodic_raw = read_json_file(root .. "/.obsidian/plugins/periodic-notes/data.json")

    ---@type vault.ObsidianTemplatesSettings|nil
    local templates = nil
    if type(templates_raw) == "table" then
        templates = {
            folder = M.normalize_folder(root, templates_raw.folder),
            folder_raw = templates_raw.folder,
            date_format = type(templates_raw.dateFormat) == "string" and templates_raw.dateFormat
                or nil,
            time_format = type(templates_raw.timeFormat) == "string" and templates_raw.timeFormat
                or nil,
        }
    end

    ---@type vault.ObsidianDailySettings|nil
    local daily = nil
    if
        type(daily_raw) == "table"
        and type(daily_raw.format) == "string"
        and daily_raw.format ~= ""
    then
        daily = {
            source = "daily-notes",
            format = daily_raw.format,
            folder = M.normalize_folder(root, daily_raw.folder),
            folder_raw = daily_raw.folder,
            template = type(daily_raw.template) == "string" and daily_raw.template or nil,
        }
    elseif type(app_raw.dailyNotesFormat) == "string" and app_raw.dailyNotesFormat ~= "" then
        daily = {
            source = "app",
            format = app_raw.dailyNotesFormat,
            folder = M.normalize_folder(root, app_raw.dailyNotesFolder),
            folder_raw = app_raw.dailyNotesFolder,
            template = type(app_raw.dailyNotesTemplate) == "string" and app_raw.dailyNotesTemplate
                or nil,
        }
    end

    ---@type table<string, vault.ObsidianPeriodicEntry>|nil
    local periodic = nil
    if type(periodic_raw) == "table" then
        periodic = {}
        for _, key in ipairs({ "daily", "weekly", "monthly", "quarterly", "yearly" }) do
            local value = periodic_raw[key]
            if type(value) == "table" then
                periodic[key] = {
                    enabled = as_boolean(value.enabled),
                    format = as_string(value.format),
                    folder = as_string(value.folder) and M.normalize_folder(root, value.folder)
                        or nil,
                    folder_raw = as_string(value.folder),
                    template = as_string(value.template),
                }
            end
        end
        if next(periodic) == nil then
            periodic = nil
        end
    end

    return {
        app = {
            new_file_location = as_string(app_raw.newFileLocation),
            new_file_folder = as_string(app_raw.newFileFolderPath),
            attachment_folder = as_string(app_raw.attachmentFolderPath),
            always_update_links = as_boolean(app_raw.alwaysUpdateLinks),
            use_markdown_links = as_boolean(app_raw.useMarkdownLinks),
        },
        templates = templates,
        daily = daily,
        periodic = periodic,
    }
end

---@param root string
---@param settings vault.ObsidianSettings|nil
---@param current_path string|nil
---@return string
function M.new_note_dir(root, settings, current_path)
    local app = settings and settings.app or nil
    local location = app and app.new_file_location or nil
    if location == "folder" then
        return M.normalize_folder(root, app.new_file_folder)
    end
    if location == "current" and type(current_path) == "string" and current_path ~= "" then
        local normalized_current = vim.fs.normalize(current_path)
        local normalized_root = vim.fs.normalize(root)
        if normalized_current:find(normalized_root, 1, true) == 1 then
            return vim.fn.fnamemodify(normalized_current, ":h")
        end
    end
    return vim.fs.normalize(root)
end

---@param root string
---@param ext string
---@param slug string
---@param settings vault.ObsidianSettings|nil
---@param current_path string|nil
---@return string
function M.new_note_path(root, ext, slug, settings, current_path)
    local normalized_slug = slug:gsub("^/+", "")
    if normalized_slug:find("/", 1, true) then
        return vim.fs.normalize(root .. "/" .. normalized_slug .. ext)
    end
    local dir = M.new_note_dir(root, settings, current_path)
    return vim.fs.normalize(dir .. "/" .. normalized_slug .. ext)
end

---@class vault.ObsidianTemplateRenderOpts
---@field ts integer
---@field title string|nil
---@field templates vault.ObsidianTemplatesSettings|nil

---@param content string
---@param opts vault.ObsidianTemplateRenderOpts
---@return string
function M.render_template(content, opts)
    opts = opts or {}
    local ts = opts.ts or os.time()
    local templates = opts.templates
    local date_default = templates and templates.date_format or "YYYY-MM-DD"
    local time_default = templates and templates.time_format or "HH:mm"
    return (
        content:gsub("{{([^}]+)}}", function(inner)
            if inner == "cursor" then
                return ""
            end
            if inner == "title" then
                return opts.title or ""
            end
            local key, fmt = inner:match("^([%a_]+)%:(.+)$")
            key = key or inner
            if key == "date" then
                return M.format_date(fmt or date_default, ts)
            end
            if key == "time" then
                return M.format_date(fmt or time_default, ts)
            end
            return "{{" .. inner .. "}}"
        end)
    )
end

return M
