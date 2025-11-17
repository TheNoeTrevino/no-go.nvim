# no-go.nvim

A Neovim plugin that intelligently collapses Go error handling blocks into a single line, making your code more readable while keeping the error handling visible.

## Features

- Automatically detects and collapses `if err != nil { ... return }` patterns
- Uses Treesitter queries, no regex
- Shows collapsed blocks with customizable virtual text (`: err 󱞿 ` by default)
- Only collapses blocks where the variable is named `err`, or the user-defined identifiers
- Customizable highlight colors and virtual text

## Before and After

TODO: add photos

## Requirements

- Neovim >= 0.11.0 (for `conceal_lines` support to completely hide error handling blocks)
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) with Go parser installed

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "noetrevino/no-go.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  ft = "go",
  -- look at default config below for customization options
}
```

## Configuration

### Default Configuration

```lua
require("no-go").setup({
  -- Enable the plugin behavior by default
  enabled = true,

  -- Identifiers to match in if statements (e.g., "if err != nil", "if error != nil")
  -- Only collapse blocks where the identifier is in this list
  identifiers = { "err" },

  -- Virtual text structure for collapsed error handling
  -- Built as: prefix + content + content_separator + return_character + suffix
  -- Content is dynamically extracted from the return statement
  virtual_text = {
    prefix = " ",
    content_separator = " ",
    return_character = "󱞿 ",
    suffix = "",
  },

  -- Highlight group for the collapsed text
  highlight_group = "NoGoZone",

  -- Default highlight colors
  highlight = {
    bg = "#2A2A37",
    -- fg = "#808080", -- Optional foreground color
  },

  -- Auto-update on these events
  update_events = {
    "BufEnter",
    "BufWritePost",
    "TextChanged",
    "TextChangedI",
    "InsertLeave",
  },

  -- Key mappings to skip over concealed lines
  -- The plugin automatically remaps these keys to skip concealed error blocks
  keymaps = {
    move_down = "j", -- Key to move down and skip concealed lines
    move_up = "k",   -- Key to move up and skip concealed lines
  },

  -- Reveal concealed lines when cursor is on the if err != nil line
  -- This allows you to inspect the error handling by hovering over the collapsed line
  reveal_on_cursor = true,
})
```

### Custom Virtual Text

The virtual text is dynamically built based on what's in the return statement. It's composed of four parts:
- **prefix**: What comes before the content
- **content**: The identifier from the return statement (e.g., `err` from `return err`)
- **content_separator**: Space between content and return character (only added if content exists)
- **return_character**: The icon/symbol indicating a return
- **suffix**: What comes at the end

### Reveal on Cursor

The `reveal_on_cursor` feature automatically reveals concealed error handling blocks when you move your cursor to the `if err != nil` line. This allows you to inspect the actual error handling code without manually toggling concealment.

TODO: add videos here

```lua
-- Enable reveal on cursor (default)
require("no-go").setup({
  reveal_on_cursor = true,
})

-- Disable reveal on cursor. Please read warning below!
require("no-go").setup({
  reveal_on_cursor = false,
})
```

**How it works:**
- When your cursor is on the `if err != nil` line, the concealed block below is revealed
- You can move down into the revealed block and navigate around inside it
- While your cursor is anywhere inside the block (from the `if` line to the closing `}`) it will, of course, stays revealed
- When you move the cursor completely outside the block, it will conceal again automatically
- This gives you: compact view by default, detailed view when needed

> [!WARNING]
> PLEASE note that if you disable `reveal_on_cursor`, you MUST manually toggle concealment
> using the provided commands to access the error handling!
> Though, it is nice when you just want to view the happy path.


## Commands

The plugin provides user commands rather than key mappings:

- `:NoGoRefresh` - Manually refresh the current buffer
- `:NoGoToggle` - Toggle error collapsing for the current buffer
- `:NoGoEnable` - Enable error collapsing for the current buffer
- `:NoGoDisable` - Disable error collapsing for the current buffer

> [!NOTE]
> Of course, you can always add your own mappings. 

## How It Works

The plugin uses Treesitter to parse your Go code and identify error handling patterns. It specifically looks for:

1. An `if` statement with a binary expression (e.g., `err != nil`)
2. The left side of the expression must be the identifier `err`, or whatever identifiers you have configured
3. The consequence block must contain a `return` statement

When all conditions are met, the plugin:
- Adds virtual text at the end of the `if` line
- Hides the lines containing the error handling block
- Highlights the virtual text with the `NoGoZone` highlight group

This approach ensures only standard Go error handling patterns are collapsed, avoiding false positives.

### Look at The AST Yourself

If you are interested in how the AST queries are structured, go over to one of
the if statements that this plugin conceals. Run the command
`:InspectTree`. It is actually quite neat!

## TODO

- [ ] Add command to toggle reveal on cursor
- [ ] Add support for not operator. `if !ok {...`
