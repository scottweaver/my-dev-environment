return {
  "AstroNvim/astrocore",
  ---@type AstroCoreOpts
  opts = {
    mappings = {
      n = {
        ["<Leader>fd"] = {
          function()
            require("telescope.builtin").find_files({
              find_command = { "fd", "--type", "d", "--hidden", "--exclude", ".git" },
              prompt_title = "Find Directories",
            })
          end,
          desc = "Find directories",
        },
        ["<Leader>fh"] = {
          function()
            require("telescope.builtin").find_files({
              cwd = vim.fn.expand("$HOME"),
              prompt_title = "Find Files (Home)",
              hidden = false, -- set to true to include dotfiles
            })
          end,
          desc = "Find files in home directory",
        },
      },
    },
  },
}
