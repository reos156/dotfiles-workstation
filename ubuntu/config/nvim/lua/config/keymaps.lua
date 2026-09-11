vim.keymap.set("i", "<C-b>", "<C-o>de", { desc = "Delete to end of word" })
vim.keymap.set({ "i", "v" }, "<C-c>", "<Esc>", { desc = "Escape" })
vim.keymap.set("n", "<C-s>", "<cmd>write<cr>", { desc = "Save file" })
vim.keymap.set("n", "<leader>bq", "<cmd>%bdelete|edit #|normal `\"<cr>", { desc = "Delete other buffers" })

local function selected_text()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local lines = vim.fn.getline(start_pos[2], end_pos[2])
  if #lines == 0 then
    return ""
  end
  lines[1] = string.sub(lines[1], start_pos[3])
  lines[#lines] = string.sub(lines[#lines], 1, end_pos[3])
  return table.concat(lines, "\n")
end

vim.keymap.set("v", "<leader>sg", function()
  require("fzf-lua").live_grep({ search = selected_text() })
end, { desc = "Grep selection" })

vim.keymap.set("v", "<leader>sG", function()
  local root = vim.fs.root(0, ".git") or vim.fn.getcwd()
  require("fzf-lua").live_grep({ cwd = root, search = selected_text() })
end, { desc = "Grep selection from project root" })
