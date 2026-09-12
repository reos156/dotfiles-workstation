local lock_path = assert(vim.env.DOTFILES_RUNTIME_LOCK, "DOTFILES_RUNTIME_LOCK is required")
local expected_lazy = assert(vim.env.DOTFILES_RUNTIME_LAZY_COMMIT, "DOTFILES_RUNTIME_LAZY_COMMIT is required")
local data = vim.fn.stdpath("data")
local mason_root = data .. "/mason"
local parser_root = data .. "/site/parser"
local timeout_ms = 600000
local mason_source_prefixes = {
  ["angular-language-server"] = "pkg:npm/%40angular/language-server@",
  ["biome"] = "pkg:npm/%40biomejs/biome@",
  ["eslint-lsp"] = "pkg:npm/vscode-langservers-extracted@",
  ["json-lsp"] = "pkg:npm/vscode-langservers-extracted@",
  ["lua-language-server"] = "pkg:github/luals/lua-language-server@",
  ["markdown-toc"] = "pkg:npm/markdown-toc@",
  ["markdownlint-cli2"] = "pkg:npm/markdownlint-cli2@",
  ["marksman"] = "pkg:github/artempyanykh/marksman@",
  ["prettier"] = "pkg:npm/prettier@",
  ["shfmt"] = "pkg:github/mvdan/sh@",
  ["stylua"] = "pkg:github/johnnymorganz/stylua@",
}

local function read_file(path)
  local handle = assert(io.open(path, "rb"))
  local contents = handle:read("*a")
  handle:close()
  return contents
end

