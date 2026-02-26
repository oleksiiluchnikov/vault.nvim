--- @module "busted"
vim.opt.runtimepath:append(vim.fn.getcwd() .. "/**")
vim.opt.runtimepath:append(vim.fn.getenv("HOME") .. "/.local/share/nvim/lazy/**")

local assert = require("luassert")
local evaluator = require("vault.bases.evaluator")

-- ============================================================================
-- Tokenizer / Parser
-- ============================================================================

describe("evaluator.parse()", function()
    it("should parse a simple number literal", function()
        local ast = evaluator.parse("42")
        assert.is_not_nil(ast)
        assert.are.equal("literal", ast.type)
        assert.are.equal(42, ast.value)
    end)

    it("should parse a simple string literal", function()
        local ast = evaluator.parse('"hello"')
        assert.is_not_nil(ast)
        assert.are.equal("literal", ast.type)
        assert.are.equal("hello", ast.value)
    end)

    it("should parse a boolean literal", function()
        local ast = evaluator.parse("true")
        assert.is_not_nil(ast)
        assert.are.equal("literal", ast.type)
        assert.are.equal(true, ast.value)
    end)

    it("should parse a simple identifier", function()
        local ast = evaluator.parse("status")
        assert.is_not_nil(ast)
        assert.are.equal("identifier", ast.type)
        assert.are.equal("status", ast.name)
    end)

    it("should parse a member access (file.name)", function()
        local ast = evaluator.parse("file.name")
        assert.is_not_nil(ast)
        assert.are.equal("member_access", ast.type)
    end)

    it("should parse a function call (file.hasTag(\"project\"))", function()
        local ast = evaluator.parse('file.hasTag("project")')
        assert.is_not_nil(ast)
        -- Should be a method_call on file
        assert.is_true(ast.type == "method_call" or ast.type == "function_call")
    end)

    it("should parse a binary expression (a == b)", function()
        local ast = evaluator.parse('status == "active"')
        assert.is_not_nil(ast)
        assert.are.equal("binary", ast.type)
        assert.are.equal("==", ast.op)
    end)

    it("should parse a unary not expression", function()
        local ast = evaluator.parse("!true")
        assert.is_not_nil(ast)
        assert.are.equal("unary", ast.type)
    end)

    it("should parse nested function calls", function()
        local ast = evaluator.parse('file.name.contains("test")')
        assert.is_not_nil(ast)
    end)

    it("should parse an if() expression", function()
        local ast = evaluator.parse('if(status, status, "unknown")')
        assert.is_not_nil(ast)
        assert.is_true(ast.type == "function_call")
    end)

    it("should parse arithmetic expressions", function()
        local ast = evaluator.parse("1 + 2 * 3")
        assert.is_not_nil(ast)
        assert.are.equal("binary", ast.type)
    end)

    it("should parse logical expressions (&&, ||)", function()
        local ast = evaluator.parse("true && false || true")
        assert.is_not_nil(ast)
    end)
end)

-- ============================================================================
-- Expression Evaluation (standalone, no note context)
-- ============================================================================

describe("evaluator.evaluate_expression()", function()
    it("should evaluate a number literal", function()
        local result = evaluator.evaluate_expression("42", nil)
        assert.are.equal(42, result)
    end)

    it("should evaluate a string literal", function()
        local result = evaluator.evaluate_expression('"hello"', nil)
        assert.are.equal("hello", result)
    end)

    it("should evaluate boolean literals", function()
        assert.are.equal(true, evaluator.evaluate_expression("true", nil))
        assert.are.equal(false, evaluator.evaluate_expression("false", nil))
    end)

    it("should evaluate arithmetic: 1 + 2", function()
        local result = evaluator.evaluate_expression("1 + 2", nil)
        assert.are.equal(3, result)
    end)

    it("should evaluate arithmetic: 10 - 3 * 2", function()
        local result = evaluator.evaluate_expression("10 - 3 * 2", nil)
        assert.are.equal(4, result)
    end)

    it("should evaluate comparison: 5 > 3", function()
        local result = evaluator.evaluate_expression("5 > 3", nil)
        assert.are.equal(true, result)
    end)

    it("should evaluate equality: 1 == 1", function()
        local result = evaluator.evaluate_expression("1 == 1", nil)
        assert.are.equal(true, result)
    end)

    it("should evaluate inequality: 1 != 2", function()
        local result = evaluator.evaluate_expression("1 != 2", nil)
        assert.are.equal(true, result)
    end)

    it("should evaluate logical and: true && false", function()
        local result = evaluator.evaluate_expression("true && false", nil)
        assert.are.equal(false, result)
    end)

    it("should evaluate logical or: false || true", function()
        local result = evaluator.evaluate_expression("false || true", nil)
        assert.are.equal(true, result)
    end)

    it("should evaluate unary not: !false", function()
        local result = evaluator.evaluate_expression("!false", nil)
        assert.are.equal(true, result)
    end)

    it("should evaluate string concatenation: \"foo\" + \"bar\"", function()
        local result = evaluator.evaluate_expression('"foo" + "bar"', nil)
        assert.are.equal("foobar", result)
    end)

    it("should evaluate modulo: 10 % 3", function()
        local result = evaluator.evaluate_expression("10 % 3", nil)
        assert.are.equal(1, result)
    end)

    it("should evaluate max()", function()
        local result = evaluator.evaluate_expression("max(1, 5, 3)", nil)
        assert.are.equal(5, result)
    end)

    it("should evaluate min()", function()
        local result = evaluator.evaluate_expression("min(1, 5, 3)", nil)
        assert.are.equal(1, result)
    end)

    it("should evaluate number()", function()
        local result = evaluator.evaluate_expression('number("42")', nil)
        assert.are.equal(42, result)
    end)
end)

