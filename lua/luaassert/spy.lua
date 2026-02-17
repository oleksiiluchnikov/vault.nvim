-- Minimal stub implementation of luaassert.spy to satisfy tests in headless environment.
-- This is intentionally minimal and only implements a few helpers commonly used in tests.
local M = {}

-- Create a spy wrapper for a function
function M.new(fn)
    fn = fn or function() end
    local spy = {}
    spy._fn = fn
    spy.calls = {}

    local function wrapper(...)
        local args = { ... }
        table.insert(spy.calls, args)
        return spy._fn(...)
    end

    -- expose helpers
    function spy.called()
        return #spy.calls > 0
    end

    function spy.call_count()
        return #spy.calls
    end

    function spy.called_with(...) -- naive matching
        local want = { ... }
        for _, call in ipairs(spy.calls) do
            if #call == #want then
                local ok = true
                for i = 1, #want do
                    if call[i] ~= want[i] then
                        ok = false
                        break
                    end
                end
                if ok then
                    return true
                end
            end
        end
        return false
    end

    setmetatable(spy, { __call = function(_, ...) return wrapper(...) end })
    spy.__call = wrapper

    return spy
end

-- Attach a spy to an existing table method
function M.on(tbl, method)
    if not tbl or not method or type(tbl[method]) ~= "function" then
        error("M.on: invalid table or method")
    end
    local orig = tbl[method]
    local s = M.new(orig)
    tbl[method] = function(...)
        return s.__call(...)
    end
    return s
end

return M
