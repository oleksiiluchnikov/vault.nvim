local config = require("vault.config")
local state = require("vault.core.state")

local uv = vim.uv or vim.loop

local PREWARM_SCHEDULED_KEY = "vault.prewarm.scheduled"
local PREWARM_TIMER_KEY = "vault.prewarm.timer"

local M = {}

---@return table|nil, integer
local function prewarm_config()
    if vim.env.VAULT_TEST_DISABLE_PREWARM == "1" then
        return nil, 0
    end

    local telescope = config.options.telescope or {}
    local prewarm = telescope.prewarm
    if prewarm == false then
        return nil, 0
    end

    if type(prewarm) ~= "table" then
        return nil, 0
    end

    return prewarm, math.max(0, tonumber(prewarm.delay_ms) or 2000)
end

---@param prewarm table
---@return boolean
local function has_enabled_prewarm(prewarm)
    return prewarm.notes ~= false
        or prewarm.properties ~= false
        or prewarm.tags ~= false
        or prewarm.dirs ~= false
end

local function clear_timer_state(timer)
    if timer then
        timer:stop()
        timer:close()
    end
    state.set_global_key(PREWARM_TIMER_KEY, nil)
    state.set_global_key(PREWARM_SCHEDULED_KEY, nil)
end

function M.cancel()
    local timer = state.get_global_key(PREWARM_TIMER_KEY)
    if timer then
        clear_timer_state(timer)
        return true
    end

    state.set_global_key(PREWARM_SCHEDULED_KEY, nil)
    return false
end

function M.cancel_notes()
    return M.cancel()
end

function M.prewarm_notes()
    local ok_link_index, notes_link_index = pcall(require, "vault.notes.link_index")
    if not ok_link_index or not pcall(notes_link_index.get) then
        return false
    end

    local ok_notes, Notes = pcall(require, "vault.notes")
    if not ok_notes or not pcall(Notes) then
        return false
    end

    pcall(require, "telescope._extensions.vault.pickers.notes")

    local ok, prep = pcall(require, "telescope._extensions.vault.pickers.notes.default_prep")
    if not ok then
        return false
    end

    local prepared_ok = pcall(prep.get_or_prepare)
    return prepared_ok
end

function M.prewarm_tags()
    pcall(require, "telescope._extensions.vault.pickers.tags")

    local ok, prep = pcall(require, "telescope._extensions.vault.pickers.tags.default_prep")
    if not ok then
        return false
    end

    return pcall(prep.get_or_prepare)
end

function M.prewarm_properties()
    pcall(require, "telescope._extensions.vault.pickers.properties")

    local ok, prep = pcall(require, "telescope._extensions.vault.pickers.properties.default_prep")
    if not ok then
        return false
    end

    return pcall(prep.get_or_prepare)
end

function M.prewarm_dirs()
    pcall(require, "telescope._extensions.vault.pickers.dirs")

    local ok, prep = pcall(require, "telescope._extensions.vault.pickers.dirs.default_prep")
    if not ok then
        return false
    end

    return pcall(prep.get_or_prepare)
end

---@param prewarm table
---@return boolean
local function run_enabled_prewarms(prewarm)
    local jobs = {
        { enabled = prewarm.notes ~= false, run = M.prewarm_notes },
        { enabled = prewarm.properties ~= false, run = M.prewarm_properties },
        { enabled = prewarm.tags ~= false, run = M.prewarm_tags },
        { enabled = prewarm.dirs ~= false, run = M.prewarm_dirs },
    }

    local ran = false
    local ok = true
    for _, job in ipairs(jobs) do
        if job.enabled then
            ran = true
            if not job.run() then
                ok = false
            end
        end
    end

    return ran and ok
end

function M.schedule()
    local prewarm, delay_ms = prewarm_config()
    if not prewarm or not has_enabled_prewarm(prewarm) then
        M.cancel()
        return false
    end

    if state.get_global_key(PREWARM_SCHEDULED_KEY) then
        return true
    end

    local function start_timer()
        local current_prewarm = select(1, prewarm_config())
        if not current_prewarm or not has_enabled_prewarm(current_prewarm) then
            M.cancel()
            return
        end

        if state.get_global_key(PREWARM_TIMER_KEY) then
            return
        end

        local timer = uv.new_timer()
        state.set_global_key(PREWARM_SCHEDULED_KEY, true)
        state.set_global_key(PREWARM_TIMER_KEY, timer)

        timer:start(delay_ms, 0, function()
            clear_timer_state(timer)
            vim.schedule(function()
                run_enabled_prewarms(current_prewarm)
            end)
        end)
    end

    state.set_global_key(PREWARM_SCHEDULED_KEY, true)
    start_timer()
    return true
end

function M.schedule_notes()
    return M.schedule()
end

return M
