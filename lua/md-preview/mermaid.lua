-- mermaid.lua — Mermaid 图 → Unicode 字符画
-- 终端无法显示矢量图，这里把最常用的两类图近似为字符画：
--   1. flowchart / graph（TD / LR 等方向，分层布局 + 折线连边）
--   2. sequenceDiagram（参与者纵向生命线 + 消息箭头）
-- 其余图类型（classDiagram / gantt / pie / erDiagram 等）标记为不支持，
-- 由渲染层降级为「标注块 + 源码」，保证信息不丢失。
local util = require("md-preview.util")

local M = {}

--------------------------------------------------------------------------------
-- 字符画布：坐标按「显示宽度」计算，CJK 占 2 列
--------------------------------------------------------------------------------

local function canvas_new()
  return { cells = {}, maxx = 0, maxy = 0 }
end

local function cset(c, x, y, ch)
  if x < 1 or y < 1 then return end
  c.cells[y] = c.cells[y] or {}
  c.cells[y][x] = ch
  if x > c.maxx then c.maxx = x end
  if y > c.maxy then c.maxy = y end
end

--- 在指定位置写字符串（按显示宽度推进）
local function ctext(c, x, y, s)
  local cx = x
  for cp, pos, nb in util.chars(s or "") do
    cset(c, cx, y, s:sub(pos, pos + nb - 1))
    cx = cx + util.char_width(cp)
  end
  return cx - x
end

local function cget(c, x, y)
  local row = c.cells[y]
  return row and row[x] or nil
end

