-- parse.lua — Markdown 解析器
-- 输出统一的 AST，供「终端渲染」与「HTML 导出」两个后端共用，避免两套解析逻辑。
--
-- 块级节点：
--   heading / paragraph / code / blockquote / list / table / hr / math / mermaid
--   / html / footnote / frontmatter / blank
-- 行内节点：
--   text / code / strong / em / del / mark / link / image / autolink
--   / math / html / br / footnote_ref
local util = require("md-preview.util")

local M = {}

--------------------------------------------------------------------------------
-- 行内解析
--------------------------------------------------------------------------------

--- HTML 实体解码
local ENTITIES = {
  amp = "&", lt = "<", gt = ">", quot = '"', apos = "'",
  nbsp = " ", ndash = "–", mdash = "—",
  hellip = "…", lsquo = "‘", rsquo = "’",
  ldquo = "“", rdquo = "”", laquo = "«", raquo = "»",
  copy = "©", reg = "®", trade = "™", deg = "°",
  times = "×", divide = "÷", plusmn = "±",
  alpha = "α", beta = "β", gamma = "γ", delta = "δ",
  pi = "π", sigma = "σ", omega = "ω", infin = "∞",
  ne = "≠", le = "≤", ge = "≥",
}
local function decode_entities(s)
  return (s:gsub("&(#?[%w]+);", function(e)
    if e:sub(1, 1) == "#" then
      local cp
      if e:sub(2, 2) == "x" or e:sub(2, 2) == "X" then
        cp = tonumber(e:sub(3), 16)
      else
        cp = tonumber(e:sub(2))
      end
      if cp and cp > 0 and cp < 0x110000 then
        return vim and vim.fn and vim.fn.nr2char and vim.fn.nr2char(cp) or ""
      end
      return "&" .. e .. ";"
    end
    return ENTITIES[e] or ("&" .. e .. ";")
  end))
end
M.decode_entities = decode_entities

--- 寻找与 s[i]='[' 配对的 ']'，支持一级嵌套
local function find_bracket(s, i)
  local depth = 0
  local n = #s
  local k = i
  while k <= n do
    local c = s:sub(k, k)
    if c == "\\" then k = k + 2
    elseif c == "[" then depth = depth + 1; k = k + 1
    elseif c == "]" then
      depth = depth - 1
      if depth == 0 then return k end
      k = k + 1
    else k = k + 1 end
  end
  return nil
end

--- 寻找与 s[i]='(' 配对的 ')'，支持嵌套与转义
local function find_paren(s, i)
  local depth = 0
  local n = #s
  local k = i
  while k <= n do
    local c = s:sub(k, k)
    if c == "\\" then k = k + 2
    elseif c == "(" then depth = depth + 1; k = k + 1
    elseif c == ")" then
      depth = depth - 1
      if depth == 0 then return k end
      k = k + 1
    else k = k + 1 end
  end
  return nil
end

--- 寻找强调的闭合定界符
local function find_close(s, from, ch, n)
  local pat = string.rep(ch, n)
  local k = from
  local len = #s
  while k <= len do
    local p = s:find(pat, k, true)
    if not p then return nil end
    local after = s:sub(p + n, p + n)
    -- 排除更长的定界符序列（例如查找 ** 时遇到 ***）
    if after ~= ch then
      local prev = s:sub(p - 1, p - 1)
      if prev ~= " " and prev ~= "" then
        return p
      end
    end
    k = p + 1
  end
  return nil
end

