local Object = require("vault.core.object")
local Field = require("vault.fields.field")

--- Frontmatter class
--- @class vault.Note.Frontmatter: vault.Object - The frontmatter of a note.
--- @field raw string - The raw frontmatter string.
local NoteFrontmatter = Object("VaultNoteFrontmatter")

--- Create a new NoteFrontmatter object.
--- @param this vault.Note.Data.content - The content of the note.
function NoteFrontmatter:init(this)
    if type(this) ~= "string" then
        error("Invalid argument: " .. vim.inspect(this))
    end
    if not this:match("^%-%-%-") then
        error("NoteFrontmatter must start with --- ")
    end
    -- local frontmatter = this:gmatch("^%-%-%-(.-)%-%-%-")[1]
    -- local frontmatter
    -- for line in this:gmatch("^%-%-%-(.-)%-%-%-") do
    --     frontmatter = line
    --     break
    -- end
    local frontmatter = this:match("^%-%-%-\n(.-)%-%-%-")

    self.raw = frontmatter
    -- TODO: add support for tables to extend them
    self.data = {}
    self:decode(frontmatter)
end

function NoteFrontmatter:add_field(key, value)
    self.data[key] = value
    return self
end

--- Decode a frontmatter string to a table.
--- @param s string - The frontmatter string to decode.
--- @return vault.Note.Frontmatter - The decoded frontmatter.
function NoteFrontmatter:decode(s)
    local lines = vim.split(s, "\n")
    for i, line in ipairs(lines) do
        if line == "" then
            table.remove(lines, i)
        elseif line:match("^%s+") then
            -- it is nested field
            -- we should merge it with all previous lines until we find a non-nested field
            local j = i - 1
            while j > 0 do
                local prev_line = lines[j]
                if prev_line:match("^%s+") then
                    lines[j] = prev_line .. "\n" .. line
                    table.remove(lines, i)
                    i = i - 1
                    j = j - 1
                else
                    break
                end
            end

            -- merge with the next line if it is also a nested field
            lines[i] = lines[i - 1] .. "\n" .. lines[i]
        end
    end
    local raw_fields = lines
    for _, field_string in ipairs(raw_fields) do
        if field_string:match("^%s*$") then
            goto continue
        end
        --- @type VaultField
        local field = Field(field_string)

        if field == nil then
            goto continue
        end
        if field.key == nil then
            goto continue
        end
        self:add_field(field.key, field.value)
        ::continue::
    end

    return self
end

function NoteFrontmatter:to_table()
    local tbl = {}
    for k, v in pairs(self) do
        if type(k) ~= "function" then
            tbl[k] = v
        end
    end
    return tbl
end

--- Encode a table to frontmatter string.
--- @param tbl? table - The table to encode.
--- @return string - The encoded frontmatter.
function NoteFrontmatter:encode(tbl)
    tbl = tbl or self:to_table()
    local frontmatter = "--- \n"
    for key, value in pairs(tbl) do
        if type(value) == "table" then
            value = vim.inspect(value)
        end
        if type(value) == "boolean" then
            value = tostring(value)
        end
        if type(value) == "number" then
            value = tostring(value)
        end
        frontmatter = frontmatter .. key .. ": " .. value .. "\n"
    end

    frontmatter = frontmatter .. "--- \n"
    return frontmatter
end

--- Convert the NoteFrontmatter to a string.
--- @return string
function NoteFrontmatter:__tostring()
    return self:encode()
end

--- @alias NoteFrontmatter.constructor fun(text: string): vault.Note.Frontmatter
--- @type NoteFrontmatter.constructor|vault.Note.Frontmatter
local VaultNoteFrontmatter = NoteFrontmatter

return VaultNoteFrontmatter -- [[@as VaultsNoteFrontmatter.constructor]]
