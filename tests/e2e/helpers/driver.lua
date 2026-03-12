---@class vault.e2e.DriverSession
---@field socket string
---@field root string
---@field artifacts_dir string
---@field proc vim.SystemObj

local artifacts = require("tests.e2e.helpers.artifacts")
local fixture = require("tests.e2e.helpers.fixture")

local M = {}

local function system(cmd, opts)
    return vim.system(cmd, vim.tbl_extend("force", { text = true }, opts or {})):wait()
end

local function trim(text)
    return vim.trim((text or ""):gsub("\r", ""))
end

---@param socket string
---@param expr string
---@return string
local function remote_expr(socket, expr)
    local result = system({ "nvim", "--server", socket, "--remote-expr", expr })
    if result.code ~= 0 then
        error(trim(result.stderr ~= "" and result.stderr or result.stdout))
    end
    return trim(result.stdout)
end

---@param socket string
---@param keys string
local function remote_send(socket, keys)
    local result = system({ "nvim", "--server", socket, "--remote-send", keys })
    if result.code ~= 0 then
        error(trim(result.stderr ~= "" and result.stderr or result.stdout))
    end
end

---@param socket string
---@param timeout_ms integer
local function wait_until_ready(socket, timeout_ms)
    local deadline = vim.loop.now() + timeout_ms
    while vim.loop.now() < deadline do
        if pcall(remote_expr, socket, "1") then
            return
        end
        vim.wait(100)
    end
    error("Timed out waiting for Neovim E2E session to start")
end

---@param session vault.e2e.DriverSession
function M.stop(session)
    pcall(remote_send, session.socket, "<Esc>:qa!<CR>")
    pcall(function() session.proc:wait(5000) end)
end

---@param session vault.e2e.DriverSession
---@param command string
function M.command(session, command)
    remote_send(session.socket, string.format(":%s<CR>", command))
end

---@param session vault.e2e.DriverSession
---@param expr string
---@return string
function M.expr(session, expr)
    return remote_expr(session.socket, expr)
end

---@param session vault.e2e.DriverSession
---@param keys string
function M.keys(session, keys)
    remote_send(session.socket, keys)
end

---@param session vault.e2e.DriverSession
---@param predicate fun(): boolean
---@param opts? { timeout_ms?: integer, interval_ms?: integer }
---@return boolean
function M.wait_for(session, predicate, opts)
    opts = opts or {}
    local timeout_ms = opts.timeout_ms or 5000
    local interval_ms = opts.interval_ms or 100
    local deadline = vim.loop.now() + timeout_ms
    while vim.loop.now() < deadline do
        if predicate() then
            return true
        end
        vim.wait(interval_ms)
    end
    artifacts.write_text(session.artifacts_dir, "timeout.txt", "Timed out waiting for E2E predicate")
    return false
end

---@param session vault.e2e.DriverSession
function M.capture(session)
    local ok_messages, messages = pcall(M.expr, session, [[execute('messages')]])
    if ok_messages then
        artifacts.write_text(session.artifacts_dir, "messages.txt", messages)
    end
    local ok_buf, bufname = pcall(M.expr, session, [[expand('%:p')]])
    if ok_buf then
        artifacts.write_text(session.artifacts_dir, "current-buffer.txt", bufname)
    end
end

---@param opts? { source_root?: string, scenario?: string, lines?: integer, columns?: integer }
---@return vault.e2e.DriverSession
function M.start(opts)
    opts = opts or {}
    local source_root = opts.source_root or fixture.default_source_vault()
    local clone_root = fixture.clone_vault(source_root, { prefix = "vault-e2e-clone" })
    local artifacts_dir = artifacts.create_dir(opts.scenario or "scenario")
    local socket = fixture.make_temp_dir("vault-e2e-socket") .. "/nvim.sock"
    local appname = "nvim-vault-e2e-" .. tostring(os.time())
    local proc = vim.system({
        "nvim",
        "--headless",
        "-u",
        "tests/minimal_init.lua",
        "--listen",
        socket,
    }, {
        cwd = vim.fn.getcwd(),
        env = {
            NVIM_LISTEN_ADDRESS = "",
            NVIM_APPNAME = appname,
            VAULT_TEST_APPNAME = appname,
            VAULT_TEST_ROOT = clone_root,
            VAULT_TEST_LINES = tostring(opts.lines or 40),
            VAULT_TEST_COLUMNS = tostring(opts.columns or 140),
            VAULT_TEST_ARTIFACTS = artifacts_dir,
        },
        detach = true,
    })
    local session = {
        socket = socket,
        root = clone_root,
        artifacts_dir = artifacts_dir,
        proc = proc,
    }
    wait_until_ready(socket, 10000)
    return session
end

return M
