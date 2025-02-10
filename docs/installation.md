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

        -- Optional: Feature toggles
        features = {
            cmp = true,      -- Enable completion
            commands = true, -- Enable commands
            -- blink = true    -- Enable blink.cmp integration. TODO: Not implemented yet
        }
    }
}
```
