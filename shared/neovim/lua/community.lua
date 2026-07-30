-- AstroCommunity: import any community modules here
-- We import this file in `lazy_setup.lua` before the `plugins/` folder.
-- This guarantees that the specs are processed before any user plugins.

---@type LazySpec
return {
  "AstroNvim/astrocommunity",
  { import = "astrocommunity.pack.lua" },
  -- GitHub Copilot ghost-text line completion (auth: `:Copilot auth`,
  -- once per machine, uses the Copilot subscription).
  { import = "astrocommunity.completion.copilot-lua" },
}
