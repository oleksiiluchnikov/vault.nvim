local completions = require("vault.commands.completions")
local registry = require("vault.commands.registry")
local log = require("vault.log").scope("cmd")
--- @class vault.commands.callback
local callbacks = {}
local complete_duplicates_review
local complete_duplicates_related

--- Lazy accessor for telescope pickers — only loaded when a picker command runs.
--- @return table
local function get_pickers()
    return require("telescope._extensions.vault.pickers")
end

--- Safe picker launch — handles nil return from empty results.
--- @param picker any
--- @param empty_msg? string
local function safe_find(picker, empty_msg)
    if picker then
        picker:find()
    else
        log.info("%s", empty_msg or "No results found")
    end
end

function callbacks.toggle_link()
    local winid = vim.api.nvim_get_current_win()
    local cursor_pos = vim.api.nvim_win_get_cursor(winid)
    local line = vim.api.nvim_get_current_line()
    local col = cursor_pos[2] + 1 -- Convert 0-based index to 1-based

    -- Lua patterns (NOT Vim regex — string.find() only supports Lua patterns)
    local url_pattern = "(https?://[%w%-%.]+[%w%-]+[%w]/?[%w%-%._~:/?#%[%]@!%$&'%(%)%*%+,;=]*)"
    local md_link_pattern = "%[([^%]]*)%]%(([^%)]+)%)"

    local function update_line(new_content)
        vim.api.nvim_buf_set_lines(0, cursor_pos[1] - 1, cursor_pos[1], false, { new_content })
        -- Restore cursor position
        vim.api.nvim_win_set_cursor(winid, cursor_pos)
    end

    local function url_to_markdown(url, title)
        title = title or url or "Link"
        return string.format("[%s](%s)", title, url)
    end

    -- Try to find markdown link under cursor FIRST (more specific match)
    local search_start = math.max(1, col - 100)
    local md_start = search_start
    while md_start do
        local s, e, _, mdurl = line:find(md_link_pattern, md_start)
        if not s then
            break
        end
        if col >= s and col <= e then
            local new_line = line:sub(1, s - 1) .. mdurl .. line:sub(e + 1)
            update_line(new_line)
            return
        end
        md_start = s + 1
    end

    -- Try to find bare URL under cursor
    local url_start = search_start
    while url_start do
        local s, e, url = line:find(url_pattern, url_start)
        if not s then
            break
        end
        if col >= s and col <= e then
            local new_line = line:sub(1, s - 1) .. url_to_markdown(url) .. line:sub(e + 1)
            update_line(new_line)
            return
        end
        url_start = s + 1
    end

    log.warn("No URL or Markdown link found under cursor")
end

--- ============================================================================
--- Subcommand dispatch tree for :Vault
--- ============================================================================
---
--- Leaf nodes are tables with `run` (callback function) and optional `complete`
--- (completion function). Branch nodes map subcommand names to children.
---
--- Examples:
---   :Vault note              → note picker
---   :Vault note new <slug>   → create note
---   :Vault notes linked      → linked notes picker
---   :Vault tags              → tags picker
---   :Vault grep              → live grep
--- ============================================================================

--- @alias vault.Subcommand { run?: fun(args: string[], cmd_args: table), complete?: fun(prefix: string): string[], [string]: vault.Subcommand }

