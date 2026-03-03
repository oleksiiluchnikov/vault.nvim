local completions = require("vault.commands.completions")
local log = require("vault.log").scope("cmd")
--- @class vault.commands.callback
local callbacks = {}

local pickers = require("telescope._extensions.vault.pickers")

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
        local s, e, title, mdurl = line:find(md_link_pattern, md_start)
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
    return {
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
                local methods = { "new", "rename", "delete", "extract", "inlinks", "outlinks", "tags", "properties", "cluster", "random", "preview", "obsidian" }
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
                return vim.tbl_filter(function(m) return m:find(prefix, 1, true) == 1 end, methods)
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
                        if type(path) == "table" then path = path[1] end
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
                    local picker = pickers.notes({ notes = cluster })
                    if picker then picker:find() end
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
                        message = string.format("Delete note '%s'?%s", note.data.slug, permanent and " (PERMANENT)" or " (move to .trash)"),
                        title = "Vault",
                        on_yes = function() note:delete(permanent) end,
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

        -- :Vault notes [filter] — vault-wide note browsing
        notes = {
            run = function(args)
                callbacks.notes({ fargs = args })
            end,
            complete = function(prefix)
                local subs = { "linked", "orphans", "leaves", "internals", "dangling", "resolved", "status", "dir", "empty", "no-frontmatter", "empty-property" }
                return vim.tbl_filter(function(s) return s:find(prefix, 1, true) == 1 end, subs)
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
                    safe_find(
                        pickers.notes({ notes = require("vault.notes")():leaves() }),
                        "No leaf notes found"
                    )
                end,
            },
            internals = {
                run = function()
                    safe_find(
                        pickers.notes({ notes = require("vault.notes")():internals() }),
                        "No internal notes found"
                    )
                end,
            },
            dangling = {
                run = function()
                    safe_find(
                        pickers.notes({ notes = require("vault.notes")():with_outlinks_unresolved() }),
                        "No dangling links found"
                    )
                end,
            },
            resolved = {
                run = function()
                    safe_find(
                        pickers.notes({ notes = require("vault.notes")():with_outlinks_resolved_only() }),
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
            empty = {
                run = function()
                    require("vault.api").open_picker_notes_with_empty_content()
                end,
            },
            ["no-frontmatter"] = {
                run = function()
                    require("vault.api").open_picker_notes_without_frontmatter()
                end,
            },
            ["empty-property"] = {
                run = function(args)
                    local prop = args[1]
                    local val = args[2]
                    require("vault.api").open_picker_notes_with_empty_property_value(prop, val)
                end,
                complete = function(prefix)
                    local ok, props = pcall(function()
                        return vim.tbl_keys(require("vault.scanner").properties())
                    end)
                    if not ok then return {} end
                    return vim.tbl_filter(function(p) return p:find(prefix, 1, true) == 1 end, props)
                end,
            },
        },

        -- :Vault tags [tag] — vault tags picker
        tags = {
            run = function(args)
                safe_find(pickers.tags({ tags_list = args }), "No tags found")
            end,
            complete = function(prefix)
                local subs = { "rename", "merge", "doc" }
                local tag_completions = completions.tags(nil, "Vault tags " .. prefix, nil) or {}
                for _, s in ipairs(subs) do
                    if s:find(prefix, 1, true) == 1 then
                        table.insert(tag_completions, 1, s)
                    end
                end
                return tag_completions
            end,
            rename = {
                run = function(args)
                    if #args < 2 then
                        log.warn("Usage: :Vault tags rename <old> <new>")
                        return
                    end                    require("vault.api").rename_tag(args[1], args[2])
                end,
                complete = function(prefix)
                    return completions.tags(nil, "Vault tags rename " .. prefix, nil) or {}
                end,
            },
            merge = {
                run = function(args)
                    if #args < 2 then
                        log.warn("Usage: :Vault tags merge <target> <source1> [source2 ...]")
                        return
                    end
                    local target = args[1]
                    for i = 2, #args do
                        require("vault.api").rename_tag(args[i], target)
                    end
                    log.info("Merged %d tags into '%s'", #args - 1, target)
                end,
                complete = function(prefix)
                    return completions.tags(nil, "Vault tags merge " .. prefix, nil) or {}
                end,
            },
            doc = {
                run = function(args)
                    if #args == 0 then
                        log.warn("Usage: :Vault tags doc <tag_name>")
                        return
                    end
                    require("vault.api").edit_tag_documentation(args[1])
                end,
                complete = function(prefix)
                    return completions.tags(nil, "Vault tags doc " .. prefix, nil) or {}
                end,
            },
        },

        -- :Vault properties [name] [value] — vault properties picker / drill-down
        properties = {
            run = function(args)
                if #args == 0 then
                    safe_find(pickers.properties(), "No properties found")
                elseif #args == 1 then
                    -- Drill into property values
                    require("vault.api").open_picker_property_values(args[1])
                else
                    -- Show notes with specific property value
                    require("vault.api").open_picker_notes_with_property_value(args[1], args[2])
                end
            end,
            complete = function(prefix)
                local ok, props = pcall(function()
                    return vim.tbl_keys(require("vault.scanner").properties())
                end)
                if not ok then return {} end
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
                    if not ok then return {} end
                    return vim.tbl_filter(function(p) return p:find(prefix, 1, true) == 1 end, props)
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
                safe_find(pickers.dates(), "No dates found")
            end,
        },

        -- :Vault wikilinks — wikilinks picker
        wikilinks = {
            run = function()
                safe_find(pickers.wikilinks(), "No wikilinks found")
            end,
            complete = function(prefix)
                local subs = { "unresolved", "resolved" }
                return vim.tbl_filter(function(s) return s:find(prefix, 1, true) == 1 end, subs)
            end,
            unresolved = {
                run = function()
                    -- Use the fast Rust scanner path (no args) instead of Lua notes-based parsing
                    local wikilinks = require("vault.wikilinks")()
                    local unresolved = wikilinks:unresolved()
                    safe_find(pickers.wikilinks({ wikilinks = unresolved }), "No unresolved wikilinks found")
                end,
            },
            resolved = {
                run = function()
                    local wikilinks = require("vault.wikilinks")()
                    local resolved = wikilinks:resolved()
                    safe_find(pickers.wikilinks({ wikilinks = resolved }), "No resolved wikilinks found")
                end,
            },
        },

        -- :Vault tasks — tasks picker
        tasks = {
            run = function()
                callbacks.tasks()
            end,
        },

        -- :Vault bases [name] — bases picker
        bases = {
            run = function(args)
                if #args == 0 then
                    safe_find(pickers.bases(), "No bases found")
                else
                    require("vault.api").open_picker_base_notes(table.concat(args, " "))
                end
            end,
            complete = function()
                local ok, bases = pcall(function() return require("vault.bases")() end)
                return (ok and bases) and bases:names() or {}
            end,
        },

        -- :Vault process [filter] — Grid-backed metadata editing buffer (default)
        -- Supports: base <name>, undo, orphans, leaves, empty, no-frontmatter,
        --           dir <path>, tag <name>, empty-property <field> [value],
        --           title,status,tags (inline columns), <slug> (fuzzy filter)
        process = {
            run = function(args)
                local grid_editor = require("vault.bases.views.grid")
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
                    columns_arg = vim.tbl_filter(function(c) return c ~= "" end, columns_arg)
                    filter = args[2]
                    args = vim.list_slice(args, 2)
                end

                if filter == "undo" then
                    grid_editor.undo()
                    return
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
                    notes = require("vault.notes")():filter("content", [=[^\(---\)\@!.*$]=], "regex", true)
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
                        grid_editor.open({ base = base, columns = columns_arg })
                    else
                        -- No base name given — open Telescope bases picker
                        local ok, picker = pcall(require, "telescope._extensions.vault.pickers.bases")
                        if ok then
                            picker():find()
                        else
                            log.error("Telescope bases picker not available: %s", tostring(picker))
                        end
                    end
                    return
                elseif filter == "empty-property" then
                    require("vault.api").open_picker_notes_with_empty_property_value(args[2], args[3])
                    return
                else
                    notes = require("vault.notes")():filter("slug", filter, "fuzzy")
                    desc = "filter:" .. filter
                end

                grid_editor.open({ notes = notes, filter_desc = desc, columns = columns_arg })
            end,
            complete = function(prefix, line)
                if line and line:match("process%s+base%s+") then
                    local ok, Bases = pcall(require, "vault.bases")
                    if ok then
                        local bases = Bases()
                        local names = bases:names()
                        local sub = line:match("process%s+base%s+(.*)") or ""
                        return vim.tbl_filter(function(s) return s:find(sub, 1, true) == 1 end, names)
                    end
                    return {}
                end
                local col_arg = line and line:match("process%s+([^%s]*,[^%s]*)$")
                if col_arg then
                    local last_comma = col_arg:match(".*,()")
                    local col_prefix = last_comma and col_arg:sub(last_comma) or ""
                    local builtin = {
                        "slug", "title", "tags", "status",
                        "file.name", "file.folder", "file.path", "file.ext",
                        "file.ctime", "file.mtime", "file.size",
                        "file.body", "file.slug",
                        "file.inlinks", "file.outlinks", "file.headings",
                        "note.name", "note.folder", "note.path", "note.ext",
                        "note.ctime", "note.mtime", "note.size",
                        "note.body", "note.slug",
                        "note.inlinks", "note.outlinks", "note.headings",
                    }
                    local ok_core, core = pcall(require, "vault_core")
                    if ok_core and core.fields then
                        local cfg = require("vault.config")
                        local ok_f, fields = pcall(core.fields,
                            cfg.options and cfg.options.root or "",
                            cfg.options and cfg.options.ignore or {})
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
                    return vim.tbl_map(function(s) return base_part .. s end, matches)
                end
                local subs = { "base", "undo", "orphans", "leaves", "empty", "no-frontmatter", "dir", "tag", "empty-property" }
                return vim.tbl_filter(function(s) return s:find(prefix, 1, true) == 1 end, subs)
            end,
        },

        -- :Vault kanban [filter] — Kanban board view grouped by frontmatter/tags/directory
        -- Supports: base <name>, group=<field>, fields=<f1,f2>,
        --           tag <name>, dir <path>
        kanban = {
            run = function(args)
                local grid_kanban = require("vault.bases.views.kanban")
                local filter = args[1]
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
                        for i, f in ipairs(display_fields) do display_fields[i] = vim.trim(f) end
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
                        local ok, picker = pcall(require, "telescope._extensions.vault.pickers.bases")
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
                    notes = require("vault.notes")():filter("relpath", remaining[2], "startswith", false)
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
                        return vim.tbl_filter(function(s) return s:find(sub, 1, true) == 1 end, names)
                    end
                    return {}
                end
                local subs = { "base", "tag", "dir", "group=", "fields=", "mode=" }
                return vim.tbl_filter(function(s) return s:find(prefix, 1, true) == 1 end, subs)
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
                return vim.tbl_filter(function(s) return s:find(prefix, 1, true) == 1 end, subs)
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
                    if not choice then return end
                    local full_path = trash_dir .. "/" .. choice
                    require("vault.ui.confirm").select({
                        message = "Note: " .. choice,
                        title = "Vault Trash",
                        choices = {
                            { key = "r", label = "Restore", action = function()
                                local restore_path = config.options.root .. "/" .. choice
                                if vim.fn.filereadable(restore_path) == 1 then
                                    log.error("A note with that name already exists in the vault")
                                    return
                                end
                                local ok, err = (vim.uv or vim.loop).fs_rename(full_path, restore_path)
                                if ok then
                                    log.info("Restored: %s", choice)
                                else
                                    log.error("Restore failed: %s", tostring(err))
                                end
                            end },
                            { key = "d", label = "Permanent delete", action = function()
                                local ok, err = os.remove(full_path)
                                if ok then
                                    log.info("Permanently deleted: %s", choice)
                                else
                                    log.error("Delete failed: %s", tostring(err))
                                end
                            end, danger = true },
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
                safe_find(
                    pickers.notes({
                        notes = require("vault.notes")():filter("relpath", vim.fn.fnamemodify(inbox_dir, ":t"), "startswith", false),
                    }),
                    "No notes in inbox"
                )
            end,
        },

        -- :Vault lines — lines picker (dash-prefixed lines across vault)
        lines = {
            run = function()
                require("vault.api").open_picker_lines_starting_with_dash()
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
                safe_find(pickers.move_to(opts), "No directories found")
            end,
            complete = function(prefix)
                return completions.note_slugs(nil, "Vault move " .. prefix, nil) or {}
            end,
        },

        -- :Vault api <func> [args] — raw API dispatch (backward compat)
        api = {
            run = function(args)
                local func_name = args[1]
                if not func_name then
                    log.info("Usage: :Vault api <function> [args...]")
                    return
                end
                local api_func = require("vault.api")[func_name]
                if not api_func then
                    log.warn("Unknown API function: %s", func_name)
                    return
                end
                api_func(unpack(args, 2))
            end,
            complete = function()
                return vim.tbl_keys(require("vault.api"))
            end,
        },
    }
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
        safe_find(pickers.vault(), "No pickers available")
        return
    end

    -- Walk the tree
    local node = get_subcommands()
    local depth = 0
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
        depth = i
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
    local notes = require("vault.notes")():filter("slug", new_slug, "exact", false)
    if next(notes.map) then
        local _, existing = next(notes.map)
        existing:edit()
        return
    end
    local path = require("vault.utils").slug_to_path(new_slug)
    local note = require("vault.notes.note")(path)
    note:write(path)
    note:edit()
end

--- @param args vim.api.keyset.create_user_command.command_args
function callbacks.pick_dirs(args)
    local fargs = args.fargs
    if next(fargs) == nil then
        safe_find(pickers.dirs(), "No directories found")
        return
    end
    local notes = require("vault.notes")():filter("relpath", fargs[1], "startswith", false)
    safe_find(pickers.notes({ notes = notes }), "No notes found in directory: " .. fargs[1])
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
        safe_find(pickers.tags(), "No tags found")
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
        pickers.notes({ notes = require("vault.notes")():filter(filter_opts) }),
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
        safe_find(pickers.dates(), "No dates found")
        return
    end
    --TODO: Add configuration to set the date format
    local today = os.date("%Y-%m-%d")
    local year_ago = os.date("%Y-%m-%d", os.time() - 60 * 60 * 24 * 365)
    safe_find(
        pickers.dates({ start_date = tostring(today), end_date = tostring(year_ago) }),
        "No dates found"
    )
end

--- vault.Today
--- Opens the today's journal note
--- @return nil
function callbacks.today()
    --- @type vault.Config|vault.Config.options
    local config = require("vault.config")
    local today = os.date("%Y-%m-%d %A")
    if type(today) ~= "string" then
        return
    end
    local daily_dir = config.dir("journal.daily")
    if not daily_dir then
        log.error("Journal daily directory not configured (dirs.journal.daily)")
        return
    end
    local path = string.format("%s/%s%s", daily_dir, today, config.options.ext)
    if vim.fn.filereadable(path) == 0 then
        log.info("Initializing today's journal note")
    end
    vim.cmd("e " .. vim.fn.fnameescape(path))
end

--- Appends a line to today's daily note without opening it.
--- @param text string  Line text to append (a "- " prefix is added automatically)
--- @return nil
function callbacks.daily_append(text)
    local config = require("vault.config")
    local today = os.date("%Y-%m-%d %A")
    if type(today) ~= "string" then return end
    local daily_dir = config.dir("journal.daily")
    if not daily_dir then
        log.error("Journal daily directory not configured (dirs.journal.daily)")
        return
    end
    local path = string.format("%s/%s%s", daily_dir, today, config.options.ext)
    local Note = require("vault.notes.note")
    local note = Note(path)
    note:append("- " .. text)
    log.info("Appended to %s", today)
end

--- Open ask --dictate with today's daily note as context, append result.
--- Requires the `ask` binary to be available in PATH.
--- @return nil
function callbacks.today_dictate()
    if vim.fn.executable("ask") == 0 then
        log.error("`ask` not found in PATH — install it to use :Vault today dictate")
        return
    end
    local config = require("vault.config")
    local today = os.date("%Y-%m-%d %A")
    if type(today) ~= "string" then return end
    local daily_dir = config.dir("journal.daily")
    if not daily_dir then
        log.error("Journal daily directory not configured")
        return
    end
    local path = string.format("%s/%s%s", daily_dir, today, config.options.ext)
    local ctx = vim.fn.filereadable(path) == 1
        and table.concat(vim.fn.readfile(path), "\n")
        or ""
    local Note = require("vault.notes.note")
    -- Pass context via stdin ("--context -") to avoid argument-length limits
    -- and to correctly handle multiline/special-char note content.
    vim.system(
        { "ask", "--dictate", "--json", "--context", "-", "--placeholder", "Say something…" },
        { stdin = ctx },
        function(out)
            if out.code ~= 0 then return end
            vim.schedule(function()
                local ok, json = pcall(vim.json.decode, vim.trim(out.stdout))
                if ok and json.ok and json.value ~= "" then
                    Note(path):append("- " .. os.date("%H:%M:%S") .. " " .. json.value)
                end
            end)
        end
    )
end

function callbacks.open_properties_picker(args)
    local fargs = args.fargs
    if next(fargs) == nil then
        safe_find(pickers.properties(), "No properties found")
        return
    end
    local values = {}
    for _, value in ipairs(fargs) do
        table.insert(values, value)
    end
    safe_find(pickers.properties({ values = values }), "No properties found")
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
    safe_find(
        pickers.notes({ notes = require("vault.notes")():orphans() }),
        "No orphan notes found"
    )
end

--- vault.Linked
--- Opens a picker with linked notes
--- @return nil
function callbacks.open_linked_picker()
    safe_find(
        pickers.notes({ notes = require("vault.notes")():linked() }),
        "No linked notes found"
    )
end

--- Opens a live grep picker with fuzzy search
--- @param args vim.api.keyset.create_user_command.command_args
--- @return nil
function callbacks.open_live_grep_picker(args)
    local query = ""
    if args.range and args.range > 0 then
        -- Visual selection: use selected text as initial query
        local lines = vim.api.nvim_buf_get_lines(0, args.line1 - 1, args.line2, false)
        query = table.concat(lines, "\n")
        -- Trim to first line for grep prompt (multiline not practical)
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
    local config = require("vault.config")
    local yesterday = os.date("%Y-%m-%d", os.time() - 60 * 60 * 24)
    local daily_dir = config.dir("journal.daily")
    if not daily_dir then
        log.error("Journal daily directory not configured (dirs.journal.daily)")
        return
    end
    local path = string.format("%s/%s%s", daily_dir, yesterday, config.options.ext)
    if vim.fn.filereadable(path) == 0 then
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
        pickers.notes({ notes = require("vault.notes")():filter(inlink_slugs) }),
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
        pickers.notes({ notes = require("vault.notes")():filter(target_slugs) }),
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
        pickers.notes({ notes = require("vault.notes")():filter(slugs) }),
        "No notes found for tags"
    )
end

--- Create a new note from the selected text, and replace the selected text with a link to the new note
--- @param args vim.api.keyset.create_user_command.command_args
function callbacks.note_from_selected_text(args)
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
    local new_note_path = require("vault.utils").slug_to_path(new_note_slug)
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
        safe_find(pickers.properties(), "No properties found")
        return
    end
    local values = {}
    for _, value in ipairs(fargs) do
        table.insert(values, value)
    end
    safe_find(pickers.properties({ values = values }), "No properties found")
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
    safe_find(pickers.notes({ notes = notes }), "No notes found in directory: " .. fargs[1])
end

--- @param args vim.api.keyset.create_user_command.command_args
function callbacks.note(args)
    local fargs = args.fargs
    -- if no arguments, then open a picker
    if next(fargs) == nil then
        safe_find(pickers.notes(), "No notes found")
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
    local ok, output = pcall(note[method], unpack(arguments))
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
        args = input
        safe_find(pickers.notes(), "No notes found")
    elseif #args == 1 then
        if args[1] ~= "by" then
            local notes = require("vault.notes")()
            local preset = notes[args[1]]
            if type(preset) == "function" then
                preset = preset(notes)
            end
            safe_find(pickers.notes({ notes = preset }), "No notes found for preset: " .. args[1])
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
        safe_find(pickers.notes({
            notes = require("vault.notes")({ args[2], args[3], {}, "startswith", "all" }),
        }))
    elseif #args == 4 then
        if type(args[3]) ~= "table" then
            args[3] = { args[3] }
        end
        if type(args[4]) ~= "table" then
            args[4] = { args[4] }
        end
        safe_find(pickers.notes({
            notes = require("vault.notes")({ args[2], args[3], args[4], "startswith", "all" }),
        }))
    elseif #args == 5 then
        if type(args[3]) ~= "table" then
            args[3] = { args[3] }
        end
        if type(args[4]) ~= "table" then
            args[4] = { args[4] }
        end
        safe_find(pickers.notes({
            notes = require("vault.notes")({ args[2], args[3], args[4], args[5], "all" }),
        }))
    elseif #args == 6 then
        if type(args[3]) ~= "table" then
            args[3] = { args[3] }
        end
        if type(args[4]) ~= "table" then
            args[4] = { args[4] }
        end
        safe_find(pickers.notes({
            notes = require("vault.notes")({ args[2], args[3], args[4], args[5], args[6] }),
        }))
    end
end

function callbacks.notes(args)
    if next(args.fargs) == nil then
        safe_find(pickers.notes(), "No notes found")
        return
    end
    construct_notes_picker_args(args.fargs)
end

function callbacks.tasks()
    -- TODO: Implement to complete by status
    safe_find(pickers.tasks(), "No tasks found")
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
