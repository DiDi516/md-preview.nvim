-- render_term.lua — AST → 终端渲染行
-- 输出结构：lines[i] = { text = "…", spans = { {start_col, end_col, hl} }, src = 源行号 }
-- 列号一律为 0-based 字节偏移（extmark 要求），[start, end) 左闭右开。
local util = require("md-preview.util")
local theme = require("md-preview.theme")
local codehl = require("md-preview.codehl")
local mathr = require("md-preview.math")
local mermaidr = require("md-preview.mermaid")

local M = {}

-- 强调位掩码
local B, I, S = 1, 2, 4

local EMPH = {
  [0] = nil,
  [B] = theme.HL.EmphB,
  [I] = theme.HL.EmphI,
  [B + I] = theme.HL.EmphBI,
  [S] = theme.HL.EmphS,
  [B + S] = theme.HL.EmphBS,
  [I + S] = theme.HL.EmphIS,
  [B + I + S] = theme.HL.EmphBIS,
}

local LINK_EMPH = {
  [0] = theme.HL.Link,
  [B] = theme.HL.LinkB,
  [I] = theme.HL.LinkI,
  [B + I] = theme.HL.LinkBI,
  [S] = theme.HL.Link,
  [B + S] = theme.HL.LinkB,
  [I + S] = theme.HL.LinkI,
  [B + I + S] = theme.HL.LinkBI,
}

--------------------------------------------------------------------------------
-- 基础工具
--------------------------------------------------------------------------------

local function newb()
  return { text = "", spans = {} }
end

