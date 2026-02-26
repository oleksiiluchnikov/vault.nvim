---@diagnostic disable: missing-return-value
--- @class vaultifickers
--- TODO: Picker
--- assign_tags fun(opts: table?, tags: string[]): nil - Picker to choose the tag to assign, or do this as action
--- for tags picker?
--- put_links fun(opts: table?, links: string[]): nil - Picker to choose the link to put, or do this as action
--- for notes picker?
--- put_wikilinks fun(opts: table?, wikilinks: string[]): nil - Picker to choose the wikilink to put, or do this as action

--- @alias vault.TelescopeFindResults fun(self: vault.TelescopeFindResults): vault.TelescopeFindResults
--- @alias vault.TelescopeDisplayerConfig {separator: string, items: {width: number, remaining: boolean}[]}

--- @alias vault.Picker.map fun(mode: string, keymap: string, callback: fun(bufnr: integer))
--- @alias vault.TelescopeLayoutStrategy string|fun(self: Picker, window: TelescopeWindow): TelescopeLayout
--- @alias vault.TelescopeWindowOptions table
--- @alias vault.TelescopeFinder table
--- @alias vault.TelescopeSorter table
--- @alias vault.TelescopePreviewer table
--- @alias vault.TelescopeEntryManager table
--- @alias vault.TelescopeEntry {value: any, valid?: boolean, ordinal: string, display: string | vault.TelescopeEntryMaker, filename: string?, bufnr: integer?, lnum: number?, col: number}
--- @alias vault.TelescopeMultiSelect table
--- @alias vault.TelescopeScrollStrategy string|fun(self: Picker, window: TelescopeWindow, direction: string, reset: boolean)
--- @alias vault.TelescopeTiebreakStrategy string|fun(self: Picker, entries: vault.TelescopeEntry[])
--- @alias vault.TelescopeSelectionStrategy string|fun(self: Picker, entries: vault.TelescopeEntry[], prompt: string)
--- @alias vault.TelescopeBorder string|table
--- @alias vault.TelescopeBorderChars table
--- @alias vault.TelescopeCachePickerOptions table
--- @alias vault.TelescopeEntryMaker fun(entry: vault.TelescopeEntry): vault.TelescopeEntry

--- @class TelescopePickerOptions
--- @field layout_strategy? vault.TelescopeLayoutStrategy
--- @field get_window_options? fun(): vault.TelescopeWindowOptions
--- @field prompt_title? string
--- @field results_title? string
--- @field preview_title? string
--- @field prompt_prefix? string
--- @field wrap_results? boolean
--- @field selection_caret? string
--- @field entry_prefix? string
--- @field multi_icon? string
--- @field initial_mode? string
--- @field debounce? number
--- @field default_text? string
--- @field get_status_text? fun(): string
--- @field on_input_filter_cb? fun()
--- @field finder vault.TelescopeFinder
--- @field sorter? Sorter
--- @field previewer? vault.TelescopePreviewer|vault.TelescopePreviewer[]
--- @field current_previewer_index? number
--- @field default_selection_index? number
--- @field get_selection_window? fun(): TelescopeWindow
--- @field cwd? string
--- @field _completion_callbacks? table
--- @field manager? vault.TelescopeEntryManager
--- @field _multi? vault.TelescopeMultiSelect
--- @field track? boolean
--- @field attach_mappings? boolean
--- @field file_ignore_patterns? string[]
--- @field scroll_strategy? vault.TelescopeScrollStrategy
--- @field sorting_strategy? table
--- @field tiebreak? vault.TelescopeTiebreakStrategy
--- @field selection_strategy? vault.TelescopeSelectionStrategy
--- @field push_cursor_on_edit? boolean
--- @field push_tagstack_on_edit? boolean
--- @field layout_config? table
--- @field cycle_layout_list? boolean
--- @field border? vault.TelescopeBorder
--- @field borderchars? vault.TelescopeBorderChars
--- @field cache_picker? vault.TelescopeCachePickerOptions
--- @field temp__scrolling_limit? number
--- @field __locations_input? boolean
--- @field create_layout? fun(self: Picker, window: TelescopeWindow): TelescopeLayout
--- @field on_complete? fun()[]
--- @field __hide_previewer? boolean
--- @field resumed_picker? boolean
--- @field fix_preview_title? boolean,

return require("telescope").register_extension({
    setup = function(ext_config, config) end,

    exports = {
        vault = function(opts)
            require("telescope._extensions.vault.pickers.vault")(opts):find()
        end,
    },
})