--- 匹配链接 / 图片
--- @return table|nil { s, e, text, url, title, img }
local function match_link(s, i, refs)
  local start = i
  local img = false
  if s:sub(i, i) == "!" and s:sub(i + 1, i + 1) == "[" then
    img = true
    i = i + 1
  end
  if s:sub(i, i) ~= "[" then return nil end
  local close = find_bracket(s, i)
  if not close then return nil end
  local text = s:sub(i + 1, close - 1)
  local url, title
  local nxt = close + 1
  local c = s:sub(nxt, nxt)
  if c == "(" then
    local pend = find_paren(s, nxt)
    if not pend then return nil end
    local inner = s:sub(nxt + 1, pend - 1)
    local u, t = inner:match('^(%S+)%s+["\'](.*)["\']%s*$')
    if u then url, title = u, t else url = util.trim(inner) end
    nxt = pend + 1
  elseif c == "[" then
    local rend = find_bracket(s, nxt)
    if not rend then return nil end
    local ref = s:sub(nxt + 1, rend - 1)
    if ref == "" then ref = text end
    url = refs and refs[ref:lower()]
    nxt = rend + 1
  else
    if not img then
      local ref = refs and refs[text:lower()]
      if ref then url = ref end
      nxt = close + 1
    end
  end
  if not url then return nil end
  return { s = start, e = nxt - 1, text = text, url = url, title = title, img = img }
end

