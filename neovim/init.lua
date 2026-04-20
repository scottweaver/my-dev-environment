-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
require("codecompanion").setup({
  adapters = {
    acp = {
      claude_code = function()
        return require("codecompanion.adapters").extend("claude_code", {
          env = {
            CLAUDE_CODE_OAUTH_TOKEN = "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",
          },
        })
      end,
    },
  },
})

-- Set zsh as the terminal shell.
vim.opt.shell = "zsh"
