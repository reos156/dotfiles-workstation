local init_path = assert(vim.env.DOTFILES_TEST_NVIM_INIT, "DOTFILES_TEST_NVIM_INIT is required")
local real_vim = vim

local function load_with(fake)
  local setup_called = false
  package.loaded["config.nodejs"] = {
    setup = function(opts)
      assert(opts.silent == true)
      setup_called = true
    end,
  }
  package.loaded["config.lazy"] = true
  _G.vim = fake
  local ok, err = pcall(dofile, init_path)
  _G.vim = real_vim
  package.loaded["config.nodejs"] = nil
  package.loaded["config.lazy"] = nil
  assert(ok, err)
  assert(setup_called, "Node setup was not called")
end

local default_prefix = "/home/linuxbrew/.linuxbrew/bin"
local default_case = {
  env = { PATH = "/usr/bin" },
  fn = {
    isdirectory = function(path)
      return path == default_prefix and 1 or 0
    end,
    executable = function()
      return 0
    end,
  },
  opt = {},
  v = { shell_error = 0 },
}
load_with(default_case)
assert(default_case.env.PATH == "/usr/bin:" .. default_prefix, "default Linuxbrew prefix was not exposed")

local dynamic_case = {
  env = { PATH = "/usr/bin" },
  fn = {
    isdirectory = function()
      return 0
    end,
    executable = function(command)
      return command == "brew" and 1 or 0
    end,
    system = function(command)
      assert(command[1] == "brew" and command[2] == "--prefix")
      return "/opt/portable-homebrew\n"
    end,
  },
  opt = {},
  v = { shell_error = 0 },
}
load_with(dynamic_case)
assert(dynamic_case.env.PATH == "/usr/bin:/opt/portable-homebrew/bin", "dynamic Homebrew prefix was not exposed")
