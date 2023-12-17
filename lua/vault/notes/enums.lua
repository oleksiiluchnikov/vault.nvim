local enums = {}

---@alias VaultNotesFilterKey
---| '"stem"' - The stem of the note's path
---| '"basename"' - The basename of the note's path
---| '"title"' - The title of the note
---| '"tags"' - The tags of the note
---| '"content"' - The content of the note
---| '"frontmatter"' - The frontmatter of the note
---| '"body"' - The body of the note

---@enum VaultNotesFilterKeys
enums.filter_keys = {
    stem = 1,
    basename = 2,
    title = 3,
    tags = 4,
    content = 5,
    frontmatter = 6,
    body = 7,
}

return enums
