-- CodeCompanion with the Claude Code ACP adapter.
---@type LazySpec
return {
  "olimorris/codecompanion.nvim",
  version = "^19.0.0",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  opts = {
    adapters = {
      acp = {
        claude_code = function()
          return require("codecompanion.adapters").extend("claude_code", {
            env = {
              -- Never hardcode the token here (this file is in a public repo).
              -- Put it in a file under ~/.secrets/:
              --   export CLAUDE_CODE_OAUTH_TOKEN=...
              CLAUDE_CODE_OAUTH_TOKEN = os.getenv "CLAUDE_CODE_OAUTH_TOKEN" or "",
            },
          })
        end,
      },
    },
  },
}
