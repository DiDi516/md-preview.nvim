-- util.lua — 字符串与 Unicode 工具
-- 说明：Neovim 的 extmark 列号以「字节」为单位，因此解析器全程使用字节索引；
-- 但终端对齐必须按「显示宽度」计算（CJK 占 2 列），故此处提供宽度计算。
local M = {}

--- 判断码点是否为零宽（组合字符 / 控制字符）
local function is_zero_width(cp)
  if cp == 0 then return true end
  if cp < 32 or (cp >= 0x7f and cp <= 0x9f) then return true end
  -- 组合用变音符号区间（Mn / Me 的常用段）
  if cp >= 0x0300 and cp <= 0x036f then return true end
  if cp >= 0x0483 and cp <= 0x0489 then return true end
  if cp >= 0x0591 and cp <= 0x05bd then return true end
  if cp >= 0x0610 and cp <= 0x061a then return true end
  if cp >= 0x064b and cp <= 0x065f then return true end
  if cp >= 0x1ab0 and cp <= 0x1aff then return true end
  if cp >= 0x1dc0 and cp <= 0x1dff then return true end
  if cp >= 0x20d0 and cp <= 0x20f0 then return true end
  if cp >= 0xfe00 and cp <= 0xfe0f then return true end -- 变体选择符
  if cp >= 0xfe20 and cp <= 0xfe2f then return true end
  return false
end

--- 判断码点是否为宽字符（East Asian Wide / Fullwidth / Emoji）
local function is_wide(cp)
  if cp >= 0x1100 and cp <= 0x115f then return true end -- 韩文 Jamo
  if cp >= 0x2e80 and cp <= 0x303e then return true end -- CJK 符号、中日韩标点
  if cp >= 0x3041 and cp <= 0x33ff then return true end -- 假名、CJK 兼容
  if cp >= 0x3400 and cp <= 0x4dbf then return true end -- CJK Ext A
  if cp >= 0x4e00 and cp <= 0x9fff then return true end -- CJK 基本区
  if cp >= 0xa000 and cp <= 0xa4cf then return true end -- 彝文
  if cp >= 0xac00 and cp <= 0xd7a3 then return true end -- 韩文音节
  if cp >= 0xf900 and cp <= 0xfaff then return true end -- CJK 兼容表意文字
  if cp >= 0xfe10 and cp <= 0xfe19 then return true end
  if cp >= 0xfe30 and cp <= 0xfe6f then return true end -- CJK 兼容形式
  if cp >= 0xff00 and cp <= 0xff60 then return true end -- 全角 ASCII
  if cp >= 0xffe0 and cp <= 0xffe6 then return true end
  if cp >= 0x1f300 and cp <= 0x1f64f then return true end -- 表情符号
  if cp >= 0x1f900 and cp <= 0x1f9ff then return true end
  if cp >= 0x1fa70 and cp <= 0x1faff then return true end
  if cp >= 0x20000 and cp <= 0x3fffd then return true end -- CJK Ext B+
  return false
end

--- 单个字符的显示宽度（0 / 1 / 2）
function M.char_width(cp)
  if is_zero_width(cp) then return 0 end
  if is_wide(cp) then return 2 end
  return 1
end

--- 解码 UTF-8 序列：返回 (码点, 字节长度)
local function decode_utf8(s, i)
  local b1 = string.byte(s, i)
  if not b1 then return nil, 0 end
  if b1 < 0x80 then return b1, 1 end
  local nbytes, cp
  if b1 >= 0xf0 then
    nbytes, cp = 4, b1 - 0xf0
  elseif b1 >= 0xe0 then
    nbytes, cp = 3, b1 - 0xe0
  elseif b1 >= 0xc0 then
    nbytes, cp = 2, b1 - 0xc0
  else
    return b1, 1 -- 非法起始字节，按单字节处理
  end
  for k = 1, nbytes - 1 do
    local b = string.byte(s, i + k)
    if not b or b < 0x80 or b >= 0xc0 then return b1, 1 end -- 截断或非法，退化为单字节
    cp = cp * 64 + (b - 0x80)
  end
  return cp, nbytes
