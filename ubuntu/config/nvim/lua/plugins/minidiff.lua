return {
  {
    "nvim-mini/mini.diff",
    init = function()
      local function set_diff_highlights()
        local set = vim.api.nvim_set_hl

        -- git-split-diffs "Dark" theme.
        local added_text = "#66cc66"
        local added_bg = "#303a30"
        local deleted_text = "#cc6666"
        local deleted_bg = "#3a3030"

        set(0, "MiniDiffSignAdd", { fg = added_text, bold = true })
        set(0, "MiniDiffSignChange", { fg = added_text, bold = true })
        set(0, "MiniDiffSignDelete", { fg = deleted_text, bold = true })

        set(0, "MiniDiffOverAdd", { fg = added_text, bg = added_bg })
        set(0, "MiniDiffOverChange", { fg = "#ffcccc", bg = "#612626" })
        set(0, "MiniDiffOverChangeBuf", { fg = "#ccffcc", bg = "#266126" })
        set(0, "MiniDiffOverContext", { fg = deleted_text, bg = deleted_bg })
        set(0, "MiniDiffOverContextBuf", { fg = added_text, bg = added_bg })
        set(0, "MiniDiffOverDelete", { fg = deleted_text, bg = deleted_bg })
      end

      local group = vim.api.nvim_create_augroup("MiniDiffCustom", { clear = true })

      set_diff_highlights()
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = group,
        callback = set_diff_highlights,
      })

      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "MiniDiffUpdated",
        callback = function(event)
          local diff = require("mini.diff")
          local data = diff.get_buf_data(event.buf)

          if data and not data.overlay then
            diff.toggle_overlay(event.buf)
          end
        end,
      })
    end,
  },
}
