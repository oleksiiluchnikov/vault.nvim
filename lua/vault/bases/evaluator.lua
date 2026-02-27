--- vault.bases.evaluator — Full recursive descent expression parser and evaluator
--- for Obsidian Bases filter trees and formula expressions.
---
--- Covers ALL Obsidian Bases functions:
---   File:   file.hasTag, file.hasLink, file.inFolder, file.asLink
---   String: .contains, .containsAll, .containsAny, .startsWith, .endsWith,
---           .lower, .split, .replace, .trim, .title, .slice, .isEmpty, .length
---   Number: .abs, .ceil, .floor, .round, .toFixed, .isEmpty
---   Date:   .format, .date, .time, .relative, .year, .month, .day, .hour, .minute, .second
---   List:   .contains, .containsAll, .containsAny, .join, .sort, .flat, .unique,
---           .reverse, .slice, .length, .isEmpty
---   Link:   .linksTo
---   Object: .isEmpty, .keys, .values
---   Global: date, today, now, if, image, max, min, link, list, number, duration
---   Ops:    + - * / % == != > < >= <= ! && || (date arithmetic with durations)
---
--- @module vault.bases.evaluator

local config = require("vault.config")
local utils = require("vault.utils")

local M = {}


-- ============================================================================
-- Token Types
-- ============================================================================

local TK = {
    NUMBER = "NUMBER",
    STRING = "STRING",
    BOOLEAN = "BOOLEAN",
    IDENT = "IDENT",
    DOT = "DOT",
    LPAREN = "LPAREN",
    RPAREN = "RPAREN",
    COMMA = "COMMA",
    PLUS = "PLUS",
    MINUS = "MINUS",
    STAR = "STAR",
    SLASH = "SLASH",
    PERCENT = "PERCENT",
    EQ = "EQ",
    NEQ = "NEQ",
    GT = "GT",
    LT = "LT",
    GTE = "GTE",
    LTE = "LTE",
    NOT = "NOT",
    AND = "AND",
    OR = "OR",
    EOF = "EOF",
}


-- ============================================================================
-- Tokenizer
-- ============================================================================

--- @class vault.bases.Token
--- @field type string
--- @field value any

