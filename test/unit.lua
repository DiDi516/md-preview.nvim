-- md-preview.nvim 冒烟测试（headless nvim 中运行）
-- 覆盖：解析 → 终端渲染 → 数学 → Mermaid → 代码高亮 → 行号映射 → HTML 导出
local PLUGIN = os.getenv("MDP_PLUGIN")
  or (vim.fn.stdpath("config") .. "/md-preview.nvim")
vim.opt.runtimepath:append(PLUGIN)

local parse = require("md-preview.parse")
local render_term = require("md-preview.render_term")
local render_html = require("md-preview.render_html")
local mathr = require("md-preview.math")
local mermaidr = require("md-preview.mermaid")
local codehl = require("md-preview.codehl")
local util = require("md-preview.util")

local ok_all = true
local function check(name, cond, extra)
  if cond then
    print(string.format("[PASS] %s", name))
  else
    ok_all = false
    print(string.format("[FAIL] %s %s", name, extra and tostring(extra) or ""))
  end
end

--------------------------------------------------------------------------------
-- 1. 基础工具
--------------------------------------------------------------------------------
-- "中文ab" = 2*2 + 2 = 6 列
check("util.width 中文按 2 列计算", util.width("中文ab") == 6, util.width("中文ab"))
check("util.pad 按显示宽度补齐", util.width(util.pad("中文", 10)) == 10)
check("util.truncate 按显示宽度截断", util.width(util.truncate("中文abc", 5)) <= 5)

