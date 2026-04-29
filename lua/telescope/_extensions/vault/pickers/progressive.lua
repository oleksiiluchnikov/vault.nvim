local finders = require("telescope.finders")
local vault_match = require("vault.utils").match
local has_fzy, fzy = pcall(require, "telescope.algos.fzy")
local COUNT_DEBOUNCE_MS = 120

---@param prompt string
---@param line string
---@return boolean
local function fuzzy_has_match(prompt, line)
    if has_fzy and type(fzy) == "table" and type(fzy.has_match) == "function" then
        return fzy.has_match(prompt, line)
    end

    return vault_match(line, prompt, "contains", true)
end

---@class vault.TelescopeProgressivePrepared
---@field entry_maker fun(item: any): table
---@field results table[]

---@class vault.TelescopeProgressiveOptions
---@field prepare fun(): vault.TelescopeProgressivePrepared
---@field empty_message? string
---@field empty_prompt_limit? integer
---@field loading_message? string
---@field prompt_result_limit? integer
---@field search_text? fun(item: any): string
---@field matches_prompt? fun(prompt: string, searchable: string, item?: any): boolean

---@class vault.TelescopeProgressiveStatus
---@field kind "status"
---@field message string

---@class vault.TelescopeProgressiveSession
---@field count_pending boolean
---@field count_request_id integer
---@field count_timer uv_timer_t|nil
---@field empty_message string
---@field empty_prompt_limit integer
---@field entry_maker? fun(item: any): table
---@field error_message? string
---@field last_matched_count integer
---@field loading_message string
---@field picker Picker|table|nil
---@field prepare fun(): vault.TelescopeProgressivePrepared
---@field prompt_result_limit integer
---@field results table[]
---@field matches_prompt fun(prompt: string, searchable: string, item?: any): boolean
---@field search_text fun(item: any): string
---@field searchables string[]
---@field seed_results table[]
---@field started boolean
---@field state "loading"|"ready"|"error"
---@field status_updater (fun(opts?: table): nil)|nil
local Session = {}
Session.__index = Session

---@param message string
---@return vault.TelescopeProgressiveStatus[]
local function status_items(message)
    return {
        {
            kind = "status",
            message = message,
        },
    }
end

---@param title unknown
---@return string
local function title_text(title)
    if type(title) == "table" and type(title.text) == "string" then
        return title.text
    end
    if type(title) == "string" then
        return title
    end
    return ""
end

---@param item table
---@return string
local function default_search_text(item)
    local data = item.data or {}
    return table
        .concat({
            tostring(data.slug or data.name or data.relpath or data.content or ""),
            title_text(data.title),
            tostring(data.content or ""),
        }, " ")
        :lower()
end

---@param prompt string
---@param searchable string
---@return boolean
local function default_matches_prompt(prompt, searchable)
    return fuzzy_has_match(prompt:lower(), searchable)
end

---@param prompt string
---@return string|nil, boolean
local function regex_pattern(prompt)
    if prompt == "" or prompt:sub(-1) ~= "/" then
        return nil, false
    end

    local is_negative = prompt:sub(1, 1) == "-"
    local pattern = prompt:sub(1, -2)
    if is_negative then
        pattern = pattern:sub(2)
    end

    if pattern == "" then
        return nil, false
    end

    return pattern, is_negative
end

---@param picker Picker|table|nil
---@return boolean
local function picker_is_active(picker)
    if type(picker) ~= "table" or picker.closed == true then
        return false
    end

    if type(picker.is_done) == "function" then
        local ok, done = pcall(picker.is_done, picker)
        if ok and done then
            return false
        end
    end

    return true
end

---@param self vault.TelescopeProgressiveSession
---@return uv_timer_t|nil
local function ensure_count_timer(self)
    if self.count_timer or not vim.uv or type(vim.uv.new_timer) ~= "function" then
        return self.count_timer
    end

    self.count_timer = vim.uv.new_timer()
    return self.count_timer
