local enums = {}
--- @alias vault.FilterOpts.search_term string
--- | '"tag"' # Filter on tags.
--- | '"slug"' # Filter on slugs.
--- | '"title"' # Filter on title.
--- | '"body"' # Filter on body.
--- | '"status"' # Filter on status.
--- | '"type"' # Filter on type.

--- @alias vault.enum.MatchOpts.key
--- |"'exact'" -  Matches exact value. E.g., "foo" matches "foo" but not "foobar".
--- |"'contains'" -  Matches value if it contains the query. E.g., "foo" matches "foo" and "foobar".
--- |"'startswith'" -  Matches value if it starts with the query. E.g., "foo" matches "foo" and "foobar".
--- |"'endswith'" -  Matches value if it ends with the query. E.g., "foo" matches "foo" and "barfoo".
--- |"'regex'" -  Matches value if it matches the query as a regex. E.g., "foo" matches "foo" and "barfoo".
--- |"'fuzzy'" -  Matches value if it matches the query fuzzily. E.g., "foo" matches "foo" and "barfoo".

--- @enum vault.enum.MatchOpts
enums.match_opts = {
    --- Matches exact value. E.g., "foo" matches "foo" but not "foobar".
    exact = 1,
    contains = 2,
    startswith = 3,
    endswith = 4,
    regex = 5,
    fuzzy = 6,
}

--- @alias vault.enum.MatchOpts.mode
--- |"'all'"  # Matches all names.
--- |"'any'" # Matches any value.

--- @enum vault.enum.MatchOpts.mode.key
enums.filter_mode = {
    all = 1,
    any = 2,
}

return enums
