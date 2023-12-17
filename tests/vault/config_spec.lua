local assert = require("luassert")
local config = require("vault.config")

describe("config.dirs", function()
  it("should return a list of absolute pathes", function()
    --TODO: Check if the dirs are absolute pathes.
    -- local dirs = config.dirs
  end)
end)

describe("config.dirs", function()
  it("should return a list of ignore patterns", function()
    local ignore = config.ignore
    assert.is_true(type(ignore) == "table")
    for _, v in ipairs(ignore) do
      assert.is_true(type(v) == "string")
    end
    assert.is_false(next(ignore) == nil)
  end)
  --TODO: Check if the ignore patterns are are really ignored.
end)
