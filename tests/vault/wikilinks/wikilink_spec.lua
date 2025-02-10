--- @module "busted"
local assert = require("luassert")
local Wikilink = require("vault.wikilinks.wikilink")

describe("VaultWikilink", function()
    describe("parsing", function()
        local test_cases = {
            {
                input = "[[simple]]",
                expected = {
                    raw = "simple",
                    stem = "simple",
                    display = "simple",
                },
            },
            {
                input = "[[path/to/note]]",
                expected = {
                    raw = "path/to/note",
                    stem = "path/to/note",
                    display = "note",
                },
            },
            {
                input = "[[note#heading]]",
                expected = {
                    raw = "note#heading",
                    stem = "note",
                    display = "note",
                    heading = "heading",
                },
            },
            {
                input = "[[note|Custom Title]]",
                expected = {
                    raw = "note|Custom Title",
                    stem = "note",
                    display = "Custom Title",
                },
            },
            {
                input = "[[path/to/note#heading|Custom Title]]",
                expected = {
                    raw = "path/to/note#heading|Custom Title",
                    stem = "path/to/note",
                    display = "Custom Title",
                    heading = "heading",
                },
            },
            {
                input = "[[../relative/path]]",
                expected = {
                    raw = "../relative/path",
                    stem = "../relative/path",
                    display = "path",
                },
            },
        }

        for _, case in ipairs(test_cases) do
            it(string.format("should parse %s correctly", case.input), function()
                local wikilink = Wikilink(case.input)
                for key, value in pairs(case.expected) do
                    assert.are.equal(
                        value,
                        wikilink.data[key],
                        string.format(
                            "Expected %s to be %s but got %s",
                            key,
                            value,
                            wikilink.data[key]
                        )
                    )
                end
            end)
        end
    end)

    describe("content extraction", function()
        local text_with_links = [=[
            Some text with a [[basic]] link.
            A [[complex/path/note#section|Display Text]] link.
            Multiple [[link1]] [[link2]] links.
            [[link with spaces]]
            Not a ][ link
            Also not a [[incomplete link
        ]=]

        it("should extract all valid wikilinks from text", function()
            local expected_links = {
                "basic",
                "complex/path/note#section|Display Text",
                "link1",
                "link2",
                "link with spaces",
            }

            local wikilinks = Wikilink.extract_from_text(text_with_links)
            assert.are.equal(#expected_links, #wikilinks)

            for i, link in ipairs(wikilinks) do
                assert.are.equal(expected_links[i], link.data.raw)
            end
        end)
    end)

    describe("validation", function()
        it("should reject invalid wikilinks", function()
            local invalid_inputs = {
                "",
                "[[]]",
                "[[|]]",
                "[[#]]",
                "not a link",
                "[single bracket]",
                "[[unterminated",
                "extra]]brackets]]",
            }

            for _, input in ipairs(invalid_inputs) do
                assert.has_error(function()
                    Wikilink(input)
                end, "Invalid wikilink format")
            end
        end)
    end)

    describe("methods", function()
        it("should convert wikilink to string representation", function()
            local wikilink = Wikilink("[[test/note#section|Display]]")
            assert.are.equal("[[test/note#section|Display]]", tostring(wikilink))
        end)

        it("should check if wikilink is resolved", function()
            local wikilink = Wikilink("[[existing/note]]")
            -- Mock the resolution check based on your implementation
            assert.is_false(wikilink:is_resolved())
        end)

        it("should get parent path", function()
            local wikilink = Wikilink("[[parent/child/note]]")
            assert.are.equal("parent/child", wikilink:get_parent_path())
        end)
    end)
end)
