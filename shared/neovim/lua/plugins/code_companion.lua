-- CodeCompanion chat wired to Claude via the Claude Code ACP adapter —
-- bills the Claude Max subscription, not API keys. The bridge binary is
-- the @zed-industries/claude-code-acp npm global (synced by envsync).
---@type LazySpec
return {
  "olimorris/codecompanion.nvim",
  version = "^19.0.0",
  cmd = { "CodeCompanion", "CodeCompanionChat", "CodeCompanionActions", "CodeCompanionCmd" },
  keys = {
    { "<Leader>aa", "<cmd>CodeCompanionChat Toggle<cr>", desc = "Toggle Claude chat", mode = { "n", "v" } },
    { "<Leader>an", "<cmd>CodeCompanionChat<cr>", desc = "New Claude chat" },
    { "<Leader>ap", "<cmd>CodeCompanionActions<cr>", desc = "AI actions", mode = { "n", "v" } },
  },
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  opts = {
    interactions = {
      -- Claude (Max subscription) is the chat adapter.
      chat = { adapter = "claude_code" },
    },
    adapters = {
      acp = {
        claude_code = function()
          return require("codecompanion.adapters").extend("claude_code", {
            env = {
              -- Never hardcode the token here (this file is in a public repo).
              -- Generate with `claude setup-token`, then put in a file under
              -- ~/.secrets/:  export CLAUDE_CODE_OAUTH_TOKEN=...
              CLAUDE_CODE_OAUTH_TOKEN = os.getenv "CLAUDE_CODE_OAUTH_TOKEN" or "",
              -- Pin the editor chat to Fable 5 (overridable per machine
              -- by exporting ANTHROPIC_MODEL before launching nvim).
              ANTHROPIC_MODEL = os.getenv "ANTHROPIC_MODEL" or "claude-fable-5",
            },
          })
        end,
      },
    },
  },
}