end
M.decode_utf8 = decode_utf8

--- 字符串的终端显示宽度
function M.width(s)
  if s == nil then return 0 end
  local w, i, n = 0, 1, #s
  while i <= n do
    local cp, nb = decode_utf8(s, i)
    w = w + M.char_width(cp)
    i = i + nb
  end
  return w
end

--- 迭代字符：返回 码点, 字节起始位置, 字节长度
function M.chars(s)
  local i, n = 1, #s
  return function()
    if i > n then return nil end
    local cp, nb = decode_utf8(s, i)
    local start = i
    i = i + nb
    return cp, start, nb
  end
end

--- 按显示宽度截断字符串（返回字节索引对应的子串前缀）
function M.truncate(s, maxw)
  local w, i, n = 0, 1, #s
  while i <= n do
    local cp, nb = decode_utf8(s, i)
    local cw = M.char_width(cp)
    if w + cw > maxw then return s:sub(1, i - 1) end
    w = w + cw
    i = i + nb
  end
  return s
end

--- 按显示宽度填充到指定宽度
--- @param s string
--- @param w number 目标显示宽度
--- @param align string|nil "left"(默认) | "right" | "center"
function M.pad(s, w, align)
  local cur = M.width(s or "")
  if cur >= w then return s or "" end
  local diff = w - cur
  align = align or "left"
  if align == "right" then
    return string.rep(" ", diff) .. (s or "")
  elseif align == "center" then
    local l = math.floor(diff / 2)
    return string.rep(" ", l) .. (s or "") .. string.rep(" ", diff - l)
  end
  return (s or "") .. string.rep(" ", diff)
end

--- 去除首尾空白
function M.trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- 判断字符串是否全为空白
function M.is_blank(s)
  return s == nil or s:match("^%s*$") ~= nil
end

--- 字符串分割（保留空段）
function M.split(s, sep)
  local t = {}
  local pattern = string.format("([^%s]*)%s", sep, sep)
  for part in (s .. sep):gmatch(pattern) do
    t[#t + 1] = part
  end
  return t
end

--- 深拷贝（纯表结构，用于配置合并）
function M.deepcopy(orig)
  if type(orig) ~= "table" then return orig end
  local copy = {}
  for k, v in pairs(orig) do
    copy[k] = M.deepcopy(v)
  end
  return copy
end

--- 判断是否为数组式表（连续 1..n 整数键）
local function is_array(t)
  if type(t) ~= "table" then return false end
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  if n == 0 then return false end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return true
end
M.is_array = is_array

--- 递归合并：b 覆盖 a（数组整体覆盖，字典递归合并）
function M.merge(a, b)
  local out = M.deepcopy(a or {})
  for k, v in pairs(b or {}) do
    if type(v) == "table" and type(out[k]) == "table" and not is_array(v) and not is_array(out[k]) then
      out[k] = M.merge(out[k], v)
    else
      out[k] = M.deepcopy(v)
    end
  end
  return out
end

--- 转义 HTML 特殊字符
function M.escape_html(s)
  return (s:gsub("&", "&amp;")
           :gsub("<", "&lt;")
           :gsub(">", "&gt;")
           :gsub('"', "&quot;"))
end

--- 匹配 Markdown 列表项
--- @return number|nil indent 缩进空格数
--- @return string|nil marker 原始标记（如 "-" / "1."）
--- @return string|nil content 标记之后的正文
--- @return string|nil kind "bullet" | "ordered"
function M.match_list_item(line)
  local indent = line:match("^(%s*)") or ""
  local rest = line:sub(#indent + 1)
  local bullet, content = rest:match("^([%-%*%+])(%s+.*)$")
  if bullet then
    return #indent, bullet, (content:gsub("^%s+", "")), "bullet", bullet
  end
  local ordered, content2 = rest:match("^(%d+[%.%)])(%s+.*)$")
  if ordered then
    return #indent, ordered, (content2:gsub("^%s+", "")), "ordered", ordered
  end
  return nil
end

return M
