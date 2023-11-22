# 🗄️ Vault

🚧 **Please Note:** This plugin is currently in the early stages of development. Changes and potential breakages may occur as it evolves.

Plugin to manage [Obsidian](https://obsidian.md)-like vaults in Neovim.

The plugin might not suit everyone's organizational preferences but aims to
serve as a reference and potentially become more customizable in the future.

## ✨ Features

- **Fetch:**
  - notes in vault.
  - notes associated with a tag.
  - tags in vault.
  - tags associated with a note.
- **[Telescope](https://github.com/nvim-telescope/telescope.nvim) integration:**
  - Search for notes in vault
    - Search by title
    - Search by tag
  - Search for tags in vault
  - Browse nested tags from a root tag
- **[nvim-cmp](https://github.com/hrsh7th/nvim-cmp) integration:**
  - Autocompletion for tags (triggered by `#`)
  - Autocompletion for dates (triggered by century `20`)
  - Autocompletion for weekday (triggered after date)

## 🤨 Motivation

I developed this plugin with the goal of harnessing Neovim's power to manage my [Obsidian](https://obsidian.md) vault, tailored to my distinctive note organization style.
While I also appreciate and use the fantastic [obsidian.nvim](https://github.com/epwalsh/obsidian.nvim) plugin, I embarked on creating my own solution to provide the flexibility to adapt and customize it according to my unique requirements and preferences.

## 📦 Installation

Install the plugin with your preferred package manager:

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
  "oleksiiluchnikov/vault.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope.nvim",
    "hrsh7th/nvim-cmp",
    "oleksiiluchnikov/gradient.nvim",
    "oleksiiluchnikov/dates.nvim",
  },
  config = function()
    require("vault").setup()
  end,
}
```

## ⚙️ Configuration

### Setup

```lua
{
  dirs = {
    root = "~/knowledge", -- Root directory of vault.
    inbox = "inbox", -- Inbox directory relative to root.
    docs = "_docs", -- Docs directory relative to root.
    templates = "_templates", -- Templates directory relative to root.
    journal = {
      root = "Journal", -- Journal root directory relative to root.
      daily = "Journal/Daily", -- Daily journal directory relative to journal root.
      weekly = "Journal/Weekly", -- Weekly journal directory relative to journal root.
      monthly = "Journal/Monthly", -- Monthly journal directory relative to journal root.
      yearly = "Journal/Yearly", -- Yearly journal directory relative to journal root.
    },
  },
	ignore = { -- Ignore files and directories.
		".git/*",
		".obsidian/*",
    "_docs/*",
    "_templates/*",
	},
	ext = ".md", -- File extension for notes.
  tag = {
    valid = {
      hex = true, -- Hex color is a valid tag.
    }
  },
  search_pattern = { -- Search patterns for various vault objects.
    tag = "#([A-Za-z0-9/_-]+)[\r|%s|\n|$]", -- Tag search pattern.
    wikilink = "%[%[([A-Za-z0-9/_-]+)%]%]", -- Wikilink search pattern.
  }
}
```

## 🚀 Usage

### Commands

The plugin provides the following commands for seamless navigation and searching within the vault:

- `:VaultNotes`: Opens the Telescope note search picker. It autocompletes arguments as note filenames. For quick access to a specific note, use `:VaultNotes <filename>` to open it immediately.
- `:VaultTags`: Opens the Telescope tag search picker. It autocompletes arguments as tag names. Use `:VaultTags <tag>` to swiftly access notes associated with the specified tag.
- `:VaultDates`: Opens the Telescope date search picker. It autocompletes arguments as dates.
- `:VaultToday`: Opens the today's daily journal note, even if it doesn't exist yet.
- `:VaultInbox`: Opens the Telescope note search picker for the inbox directory.

### API

### Vault module
```lua
---Setup vault.
---@param opts table? -- An optional table of options.
require("vault").setup(opts)

---Fetch an list of all notes in vault.
---@type table[] -- An list of note objects.
require("vault").notes()

---Fetch an list of notes filtered by tags.
---@param include table[]? -- An list of tag names to include.
---@param exclude table[]? -- An list of tag names to exclude.
---@param match_opt string? -- An optional table of match options. E.g "exact", "contains", "startwith", "endwith", "regex". If not provided, "exact" will be used.
---@param mode string? -- A mode to filter notes by. E.g. "all", "any", "none". If not provided, "all" will be used.
---@type table[] -- An list of note objects.
require("vault").notes_filter_by_tags(include, exclude, match_opts, mode)

---Fetch an list of all tags in vault.
---@param include table[]? -- An optional list of tag names to include.
---@param exclude table[]? -- An optional list of tag names to exclude.
---@param match_opt string? -- An optional table of match options. E.g "exact", "contains", "startwith", "endwith", "regex". If not provided, "exact" will be used.
---@type table[] -- An list of tag objects.
require("vault").tags(include, exclude, match_opt)
```

### Telescope pickers

```lua
---Open Telescope note search picker.
---@param notes table[]? -- An optional list of Note objects to search. If not provided, all notes in vault will be searched.
require("vault.pickers").notes(notes)

---Open Telescope tag search picker.
---@param include table[]? -- An optional list of tag names to include.
---@param exclude table[]? -- An optional list of tag names to exclude.
---@param match_opt string? -- An optional table of match options. E.g "exact", "contains", "startwith", "endwith", "regex". If not provided, "exact" will be used.
require("vault.pickers").tags(include, exclude, match_opt)

---Open Telescope notes picker for a specific tags.
---@param include table[]? -- An list of tag names to include.
---@param exclude table[]? -- An list of tag names to exclude.
---@param match_opt string? -- An optional table of match options. E.g "exact", "contains", "startwith", "endwith", "regex". If not provided, "exact" will be used.
---@param mode string? -- A mode to filter notes by. E.g. "all", "any", "none". If not provided, "all" will be used.
require("vault.pickers").notes_filter_by_tags(include, exclude, match_opts, mode)

---Open Telescope picker to browse nested tags from a root tag.
require("vault.pickers").root_tags()

---Open Telescope picker for dates.
---@param start_date string -- Start date in ISO 8601 format. E.g. "2023-01-01". If not provided, the week ago date will be used.
---@param end_date string -- End date in ISO 8601 format. E.g. "2023-01-31". If not provided, the current date will be used.
require("vault.pickers").dates(start_date, end_date)

---Open Telescope picker for notes in the inbox directory.
require("vault.pickers").inbox()
```

## 🤝 Similar Plugins

- [obsidian.nvim](https://github.com/epwalsh/obsidian.nvim)

## License

[MIT](https://choosealicense.com/licenses/mit/)
