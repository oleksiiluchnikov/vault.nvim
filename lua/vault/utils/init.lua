local utils = {}
local config = require("vault.config")
local enums = require("vault.utils.enums")

-- path
--- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ----

--- Validates that a given path is valid
--- @param path string Path to validate
--- @return nil nil if valid, error otherwise
function utils.validate_path(path)
    if type(path) ~= "string" then
        error("path must be a string, got " .. type(path))
    end

    -- TODO: Decide if we want to enforce validation of the root directory
    -- local root_dir = config.options.root
    -- if not utils.match(path, root_dir, "startswith") then
    --     error("path must start with " .. root_dir)
    -- end

    local ext = config.options.ext
    if not path:match(ext .. "$") then
        error("path must end with " .. ext)
    end
end

--- Format an absolute path to a relative path.
--- @param path vault.path - The absolute path to format.
--- @return vault.relpath - The formatted relative path.
function utils.path_to_relpath(path)
    if type(path) ~= "string" then
        error("path must be a string, got " .. type(path))
    end
    local root_dir = config.options.root
    if not root_dir then
        error("`VaultConfig.root` is not set.")
    end
    path = path:gsub(root_dir .. "/", "")
    return path
end

--- Format a path to a note link.
--- @param path vault.path - The path to format.
--- @return vault.slug - The formatted note link.
function utils.path_to_slug(path)
    if type(path) ~= "string" then
        error("path must be a string, got " .. type(path))
    end
    local relpath = utils.path_to_relpath(path)
    local slug = relpath:sub(1, #relpath - #config.options.ext)
    return slug
end

--- Format an absolute path to a stem.
--- @param path vault.path
--- @return vault.stem
function utils.path_to_stem(path)
    if type(path) ~= "string" then
        error("path must be a string, got " .. type(path))
    end
    return vim.fn.fnamemodify(path, ":t:r")
end

-- relpath
--- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ----

--- Format a relative path to an absolute path.
--- @param relpath string - The relative path to format.
--- @return string - The formatted `absolute path`.
function utils.relpath_to_path(relpath)
    local root_dir = config.options.root
    if relpath:sub(1, 1) == "/" then
        return root_dir .. relpath
    end
    return root_dir .. "/" .. relpath
end

--- Format a relative path to a slug.
--- @param relpath string - The relative path to format.
--- @return vault.slug - The formatted slug.
function utils.relpath_to_slug(relpath)
    return relpath:sub(1, #relpath - #config.options.ext)
end

-- slug
--- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ----

--- Format a note slug to a path.
--- @param slug vault.slug - The slug to format.
--- @return string - The formatted note path.
function utils.slug_to_path(slug)
    local root_dir = config.options.root
    local ext = config.options.ext
    return root_dir .. "/" .. slug .. ext
end

--- Format a note slug to a relative path.
--- @param slug vault.slug - The slug to format.
--- @return string - The formatted relative path.
function utils.slug_to_relpath(slug)
    return slug .. config.options.ext
end

-- tag
--- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ----

--- Check if the given tag name is a valid tag
--- @param tag_name vault.Tag.data.name - The tag name to check
--- @return boolean true if valid tag, false otherwise
function utils.is_tag(tag_name)
    local raw_tag = "#" .. tag_name
    -- Skip if hex color
    if not config.options.tags.valid.hex then
        --- Regex to match hex color codes
        local hex_pattern = "(#[A-Fa-f0-9]+){3,6}"
        if raw_tag:match(hex_pattern) ~= nil then
            --- Hex codes are invalid tags
            return false
        end
    end
    -- Skip if is parth of the url
    -- TODO: Add support for url validation
    -- if not config.options.tags.valid.url then
    --     if raw_tag:match(lua_url_pattern) ~= nil then
    --         return false
    --     end
    -- end

    --- Passed all checks, so must be valid
    return true
end

function utils.validate_tag_name(tag_name)
    tag_name = "#" .. tag_name
    if not utils.is_tag(tag_name) then
        error("Invalid tag name: " .. tag_name)
    end
end

--- @param tbl table - The table to check.
--- @param expected_type string - The expected type.
--- | "string" - The expected type is string.
--- | "table" - The expected type is table.
--- | "number" - The expected type is number.
--- | "boolean" - The expected type is boolean.
--- | "function" - The expected type is function.
--- | "thread" - The expected type is thread.
--- | "userdata" - The expected type is userdata.
--- @return boolean
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
    if config.options.debug then
        vim.notify(msg, vim.log.levels.DEBUG, { title = "Vault" })
    end
end

function utils.info(msg)
    vim.notify(msg, vim.log.levels.INFO, { title = "Vault" })
end

--- Performs a fuzzy match between two strings
--- @param a string The first string
--- @param b string The second string
--- @return boolean True if the strings match, false otherwise
function utils.fuzzy_match(a, b)
    local a_len, b_len = #a, #b
    local a_idx, b_idx = 1, 1

    while a_idx <= a_len and b_idx <= b_len do
        if string.sub(a, a_idx, a_idx) == string.sub(b, b_idx, b_idx) then
            b_idx = b_idx + 1
        end
        a_idx = a_idx + 1
    end

    return b_idx > b_len
end

-- The perform_match function now takes an additional parameter, the match type
--- Checks if two strings match based on the given match option
--- @param a string The first string to compare
--- @param b string The second string to compare
--- @param match_opt vault.enum.MatchOpts.key The match option to use
--- |"'exact'" Matches exact value. E.g., "foo" matches "foo" but not "foobar".
--- |"'contains'" Matches value if it contains the query. E.g., "foo" matches "foo" and "foobar".
--- |"'startswith'" Matches value if it starts with the query. E.g., "foo" matches "foo" and "foobar".
--- |"'endswith'" Matches value if it ends with the query. E.g., "foo" matches "foo" and "barfoo".
--- |"'regex'" Matches value if it matches the query as a regex. E.g., "foo" matches "foo" and "barfoo".
--- @param case_sensitive? boolean Whether to match case sensitively
--- @return boolean True if the strings match, false otherwise
function utils.match(a, b, match_opt, case_sensitive)
    if type(a) ~= "string" or type(b) ~= "string" then
        return false
    end

    --- @type number
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
        if string.sub(a, - #b) == b then
            return true
        end
    elseif v == 5 then -- regex
        -- Convert regex to lua valid pattern
        -- TODO: Add support for regex validation
        -- if string.match(a, b) then
        if vim.fn.matchlist(a, b) ~= nil then
            return true
        end
    elseif v == 6 then -- fuzzy
        return utils.fuzzy_match(a, b)
    end

    return false
end

--- Generate a uuid e.g. 202301011924 (YYYYMMDDHHMM)
--- @return number
function utils.generate_uuid()
    -- return tostring(os.date("%Y%m%d%H%M%S")) -- YYYYMMDDHHMMSS (202301011924)
    return tonumber(os.date("%Y%m%d%H%M")) -- YYYYMMDDHHMM (202301011924)
end

return utils
