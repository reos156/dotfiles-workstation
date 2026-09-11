-- Make an installed default Linuxbrew available even when brew is not yet in PATH.
local linuxbrew_bin = "/home/linuxbrew/.linuxbrew/bin"
if vim.fn.isdirectory(linuxbrew_bin) == 1 then
  vim.env.PATH = (vim.env.PATH or "") .. ":" .. linuxbrew_bin
end

-- Also discover non-default Homebrew installations from an executable brew.
if vim.fn.executable("brew") == 1 then
  local brew_prefix = vim.fn.system({ "brew", "--prefix" }):gsub("%s+$", "")
  local brew_bin = brew_prefix .. "/bin"
  if vim.v.shell_error == 0 and brew_prefix ~= "" and brew_bin ~= linuxbrew_bin then
    vim.env.PATH = (vim.env.PATH or "") .. ":" .. brew_bin
  end
end

-- Configure Node.js before loading plugins
require("config.nodejs").setup({ silent = true })

-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
vim.opt.timeoutlen = 1000
vim.opt.ttimeoutlen = 0
