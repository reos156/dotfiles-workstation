local active_path = assert(vim.env.DOTFILES_TEST_ACTIVE_UI, "DOTFILES_TEST_ACTIVE_UI is required")
local published_path = assert(vim.env.DOTFILES_TEST_PUBLISHED_UI, "DOTFILES_TEST_PUBLISHED_UI is required")

local handle = assert(io.open(active_path, "rb"))
local active_source = handle:read("*a")
handle:close()
local expected = assert(active_source:match("header%s*=%s*%[%[(.-)%]%],"), "active long-bracket header not found")

local specs = assert(dofile(published_path))
local actual
for _, spec in ipairs(specs) do
  if spec[1] == "folke/snacks.nvim" then
    actual = spec.opts.dashboard.preset.header
    break
  end
end

assert(type(actual) == "string", "published evaluated dashboard header not found")
assert(actual == expected, string.format("dashboard header bytes differ: active=%d published=%d", #expected, #actual))
assert(actual:sub(1, 1) == "\n" and actual:sub(-1) == "\n", "dashboard header newline semantics changed")
io.stdout:write(string.format("dashboard header bytes match active source: %d\n", #actual))
