local utils = {}
local config = require("vault.config")
local enums = require("vault.utils.enums")

--- Generate a uuid e.g. 202301011924 (YYYYMMDDHHMM)
---@return string
function utils.generate_uuid()
    return tostring(os.date("%Y%m%d%H%M"))
end

--- Format an absolute path to a relative path.
---@param path string - The absolute path to format.
---@return string - The formatted relative path.
function utils.path_to_relpath(path)
    if type(path) ~= "string" then
        error("path must be a string, got " .. type(path))
    end
    local root_dir = config.root
    path = path:gsub(root_dir .. "/", "")
    return path
end

--- Format a relative path to an absolute path.
---@param relpath string - The relative path to format.
---@return string - The formatted `absolute path`.
function utils.relpath_to_path(relpath)
    local root_dir = config.root
    if relpath:sub(1, 1) == "/" then
        return root_dir .. relpath
    end
    return root_dir .. "/" .. relpath
end

--- Format a path to a note link.
---@param path string - The path to format.
---@return string - The formatted note link.
function utils.path_to_slug(path)
    if type(path) ~= "string" then
        error("path must be a string, got " .. type(path))
    end
    local relpath = utils.path_to_relpath(path)
    local slug = relpath:sub(1, #relpath - #config.ext)
    return slug
end

--- Check if the value is a tag.
function utils.is_tag(tag_name)
    local raw_tag = "#" .. tag_name
    if not config.tags.valid.hex then
        local hex_pattern = "(#[A-Fa-f0-9]+){3,6}"
        if raw_tag:match(hex_pattern) ~= nil then
            return false
        end
    end
    return true
end

---@param tbl table - The table to check.
---@param expected_type string - The expected type.
---| "string" - The expected type is string.
---| "table" - The expected type is table.
---| "number" - The expected type is number.
---| "boolean" - The expected type is boolean.
---| "function" - The expected type is function.
---| "thread" - The expected type is thread.
---| "userdata" - The expected type is userdata.
---@return boolean
function utils.is_flatten_list(tbl, expected_type)
    if not tbl then
        error("`tbl` argument is required.")
    end

    if type(tbl) ~= "table" then
        error("`tbl` argument must be a table, got " .. type(tbl))
    end

    if not expected_type then
        error("`expected_type` argument is required.")
    end

    if type(expected_type) ~= "string" then
        error("`expected_type` argument must be a string, got " .. type(expected_type))
    end

    for _, v in ipairs(tbl) do
        if type(v) == expected_type then
            return true
        end
    end

    return false
end

function utils.warn(msg)
    vim.notify(msg, vim.log.levels.WARN, { title = "Vault" })
end

function utils.error(msg)
    vim.notify(msg, vim.log.levels.ERROR, { title = "Vault" })
end

function utils.debug(msg)
    if config.debug then
        vim.notify(msg, vim.log.levels.DEBUG, { title = "Vault" })
    end
end

function utils.info(msg)
    vim.notify(msg, vim.log.levels.INFO, { title = "Vault" })
end

-- The perform_match function now takes an additional parameter, the match type
---@param a string - The value to filter notes.
---@param b string - The value to filter notes.
---@param match_opt VaultMatchOptsKey - The match type to use.
---|"'exact'" # Matches exact value. E.g., "foo" matches "foo" but not "foobar".
---|"'contains'" # Matches value if it contains the query. E.g., "foo" matches "foo" and "foobar".
---|"'startswith'" # Matches value if it starts with the query. E.g., "foo" matches "foo" and "foobar".
---|"'endswith'" # Matches value if it ends with the query. E.g., "foo" matches "foo" and "barfoo".
---|"'regex'" # Matches value if it matches the query as a regex. E.g., "foo" matches "foo" and "barfoo".
---@param case_sensitive boolean? - Whether or not to match case sensitively.
---@return boolean
function utils.match(a, b, match_opt, case_sensitive)
    if type(a) ~= "string" or type(b) ~= "string" then
        return false
    end

    ---@type number
    local v = enums.match_opts[match_opt]

    if not v then
        return false
    end

    if case_sensitive == false then
        a = string.lower(a)
        b = string.lower(b)
    end

    if v == 1 then -- exact
        if a == b then
            return true
        end
    elseif v == 2 then -- contains
        if string.find(a, b, 1, true) then
            return true
        end
    elseif v == 3 then -- startswith
        if vim.startswith(a, b) then
            return true
        end
    elseif v == 4 then -- endswith
        if string.sub(a, -#b) == b then
            return true
        end
    elseif v == 5 then -- regex
        if string.match(a, b) then
            return true
        end
    elseif v == 6 then -- fuzzy
        for i = 1, #a do
            if string.sub(a, i, i) == string.sub(b, i, i) then
                return true
            end
        end
    end

    return false
end

return utils