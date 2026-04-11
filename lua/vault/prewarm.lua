local config = require("vault.config")
local state = require("vault.core.state")

local uv = vim.uv or vim.loop

local NOTES_SCHEDULED_KEY = "vault.prewarm.notes.scheduled"
local NOTES_TIMER_KEY = "vault.prewarm.notes.timer"

local M = {}

---@return boolean, integer
local function notes_prewarm_config()
    if vim.env.VAULT_TEST_DISABLE_PREWARM == "1" then
        return false, 0
    end

    local telescope = config.options.telescope or {}
    local prewarm = telescope.prewarm
    if prewarm == false then
        return false, 0
    end

    if type(prewarm) ~= "table" then
        return false, 0
    end

    if prewarm.notes == false then
        return false, tonumber(prewarm.delay_ms) or 2000
    end

    return true, math.max(0, tonumber(prewarm.delay_ms) or 2000)
end

local function clear_timer_state(timer)
    if timer then
        timer:stop()
        timer:close()
    end
    state.set_global_key(NOTES_TIMER_KEY, nil)
    state.set_global_key(NOTES_SCHEDULED_KEY, nil)
end

function M.cancel_notes()
    local timer = state.get_global_key(NOTES_TIMER_KEY)
    if timer then
        clear_timer_state(timer)
        return true
    end

    state.set_global_key(NOTES_SCHEDULED_KEY, nil)
    return false
end

function M.prewarm_notes()
    pcall(require, "telescope._extensions.vault.pickers.notes")

    local ok, prep = pcall(require, "telescope._extensions.vault.pickers.notes.default_prep")
    if not ok then
        return false
    end

    local prepared_ok = pcall(prep.get_or_prepare)
    return prepared_ok
end

function M.schedule_notes()
    local enabled, delay_ms = notes_prewarm_config()
    if not enabled then
        M.cancel_notes()
        return false
    end

    if state.get_global_key(NOTES_SCHEDULED_KEY) then
        return true
    end

    local function start_timer()
        local still_enabled = notes_prewarm_config()
        if not still_enabled then
            M.cancel_notes()
            return
        end

        if state.get_global_key(NOTES_TIMER_KEY) then
            return
        end

        local timer = uv.new_timer()
        state.set_global_key(NOTES_SCHEDULED_KEY, true)
        state.set_global_key(NOTES_TIMER_KEY, timer)

        timer:start(delay_ms, 0, function()
            clear_timer_state(timer)
            vim.schedule(function()
                M.prewarm_notes()
            end)
        end)
    end

    state.set_global_key(NOTES_SCHEDULED_KEY, true)
    start_timer()
    return true
end

return M
