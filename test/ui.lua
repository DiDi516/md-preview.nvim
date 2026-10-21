-- md-preview.nvim UI 集成测试：窗口创建 / extmark 施加 / 滚动同步 / 导出
-- 在 headless nvim 中运行（headless 仍具备窗口布局与 extmark 能力）
vim.opt.runtimepath:append(vim.fn.stdpath("config") .. "/md-preview.nvim")

local function check(name, cond, extra)
  if cond then
    print(string.format("[PASS] %s", name))
  else
    print(string.format("[FAIL] %s %s", name, extra and tostring(extra) or ""))
  end
  return cond
end

local ok_all = true
local function chk(name, cond, extra)
  if not check(name, cond, extra) then ok_all = false end
end

--------------------------------------------------------------------------------
-- 准备一个 markdown 文件
--------------------------------------------------------------------------------
local mdpath = vim.fn.tempname() .. ".md"
local content = table.concat({
  "# 标题一",
  "",
  "正文 **粗体** 与 `code`。",
  "",
  "```python",
  "def hello(name):",
  "    return f\"你好 {name}\"",
  "```",
  "",
  "| a | b |",
  "|---|---|",
  "| 1 | 2 |",
  "",
  "$$x^2$$",
}, "\n")
local f = io.open(mdpath, "w")
f:write(content)
f:close()

--------------------------------------------------------------------------------
-- setup
--------------------------------------------------------------------------------
local md = require("md-preview")
local ok_setup, err = pcall(md.setup, {
  position = "right",
  size = 0.5,
  debounce = 0,
  show_url = false,
})
chk("setup 无异常", ok_setup, err)

-- 命令已注册
local cmds = { "MdPreviewStart", "MdPreviewStop", "MdPreviewToggle", "MdPreviewRefresh", "MdPreviewExport" }
local all_cmds = true
for _, c in ipairs(cmds) do
  if vim.fn.exists(":" .. c) == 0 then all_cmds = false end
end
chk("五个命令均已注册", all_cmds)

--------------------------------------------------------------------------------
-- 打开源文件并启动预览
--------------------------------------------------------------------------------
vim.cmd("edit " .. vim.fn.fnameescape(mdpath))
vim.bo.filetype = "markdown"
local src_buf = vim.api.nvim_get_current_buf()
local win_count_before = #vim.api.nvim_list_wins()

local ok_start, err2 = pcall(md.start)
chk("start 无异常", ok_start, err2)

local sess = md.get_sessions()[src_buf]
chk("会话已建立", sess ~= nil)

if sess then
  chk("预览窗口已创建", vim.api.nvim_win_is_valid(sess.prev_win))
  chk("预览 buffer 有效", vim.api.nvim_buf_is_valid(sess.prev_buf))
  chk("窗口数增加", #vim.api.nvim_list_wins() > win_count_before,
    string.format("%d -> %d", win_count_before, #vim.api.nvim_list_wins()))

  -- 预览 buffer 内容
  local plines = vim.api.nvim_buf_get_lines(sess.prev_buf, 0, -1, false)
  chk("预览 buffer 非空", #plines > 0, #plines)
  chk("预览内容含标题文本", (function()
    for _, l in ipairs(plines) do if l:find("标题一") then return true end end
    return false
  end)(), table.concat(plines, "\n"))
  chk("预览内容含代码块边框", (function()
    for _, l in ipairs(plines) do if l:find("╭") then return true end end
    return false
  end)(), table.concat(plines, "\n"))
  chk("预览内容含表格", (function()
    for _, l in ipairs(plines) do if l:find("┌") then return true end end
    return false
  end)())

  -- extmark 施加情况
  local marks = vim.api.nvim_buf_get_extmarks(sess.prev_buf, md.ns, 0, -1, { details = true })
  chk("extmark 已施加", #marks > 0, #marks)

  -- 校验每个 extmark 的列范围都不越界对应行
  local bad = nil
  for _, m in ipairs(marks) do
    local row, col = m[2], m[3]
    local d = m[4] or {}
    local erow, ecol = d.end_row or row, d.end_col
    local line = plines[row + 1] or ""
    if ecol and ecol > #line then
      bad = string.format("行 %d extmark end_col %d > 行长 %d (%q)", row, ecol, #line, line)
      break
    end
    if not d.hl_group then
      bad = string.format("行 %d extmark 缺少 hl_group", row)
      break
    end
  end
  chk("extmark 范围均合法且带高亮组", bad == nil, bad)

  -- 验证高亮组确实存在（否则终端看不到颜色）
  local missing = nil
  local seen = {}
  for _, m in ipairs(marks) do
    local hg = (m[4] or {}).hl_group
    if hg and not seen[hg] then
      seen[hg] = true
      local ok_hl = pcall(vim.api.nvim_get_hl, 0, { name = hg })
      if not ok_hl then missing = hg end
    end
  end
  chk("所有引用的高亮组均已定义", missing == nil, missing)

  ------------------------------------------------------------------------------
  -- 滚动同步映射
  ------------------------------------------------------------------------------
  local sync = require("md-preview.sync")
  chk("同步已挂载", sync.is_attached() == true)
  local mapped = sync.map_src_to_out(1)
  chk("源行 1 可映射到预览行", mapped ~= nil, tostring(mapped))
  local back = mapped and sync.map_out_to_src(mapped)
  chk("预览行可反向映射", back ~= nil, tostring(back))

  ------------------------------------------------------------------------------
  -- 修改内容后自动重渲染
  ------------------------------------------------------------------------------
  local before = vim.api.nvim_buf_line_count(sess.prev_buf)
  vim.api.nvim_buf_set_lines(src_buf, -1, -1, false, { "", "## 新增标题", "", "新增段落内容。" })
  -- headless 下事件循环不自动推进，改为直接同步渲染验证刷新链路
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = src_buf })
  md.render_session(sess)
  local after = vim.api.nvim_buf_line_count(sess.prev_buf)
  chk("文本变更后预览已更新", after > before, string.format("%d -> %d", before, after))
  local has_new = false
  for _, l in ipairs(vim.api.nvim_buf_get_lines(sess.prev_buf, 0, -1, false)) do
    if l:find("新增标题") then has_new = true end
  end
  chk("新内容出现在预览中", has_new)
end

--------------------------------------------------------------------------------
-- 导出
--------------------------------------------------------------------------------
local export = require("md-preview.export")
local outpath = vim.fn.tempname() .. ".html"
local ok_exp, res = export.export(src_buf, outpath, md.get_opts())
chk("导出成功", ok_exp, tostring(res))
if ok_exp then
  local g = io.open(outpath, "r")
  local html = g and g:read("*a") or ""
  if g then g:close() end
  chk("导出文件非空", #html > 500, #html)
  chk("导出含表格", html:find("<table>") ~= nil)
  chk("导出含代码块", html:find("<code") ~= nil)
  chk("导出含二级标题", html:find("<h2>") ~= nil)
end

--------------------------------------------------------------------------------
-- 停止
--------------------------------------------------------------------------------
if sess then
  local ok_stop, err3 = pcall(md.stop)
  chk("stop 无异常", ok_stop, err3)
  chk("会话已清理", md.get_sessions()[src_buf] == nil)
  chk("预览窗口已关闭", not vim.api.nvim_win_is_valid(sess.prev_win))
end

-- 清理临时文件
os.remove(mdpath)
if ok_exp then os.remove(outpath) end

print("")
if ok_all then
  print("===== UI 集成测试全部通过 =====")
else
  print("===== UI 集成测试存在失败 =====")
  vim.cmd("cquit 1")
end
