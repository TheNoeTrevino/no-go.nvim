# no-go.nvim

Verbose error handling in Go? That's a no-go from me!

A Neovim plugin that intelligently collapses Go error handling blocks into a single line,
making your code more readable while keeping the semantics of error handling visible.

## Before and After

<img width="2191" height="1219" alt="before-after" src="https://github.com/user-attachments/assets/b41778f7-bf20-48d2-a0c3-bb3e4ed5589e" />

## Motivation

Go's error handing is explicit and unmagical (awesome!), but that comes with verbosity and a tendency to create bloat in your code (sad!).

After doing research and finding from [this issue](https://github.com/golang/vscode-go/issues/2311) that GoLand has implemented their own solution, 
I knew I wanted to create something similar in Neovim. 

## Features

- Automatically detects and collapses `if err != nil { ... return }` patterns
- Uses Treesitter queries, no regex
- Shows collapsed blocks with customizable virtual text (`: err 󱞿 ` by default)
- Only collapses blocks where the variable is named `err`, or the user-defined identifiers
- Customizable highlight colors and virtual text
- Text concealment, no folding

## Requirements

- Neovim >= 0.11.0 (for `conceal_lines` support to completely hide error handling blocks)
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) with Go parser installed

### Optional 

Don't see the proper Treesitter parsing? 

- Treesitter prioritized over LSP Semantic Tokens.

``` lua
vim.highlight.priorities.semantic_tokens = 95 -- default is 125
vim.highlight.priorities.treesitter = 100 -- default is 100
```

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "TheNoeTrevino/no-go.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  ft = "go",
  opts = {
    -- Your configuration here (optional)
    -- lazy.nvim automatically calls setup() with the opts property
    identifiers = { "err", "error" }, -- Customize which identifiers to collapse
    -- look at the default config for more details
  },
}
```

## Configuration

### Default Configuration

```lua
require("no-go").setup({ -- required w/o lazy.nvim
  -- Enable the plugin behavior by default
  enabled = true,

  -- Identifiers to match in if statements (e.g., "if err != nil", "if error != nil")
  -- Only collapse blocks where the identifier is in this list
  identifiers = { "err" },

  -- Virtual text for collapsed error handling
  -- Built as: prefix + content + content_separator + return_character + suffix
  -- The default follows Jetbrains GoLand style of concealment:
  virtual_text = {
    prefix = ": ",
    content_separator = " ",
    return_character = "󱞿 ",
    suffix = "",
  },

  -- virtual text for collapsed import blocks
  -- Built as: prefix + content (num of packages) + suffix
  import_virtual_text = { -- e.g. ' 2  '
    prefix = " ",
    suffix = "  ",
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

  -- Reveal concealed lines when cursor is on the if err != nil line
  -- This allows you to inspect the error handling by hovering over the collapsed line
  reveal_on_cursor = true,
})
```

### Custom Virtual Text

The virtual text is dynamically built based on what's in the return statement. It's composed of four parts:
- **prefix**: What comes before the content
- **content**: The identifier from the return statement ('err', or what you set in the opts)
- **content_separator**: Space between content and return character
- **return_character**: The icon/symbol indicating a return
- **suffix**: What comes at the end

### Reveal on Cursor

The `reveal_on_cursor` feature automatically reveals concealed error handling blocks when you move your cursor to the `if err != nil` line. 
This allows you to inspect the actual error handling code without manually toggling concealment.

https://github.com/user-attachments/assets/b27bc069-4459-437f-8f74-599ce738536f

#### Reveal on Cursor Off (manual toggling)

https://github.com/user-attachments/assets/b9e336c7-fedc-4847-8960-5b9a527dd050

**How it works:**
- When your cursor is on the `if err != nil` line, the concealed block below is revealed
- You can move down into the revealed block and navigate around inside it
- While your cursor is anywhere inside the block (from the `if` line to the closing `}`) it will, of course, stay revealed
- When you move the cursor completely outside the block, it will conceal again automatically
- This gives you: compact view by default, detailed view when needed

> [!WARNING]
> PLEASE note that if you disable `reveal_on_cursor`, you MUST manually toggle concealment (like the video above)
> using the provided commands to access the error handling!
> Though, it is nice when you only want to view the happy path.

## Commands

The plugin provides user commands, rather than keymappings. You can of course do
that yourself. The exception is `j` and `k`. If you don't provide those, these keys will be set
to traverse the concealed text in an itelligent matter. If you are like myself and use `jkl;` instead of `hjkl`, 
you will have to set your own keymaps.

Here are the commands and how they interact with each other:

### Global Commands (affect all buffers)

- `:NoGoEnable` - Enable error collapsing globally (all Go buffers)
- `:NoGoDisable` - Disable error collapsing globally (all Go buffers)
- `:NoGoToggle` - Toggle error collapsing globally

### Buffer-Specific Commands (affect only current buffer)

- `:NoGoBufEnable` - Enable error collapsing for current buffer only
- `:NoGoBufDisable` - Disable error collapsing for current buffer only
- `:NoGoBufToggle` - Toggle error collapsing for current buffer only

> [!NOTE]
> **Hierarchy:** Global state overrides buffer-specific state. So, `NoGoDisable`
> will set ALL buffers to disabled. But, if you then run `NoGoBufEnable` in a
> specific buffer, it will enable the plugin behavior, only for that buffer.

## How It Works

The plugin uses Treesitter to parse your Go code and identify error handling patterns. It specifically looks for:

1. An `if` statement with a binary expression (e.g., `err != nil`)
2. The left side of the expression must be the identifier `err`, or one of whatever identifiers you have passed into the config
3. The consequence block must contain a `return` statement

When all conditions are met, the plugin will then:
- Adds virtual text at the end of the `if` line
- Hides the lines containing the error handling block using concealment (not folding)
- Highlights the virtual text with the `NoGoZone` highlight group

This approach ensures only standard Go error handling patterns are collapsed, avoiding false positives.

If you use a different variable name for your errors, refer to the configuration section. 

### Look at the AST Yourself

If you are interested in how the AST queries are structured, go over to one of
the if statements that this plugin conceals. Run the command
`:InspectTree`. It is actually quite neat!

Try out writing some queries yourself with the `EditQuery` command. 

## TODO

- [ ] Add command to toggle reveal on cursor
- [ ] Add support for the not operator. For stuff like: `if !ok {...`
- [ ] Link to a more default background, so colorschemes can set it
- [ ] Add support for gin? 
