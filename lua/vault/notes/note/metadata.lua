local metadata = {}
--- @alias NoteMetadataKey
--- | "'relpath'" -- unique
--- | "'path'" -- unique
--- | "'slug'" -- unique
--- | "'basename'"
--- | "'stem'"
--- | "'title'"
--- | "'content'"
--- | "'lists'"
--- | "'frontmatter'"
--- | "'dangling_links'"
--- | "'body'"
--- | "'title'"
--- | "'tags'"
--- | "'inlinks'"
--- | "'outlinks'"
--- | "'type'"
--- | "'status'"

--- @alias VaultNotesMedataKey.unique
--- | "'relpath'" -- unique
--- | "'path'" -- unique


--- @alias VaultNotesSearchTerm NoteMetadataKey

--- @type table<NoteMetadataKey, boolean>
metadata.unique = {
    relpath = true,
    path = true,
}

--- @type table<NoteMetadataKey, boolean>
metadata.keys = {
    relpath = true,
    path = true,
    basename = true,
    stem = true,
    title = true,
    content = true,
    frontmatter = true,
    body = true,
    tags = true,
    inlinks = true,
    outlinks = true,
    type = true,
    status = true,
}


function metadata.is_valid(key)
    return metadata.keys[key] ~= nil
end

return metadata