local function canvas_lines(c)
  local out = {}
  for y = 1, c.maxy do
    local row = c.cells[y] or {}
    local buf = {}
    local x = 1
    while x <= c.maxx do
      local ch = row[x] or " "
      -- 宽字符占位：后一格不重复输出
      buf[#buf + 1] = ch
      x = x + util.char_width(util.decode_utf8(ch, 1) or 32)
    end
    out[#out + 1] = (table.concat(buf):gsub("%s+$", ""))
  end
  return out
end

--------------------------------------------------------------------------------
-- flowchart / graph
--------------------------------------------------------------------------------

--- 节点定界符 → 边框样式
--- 注意两点：
---   1. 每个 pattern 必须带两个捕获组 (id)(text)，漏了括号会让文本退化成 id
---   2. id 用「非空白非括号」而非 [%w_]，否则中文节点名（如 需求[规格]）匹配不到
local ID = "([^%s%[%]%(%)%{%}%>%|]+)"
local NODE_SHAPES = {
  { pat = "^" .. ID .. "%[%[(.-)%]%]$", style = "subroutine" },   -- id[[text]]
  { pat = "^" .. ID .. "%[/(.-)/%]$",   style = "parallelogram" },-- id[/text/]
  -- id[\text\]：pattern 中 \ 不是转义符，源码里写 \\ 表示匹配一个字面反斜杠
  { pat = "^" .. ID .. "%[\\(.-)\\%]$", style = "parallelogram" },
  { pat = "^" .. ID .. "%[(.-)%]$",     style = "rect" },         -- id[text]
  { pat = "^" .. ID .. "%{%{(.-)%}%}$", style = "circle" },       -- id{{text}}
  { pat = "^" .. ID .. "%{(.-)%}$",     style = "diamond" },      -- id{text}
  { pat = "^" .. ID .. "%(%(.-%)%)$",   style = "circle" },       -- id((text))
  { pat = "^" .. ID .. "%((.-)%)$",     style = "round" },        -- id(text)
  { pat = "^" .. ID .. "%>(.-)%]$",     style = "asym" },         -- id>text]
  { pat = "^" .. ID .. "$",             style = "plain" },        -- id
}

--- 解析单个节点定义串，返回 {id, text, style}
local function parse_node(str)
  str = util.trim(str or "")
  if str == "" then return nil end
  for _, shape in ipairs(NODE_SHAPES) do
    local id, text = str:match(shape.pat)
    if id then
      if not text or text == "" then text = id end
      return { id = id, text = text, style = shape.style }
    end
  end
  -- 退化：整体作为纯文本节点
  return { id = str, text = str, style = "plain" }
end

--- 节点的字符框，返回 { lines = {...}, w, h }
local function node_box(node)
  local t = node.text
  local w = util.width(t)
  local lines
  local style = node.style
  if style == "rect" or style == "subroutine" then
    local tl, tr, bl, br, v, h = "┌", "┐", "└", "┘", "│", "─"
    if style == "subroutine" then tl, tr, bl, br, v, h = "╔", "╗", "╚", "╝", "║", "═" end
    lines = {
      tl .. string.rep(h, w + 2) .. tr,
      v .. " " .. t .. " " .. v,
      bl .. string.rep(h, w + 2) .. br,
    }
    return { lines = lines, w = w + 4, h = 3 }
  elseif style == "round" then
    lines = {
      "╭" .. string.rep("─", w + 2) .. "╮",
      "│ " .. t .. " │",
      "╰" .. string.rep("─", w + 2) .. "╯",
    }
    return { lines = lines, w = w + 4, h = 3 }
  elseif style == "circle" then
    lines = {
      "╭" .. string.rep("─", w + 4) .. "╮",
      "│  " .. t .. "  │",
      "╰" .. string.rep("─", w + 4) .. "╯",
    }
    return { lines = lines, w = w + 6, h = 3 }
  elseif style == "diamond" then
    lines = { "  ◇ " .. t .. " ◇  " }
    return { lines = lines, w = util.width(lines[1]), h = 1 }
  elseif style == "parallelogram" then
    lines = { " ◺ " .. t .. " ◹ " }
    return { lines = lines, w = util.width(lines[1]), h = 1 }
  elseif style == "asym" then
    lines = { " ▶ " .. t .. " ▶ " }
    return { lines = lines, w = util.width(lines[1]), h = 1 }
  end
  -- plain
  lines = { "[ " .. t .. " ]" }
  return { lines = lines, w = util.width(lines[1]), h = 1 }
end

local SEPS = { "-.->", "===>", "-->", "==>", "---", "-.-", "===", "--o", "--x", "<-->" }

--- 拆分一条边，返回 from, to, label, style
local function split_edge(line)
  -- A -->|label| B
  local a, l, b = line:match("^(.-)%s*%-%->%s*|(.-)|%s*(.+)$")
  if a and b then return util.trim(a), util.trim(b), util.trim(l), "arrow" end
  -- A -- label --> B
  a, l, b = line:match("^(.-)%s+%-%-+%s+(.-)%s+%-%->%s*(.+)$")
  if a and b then return util.trim(a), util.trim(b), util.trim(l), "arrow" end
  -- A == label ==> B
  a, l, b = line:match("^(.-)%s+=+%s+(.-)%s+=+=>%s*(.+)$")
  if a and b then return util.trim(a), util.trim(b), util.trim(l), "thick" end
  -- A -. label .-> B
  a, l, b = line:match("^(.-)%s+%-%.(.-)%.%-%>%s*(.+)$")
  if a and b then return util.trim(a), util.trim(b), util.trim(l), "dotted" end

  for _, sep in ipairs(SEPS) do
    local p = line:find(sep, 1, true)
    if p then
      local left = util.trim(line:sub(1, p - 1))
      local right = util.trim(line:sub(p + #sep))
      if left ~= "" and right ~= "" then
        local style = "arrow"
        if sep == "---" then style = "line"
        elseif sep == "-.-" or sep == "-.->" then style = "dotted"
        elseif sep:sub(1, 1) == "=" then style = "thick" end
        return left, right, nil, style
      end
    end
  end
  return nil
end

--- 边的线段字符
local function edge_chars(style)
  if style == "dotted" then return "┈", "┈", "▶" end
  if style == "thick" then return "━", "━", "▶" end
  if style == "line" then return "─", "│", "" end
  return "─", "│", "▶"
end

--- 解析 flowchart 全文
local function parse_flowchart(lines, direction)
  local nodes, order, edges = {}, {}, {}
  local function ensure(node)
    if not node then return nil end
    if not nodes[node.id] then
      nodes[node.id] = node
      order[#order + 1] = node.id
    else
      -- 后续出现时补充文本（如 A 单独定义后再写 A[文本]）
      if node.text and node.text ~= node.id then nodes[node.id].text = node.text end
    end
    return nodes[node.id]
  end
  for _, raw in ipairs(lines) do
    local line = util.trim(raw)
    if line ~= "" and not line:match("^%%") then
      local f, t, label, style = split_edge(line)
      if f and t then
        -- 支持链式写法 A --> B --> C：右侧仍含分隔符时继续拆分
        local prev, rest, lbl, sty = f, t, label, style
        local guard = 0
        while guard < 32 do
          guard = guard + 1
          local nf = ensure(parse_node(prev))
          local f2, t2, l2, s2 = split_edge(rest)
          if f2 and t2 then
            local nt = ensure(parse_node(f2))
            if nf and nt then
              edges[#edges + 1] = { from = nf.id, to = nt.id, label = lbl, style = sty }
            end
            prev, rest, lbl, sty = f2, t2, nil, s2
          else
            local nt = ensure(parse_node(rest))
            if nf and nt then
              edges[#edges + 1] = { from = nf.id, to = nt.id, label = lbl, style = sty }
            end
            break
          end
        end
      else
        -- 单独的节点定义行 / 样式声明
        if not line:match("^style") and not line:match("^classDef")
            and not line:match("^class ") and not line:match("^subgraph")
            and not line:match("^end$") and not line:match("^linkStyle") then
          ensure(parse_node(line))
        end
      end
    end
  end
  return nodes, order, edges
end

--- 分层：level[to] = max(level[from] + 1)
---
--- 要点：
---   1. 必须在「拓扑序」上松弛。若在 DFS 后序过程中就地更新，父节点的层级
---      此时还没算出来，会导致所有后代都停在 level 1。
---   2. 必须跳过「回边」（DFS 中遇到访问中的节点），否则环会让层级每轮递增、
---      无上限增长，最终把图拉成几百行。
local function compute_levels(nodes, order, edges)
  local adj = {}
  for _, id in ipairs(order) do adj[id] = {} end
  for _, e in ipairs(edges) do
    if adj[e.from] then adj[e.from][#adj[e.from] + 1] = e.to end
  end

  -- DFS 后序 + 回边标记
  local state, topo, back = {}, {}, {}
  local function dfs(u)
    state[u] = 1
    for _, v in ipairs(adj[u] or {}) do
      if state[v] == 1 then
        back[u .. "\1" .. v] = true
      elseif state[v] ~= 2 then
        dfs(v)
      end
    end
    state[u] = 2
    topo[#topo + 1] = u
  end
  for _, id in ipairs(order) do
    if not state[id] then dfs(id) end
  end

  -- 后序反转 = 拓扑序
  local n = #topo
  for i = 1, math.floor(n / 2) do
    topo[i], topo[n - i + 1] = topo[n - i + 1], topo[i]
  end

  local level = {}
  for _, id in ipairs(order) do level[id] = 0 end
  for _, u in ipairs(topo) do
    for _, v in ipairs(adj[u] or {}) do
      if not back[u .. "\1" .. v] then
        if (level[u] or 0) + 1 > (level[v] or 0) then
          level[v] = (level[u] or 0) + 1
        end
      end
    end
  end
  return level
end

--- 布局：返回 positions[id] = {x, y, w, h}
local function layout(nodes, order, edges, dir)
  local level = compute_levels(nodes, order, edges)
  local boxes = {}
  for _, id in ipairs(order) do boxes[id] = node_box(nodes[id]) end

  local layers, maxL = {}, 0
  for _, id in ipairs(order) do
    local L = level[id] or 0
    layers[L] = layers[L] or {}
    layers[L][#layers[L] + 1] = id
    if L > maxL then maxL = L end
  end

  local pos = {}
  -- LR / RL 为横向布局，其余（TD / TB / BT）为纵向布局
  local vertical = not (dir == "LR" or dir == "RL")

  if vertical then
    -- TD / TB / BT：层沿纵向
    local maxw = 0
    for _, id in ipairs(order) do maxw = math.max(maxw, boxes[id].w) end
    for L = 0, maxL do
      local ids = layers[L] or {}
      local x = 1
      for _, id in ipairs(ids) do
        pos[id] = { x = x, y = 1 + L * 6, w = boxes[id].w, h = boxes[id].h }
        x = x + boxes[id].w + 4
      end
    end
  else
    -- LR / RL：层沿横向
    local x = 1
    for L = 0, maxL do
      local ids = layers[L] or {}
      local layerw, y = 0, 1
      for _, id in ipairs(ids) do layerw = math.max(layerw, boxes[id].w) end
      for _, id in ipairs(ids) do
        pos[id] = { x = x, y = y, w = boxes[id].w, h = boxes[id].h }
        y = y + boxes[id].h + 3
      end
      x = x + layerw + 7
    end
  end
  return pos, boxes, level, vertical
end

--- 绘制 flowchart
local function draw_flowchart(lines, dir)
  local nodes, order, edges = parse_flowchart(lines, dir)
  if #order == 0 then return nil end
  local pos, boxes, level, vertical = layout(nodes, order, edges, dir)

  local c = canvas_new()
  -- 先画节点
  for _, id in ipairs(order) do
    local p, b = pos[id], boxes[id]
    for i, l in ipairs(b.lines) do ctext(c, p.x, p.y + i - 1, l) end
  end

  -- 再画边
  for _, e in ipairs(edges) do
    local pf, pt = pos[e.from], pos[e.to]
    if pf and pt then
      local hch, vch, arrow = edge_chars(e.style)
      if vertical then
        local px = math.floor(pf.x + pf.w / 2) - 1
        local pyb = pf.y + pf.h - 1
        local cx = math.floor(pt.x + pt.w / 2) - 1
        local cyt = pt.y
        local midy = pyb + 2
        if cx == px then
          for y = pyb + 1, cyt - 1 do
            cset(c, px, y, (y == cyt - 1 and arrow ~= "") and "▼" or vch)
          end
          if e.label and e.label ~= "" then
            ctext(c, px + 2, math.floor((pyb + cyt) / 2), e.label)
          end
        else
          local step = cx > px and 1 or -1
          -- 垂直段（起点向下）
          for y = pyb + 1, midy do cset(c, px, y, vch) end
          cset(c, px, midy, step > 0 and "└" or "┘")
          -- 水平段
          for x = px + step, cx - step, step do
            if x ~= px and x ~= cx then cset(c, x, midy, hch) end
          end
          cset(c, cx, midy, step > 0 and "┐" or "┌")
          -- 垂直段（到终点）
          for y = midy + 1, cyt - 1 do
            cset(c, cx, y, (y == cyt - 1 and arrow ~= "") and "▼" or vch)
          end
          if e.label and e.label ~= "" then
            local lx = math.floor((px + cx) / 2) - math.floor(util.width(e.label) / 2)
            ctext(c, math.max(1, lx), midy - 1, e.label)
          end
        end
      else
        local pxr = pf.x + pf.w
        local py = pf.y + math.floor(pf.h / 2)
        local cxl = pt.x
        local cy = pt.y + math.floor(pt.h / 2)
        local midx = math.floor((pxr + cxl) / 2)
        if py == cy then
          for x = pxr, cxl - 1 do
            cset(c, x, py, (x == cxl - 1 and arrow ~= "") and "▶" or hch)
          end
          if e.label and e.label ~= "" then
            local lx = math.floor((pxr + cxl) / 2) - math.floor(util.width(e.label) / 2)
            ctext(c, math.max(1, lx), py - 1, e.label)
          end
        else
          local step = cy > py and 1 or -1
          for x = pxr, midx do cset(c, x, py, hch) end
          cset(c, midx, py, step > 0 and "┐" or "┘")
          for y = py + step, cy - step, step do cset(c, midx, y, vch) end
          cset(c, midx, cy, step > 0 and "┌" or "└")
          for x = midx, cxl - 1 do
            cset(c, x, cy, (x == cxl - 1 and arrow ~= "") and "▶" or hch)
          end
          if e.label and e.label ~= "" then
            local ly = math.floor((py + cy) / 2)
            ctext(c, midx + 2, ly, e.label)
          end
        end
      end
    end
  end

  return canvas_lines(c)
end

--------------------------------------------------------------------------------
-- sequenceDiagram
--------------------------------------------------------------------------------

--- 时序图箭头（按长度降序尝试；Lua pattern 不支持 | 或运算，改用 plain find）
local SEQ_ARROWS = { "-->>", "->>", "-->", "--x", "->", "-x" }

local function parse_msg(line)
  for _, arrow in ipairs(SEQ_ARROWS) do
    local p = line:find(arrow, 1, true)
    if p then
      local from = util.trim(line:sub(1, p - 1))
      local rest = line:sub(p + #arrow)
      local to, text = rest:match("^%s*(%S+)%s*:%s*(.*)$")
      if from ~= "" and to then
        return from, to, util.trim(text or ""), (arrow:sub(1, 2) == "--")
      end
    end
  end
  return nil
end

local function parse_sequence(lines)
  local actors, order = {}, {}
  local messages = {}
  local function ensure(name)
    if not actors[name] then
      actors[name] = true
      order[#order + 1] = name
    end
  end
  for _, raw in ipairs(lines) do
    local line = util.trim(raw)
    if line == "" or line:match("^%%") then goto continue end
    if line:match("^participant ") then
      local nm = line:match("^participant%s+(%S+)")
      if nm then ensure(nm) end
    elseif line:match("^sequenceDiagram") or line:match("^autonumber")
        or line:match("^activate ") or line:match("^deactivate ")
        or line:match("^Note ") or line:match("^loop ")
        or line:match("^alt ") or line:match("^else") or line:match("^end")
        or line:match("^opt ") or line:match("^par ") then
      -- 暂不渲染控制结构（Note / loop / alt 等）
    else
      local a, b, text, dashed = parse_msg(line)
      if a and b then
        ensure(a)
        ensure(b)
        messages[#messages + 1] = { from = a, to = b, text = text, dashed = dashed }
      end
    end
    ::continue::
  end
  return order, messages
end

local function draw_sequence(lines)
  local order, messages = parse_sequence(lines)
  if #order == 0 then return nil end

  -- 列位置：参与者名宽度 + 间隔
  local colw, gap = {}, 6
  for i, nm in ipairs(order) do colw[i] = util.width(nm) end
  local x = {}
  local cx = 1
  for i = 1, #order do
    x[i] = cx + math.floor(colw[i] / 2)
    cx = cx + colw[i] + gap
  end
  local c = canvas_new()

  -- 参与者名
  local name_y = 1
  for i, nm in ipairs(order) do
    ctext(c, x[i] - math.floor(util.width(nm) / 2), name_y, nm)
  end
  -- 生命线起点
  local y = name_y + 1
  for i = 1, #order do cset(c, x[i], y, "│") end

  for _, m in ipairs(messages) do
    y = y + 2
    local fi, ti
    for i, nm in ipairs(order) do
      if nm == m.from then fi = i end
      if nm == m.to then ti = i end
    end
    if fi and ti then
      -- 所有生命线
      for i = 1, #order do cset(c, x[i], y, "│") end
      local x1, x2 = x[fi], x[ti]
      local hch = m.dashed and "┈" or "─"
      local lo, hi = math.min(x1, x2), math.max(x1, x2)
      for xx = lo + 1, hi - 1 do cset(c, xx, y, hch) end
      -- 箭头
      if x2 > x1 then
        cset(c, x2 - 1, y, "▶")
      elseif x2 < x1 then
        cset(c, x2 + 1, y, "◀")
      end
      -- 消息文本嵌在线上方
      if m.text ~= "" then
        local lx = math.floor((lo + hi) / 2) - math.floor(util.width(m.text) / 2)
        ctext(c, math.max(1, lx), y - 1, m.text)
      end
    end
  end
  -- 收尾生命线
  y = y + 2
  for i = 1, #order do cset(c, x[i], y, "│") end

  return canvas_lines(c)
end

--------------------------------------------------------------------------------
-- 入口
--------------------------------------------------------------------------------

--- 判断图类型
--- @return string "flowchart" | "sequence" | "unsupported"
--- @return string 方向（flowchart 用）
function M.detect(code)
  local first = code:match("^%s*(%S+)") or ""
  local fl = first:lower()
  if fl == "graph" or fl == "flowchart" then
    local dir = code:match("^%s*%S+%s+([TBLR][DRBTU]?)")
    return "flowchart", (dir or "TD"):upper()
  end
  if fl == "sequencediagram" then return "sequence", "" end
  return "unsupported", first
end

--- 渲染 Mermaid 源码
--- @param code string
--- @return table { ok = bool, kind = string, lines = table, note = string|nil }
function M.render(code)
  local kind, dir = M.detect(code)
  if kind == "flowchart" then
    local lines = {}
    for _, l in ipairs(vim.split(code, "\n", { plain = true })) do lines[#lines + 1] = l end
    -- 去掉首行的图声明
    table.remove(lines, 1)
    local out = draw_flowchart(lines, dir)
    if out and #out > 0 then
      return { ok = true, kind = "flowchart", lines = out }
    end
    return { ok = false, kind = "flowchart", lines = {}, note = "流程图为空或无法解析" }
  elseif kind == "sequence" then
    local lines = {}
    for _, l in ipairs(vim.split(code, "\n", { plain = true })) do lines[#lines + 1] = l end
    table.remove(lines, 1)
    local out = draw_sequence(lines)
    if out and #out > 0 then
      return { ok = true, kind = "sequence", lines = out }
    end
    return { ok = false, kind = "sequence", lines = {}, note = "时序图为空或无法解析" }
  end
  return {
    ok = false, kind = "unsupported", lines = {},
    note = "终端暂不支持渲染 " .. (dir ~= "" and dir or "该") .. " 类型图表，已保留源码",
  }
end

return M
