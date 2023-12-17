local enums = {}

---@alias VaultMatchOptsKey
---|"'exact'" -  Matches exact value. E.g., "foo" matches "foo" but not "foobar".
---|"'contains'" -  Matches value if it contains the query. E.g., "foo" matches "foo" and "foobar".
---|"'startswith'" -  Matches value if it starts with the query. E.g., "foo" matches "foo" and "foobar".
---|"'endswith'" -  Matches value if it ends with the query. E.g., "foo" matches "foo" and "barfoo".
---|"'regex'" -  Matches value if it matches the query as a regex. E.g., "foo" matches "foo" and "barfoo".
---|"'fuzzy'" -  Matches value if it matches the query fuzzily. E.g., "foo" matches "foo" and "barfoo".

---@enum VaultMatchOptsKeys
enums.match_opts = {
    exact = 1,
    contains = 2,
    startswith = 3,
    endswith = 4,
    regex = 5,
    fuzzy = 6,
}

---@enum VaultFilterOptsModeKeys
enums.filter_mode = {
    all = 1,
    any = 2,
}

return enums
