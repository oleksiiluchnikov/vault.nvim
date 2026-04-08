# Installation

## Requirements

- Neovim 0.10+
- [ripgrep](https://github.com/BurntSushi/ripgrep) (required)
- [glow](https://github.com/charmbracelet/glow) (optional)

## `lazy.nvim`

```lua
{
    'oleksiiluchnikov/vault.nvim',
    version = '*',

    ---@module 'vault.nvim'
    ---@type vault.Config
    opts = {
        -- Required: Root directory path where notes are stored
        root = "~/vault",

        -- Optional: Directory structure for organizing different note types
        dirs = {
            inbox = "inbox",
            docs = "_docs",
            templates = "_templates",
            journal = {
                root = "Journal",
                daily = "Journal/Daily",
                weekly = "Journal/Weekly",
                monthly = "Journal/Monthly",
                yearly = "Journal/Yearly"
            }
        },

        -- If the vault contains Obsidian settings, vault.nvim derives:
        --   - daily note folder/format/template from .obsidian/daily-notes.json
        --   - daily fallback from .obsidian/app.json
        --   - generic new-note folder from app.json newFileLocation/newFileFolderPath
        --   - link rewrite default from app.json alwaysUpdateLinks

        -- Optional: Files/directories to ignore during searches
        ignore = {
            ".git/*",
            ".obsidian/*",
            ".trash/*"
        },

        -- Optional: File extension for notes (default: .md)
        ext = ".md",

        -- Optional: YAML frontmatter configuration
        frontmatter = {
            keys = {
                tags = "tags"
            }
        },

        -- Optional: Tag configuration
        tags = {
            valid = {
                hex = true -- Allow hex values as valid tags
            }
        },

        -- Optional: Search patterns for parsing note elements
        search_pattern = {
            task = {
                pcre2 = [[^\s*-\s+\[.\]\s+\S+]]
            },
            date = {
                pcre2 = [[\d{4}-\d{2}-\d{2}]],
                lua = "[%d%d%d%d]-[%d%d]-[%d%d]"
            },
            tag = "#([A-Za-z0-9/_-]+)[\r|%s|\n|$]",
            wikilink = "%[%[([^\\]]*)%]%]",
            note = {
                type = "class::%s#class/([A-Za-z0-9_-]+)"
            }
        },

        -- Optional: Search tool (default: "rg")
        search_tool = "rg",

        -- Optional: Notification settings
        notify = {
            on_write = true
        },

        -- Optional: Check for duplicate filenames
        check_duplicate_basename = true,

        -- Optional: Popup configurations
        ui = {
            popups = {
                fleeting_note = {
                    title = {
                        text = "Fleeting Note",
                        preview = "border" -- "border" | "prompt" | "none"
                    },
                    editor = {
                        size = {
                            height = 6,
                            width = 80
                        }
                    }
                }
            },
        },

        -- Optional: Previewer tool (default: "glow")
        previewer = "glow",

        -- Optional: Default columns for :Vault process
        process = {
            columns = { "slug", "title", "status", "tags" },
        },

        -- Optional: Feature toggles
        features = {
            cmp = true,       -- Enable nvim-cmp completion
            commands = true,  -- Enable :Vault commands
            watcher = false,  -- Enable file watcher for auto wikilink patching
        },

        -- Optional: File watcher settings (only used when features.watcher = true)
        watcher = {
            debounce_ms = 500,           -- Debounce delay for batch processing
            auto_update_links = true,    -- Automatically update wikilinks on rename
            notify_on_rename = true,     -- Show notifications for renames
            prompt_on_rename = false,    -- Ask before applying link updates
            frontmatter_key = "slug",    -- Frontmatter key to update on rename (nil to skip)
        },

        -- Optional: Wikilink action confirmations
        wikilinks = {
            confirm_rewrite = true,  -- Confirm before rewriting [[old]] -> [[new]]
            confirm_merge = true,    -- Confirm before merging two notes
            confirm_create = false,  -- Confirm before creating from unresolved wikilink
        },

        -- Optional: Bases configuration
        bases = {
            ext = ".base",  -- File extension for base files
            dirs = nil,     -- Directories to scan for .base files (nil = entire vault)
        },
    }
}
```
