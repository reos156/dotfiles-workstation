return {
  "nvim-treesitter/nvim-treesitter",
  -- Includes upstream Python compatibility and runtimepath health fixes.
  commit = "4916d6592ede8c07973490d9322f187e07dfefac",
  opts = function(_, opts)
    -- This revision handles JSONC through the JSON parser.
    opts.ensure_installed = vim.tbl_filter(function(lang)
      return lang ~= "jsonc"
    end, opts.ensure_installed or {})
  end,
}