local function parse_lock()
  local result = { mason = {}, parsers = {} }
  for line in read_file(lock_path):gmatch("[^\n]+") do
    if line:sub(1, 1) ~= "#" and line:match("%S") then
      local kind, name, version, value = line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$")
      assert(kind, "invalid runtime lock row")
      if kind == "mason" then
        table.insert(result.mason, { name = name, version = version, executable = value })
      elseif kind == "parser" then
        table.insert(result.parsers, { name = name, plugin_commit = version, file = value })
      elseif kind == "tree-sitter-cli" then
        result.tree_sitter = { version = version, sha256 = value }
      else
        error("unknown runtime lock kind")
      end
    end
  end
  assert(result.tree_sitter and #result.mason == 11 and #result.parsers == 25, "incomplete runtime lock")
  return result
end

local function system_ok(command, timeout)
  local completed = vim.system(command, { text = true }):wait(timeout or 15000)
  return completed.code == 0, completed
end

local function restore_plugins()
  local lazy = require("lazy")
  lazy.restore({ wait = true, show = false })
  local lock = vim.json.decode(read_file(vim.fn.stdpath("config") .. "/lazy-lock.json"))
  assert(lock["lazy.nvim"].commit == expected_lazy, "lazy.nvim source lock changed")
  local plugins = require("lazy.core.config").plugins
  for name, plugin in pairs(plugins) do
    if plugin.enabled ~= false and plugin.url then
      local pin = assert(lock[name], "enabled plugin is absent from source lock")
      assert(plugin.dir and vim.fn.isdirectory(plugin.dir .. "/.git") == 1, "enabled plugin checkout is missing")
      local ok, completed = system_ok({ "git", "-C", plugin.dir, "rev-parse", "HEAD" })
      assert(ok and vim.trim(completed.stdout or "") == pin.commit, "enabled plugin checkout differs from source lock")
    end
  end
end

local function refresh_registry(registry)
  local done, success = false, false
  registry.refresh(function(ok)
    success = ok == true
    done = true
  end)
  assert(vim.wait(timeout_ms, function() return done end, 100), "Mason registry refresh timed out")
  assert(success, "Mason registry refresh failed")
end

local function receipt_for(name)
  return vim.json.decode(read_file(mason_root .. "/packages/" .. name .. "/mason-receipt.json"))
end

local function receipt_matches(item)
  local ok, receipt = pcall(receipt_for, item.name)
  if not ok then return false end
  local source_id = receipt.source and receipt.source.id or ""
  local source_prefix = mason_source_prefixes[item.name]
  return receipt.name == item.name
    and source_prefix ~= nil
    and source_id == source_prefix .. item.version
end

local function install_mason_package(registry, item)
  local package = registry.get_package(item.name)
  if not receipt_matches(item) then
    local callback_done, callback_success, callback_error = false, false, nil
    local handle = package:install({ version = item.version, force = true }, function(success, err)
      callback_success = success
      callback_error = err
      callback_done = true
    end)
    assert(
      handle and type(handle.once) == "function" and type(handle.is_closed) == "function",
      "Mason package install returned no usable handle for " .. item.name
    )

    local close_event = false
    handle:once("closed", function() close_event = true end)
    local function closed()
      local state_ok, value = pcall(handle.is_closed, handle)
      return state_ok and value == true
    end
    local completed = vim.wait(timeout_ms, function()
      return callback_done and (close_event or closed()) and closed()
    end, 100)
    if not completed then
      if closed() and not callback_done then
        error("Mason package install closed without a result callback for " .. item.name)
      elseif callback_done and not closed() then
        error("Mason package install callback completed but handle did not close for " .. item.name)
      end
      error("Mason package install timed out for " .. item.name)
    end

    local function safe_failure_detail(err)
      local detail = err
      if type(err) == "table" then
        detail = nil
        for _, key in ipairs({ "error", "reason", "message" }) do
          if type(err[key]) == "string" and err[key] ~= "" then
            detail = err[key]
            break
          end
        end
      end
      if type(detail) ~= "string" or detail == "" then return nil end
      detail = vim.trim(detail:gsub("[%c]+", " "))
      detail = detail:gsub("([?&][%w_%-]+)=([^&%s]+)", "%1=<redacted>")
      detail = detail:gsub("([Aa]uthorization:%s*)%S+", "%1<redacted>")
      detail = detail:gsub("([Bb]earer%s+)%S+", "%1<redacted>")
      detail = detail:gsub("([Tt]oken%s*[=:]%s*)%S+", "%1<redacted>")
      if #detail > 200 then detail = detail:sub(1, 200) .. "..." end
      return detail ~= "" and detail or nil
    end

    local cancelled = false
    if type(handle.is_cancelled) == "function" then
      local cancelled_ok, value = pcall(handle.is_cancelled, handle)
      cancelled = cancelled_ok and value == true
    end
    local detail = safe_failure_detail(callback_error)
    assert(
      not cancelled and callback_success == true,
      "Mason package install failed for " .. item.name .. (detail and (": " .. detail) or "")
    )
  end
  assert(receipt_matches(item), "Mason receipt does not match the expected package name and source version for " .. item.name)
end

local function repair_biome_native(item)
  local executable = mason_root .. "/bin/" .. item.executable
  if vim.fn.executable(executable) == 1 then return end
  local package_root = mason_root .. "/packages/biome"
  local ok = system_ok({
    "npm", "install", "--no-save", "--no-package-lock", "--prefix", package_root,
    "@biomejs/cli-linux-x64@2.5.12",
  }, timeout_ms)
  assert(ok, "pinned Biome native executable repair failed for " .. item.name)
  assert(vim.fn.executable(executable) == 1, "Biome native executable remains unavailable for " .. item.name)
  local version_ok = system_ok({ executable, "--version" })
  assert(version_ok, "Biome version check failed for " .. item.name)
end

local function verify_mason_executable(item)
  local executable = mason_root .. "/bin/" .. item.executable
  assert(vim.fn.executable(executable) == 1, "Mason executable is unavailable for " .. item.name)
  local ok, completed = system_ok({ executable, "--version" })
  if item.name == "marksman" and not ok and (completed.stderr or ""):find("Couldn't find a valid ICU package installed on the system", 1, true) then
    error("RUNTIME_BOOTSTRAP_MARKSMAN_ICU", 0)
  end
  assert(ok, "Mason executable version check failed for " .. item.name)
end

local function bootstrap_mason(runtime)
  require("lazy").load({ plugins = { "mason.nvim" }, wait = true })
  require("mason").setup({
    registries = { "github:mason-org/mason-registry" },
  })
  local registry = require("mason-registry")
  refresh_registry(registry)
  for _, item in ipairs(runtime.mason) do
    install_mason_package(registry, item)
    if item.name == "biome" then repair_biome_native(item) end
    verify_mason_executable(item)
  end
end

local function bootstrap_parsers(runtime)
  require("lazy").load({ plugins = { "nvim-treesitter" }, wait = true })
  local names = {}
  for _, item in ipairs(runtime.parsers) do
    assert(item.plugin_commit == runtime.parsers[1].plugin_commit, "parser plugin pins disagree")
    table.insert(names, item.name)
  end
  local operation = require("nvim-treesitter").install(names, { force = true, summary = true })
  local waited, result = pcall(function() return operation:wait(timeout_ms) end)
  assert(waited and result ~= false, "Treesitter parser installs did not complete")
  for _, item in ipairs(runtime.parsers) do
    assert(vim.fn.filereadable(parser_root .. "/" .. item.file) == 1, "Treesitter parser artifact is missing")
  end
  for _, language in ipairs({ "vim", "markdown" }) do
    local query_ok, query = pcall(vim.treesitter.query.get, language, "highlights")
    assert(query_ok and query ~= nil, "Treesitter highlights query does not compile")
  end
end

local ok, failure = xpcall(function()
  local runtime = parse_lock()
  restore_plugins()
  bootstrap_mason(runtime)
  bootstrap_parsers(runtime)
end, debug.traceback)

if not ok then
  if tostring(failure):find("RUNTIME_BOOTSTRAP_MARKSMAN_ICU", 1, true) then
    io.stdout:write("RUNTIME_BOOTSTRAP_MARKSMAN_ICU\n")
  else
    io.stdout:write("RUNTIME_BOOTSTRAP_FAILED\n", tostring(failure), "\n")
  end
  vim.cmd("cquit 1")
else
  io.stdout:write("RUNTIME_BOOTSTRAP_OK\n")
  vim.cmd("qa")
end
