-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
require("codecompanion").setup({
  adapters = {
    acp = {
      claude_code = function()
        return require("codecompanion.adapters").extend("claude_code", {
          env = {
            -- Never hardcode the token here (this file is in a public repo).
            -- Set it in ~/.zshrc.local:  export CLAUDE_CODE_OAUTH_TOKEN=...
            CLAUDE_CODE_OAUTH_TOKEN = os.getenv("CLAUDE_CODE_OAUTH_TOKEN") or "",
          },
        })
      end,
    },
  },
})

-- Set zsh as the terminal shell.
vim.opt.shell = "zsh"
