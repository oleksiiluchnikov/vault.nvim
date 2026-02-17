-- Minimal stub implementation of luaassert.stub to satisfy tests in headless environment.
-- Provides a subset of functionality used by tests: basic stubbing of functions with restore.
local M = {}

local stubs = {}

-- Create a stub function and replace target function
function M.new(fn)
    fn = fn or function() end
    local s = {}
    s._fn = fn
    s.calls = {}

    local function wrapper(...)
        table.insert(s.calls, { ... })
        if type(s._fn) == "function" then
            return s._fn(...)
        end
    end

    function s.called()
        return #s.calls > 0
    end

    function s.call_count()
        return #s.calls
    end

    setmetatable(s, { __call = function(_, ...) return wrapper(...) end })
    s.__call = wrapper

    return s
end

-- Attach a stub to a table method and return the stub so tests can inspect calls
function M.on(tbl, method, fn)
    if not tbl or not method or type(tbl[method]) ~= "function" then
        error("M.on: invalid table or method")
    end
    local orig = tbl[method]
    local s = M.new(fn or function() end)
    tbl[method] = function(...)
        return s.__call(...)
    end

    -- store for restore
    stubs[#stubs + 1] = { tbl = tbl, method = method, orig = orig }
    return s
end

-- Restore all stubbed methods
function M.restore()
    for _, v in ipairs(stubs) do
        v.tbl[v.method] = v.orig
    end
    stubs = {}
end

return M