--- Tokenize an expression string into a list of tokens.
--- @param input string
--- @return vault.bases.Token[]
local function tokenize(input)
    local tokens = {}
    local pos = 1
    local len = #input

    while pos <= len do
        local ch = input:sub(pos, pos)

        -- Skip whitespace
        if ch:match("%s") then
            pos = pos + 1

        -- Double-quoted string
        elseif ch == '"' then
            local start = pos + 1
            pos = pos + 1
            local parts = {}
            while pos <= len do
                local c = input:sub(pos, pos)
                if c == "\\" and pos + 1 <= len then
                    pos = pos + 1
                    parts[#parts + 1] = input:sub(pos, pos)
                    pos = pos + 1
                elseif c == '"' then
                    break
                else
                    parts[#parts + 1] = c
                    pos = pos + 1
                end
            end
            tokens[#tokens + 1] = { type = TK.STRING, value = table.concat(parts) }
            pos = pos + 1 -- skip closing quote

        -- Single-quoted string
        elseif ch == "'" then
            local start = pos + 1
            pos = pos + 1
            local parts = {}
            while pos <= len do
                local c = input:sub(pos, pos)
                if c == "\\" and pos + 1 <= len then
                    pos = pos + 1
                    parts[#parts + 1] = input:sub(pos, pos)
                    pos = pos + 1
                elseif c == "'" then
                    break
                else
                    parts[#parts + 1] = c
                    pos = pos + 1
                end
            end
            tokens[#tokens + 1] = { type = TK.STRING, value = table.concat(parts) }
            pos = pos + 1

        -- Numbers (integer and float)
        elseif ch:match("[%d]") or (ch == "-" and pos + 1 <= len and input:sub(pos + 1, pos + 1):match("%d")) then
            local start = pos
            if ch == "-" then
                pos = pos + 1
            end
            while pos <= len and input:sub(pos, pos):match("[%d]") do
                pos = pos + 1
            end
            if pos <= len and input:sub(pos, pos) == "." then
                pos = pos + 1
                while pos <= len and input:sub(pos, pos):match("[%d]") do
                    pos = pos + 1
                end
            end
            tokens[#tokens + 1] = { type = TK.NUMBER, value = tonumber(input:sub(start, pos - 1)) }

        -- Operators and punctuation
        elseif ch == "(" then
            tokens[#tokens + 1] = { type = TK.LPAREN, value = "(" }
            pos = pos + 1
        elseif ch == ")" then
            tokens[#tokens + 1] = { type = TK.RPAREN, value = ")" }
            pos = pos + 1
        elseif ch == "," then
            tokens[#tokens + 1] = { type = TK.COMMA, value = "," }
            pos = pos + 1
        elseif ch == "." then
            tokens[#tokens + 1] = { type = TK.DOT, value = "." }
            pos = pos + 1
        elseif ch == "+" then
            tokens[#tokens + 1] = { type = TK.PLUS, value = "+" }
            pos = pos + 1
        elseif ch == "-" then
            tokens[#tokens + 1] = { type = TK.MINUS, value = "-" }
            pos = pos + 1
        elseif ch == "*" then
            tokens[#tokens + 1] = { type = TK.STAR, value = "*" }
            pos = pos + 1
        elseif ch == "/" then
            tokens[#tokens + 1] = { type = TK.SLASH, value = "/" }
            pos = pos + 1
        elseif ch == "%" then
            tokens[#tokens + 1] = { type = TK.PERCENT, value = "%" }
            pos = pos + 1
        elseif ch == "=" and pos + 1 <= len and input:sub(pos + 1, pos + 1) == "=" then
            tokens[#tokens + 1] = { type = TK.EQ, value = "==" }
            pos = pos + 2
        elseif ch == "!" and pos + 1 <= len and input:sub(pos + 1, pos + 1) == "=" then
            tokens[#tokens + 1] = { type = TK.NEQ, value = "!=" }
            pos = pos + 2
        elseif ch == "!" then
            tokens[#tokens + 1] = { type = TK.NOT, value = "!" }
            pos = pos + 1
        elseif ch == ">" and pos + 1 <= len and input:sub(pos + 1, pos + 1) == "=" then
            tokens[#tokens + 1] = { type = TK.GTE, value = ">=" }
            pos = pos + 2
        elseif ch == ">" then
            tokens[#tokens + 1] = { type = TK.GT, value = ">" }
            pos = pos + 1
        elseif ch == "<" and pos + 1 <= len and input:sub(pos + 1, pos + 1) == "=" then
            tokens[#tokens + 1] = { type = TK.LTE, value = "<=" }
            pos = pos + 2
        elseif ch == "<" then
            tokens[#tokens + 1] = { type = TK.LT, value = "<" }
            pos = pos + 1
        elseif ch == "&" and pos + 1 <= len and input:sub(pos + 1, pos + 1) == "&" then
            tokens[#tokens + 1] = { type = TK.AND, value = "&&" }
            pos = pos + 2
        elseif ch == "|" and pos + 1 <= len and input:sub(pos + 1, pos + 1) == "|" then
            tokens[#tokens + 1] = { type = TK.OR, value = "||" }
            pos = pos + 2

        -- Identifiers and keywords
        elseif ch:match("[%a_]") then
            local start = pos
            while pos <= len and input:sub(pos, pos):match("[%a%d_]") do
                pos = pos + 1
            end
            local word = input:sub(start, pos - 1)
            if word == "true" then
                tokens[#tokens + 1] = { type = TK.BOOLEAN, value = true }
            elseif word == "false" then
                tokens[#tokens + 1] = { type = TK.BOOLEAN, value = false }
            else
                tokens[#tokens + 1] = { type = TK.IDENT, value = word }
            end

        else
            -- Skip unknown characters
            pos = pos + 1
        end
    end

    tokens[#tokens + 1] = { type = TK.EOF, value = nil }
    return tokens
end


-- ============================================================================
-- Parser — Recursive Descent
-- ============================================================================

--- @class vault.bases.Parser
--- @field tokens vault.bases.Token[]
--- @field pos integer
local Parser = {}
Parser.__index = Parser


--- Create a new parser for the given tokens.
--- @param tokens vault.bases.Token[]
--- @return vault.bases.Parser
function Parser.new(tokens)
    return setmetatable({ tokens = tokens, pos = 1 }, Parser)
end


--- Peek at current token.
--- @return vault.bases.Token
function Parser:peek()
    return self.tokens[self.pos] or { type = TK.EOF, value = nil }
end


--- Advance and return the current token.
--- @return vault.bases.Token
function Parser:advance()
    local tok = self.tokens[self.pos]
    self.pos = self.pos + 1
    return tok or { type = TK.EOF, value = nil }
end


--- Expect a specific token type, advance and return it. Error if mismatch.
--- @param tk_type string
--- @return vault.bases.Token
function Parser:expect(tk_type)
    local tok = self:advance()
    if tok.type ~= tk_type then
        error(string.format(
            "Expected token %s but got %s (%s) at position %d",
            tk_type, tok.type, tostring(tok.value), self.pos - 1
        ))
    end
    return tok
end


--- Match current token type and advance if match.
--- @param tk_type string
--- @return vault.bases.Token|nil
function Parser:match(tk_type)
    if self:peek().type == tk_type then
        return self:advance()
    end
    return nil
end


-- Expression parsing with precedence climbing:
-- or_expr -> and_expr ( "||" and_expr )*
-- and_expr -> equality_expr ( "&&" equality_expr )*
-- equality_expr -> comparison_expr ( ("==" | "!=") comparison_expr )*
-- comparison_expr -> additive_expr ( (">" | "<" | ">=" | "<=") additive_expr )*
-- additive_expr -> multiplicative_expr ( ("+" | "-") multiplicative_expr )*
-- multiplicative_expr -> unary_expr ( ("*" | "/" | "%") unary_expr )*
-- unary_expr -> ("!" | "-") unary_expr | postfix_expr
-- postfix_expr -> primary ( "." IDENT ( "(" args ")" )? | "(" args ")" )*
-- primary -> NUMBER | STRING | BOOLEAN | IDENT | "(" expr ")"


--- Parse a full expression.
--- @return table AST node
function Parser:parse_expression()
    return self:parse_or()
end


function Parser:parse_or()
    local left = self:parse_and()
    while self:peek().type == TK.OR do
        self:advance()
        local right = self:parse_and()
        left = { type = "binary", op = "||", left = left, right = right }
    end
    return left
end


function Parser:parse_and()
    local left = self:parse_equality()
    while self:peek().type == TK.AND do
        self:advance()
        local right = self:parse_equality()
        left = { type = "binary", op = "&&", left = left, right = right }
    end
    return left
end


function Parser:parse_equality()
    local left = self:parse_comparison()
    while self:peek().type == TK.EQ or self:peek().type == TK.NEQ do
        local op = self:advance().value
        local right = self:parse_comparison()
        left = { type = "binary", op = op, left = left, right = right }
    end
    return left
end


function Parser:parse_comparison()
    local left = self:parse_additive()
    while self:peek().type == TK.GT
        or self:peek().type == TK.LT
        or self:peek().type == TK.GTE
        or self:peek().type == TK.LTE
    do
        local op = self:advance().value
        local right = self:parse_additive()
        left = { type = "binary", op = op, left = left, right = right }
    end
    return left
end


function Parser:parse_additive()
    local left = self:parse_multiplicative()
    while self:peek().type == TK.PLUS or self:peek().type == TK.MINUS do
        local op = self:advance().value
        local right = self:parse_multiplicative()
        left = { type = "binary", op = op, left = left, right = right }
    end
    return left
end


function Parser:parse_multiplicative()
    local left = self:parse_unary()
    while self:peek().type == TK.STAR
        or self:peek().type == TK.SLASH
        or self:peek().type == TK.PERCENT
    do
        local op = self:advance().value
        local right = self:parse_unary()
        left = { type = "binary", op = op, left = left, right = right }
    end
    return left
end


function Parser:parse_unary()
    if self:peek().type == TK.NOT then
        self:advance()
        local operand = self:parse_unary()
        return { type = "unary", op = "!", operand = operand }
    end
    if self:peek().type == TK.MINUS then
        -- Only treat as unary minus if previous token is not a number/ident/rparen
        self:advance()
        local operand = self:parse_unary()
        return { type = "unary", op = "-", operand = operand }
    end
    return self:parse_postfix()
end


function Parser:parse_postfix()
    local node = self:parse_primary()

    while true do
        if self:peek().type == TK.DOT then
            self:advance()
            local member = self:expect(TK.IDENT)
            -- Check if it's a method call
            if self:peek().type == TK.LPAREN then
                self:advance()
                local args = self:parse_args()
                self:expect(TK.RPAREN)
                node = { type = "method_call", object = node, method = member.value, args = args }
            else
                -- Property access
                node = { type = "member_access", object = node, member = member.value }
            end
        elseif self:peek().type == TK.LPAREN and node.type == "identifier" then
            -- Function call: ident(args)
            self:advance()
            local args = self:parse_args()
            self:expect(TK.RPAREN)
            node = { type = "function_call", name = node.name, args = args }
        else
            break
        end
    end

    return node
end


function Parser:parse_args()
    local args = {}
    if self:peek().type == TK.RPAREN then
        return args
    end
    args[#args + 1] = self:parse_expression()
    while self:peek().type == TK.COMMA do
        self:advance()
        args[#args + 1] = self:parse_expression()
    end
    return args
end


function Parser:parse_primary()
    local tok = self:peek()

    if tok.type == TK.NUMBER then
        self:advance()
        return { type = "literal", value = tok.value }
    end

    if tok.type == TK.STRING then
        self:advance()
        return { type = "literal", value = tok.value }
    end

    if tok.type == TK.BOOLEAN then
        self:advance()
        return { type = "literal", value = tok.value }
    end

    if tok.type == TK.IDENT then
        self:advance()
        return { type = "identifier", name = tok.value }
    end

    if tok.type == TK.LPAREN then
        self:advance()
        local expr = self:parse_expression()
        self:expect(TK.RPAREN)
        return expr
    end

    error(string.format(
        "Unexpected token %s (%s) at position %d",
        tok.type, tostring(tok.value), self.pos
    ))
end


--- Parse an expression string into an AST.
--- @param input string
--- @return table AST root node
function M.parse(input)
    local tokens = tokenize(input)
    local parser = Parser.new(tokens)
    return parser:parse_expression()
end


-- ============================================================================
-- Evaluator — AST interpreter
-- ============================================================================

--- @class vault.bases.EvalContext
--- @field note vault.Note The note being evaluated
--- @field root string Vault root path

--- Build a context table for evaluation from a note.
--- @param note vault.Note
--- @return vault.bases.EvalContext
local function build_context(note)
    local root = vim.fn.expand(config.options.root)
    return {
        note = note,
        root = root,
    }
end


--- Resolve a dotted identifier path (e.g. "file.name", "status") from context.
--- @param name string The identifier name (first segment)
--- @param ctx vault.bases.EvalContext
--- @return any
local function resolve_identifier(name, ctx)
    local note = ctx.note

    -- file.* namespace
    if name == "file" then
        return {
            _type = "file_ref",
            note = note,
        }
    end

    -- formula.* namespace — resolved by the caller (Base:evaluate_formulas)
    if name == "formula" then
        return { _type = "formula_ref" }
    end

    -- Bare identifiers resolve to frontmatter properties
    if note.data and note.data.frontmatter then
        local fm = note.data.frontmatter
        -- Check directly on frontmatter table (raw table case)
        if fm[name] ~= nil then
            return fm[name]
        end
        -- Check fm.data (VaultNoteFrontmatter object case)
        if type(fm.data) == "table" and fm.data[name] ~= nil then
            return fm.data[name]
        end
    end

    -- Also try data fields directly (use pcall to guard against
    -- NoteData __index metamethod throwing on unknown keys)
    if note.data then
        local ok_d, val_d = pcall(function() return note.data[name] end)
        if ok_d and val_d ~= nil then
            return val_d
        end
    end

    return nil
end


--- Resolve member access on a file_ref object.
--- @param file_ref table
--- @param member string
--- @return any
local function resolve_file_member(file_ref, member)
    local note = file_ref.note

    if member == "name" then
        return note.data.stem or vim.fn.fnamemodify(note.data.path, ":t:r")
    elseif member == "folder" then
        local relpath = note.data.relpath or ""
        return vim.fn.fnamemodify(relpath, ":h")
    elseif member == "ext" then
        return vim.fn.fnamemodify(note.data.path, ":e")
    elseif member == "path" then
        return note.data.path
    elseif member == "relpath" then
        return note.data.relpath
    elseif member == "size" then
        local stat = (vim.uv or vim.loop).fs_stat(note.data.path)
        return stat and stat.size or 0
    elseif member == "ctime" then
        local stat = (vim.uv or vim.loop).fs_stat(note.data.path)
        return stat and stat.birthtime and stat.birthtime.sec or 0
    elseif member == "mtime" then
        local stat = (vim.uv or vim.loop).fs_stat(note.data.path)
        return stat and stat.mtime and stat.mtime.sec or 0
    elseif member == "tags" then
        if note.data.frontmatter and note.data.frontmatter.tags then
            return note.data.frontmatter.tags
        end
        return {}
    elseif member == "links" then
        return note.data.outlinks or {}
    end

    return nil
end


--- Duration parsing: "1y", "2M", "3w", "4d", "5h", "6m", "7s"
--- Returns seconds.
--- @param str string
--- @return number seconds
local function parse_duration(str)
    local total = 0
    for num, unit in str:gmatch("(%d+)(%a)") do
        local n = tonumber(num) or 0
        if unit == "y" then
            total = total + n * 365.25 * 86400
        elseif unit == "M" then
            total = total + n * 30.44 * 86400
        elseif unit == "w" then
            total = total + n * 7 * 86400
        elseif unit == "d" then
            total = total + n * 86400
        elseif unit == "h" then
            total = total + n * 3600
        elseif unit == "m" then
            total = total + n * 60
        elseif unit == "s" then
            total = total + n
        end
    end
    return total
end


--- Check if a value looks like a date (number representing epoch or date string).
--- @param v any
--- @return boolean
local function is_date_value(v)
    if type(v) == "table" and v._type == "date" then
        return true
    end
    return false
end


--- Create a date wrapper.
--- @param epoch number
--- @return table
local function make_date(epoch)
    return { _type = "date", epoch = epoch }
end


--- Try to parse a string as a date. Returns epoch or nil.
--- @param s string
--- @return number|nil
local function parse_date_string(s)
    if type(s) ~= "string" then
        return nil
    end
    -- YYYY-MM-DD
    local y, m, d = s:match("^(%d%d%d%d)-(%d%d)-(%d%d)")
    if y then
        local t = os.time({
            year = tonumber(y),
            month = tonumber(m),
            day = tonumber(d),
            hour = 0,
            min = 0,
            sec = 0,
        })
        return t
    end
    -- Epoch number as string
    local n = tonumber(s)
    if n and n > 1000000000 then
        return n
    end
    return nil
end


-- Forward declaration
local eval_node


--- Evaluate a method call on a value.
--- @param obj any The receiver object
--- @param method string The method name
--- @param args any[] Evaluated argument values
--- @param ctx vault.bases.EvalContext
--- @return any
local function eval_method(obj, method, args, ctx)
    -- nil/missing values: isEmpty → true, everything else → nil/false
    if obj == nil then
        if method == "isEmpty" then return true end
        if method == "length" then return 0 end
        return nil
    end

    -- ---- File methods ----
    if type(obj) == "table" and obj._type == "file_ref" then
        local note = obj.note

        if method == "hasTag" then
            local tag_name = args[1]
            if not tag_name then
                return false
            end
            -- Check frontmatter tags
            if note.data.frontmatter and note.data.frontmatter.tags then
                local tags = note.data.frontmatter.tags
                if type(tags) == "table" then
                    for _, t in ipairs(tags) do
                        if type(t) == "string" and t:lower() == tag_name:lower() then
                            return true
                        end
                        -- Handle Tag objects
                        if type(t) == "table" and t.data and t.data.name then
                            if t.data.name:lower() == tag_name:lower() then
                                return true
                            end
                        end
                    end
                end
            end
            -- Check inline tags via note data
            if note.data.tags then
                local tags = note.data.tags
                if type(tags) == "table" then
                    for key, _ in pairs(tags) do
                        if type(key) == "string" and key:lower() == tag_name:lower() then
                            return true
                        end
                    end
                end
            end
            return false
        end

        if method == "hasLink" then
            local target = args[1]
            if not target then
                return false
            end
            local outlinks = note.data.outlinks or {}
            for _, wl in pairs(outlinks) do
                local stem = wl.data and wl.data.stem or ""
                if stem:lower() == target:lower() then
                    return true
                end
            end
            return false
        end

        if method == "inFolder" then
            local folder = args[1]
            if not folder then
                return false
            end
            local relpath = note.data.relpath or ""
            local note_folder = vim.fn.fnamemodify(relpath, ":h")
            -- Case-insensitive folder match
            return note_folder:lower():find(folder:lower(), 1, true) ~= nil
        end

        if method == "asLink" then
            local display = args[1]
            local stem = note.data.stem or vim.fn.fnamemodify(note.data.path, ":t:r")
            if display then
                return "[[" .. stem .. "|" .. display .. "]]"
            end
            return "[[" .. stem .. "]]"
        end
    end

    -- ---- String methods ----
    if type(obj) == "string" then
        if method == "contains" then
            return obj:lower():find((args[1] or ""):lower(), 1, true) ~= nil
        end
        if method == "containsAll" then
            for _, a in ipairs(args) do
                if not obj:lower():find(tostring(a):lower(), 1, true) then
                    return false
                end
            end
            return true
        end
        if method == "containsAny" then
            for _, a in ipairs(args) do
                if obj:lower():find(tostring(a):lower(), 1, true) then
                    return true
                end
            end
            return false
        end
        if method == "startsWith" then
            local prefix = args[1] or ""
            return obj:sub(1, #prefix) == prefix
        end
        if method == "endsWith" then
            local suffix = args[1] or ""
            return obj:sub(-#suffix) == suffix
        end
        if method == "lower" then
            return obj:lower()
        end
        if method == "upper" then
            return obj:upper()
        end
        if method == "split" then
            local sep = args[1] or " "
            return vim.split(obj, sep, { plain = true })
        end
        if method == "replace" then
            local from = args[1] or ""
            local to = args[2] or ""
            return (obj:gsub(vim.pesc(from), to))
        end
        if method == "trim" then
            return obj:match("^%s*(.-)%s*$")
        end
        if method == "title" then
            return obj:gsub("(%a)([%w_']*)", function(first, rest)
                return first:upper() .. rest:lower()
            end)
        end
        if method == "slice" then
            local s = (args[1] or 0) + 1 -- 0-based to 1-based
            local e = args[2] and args[2] or #obj
            return obj:sub(s, e)
        end
        if method == "isEmpty" then
            return obj == ""
        end
        if method == "length" then
            return #obj
        end
    end

    -- ---- Number methods ----
    if type(obj) == "number" then
        if method == "abs" then
            return math.abs(obj)
        end
        if method == "ceil" then
            return math.ceil(obj)
        end
        if method == "floor" then
            return math.floor(obj)
        end
        if method == "round" then
            return math.floor(obj + 0.5)
        end
        if method == "toFixed" then
            local n = args[1] or 0
            return string.format("%." .. tostring(n) .. "f", obj)
        end
        if method == "isEmpty" then
            return false
        end
    end

    -- ---- Date methods ----
    if is_date_value(obj) then
        local epoch = obj.epoch
        if method == "format" then
            local fmt = args[1] or "%Y-%m-%d"
            return os.date(fmt, epoch)
        end
        if method == "date" then
            return os.date("%Y-%m-%d", epoch)
        end
        if method == "time" then
            return os.date("%H:%M:%S", epoch)
        end
        if method == "relative" then
            local diff = os.time() - epoch
            local abs_diff = math.abs(diff)
            if abs_diff < 60 then
                return "just now"
            elseif abs_diff < 3600 then
                return math.floor(abs_diff / 60) .. " minutes ago"
            elseif abs_diff < 86400 then
                return math.floor(abs_diff / 3600) .. " hours ago"
            else
                return math.floor(abs_diff / 86400) .. " days ago"
            end
        end
    end

    -- ---- List methods ----
    if type(obj) == "table" and not obj._type then
        if method == "contains" then
            local target = args[1]
            for _, v in ipairs(obj) do
                if v == target or (type(v) == "string" and type(target) == "string" and v:lower() == target:lower()) then
                    return true
                end
            end
            return false
        end
        if method == "containsAll" then
            for _, a in ipairs(args) do
                local found = false
                for _, v in ipairs(obj) do
                    if v == a or (type(v) == "string" and type(a) == "string" and v:lower() == a:lower()) then
                        found = true
                        break
                    end
                end
                if not found then
                    return false
                end
            end
            return true
        end
        if method == "containsAny" then
            for _, a in ipairs(args) do
                for _, v in ipairs(obj) do
                    if v == a or (type(v) == "string" and type(a) == "string" and v:lower() == a:lower()) then
                        return true
                    end
                end
            end
            return false
        end
        if method == "join" then
            local sep = args[1] or ", "
            local strs = {}
            for _, v in ipairs(obj) do
                strs[#strs + 1] = tostring(v)
            end
            return table.concat(strs, sep)
        end
        if method == "sort" then
            local copy = vim.deepcopy(obj)
            table.sort(copy, function(a, b)
                return tostring(a) < tostring(b)
            end)
            return copy
        end
        if method == "flat" then
            local result = {}
            local function flatten(tbl)
                for _, v in ipairs(tbl) do
                    if type(v) == "table" and not v._type then
                        flatten(v)
                    else
                        result[#result + 1] = v
                    end
                end
            end
            flatten(obj)
            return result
        end
        if method == "unique" then
            local seen = {}
            local result = {}
            for _, v in ipairs(obj) do
                local key = tostring(v)
                if not seen[key] then
                    seen[key] = true
                    result[#result + 1] = v
                end
            end
            return result
        end
        if method == "reverse" then
            local result = {}
            for i = #obj, 1, -1 do
                result[#result + 1] = obj[i]
            end
            return result
        end
        if method == "slice" then
            local s = (args[1] or 0) + 1
            local e = args[2] or #obj
            local result = {}
            for i = s, e do
                if obj[i] then
                    result[#result + 1] = obj[i]
                end
            end
            return result
        end
        if method == "length" then
            return #obj
        end
        if method == "isEmpty" then
            return #obj == 0
        end
    end

    -- ---- Object methods ----
    if type(obj) == "table" then
        if method == "isEmpty" then
            return next(obj) == nil
        end
        if method == "keys" then
            return vim.tbl_keys(obj)
        end
        if method == "values" then
            return vim.tbl_values(obj)
        end
        if method == "linksTo" then
            -- For wikilink objects
            local target = args[1]
            if not target then
                return false
            end
            if obj.data and obj.data.stem then
                return obj.data.stem:lower() == target:lower()
            end
            return false
        end
    end

    error(string.format(
        "Unknown method '%s' on value of type %s",
        method, type(obj)
    ))
end


--- Evaluate a global function call.
--- @param name string
--- @param args any[]
--- @param ctx vault.bases.EvalContext
--- @return any
local function eval_global_function(name, args, ctx)
    if name == "date" then
        local s = args[1]
        if not s then
            return make_date(os.time())
        end
        local epoch = parse_date_string(tostring(s))
        if epoch then
            return make_date(epoch)
        end
        return make_date(os.time())
    end

    if name == "today" then
        local t = os.time({
            year = tonumber(os.date("%Y")),
            month = tonumber(os.date("%m")),
            day = tonumber(os.date("%d")),
            hour = 0,
            min = 0,
            sec = 0,
        })
        return make_date(t)
    end

    if name == "now" then
        return make_date(os.time())
    end

    if name == "duration" then
        local s = args[1] or "0s"
        return { _type = "duration", seconds = parse_duration(tostring(s)) }
    end

    if name == "number" then
        return tonumber(args[1]) or 0
    end

    if name == "list" then
        return args
    end

    if name == "link" then
        local target = args[1] or ""
        local display = args[2]
        if display then
            return "[[" .. tostring(target) .. "|" .. tostring(display) .. "]]"
        end
        return "[[" .. tostring(target) .. "]]"
    end

    if name == "image" then
        return "![](" .. tostring(args[1] or "") .. ")"
    end

    if name == "max" then
        local result = nil
        for _, v in ipairs(args) do
            local n = tonumber(v)
            if n and (result == nil or n > result) then
                result = n
            end
        end
        return result or 0
    end

    if name == "min" then
        local result = nil
        for _, v in ipairs(args) do
            local n = tonumber(v)
            if n and (result == nil or n < result) then
                result = n
            end
        end
        return result or 0
    end

    -- if(condition, then_value, else_value)
    if name == "if" then
        local condition = args[1]
        local then_val = args[2]
        local else_val = args[3]
        -- Truthy check: non-nil, non-false, non-empty-string, non-0
        local is_truthy = condition ~= nil
            and condition ~= false
            and condition ~= ""
            and condition ~= 0
        if is_truthy then
            return then_val
        else
            return else_val
        end
    end

    error("Unknown function: " .. tostring(name))
end


--- Evaluate an AST node in the given context.
--- @param node table AST node
--- @param ctx vault.bases.EvalContext
--- @return any
eval_node = function(node, ctx)
    if node.type == "literal" then
        return node.value
    end

    if node.type == "identifier" then
        return resolve_identifier(node.name, ctx)
    end

    if node.type == "member_access" then
        local obj = eval_node(node.object, ctx)

        -- Handle file_ref member access
        if type(obj) == "table" and obj._type == "file_ref" then
            local val = resolve_file_member(obj, node.member)
            -- Check for date properties
            if is_date_value(val) then
                return val
            end
            -- Return date property shortcuts
            if node.member == "year" or node.member == "month" or node.member == "day"
                or node.member == "hour" or node.member == "minute" or node.member == "second" then
                if is_date_value(obj) then
                    return tonumber(os.date("%" .. ({ year = "Y", month = "m", day = "d", hour = "H", minute = "M", second = "S" })[node.member], obj.epoch))
                end
            end
            return val
        end

        -- Handle date member access (.year, .month, .day, etc.)
        if is_date_value(obj) then
            local date_members = {
                year = "%Y", month = "%m", day = "%d",
                hour = "%H", minute = "%M", second = "%S",
            }
            if date_members[node.member] then
                return tonumber(os.date(date_members[node.member], obj.epoch))
            end
        end

        -- Handle string .length as property (not method)
        if type(obj) == "string" and node.member == "length" then
            return #obj
        end

        -- Handle table .length as property
        if type(obj) == "table" and not obj._type and node.member == "length" then
            return #obj
        end

        -- Generic table member access
        if type(obj) == "table" then
            return obj[node.member]
        end

        return nil
    end

    if node.type == "method_call" then
        local obj = eval_node(node.object, ctx)
        local eval_args = {}
        for _, arg_node in ipairs(node.args) do
            eval_args[#eval_args + 1] = eval_node(arg_node, ctx)
        end
        return eval_method(obj, node.method, eval_args, ctx)
    end

    if node.type == "function_call" then
        -- Evaluate args lazily for if() — but since we've already parsed the AST,
        -- we need to evaluate all args. The if() function handles truthy check.
        local eval_args = {}
        for _, arg_node in ipairs(node.args) do
            eval_args[#eval_args + 1] = eval_node(arg_node, ctx)
        end
        return eval_global_function(node.name, eval_args, ctx)
    end

    if node.type == "unary" then
        local operand = eval_node(node.operand, ctx)
        if node.op == "!" then
            return not operand
        end
        if node.op == "-" then
            return -(tonumber(operand) or 0)
        end
    end

    if node.type == "binary" then
        local left = eval_node(node.left, ctx)
        local right = eval_node(node.right, ctx)

        -- Logical operators
        if node.op == "&&" then
            return left and right
        end
        if node.op == "||" then
            return left or right
        end

        -- Equality
        if node.op == "==" then
            if type(left) == "string" and type(right) == "string" then
                return left:lower() == right:lower()
            end
            return left == right
        end
        if node.op == "!=" then
            if type(left) == "string" and type(right) == "string" then
                return left:lower() ~= right:lower()
            end
            return left ~= right
        end

        -- Arithmetic + date arithmetic
        if node.op == "+" then
            -- Date + Duration
            if is_date_value(left) and type(right) == "table" and right._type == "duration" then
                return make_date(left.epoch + right.seconds)
            end
            if type(left) == "table" and left._type == "duration" and is_date_value(right) then
                return make_date(right.epoch + left.seconds)
            end
            -- String concatenation
            if type(left) == "string" or type(right) == "string" then
                return tostring(left) .. tostring(right)
            end
            return (tonumber(left) or 0) + (tonumber(right) or 0)
        end
        if node.op == "-" then
            -- Date - Duration
            if is_date_value(left) and type(right) == "table" and right._type == "duration" then
                return make_date(left.epoch - right.seconds)
            end
            -- Date - Date = seconds difference
            if is_date_value(left) and is_date_value(right) then
                return left.epoch - right.epoch
            end
            return (tonumber(left) or 0) - (tonumber(right) or 0)
        end
        if node.op == "*" then
            return (tonumber(left) or 0) * (tonumber(right) or 0)
        end
        if node.op == "/" then
            local r = tonumber(right) or 0
            if r == 0 then
                return 0
            end
            return (tonumber(left) or 0) / r
        end
        if node.op == "%" then
            local r = tonumber(right) or 0
            if r == 0 then
                return 0
            end
            return (tonumber(left) or 0) % r
        end

        -- Comparisons
        if node.op == ">" then
            if is_date_value(left) and is_date_value(right) then
                return left.epoch > right.epoch
            end
            return (tonumber(left) or 0) > (tonumber(right) or 0)
        end
        if node.op == "<" then
            if is_date_value(left) and is_date_value(right) then
                return left.epoch < right.epoch
            end
            return (tonumber(left) or 0) < (tonumber(right) or 0)
        end
        if node.op == ">=" then
            if is_date_value(left) and is_date_value(right) then
                return left.epoch >= right.epoch
            end
            return (tonumber(left) or 0) >= (tonumber(right) or 0)
        end
        if node.op == "<=" then
            if is_date_value(left) and is_date_value(right) then
                return left.epoch <= right.epoch
            end
            return (tonumber(left) or 0) <= (tonumber(right) or 0)
        end
    end

    return nil
end


-- ============================================================================
-- Public API
-- ============================================================================

--- Evaluate a single expression string against a note.
--- Used for both filter expressions and formula expressions.
---
--- @param expr string The expression string
--- @param note vault.Note The note to evaluate against
--- @return any The result of the expression
function M.evaluate_expression(expr, note)
    local ast = M.parse(expr)
    local ctx = build_context(note)
    return eval_node(ast, ctx)
end


--- Evaluate a filter tree (from .base YAML) against a note.
--- The filter tree uses and:/or:/not: combinators with string leaf expressions.
---
--- @param filter_tree table The parsed filter structure
--- @param note vault.Note The note to test
--- @return boolean Whether the note matches the filter
function M.evaluate_filter(filter_tree, note)
    if filter_tree == nil then
        return true
    end

    -- String leaf: evaluate as boolean expression
    if type(filter_tree) == "string" then
        local ok, result = pcall(M.evaluate_expression, filter_tree, note)
        if not ok then
            return false
        end
        -- Truthy: non-nil, non-false
        return result ~= nil and result ~= false
    end

    -- Table with combinators
    if type(filter_tree) == "table" then
        -- and: — all children must match
        if filter_tree["and"] then
            local children = filter_tree["and"]
            if type(children) ~= "table" then
                return true
            end
            for _, child in ipairs(children) do
                if not M.evaluate_filter(child, note) then
                    return false
                end
            end
            return true
        end

        -- or: — any child must match
        if filter_tree["or"] then
            local children = filter_tree["or"]
            if type(children) ~= "table" then
                return true
            end
            for _, child in ipairs(children) do
                if M.evaluate_filter(child, note) then
                    return true
                end
            end
            return false
        end

        -- not: — negate children (treat as implicit and, then negate)
        if filter_tree["not"] then
            local children = filter_tree["not"]
            if type(children) ~= "table" then
                return true
            end
            for _, child in ipairs(children) do
                if M.evaluate_filter(child, note) then
                    return false
                end
            end
            return true
        end

        -- Array of filters (implicit and)
        if #filter_tree > 0 then
            for _, child in ipairs(filter_tree) do
                if not M.evaluate_filter(child, note) then
                    return false
                end
            end
            return true
        end
    end

    return true
end


return M
