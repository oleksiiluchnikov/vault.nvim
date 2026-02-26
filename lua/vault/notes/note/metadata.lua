local metadata = {}
--- @alias NoteMetaDataKey
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

--- @alias VaultNotesMeDataKey.unique
--- | "'relpath'" -- unique
--- | "'path'" -- unique


--- @alias VaultNotesSearchTerm NoteMetaDataKey

--- @type table<NoteMetaDataKey, boolean>
metadata.unique = {
    relpath = true,
    path = true,
}

--- @type table<NoteMetaDataKey, boolean>
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
