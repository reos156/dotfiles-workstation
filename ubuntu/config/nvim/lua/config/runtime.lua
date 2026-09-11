local M = {}

local function executable(path)
  return path and path ~= "" and vim.fn.executable(path) == 1
end

local function discover_node()
  local candidates = {}
  if vim.env.NVM_BIN then
    table.insert(candidates, vim.env.NVM_BIN .. "/node")
  end
  if vim.env.VOLTA_HOME then
    table.insert(candidates, vim.env.VOLTA_HOME .. "/bin/node")
  end

  local brew = vim.fn.exepath("brew")
  if executable(brew) then
    local output = vim.fn.systemlist({ brew, "--prefix", "node" })
    if vim.v.shell_error == 0 and output[1] then
      table.insert(candidates, output[1] .. "/bin/node")
    end
  end
  table.insert(candidates, vim.fn.exepath("node"))

  for _, candidate in ipairs(candidates) do
    if executable(candidate) then
      vim.g.node_host_prog = candidate
      return
    end
  end
end

local function configure_wsl_clipboard()
  if vim.fn.has("wsl") ~= 1 or vim.fn.executable("win32yank.exe") ~= 1 then
    return
  end
  vim.g.clipboard = {
    name = "win32yank",
    copy = {
      ["+"] = { "win32yank.exe", "-i", "--crlf" },
      ["*"] = { "win32yank.exe", "-i", "--crlf" },
    },
    paste = {
      ["+"] = { "win32yank.exe", "-o", "--lf" },
      ["*"] = { "win32yank.exe", "-o", "--lf" },
    },
    cache_enabled = false,
  }
end

function M.setup()
  discover_node()
  configure_wsl_clipboard()
end

return M