--------------------------------------------------------------------------------
-- 2. 解析器
--------------------------------------------------------------------------------
local MD = [[
---
title: 测试
---

# 一级标题

这是**粗体**、*斜体*、~~删除线~~、`行内代码`与[链接](https://example.com)。

## 二级标题

- 项目一
- 项目二
  - 嵌套项
- [x] 已完成任务
- [ ] 未完成任务

1. 有序一
2. 有序二

> 引用块内容
> 第二行

| 名称 | 数量 | 说明 |
|:-----|:----:|-----:|
| 苹果 | 3 | 水果 |
| 中文列 | 12 | 测试 |

```lua
local function greet(name)
  -- 问候
  return "你好, " .. name
end
```

行内公式 $E = mc^2$ 与块级公式：

$$
\sum_{i=1}^{n} x_i^2 \leq \frac{1}{2}
$$

```mermaid
graph TD
  A[开始] --> B{判断}
  B -->|是| C[结束]
  B -->|否| D[继续]
```

---

脚注示例[^1]。

[^1]: 这是脚注内容。
]]

local ast = parse.parse(MD)
check("解析返回 blocks", type(ast.blocks) == "table" and #ast.blocks > 0, #ast.blocks)

local kinds = {}
for _, b in ipairs(ast.blocks) do
  kinds[b.t] = (kinds[b.t] or 0) + 1
end
check("识别出 frontmatter", kinds.frontmatter == 1, vim.inspect(kinds))
check("识别出 heading", (kinds.heading or 0) >= 2, vim.inspect(kinds))
check("识别出 list", (kinds.list or 0) >= 2, vim.inspect(kinds))
check("识别出 blockquote", kinds.blockquote == 1, vim.inspect(kinds))
check("识别出 table", kinds.table == 1, vim.inspect(kinds))
check("识别出 code", kinds.code == 1, vim.inspect(kinds))
check("识别出 math", kinds.math == 1, vim.inspect(kinds))
check("识别出 mermaid", kinds.mermaid == 1, vim.inspect(kinds))
check("识别出 hr", kinds.hr == 1, vim.inspect(kinds))
check("识别出 footnote", kinds.footnote == 1, vim.inspect(kinds))

-- 行内节点
local function find_inline(nodes, t)
  for _, n in ipairs(nodes) do
    if n.t == t then return n end
    if n.children then
      local r = find_inline(n.children, t)
      if r then return r end
    end
  end
  return nil
end
local para
for _, b in ipairs(ast.blocks) do
  if b.t == "paragraph" and find_inline(b.inline, "strong") then para = b break end
end
check("段落含 strong", find_inline(para.inline, "strong") ~= nil)
check("段落含 em", find_inline(para.inline, "em") ~= nil)
check("段落含 del", find_inline(para.inline, "del") ~= nil)
check("段落含 code", find_inline(para.inline, "code") ~= nil)
check("段落含 link", find_inline(para.inline, "link") ~= nil)

-- 表格结构
local tbl
for _, b in ipairs(ast.blocks) do if b.t == "table" then tbl = b break end
end
check("表格 3 列", #tbl.header == 3, #tbl.header)
check("表格 2 行", #tbl.rows == 2, #tbl.rows)
check("表格对齐解析", tbl.aligns[1] == "left" and tbl.aligns[2] == "center" and tbl.aligns[3] == "right",
  vim.inspect(tbl.aligns))

--------------------------------------------------------------------------------
-- 3. 终端渲染
--------------------------------------------------------------------------------
local ropts = {
  width = 78, show_url = false, image_icon = "▣",
  code_lang_label = true, code_line_numbers = false,
  quote_bar = "▎", todo_done = "[✓]", todo_pending = "[ ]",
  heading_markers = { "", "", "▍", "▎", "·", "·" },
}
local lines = render_term.render(ast, ropts)
check("渲染输出非空", #lines > 0, #lines)

-- 检查 span 合法性：列号必须在行内且不越界
local span_err = nil
for i, l in ipairs(lines) do
  for _, sp in ipairs(l.spans) do
    if sp[1] < 0 or sp[2] > #l.text or sp[1] >= sp[2] then
      span_err = string.format("行 %d span 越界: [%d,%d) text=%q", i, sp[1], sp[2], l.text)
      break
    end
  end
  if span_err then break end
end
check("所有 span 列号合法", span_err == nil, span_err)

-- 表格应出现制表符边框
local has_table_border = false
for _, l in ipairs(lines) do
  if l.text:find("┌") and l.text:find("┐") then has_table_border = true end
end
check("渲染出表格边框", has_table_border)

-- 代码块边框
local has_code_border = false
for _, l in ipairs(lines) do
  if l.text:find("╭") and l.text:find("lua") then has_code_border = true end
end
check("渲染出代码块边框与语言名", has_code_border)

-- 任务列表
local has_todo = false
for _, l in ipairs(lines) do
  if l.text:find("✓") then has_todo = true end
end
check("渲染出任务列表勾选框", has_todo)

-- 行宽不得超过设定宽度（中文按显示宽度）
local over = nil
for i, l in ipairs(lines) do
  if util.width(l.text) > ropts.width + 2 then
    over = string.format("行 %d 宽度 %d > %d: %s", i, util.width(l.text), ropts.width, l.text)
    break
  end
end
check("渲染行未超宽", over == nil, over)

--------------------------------------------------------------------------------
-- 4. 行号映射
--------------------------------------------------------------------------------
local s2o, o2s = render_term.build_maps(lines)
check("o2s 覆盖所有渲染行", (function()
  for i = 1, #lines do if not o2s[i] then return false end end
  return true
end)())
-- 源第 4 行（# 一级标题）应能映射
local mapped = s2o[4] or s2o[5] or s2o[6]
check("源行可映射到渲染行", mapped ~= nil, vim.inspect({ s2o[4], s2o[5], s2o[6] }))

--------------------------------------------------------------------------------
-- 5. 数学
--------------------------------------------------------------------------------
check("数学：上标", mathr.convert("x^2") == "x²", mathr.convert("x^2"))
check("数学：下标", mathr.convert("x_i") == "xᵢ", mathr.convert("x_i"))
check("数学：希腊字母", mathr.convert("\\alpha") == "α", mathr.convert("\\alpha"))
check("数学：求和", mathr.convert("\\sum") == "∑", mathr.convert("\\sum"))
check("数学：分式", mathr.convert("\\frac{a}{b}") == "a⁄b", mathr.convert("\\frac{a}{b}"))
check("数学：根号", mathr.convert("\\sqrt{x}") == "√(x)", mathr.convert("\\sqrt{x}"))
check("数学：不等式", mathr.convert("a \\leq b") == "a ≤ b", mathr.convert("a \\leq b"))
local mres = mathr.convert("\\sum_{i=1}^{n} x_i^2")
check("数学：复合公式可转换", mres:find("∑") ~= nil, mres)

--------------------------------------------------------------------------------
-- 6. Mermaid
--------------------------------------------------------------------------------
-- 注意：用 table.concat 而非 [[...]]，避免内容中的 "]]" 提前终止长字符串
local fc = mermaidr.render(table.concat({
  "graph TD",
  "  A[开始] --> B{判断}",
  "  B -->|是| C[结束]",
  "  B -->|否| D[继续]",
}, "\n"))
check("mermaid flowchart 渲染成功", fc.ok == true, vim.inspect(fc))
if fc.ok then
  local joined = table.concat(fc.lines, "\n")
  check("flowchart 含节点文本", joined:find("开始") ~= nil, joined)
  check("flowchart 含箭头", joined:find("▼") ~= nil or joined:find("▶") ~= nil, joined)
end

local sq = mermaidr.render([[sequenceDiagram
  Alice->>Bob: 你好
  Bob-->>Alice: 你好啊]])
check("mermaid sequence 渲染成功", sq.ok == true, vim.inspect(sq))
if sq.ok then
  local joined = table.concat(sq.lines, "\n")
  check("sequence 含参与者", joined:find("Alice") ~= nil and joined:find("Bob") ~= nil, joined)
end

local un = mermaidr.render("pie title 分布\n  \"A\" : 30")
check("不支持的图类型被正确标记", un.ok == false and un.kind == "unsupported", vim.inspect(un))

--------------------------------------------------------------------------------
-- 7. 代码高亮
--------------------------------------------------------------------------------
local toks = codehl.tokenize_line("local x = 1 -- 注释", codehl.lang_def("lua"), {})
check("lua 关键字被识别", (function()
  for _, t in ipairs(toks) do if t[3] == "keyword" then return true end end
  return false
end)(), vim.inspect(toks))
check("lua 注释被识别", (function()
  for _, t in ipairs(toks) do if t[3] == "comment" then return true end end
  return false
end)(), vim.inspect(toks))
check("支持语言数量 >= 20", (function()
  local n = 0
  for _ in pairs(codehl.LANGS) do n = n + 1 end
  return n >= 20
end)(), (function() local n = 0 for _ in pairs(codehl.LANGS) do n = n + 1 end return n end)())

--------------------------------------------------------------------------------
-- 8. HTML 导出
--------------------------------------------------------------------------------
local html = render_html.render(ast, { cdn = {} }, { title = "测试" })
check("HTML 含 doctype", html:find("<!DOCTYPE html>") ~= nil)
check("HTML 含 h1", html:find("<h1>") ~= nil)
check("HTML 含 table", html:find("<table>") ~= nil)
check("HTML 含 code", html:find("<code") ~= nil)
check("HTML 含 mermaid 块", html:find('class="mermaid"') ~= nil)
check("HTML 转义了尖括号", html:find("<script>") == nil)

--------------------------------------------------------------------------------
-- 输出一段渲染样例，便于人工核对
--------------------------------------------------------------------------------
print("\n===== 终端渲染样例（前 46 行）=====")
for i = 1, math.min(46, #lines) do
  print(string.format("%3d|%s", i, lines[i].text))
end
print(string.format("===== 共 %d 行 =====", #lines))

print("")
if ok_all then
  print("===== 全部断言通过 =====")
else
  print("===== 存在失败断言 =====")
end
-- 退出码：失败时非 0
if not ok_all then vim.cmd("cquit 1") end