end

---@param self vault.TelescopeProgressiveSession
---@return nil
local function close_count_timer(self)
    if not self.count_timer then
        return
    end

    self.count_timer:stop()
    self.count_timer:close()
    self.count_timer = nil
end

---@param self vault.TelescopeProgressiveSession
---@return nil
local function cancel_pending_count(self)
    self.count_request_id = self.count_request_id + 1
    self.count_pending = false
    if self.count_timer then
        self.count_timer:stop()
    end
end

---@param self vault.TelescopeProgressiveSession
---@param matched_count integer
---@param request_id integer
---@return nil
local function apply_exact_match_count(self, matched_count, request_id)
    if request_id ~= self.count_request_id then
        return
    end

    self.last_matched_count = matched_count
    self.count_pending = false

    if self.status_updater and picker_is_active(self.picker) then
        self.status_updater({ completed = true })
    end
end

---@param self vault.TelescopeProgressiveSession
---@param prompt string
---@return table[]
local function prompt_matches(self, prompt)
    local filtered = {}

    for index, item in ipairs(self.results) do
        if self.matches_prompt(prompt, self.searchables[index], item) then
            if #filtered < self.prompt_result_limit then
                filtered[#filtered + 1] = item
            else
                break
            end
        end
    end

    return filtered
end

---@param self vault.TelescopeProgressiveSession
---@param pattern string
---@param is_negative boolean
---@return table[]
local function regex_matches(self, pattern, is_negative)
    local filtered = {}

    for index, item in ipairs(self.results) do
        local ok, matched = pcall(vault_match, self.searchables[index], pattern, "regex", false)
        if ok and matched ~= is_negative then
            if #filtered < self.prompt_result_limit then
                filtered[#filtered + 1] = item
            else
                break
            end
        end
    end

    return filtered
end

---@param self vault.TelescopeProgressiveSession
---@param prompt string
---@return integer
local function count_prompt_matches(self, prompt)
    local matched_count = 0

    for index, item in ipairs(self.results) do
        if self.matches_prompt(prompt, self.searchables[index], item) then
            matched_count = matched_count + 1
        end
    end

    return matched_count
end

---@param self vault.TelescopeProgressiveSession
---@param pattern string
---@param is_negative boolean
---@return integer
local function count_regex_matches(self, pattern, is_negative)
    local matched_count = 0

    for index = 1, #self.results do
        local ok, matched = pcall(vault_match, self.searchables[index], pattern, "regex", false)
        if ok and matched ~= is_negative then
            matched_count = matched_count + 1
        end
    end

    return matched_count
end

---@param self vault.TelescopeProgressiveSession
---@param prompt string
---@param counter fun(): integer
---@return nil
local function schedule_exact_match_count(self, prompt, counter)
    local timer = ensure_count_timer(self)
    local request_id = self.count_request_id + 1
    self.count_request_id = request_id
    self.count_pending = true

    if not timer then
        vim.schedule(function()
            apply_exact_match_count(self, counter(), request_id)
        end)
        return
    end

    timer:stop()
    timer:start(
        COUNT_DEBOUNCE_MS,
        0,
        vim.schedule_wrap(function()
            if
                request_id ~= self.count_request_id
                or prompt == ""
                or not picker_is_active(self.picker)
            then
                return
            end

            apply_exact_match_count(self, counter(), request_id)
        end)
    )
end

---@param self vault.TelescopeProgressiveSession
---@param prepared vault.TelescopeProgressivePrepared
---@return nil
local function set_ready(self, prepared)
    self.entry_maker = prepared.entry_maker
    self.results = prepared.results or {}
    self.searchables = {}
    self.seed_results = {}
    self.state = "ready"
    self.last_matched_count = #self.results
    self.count_pending = false

    for index, item in ipairs(self.results) do
        self.searchables[index] = self.search_text(item)
        if index <= self.empty_prompt_limit then
            self.seed_results[index] = item
        end
    end
end

---@param opts vault.TelescopeProgressiveOptions
---@return vault.TelescopeProgressiveSession
function Session:new(opts)
    return setmetatable({
        count_pending = false,
        count_request_id = 0,
        count_timer = nil,
        empty_message = opts.empty_message or "No results found",
        empty_prompt_limit = math.max(1, tonumber(opts.empty_prompt_limit) or 200),
        loading_message = opts.loading_message or "Collecting results...",
        prepare = opts.prepare,
        prompt_result_limit = math.max(1, tonumber(opts.prompt_result_limit) or 400),
        results = {},
        matches_prompt = opts.matches_prompt or default_matches_prompt,
        search_text = opts.search_text or default_search_text,
        searchables = {},
        seed_results = {},
        last_matched_count = 0,
        picker = nil,
        started = false,
        state = "loading",
        status_updater = nil,
    }, self)
end

---@param prompt string|nil
---@return (table|vault.TelescopeProgressiveStatus)[]
function Session:items_for_prompt(prompt)
    prompt = prompt or ""

    if self.state == "error" then
        cancel_pending_count(self)
        self.last_matched_count = 0
        return status_items(self.error_message or "Failed to load results")
    end

    if self.state ~= "ready" then
        cancel_pending_count(self)
        self.last_matched_count = 0
        return status_items(self.loading_message)
    end

    if #self.results == 0 then
        cancel_pending_count(self)
        self.last_matched_count = 0
        return status_items(self.empty_message)
    end

    local pattern, is_negative = regex_pattern(prompt)
    if pattern then
        schedule_exact_match_count(self, prompt, function()
            return count_regex_matches(self, pattern, is_negative)
        end)
        return regex_matches(self, pattern, is_negative)
    end

    if prompt == "" then
        cancel_pending_count(self)
        self.last_matched_count = #self.results
        return self.seed_results
    end

    schedule_exact_match_count(self, prompt, function()
        return count_prompt_matches(self, prompt)
    end)
    return prompt_matches(self, prompt)
end

---@param item table|vault.TelescopeProgressiveStatus
---@return table
function Session:make_entry(item)
    if type(item) == "table" and item.kind == "status" then
        return {
            value = item,
            ordinal = item.message,
            display = item.message,
        }
    end

    return self.entry_maker(item)
end

---@return finder
function Session:finder()
    return finders.new_dynamic({
        fn = function(prompt)
            return self:items_for_prompt(prompt)
        end,
        entry_maker = function(item)
            return self:make_entry(item)
        end,
    })
end

---@param picker Picker|table
---@param opts? { after_refresh?: fun(current_picker: Picker|table) }
---@return nil
function Session:start(picker, opts)
    if self.started then
        return
    end

    self.started = true
    self.picker = picker
    opts = opts or {}
    if
        type(picker.get_status_updater) == "function"
        and picker.prompt_win
        and picker.prompt_bufnr
    then
        self.status_updater = picker:get_status_updater(picker.prompt_win, picker.prompt_bufnr)
        if picker.prompt_bufnr and vim.api and vim.api.nvim_create_autocmd then
            vim.api.nvim_create_autocmd("BufWipeout", {
                buffer = picker.prompt_bufnr,
                once = true,
                callback = function()
                    close_count_timer(self)
                end,
            })
        end
    end

    vim.schedule(function()
        local ok, prepared = pcall(self.prepare)
        if ok then
            set_ready(self, prepared)
        else
            self.state = "error"
            self.error_message = tostring(prepared)
        end

        if not picker_is_active(picker) then
            return
        end

        if type(picker.refresh) == "function" then
            picker:refresh(self:finder(), { reset_prompt = false })
        end

        if type(opts.after_refresh) == "function" then
            opts.after_refresh(picker)
        end
    end)
end

local M = {}

---@param opts vault.TelescopeProgressiveOptions
---@return vault.TelescopeProgressiveSession
function M.new(opts)
    return Session:new(opts)
end

return M
