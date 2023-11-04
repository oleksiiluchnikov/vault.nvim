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

I developed this plugin with the goal of harnessing Neovim's power to manage my
[Obsidian](https://obsidian.md) vault, tailored to my distinctive note organization style.
While I also appreciate and use the fantastic [obsidian.nvim](https://github.com/epwalsh/obsidian.nvim) plugin,
I embarked on creating my own solution to provide the flexibility to adapt and customize it
according to my unique requirements and preferences.

## 📦 Installation

Install the plugin with your preferred package manager:

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
  'oleksiiluchnikov/gradient.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-telescope/telescope.nvim',
    'hrsh7th/nvim-cmp',
  },
  config = function()
    require('vault').setup()
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

### API

```lua
--- Setup vault.
require('vault').setup()

---Fetch an array of all notes in vault.
---@type table[] @ An array of note objects.
require('vault').notes()

--- Fetch an array of all tags in vault.
---@type table[] @ An array of tag objects.
require('vault').tags()

---Open Telescope note search picker.
---@param notes table[]? @ An optional array of note objects to search. If not provided, all notes in vault will be searched.
require('vault.pickers').notes(notes)

---Open Telescope tag search picker.
require('vault.pickers').tags()

---Open Telescope notes picker for a specific tags.
---@param tag_values string[] @ An array of tag values to search.
require('vault.pickers').notes_with_tags(tag_values)

---Open Telescope picker to browse nested tags from a root tag.
require('vault.pickers').root_tags()
```

## 🤝 Similar Plugins

- [obsidian.nvim](https://github.com/epwalsh/obsidian.nvim)

## License

[MIT](https://choosealicense.com/licenses/mit/)
