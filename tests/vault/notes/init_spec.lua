vim.opt.runtimepath:append(vim.fn.getcwd() .. "/**")
vim.opt.runtimepath:append(vim.fn.getenv("HOME") .. "/.local/share/nvim/lazy/**")
local assert = require("luassert")
local Notes = require("vault.notes")

--- @param note vault.Note
--- @param key vault.Note.Data._key
local function has_key(note, key)
    local note_data = note.data
    if note_data[key] then
        return true
    end
    return false
end

describe("VaultNotes", function()
    it("should return", function()
        assert(Notes():with_outlinks_resolved_only().map)
    end)
end)

describe("VaultNotes:init()", function()
    local notes = Notes()
    it("should return a `VaultNotes` object", function()
        assert.is_true(notes.class.name == "VaultNotes")
    end)

    it("should return have more than 0 notes in notes.map", function()
        assert.is_true(notes:count() == #vim.tbl_keys(notes.map))
    end)

    it("should return a vault.Note object", function()
        --- @type vault.Note
        local note = vim.tbl_values(notes.map)[1]
        assert.is_true(note.class.name == "VaultNote")
    end)
    --TODO: describe("VaultNotes:init(<with filter_opts>)
end)

describe("VaultNotes:to_group", function()
    local notes = Notes()
    it("should return a `VaultNotesGroup` object", function()
        local notes_group = notes:to_group()
        assert.is_true("VaultNotesGroup" == notes_group.class.name)
    end)

    it("should have less notes than the `VaultNotes` object", function()
        local orphans = Notes():orphans()
        assert.is_true(orphans:count() < Notes():count())
    end)
end)

describe("VaultNotes:to_cluster", function()
    it("should return a `VaultNotesCluster` object", function()
        local note_with_wikilinks = Notes():linked():get_random_note()
        local notes = Notes():to_cluster(note_with_wikilinks, 0)
        assert.is_true("VaultNotesCluster" == notes.class.name)
    end)
end)

describe("VaultNotes:wikilinks()", function()
    it("should return a `VaultNotesGroup` object", function()
        local notes = Notes():wikilinks()
        assert.is_true(notes.class.name == "VaultWikilinks")
    end)
end)

describe("VaultNotes:list()", function()
    it("should return a list of vault.Note objects", function()
        local notes = Notes()
        local notes_list = notes:list()
        for i, note in pairs(notes_list) do
            assert.is_true(type(i) == "number")
            assert.is_true(note.class.name == "VaultNote")
        end
    end)
end)

describe("VaultNotes:values_map_with_key()", function()
    it("should return a map of values with key", function()
        local stems = Notes():values_map_by_key("stem")
        local random_note = Notes():get_random_note() or error("No notes found")
        assert.is_true(stems[random_note.data.stem] ~= nil)
    end)
end)

describe("VaultNotes:count()", function()
    local notes = Notes()
    it("should return a count notes in notes.map", function()
        assert.is_true(notes:count() == #vim.tbl_keys(notes.map))
    end)
end)

describe("VaultNotes:average_chars()", function()
    local notes = Notes()
    it("should return a number", function()
        local average_content_count = notes:average_content_chars()
        assert.is_true(type(average_content_count) == "number")
    end)

    it("should return a number greater than 0", function()
        local average_content_count = notes:average_content_chars()
        assert.is_true(average_content_count > 0)
    end)
end)

-- describe("VaultNotes:duplicates()", function()
--     print("TODO: Figure out how to test this")
-- end)

describe("VaultNotes:get_random_note()", function()
    local notes = Notes()
    it("should return random `VaultNote` object from `VaultNotes`", function()
        --- @type vault.Note
        local note = notes:get_random_note()
        assert.is_true(note.class.name == "VaultNote")
    end)
end)

describe("VaultNotes:has_note()", function()
    it(
        "should return true if `VaultNotes` has `VaultNote` note with `exact` `VaultNote.data.stem`",
        function()
            local notes = Notes()
            local random_note = notes:get_random_note()
            local key = "stem"
            local query = random_note.data.stem
            local match_opt = "exact"
            local case_sensitive = false
            assert.is_true(notes:has_note(key, query, match_opt, case_sensitive))
        end
    )
    it(
        "should return true if `VaultNotes` has `VaultNote` note with `startswith` `VaultNote.data.stem`",
        function()
            local notes = Notes()
            local random_note = notes:get_random_note()
            local stem = random_note.data.stem
            local stem_length = #stem
            local key = "stem"
            local query = random_note.data.stem:sub(1, math.floor(stem_length / 2))
            local match_opt = "startswith"
            local case_sensitive = false
            assert.is_true(notes:has_note(key, query, match_opt, case_sensitive))
        end
    )
end)

-- TODO: Figure out how to test this.
-- describe("VaultNotes:add_note()", function()
--     it("should add a `VaultNote` to notes.map", function()
--         print("TODO: Figure out how to test this")
--     end)
-- end)

describe("VaultNotes:fetch_note_by()", function()
    it("should return a `VaultNote` with `exact` `VaultNote.data.stem`", function()
        local notes = Notes()
        local random_note = notes:get_random_note()
        local key = "stem"
        local query = random_note.data.stem
        local match_opt = "exact"
        local case_sensitive = false
        local note = notes:fetch_note_by(key, query, match_opt, case_sensitive)
        if note == nil then
            error("note is nil")
        end
        assert.is_true(note.class.name == "VaultNote")
    end)
end)

describe("VaultNotes:fetch_note_by_slug()", function()
    it("should return a `VaultNote` with `exact` `VaultNote.data.slug`", function()
        local notes = Notes()
        local random_note = notes:get_random_note()
        local query = random_note.data.slug
        local match_opt = "exact"
        local case_sensitive = false
        local note = notes:fetch_note_by_slug(query, match_opt, case_sensitive)
        if note == nil then
            error("note is nil")
        end
        assert.is_true(note.class.name == "VaultNote")
        assert.is_true(notes.map[note.data.slug] == note)
    end)
end)

describe("VaultNotes:fetch_note_by_path()", function()
    it("should return a `VaultNote` with `exact` `VaultNote.data.path`", function()
        local notes = Notes()
        local random_note = notes:get_random_note()
        local query = random_note.data.path
        local match_opt = "exact"
        local case_sensitive = false
        local note = notes:fetch_note_by_path(query, match_opt, case_sensitive)
        if note == nil then
            error("note is nil")
        end
        assert.is_true(note.class.name == "VaultNote")
    end)
end)

describe("VaultNotes:fetch_note_by_relpath()", function()
    it("should return a `VaultNote` with `exact` `string`", function()
        local notes = Notes()
        local random_note = notes:get_random_note()
        local query = random_note.data.relpath
        local match_opt = "exact"
        local case_sensitive = false
        local note = notes:fetch_note_by_relpath(query, match_opt, case_sensitive)
        if note == nil then
            error("note is nil")
        end
        assert.is_true(note.class.name == "VaultNote")
    end)
end)

describe("VaultNotes:filter()", function()
    it("should return a `VaultNotesGroup` object", function()
        local notes = Notes():filter({
            {
                search_term = "tags",
                include = { "status" },
                exclude = {},
                match_opt = "startswith",
                mode = "any",
            },
        })
        assert.is_true(notes.class.name == "VaultNotesGroup")
    end)
    it(
        "should return a `VaultNotesGroup` object with `VaultNote.data.tags` that startswith `status` tag",
        function()
            local notes = Notes():filter({
                {
                    search_term = "tags",
                    include = { "status" },
                    exclude = {},
                    match_opt = "startswith",
                    mode = "any",
                },
            })
            for _, note in pairs(notes.map) do
                local tags = note.data.tags
                for tag_name, tag in pairs(tags) do
                    assert.is_true(vim.startswith(tag_name, "status"))
                end
            end
        end
    )
    it("should return a `VaultNotesGroup` without tags that startswith `status` tag", function()
        local notes = Notes():filter({
            {
                search_term = "tags",
                exclude = { "status" },
                match_opt = "startswith",
                mode = "any",
            },
        })
        for _, note in pairs(notes.map) do
            local tags = note.data.tags
            for tag_name, tag in pairs(tags) do
                assert.is_false(vim.startswith(tag_name, "status"))
            end
        end
    end)
    it("should return a less `VaultNotesGroup` object than `VaultNotes`", function()
        local notes = Notes():filter({
            {
                search_term = "tags",
                include = { "status" },
                exclude = {},
                match_opt = "startswith",
                mode = "any",
            },
        })
        assert.is_true(notes:count() < Notes():count())
    end)

    --TODO: Add more tests.
end)

describe("VaultNotes:with_key(<VaulNote.data[key]>)", function()
    it(
        "should return a `VaultNotesGroup` object where `VaultNote.data.frontmatter` exists",
        function()
            local notes = Notes():with_key("frontmatter")
            for _, note in pairs(notes.map) do
                assert.is_true(note.data.frontmatter ~= nil)
            end
            assert.is_true(notes.class.name == "VaultNotesGroup")
        end
    )
    it(
        "should return a `VaultNotesGroup` object where `VaultNote.data.frontmatter.data` not empty",
        function()
            local notes = Notes():with_key("frontmatter")
            for _, note in pairs(notes.map) do
                assert.is_true(note.data.frontmatter.data ~= nil)
            end
            assert.is_true(notes.class.name == "VaultNotesGroup")
        end
    )
    --TODO: Add more tests.
end)

describe("VaultNotes:with()", function()
    it(
        "should return a `VaultNotesGroup` object with `VaultNote.data.stem` that starts with `20`",
        function()
            local notes = Notes():with("stem", "20", "startswith", false)
            for _, note in pairs(notes.map) do
                local stem = note.data.stem
                assert.is_true(stem:find("20") ~= nil)
            end
        end
    )
end)

describe("VaultNotes:with_slug()", function()
    it(
        "should return a `VaultNotesGroup` object with `VaultNote.data.slug` that starts with",
        function()
            local notes = Notes()
            local note = notes:get_random_note()
            local slug = note.data.slug
            local slug_char_count = string.len(slug)
            local query = slug:sub(1, math.floor(slug_char_count - 2))
            local notes_with_slugs = Notes():with_slug(query, "startswith", false)
            for _, note_with_slug in pairs(notes_with_slugs.map) do
                slug = note_with_slug.data.slug
                if slug:find(query) == nil then
                    -- compare with slug
                    print("note slug: " .. slug)
                    print("query: " .. query)
                    print("note_with_slug slug: " .. note_with_slug.data.slug)
                end
                assert.is_true(slug:find(query) ~= nil)
            end
        end
    )
end)

describe("VaultNotes:with_path()", function()
    it(
        "should return a `VaultNotesGroup` object with `VaultNote.data.path` that starts with",
        function()
            local notes = Notes()
            local note = notes:get_random_note()
            local path = note.data.path
            local path_char_count = #path
            local query = path:sub(1, math.floor(path_char_count / 2))
            local notes_with_path = Notes():with_path(query, "startswith", false)
            for _, note_with_path in pairs(notes_with_path.map) do
                path = note_with_path.data.path
                if path:find(query) == nil then
                    -- compare with path
                    print("note path: " .. path)
                    print("query: " .. query)
                    print("note_with_path path: " .. note_with_path.data.path)
                end
                assert.is_true(path:find(query) ~= nil)
            end
        end
    )
end)

describe("VaultNotes:with_relpath()", function()
    it("should return a `VaultNotesGroup` object with `string` that starts with", function()
        local notes = Notes()
        local note = notes:get_random_note()
        local relpath = note.data.relpath
        local relpath_char_count = #relpath
        local query = relpath:sub(1, math.floor(relpath_char_count / 2))
        local notes_with_relpath = Notes():with_relpath(query, "startswith", false)
        for _, note_with_relpath in pairs(notes_with_relpath.map) do
            relpath = note_with_relpath.data.relpath
            assert.is_true(relpath:find(query) ~= nil)
        end
    end)
end)

describe("VaultNotes:with_basename()", function()
    it(
        "should return a `VaultNotesGroup` object with `VaultNote.data.basename` that starts with",
        function()
            local notes = Notes()
            local note = notes:get_random_note()
            local basename = note.data.basename
            local basename_char_count = #basename
            local query = basename:sub(1, math.floor(basename_char_count / 2))
            local notes_with_basename = Notes():with_basename(query, "startswith", false)
            for _, note_with_basename in pairs(notes_with_basename.map) do
                basename = note_with_basename.data.basename
                assert.is_true(basename:find(query) ~= nil)
            end
        end
    )
end)

describe("VaultNotes:with_stem()", function()
    it(
        "should return a `VaultNotesGroup` object with `VaultNote.data.stem` that starts with",
        function()
            local notes = Notes()
            local note = nil
            while note == nil do
                note = notes:get_random_note()
                if note.data.stem == nil or note.data.stem == "" then
                    note = nil
                end
                if note and note.data.stem:len() < 3 then
                    note = nil
                end
            end
            local stem = note.data.stem
            local stem_char_count = stem:len()
            local query = stem:sub(1, math.floor(stem_char_count - 2))
            --- @type vault.Notes.Group
            local notes_with_stem = Notes():with_stem(query, "startswith", false)
            if notes_with_stem:count() == 0 then
                error("notes_with_stem:count() == 0")
            end
            for _, note_with_stem in pairs(notes_with_stem.map) do
                assert.is_true(vim.startswith(note_with_stem.data.stem, query))
            end
        end
    )
end)

describe("VaultNotes:with_title()", function()
    it(
        "should return a `VaultNotesGroup` object with `VaultNote.data.title` that starts with",
        function()
            local notes = Notes()
            local note = nil
            while note == nil do
                note = notes:get_random_note()
                if note.data.title == nil or note.data.title == "" then
                    note = nil
                end
            end
            local title = note.data.title
            local title_char_count = #title
            local query = title:sub(1, math.floor(title_char_count / 2))
            local notes = Notes():with_title(query, "startswith", false)
            for _, note in pairs(notes.map) do
                local title = note.data.title
                assert.is_true(title:find("^" .. query) ~= nil)
            end
        end
    )
end)

describe("VaultNotes:with_content()", function()
    it(
        "should return a `VaultNotesGroup` object with `VaultNote.data.content` that starts with",
        function()
            local notes = Notes()
            local note = nil
            while note == nil do
                note = notes:get_random_note()
                if note.data.content == nil or note.data.content == "" then
                    note = nil
                end
                if note and note.data.content:len() < 6 then
                    note = nil
                end
            end
            local content = note.data.content
            local content_char_count = content:len()
            local query = content:sub(1, math.floor(content_char_count / 2))
            local notes_with_content = Notes():with_content(query, "startswith", false)
            for _, note_with_content in pairs(notes_with_content.map) do
                assert.is_true(vim.startswith(note_with_content.data.content, query))
            end
        end
    )
end)

describe("VaultNotes:with_frontmatter()", function()
    it(
        "should return a `VaultNotesGroup` object with `VaultNote.data.frontmatter` that starts with",
        function()
            local notes = Notes()
            local note = nil
            while note == nil do
                note = notes:get_random_note()
                if note.data.frontmatter == nil then
                    note = nil
                end
            end
            local frontmatter = note.data.frontmatter
            print(vim.inspect(frontmatter))
        end
    )
end)

describe("VaultNotes:with_body()", function()
    it(
        "should return a `VaultNotesGroup` object with `VaultNote.data.body` that starts with",
        function()
            local notes = Notes()
            local note = nil
            while note == nil do
                note = notes:get_random_note()
                if note.data.body == nil then
                    note = nil
                end
                if note and note.data.body:len() < 6 then
                    note = nil
                end
                if note and note.data.content ~= note.data.body then
                    note = nil
                end
            end
            local body = note.data.body
            local body_char_count = body:len()
            local query = body:sub(1, math.floor(body_char_count / 2))
            local notes_with_body = Notes():with_body(query, "startswith", false)
            for _, note_with_body in pairs(notes_with_body.map) do
                assert.is_true(vim.startswith(note_with_body.data.body, query))
            end
        end
    )
end)

-- TODO: Figure out how to test this.
describe("VaultNotes:filter_by_tags()", function()
    it(
        "should return a `VaultNotesGroup` object with `VaultNote.data.tags` that starts with",
        function()
            local notes = Notes()
            local note = nil
            while note == nil do
                note = notes:get_random_note()
                if next(note.data.tags) == nil then
                    note = nil
                end
            end
            local note_tags = note.data.tags
            --- @type vault.Tag
            local tag = vim.tbl_values(note_tags)[1]
            local tag_name = tag.data.name
            local tag_name_char_count = tag_name:len()
            local query = tag_name:sub(1, math.floor(tag_name_char_count - 1))
            local notes_with_tags = Notes():filter_by_tags({
                include = { query },
                exclude = {},
                match_opt = "startswith",
                mode = "any",
            })
            for _, note_with_tag in pairs(notes_with_tags.map) do
                local tags = note_with_tag.data.tags
                assert.is_true(tags[query] ~= nil)
            end
        end
    )

    --FIXME: That not filters.
    it(
        "should return a filtered `VaultNotes` object with tags that startswith `status` tag",
        function()
            local notes = Notes():filter_by_tags({
                include = { "status" },
                exclude = {},
                match_opt = "startswith",
                mode = "any",
            })

            local function has_tag_with_root(note, root)
                local tags = note.data.tags
                for _, tag in pairs(tags) do
                    if tag.data.root == root then
                        return true
                    end
                end
                return false
            end

            for _, note in pairs(notes.map) do
                assert.is_true(has_tag_with_root(note, "status"))
            end
        end
    )
end)

describe("VaultNotes:linked()", function()
    local notes = Notes():linked()
    it("should return a `VaultNotesGroup` object", function()
        --- @diagnostic disable-next-line: undefined-field
        assert.is_true(notes.class.name == "VaultNotesGroup")
    end)

    it("should return less notes than the `VaultNotes` object has", function()
        assert.is_true(notes:count() < Notes():count())
    end)

    it("should return a `VaultNote` object", function()
        --- @type vault.Note
        local note = vim.tbl_values(notes.map)[1]
        assert.is_true(note.class.name == "VaultNote")
    end)

    it(
        "should return a `VaultNote` objects that have `VaultNote.data.outlinks` or `VaultNote.data.inlinks`",
        function()
            for _, note in pairs(notes.map) do
                if next(note.data.outlinks) == nil and next(note.data.inlinks) == nil then
                    print(vim.inspect(note))
                end

                assert.is_true(next(note.data.outlinks) ~= nil or next(note.data.inlinks) ~= nil)
            end
        end
    )
end)

describe("VaultNotes:internals()", function()
    local notes = Notes():internals()
    it("should return a `VaultNotesGroup` object", function()
        --- @diagnostic disable-next-line: undefined-field
        assert.is_true(notes.class.name == "VaultNotesGroup")
    end)

    it("should return less notes than the `VaultNotes` object has", function()
        assert.is_true(notes:count() < Notes():count())
    end)

    it("should return a `VaultNote` object", function()
        --- @type vault.Note
        local note = notes:get_random_note()
        assert.is_true(note.class.name == "VaultNote")
    end)

    it(
        "should return a `VaultNote` objects that have `VaultNote.data.outlinks` AND `VaultNote.data.inlinks`",
        function()
            for _, note in pairs(notes.map) do
                if next(note.data.outlinks) == nil and next(note.data.inlinks) == nil then
                    print(vim.inspect(note))
                end

                assert.is_true(next(note.data.outlinks) ~= nil and next(note.data.inlinks) ~= nil)
            end
        end
    )
end)

describe("VaultNotes:leaves()", function()
    local notes = Notes():leaves()
    it("should return a `VaultNotesGroup` object", function()
        --- @diagnostic disable-next-line: undefined-field
        assert.is_true(notes:is_instance_of(Notes))
    end)

    it("should return less notes than the `VaultNotes` object has", function()
        assert.is_true(notes:count() < Notes():count())
    end)

    it("should return a `VaultNote` object", function()
        print(vim.inspect(notes))
        --- @type vault.Note
        local note = vim.tbl_values(notes.map)[1]
        if note.class.name ~= "VaultNote" then
            print(vim.inspect(notes))
        end
        assert.is_true(note.class.name == "VaultNote")
    end)

    it(
        "should NOT return a `VaultNote` objects with greater than 0 `VaultNote.data.outlinks`",
        function()
            for _, note in pairs(notes.map) do
                assert.is_false(has_key(note))
            end
        end
    )

    it(
        "should return a `VaultNote` objects with greater than 0 `VaultNote.data.inlinks`",
        function()
            --TODO: Try when `VaultNote.data.inlinks` is implemented.
            for _, note in pairs(notes.map) do
                assert.is_true(has_key(note))
            end
        end
    )
end)

describe("VaultNotes:orphans()", function()
    --- @type vault.Notes.Group
    local notes = Notes():orphans()

    it("should return a `VaultNotesGroup` object", function()
        assert.is_true(notes.class.name == "VaultNotesGroup")
    end)

    it("should return a count of notes.map", function()
        assert.is_true(notes:count() == #vim.tbl_keys(notes.map))
    end)

    it("should return a `VaultNote` object", function()
        local notes_map = notes.map
        --- @type vault.Note
        local note = vim.tbl_values(notes_map)[1]
        assert.is_true("VaultNote" == note.class.name)
    end)

    it("should NOT return a VaultNote objects with empty `VaultNote.data.outlinks`", function()
        local notes_map = notes.map
        for _, note in pairs(notes_map) do
            local outlinks = note.data.outlinks
            if next(outlinks) then
                print(vim.inspect(note.data.outlinks))
            end
            assert.is_true(note.data.outlinks[1] == nil)
        end
    end)

    -- TODO: Waiting for implementation.
    --[[
    it("should NOT return a VaultNote object with `VaultNote.data.inlinks`", function()
        local notes_map = notes.map
        for _, note in pairs(notes_map) do
            if next(note.data.inlinks) == nil then
                print(vim.inspect(note))
            end
            assert.is_true(note.data.inlinks[1] ~= nil)
        end
    end)
    ]]
    --
end)

--FIXME: Figure out how to test this.
describe("VaultNotes:with_outlinks_resolved_only", function()
    it("should return less notes than the `VaultNotes` object", function()
        --- @type vault.Notes.Group
        local notes = Notes():with_outlinks_resolved_only()
        assert.is_true(notes:count() < Notes():count())
    end)

    it("should return notes that have more than 0 `VaultNote.data.outlinks`", function()
        local notes = Notes():with_outlinks_resolved_only()
        for _, note in pairs(notes.map) do
            local outlinks = note.data.outlinks
            if next(outlinks) == nil then
                print(vim.inspect(note))
            end
            assert.is_true(next(outlinks) ~= nil)
        end
    end)

    it("should return notes that have `VaultNote.data.outlinks` with `target`", function()
        local notes = Notes()
        local notes_with_resolved_links_only = Notes():with_outlinks_resolved_only()

        --- @param note vault.Note
        local function has_resolved_links_only(note)
            local outlinks = note.data.outlinks
            for stem, outlink in pairs(outlinks) do
                if outlink.target then
                    return true
                end
            end
            return false
        end

        for _, note in pairs(notes_with_resolved_links_only.map) do
            assert.is_true(has_resolved_links_only(note))
        end
    end)
end)

--FIXME: Figure out how to test this.
describe("VaultNotes:with_outlinks_unresolved", function()
    it("should return notes that do NOT have `VaultNote.data.outlinks` with `target`", function()
        local notes = Notes():with_outlinks_unresolved()

        local function has_unresolved_links(note)
            local outlinks = note.data.outlinks
            local is_outlink_unresolved_exists = false
            for _, outlink in pairs(outlinks) do
                if not outlink.target then
                    is_outlink_unresolved_exists = true
                    break
                end
            end
            return is_outlink_unresolved_exists
        end

        for _, note in pairs(notes.map) do
            assert.is_true(has_unresolved_links(note))
        end
    end)
end)

describe("VaultNotes:reset()", function()
    it("should reset notes.map", function()
        local notes = Notes()
        local init_length = notes:count()
        assert.is_true(init_length > 0)
        -- delete half notes from notes.map
        -- TODO: Figure out how to test this.
        local list = notes:list()
        local half_length = math.floor(init_length / 2)
        local new_map = {}
        for i = 1, half_length do
            local slug = list[i].data.slug
            new_map[slug] = list[i]
        end
        notes.map = new_map
        assert.is_true(notes:count() == half_length)
        notes:reset()
        assert.is_true(notes:count() == init_length)
    end)
end)