--- 行内解析主函数
--- @param s string 原始行内文本
--- @param refs table 链接引用定义
--- @return table 行内节点数组
function M.parse_inline(s, refs)
  local out = {}
  local i, n = 1, #s
  local buf = {}

  local function flush()
    if #buf > 0 then
      out[#out + 1] = { t = "text", value = decode_entities(table.concat(buf)) }
      buf = {}
    end
  end

  while i <= n do
    local c = s:sub(i, i)
    local nxt = s:sub(i + 1, i + 1)

    -- 反斜杠转义
    if c == "\\" and nxt ~= "" then
      if nxt:match('[\\`*_{}%[%]%(%)#%+%-%.!~<>|$/&"\']') then
        buf[#buf + 1] = nxt
        i = i + 2
        goto continue
      end
    end

    -- 行内代码：支持任意长度的反引号围栏
    if c == "`" then
      local ticks = s:match("^(`+)", i)
      local tl = #ticks
      local p = find_close(s, i + tl, "`", tl)
      if p then
        flush()
        out[#out + 1] = { t = "code", value = s:sub(i + tl, p - 1) }
        i = p + tl
        goto continue
      end
    end

    -- 行内数学 $...$ / $$...$$
    if c == "$" then
      local double = (nxt == "$")
      local delim = double and "$$" or "$"
      local dl = #delim
      local after = s:sub(i + dl, i + dl)
      if after ~= " " and after ~= "" then
        local p = s:find(delim, i + dl, true)
        if p then
          flush()
          out[#out + 1] = { t = "math", value = s:sub(i + dl, p - 1), block = false }
          i = p + dl
          goto continue
        end
      end
    end

    -- 图片 / 链接
    if c == "!" or c == "[" then
      local m = match_link(s, i, refs)
      if m then
        flush()
        if m.img then
          out[#out + 1] = {
            t = "image", url = m.url, title = m.title,
            alt = m.text, children = M.parse_inline(m.text, refs),
          }
        else
          out[#out + 1] = {
            t = "link", url = m.url, title = m.title,
            children = M.parse_inline(m.text, refs),
          }
        end
        i = m.e + 1
        goto continue
      end
    end

    -- 脚注引用 [^1]
    if c == "[" and nxt == "^" then
      local close = find_bracket(s, i)
      if close then
        flush()
        out[#out + 1] = { t = "footnote_ref", label = s:sub(i + 2, close - 1) }
        i = close + 1
        goto continue
      end
    end

    -- 自动链接 <https://...> 或 <a@b.com>
    if c == "<" then
      local inner, stop = s:match("^<([^%s>]+)>()", i)
      if inner then
        if inner:match("^[%w%.%+%-]+://") or inner:match("^[%w%.%+%-]+@[%w%.%-]+%.%w+") then
          flush()
          out[#out + 1] = { t = "autolink", url = inner }
          i = stop
          goto continue
        end
      end
      -- 行内 HTML 标签
      local tag = s:match("^</?[%a][^>]*>", i)
      if tag then
        flush()
        out[#out + 1] = { t = "html", value = tag }
        i = i + #tag
        goto continue
      end
    end

    -- 高亮 ==text==
    if c == "=" and nxt == "=" then
      local p = find_close(s, i + 2, "=", 2)
      if p then
        flush()
        local inner = s:sub(i + 2, p - 1)
        if inner ~= "" and inner:sub(1, 1) ~= " " then
          out[#out + 1] = { t = "mark", children = M.parse_inline(inner, refs) }
          i = p + 2
          goto continue
        end
      end
    end

    -- 删除线 ~~text~~
    if c == "~" and nxt == "~" then
      local p = find_close(s, i + 2, "~", 2)
      if p then
        flush()
        local inner = s:sub(i + 2, p - 1)
        if inner ~= "" and inner:sub(1, 1) ~= " " then
          out[#out + 1] = { t = "del", children = M.parse_inline(inner, refs) }
          i = p + 2
          goto continue
        end
      end
    end

    -- 强调 * / _
    if c == "*" or c == "_" then
      local cnt = 0
      local j = i
      while s:sub(j, j) == c and cnt < 3 do cnt = cnt + 1; j = j + 1 end
      local p = find_close(s, j, c, cnt)
      if p and s:sub(j, j) ~= " " then
        -- 下划线强调要求单词边界：左侧不能紧跟字母数字
        if c == "*" or (i == 1 or not s:sub(i - 1, i - 1):match("[%w]")) then
          flush()
          local inner = s:sub(j, p - 1)
          local node
          if cnt >= 2 then
            node = { t = "strong", children = M.parse_inline(inner, refs) }
            if cnt == 3 then
              node = { t = "strong", children = { { t = "em", children = M.parse_inline(inner, refs) } } }
            end
          else
            node = { t = "em", children = M.parse_inline(inner, refs) }
          end
          out[#out + 1] = node
          i = p + cnt
          goto continue
        end
      end
    end

    -- 硬换行（反斜杠结尾）
    if c == "\\" and nxt == "" then
      flush()
      out[#out + 1] = { t = "br" }
      i = i + 1
      goto continue
    end

    buf[#buf + 1] = c
    i = i + 1

    ::continue::
  end

  flush()
  return out
end

--------------------------------------------------------------------------------
-- 块级解析
--------------------------------------------------------------------------------

local function heading_line(line)
  local hashes, text = line:match("^%s*(#+)%s*(.*)$")
  if not hashes then return nil end
  local level = #hashes
  if level > 6 then return nil end
  text = text:gsub("%s+#+%s*$", "")
  return level, text
end

local function is_hr(line)
  local t = util.trim(line)
  if #t < 3 then return false end
  local ch = t:sub(1, 1)
  if ch ~= "*" and ch ~= "-" and ch ~= "_" then return false end
  for k = 1, #t do
    local c = t:sub(k, k)
    if c ~= ch and c ~= " " and c ~= "\t" then return false end
  end
  local cnt = 0
  for k = 1, #t do if t:sub(k, k) == ch then cnt = cnt + 1 end end
  return cnt >= 3
end

--- 表格分隔行 → 对齐数组
local function parse_align_row(line)
  local t = util.trim(line)
  if t:sub(1, 1) ~= "|" and not t:match("^%s*|") then
    -- GFM 也允许不带前后竖线
  end
  local cells = util.split(t, "|")
  -- 去掉首尾因 | 产生的空单元
  if #cells > 0 and util.trim(cells[1]) == "" then table.remove(cells, 1) end
  if #cells > 0 and util.trim(cells[#cells]) == "" then table.remove(cells, #cells) end
  local aligns = {}
  for _, c in ipairs(cells) do
    local v = util.trim(c)
    if v:match("^:?%-+:?$") then
      local l = v:sub(1, 1) == ":"
      local r = v:sub(-1) == ":"
      if l and r then aligns[#aligns + 1] = "center"
      elseif r then aligns[#aligns + 1] = "right"
      elseif l then aligns[#aligns + 1] = "left"
      else aligns[#aligns + 1] = "left" end
    else
      return nil
    end
  end
  if #aligns == 0 then return nil end
  return aligns
end

--- 拆分表格行（支持 \| 转义）
local function split_row(line)
  local t = util.trim(line)
  -- 保护转义的 \|
  t = t:gsub("\\|", "\001")
  local cells = util.split(t, "|")
  if #cells > 0 and util.trim(cells[1]) == "" then table.remove(cells, 1) end
  if #cells > 0 and util.trim(cells[#cells]) == "" then table.remove(cells, #cells) end
  for i, c in ipairs(cells) do
    cells[i] = util.trim(c):gsub("\001", "|")
  end
  return cells
end

--- 收集链接引用定义。
--- 同时返回行号映射 linemap：out[k] 对应原文第 linemap[k] 行，
--- 这样移除引用定义后 src_line 依然精确，滚动同步不会累积偏移。
--- @return table refs, table out, table linemap
local function extract_refs(lines)
  local refs, out, linemap = {}, {}, {}
  local i = 1
  while i <= #lines do
    local line = lines[i]
    local indent, rest = line:match("^(%s*)(.*)$")
    local label, url = rest:match("^%[([^%]]+)%]:%s*(.+)$")
    -- 排除脚注定义 [^1]: ...（交给块级解析器处理）
    if label and label:sub(1, 1) ~= "^" and #indent <= 3 and url then
      url = util.trim(url)
      -- 去掉可选的标题
      url = url:match('^(%S+)%s+["\'].*["\']$') or url
      url = url:gsub("^<(.-)>$", "%1")
      refs[label:lower()] = url
      i = i + 1
    else
      out[#out + 1] = line
      linemap[#linemap + 1] = i
      i = i + 1
    end
  end
  return refs, out, linemap
end

--- 匹配围栏代码块的起始行。
--- 注意：Lua pattern 不支持 {n,m} 量词，必须匹配 `+ 后自行判断长度 >= 3。
--- @return string|nil fence 围栏字符串
--- @return string|nil info 语言信息
local function match_fence(line)
  local fence, info = line:match("^%s*(`+)(.*)$")
  if not fence then fence, info = line:match("^%s*(~+)(.*)$") end
  if fence and #fence >= 3 then return fence, info or "" end
  return nil
end

--- 取字符串的最后一个「字符」（按 UTF-8，而非最后一个字节）
local function last_char(s)
  local c = ""
  for _cp, st, nb in util.chars(s) do c = s:sub(st, st + nb - 1) end
  return c
end

--- 取字符串去掉前导空白后的第一个「字符」
local function first_char(s)
  local t = s:match("^%s*(.*)$")
  local cp, st, nb = util.chars(t)()
  if not cp then return "" end
  return t:sub(st, st + nb - 1)
end

--- 合并段落内的多行（软换行处理）
---
--- CommonMark 规定段落内的单个换行是「软换行」，渲染时不产生硬换行，
--- 等价于一个空格。但中文等全角字符之间不该凭空多出空格，所以按两侧字符决定：
---   · 两侧都是全角（中文/全角标点）→ 直接相连，不插空格
---   · 其余（英文单词、中英混排、标点后）→ 插一个空格
---
--- 注意：这里刻意不往正文里塞 "\n"。渲染层的 "\n" 只表示硬换行（行尾双空格 / <br>），
--- 软换行若也用 "\n" 会让每个源码行各占一行，徽章等行内元素就无法合并排版。
local function join_soft(lines)
  local out = {}
  for i, l in ipairs(lines) do
    out[#out + 1] = l
    if i < #lines then
      local prev = last_char(l)
      local nxt = first_char(lines[i + 1])
      local both_fullwidth = prev ~= "" and nxt ~= ""
        and util.width(prev) == 2 and util.width(nxt) == 2
      if not both_fullwidth then out[#out + 1] = " " end
    end
  end
  return table.concat(out)
end

--- 缩进宽度（按显示宽度换算，tab = 4）
local function indent_width(s)
  local ind = s:match("^(%s*)") or ""
  local w = 0
  for k = 1, #ind do
    if ind:sub(k, k) == "\t" then w = w + 4 else w = w + 1 end
  end
  return w
end

--- 块级解析主循环
--- @param lines table 行数组
--- @param refs table 链接引用
--- @param linemap table|nil lines[k] 对应的原始行号；nil 时退化为下标
local function parse_blocks(lines, refs, linemap)
  local blocks = {}
  local i = 1
  local n = #lines

  local function src(i2)
    if linemap and linemap[i2] then return linemap[i2] end
    return i2
  end

  while i <= n do
    local line = lines[i]
    local cur_src = src(i)

    -- 空行
    if util.is_blank(line) then
      i = i + 1
      goto cont
    end

    -- 围栏代码块（也可用于 math / mermaid）
    local fence, info = match_fence(line)
    if fence then
      local lang = util.trim(info or "")
      local code_lines = {}
      local start_src = cur_src
      i = i + 1
      local fchar = fence:sub(1, 1)
      while i <= n do
        -- 闭合围栏：同种字符、长度不小于开启围栏、之后只有空白
        local close = lines[i]:match("^%s*(" .. fchar .. "+)%s*$")
        if close and #close >= #fence then
          i = i + 1
          break
        end
        code_lines[#code_lines + 1] = lines[i]
        i = i + 1
      end
      local code = table.concat(code_lines, "\n")
      local lname = lang:match("^(%S+)") or ""
      lname = lname:lower()
      if lname == "mermaid" then
        blocks[#blocks + 1] = { t = "mermaid", code = code, src_line = start_src }
      elseif lname == "math" or lname == "latex" or lname == "tex" then
        blocks[#blocks + 1] = { t = "math", value = code, src_line = start_src, block = true }
      else
        blocks[#blocks + 1] = { t = "code", lang = lname, code = code, src_line = start_src }
      end
      goto cont
    end

    -- 块级数学 $$ ... $$
    if line:match("^%s*%$%$%s*$") then
      local body = {}
      local start_src = cur_src
      i = i + 1
      while i <= n and not lines[i]:match("^%s*%$%$%s*$") do
        body[#body + 1] = lines[i]
        i = i + 1
      end
      i = i + 1 -- 跳过闭合 $$
      blocks[#blocks + 1] = {
        t = "math", value = table.concat(body, "\n"), src_line = start_src, block = true,
      }
      goto cont
    end

    -- ATX 标题
    local level, htext = heading_line(line)
    if level then
      blocks[#blocks + 1] = {
        t = "heading", level = level, src_line = cur_src,
        inline = M.parse_inline(htext, refs),
      }
      i = i + 1
      goto cont
    end

    -- 水平线
    if is_hr(line) then
      blocks[#blocks + 1] = { t = "hr", src_line = cur_src }
      i = i + 1
      goto cont
    end

    -- 引用块
    if line:match("^%s*>") then
      local inner, inner_map = {}, {}
      local start_src = cur_src
      while i <= n do
        local l = lines[i]
        if not l:match("^%s*>") then
          -- 引用内的惰性延续行（非空且属于段落）
          if #inner > 0 and not util.is_blank(l) and not l:match("^%s*[%-%*%+]%s")
              and not l:match("^%s*#") and not l:match("^%s*%d+[%.%)]%s")
              and not l:match("^%s*```") then
            inner[#inner + 1] = l
            inner_map[#inner_map + 1] = src(i)
            i = i + 1
          else
            break
          end
        else
          local stripped = l:gsub("^%s*>%s?", "")
          inner[#inner + 1] = stripped
          inner_map[#inner_map + 1] = src(i)
          i = i + 1
        end
      end
      blocks[#blocks + 1] = {
        t = "blockquote", src_line = start_src,
        blocks = parse_blocks(inner, refs, inner_map),
      }
      goto cont
    end

    -- 表格
    if line:match("|") and i + 1 <= n then
      local aligns = parse_align_row(lines[i + 1])
      if aligns then
        local header = split_row(line)
        -- 列数必须一致（允许表头少一列时补齐）
        local start_src = cur_src
        i = i + 2
        local rows = {}
        while i <= n and lines[i]:match("|") and not util.is_blank(lines[i]) do
          local cells = split_row(lines[i])
          if #cells == 0 then break end
          rows[#rows + 1] = cells
          i = i + 1
        end
        local hinl, rinl = {}, {}
        for _, c in ipairs(header) do hinl[#hinl + 1] = M.parse_inline(c, refs) end
        for _, r in ipairs(rows) do
          local row = {}
          for _, c in ipairs(r) do row[#row + 1] = M.parse_inline(c, refs) end
          rinl[#rinl + 1] = row
        end
        blocks[#blocks + 1] = {
          t = "table", header = hinl, aligns = aligns, rows = rinl, src_line = start_src,
        }
        goto cont
      end
    end

    -- 列表
    local li_indent, li_marker, li_content, li_kind = util.match_list_item(line)
    if li_indent then
      local start_src = cur_src
      local items = {}
      local ordered = (li_kind == "ordered")
      local start_num = tonumber(li_marker:match("^(%d+)")) or 1
      local marker_char = li_marker
      while i <= n do
        local ind, marker, content, kind = util.match_list_item(lines[i])
        if not ind or kind ~= li_kind or ind ~= li_indent then
          -- 缩进更深且不为空 → 交由子项递归处理（理论上不会发生）
          break
        end
        -- 任务列表
        local checked = nil
        local cbody = content
        local cb = content:match("^%[([ xX])%]%s*(.*)$")
        if cb then
          checked = (cb == "x" or cb == "X")
          cbody = content:match("^%[[ xX]%]%s*(.*)$") or ""
        end
        local item_lines, item_map = { cbody }, { src(i) }
        local j = i + 1
        local content_indent = li_indent + #marker + 1
        while j <= n do
          local l = lines[j]
          if util.is_blank(l) then
            -- 空行：若下一行仍缩进足够，则保留为段落分隔
            local nxt = lines[j + 1]
            if nxt and not util.is_blank(nxt) and indent_width(nxt) >= content_indent then
              item_lines[#item_lines + 1] = ""
              item_map[#item_map + 1] = src(j)
              j = j + 1
            else
              break
            end
          elseif indent_width(l) >= content_indent then
            item_lines[#item_lines + 1] = l:sub(content_indent + 1)
            item_map[#item_map + 1] = src(j)
            j = j + 1
          elseif indent_width(l) > li_indent then
            -- 缩进介于两者之间（如 marker 后跟多个空格）：按可用宽度剥离
            local k = li_indent + 1
            item_lines[#item_lines + 1] = l:sub(k)
            item_map[#item_map + 1] = src(j)
            j = j + 1
          else
            break
          end
        end
        items[#items + 1] = {
          blocks = parse_blocks(item_lines, refs, item_map),
          checked = checked,
          marker = marker,
          src_line = src(i),
        }
        i = j
        -- 跳过列表项之间的空行（松列表）
        while i <= n and util.is_blank(lines[i]) do
          local nxt = lines[i + 1]
          if nxt and indent_width(nxt) >= li_indent and util.match_list_item(nxt) then
            i = i + 1
            break
          end
          i = i + 1
        end
      end
      blocks[#blocks + 1] = {
        t = "list", ordered = ordered, start = start_num, marker = marker_char,
        items = items, src_line = start_src, indent = li_indent,
      }
      goto cont
    end

    -- HTML 块
    if line:match("^%s*</?[%a%!]") then
      local raw = {}
      local start_src = cur_src
      while i <= n and not util.is_blank(lines[i]) do
        raw[#raw + 1] = lines[i]
        i = i + 1
      end
      blocks[#blocks + 1] = { t = "html", raw = table.concat(raw, "\n"), src_line = start_src }
      goto cont
    end

    -- 脚注定义
    local fnlabel, fnbody = line:match("^%s*%[%^([^%]]+)%]:%s*(.*)$")
    if fnlabel then
      local body = { fnbody }
      local start_src = cur_src
      i = i + 1
      while i <= n and (util.is_blank(lines[i]) == false) and indent_width(lines[i]) >= 2 do
        body[#body + 1] = util.trim(lines[i])
        i = i + 1
      end
      local body_map = {}
      for k = 1, #body do body_map[k] = start_src + k - 1 end
      blocks[#blocks + 1] = {
        t = "footnote", label = fnlabel, src_line = start_src,
        blocks = parse_blocks(body, refs, body_map),
      }
      goto cont
    end

    -- 段落（含 Setext 标题判断）
    local para = {}
    local start_src = cur_src
    while i <= n do
      local l = lines[i]
      if util.is_blank(l) then break end
      -- 段落可被下列块打断
      if l:match("^%s*#") or is_hr(l) or l:match("^%s*>")
          or (match_fence(l) ~= nil) or l:match("^%s*%$%$%s*$")
          or l:match("^%s*%[%^[^%]]+%]:") then
        break
      end
      -- Setext 标题
      if i + 1 <= n then
        local u = lines[i + 1]
        if u:match("^%s*=+%s*$") and not util.is_blank(l) then
          para[#para + 1] = l
          blocks[#blocks + 1] = {
            t = "heading", level = 1, src_line = start_src,
            inline = M.parse_inline(join_soft(para), refs),
          }
          i = i + 2
          goto cont
        elseif u:match("^%s%-+%s*$") and not util.is_blank(l) and not util.match_list_item(l) then
          para[#para + 1] = l
          blocks[#blocks + 1] = {
            t = "heading", level = 2, src_line = start_src,
            inline = M.parse_inline(join_soft(para), refs),
          }
          i = i + 2
          goto cont
        end
      end
      -- 列表项打断段落
      if util.match_list_item(l) and #para > 0 then break end
      para[#para + 1] = l
      i = i + 1
    end
    if #para > 0 then
      blocks[#blocks + 1] = {
        t = "paragraph", src_line = start_src,
        inline = M.parse_inline(join_soft(para), refs),
      }
    end

    ::cont::
  end

  return blocks
end

--- 解析整篇文档
--- @param text string 文档全文
--- @return table { blocks = {...}, refs = {...} }
function M.parse(text)
  local lines = vim.split(text, "\n", { plain = true })
  -- YAML front matter
  local frontmatter = nil
  if #lines > 0 and lines[1]:match("^%-%-%-%s*$") then
    local body = {}
    local i = 2
    while i <= #lines and not lines[i]:match("^%-%-%-%s*$") do
      body[#body + 1] = lines[i]
      i = i + 1
    end
    if i <= #lines then
      frontmatter = table.concat(body, "\n")
      -- 删除 frontmatter 整体（第 1 行至第 i 行的 ---）
      for _ = 1, i do table.remove(lines, 1) end
    end
  end
  local refs, rest, linemap = extract_refs(lines)
  local blocks = parse_blocks(rest, refs, linemap)
  if frontmatter then
    table.insert(blocks, 1, { t = "frontmatter", value = frontmatter, src_line = 1 })
  end
  return { blocks = blocks, refs = refs }
end

return M
