-- Here the interesting function are for testing,
-- but they under .gitignore, so they are not pushed to github.

--


--- VaultNote <method> <target(key)> <arg1> <arg2> ...
---```vim
---:VaultNote open <autocomplete basename>
local function get_methods(object)
    local methods = {}
    for k, v in pairs(getmetatable(object)) do
        if type(v) == "function" then
            local ignore_patterns = {
                "^__",
                "init",
            }
            local ignore = false
            -- table.insert(VaultNotesMethods, k)
            for _, pattern in ipairs(ignore_patterns) do
                if k:match(pattern) then
                    ignore = true
                end
            end
            if not ignore then
                table.insert(methods, k)
            end
        end
    end
    return methods
end

local function get_function_args(method)
    local arguments = {}
    local info = debug.getinfo(method)
    local source = info.source:sub(2) -- Remove the @ from the beginning
    local source_lines = vim.fn.readfile(source)
    local method_line = source_lines[info.linedefined]
    local method_arguments = method_line:match("%((.*)%)")
    method_arguments = vim.split(method_arguments, ",")
    for _, argument in ipairs(method_arguments) do
        argument = vim.trim(argument)
        if not argument:match("self") and argument ~= "" then
            table.insert(arguments, argument)
        end
    end
    return arguments
end

local function get_keys(object)
    local keys = {}
    for k, _ in pairs(object) do
        table.insert(keys, k)
    end
    return keys
end
