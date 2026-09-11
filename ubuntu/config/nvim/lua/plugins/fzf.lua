return {
  {
    "ibhagwan/fzf-lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      fzf_opts = { ["--layout"] = "reverse-list" },
      winopts = {
        height = 0.85,
        width = 0.85,
        preview = { layout = "flex" },
      },
      files = { cwd_prompt = false },
      grep = { rg_glob = true },
    },
  },
}