local function add(b, s, hl)
  if not s or s == "" then return end
  local st = #b.text
  b.text = b.text .. s
  if hl then
    b.spans[#b.spans + 1] = { st, #b.text, hl }
  end
end

local function push(ctx, text, spans, src)
  ctx.out[#ctx.out + 1] = { text = text, spans = spans or {}, src = src }
end

--- 给一整行加前缀，并同步平移所有 span
local function prefix_line(line, pfx, pfx_hl)
  if pfx == "" then return end
  local plen = #pfx
  line.text = pfx .. line.text
  for _, sp in ipairs(line.spans) do
    sp[1] = sp[1] + plen
    sp[2] = sp[2] + plen
  end
  if pfx_hl then table.insert(line.spans, 1, { 0, plen, pfx_hl }) end
end

--- 平移 spans（用于缩进）
local function shift_spans(spans, n)
  if n == 0 then return spans end
  for _, sp in ipairs(spans) do
    sp[1] = sp[1] + n
    sp[2] = sp[2] + n
  end
  return spans
end

--------------------------------------------------------------------------------
-- 折行
--------------------------------------------------------------------------------

--- 按显示宽度折行；\n 视为强制断点，空格优先作为断点，CJK 可任意断
local function wrap(text, spans, width)
  local segs = {}
  if width <= 0 then
    -- 不限制宽度：只按 \n 切分
    local bs = 1
    local i = 1
    while i <= #text + 1 do
      if i > #text or text:sub(i, i) == "\n" then
        segs[#segs + 1] = { bs = bs, be = i - 1 }
        bs = i + 1
      end
      i = i + 1
    end
  else
    local bs, lw = 1, 0
    local last_space = nil
    local i, n = 1, #text
    while i <= n do
      local ch = text:sub(i, i)
      if ch == "\n" then
        segs[#segs + 1] = { bs = bs, be = i - 1 }
        bs, lw, last_space = i + 1, 0, nil
        i = i + 1
        goto continue
      end
      local cp, nb = util.decode_utf8(text, i)
      if ch == " " then last_space = i end
      if lw + util.char_width(cp) > width and lw > 0 then
        local brk = last_space or i
        segs[#segs + 1] = { bs = bs, be = brk - 1 }
        bs = (last_space and last_space + 1) or i
        lw, last_space = 0, nil
        i = bs
        goto continue
      end
      lw = lw + util.char_width(cp)
      i = i + nb
      ::continue::
    end
    if bs <= n then segs[#segs + 1] = { bs = bs, be = n } end
    if #segs == 0 then segs[#segs + 1] = { bs = 1, be = 0 } end
  end

  local out = {}
  for _, seg in ipairs(segs) do
    local t = text:sub(seg.bs, seg.be)
    local ss = {}
    local base = seg.bs - 1
    for _, sp in ipairs(spans or {}) do
      local s = math.max(sp[1], base)
      local e = math.min(sp[2], seg.be)
      if e > s then ss[#ss + 1] = { s - base, e - base, sp[3] } end
    end
    out[#out + 1] = { text = t, spans = ss }
  end
  return out
end

--------------------------------------------------------------------------------
-- 行内渲染
--------------------------------------------------------------------------------

local function render_inline(nodes, ctx, b, mask, in_link)
  mask = mask or 0
  for _, n in ipairs(nodes) do
    local t = n.t
    if t == "text" then
      add(b, n.value, in_link and LINK_EMPH[mask] or EMPH[mask])
    elseif t == "code" then
      add(b, n.value, theme.HL.InlineCode)
    elseif t == "strong" then
      render_inline(n.children, ctx, b, mask + B, in_link)
    elseif t == "em" then
      render_inline(n.children, ctx, b, mask + I, in_link)
    elseif t == "del" then
      render_inline(n.children, ctx, b, mask + S, in_link)
    elseif t == "mark" then
      local st = #b.text
      render_inline(n.children, ctx, b, mask, in_link)
      if #b.text > st then
        b.spans[#b.spans + 1] = { st, #b.text, theme.HL.Mark }
      end
    elseif t == "link" then
      local st = #b.text
      -- 继承外层强调（如 **[链接](url)** 需要同时保留粗体）
      render_inline(n.children, ctx, b, mask, true)
      if #b.text == st then add(b, n.url, theme.HL.Link) end
      if ctx.opts.show_url then
        add(b, " " .. n.url, theme.HL.LinkUrl)
      end
    elseif t == "autolink" then
      add(b, n.url, theme.HL.Link)
    elseif t == "image" then
      local alt = n.alt or ""
      if alt == "" then
        alt = n.url:match("([^/%\\]+)$") or n.url
      end
      add(b, (ctx.opts.image_icon or "▣") .. " " .. alt, theme.HL.Image)
    elseif t == "math" then
      add(b, mathr.convert(n.value), theme.HL.Math)
    elseif t == "footnote_ref" then
      add(b, "[^" .. n.label .. "]", theme.HL.Footnote)
    elseif t == "br" then
      add(b, "\n")
    elseif t == "html" then
      -- 行内 HTML 标签在预览中隐藏（标签本身不是正文内容）
    end
  end
end

--- 行内渲染为字符串 + spans（供表格单元格等处使用）
local function inline_to_text(nodes, ctx)
  local b = newb()
  render_inline(nodes, ctx, b, 0, false)
  return b.text, b.spans
end

--------------------------------------------------------------------------------
-- 块级渲染
--------------------------------------------------------------------------------

local function render_heading(b, ctx, indent_str)
  local hl = theme.HL["H" .. b.level]
  local bb = newb()
  render_inline(b.inline, ctx, bb, 0, false)
  local w = ctx.width - #indent_str
  local lines = wrap(bb.text, bb.spans, w > 0 and w or 0)

  local marker = (ctx.opts.heading_markers or {})[b.level] or ""
  if b.level == 1 then
    local bar = string.rep("━", math.min(util.width(bb.text) + 2, w > 0 and w or 40))
    push(ctx, indent_str .. bar, { { #indent_str, #indent_str + #bar, theme.HL.H1Bar } }, b.src_line)
    for _, l in ipairs(lines) do
      local sps = shift_spans(l.spans, #indent_str)
      push(ctx, indent_str .. l.text, sps, b.src_line)
    end
  elseif b.level == 2 then
    for _, l in ipairs(lines) do
      local sps = shift_spans(l.spans, #indent_str)
      push(ctx, indent_str .. l.text, sps, b.src_line)
    end
    local bar = string.rep("─", math.min(util.width(bb.text) + 2, w > 0 and w or 40))
    push(ctx, indent_str .. bar, { { #indent_str, #indent_str + #bar, theme.HL.H2Bar } }, b.src_line)
  else
    for i, l in ipairs(lines) do
      local pfx = (i == 1) and (indent_str .. marker) or (indent_str .. string.rep(" ", util.width(marker)))
      local sps = shift_spans(l.spans, #pfx)
      push(ctx, pfx .. l.text, sps, b.src_line)
      if i == 1 and marker ~= "" then
        table.insert(ctx.out[#ctx.out].spans, 1, { #indent_str, #indent_str + #marker, hl })
      end
    end
  end
end

local function render_paragraph(b, ctx, indent_str)
  local bb = newb()
  render_inline(b.inline, ctx, bb, 0, false)
  local w = ctx.width - #indent_str
  local lines = wrap(bb.text, bb.spans, w > 0 and w or 0)
  for _, l in ipairs(lines) do
    local sps = shift_spans(l.spans, #indent_str)
    push(ctx, indent_str .. l.text, sps, b.src_line)
  end
end

--- 代码块：Unicode 边框 + 词法着色
local function render_code(b, ctx, indent_str)
  local lines = vim.split(b.code, "\n", { plain = true })
  -- 去掉首尾空行
  while #lines > 0 and util.is_blank(lines[1]) do table.remove(lines, 1) end
  while #lines > 0 and util.is_blank(lines[#lines]) do table.remove(lines, #lines) end

  local lang = b.lang or ""
  local show_lang = lang ~= "" and ctx.opts.code_lang_label ~= false
  local linenr = ctx.opts.code_line_numbers
  local gutter = 0
  if linenr then
    gutter = #tostring(#lines) + 1
  end

  local maxw = 0
  for _, l in ipairs(lines) do maxw = math.max(maxw, util.width(l)) end
  local avail = ctx.width - #indent_str - 4 - gutter
  local inner = math.min(maxw, avail > 8 and avail or 8)
  if inner < 8 then inner = 8 end

  -- 内容行显示宽度：│ + 空格(+行号) + inner + 空格 + │
  local content_w = inner + gutter + 4

  -- 顶部：╭─ lua ─────╮
  local label = show_lang and (lang .. " ") or ""
  local top_prefix = "╭─ " .. label
  local fill = content_w - util.width(top_prefix) - 1 -- 右侧留给 ╮
  if fill < 1 then fill = 1 end
  local top = top_prefix .. string.rep("─", fill) .. "╮"
  push(ctx, indent_str .. top, { { #indent_str, #indent_str + #top, theme.HL.CodeBorder } }, b.src_line)

  local def = codehl.lang_def(lang)
  for i, l in ipairs(lines) do
    local src = b.src_line + i -- 围栏行占 1 行
    local spans = {}
    local body = l
    if util.width(body) > inner then
      body = util.truncate(body, inner)
    end
    local pad = util.pad(body, inner)
    local prefix = "│ "
    if linenr then
      prefix = prefix .. util.pad(tostring(i), gutter - 1) .. " "
    end
    local text = prefix .. pad .. " │"

    -- 整行底色最先创建，后续 token / 边框覆盖其上
    table.insert(spans, 1, { #indent_str, #indent_str + #text, theme.HL.CodeBlock })

    -- 词法着色
    local toks = codehl.tokenize_line(l, def, {})
    local offset = #prefix
    local body_end = #prefix + #body
    for _, tk in ipairs(toks) do
      local s, e = tk[1] + offset, tk[2] + offset
      if e > body_end then e = body_end end
      if e > s then
        local hl = nil
        if tk[3] == "comment" then hl = theme.HL.Comment
        elseif tk[3] == "string" then hl = theme.HL.String
        elseif tk[3] == "number" then hl = theme.HL.Number
        elseif tk[3] == "keyword" then hl = theme.HL.Keyword
        elseif tk[3] == "func" then hl = theme.HL.Func
        elseif tk[3] == "type" then hl = theme.HL.Type
        elseif tk[3] == "operator" then hl = theme.HL.Operator
        elseif tk[3] == "punct" then hl = theme.HL.Punct
        elseif tk[3] == "constant" then hl = theme.HL.Constant
        elseif tk[3] == "variable" then hl = theme.HL.Variable end
        if hl then spans[#spans + 1] = { s, e, hl } end
      end
    end
    -- 两侧竖边框（最后创建）
    spans[#spans + 1] = { #indent_str, #indent_str + 1, theme.HL.CodeBorder }
    if linenr then
      spans[#spans + 1] = { #indent_str + 2, #indent_str + 2 + gutter, theme.HL.CodeLineNr }
    end
    spans[#spans + 1] = { #indent_str + #text - 1, #indent_str + #text, theme.HL.CodeBorder }
    push(ctx, indent_str .. text, spans, src)
  end

  local bottom = "╰" .. string.rep("─", content_w - 2) .. "╯"
  push(ctx, indent_str .. bottom, { { #indent_str, #indent_str + #bottom, theme.HL.CodeBorder } }, b.src_line)
end

local function render_blockquote(b, ctx, indent_str)
  local start = #ctx.out + 1
  -- 不额外缩进：竖条 + 一个空格已经提供了视觉层次
  M.render_blocks(b.blocks, ctx, indent_str)
  local bar = ctx.opts.quote_bar or "▎"
  for i = start, #ctx.out do
    local l = ctx.out[i]
    prefix_line(l, indent_str .. bar .. " ", nil)
    local barlen = #indent_str + #bar + 1 -- 前缀（含尾随空格）的字节长度
    -- 引用正文底色先创建（优先级最低），行内样式后创建会覆盖它
    table.insert(l.spans, 1, { barlen, #l.text, theme.HL.Quote })
    -- 竖条最后创建，避免被正文色覆盖
    l.spans[#l.spans + 1] = { 0, barlen, theme.HL.QuoteBar }
  end
end

local BULLETS = { "•", "◦", "▪" }

local function render_list(b, ctx, indent_str, depth)
  depth = depth or 0
  local bullet = BULLETS[(depth % #BULLETS) + 1]
  local idx = b.start or 1
  for _, item in ipairs(b.items) do
    local marker, mhl
    if item.checked ~= nil then
      marker = item.checked and (ctx.opts.todo_done or "[✓]") or (ctx.opts.todo_pending or "[ ]")
      mhl = item.checked and theme.HL.TodoDone or theme.HL.TodoPending
    elseif b.ordered then
      marker = tostring(idx) .. (item.marker:sub(-1) == ")" and ")" or ".")
      mhl = theme.HL.OrdMarker
    else
      marker = bullet
      mhl = theme.HL.Bullet
    end
    idx = idx + 1

    local mw = util.width(marker)
    local first_pfx = indent_str .. marker .. " "
    local rest_pfx = indent_str .. string.rep(" ", mw + 1)

    local start = #ctx.out + 1
    -- 列表项内部保持紧凑（tight list）：子块之间不插空行
    local saved = ctx.no_blank
    ctx.no_blank = true
    M.render_blocks(item.blocks, ctx, rest_pfx)
    ctx.no_blank = saved
    if #ctx.out >= start then
      -- 第一行换成带标记的前缀
      local line = ctx.out[start]
      local body = line.text:sub(#rest_pfx + 1)
      line.text = first_pfx .. body
      local delta = #first_pfx - #rest_pfx
      for _, sp in ipairs(line.spans) do
        sp[1] = sp[1] + delta
        sp[2] = sp[2] + delta
      end
      table.insert(line.spans, 1, { #indent_str, #indent_str + #marker, mhl })
    else
      push(ctx, first_pfx, { { #indent_str, #indent_str + #marker, mhl } }, item.src_line)
    end
  end
end

local function render_table(b, ctx, indent_str)
  local ncol = #b.header
  if ncol == 0 then return end

  local hdr, rows = {}, {}
  for i, cell in ipairs(b.header) do
    local t, sp = inline_to_text(cell, ctx)
    hdr[i] = { text = t, spans = sp }
  end
  for _, r in ipairs(b.rows) do
    local rr = {}
    for i = 1, ncol do
      local t, sp = inline_to_text(r[i] or {}, ctx)
      rr[i] = { text = t, spans = sp }
    end
    rows[#rows + 1] = rr
  end

  -- 列宽
  local w = {}
  for i = 1, ncol do
    w[i] = util.width(hdr[i].text) + 2
    for _, r in ipairs(rows) do
      w[i] = math.max(w[i], util.width(r[i].text) + 2)
    end
  end

  -- 超宽时按最宽列压缩
  local function total_w()
    local s = 1
    for i = 1, ncol do s = s + w[i] + 1 end
    return s
  end
  local avail = ctx.width - #indent_str
  while total_w() > avail and avail > 0 do
    local mi, mv = 1, w[1]
    for i = 2, ncol do if w[i] > mv then mi, mv = i, w[i] end end
    if mv <= 4 then break end
    w[mi] = mv - 1
  end

  local function hline(l, m, r)
    local parts = {}
    for i = 1, ncol do parts[i] = string.rep("─", w[i]) end
    return l .. table.concat(parts, m) .. r
  end

  --- 组装一行：│ cell │ cell │
  --- @return string body, table spans, table cell_ranges（各单元格在 body 中的 0-based 字节区间）
  local function row_line(cells, aligns)
    local inners, texts, spans, ranges = {}, {}, {}, {}
    for i = 1, ncol do
      local txt = cells[i].text
      if util.width(txt) > w[i] - 2 then
        txt = util.truncate(txt, w[i] - 3) .. "…"
      end
      texts[i] = txt
      local align = (aligns and aligns[i]) or "left"
      inners[i] = " " .. util.pad(txt, w[i] - 2, align) .. " "
    end
    local body = "│" .. table.concat(inners, "│") .. "│"

    local pos = 1 -- body 中第 1 个单元格的 0-based 字节起点（跳过行首 │）
    for i = 1, ncol do
      local content_start = pos + 1 -- 跳过单元格左侧的填充空格
      ranges[i] = { pos, pos + #inners[i] }
      local limit = #texts[i]
      for _, sp in ipairs(cells[i].spans) do
        local s, e = sp[1], sp[2]
        if e > limit then e = limit end
        if e > s then
          spans[#spans + 1] = { content_start + s, content_start + e, sp[3] }
        end
      end
      pos = pos + #inners[i] + 1 -- 加上单元格后的 │
    end
    return body, spans, ranges
  end

  local top = hline("┌", "┬", "┐")
  push(ctx, indent_str .. top, { { #indent_str, #indent_str + #top, theme.HL.TableBorder } }, b.src_line)

  -- 表头
  local ht, hsp, hrg = row_line(hdr, nil)
  shift_spans(hsp, #indent_str)
  -- 表头整格着色最先创建，单元格内的行内样式后创建会覆盖它
  local head_spans = {}
  for i = 1, ncol do
    head_spans[i] = { #indent_str + hrg[i][1], #indent_str + hrg[i][2], theme.HL.TableHead }
  end
  local all = {}
  for i = 1, ncol do all[#all + 1] = head_spans[i] end
  for _, sp in ipairs(hsp) do all[#all + 1] = sp end
  push(ctx, indent_str .. ht, all, b.src_line)

  local sep = hline("├", "┼", "┤")
  push(ctx, indent_str .. sep, { { #indent_str, #indent_str + #sep, theme.HL.TableBorder } }, b.src_line)

  for ri, r in ipairs(rows) do
    local t, sp = row_line(r, b.aligns)
    shift_spans(sp, #indent_str)
    push(ctx, indent_str .. t, sp, b.src_line + ri)
  end

  local bot = hline("└", "┴", "┘")
  push(ctx, indent_str .. bot, { { #indent_str, #indent_str + #bot, theme.HL.TableBorder } }, b.src_line)
end

local function render_hr(b, ctx, indent_str)
  local w = ctx.width - #indent_str
  if w < 3 then w = 3 end
  local line = string.rep("─", w)
  push(ctx, indent_str .. line, { { #indent_str, #indent_str + #line, theme.HL.Hr } }, b.src_line)
end

local function render_math(b, ctx, indent_str)
  local w = ctx.width - #indent_str
  local lines = mathr.convert_block(b.value, w > 0 and w or 0)
  for _, l in ipairs(lines) do
    push(ctx, indent_str .. l, { { #indent_str, #indent_str + #l, theme.HL.MathBlock } }, b.src_line)
  end
end

local function render_mermaid(b, ctx, indent_str)
  local res = mermaidr.render(b.code)
  if res.ok then
    for _, l in ipairs(res.lines) do
      push(ctx, indent_str .. l, { { #indent_str, #indent_str + #l, theme.HL.Mermaid } }, b.src_line)
    end
    return
  end
  -- 降级：标注块 + 源码，保证信息不丢失
  local note = res.note or "无法渲染该图表"
  local top = "╭─ mermaid: " .. note .. " "
  local w = ctx.width - #indent_str
  top = top .. string.rep("─", math.max(1, w - util.width(top) - 1)) .. "╮"
  push(ctx, indent_str .. top, { { #indent_str, #indent_str + #top, theme.HL.CodeBorder } }, b.src_line)
  for i, l in ipairs(vim.split(b.code, "\n", { plain = true })) do
    if util.trim(l) ~= "" then
      push(ctx, indent_str .. "│ " .. l, { { #indent_str, #indent_str + #l + 2, theme.HL.Mermaid } }, b.src_line + i)
    end
  end
  local bot = "╰" .. string.rep("─", math.max(1, w - 2)) .. "╯"
  push(ctx, indent_str .. bot, { { #indent_str, #indent_str + #bot, theme.HL.CodeBorder } }, b.src_line)
end

local function render_html(b, ctx, indent_str)
  for i, l in ipairs(vim.split(b.raw, "\n", { plain = true })) do
    push(ctx, indent_str .. l, { { #indent_str, #indent_str + #l, theme.HL.HtmlTag } }, b.src_line + i - 1)
  end
end

local function render_frontmatter(b, ctx, indent_str)
  push(ctx, indent_str .. "---", { { #indent_str, #indent_str + 3, theme.HL.HtmlTag } }, b.src_line)
  for i, l in ipairs(vim.split(b.value, "\n", { plain = true })) do
    push(ctx, indent_str .. l, { { #indent_str, #indent_str + #l, theme.HL.HtmlTag } }, b.src_line + i)
  end
  push(ctx, indent_str .. "---", { { #indent_str, #indent_str + 3, theme.HL.HtmlTag } }, b.src_line)
end

local function render_footnote(b, ctx, indent_str)
  local pfx = indent_str .. "[^" .. b.label .. "]: "
  local start = #ctx.out + 1
  M.render_blocks(b.blocks, ctx, indent_str)
  if #ctx.out >= start then
    prefix_line(ctx.out[start], pfx, theme.HL.Footnote)
  else
    push(ctx, pfx, { { #indent_str, #pfx, theme.HL.Footnote } }, b.src_line)
  end
end

--------------------------------------------------------------------------------
-- 入口
--------------------------------------------------------------------------------

--- 渲染块序列
function M.render_blocks(blocks, ctx, indent_str)
  indent_str = indent_str or ""
  for i, b in ipairs(blocks) do
    local t = b.t
    if t == "heading" then render_heading(b, ctx, indent_str)
    elseif t == "paragraph" then render_paragraph(b, ctx, indent_str)
    elseif t == "code" then render_code(b, ctx, indent_str)
    elseif t == "blockquote" then render_blockquote(b, ctx, indent_str)
    elseif t == "list" then render_list(b, ctx, indent_str, 0)
    elseif t == "table" then render_table(b, ctx, indent_str)
    elseif t == "hr" then render_hr(b, ctx, indent_str)
    elseif t == "math" then render_math(b, ctx, indent_str)
    elseif t == "mermaid" then render_mermaid(b, ctx, indent_str)
    elseif t == "html" then render_html(b, ctx, indent_str)
    elseif t == "frontmatter" then render_frontmatter(b, ctx, indent_str)
    elseif t == "footnote" then render_footnote(b, ctx, indent_str)
    end
    -- 块之间留一个空行（最后一个块之后不留；tight 上下文下不留）
    if i < #blocks and not ctx.no_blank then
      push(ctx, "", {}, b.src_line)
    end
  end
end

--- 渲染整篇文档
--- @param ast table parse.parse() 的结果
--- @param opts table 渲染选项
--- @return table lines 数组，每项 { text, spans, src }
function M.render(ast, opts)
  local ctx = {
    opts = opts or {},
    out = {},
    width = (opts and opts.width) or 80,
  }
  M.render_blocks(ast.blocks, ctx, "")
  -- 纯空白行（如引用块内的空行）抹平，避免留下尾随空格
  for _, l in ipairs(ctx.out) do
    if l.text:match("^%s+$") then l.text = "" end
  end
  -- 去掉尾部多余空行
  while #ctx.out > 0 and ctx.out[#ctx.out].text == "" do
    table.remove(ctx.out)
  end
  return ctx.out
end

--- 由渲染结果构建双向行号映射。
--- 块与块之间通常只有首行有精确映射，中间行用线性插值补齐，
--- 否则滚动同步在长段落/长代码块内部会出现「跳不动」。
--- @param lines table M.render 的输出
--- @return table s2o { [源行号] = 渲染行号 }（已插值补全）
--- @return table o2s { [渲染行号] = 源行号 }
function M.build_maps(lines)
  local o2s, known = {}, {}
  for i, l in ipairs(lines) do
    if l.src then
      o2s[i] = l.src
      known[#known + 1] = { src = l.src, out = i }
    end
  end
  table.sort(known, function(a, b) return a.src < b.src end)

  local s2o = {}
  for k, cur in ipairs(known) do
    s2o[cur.src] = cur.out
    local nxt = known[k + 1]
    if nxt and nxt.src > cur.src + 1 then
      for s = cur.src + 1, nxt.src - 1 do
        local ratio = (s - cur.src) / (nxt.src - cur.src)
        s2o[s] = math.floor(cur.out + ratio * (nxt.out - cur.out) + 0.5)
      end
    end
  end
  return s2o, o2s
end

return M
