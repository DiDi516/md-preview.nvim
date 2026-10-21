-- export.lua — 导出自包含 HTML
local parse = require("md-preview.parse")
local render_html = require("md-preview.render_html")

local M = {}

--- 读取 buffer 全部文本
local function buf_text(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table.concat(lines, "\n")
end

--- 默认导出路径：与源文件同目录、同名，扩展名改为 .html
--- @param bufnr number
--- @return string
function M.default_path(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return vim.fn.expand("%:p:h") .. "/md-preview-export.html"
  end
  local base = name:gsub("%.[^%.\\/]+$", "")
  return base .. ".html"
end

--- 导出为 HTML 文件
--- @param bufnr number 源 buffer
--- @param path string|nil 目标路径，nil 时自动推导
--- @param opts table 完整配置（使用其中的 export 段）
--- @return boolean ok, string path|errmsg
function M.export(bufnr, path, opts)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  path = path or M.default_path(bufnr)
  opts = opts or {}

  local text = buf_text(bufnr)
  local ast = parse.parse(text)

  local title = opts.export and opts.export.title
  if not title then
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
      title = vim.fn.fnamemodify(name, ":t:r")
    else
      title = "Markdown 导出"
    end
  end

  local html = render_html.render(ast, opts.export or {}, { title = title })

  -- 确保父目录存在
  local dir = vim.fn.fnamemodify(path, ":h")
  if dir ~= "" and vim.fn.isdirectory(dir) == 0 then
    local ok = vim.fn.mkdir(dir, "p")
    if ok ~= 1 and vim.fn.isdirectory(dir) == 0 then
      return false, "无法创建目录: " .. dir
    end
  end

  local f, err = io.open(path, "wb")
  if not f then return false, "无法写入文件: " .. tostring(err) end
  f:write(html)
  f:close()
  return true, path
end

return M
