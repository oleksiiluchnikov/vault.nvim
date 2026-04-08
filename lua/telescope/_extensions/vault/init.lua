--- @alias vault.Picker.map fun(mode: string, keymap: string, callback: fun(bufnr: integer))
--- @alias vault.TelescopeDisplayerConfig {separator: string, items: {width: number, remaining: boolean}[]}
--- @alias vault.TelescopeEntry {value: any, valid?: boolean, ordinal: string, display: string|fun(entry: vault.TelescopeEntry): string, string[][], filename: string?, bufnr: integer?, lnum: number?, col: number}
--- @alias vault.TelescopeEntryMaker fun(entry: vault.TelescopeEntry): vault.TelescopeEntry

return require("telescope").register_extension({
    setup = function(_, _) end,

    exports = {
        vault = function(opts)
            require("telescope._extensions.vault.pickers.vault")(opts):find()
        end,
    },
})