-- ============================================================================
-- String Methods
-- ============================================================================

describe("evaluator string methods", function()
    it("should evaluate .contains()", function()
        local result = evaluator.evaluate_expression('"hello world".contains("world")', nil)
        assert.are.equal(true, result)
    end)

    it("should evaluate .startsWith()", function()
        local result = evaluator.evaluate_expression('"hello".startsWith("he")', nil)
        assert.are.equal(true, result)
    end)

    it("should evaluate .endsWith()", function()
        local result = evaluator.evaluate_expression('"hello".endsWith("lo")', nil)
        assert.are.equal(true, result)
    end)

    it("should evaluate .lower()", function()
        local result = evaluator.evaluate_expression('"HELLO".lower()', nil)
        assert.are.equal("hello", result)
    end)

    it("should evaluate .upper()", function()
        local result = evaluator.evaluate_expression('"hello".upper()', nil)
        assert.are.equal("HELLO", result)
    end)

    it("should evaluate .trim()", function()
        local result = evaluator.evaluate_expression('"  hello  ".trim()', nil)
        assert.are.equal("hello", result)
    end)

    it("should evaluate .isEmpty() on empty string", function()
        local result = evaluator.evaluate_expression('"".isEmpty()', nil)
        assert.are.equal(true, result)
    end)

    it("should evaluate .isEmpty() on non-empty string", function()
        local result = evaluator.evaluate_expression('"hello".isEmpty()', nil)
        assert.are.equal(false, result)
    end)

    it("should evaluate .length on a string", function()
        local result = evaluator.evaluate_expression('"hello".length', nil)
        assert.are.equal(5, result)
    end)

    it("should evaluate .replace()", function()
        local result = evaluator.evaluate_expression('"foo bar".replace("bar", "baz")', nil)
        assert.are.equal("foo baz", result)
    end)
end)

-- ============================================================================
-- Filter Evaluation
-- ============================================================================

describe("evaluator.evaluate_filter()", function()
    -- A minimal mock note for filter testing
    local mock_note = {
        data = {
            path = "/vault/Project/test_note.md",
            relpath = "Project/test_note.md",
            slug = "Project/test_note",
            stem = "test_note",
            content = "some content",
            tags = {
                project = { data = { name = "project", sources = {} } },
                active = { data = { name = "active", sources = {} } },
            },
            frontmatter = {
                data = {
                    status = "active",
                    tags = { "project", "active" },
                },
            },
        },
    }

    it("should return true for empty filter tree", function()
        assert.is_true(evaluator.evaluate_filter({}, mock_note))
    end)

    it("should return true for nil filter tree", function()
        assert.is_true(evaluator.evaluate_filter(nil, mock_note))
    end)

    it("should evaluate a simple string expression as filter", function()
        -- A string filter like 'file.inFolder("Project")' should be truthy
        assert.is_true(evaluator.evaluate_filter('file.inFolder("Project")', mock_note))
    end)

    it("should evaluate and: combinator", function()
        local filter = {
            ["and"] = {
                'file.inFolder("Project")',
                'file.hasTag("project")',
            },
        }
        assert.is_true(evaluator.evaluate_filter(filter, mock_note))
    end)

    it("should fail and: if one condition fails", function()
        local filter = {
            ["and"] = {
                'file.inFolder("Nonexistent")',
                'file.hasTag("project")',
            },
        }
        assert.is_false(evaluator.evaluate_filter(filter, mock_note))
    end)

    it("should evaluate or: combinator", function()
        local filter = {
            ["or"] = {
                'file.inFolder("Nonexistent")',
                'file.hasTag("project")',
            },
        }
        assert.is_true(evaluator.evaluate_filter(filter, mock_note))
    end)

    it("should evaluate not: combinator", function()
        local filter = {
            ["not"] = {
                'file.inFolder("_docs")',
            },
        }
        -- mock note is in Project, not _docs, so not: should be true
        assert.is_true(evaluator.evaluate_filter(filter, mock_note))
    end)

    it("should evaluate nested and:/not: combinator", function()
        local filter = {
            ["and"] = {
                'status == "active"',
                {
                    ["not"] = {
                        'file.inFolder("_docs")',
                    },
                },
            },
        }
        assert.is_true(evaluator.evaluate_filter(filter, mock_note))
    end)
end)

-- ============================================================================
-- Global Functions
-- ============================================================================

describe("evaluator global functions", function()
    it("should evaluate if(true, a, b) => a", function()
        local result = evaluator.evaluate_expression('if(true, "yes", "no")', nil)
        assert.are.equal("yes", result)
    end)

    it("should evaluate if(false, a, b) => b", function()
        local result = evaluator.evaluate_expression('if(false, "yes", "no")', nil)
        assert.are.equal("no", result)
    end)

    it("should evaluate today() as a date table", function()
        local result = evaluator.evaluate_expression("today()", nil)
        assert.is_not_nil(result)
        assert.is_true(type(result) == "table")
        assert.are.equal("date", result._type)
        assert.is_true(type(result.epoch) == "number")
    end)

    it("should evaluate now() as a string", function()
        local result = evaluator.evaluate_expression("now()", nil)
        assert.is_not_nil(result)
    end)
end)