--- Build the subcommand tree lazily so pickers/callbacks resolve at call time.
--- @return table<string, vault.Subcommand>
local function build_subcommands()
    local tree = {
        -- :Vault note [method] — operate on current note
        note = {
            run = function(args, cmd_args)
                -- No args: open notes picker
                callbacks.note({
                    fargs = args,
                    line1 = cmd_args.line1,
                    line2 = cmd_args.line2,
                    range = cmd_args.range,
                })
            end,
            complete = function(prefix)
                local methods = {
                    "new",
                    "rename",
                    "merge",
                    "delete",
                    "extract",
                    "inlinks",
                    "outlinks",
                    "tags",
                    "properties",
                    "cluster",
                    "random",
                    "preview",
                    "graph",
                    "obsidian",
                }
                -- Also include Note methods
                local bufpath = vim.fn.expand("%:p")
                if bufpath:match("%.md$") then
                    local ok, Note = pcall(require, "vault.notes.note")
                    if ok and Note and Note.get_methods then
                        pcall(function()
                            local inst = Note(bufpath)
                            for _, m in ipairs(inst:get_methods()) do
                                if not vim.tbl_contains(methods, m) then
                                    table.insert(methods, m)
                                end
                            end
                        end)
                    end
                end
                return vim.tbl_filter(function(m)
                    return m:find(prefix, 1, true) == 1
                end, methods)
            end,
            new = {
                run = function(args)
                    callbacks.create_new_note({ fargs = args })
                end,
                complete = function(prefix)
                    return completions.dirs(nil, "Vault note new " .. prefix, nil) or {}
                end,
            },
            rename = {
                run = function(args)
                    callbacks.rename({ fargs = args })
                end,
            },
            merge = {
                run = function(args)
                    if #args == 0 then
                        require("vault.notes.workflows").open_merge_picker(nil, {})
                        return
                    end

                    if #args == 1 then
                        local current = vim.fn.expand("%:p")
                        if
                            type(current) == "string"
                            and current ~= ""
                            and current:match("%.md$")
                        then
                            require("vault.notes.workflows").merge(current, args[1], {})
                        else
                            require("vault.notes.workflows").open_merge_picker(args[1], {})
                        end
                        return
                    end

                    require("vault.notes.workflows").merge(args[1], args[2], {})
                end,
                complete = function(prefix, line)
                    line = line or ""
                    local args_text = line:match("note%s+merge%s*(.*)$") or ""
                    local ends_with_space = line:match("%s$") ~= nil
                    local args = vim.split(vim.trim(args_text), " ", { trimempty = true })
                    if #args == 0 or (#args == 1 and not ends_with_space) then
                        return completions.note_slugs(prefix, line, nil) or {}
                    end
                    return completions.wikilink_slugs(prefix, line, nil) or {}
                end,
            },
            extract = {
                run = function(args, cmd_args)
                    callbacks.note_from_selected_text({
                        fargs = args,
                        line1 = cmd_args.line1,
                        line2 = cmd_args.line2,
                        range = cmd_args.range,
                    })
                end,
                complete = function(prefix)
                    return completions.note_slugs(nil, "Vault note extract " .. prefix, nil) or {}
                end,
            },
            inlinks = {
                run = function()
                    callbacks.note_inlinks_picker({ fargs = {} })
                end,
            },
            outlinks = {
                run = function()
                    callbacks.note_outlinks_picker({ fargs = {} })
                end,
            },
            tags = {
                run = function(args, cmd_args)
                    callbacks.note_tags_picker({
                        fargs = args,
                        line1 = cmd_args.line1,
                        line2 = cmd_args.line2,
                        range = cmd_args.range,
                    })
                end,
                complete = function(prefix)
                    return completions.note_tags(nil, "Vault note tags " .. prefix, nil) or {}
                end,
            },
            properties = {
                run = function(args)
                    callbacks.open_note_properties_picker({ fargs = args })
                end,
            },
            cluster = {
                run = function(args)
                    local input = args[1] or ""
                    if input == "" then
                        local path = vim.fn.expand("%")
                        if type(path) == "table" then
                            path = path[1]
                        end
                        input = require("vault.utils").path_to_slug(path)
                    end
                    local notes = require("vault.notes")()
                    local note = notes:filter("slug", input, "exact"):list()[1]
                    if not note then
                        log.warn("Note not found: %s", input)
                        return
                    end
                    notes = require("vault.notes")()
                    local cluster = notes:to_cluster(note, 0)
                    local picker = get_pickers().notes({ notes = cluster })
                    if picker then
                        picker:find()
                    end
                end,
                complete = function(prefix)
                    return completions.note_slugs(nil, "Vault note cluster " .. prefix, nil) or {}
                end,
            },
            random = {
                run = function(args)
                    callbacks.edit_random_note({ fargs = args })
                end,
            },
            delete = {
                run = function(args)
                    local path
                    if args[1] and args[1] ~= "" then
                        path = require("vault.utils").slug_to_path(args[1])
                    else
                        path = vim.fn.expand("%:p")
                    end
                    if not path:match("%.md$") then
                        log.warn("Current buffer is not a note")
                        return
                    end
                    local note = require("vault.notes.note")(path)
                    local permanent = vim.tbl_contains(args, "--permanent")
                    require("vault.ui.confirm").confirm({
                        message = string.format(
                            "Delete note '%s'?%s",
                            note.data.slug,
                            permanent and " (PERMANENT)" or " (move to .trash)"
                        ),
                        title = "Vault",
                        on_yes = function()
                            note:delete(permanent)
                        end,
                        on_no = function()
                            log.info("Delete cancelled")
                        end,
                    })
                end,
                complete = function(prefix)
                    return completions.note_slugs(nil, "Vault note delete " .. prefix, nil) or {}
                end,
            },
            preview = {
                run = function()
                    local path = vim.fn.expand("%:p")
                    if not path:match("%.md$") then
                        log.warn("Current buffer is not a note")
                        return
                    end
                    require("vault.notes.note")(path):preview()
                end,
            },
            graph = {
                run = function()
                    local path = vim.fn.expand("%:p")
                    if not path:match("%.md$") then
                        log.warn("Current buffer is not a note")
                        return
                    end
                    require("vault.notes.note")(path):local_graph()
                end,
            },
            obsidian = {
                run = function()
                    local path = vim.fn.expand("%:p")
                    if not path:match("%.md$") then
                        log.warn("Current buffer is not a note")
                        return
                    end
                    require("vault.notes.note")(path):open_in_obsidian()
                end,
            },
        },

        conflicts = {
            run = function(args)
                callbacks.conflicts_review({ fargs = args })
            end,
            complete = function(prefix)
                local subs = { "review" }
                return vim.tbl_filter(function(m)
                    return m:find(prefix, 1, true) == 1
                end, subs)
            end,
            review = {
                run = function(args)
                    callbacks.conflicts_review({ fargs = args })
                end,
                complete = function(prefix)
                    return completions.dirs(nil, "Vault conflicts review " .. prefix, nil) or {}
                end,
            },
        },

        duplicates = {
            run = function(args)
                callbacks.duplicates_review({ fargs = args })
            end,
            complete = function(prefix)
                local subs = { "review", "related" }
                return vim.tbl_filter(function(m)
                    return m:find(prefix, 1, true) == 1
                end, subs)
            end,
            review = {
                run = function(args)
                    callbacks.duplicates_review({ fargs = args })
                end,
                complete = function(prefix, line)
                    return complete_duplicates_review(prefix, line)
                end,
                preset = {
                    run = function(args)
                        callbacks.duplicates_review_preset({ fargs = args })
                    end,
                    complete = function(prefix)
                        return require("vault.duplicates").preset_names(prefix)
                    end,
                },
            },
            related = {
                run = function(args)
                    callbacks.duplicates_related({ fargs = args })
                end,
                complete = function(prefix, line)
                    return complete_duplicates_related(prefix, line)
                end,
            },
        },

        -- :Vault notes [filter] — vault-wide note browsing
        notes = {
            run = function(args)
                callbacks.notes({ fargs = args })
            end,
            complete = function(prefix)
                local subs = {
                    "linked",
                    "orphans",
                    "leaves",
                    "internals",
                    "dangling",
                    "resolved",
                    "status",
                    "dir",
                    "empty",
                    "no-frontmatter",
                    "empty-property",
                }
                return vim.tbl_filter(function(s)
                    return s:find(prefix, 1, true) == 1
                end, subs)
            end,
            linked = {
                run = function()
                    callbacks.open_linked_picker({ fargs = {} })
                end,
            },
            orphans = {
                run = function()
                    callbacks.open_orphans_picker({ fargs = {} })
                end,
            },
            leaves = {
                run = function()
                    safe_find(get_pickers().leaves(), "No leaf notes found")
                end,
            },
            internals = {
                run = function()
                    safe_find(get_pickers().internals(), "No internal notes found")
                end,
            },
            dangling = {
                run = function()
                    safe_find(get_pickers().with_outlinks_unresolved(), "No dangling links found")
                end,
            },
            resolved = {
                run = function()
                    safe_find(
                        get_pickers().with_outlinks_resolved_only(),
                        "No notes with all outlinks resolved"
                    )
                end,
            },
            status = {
                run = function(args)
                    callbacks.open_notes_status_picker({ fargs = args })
                end,
                complete = function(prefix)
                    return completions.statuses(nil, "Vault notes status " .. prefix, nil) or {}
                end,
            },
            dir = {
                run = function(args)
                    callbacks.open_note_by_dir_picker({ fargs = args })
                end,
                complete = function(prefix)
                    return completions.dirs(nil, "Vault notes dir " .. prefix, nil) or {}
                end,
            },
            ["empty-property"] = {
                run = function(args)
                    local prop = args[1]
                    local val = args[2]
                    require("vault.properties.actions").open_picker_notes_with_empty_value(
                        prop,
                        val
                    )
                end,
                complete = function(prefix)
                    local ok, props = pcall(function()
                        return vim.tbl_keys(require("vault.scanner").properties())
                    end)
                    if not ok then
                        return {}
                    end
                    return vim.tbl_filter(function(p)
                        return p:find(prefix, 1, true) == 1
                    end, props)
                end,
            },
        },

        -- :Vault tags [tag] — vault tags picker
        tags = {
            run = function(args)
                safe_find(get_pickers().tags({ tags_list = args }), "No tags found")
            end,
            complete = function(prefix)
                local subs = { "rename", "merge", "doc", "promote" }
                local tag_completions = completions.tags(nil, "Vault tags " .. prefix, nil) or {}
                for _, s in ipairs(subs) do
                    if s:find(prefix, 1, true) == 1 then
                        table.insert(tag_completions, 1, s)
                    end
                end
                return tag_completions
            end,
            promote = {
                run = function(args)
                    if #args == 0 then
                        log.warn("Usage: :Vault tags promote <tag> [note-slug] [--frontmatter]")
                        return
                    end

                    local keep_frontmatter_tags = true
                    local parts = {}
                    for _, arg in ipairs(args) do
                        if arg == "--frontmatter" then
                            keep_frontmatter_tags = false
                        else
                            parts[#parts + 1] = arg
                        end
                    end
                    if #parts == 0 then
                        log.warn("Usage: :Vault tags promote <tag> [note-slug] [--frontmatter]")
                        return
                    end

                    if #parts == 1 then
                        require("vault.tags.workflows").open_promote_picker(parts[1], {
                            keep_frontmatter_tags = keep_frontmatter_tags,
                        })
                        return
                    end

                    require("vault.tags.workflows").promote(parts[1], parts[2], {
                        keep_frontmatter_tags = keep_frontmatter_tags,
                    })
                end,
                complete = function(prefix, line)
                    line = line or ""
                    local frontmatter_flag = "--frontmatter"
                    local args_text = line:match("tags%s+promote%s*(.*)$") or ""
                    local ends_with_space = line:match("%s$") ~= nil
                    local args = vim.split(vim.trim(args_text), " ", { trimempty = true })

                    if #args == 0 or (#args == 1 and not ends_with_space) then
                        return completions.tags(nil, line, nil) or {}
                    end

                    if #args == 1 and ends_with_space then
                        local results = completions.wikilink_slugs(nil, line, nil) or {}
                        if frontmatter_flag:find(prefix, 1, true) == 1 then
                            results[#results + 1] = frontmatter_flag
                        end
                        return results
                    end

                    if #args == 2 and not ends_with_space then
                        local results = completions.wikilink_slugs(nil, line, nil) or {}
                        if frontmatter_flag:find(prefix, 1, true) == 1 then
                            results[#results + 1] = frontmatter_flag
                        end
                        return results
                    end

                    return frontmatter_flag:find(prefix, 1, true) == 1 and { frontmatter_flag }
                        or {}
                end,
            },
        },

        -- :Vault properties [name] [value] — vault properties picker / drill-down
        properties = {
            run = function(args)
                return require("vault.properties.commands").spec().properties.run(args)
            end,
            complete = function(prefix)
                local ok, props = pcall(function()
                    return vim.tbl_keys(require("vault.scanner").properties())
                end)
                if not ok then
                    return {}
                end
                local subs = { "rename" }
                local results = {}
                for _, s in ipairs(subs) do
                    if s:find(prefix, 1, true) == 1 then
                        table.insert(results, s)
                    end
                end
                for _, p in ipairs(props) do
                    if p:find(prefix, 1, true) == 1 then
                        table.insert(results, p)
                    end
                end
                return results
            end,
            rename = {
                run = function(args)
                    if #args < 2 then
                        log.warn("Usage: :Vault properties rename <old> <new>")
                        return
                    end
                    local properties = require("vault.properties")()
                    local property = properties.map[args[1]]
                    if not property then
                        log.warn("Property not found: %s", args[1])
                        return
                    end
                    property:rename(args[2])
                    log.info("Renamed property '%s' -> '%s'", args[1], args[2])
                end,
                complete = function(prefix)
                    local ok, props = pcall(function()
                        return vim.tbl_keys(require("vault.scanner").properties())
                    end)
                    if not ok then
                        return {}
                    end
                    return vim.tbl_filter(function(p)
                        return p:find(prefix, 1, true) == 1
                    end, props)
                end,
            },
        },

        -- :Vault dirs [dir] — vault directories picker
        dirs = {
            run = function(args)
                callbacks.pick_dirs({ fargs = args })
            end,
            complete = function(prefix)
                return completions.dirs(nil, "Vault dirs " .. prefix, nil) or {}
            end,
        },

        -- :Vault dates — dates picker
        dates = {
            run = function()
                safe_find(get_pickers().dates(), "No dates found")
            end,
        },

        -- :Vault wikilinks — wikilinks picker
        wikilinks = {
            run = function()
                safe_find(get_pickers().wikilinks(), "No wikilinks found")
            end,
            complete = function(prefix)
                local subs = { "unresolved", "resolved" }
                return vim.tbl_filter(function(s)
                    return s:find(prefix, 1, true) == 1
                end, subs)
            end,
            unresolved = {
                run = function()
                    -- Use the fast Rust scanner path (no args) instead of Lua notes-based parsing
                    local wikilinks = require("vault.wikilinks")()
                    local unresolved = wikilinks:unresolved()
                    safe_find(
                        get_pickers().wikilinks({ wikilinks = unresolved }),
                        "No unresolved wikilinks found"
                    )
                end,
            },
            resolved = {
                run = function()
                    local wikilinks = require("vault.wikilinks")()
                    local resolved = wikilinks:resolved()
                    safe_find(
                        get_pickers().wikilinks({ wikilinks = resolved }),
                        "No resolved wikilinks found"
                    )
                end,
            },
        },

        -- :Vault tasks — tasks picker
        tasks = require("vault.tasks.commands").spec().tasks,

        actions = {
            run = function()
                callbacks.actions()
            end,
        },

        -- :Vault bases [name] — bases picker
        bases = require("vault.bases.commands").spec().bases,

        -- :Vault process [filter] — Grid-backed metadata editing buffer (default)
        -- Supports: base <name>, undo, orphans, leaves, empty, no-frontmatter,
        --           dir <path>, tag <name>, without-property <field>, empty-property <field> [value],
        --           title,status,tags (inline columns), taxonomy=<field>, group_by=<field>, <slug> (fuzzy filter)
        process = {
            run = function(args)
                local grid_editor = require("vault.views.grid")

                -- Extract key=value options (e.g. group_by=status) before
                -- interpreting positional args.
                local kv_opts = {} --- @type table<string, string>
                local positional = {} --- @type string[]
                for _, a in ipairs(args) do
                    local k, v = a:match("^([%w_-]+)=(.+)$")
                    if k then
                        kv_opts[k] = v
                    else
                        table.insert(positional, a)
                    end
                end
                args = positional

                local filter = args[1]
                local notes, desc

                -- Inline column spec: if first arg contains a comma, treat as columns
                -- e.g. :Vault process title,status,tags
                -- e.g. :Vault process title,status,tags orphans
                local columns_arg = nil
                if filter and filter:find(",") then
                    columns_arg = vim.split(filter, ",", { plain = true })
                    for i, c in ipairs(columns_arg) do
                        columns_arg[i] = vim.trim(c)
                    end
                    columns_arg = vim.tbl_filter(function(c)
                        return c ~= ""
                    end, columns_arg)
                    filter = args[2]
                    args = vim.list_slice(args, 2)
                end

                if filter == "undo" then
                    grid_editor.undo()
                    return
                elseif kv_opts["without-property"] and kv_opts["without-property"] ~= "" then
                    notes = require("vault.notes")():without_property(kv_opts["without-property"])
                    desc = "without property:" .. kv_opts["without-property"]
                elseif not filter or filter == "" then
                    notes = require("vault.notes")()
                    desc = "all notes"
                elseif filter == "orphans" then
                    notes = require("vault.notes")():orphans()
                    desc = "orphan notes"
                elseif filter == "leaves" then
                    notes = require("vault.notes")():leaves()
                    desc = "leaf notes"
                elseif filter == "empty" then
                    notes = require("vault.notes")():filter("content", [[^\s*$]], "regex", false)
                    desc = "empty notes"
                elseif filter == "no-frontmatter" then
                    notes = require("vault.notes")():filter(
                        "content",
                        [=[^\(---\)\@!.*$]=],
                        "regex",
                        true
                    )
                    desc = "no frontmatter"
                elseif filter == "dir" and args[2] then
                    notes = require("vault.notes")():filter("relpath", args[2], "startswith", false)
                    desc = "dir:" .. args[2]
                elseif filter == "tag" and args[2] then
                    notes = require("vault.notes")():filter({
                        search_term = "tags",
                        include = { args[2] },
                        exclude = {},
                        match_opt = "exact",
                        mode = "all",
                    })
                    desc = "tag:" .. args[2]
                elseif filter == "base" then
                    if args[2] then
                        local base_name = table.concat(vim.list_slice(args, 2), " ")
                        local Bases = require("vault.bases")
                        local bases = Bases()
                        local base = bases:get(base_name)
                        if not base then
                            log.error("Base not found: %s", base_name)
                            return
                        end
                        if kv_opts.taxonomy and kv_opts.taxonomy ~= "" then
                            local taxonomy_field = kv_opts.taxonomy
                            if not columns_arg then
                                columns_arg = { "slug", "title", taxonomy_field }
                            elseif not vim.tbl_contains(columns_arg, taxonomy_field) then
                                table.insert(columns_arg, taxonomy_field)
                            end
                        end

                        local open_opts = {
                            base = base,
                            columns = columns_arg,
                            group_by = kv_opts.group_by,
                        }
                        if kv_opts.taxonomy and kv_opts.taxonomy ~= "" then
                            local taxonomy = require("vault.taxonomy")
                            open_opts = vim.tbl_extend(
                                "force",
                                open_opts,
                                taxonomy.grid_process_opts(kv_opts.taxonomy)
                            )
                        end
                        grid_editor.open(open_opts)
                    else
                        -- No base name given — open Telescope bases picker
                        local ok, picker =
                            pcall(require, "telescope._extensions.vault.pickers.bases")
                        if ok then
                            picker():find()
                        else
                            log.error("Telescope bases picker not available: %s", tostring(picker))
                        end
                    end
                    return
                elseif filter == "candidates-delete" then
                    -- Smart delete candidates: empty body, stubs (<20 chars body),
                    -- and truly orphaned+untagged notes.
                    local Notes = require("vault.notes")
                    local all = Notes()
                    local candidates = {}
                    for slug, note in pairs(all.map) do
                        local body = note.data.content or ""
                        -- Strip frontmatter for body length check
                        local stripped = body:gsub("^%-%-%-.-%-%-%-\n?", "")
                        stripped = vim.trim(stripped)
                        if #stripped == 0 or #stripped < 20 then
                            candidates[slug] = note
                        end
                    end
                    -- Also add orphans with no tags
                    local orphans = Notes():orphans()
                    local tags_sources = require("vault.tags")():sources()
                    for slug, note in pairs(orphans.map) do
                        if not tags_sources[slug] then
                            candidates[slug] = note
                        end
                    end
                    notes = Notes()
                    notes.map = candidates
                    desc = "delete candidates"
                elseif filter == "empty-property" then
                    require("vault.properties.actions").open_picker_notes_with_empty_value(
                        args[2],
                        args[3]
                    )
                    return
                elseif filter == "without-property" and args[2] then
                    notes = require("vault.notes")():without_property(args[2])
                    desc = "without property:" .. args[2]
                else
                    notes = require("vault.notes")():filter("slug", filter, "fuzzy")
                    desc = "filter:" .. filter
                end

                if kv_opts.taxonomy and kv_opts.taxonomy ~= "" then
                    local taxonomy_field = kv_opts.taxonomy
                    if not columns_arg then
                        columns_arg = { "slug", "title", taxonomy_field }
                    elseif not vim.tbl_contains(columns_arg, taxonomy_field) then
                        table.insert(columns_arg, taxonomy_field)
                    end
                end

                local open_opts = {
                    notes = notes,
                    filter_desc = desc,
                    columns = columns_arg,
                    group_by = kv_opts.group_by,
                }

                if kv_opts.taxonomy and kv_opts.taxonomy ~= "" then
                    local taxonomy = require("vault.taxonomy")
                    open_opts = vim.tbl_extend(
                        "force",
                        open_opts,
                        taxonomy.grid_process_opts(kv_opts.taxonomy)
                    )
                end

                grid_editor.open(open_opts)
            end,
            complete = function(prefix, line)
                if line and line:match("process%s+base%s+") then
                    local ok, Bases = pcall(require, "vault.bases")
                    if ok then
                        local bases = Bases()
                        local names = bases:names()
                        local sub = line:match("process%s+base%s+(.*)") or ""
                        return vim.tbl_filter(function(s)
                            return s:find(sub, 1, true) == 1
                        end, names)
                    end
                    return {}
                end
                if line and line:match("process%s+without%-property%s+") then
                    local ok, properties = pcall(function()
                        return require("vault.scanner").properties()
                    end)
                    if not ok or type(properties) ~= "table" then
                        return {}
                    end
                    local query = line:match("process%s+without%-property%s+(.*)$") or ""
                    local keys = vim.tbl_keys(properties)
                    table.sort(keys)
                    return vim.tbl_filter(function(s)
                        return s:find(query, 1, true) == 1
                    end, keys)
                end
                local col_arg = line and line:match("process%s+([^%s]*,[^%s]*)$")
                if col_arg then
                    local last_comma = col_arg:match(".*,()")
                    local col_prefix = last_comma and col_arg:sub(last_comma) or ""
                    local builtin = {
                        "slug",
                        "title",
                        "tags",
                        "status",
                        "file.name",
                        "file.folder",
                        "file.path",
                        "file.ext",
                        "file.ctime",
                        "file.mtime",
                        "file.size",
                        "file.body",
                        "file.slug",
                        "file.inlinks",
                        "file.outlinks",
                        "file.headings",
                        "note.name",
                        "note.folder",
                        "note.path",
                        "note.ext",
                        "note.ctime",
                        "note.mtime",
                        "note.size",
                        "note.body",
                        "note.slug",
                        "note.inlinks",
                        "note.outlinks",
                        "note.headings",
                    }
                    local ok_core, core = pcall(require, "vault_core")
                    if ok_core and core.fields then
                        local cfg = require("vault.config")
                        local ok_f, fields = pcall(
                            core.fields,
                            cfg.options and cfg.options.root or "",
                            cfg.options and cfg.options.ignore or {}
                        )
                        if ok_f and type(fields) == "table" then
                            for k, _ in pairs(fields) do
                                if not vim.tbl_contains(builtin, k) then
                                    table.insert(builtin, k)
                                end
                            end
                        end
                    end
                    local matches = vim.tbl_filter(function(s)
                        return s:find(col_prefix, 1, true) == 1
                    end, builtin)
                    local base_part = last_comma and col_arg:sub(1, last_comma - 1) or ""
                    return vim.tbl_map(function(s)
                        return base_part .. s
                    end, matches)
                end
                -- Complete group_by= with known column names
                if prefix:match("^group_by=") then
                    local gp = prefix:match("^group_by=(.*)$") or ""
                    local cols = { "status", "tags", "title", "dir" }
                    return vim.tbl_map(
                        function(c)
                            return "group_by=" .. c
                        end,
                        vim.tbl_filter(function(c)
                            return c:find(gp, 1, true) == 1
                        end, cols)
                    )
                end
                if prefix:match("^taxonomy=") then
                    local field = prefix:match("^taxonomy=(.*)$") or ""
                    local settings = require("vault.taxonomy")._get_settings()
                    local fields = { settings.field }
                    return vim.tbl_map(
                        function(item)
                            return "taxonomy=" .. item
                        end,
                        vim.tbl_filter(function(item)
                            return item:find(field, 1, true) == 1
                        end, fields)
                    )
                end
                local subs = {
                    "base",
                    "undo",
                    "orphans",
                    "leaves",
                    "empty",
                    "no-frontmatter",
                    "dir",
                    "tag",
                    "without-property",
                    "empty-property",
                    "candidates-delete",
                    "group_by=",
                    "taxonomy=",
                }
                return vim.tbl_filter(function(s)
                    return s:find(prefix, 1, true) == 1
                end, subs)
            end,
        },

        -- :Vault list [filter] — List-backed metadata editing buffer
        list = {
            run = function(args)
                local list_editor = require("vault.views.list")
                local filter = args[1]
                local notes, desc

                local columns_arg = nil
                if filter and filter:find(",") then
                    columns_arg = vim.split(filter, ",", { plain = true })
                    for i, c in ipairs(columns_arg) do
                        columns_arg[i] = vim.trim(c)
                    end
                    columns_arg = vim.tbl_filter(function(c)
                        return c ~= ""
                    end, columns_arg)
                    filter = args[2]
                    args = vim.list_slice(args, 2)
                end

                if not filter or filter == "" then
                    notes = require("vault.notes")()
                    desc = "all notes"
                elseif filter == "orphans" then
                    notes = require("vault.notes")():orphans()
                    desc = "orphan notes"
                elseif filter == "leaves" then
                    notes = require("vault.notes")():leaves()
                    desc = "leaf notes"
                elseif filter == "dir" and args[2] then
                    notes = require("vault.notes")():filter("relpath", args[2], "startswith", false)
                    desc = "dir:" .. args[2]
                elseif filter == "tag" and args[2] then
                    notes = require("vault.notes")():filter({
                        search_term = "tags",
                        include = { args[2] },
                        exclude = {},
                        match_opt = "exact",
                        mode = "all",
                    })
                    desc = "tag:" .. args[2]
                elseif filter == "base" then
                    if args[2] then
                        local base_name = table.concat(vim.list_slice(args, 2), " ")
                        local Bases = require("vault.bases")
                        local base = Bases():get(base_name)
                        if not base then
                            log.error("Base not found: %s", base_name)
                            return
                        end
                        list_editor.open({ base = base, columns = columns_arg })
                    else
                        local ok, picker =
                            pcall(require, "telescope._extensions.vault.pickers.bases")
                        if ok then
                            picker():find()
                        end
                    end
                    return
                else
                    notes = require("vault.notes")():filter("slug", filter, "fuzzy")
                    desc = "filter:" .. filter
                end

                list_editor.open({ notes = notes, filter_desc = desc, columns = columns_arg })
            end,
            complete = function(prefix, line)
                if line and line:match("list%s+base%s+") then
                    local ok, Bases = pcall(require, "vault.bases")
                    if ok then
                        local names = Bases():names()
                        local sub = line:match("list%s+base%s+(.*)") or ""
                        return vim.tbl_filter(function(s)
                            return s:find(sub, 1, true) == 1
                        end, names)
                    end
                    return {}
                end
                local subs = { "base", "orphans", "leaves", "dir", "tag" }
                return vim.tbl_filter(function(s)
                    return s:find(prefix, 1, true) == 1
                end, subs)
            end,
        },

        -- :Vault kanban [filter] — Kanban board view grouped by frontmatter/tags/directory
        -- Supports: base <name>, group=<field>, fields=<f1,f2>,
        --           tag <name>, dir <path>
        kanban = {
            run = function(args)
                local grid_kanban = require("vault.views.kanban")
                local filter
                local notes, desc

                -- Parse key=value args anywhere in the arg list
                local group_field, display_fields, render_mode
                local remaining = {}
                for _, arg in ipairs(args) do
                    local k, v = arg:match("^(%w+)=(.+)$")
                    if k == "group" or k == "field" then
                        group_field = v
                    elseif k == "fields" then
                        display_fields = vim.split(v, ",", { plain = true })
                        for i, f in ipairs(display_fields) do
                            display_fields[i] = vim.trim(f)
                        end
                    elseif k == "mode" then
                        render_mode = v
                    else
                        table.insert(remaining, arg)
                    end
                end
                filter = remaining[1]

                if not filter or filter == "" then
                    notes = require("vault.notes")()
                    desc = "all notes"
                elseif filter == "base" then
                    if remaining[2] then
                        local base_name = table.concat(vim.list_slice(remaining, 2), " ")
                        local Bases = require("vault.bases")
                        local bases = Bases()
                        local base = bases:get(base_name)
                        if not base then
                            log.error("Base not found: %s", base_name)
                            return
                        end
                        grid_kanban.open({
                            base = base,
                            group_field = group_field,
                            display_fields = display_fields,
                            render_mode = render_mode,
                        })
                    else
                        -- No base name given — open Telescope bases picker
                        local ok, picker =
                            pcall(require, "telescope._extensions.vault.pickers.bases")
                        if ok then
                            picker():find()
                        else
                            log.error("Telescope bases picker not available: %s", tostring(picker))
                        end
                    end
                    return
                elseif filter == "tag" and remaining[2] then
                    notes = require("vault.notes")():filter({
                        search_term = "tags",
                        include = { remaining[2] },
                        exclude = {},
                        match_opt = "exact",
                        mode = "all",
                    })
                    desc = "tag:" .. remaining[2]
                elseif filter == "dir" and remaining[2] then
                    notes = require("vault.notes")():filter(
                        "relpath",
                        remaining[2],
                        "startswith",
                        false
                    )
                    desc = "dir:" .. remaining[2]
                else
                    notes = require("vault.notes")():filter("slug", filter, "fuzzy")
                    desc = "filter:" .. filter
                end

                grid_kanban.open({
                    notes = notes,
                    filter_desc = desc,
                    group_field = group_field,
                    display_fields = display_fields,
                    render_mode = render_mode,
                })
            end,
            complete = function(prefix, line)
                if line and line:match("kanban%s+base%s+") then
                    local ok, Bases = pcall(require, "vault.bases")
                    if ok then
                        local bases = Bases()
                        local names = bases:names()
                        local sub = line:match("kanban%s+base%s+(.*)") or ""
                        return vim.tbl_filter(function(s)
                            return s:find(sub, 1, true) == 1
                        end, names)
                    end
                    return {}
                end
                local subs = { "base", "tag", "dir", "group=", "fields=", "mode=" }
                return vim.tbl_filter(function(s)
                    return s:find(prefix, 1, true) == 1
                end, subs)
            end,
        },

        -- :Vault calendar [filter] — Calendar view placing notes by date field
        -- Supports: base <name>, date=<field>, primary=<field>,
        --           tag <name>, dir <path>
        calendar = {
            run = function(args)
                local cal_view = require("vault.views.calendar")
                local filter
                local notes, desc

                -- Parse key=value args
                local date_field, primary_field, annual_override
                local remaining = {}
                for _, arg in ipairs(args) do
                    local k, v = arg:match("^(%w+)=(.+)$")
                    if k == "date" then
                        date_field = v
                    elseif k == "primary" then
                        primary_field = v
                    elseif k == "annual" then
                        annual_override = (v == "true" or v == "1")
                    else
                        table.insert(remaining, arg)
                    end
                end
                filter = remaining[1]

                if not filter or filter == "" then
                    notes = require("vault.notes")()
                    desc = "all notes"
                elseif filter == "base" then
                    if remaining[2] then
                        local base_name = table.concat(vim.list_slice(remaining, 2), " ")
                        local Bases = require("vault.bases")
                        local bases = Bases()
                        local base = bases:get(base_name)
                        if not base then
                            log.error("Base not found: %s", base_name)
                            return
                        end
                        cal_view.open({
                            base = base,
                            date_field = date_field,
                            primary_field = primary_field,
                            annual = annual_override,
                        })
                    else
                        local ok, picker =
                            pcall(require, "telescope._extensions.vault.pickers.bases")
                        if ok then
                            picker():find()
                        else
                            log.error("Telescope bases picker not available: %s", tostring(picker))
                        end
                    end
                    return
                elseif filter == "tag" and remaining[2] then
                    notes = require("vault.notes")():filter({
                        search_term = "tags",
                        include = { remaining[2] },
                        exclude = {},
                        match_opt = "exact",
                        mode = "all",
                    })
                    desc = "tag:" .. remaining[2]
                elseif filter == "dir" and remaining[2] then
                    notes = require("vault.notes")():filter(
                        "relpath",
                        remaining[2],
                        "startswith",
                        false
                    )
                    desc = "dir:" .. remaining[2]
                else
                    notes = require("vault.notes")():filter("slug", filter, "fuzzy")
                    desc = "filter:" .. filter
                end

                cal_view.open({
                    notes = notes,
                    filter_desc = desc,
                    date_field = date_field,
                    primary_field = primary_field,
                    annual = annual_override,
                })
            end,
            complete = function(prefix, line)
                if line and line:match("calendar%s+base%s+") then
                    local ok, Bases = pcall(require, "vault.bases")
                    if ok then
                        local bases = Bases()
                        local names = bases:names()
                        local sub = line:match("calendar%s+base%s+(.*)") or ""
                        return vim.tbl_filter(function(s)
                            return s:find(sub, 1, true) == 1
                        end, names)
                    end
                    return {}
                end
                local subs = { "base", "tag", "dir", "date=", "primary=", "annual=" }
                return vim.tbl_filter(function(s)
                    return s:find(prefix, 1, true) == 1
                end, subs)
            end,
        },

        -- :Vault triage — open process buffer pre-filtered to highest-value items
        -- Shows untagged notes merged with orphans, sorted by mtime descending.
        -- One command that says "start here."
        triage = {
            run = function()
                local Notes = require("vault.notes")
                -- Collect untagged notes
                local untagged = Notes():without_tags()
                -- Collect orphans separately (without_tags mutates self.map)
                local orphan_set = Notes():orphans()
                -- Merge: untagged ∪ orphans (dedup by slug)
                local merged = {}
                for slug, note in pairs(untagged.map) do
                    merged[slug] = note
                end
                for slug, note in pairs(orphan_set.map) do
                    merged[slug] = note
                end
                -- Wrap in a fresh Notes-like object for grid.open
                local all = Notes()
                all.map = merged
                local grid = require("vault.views.grid")
                grid.open({
                    notes = all,
                    filter_desc = "triage",
                    columns = { "slug", "title", "tags", "status" },
                })
            end,
        },

        -- :Vault stats — progress dashboard showing vault health metrics
        stats = {
            run = function()
                require("vault.ui.stats").open()
            end,
        },

        -- :Vault doctor          — vault-wide frontmatter type check
        -- :Vault doctor --fix    — auto-fix known patterns
        doctor = {
            run = function(args)
                callbacks.vault_doctor(args)
            end,
        },

        -- :Vault today           — open today's journal
        -- :Vault today append    — append a line
        -- :Vault today dictate   — dictate a line via ask --dictate
        today = {
            run = function()
                callbacks.today()
            end,
            append = {
                run = function(args)
                    local text = table.concat(args, " ")
                    if text == "" then
                        log.warn("Usage: :Vault today append <text>")
                        return
                    end
                    callbacks.daily_append(text)
                end,
            },
            dictate = vim.fn.executable("ask") == 1 and {
                run = function()
                    callbacks.today_dictate()
                end,
            } or nil,
        },

        -- :Vault yesterday — yesterday's journal
        yesterday = {
            run = function()
                callbacks.yesterday()
            end,
        },

        -- :Vault watcher [start|stop|status] — file watcher control
        watcher = {
            run = function(args)
                local state = require("vault.core.state")
                local w = state.get_global_key("watcher")
                local sub = args[1] or "status"
                if sub == "status" then
                    if w and w.is_watching then
                        log.info("Watcher is active")
                    else
                        log.info("Watcher is inactive")
                    end
                elseif sub == "start" then
                    local Watcher = require("vault.watcher")
                    w = w or Watcher()
                    w:start()
                    state.set_global_key("watcher", w)
                    log.info("Watcher started")
                elseif sub == "stop" then
                    if w and w.is_watching then
                        w:stop()
                        log.info("Watcher stopped")
                    else
                        log.warn("Watcher is not running")
                    end
                else
                    log.warn("Usage: :Vault watcher [start|stop|status]")
                end
            end,
            complete = function(prefix)
                local subs = { "start", "stop", "status" }
                return vim.tbl_filter(function(s)
                    return s:find(prefix, 1, true) == 1
                end, subs)
            end,
        },

        -- :Vault trash — browse and manage trashed notes
        trash = {
            run = function()
                local config = require("vault.config")
                local trash_dir = config.options.root .. "/.trash"
                if vim.fn.isdirectory(trash_dir) == 0 then
                    log.info("Trash is empty (.trash/ does not exist)")
                    return
                end
                local files = vim.fn.globpath(trash_dir, "*.md", false, true)
                if #files == 0 then
                    log.info("Trash is empty")
                    return
                end
                -- Use vim.ui.select for simplicity
                local items = {}
                for _, f in ipairs(files) do
                    table.insert(items, vim.fn.fnamemodify(f, ":t"))
                end
                vim.ui.select(items, {
                    prompt = "Trashed notes (" .. #items .. ") — select to restore or delete:",
                }, function(choice)
                    if not choice then
                        return
                    end
                    local full_path = trash_dir .. "/" .. choice
                    require("vault.ui.confirm").select({
                        message = "Note: " .. choice,
                        title = "Vault Trash",
                        choices = {
                            {
                                key = "r",
                                label = "Restore",
                                action = function()
                                    local restore_path = config.options.root .. "/" .. choice
                                    if vim.fn.filereadable(restore_path) == 1 then
                                        log.error(
                                            "A note with that name already exists in the vault"
                                        )
                                        return
                                    end
                                    local ok, err = (vim.uv or vim.loop).fs_rename(
                                        full_path,
                                        restore_path
                                    )
                                    if ok then
                                        log.info("Restored: %s", choice)
                                    else
                                        log.error("Restore failed: %s", tostring(err))
                                    end
                                end,
                            },
                            {
                                key = "d",
                                label = "Permanent delete",
                                action = function()
                                    local ok, err = os.remove(full_path)
                                    if ok then
                                        log.info("Permanently deleted: %s", choice)
                                    else
                                        log.error("Delete failed: %s", tostring(err))
                                    end
                                end,
                                danger = true,
                            },
                            { key = "c", label = "Cancel", action = function() end },
                        },
                    })
                end)
            end,
        },

        -- :Vault fleeting — fleeting note popup
        fleeting = {
            run = function(args)
                callbacks.open_fleeting_note_popup({ fargs = args })
            end,
        },

        -- :Vault grep — live grep across vault
        grep = {
            run = function(args, cmd_args)
                callbacks.open_live_grep_picker({
                    fargs = args,
                    line1 = cmd_args.line1,
                    line2 = cmd_args.line2,
                    range = cmd_args.range,
                })
            end,
        },

        -- :Vault toggle-link — toggle markdown link under cursor
        ["toggle-link"] = {
            run = function()
                callbacks.toggle_link()
            end,
        },

        -- :Vault inbox — inbox notes picker
        inbox = {
            run = function()
                local config = require("vault.config")
                local inbox_dir = config.dir("inbox")
                if not inbox_dir or vim.fn.isdirectory(inbox_dir) == 0 then
                    log.warn("Inbox directory not configured or does not exist (dirs.inbox)")
                    return
                end
                safe_find(get_pickers().inbox(), "No notes in inbox")
            end,
        },

        -- :Vault move [note] — move note to a different directory
        move = {
            run = function(args)
                local opts = {}
                if args[1] and args[1] ~= "" then
                    local notes = require("vault.notes")():filter("slug", args[1], "exact", false)
                    local _, note = next(notes.map)
                    if note then
                        opts.note = note
                    else
                        log.warn("Note not found: %s", args[1])
                        return
                    end
                end
                safe_find(get_pickers().move_to(opts), "No directories found")
            end,
            complete = function(prefix)
                return completions.note_slugs(nil, "Vault move " .. prefix, nil) or {}
            end,
        },

        merge = {
            biases = {
                run = function()
                    require("vault.merge_biases").open()
                end,
            },
        },
    }

    return registry.build(tree)
end

--- Cached subcommand tree (built on first use)
local _subcommands = nil
local function get_subcommands()
    if not _subcommands then
        _subcommands = build_subcommands()
    end
    return _subcommands
end

--- Walk the subcommand tree and dispatch.
--- @param args vim.api.keyset.create_user_command.command_args
function callbacks.api(args)
    local fargs = args.fargs or {}

    -- No subcommand: open meta picker (picker of pickers)
    if #fargs == 0 then
        safe_find(get_pickers().vault(), "No pickers available")
        return
    end

    -- Walk the tree
    local node = get_subcommands()
    for i, arg in ipairs(fargs) do
        local child = node[arg]
        if not child then
            -- No deeper match — if current node has `run`, call it with remaining args
            if node.run then
                local remaining = vim.list_slice(fargs, i)
                node.run(remaining, args)
                return
            end
            log.warn("Unknown subcommand: %s", table.concat(vim.list_slice(fargs, 1, i), " "))
            return
        end
        -- child is a subtree or a leaf
        if type(child) == "table" and child.run then
            -- Check if there are deeper children matching the next arg
            local next_arg = fargs[i + 1]
            if next_arg and child[next_arg] then
                node = child
            else
                -- Leaf (or branch with run): call with remaining args
                local remaining = vim.list_slice(fargs, i + 1)
                child.run(remaining, args)
                return
            end
        elseif type(child) == "table" then
            node = child
        end
    end

    -- Reached end of args at a branch node with a run function
    if node.run then
        node.run({}, args)
    else
        local subs = {}
        for k, v in pairs(node) do
            if type(v) == "table" and k ~= "run" and k ~= "complete" then
                table.insert(subs, k)
            end
        end
        table.sort(subs)
        log.info("Subcommands: %s", table.concat(subs, ", "))
    end
end

--- ```vim
--- :vaultNotes <preset> <filter> ...
--- :Vault notes linked tags <include_tags> <exclude_tags> <match_opt> <match_type>
--- :Vault notes orphans tags <include_tags> <exclude_tags> <match_opt> <match_type>
--- :Vault notes tags <include_tags> <exclude_tags> <match_opt> <match_type>
--- ```

--- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- --
--- Create a new note with the given slug.
---
--- If no slug is provided, a fleeting note popup is shown.
--- If a note with the given slug already exists, it is opened for editing.
--- Otherwise, a new note is created with the given slug and opened for editing.
---
--- @param args vim.api.keyset.create_user_command.command_args
--- @usage
--- ```lua
--- ```
function callbacks.create_new_note(args)
    local fargs = args.fargs
    if next(fargs) == nil then
        require("vault.popups.fleeting_note")()
        return
    end

    local new_slug = table.concat(fargs, " ")
    local create_path = require("vault.notes.paths").for_slug(new_slug)
    if create_path and vim.fn.filereadable(create_path) == 1 then
        require("vault.notes.note")(create_path):edit()
        return
    end

    local notes = require("vault.notes")():filter("slug", new_slug, "exact", false)
    if next(notes.map) then
        local _, existing = next(notes.map)
        existing:edit()
        return
    end
    require("vault.notes.create").create(new_slug)
end

--- @param args vim.api.keyset.create_user_command.command_args
function callbacks.pick_dirs(args)
    local fargs = args.fargs
    if next(fargs) == nil then
        safe_find(get_pickers().dirs(), "No directories found")
        return
    end
    local notes = require("vault.notes")():filter("relpath", fargs[1], "startswith", false)
    safe_find(get_pickers().notes({ notes = notes }), "No notes found in directory: " .. fargs[1])
end

---Edits a random note from the vault.
---@param args vim.api.keyset.create_user_command.command_args
---@return nil
function callbacks.edit_random_note(args)
    ---@type vault.Notes
    local notes
    if #args.fargs == 0 then
        notes = require("vault.notes")()
    else
        notes = require("vault.notes")():filter("slug", table.concat(args.fargs, " "), "fuzzy")
    end
    local random_note = notes:get_random()
    if random_note == nil then
        return
    end
    random_note:edit()
end

--- vault.Tags
--- @param args vim.api.keyset.create_user_command.command_args
function callbacks.open_tags_picker(args)
    local fargs = args.fargs
    if next(fargs) == nil then
        safe_find(get_pickers().tags(), "No tags found")
        return
    end

    local tags_names = fargs
    --- @type vault.Filter.option.tags
    local filter_opts = {
        search_term = "tags",
        include = tags_names,
        exclude = {},
        match_opt = "contains",
        mode = "all",
    }

    safe_find(
        get_pickers().notes({ notes = require("vault.notes")():filter(filter_opts) }),
        "No notes found with tags: " .. table.concat(tags_names, ", ")
    )
end

--- Vault Dates
--- Opens a picker with the dates
--- @param args vim.api.keyset.create_user_command.command_args
--- @return nil
function callbacks.open_dates_picker(args)
    local fargs = args.fargs
    if next(fargs) == nil then
        safe_find(get_pickers().dates(), "No dates found")
        return
    end
    --TODO: Add configuration to set the date format
    local today = os.date("%Y-%m-%d")
    local year_ago = os.date("%Y-%m-%d", os.time() - 60 * 60 * 24 * 365)
    safe_find(
        get_pickers().dates({ start_date = tostring(today), end_date = tostring(year_ago) }),
        "No dates found"
    )
end

--- vault.Today
--- Opens the today's journal note
--- @return nil
function callbacks.today()
    local journal = require("vault.journal")
    local today = os.date("%Y-%m-%d")
    local path, created = journal.ensure(today)
    if type(path) ~= "string" then
        log.error(
            "Journal daily note path not configured (configure .obsidian/daily-notes.json or dirs.journal.daily)"
        )
        return
    end
    if created then
        log.info("Initializing today's journal note")
    end
    vim.cmd("e " .. vim.fn.fnameescape(path))
end

--- Appends a line to today's daily note without opening it.
--- @param text string  Line text to append (a "- " prefix is added automatically)
--- @return nil
function callbacks.daily_append(text)
    local journal = require("vault.journal")
    local today = os.date("%Y-%m-%d")
    local path = select(1, journal.ensure(today))
    if type(path) ~= "string" then
        log.error(
            "Journal daily note path not configured (configure .obsidian/daily-notes.json or dirs.journal.daily)"
        )
        return
    end
    local basename = journal.basename(today)
    if type(basename) ~= "string" then
        return
    end
    local Note = require("vault.notes.note")
    local note = Note(path)
    note:append("- " .. text)
    log.info("Appended to %s", basename)
end

--- Open ask --dictate with today's daily note as context, append result.
--- Requires the `ask` binary to be available in PATH.
--- @return nil
function callbacks.today_dictate()
    if vim.fn.executable("ask") == 0 then
        log.error("`ask` not found in PATH — install it to use :Vault today dictate")
        return
    end
    local journal = require("vault.journal")
    local today = os.date("%Y-%m-%d")
    local path = select(1, journal.ensure(today))
    if type(path) ~= "string" then
        log.error(
            "Journal daily note path not configured (configure .obsidian/daily-notes.json or dirs.journal.daily)"
        )
        return
    end
    local basename = journal.basename(today)
    if type(basename) ~= "string" then
        return
    end
    local ctx = vim.fn.filereadable(path) == 1 and table.concat(vim.fn.readfile(path), "\n") or ""
    local Note = require("vault.notes.note")
    -- Pass context via stdin ("--context -") to avoid argument-length limits
    -- and to correctly handle multiline/special-char note content.
    vim.system(
        { "ask", "--dictate", "--json", "--context", "-", "--placeholder", "Say something…" },
        { stdin = ctx },
        function(out)
            if out.code ~= 0 then
                return
            end
            vim.schedule(function()
                local ok, json = pcall(vim.json.decode, vim.trim(out.stdout))
                if ok and json.ok and json.value ~= "" then
                    Note(path):append("- " .. os.date("%H:%M:%S") .. " " .. json.value)
                    log.info("Appended dictated line to %s", basename)
                end
            end)
        end
    )
end

function callbacks.open_properties_picker(args)
    local fargs = args.fargs
    if next(fargs) == nil then
        safe_find(get_pickers().properties(), "No properties found")
        return
    end
    local values = {}
    for _, value in ipairs(fargs) do
        table.insert(values, value)
    end
    safe_find(get_pickers().properties({ values = values }), "No properties found")
end

--- @command :Vault yesterday [[
--- Opens a picker with the statuses
--- @command ]]
--- @param args vim.api.keyset.create_user_command.command_args
--- @return nil
function callbacks.open_notes_status_picker(args)
    local fargs = args.fargs
    if next(fargs) == nil then
        fargs = { "status" }
    end
    --TODO: Moved statuse to the frontmatter. Need to update this
    local tags = require("vault.tags")()
    local statuses = {}
    for _, tag in pairs(tags.map) do
        for _, farg in ipairs(fargs) do
            if tag.data.name == farg then
                table.insert(statuses, tag.data.name)
            end
        end
    end
    if next(statuses) == nil then
        log.info("No matching status tags found")
        return
    end
    local notes = require("vault.notes")():filter({ "tags", statuses, {}, "startswith", "all" })

    local picker = require("telescope._extensions.vault.pickers").notes({ notes = notes })
    if picker then
        picker:find()
    end
end

--- vault.FleetingNote
--- Opens a fleeting note
--- @param args vim.api.keyset.create_user_command.command_args
--- @return nil
function callbacks.open_fleeting_note_popup(args)
    local FleetingNote = require("vault.popups.fleeting_note")
    local content = table.concat(args.fargs, " ")
    if content == "" then
        content = nil
    end
    FleetingNote(content)
end

--- vault.Orphans
--- Opens a picker with orphans
--- @return nil
function callbacks.open_orphans_picker()
    safe_find(get_pickers().orphans(), "No orphan notes found")
end

--- vault.Linked
--- Opens a picker with linked notes
--- @return nil
function callbacks.open_linked_picker()
    safe_find(get_pickers().linked(), "No linked notes found")
end

--- Opens a live grep picker with fuzzy search
--- @param args vim.api.keyset.create_user_command.command_args
--- @return nil
function callbacks.open_live_grep_picker(args)
    local query = ""
    if args.range and args.range > 0 then
        -- Visual selection: use selected text as initial query
        local lines = vim.api.nvim_buf_get_lines(0, args.line1 - 1, args.line2, false)
        query = vim.trim(lines[1] or "")
    elseif args.fargs and #args.fargs > 0 then
        query = table.concat(args.fargs, " ")
    end
    -- live_grep opens the picker directly (returns nil), no :find() needed
    require("telescope._extensions.vault.pickers.grep")({ query = query })
end

--- vault.Yesterday
--- Opens the yesterday's journal note
--- @return nil
function callbacks.yesterday()
    local journal = require("vault.journal")
    local yesterday = os.date("%Y-%m-%d", os.time() - 60 * 60 * 24)
    local path, created = journal.ensure(yesterday)
    if type(path) ~= "string" then
        log.error(
            "Journal daily note path not configured (configure .obsidian/daily-notes.json or dirs.journal.daily)"
        )
        return
    end
    if created then
        log.info("Initializing yesterday's journal note")
    end
    vim.cmd("e " .. vim.fn.fnameescape(path))
end

--- vault.NoteRename
--- Rename a note title and update all the links to that note
--- ```vim
--- :Vault note rename <new_title>
--- ```
---
--- ```lua
--- require("vault.notes.note")(vim.fn.expand("%:p")):rename(new_path)
--- ```
--- @param args vim.api.keyset.create_user_command.command_args
--- @return nil
function callbacks.rename(args)
    local ok_note, note = pcall(require("vault.notes.note"), vim.fn.expand("%:p"))
    if not ok_note then
        log.warn("Current buffer is not a vault note")
        return
    end
    local new_slug
    if next(args.fargs) == nil then
        -- Interactive rename: prompt for new slug
        new_slug = vim.fn.input("Rename to: ", note.data.slug)
        if not new_slug or new_slug == "" or new_slug == note.data.slug then
            log.info("Rename cancelled")
            return
        end
    else
        new_slug = table.concat(args.fargs, " ")
    end
    if new_slug == "" then
        return
    end
    local new_path = require("vault.utils").slug_to_path(new_slug)

    local ok, err = pcall(function()
        note:move(new_path)
    end)
    if not ok then
        log.error("Failed to move note: %s", tostring(err):match("[^\n]+"))
        return
    end

    vim.cmd("bdelete!")
    note:edit()
end

--- vault.ConflictsReview
--- Open a resolver queue from a markdown conflict report.
--- ```vim
--- :Vault conflicts review reports/references-conflicts-review.md
--- ```
--- @param args vim.api.keyset.create_user_command.command_args
function callbacks.conflicts_review(args)
    local root = args.fargs and args.fargs[1] or ""
    if root == "" then
        local current = vim.fn.expand("%:p")
        if type(current) == "string" and current ~= "" and current:match("%.md$") then
            root = vim.fn.fnamemodify(current, ":h")
        else
            root = require("vault.config").options.root
        end
    end
    if type(root) ~= "string" or root == "" then
        log.warn("Provide a conflict review root")
        return
    end
    local abs_root = root
    if not abs_root:match("^/") then
        abs_root = require("vault.utils").relpath_to_path(root)
    end
    abs_root = vim.fn.fnamemodify(abs_root, ":p")
    if vim.fn.isdirectory(abs_root) == 0 then
        log.warn("Conflict review directory not found: %s", abs_root)
        return
    end
    require("vault.conflicts").review(abs_root)
end

--- vault.DuplicatesReview
--- Review duplicate note candidates through a diff-first A/B UI.
--- ```vim
--- :Vault duplicates review References
--- :Vault duplicates review vault
--- :Vault duplicates review dir References
--- :Vault duplicates review tags test
--- :Vault duplicates review kind metadata
--- :Vault duplicates review dir Inbox kind body
--- ```
---@param args string[]
---@param start_index integer
---@param stop_words table<string, boolean>
---@return string, integer
local function collect_clause_text(args, start_index, stop_words)
    local parts = {}
    local index = start_index
    while index <= #args and not stop_words[args[index]] do
        parts[#parts + 1] = args[index]
        index = index + 1
    end
    return table.concat(parts, " "), index
end

---@class vault.commands.DuplicatesClauses
---@field dirs vault.relpath[]
---@field tags string[]
---@field kind_tokens vault.duplicates.Kind[]

---@param args string[]
---@return vault.path|nil, vault.commands.DuplicatesClauses|nil
local function parse_duplicates_review_args(args)
    local stop_words = {
        dir = true,
        tags = true,
        kind = true,
        root = true,
        vault = true,
    }
    local root = nil
    local dirs = {}
    local tags = {}
    local kind_tokens = {}
    local index = 1

    while index <= #args do
        local token = args[index]
        if token == "vault" then
            root = require("vault.config").options.root
            index = index + 1
        elseif token == "root" then
            local value
            value, index = collect_clause_text(args, index + 1, stop_words)
            if value == "" then
                return nil, nil
            end
            root = value
        elseif token == "dir" then
            local value
            value, index = collect_clause_text(args, index + 1, stop_words)
            if value == "" then
                return nil, nil
            end
            dirs[#dirs + 1] = value
        elseif token == "tags" then
            index = index + 1
            while index <= #args and not stop_words[args[index]] do
                tags[#tags + 1] = args[index]
                index = index + 1
            end
            if vim.tbl_isempty(tags) then
                return nil, nil
            end
        elseif token == "kind" then
            index = index + 1
            while index <= #args and not stop_words[args[index]] do
                kind_tokens[#kind_tokens + 1] = args[index]
                index = index + 1
            end
            if vim.tbl_isempty(kind_tokens) then
                return nil, nil
            end
        elseif index == 1 then
            root = table.concat(vim.list_slice(args, index), " ")
            index = #args + 1
        else
            log.warn("Unknown duplicates review filter: %s", token)
            return nil, nil
        end
    end

    return root,
        {
            dirs = dirs,
            tags = tags,
            kind_tokens = kind_tokens,
        }
end

local DUPLICATES_CLAUSE_KEYWORDS = { "vault", "root", "dir", "tags", "kind", "preset" }

---@param root vault.path|nil
---@param _clauses vault.commands.DuplicatesClauses
---@return vault.path
local function resolve_duplicates_root(root, _clauses)
    if root ~= nil and root ~= "" then
        return root
    end
    return require("vault.config").options.root
end

---@param clauses vault.commands.DuplicatesClauses
---@param path_index table<string, table>
---@return table<string, table<vault.path, boolean>>
local function build_duplicates_path_filters(clauses, path_index)
    local path_filters = {}
    if not vim.tbl_isempty(clauses.dirs) then
        local dir_paths = {}
        for _, dir in ipairs(clauses.dirs) do
            for _, entry in pairs(path_index) do
                local path = type(entry) == "table" and entry.path or nil
                if type(path) == "string" then
                    local relpath = require("vault.utils").path_to_relpath(path)
                    if relpath == dir or relpath:sub(1, #dir + 1) == (dir .. "/") then
                        dir_paths[path] = true
                    end
                end
            end
        end
        path_filters.dirs = dir_paths
    end

    if not vim.tbl_isempty(clauses.tags) then
        local tag_paths = {}
        local notes = require("vault.notes")():filter({
            search_term = "tags",
            include = clauses.tags,
            exclude = {},
            match_opt = "exact",
            mode = "any",
        })
        for _, note in pairs(notes.map or {}) do
            tag_paths[note.data.path] = true
        end
        path_filters.tags = tag_paths
    end
    return path_filters
end

---@class vault.commands.DuplicatesFilterSpec
---@field dirs vault.relpath[]
---@field tags string[]
---@field kinds vault.duplicates.Kind[]
---@field related string[]

---@param clauses vault.commands.DuplicatesClauses
---@param _kinds vault.duplicates.Kind[]|nil
---@param related string[]|nil
---@return vault.commands.DuplicatesFilterSpec
local function build_duplicates_filter_spec(clauses, _kinds, related)
    table.sort(clauses.dirs)
    table.sort(clauses.tags)
    table.sort(clauses.kind_tokens)
    related = related or {}
    table.sort(related)
    return {
        dirs = vim.deepcopy(clauses.dirs),
        tags = vim.deepcopy(clauses.tags),
        kinds = vim.deepcopy(clauses.kind_tokens),
        related = vim.deepcopy(related),
    }
end

---@param root vault.path
---@param clauses vault.commands.DuplicatesClauses
---@param kind_tokens vault.duplicates.Kind[]
---@return vault.path, table<string, table<vault.path, boolean>>, table<string, boolean>|nil
local function build_review_request(root, clauses, kind_tokens)
    local path_index = require("vault.scanner").paths()
    local path_filters = build_duplicates_path_filters(clauses, path_index)

    local kinds = nil
    if not vim.tbl_isempty(kind_tokens) then
        local kind_err
        kinds, kind_err = require("vault.duplicates").resolve_kind_filter(kind_tokens)
        if not kinds then
            error(kind_err or "Unknown duplicate kind filter")
        end
    end

    return root, path_filters, kinds
end

---@param preset_name string
---@return boolean
local function run_duplicate_review_preset(preset_name)
    local duplicates = require("vault.duplicates")
    local preset, err = duplicates.resolve_preset(preset_name)
    if not preset then
        log.warn("%s", tostring(err or "Unknown duplicate preset"))
        return false
    end

    local root = resolve_duplicates_root(preset.root, {
        dirs = vim.deepcopy(preset.dirs),
        tags = vim.deepcopy(preset.tags),
        kind_tokens = vim.deepcopy(preset.kind_tokens),
    })
    local ok, resolved_root, path_filters, kinds = pcall(build_review_request, root, {
        dirs = vim.deepcopy(preset.dirs),
        tags = vim.deepcopy(preset.tags),
        kind_tokens = vim.deepcopy(preset.kind_tokens),
    }, preset.kind_tokens)
    if not ok then
        log.warn("%s", tostring(resolved_root))
        return false
    end

    duplicates.review(resolved_root, {
        path_filters = next(path_filters) and path_filters or nil,
        kinds = kinds,
        filter_spec = {
            preset = preset.name,
            dirs = vim.deepcopy(preset.dirs),
            tags = vim.deepcopy(preset.tags),
            kinds = vim.deepcopy(preset.kind_tokens),
            related = {},
        },
    })
    return true
end

---@param values string[]
---@return string[]
local function uniq_sorted(values)
    local seen = {}
    local result = {}
    for _, value in ipairs(values or {}) do
        if type(value) == "string" and value ~= "" and not seen[value] then
            seen[value] = true
            result[#result + 1] = value
        end
    end
    table.sort(result)
    return result
end

---@param prefix string
---@param line string|nil
---@return string[]
complete_duplicates_review = function(prefix, line)
    line = line or ""
    prefix = prefix or ""

    local keyword_matches = vim.tbl_filter(function(name)
        return name:find(prefix, 1, true) == 1
    end, DUPLICATES_CLAUSE_KEYWORDS)

    local args_text = line:match("duplicates%s+review%s*(.*)$") or ""
    local dirs = completions.dirs(nil, line, nil) or {}
    if args_text == "" then
        return uniq_sorted(vim.list_extend(vim.deepcopy(keyword_matches), dirs))
    end

    local ends_with_space = line:match("%s$") ~= nil
    local args = vim.split(vim.trim(args_text), " ", { trimempty = true })
    local clause = nil
    local value_count = 0
    for _, token in ipairs(args) do
        if token == "root" or token == "dir" or token == "tags" or token == "kind" then
            clause = token
            value_count = 0
        elseif token ~= "vault" then
            value_count = value_count + 1
        end
    end

    local tags = completions.tags(nil, line, nil) or {}
    local kinds = vim.tbl_filter(function(name)
        return name:find(prefix, 1, true) == 1
    end, require("vault.duplicates").kind_filter_names())

    if clause == "root" or clause == "dir" then
        if not ends_with_space or value_count == 0 then
            return uniq_sorted(dirs)
        end
        return uniq_sorted(vim.list_extend(vim.deepcopy(keyword_matches), dirs))
    end

    if clause == "tags" then
        if not ends_with_space or value_count == 0 then
            return uniq_sorted(tags)
        end
        return uniq_sorted(vim.list_extend(vim.deepcopy(keyword_matches), tags))
    end

    if clause == "kind" then
        if not ends_with_space or value_count == 0 then
            return uniq_sorted(kinds)
        end
        return uniq_sorted(vim.list_extend(vim.deepcopy(keyword_matches), kinds))
    end
    return uniq_sorted(vim.list_extend(vim.deepcopy(keyword_matches), dirs))
end

---@param prefix string
---@param line string|nil
---@return string[]
complete_duplicates_related = function(prefix, line)
    line = line or ""
    prefix = prefix or ""

    local duplicates = require("vault.duplicates")
    local bucket_matches = vim.tbl_filter(function(name)
        return name:find(prefix, 1, true) == 1
    end, duplicates.related_filter_names())
    local keyword_matches = vim.tbl_filter(function(name)
        return name:find(prefix, 1, true) == 1
    end, DUPLICATES_CLAUSE_KEYWORDS)

    local args_text = line:match("duplicates%s+related%s*(.*)$") or ""
    local dirs = completions.dirs(nil, line, nil) or {}
    if args_text == "" then
        return uniq_sorted(
            vim.list_extend(vim.list_extend(vim.deepcopy(bucket_matches), keyword_matches), dirs)
        )
    end

    local ends_with_space = line:match("%s$") ~= nil
    local args = vim.split(vim.trim(args_text), " ", { trimempty = true })
    local clause = nil
    local value_count = 0
    local first_is_bucket = duplicates.resolve_related_filter({ args[1] }) ~= nil
    for index, token in ipairs(args) do
        if token == "root" or token == "dir" or token == "tags" or token == "kind" then
            clause = token
            value_count = 0
        elseif token ~= "vault" and not (index == 1 and first_is_bucket) then
            value_count = value_count + 1
        end
    end

    local tags = completions.tags(nil, line, nil) or {}
    local kinds = vim.tbl_filter(function(name)
        return name:find(prefix, 1, true) == 1
    end, duplicates.kind_filter_names())

    if clause == "root" or clause == "dir" then
        if not ends_with_space or value_count == 0 then
            return uniq_sorted(dirs)
        end
        return uniq_sorted(vim.list_extend(vim.deepcopy(keyword_matches), dirs))
    end
    if clause == "tags" then
        if not ends_with_space or value_count == 0 then
            return uniq_sorted(tags)
        end
        return uniq_sorted(vim.list_extend(vim.deepcopy(keyword_matches), tags))
    end
    if clause == "kind" then
        if not ends_with_space or value_count == 0 then
            return uniq_sorted(kinds)
        end
        return uniq_sorted(vim.list_extend(vim.deepcopy(keyword_matches), kinds))
    end

    if #args == 0 or (#args == 1 and not ends_with_space) then
        return uniq_sorted(
            vim.list_extend(vim.list_extend(vim.deepcopy(bucket_matches), keyword_matches), dirs)
        )
    end
    return uniq_sorted(
        vim.list_extend(vim.list_extend(vim.deepcopy(bucket_matches), keyword_matches), dirs)
    )
end

---@param fargs string[]
---@param usage string
---@return string|nil, table|nil
local function parse_duplicate_clauses_or_warn(fargs, usage)
    local root, clauses = parse_duplicates_review_args(fargs)
    if root == nil and clauses == nil and #fargs > 0 then
        log.warn("%s", usage)
        return nil, nil
    end
    return root, clauses or { dirs = {}, tags = {}, kind_tokens = {} }
end

--- @param args vim.api.keyset.create_user_command.command_args
function callbacks.duplicates_review(args)
    local fargs = args.fargs or {}
    local root, clauses = parse_duplicate_clauses_or_warn(
        fargs,
        "Usage: :Vault duplicates review [vault|root <dir>|dir <dir>|tags <tag...>|kind <set...>]"
    )
    if not clauses then
        return
    end
    root = resolve_duplicates_root(root, clauses)

    local ok, resolved_root, path_filters, kinds =
        pcall(build_review_request, root, clauses, clauses.kind_tokens)
    if not ok then
        log.warn("%s", tostring(resolved_root))
        return
    end

    require("vault.duplicates").review(resolved_root, {
        path_filters = next(path_filters) and path_filters or nil,
        kinds = kinds,
        filter_spec = build_duplicates_filter_spec(clauses),
    })
end

callbacks.complete_duplicates_review = complete_duplicates_review

--- @param args vim.api.keyset.create_user_command.command_args
function callbacks.duplicates_review_preset(args)
    local preset_name = args.fargs and args.fargs[1] or nil
    if preset_name and preset_name ~= "" then
        run_duplicate_review_preset(preset_name)
        return
    end
    safe_find(
        get_pickers().duplicate_presets({
            presets = require("vault.duplicates").presets(),
            on_select = function(entry)
                run_duplicate_review_preset(entry.name)
            end,
        }),
        "No duplicate review presets configured"
    )
end

--- @param args vim.api.keyset.create_user_command.command_args
function callbacks.duplicates_related(args)
    local fargs = vim.deepcopy(args.fargs or {})
    local related_tokens = {}
    if #fargs > 0 then
        local related = require("vault.duplicates")
        local buckets, _ = related.resolve_related_filter({ fargs[1] })
        if buckets then
            related_tokens = { table.remove(fargs, 1) }
        end
    end

    local root, clauses = parse_duplicate_clauses_or_warn(
        fargs,
        "Usage: :Vault duplicates related [likely|maybe|weak] [vault|root <dir>|dir <dir>|tags <tag...>|kind <set...>]"
    )
    if not clauses then
        return
    end
    if root == nil or root == "" then
        root = require("vault.config").options.root
    end

    local path_index = require("vault.scanner").paths()
    local path_filters = build_duplicates_path_filters(clauses, path_index)

    local kinds = nil
    if not vim.tbl_isempty(clauses.kind_tokens) then
        local kind_err
        kinds, kind_err = require("vault.duplicates").resolve_kind_filter(clauses.kind_tokens)
        if not kinds then
            log.warn("%s", tostring(kind_err or "Unknown duplicate kind filter"))
            return
        end
    end

    local related_buckets = nil
    if not vim.tbl_isempty(related_tokens) then
        local related_err
        related_buckets, related_err =
            require("vault.duplicates").resolve_related_filter(related_tokens)
        if not related_buckets then
            log.warn("%s", tostring(related_err or "Unknown related duplicate filter"))
            return
        end
    end

    require("vault.duplicates").review_related(root, {
        path_filters = next(path_filters) and path_filters or nil,
        kinds = kinds,
        related_buckets = related_buckets,
        filter_spec = build_duplicates_filter_spec(clauses, nil, related_tokens),
    })
end

callbacks.complete_duplicates_related = complete_duplicates_related

--- vault.NoteInlinks
--- Opens a picker with the notes where current note is mentioned
--- ```vim
--- :Vault note inlinks
--- ```
---
--- ```lua
--- pickers.notes({}, nil, inlinks)
--- ```
--- @return nil
function callbacks.note_inlinks_picker()
    local ok, note = pcall(require("vault.notes.note"), vim.fn.expand("%:p"))
    if not ok or note == nil then
        log.warn("Current buffer is not a vault note")
        return
    end
    local inlinks = note.data.inlinks or {}
    if next(inlinks) == nil then
        log.info("No inlinks")
        return
    end
    local inlink_slugs = vim.tbl_keys(inlinks)
    safe_find(
        get_pickers().notes({ notes = require("vault.notes")():filter(inlink_slugs) }),
        "No inlink notes found"
    )
end

--- vault.NoteOutlinks
--- Opens a picker with the notes that current note links to
--- ```vim
--- :Vault note outlinks
--- ```
---
--- ```lua
--- pickers.notes({ notes = require('vault.notes')():with_slugs(vim.tbl_keys(outlinks)) }):find()
--- ```
--- @return nil
function callbacks.note_outlinks_picker()
    local ok, note = pcall(require("vault.notes.note"), vim.fn.expand("%:p"))
    if not ok or note == nil then
        log.warn("Current buffer is not a vault note")
        return
    end
    local outlinks = note.data.outlinks or {}
    if next(outlinks) == nil then
        log.info("No outlinks")
        return
    end
    local target_slugs = {}
    for _, outlink in pairs(outlinks) do
        if outlink.data.target and outlink.data.target ~= "" then
            table.insert(target_slugs, outlink.data.target)
        end
    end
    safe_find(
        get_pickers().notes({ notes = require("vault.notes")():filter(target_slugs) }),
        "No outlink notes found"
    )
end

--- vault.NoteTags
--- Opens a picker with the notes that have the tags
--- ```vim
--- :Vault note tags <range>
--- ```
---
--- ```lua
--- ```
--- @param args vim.api.keyset.create_user_command.command_args
function callbacks.note_tags_picker(args)
    local ok, note = pcall(require("vault.notes.note"), vim.fn.expand("%:p"))
    if not ok or note == nil then
        log.warn("Current buffer is not a vault note")
        return
    end
    if next(note.data.tags) == nil then
        log.info("No tags")
        return
    end

    --- @type vault.slug[]
    local slugs = {}

    if next(args.fargs) == nil then
        for _, tag in pairs(note.data.tags) do
            -- table.insert(slugs, vim.tbl_keys(tag.data.sources))
            for slug, _ in pairs(tag.data.sources) do
                table.insert(slugs, slug)
            end
        end
    elseif args.fargs[1] then
        for _, tag in pairs(note.data.tags) do
            if tag.data.name == args.fargs[1] then
                for slug, _ in pairs(tag.data.sources) do
                    table.insert(slugs, slug)
                end
            end
        end
    end
    -- -- if range is provided, then get the tags from the range
    -- if args.range == 0 then
    -- end
    -- if args.range == 2 then
    --     error("Not implemented")
    -- end
    safe_find(
        get_pickers().notes({ notes = require("vault.notes")():filter(slugs) }),
        "No notes found for tags"
    )
end

--- Create a new note from the selected text, and replace the selected text with a link to the new note
--- @param _args vim.api.keyset.create_user_command.command_args
function callbacks.note_from_selected_text(_args)
    local start_pos = vim.api.nvim_buf_get_mark(0, "<")
    local end_pos = vim.api.nvim_buf_get_mark(0, ">")

    -- Validate marks
    if start_pos[1] == 0 or end_pos[1] == 0 then
        log.warn("No selection found")
        return
    end

    -- Adjust for 0-based indexing for API calls
    local row1, col1 = start_pos[1] - 1, start_pos[2]
    local row2, col2 = end_pos[1] - 1, end_pos[2]

    -- Handle visual line mode or block mode if necessary, but assuming characterwise for now
    -- In visual line mode, col1 is 0 and col2 is 2147483647
    if col2 == 2147483647 then
        local line_content = vim.api.nvim_buf_get_lines(0, row2, row2 + 1, false)[1]
        if not line_content then
            log.warn("Invalid selection range")
            return
        end
        col2 = #line_content
    else
        -- Include the last character
        col2 = col2 + 1
    end

    local lines = vim.api.nvim_buf_get_text(0, row1, col1, row2, col2, {})
    if next(lines) == nil then
        log.warn("Invalid text")
        return
    end

    --- @type string
    local new_note_slug = vim.fn.input("New note slug: ")
    if not new_note_slug or new_note_slug == "" then
        log.warn("Invalid slug")
        return
    end

    -- Optional: Make UUID optional via config? For now keeping it but maybe user wants control
    --- @type number
    local uuid = require("vault.utils").generate_uuid()
    new_note_slug = uuid .. " " .. new_note_slug

    --- @type vault.path
    local new_note_path = require("vault.notes.paths").for_slug(new_note_slug)
    if vim.fn.filereadable(new_note_path) == 1 then
        log.warn("File already exists: %s", new_note_path)
        return
    end

    --- @type vault.Wikilink.Data.raw
    local link = "[[" .. new_note_slug .. "]]"

    -- Replace text with link
    vim.api.nvim_buf_set_text(0, row1, col1, row2, col2, { link })

    local new_note_content = table.concat(lines, "\n")
    local note = require("vault.notes.note")(new_note_path)
    note.data.content = new_note_content
    note:write()
    -- renew the note to update marksman cache
    if vim.fn.executable("marksman") == 1 then
        vim.cmd("LspRestart marksman")
    end
end

--- vault.NoteProperties
--- Opens a picker with the properties of the note
--- ```vim
--- :Vault note properties
--- :Vault note properties <property_name>
--- :Vault note properties <property_name> <property_name>
--- ```
--- @param args vim.api.keyset.create_user_command.command_args
--- @return nil
function callbacks.open_note_properties_picker(args)
    local fargs = args.fargs
    if next(fargs) == nil then
        safe_find(get_pickers().properties(), "No properties found")
        return
    end
    local values = {}
    for _, value in ipairs(fargs) do
        table.insert(values, value)
    end
    safe_find(get_pickers().properties({ values = values }), "No properties found")
end

--- VaultNoteByDir
--- Opens a picker with notes by directory
--- @param args vim.api.keyset.create_user_command.command_args
function callbacks.open_note_by_dir_picker(args)
    local fargs = args.fargs
    if next(fargs) == nil then
        -- return notes in the root directory (no subdirectory in relpath)
        local notes = require("vault.notes")()
        local root_notes = {}
        for id, note in pairs(notes.map) do
            if not note.data.relpath:find("/") then
                root_notes[id] = note
            end
        end
        notes.map = root_notes
        local picker = require("telescope._extensions.vault.pickers").notes({ notes = notes })
        if picker then
            picker:find()
        end
        return
    end
    local notes = require("vault.notes")():filter("relpath", fargs[1], "startswith", false)
    safe_find(get_pickers().notes({ notes = notes }), "No notes found in directory: " .. fargs[1])
end

--- @param args vim.api.keyset.create_user_command.command_args
function callbacks.note(args)
    local fargs = args.fargs
    -- if no arguments, then open a picker
    if next(fargs) == nil then
        safe_find(get_pickers().notes(), "No notes found")
        return
    elseif #fargs == 1 then
        -- Apply method to the current buffer's note
        local ok, note = pcall(require("vault.notes.note"), vim.fn.expand("%:p"))
        if not ok or note == nil then
            log.warn("No note found in current buffer")
            return
        end
        local method = fargs[1]
        if type(note[method]) ~= "function" then
            log.warn("Unknown note method: %s", method)
            return
        end
        local output = note[method](note)
        if output then
            log.info("%s", tostring(output))
        end
        return
    end
    local method = fargs[1]
    local slug = fargs[2]
    local arguments = {}
    for i = 3, #fargs do
        table.insert(arguments, fargs[i])
    end
    local note = require("vault.notes")().map[slug]
    if not note then
        log.warn("Note not found: %s", tostring(slug))
        return
    end
    if not note[method] then
        log.warn("Unknown method: %s", tostring(method))
        return
    end
    table.insert(arguments, 1, note)
    -- Apply the method to the note
    local ok, output = pcall(note[method], table.unpack(arguments))
    if not ok then
        log.error("Error: %s", tostring(output):match("[^\n]+"))
        return
    end
    if output then
        --- @class notify.Options
        local notify_opts = {
            timeout = 1000,
            title = note.data.stem,
        }
        vim.notify(output, vim.log.levels.INFO, notify_opts)
    end
end

local function construct_notes_picker_args(input)
    local args = {}

    -- Check if the first argument is a valid preset
    -- if no preset is provided, use filter directly
    if vim.tbl_contains(completions.vault_notes_presets(), input[1]) then
        args[1] = input[1]
    end

    -- Check if the second argument is a valid key
    if vim.tbl_contains(completions.note_data_keys(), input[2]) then
        input[2] = input[2] or error("Invalid key: " .. input[2])
        args[2] = input[2] -- key - key to filter by (tags, title, basename, path, type, status, date, children)
        args[3] = input[3] -- include - table of values to include
        args[4] = input[4] -- exclude - table of values to exclude
        args[5] = input[5] -- match_opt - exact, contains, startswith
        args[6] = input[6] -- match_type - any, all

        args = { input[2], input[3], input[4], input[5], input[6] }
    end
    if #args == 0 then
        safe_find(get_pickers().notes(), "No notes found")
    elseif #args == 1 then
        if args[1] ~= "by" then
            local preset_pickers = {
                linked = "linked",
                orphans = "orphans",
                leaves = "leaves",
                internals = "internals",
                dangling = "with_outlinks_unresolved",
                resolved = "with_outlinks_resolved_only",
            }
            local picker_key = preset_pickers[args[1]]
            if picker_key then
                safe_find(get_pickers()[picker_key](), "No notes found for preset: " .. args[1])
                return
            end

            local notes = require("vault.notes")()
            local preset = notes[args[1]]
            if type(preset) == "function" then
                preset = preset(notes)
            end
            safe_find(
                get_pickers().notes({ notes = preset }),
                "No notes found for preset: " .. args[1]
            )
        elseif args[1] == "by" then
            log.warn("Need further arguments")
        end
    elseif #args == 2 then
        log.warn("Need further arguments")
        return
    elseif #args == 3 then
        if type(args[3]) ~= "table" then
            args[3] = { args[3] }
        end
        safe_find(get_pickers().notes({
            notes = require("vault.notes")({ args[2], args[3], {}, "startswith", "all" }),
        }))
    elseif #args == 4 then
        if type(args[3]) ~= "table" then
            args[3] = { args[3] }
        end
        if type(args[4]) ~= "table" then
            args[4] = { args[4] }
        end
        safe_find(get_pickers().notes({
            notes = require("vault.notes")({ args[2], args[3], args[4], "startswith", "all" }),
        }))
    elseif #args == 5 then
        if type(args[3]) ~= "table" then
            args[3] = { args[3] }
        end
        if type(args[4]) ~= "table" then
            args[4] = { args[4] }
        end
        safe_find(get_pickers().notes({
            notes = require("vault.notes")({ args[2], args[3], args[4], args[5], "all" }),
        }))
    elseif #args == 6 then
        if type(args[3]) ~= "table" then
            args[3] = { args[3] }
        end
        if type(args[4]) ~= "table" then
            args[4] = { args[4] }
        end
        safe_find(get_pickers().notes({
            notes = require("vault.notes")({ args[2], args[3], args[4], args[5], args[6] }),
        }))
    end
end

function callbacks.notes(args)
    if next(args.fargs) == nil then
        safe_find(get_pickers().notes(), "No notes found")
        return
    end
    construct_notes_picker_args(args.fargs)
end

function callbacks.actions()
    safe_find(get_pickers().tasks(), "No tasks found")
end

function callbacks.tasks_new(args)
    local name = table.concat(args, " ")
    local path = require("vault.tasks.notes").create(name)
    if not path then
        return
    end
    vim.cmd("edit " .. vim.fn.fnameescape(path))
end

function callbacks.tasks_status(args)
    local task_notes = require("vault.tasks.notes")
    local path = task_notes.current_task_path()
    if not path then
        log.warn("Current buffer is not a task note in Tasks/")
        return
    end
    local task = task_notes.read_task(path)
    if not task then
        log.warn("Failed to parse task frontmatter")
        return
    end
    local target = table.concat(args or {}, " ")
    if target == "" then
        local next_states = task_notes.next_statuses(task.status)
        local msg = "status=" .. task.status
        if #next_states > 0 then
            msg = msg .. " | next=" .. table.concat(next_states, ", ")
        end
        log.info("%s", msg)
        return
    end
    local ok, err = task_notes.set_status(path, target)
    if not ok then
        log.warn("%s", err or "Failed to update status")
        return
    end
    log.info("Task status updated: %s", target)
end

function callbacks.tasks_pick_next()
    local task_notes = require("vault.tasks.notes")
    local candidates = task_notes.pick_candidates()
    if #candidates == 0 then
        log.info("No unblocked active tasks found")
        return
    end
    local top = candidates[1]
    vim.cmd("edit " .. vim.fn.fnameescape(top.path))
    log.info("Picked next: %s (%s, %s)", top.title, top.priority, top.status)
end

function callbacks.tasks_promote(args)
    local task_notes = require("vault.tasks.notes")
    local current = vim.api.nvim_get_current_line()
    local indent = current:match("^(%s*)") or ""
    local source = table.concat(args or {}, " ")
    if source == "" then
        source = current
    end
    local name = source
    name = name:gsub("^%s*[-*]%s*%[[^%]]*%]%s*", "")
    name = name:gsub("^%s*[-*]%s*", "")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then
        log.warn("Nothing to promote. Provide text or place cursor on a non-empty line.")
        return
    end
    local path = task_notes.create(name)
    if not path then
        return
    end
    local stem = vim.fn.fnamemodify(path, ":t:r")
    vim.api.nvim_set_current_line(string.format("%s- [[%s]]", indent, stem))
    log.info("Promoted to task: %s", stem)
end

function callbacks.tasks_list()
    local notes = require("vault.notes")():filter(
        "relpath",
        require("vault.tasks.notes").tasks_dir_rel() .. "/",
        "startswith",
        false
    )
    safe_find(get_pickers().notes({ notes = notes }), "No tasks found")
end

function callbacks.tasks_kanban()
    local Bases = require("vault.bases")
    local base = Bases():get("Tasks Kanban")
    if not base then
        log.error("Base not found: Tasks Kanban")
        return
    end

    local cfg = require("vault.config").options or {}
    local task_cfg = cfg.task_notes or {}
    local group_values = type(task_cfg.status_order) == "table" and task_cfg.status_order or nil
    local card_sort = type(task_cfg.kanban_sort) == "table" and task_cfg.kanban_sort or nil
    local empty_columns = type(task_cfg.kanban_empty_columns) == "string"
            and task_cfg.kanban_empty_columns
        or nil

    require("vault.views.kanban").open({
        base = base,
        filter_desc = "base:Tasks Kanban",
        group_values = group_values,
        card_sort = card_sort,
        empty_columns = empty_columns,
    })
end

function callbacks.tasks_backlog()
    callbacks.api({ fargs = { "process", "base", "Tasks Backlog" } })
end

function callbacks.tasks_doctor(args)
    local fix = false
    for _, arg in ipairs(args or {}) do
        if arg == "fix" or arg == "--fix" then
            fix = true
        end
    end

    local report = require("vault.tasks.notes").doctor({ fix = fix })
    local total = #report.issues
    if total == 0 then
        log.info("Tasks doctor: %d scanned, no issues", report.scanned)
        return
    end

    local by_kind = {}
    for _, issue in ipairs(report.issues) do
        by_kind[issue.kind] = (by_kind[issue.kind] or 0) + 1
    end

    local parts = {
        string.format("Tasks doctor: %d scanned", report.scanned),
        string.format("%d issues", total),
    }
    if report.fixed > 0 then
        table.insert(parts, string.format("%d fixed", report.fixed))
    end
    log.warn(table.concat(parts, ", "))

    for kind, n in pairs(by_kind) do
        log.warn("  %s: %d", kind, n)
    end

    local preview = math.min(10, total)
    for i = 1, preview do
        local issue = report.issues[i]
        log.warn("  - %s [%s]", issue.stem, issue.kind)
    end
    if total > preview then
        log.warn("  ... and %d more", total - preview)
    end
end

function callbacks.vault_doctor(args)
    local fix = false
    for _, arg in ipairs(args or {}) do
        if arg == "fix" or arg == "--fix" then
            fix = true
        end
    end

    local typecheck = require("vault.typecheck")
    local dr
    if fix then
        dr = typecheck.doctor_fix()
    else
        dr = typecheck.doctor()
    end

    local total_errors = #dr.errors
    local error_file_count = 0
    for _ in pairs(dr.error_files) do
        error_file_count = error_file_count + 1
    end

    if total_errors == 0 then
        log.info(
            "Vault doctor: %d scanned, no type errors. %d untyped notes.",
            dr.scanned,
            #dr.untyped
        )
        return
    end

    -- Summary
    log.warn(
        "Vault doctor: %d scanned. %d errors in %d files. %d untyped notes.",
        dr.scanned,
        total_errors,
        error_file_count,
        #dr.untyped
    )

    -- Quickfix list
    ---@type table[]
    local qf_items = {}
    for _, err in ipairs(dr.errors) do
        table.insert(qf_items, {
            filename = err.path,
            lnum = (err.lnum or 0) + 1, -- quickfix uses 1-indexed
            col = 1,
            text = err.field .. ": " .. err.message,
            type = "E",
        })
    end
    vim.fn.setqflist(qf_items, "r")
    vim.fn.setqflist({}, "a", { title = "Vault Doctor" })
    log.info("Results in quickfix (:copen)")
end

function callbacks.tasks_recur_preview()
    local task_notes = require("vault.tasks.notes")
    local path = task_notes.current_task_path()
    if not path then
        log.warn("Current buffer is not a task note in Tasks/")
        return
    end
    local due, err = task_notes.recur_preview(path)
    if not due then
        log.warn("%s", err or "Recurring preview failed")
        return
    end
    log.info("Recurring preview: next due %s", due)
end

function callbacks.tasks_recur_now()
    local task_notes = require("vault.tasks.notes")
    local path = task_notes.current_task_path()
    if not path then
        log.warn("Current buffer is not a task note in Tasks/")
        return
    end
    local created, err = task_notes.recur_spawn(path, true)
    if not created then
        log.warn("%s", err or "Recurring spawn failed")
        return
    end
    local stem = vim.fn.fnamemodify(created, ":t:r")
    log.info("Recurring spawned: %s", stem)
end

function callbacks.tasks_recur_sweep()
    local task_notes = require("vault.tasks.notes")
    local scanned, spawned = task_notes.recur_sweep()
    log.info("Recurring sweep: %d scanned, %d spawned", scanned, spawned)
end

-- Commands for the plugin
local M = {
    ["Vault"] = {
        callback = callbacks.api,
        opts = {
            desc = "Vault subcommand dispatcher — :Vault <subcommand> [args]",
            complete = completions.api,
            nargs = "*",
            range = true,
        },
    },
}

for command, opts in pairs(M) do
    local assign, err = pcall(vim.api.nvim_create_user_command, command, opts.callback, opts.opts)
    if not assign then
        error(string.format("`:%s` failed to create, error: %s", command, err))
    end
end

--- Expose subcommand tree for completion module
callbacks._get_subcommands = get_subcommands

return callbacks
