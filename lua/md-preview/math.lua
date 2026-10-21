-- math.lua — LaTeX 数学公式 → Unicode 终端文本
-- 终端无法渲染矢量公式，这里把常见的 LaTeX 结构转成 Unicode 近似：
--   希腊字母、运算符、上下标、分式、根号、矩阵，以及少量重音符号。
-- 无法识别的命令原样保留，不会破坏公式可读性。
local util = require("md-preview.util")

local M = {}

--------------------------------------------------------------------------------
-- 符号表
--------------------------------------------------------------------------------

local GREEK = {
  alpha = "α", beta = "β", gamma = "γ", delta = "δ", epsilon = "ϵ",
  varepsilon = "ε", zeta = "ζ", eta = "η", theta = "θ", vartheta = "ϑ",
  iota = "ι", kappa = "κ", lambda = "λ", mu = "μ", nu = "ν", xi = "ξ",
  omicron = "ο", pi = "π", varpi = "ϖ", rho = "ρ", varrho = "ϱ",
  sigma = "σ", varsigma = "ς", tau = "τ", upsilon = "υ", phi = "ϕ",
  varphi = "φ", chi = "χ", psi = "ψ", omega = "ω",
  Alpha = "Α", Beta = "Β", Gamma = "Γ", Delta = "Δ", Epsilon = "Ε",
  Zeta = "Ζ", Eta = "Η", Theta = "Θ", Iota = "Ι", Kappa = "Κ",
  Lambda = "Λ", Mu = "Μ", Nu = "Ν", Xi = "Ξ", Omicron = "Ο", Pi = "Π",
  Rho = "Ρ", Sigma = "Σ", Tau = "Τ", Upsilon = "Υ", Phi = "Φ",
  Chi = "Χ", Psi = "Ψ", Omega = "Ω",
}

local SYMBOLS = {
  -- 运算符
  times = "×", cdot = "·", div = "÷", pm = "±", mp = "∓", ast = "∗",
  star = "⋆", circ = "∘", bullet = "•", oplus = "⊕", ominus = "⊖",
  otimes = "⊗", odot = "⊙",
  -- 关系
  le = "≤", leq = "≤", ge = "≥", geq = "≥", neq = "≠", ne = "≠",
  approx = "≈", equiv = "≡", sim = "∼", simeq = "≃", cong = "≅",
  propto = "∝", ll = "≪", gg = "≫", doteq = "≐",
  -- 集合与逻辑
  ["in"] = "∈", notin = "∉", ni = "∋", subset = "⊂", subseteq = "⊆",
  supset = "⊃", supseteq = "⊇", cup = "∪", cap = "∩", emptyset = "∅",
  forall = "∀", exists = "∃", nexists = "∄", neg = "¬", land = "∧",
  lor = "∨", implies = "⇒", iff = "⇔", mid = "∣", parallel = "∥",
  -- 箭头
  to = "→", rightarrow = "→", longrightarrow = "⟶", Rightarrow = "⇒",
  leftarrow = "←", longleftarrow = "⟵", Leftarrow = "⇐",
  leftrightarrow = "↔", Leftrightarrow = "⇔", mapsto = "↦",
  uparrow = "↑", downarrow = "↓", nearrow = "↗", searrow = "↘",
  -- 大运算符
  sum = "∑", prod = "∏", int = "∫", iint = "∬", oint = "∮",
  bigcup = "⋃", bigcap = "⋂", coprod = "∐",
  -- 其他
  infty = "∞", partial = "∂", nabla = "∇", sqrt = "√", angle = "∠",
  triangle = "△", square = "□", perp = "⊥", degree = "°", ell = "ℓ",
  hbar = "ℏ", prime = "′", dots = "…", ldots = "…", cdots = "⋯",
  vdots = "⋮", ddots = "⋱", therefore = "∴", because = "∵",
  checkmark = "✓", star2 = "★", diamond = "◇", heartsuit = "♥",
  -- 定界符
  langle = "⟨", rangle = "⟩", lbrace = "{", rbrace = "}",
  lbrack = "[", rbrack = "]", lceil = "⌈", rceil = "⌉",
  lfloor = "⌊", rfloor = "⌋", vert = "|", Vert = "‖",
  -- 空格与排版
  quad = " ", qquad = " ", [" "] = " ", [","] = " ",
  [";"] = " ", ["!"] = " ",
}

--- 重写音符号（组合字符，拼在字符之后）
local ACCENTS = {
  hat = "̂", widehat = "̂", bar = "̄", overline = "̄",
  vec = "⃗", tilde = "̃", dot = "̇", ddot = "̈",
  check = "̌", breve = "̆", acute = "́", grave = "̀",
}

local SUP = {
  ["0"] = "⁰", ["1"] = "¹", ["2"] = "²", ["3"] = "³", ["4"] = "⁴",
  ["5"] = "⁵", ["6"] = "⁶", ["7"] = "⁷", ["8"] = "⁸", ["9"] = "⁹",
  ["+"] = "⁺", ["-"] = "⁻", ["="] = "⁼", ["("] = "⁽", [")"] = "⁾",
  n = "ⁿ", i = "ⁱ", j = "ʲ", k = "ᵏ", T = "ᵀ", t = "ᵗ",
  ["*"] = "＊",
}
local SUB = {
  ["0"] = "₀", ["1"] = "₁", ["2"] = "₂", ["3"] = "₃", ["4"] = "₄",
  ["5"] = "₅", ["6"] = "₆", ["7"] = "₇", ["8"] = "₈", ["9"] = "₉",
  ["+"] = "₊", ["-"] = "₋", ["="] = "₌", ["("] = "₍", [")"] = "₎",
  a = "ₐ", e = "ₑ", o = "ₒ", x = "ₓ", h = "ₕ", k = "ₖ", l = "ₗ",
  m = "ₘ", n = "ₙ", p = "ₚ", s = "ₛ", t = "ₜ", i = "ᵢ", j = "ⱼ",
  r = "ᵣ", u = "ᵤ", v = "ᵥ",
}

local function to_sup(s)
  local out = {}
  for _, pos, nb in util.chars(s) do
    local ch = s:sub(pos, pos + nb - 1)
    out[#out + 1] = SUP[ch] or ch
  end
  return table.concat(out)
end

local function to_sub(s)
  local out = {}
  for _, pos, nb in util.chars(s) do
    local ch = s:sub(pos, pos + nb - 1)
    out[#out + 1] = SUB[ch] or ch
  end
  return table.concat(out)
end
M.to_sup = to_sup
M.to_sub = to_sub

--------------------------------------------------------------------------------
-- 解析
--------------------------------------------------------------------------------

--- 读取 {...} 分组内容，返回 (内容, 下一个索引)
local function read_group(s, i)
  if s:sub(i, i) ~= "{" then return nil, i end
  local depth = 0
  local k = i
  local n = #s
  while k <= n do
    local c = s:sub(k, k)
    if c == "\\" then k = k + 2
    elseif c == "{" then depth = depth + 1; k = k + 1
    elseif c == "}" then
      depth = depth - 1
      if depth == 0 then return s:sub(i + 1, k - 1), k + 1 end
      k = k + 1
    else k = k + 1 end
  end
  return s:sub(i + 1), n + 1 -- 未闭合，取到末尾
end

--- 读取命令的下一个参数：{group} 或单字符
local function read_arg(s, i)
  if i > #s then return "", i end
  if s:sub(i, i) == "{" then return read_group(s, i) end
  local c = s:sub(i, i)
  if c == "\\" then
    local name = s:match("^(\\[%a]+)", i)
    if name then return name, i + #name end
    return s:sub(i, i + 1), i + 2
  end
  return c, i + 1
end

--- 矩阵 / 行列式渲染
--- @param delim table|nil 边框六元组 {首行左, 中间左, 末行左, 首行右, 中间右, 末行右}
local function render_matrix(body, delim)
  local d = delim or { "", "", "", "", "", "" }
  local rows = {}
  for _, r in ipairs(vim.split(body, "\\\\", { plain = true })) do
    local cells = {}
    -- 单元格必须 trim：\begin{...} 后的换行会混进首个单元格，导致矩阵错位换行
    for _, c in ipairs(vim.split(r, "&", { plain = true })) do
      cells[#cells + 1] = M.convert(util.trim(c))
    end
    -- 过滤全空行（尾部 \\ 会产生）
    local any = false
    for _, c in ipairs(cells) do if c ~= "" then any = true end end
    if any then rows[#rows + 1] = cells end
  end
  if #rows == 0 then return "" end
  -- 列宽对齐
  local ncol = 0
  for _, r in ipairs(rows) do ncol = math.max(ncol, #r) end
  local w = {}
  for ci = 1, ncol do
    w[ci] = 0
    for _, r in ipairs(rows) do
      w[ci] = math.max(w[ci], util.width(r[ci] or ""))
    end
  end
  local out = {}
  for ri, r in ipairs(rows) do
    local cells = {}
    for ci = 1, ncol do cells[ci] = util.pad(r[ci] or "", w[ci]) end
    local line = " " .. table.concat(cells, "  ") .. " "
    local li, ri2 = 1, 4
    if ri > 1 then li = 2 end
    if ri == #rows then li = 3 end
    if ri > 1 then ri2 = 5 end
    if ri == #rows then ri2 = 6 end
    if #rows == 1 then li, ri2 = 1, 4 end
    out[#out + 1] = (d[li] or "") .. line .. (d[ri2] or "")
  end
  return table.concat(out, "\n")
end

--- 各环境的边框：{首行左, 中间左, 末行左, 首行右, 中间右, 末行右}
local MATRIX_DELIM = {
  pmatrix = { "⎛", "⎜", "⎝", "⎞", "⎟", "⎠" },
  bmatrix = { "⎡", "⎢", "⎣", "⎤", "⎥", "⎦" },
  Bmatrix = { "⎧", "⎨", "⎩", "⎫", "⎬", "⎭" },
  vmatrix = { "⎢", "⎢", "⎢", "⎥", "⎥", "⎥" },
  Vmatrix = { "⎢", "⎢", "⎢", "⎥", "⎥", "⎥" },
  cases =   { "⎧", "⎨", "⎩", " ", " ", " " },
  array =   { "⎡", "⎢", "⎣", "⎤", "⎥", "⎦" },
  -- matrix / aligned / align / split / gathered / equation 等：无边框
}

--- 主转换函数
--- @param expr string LaTeX 源码
--- @return string Unicode 文本
function M.convert(expr)
  if not expr or expr == "" then return "" end
  local out = {}
  local i, n = 1, #expr

  while i <= n do
    local c = expr:sub(i, i)

    if c == "\\" then
      local name = expr:match("^\\([%a]+)", i)
      local after
      if name then
        after = i + 1 + #name
      else
        local sym = expr:match("^\\(%W)", i)
        if sym then
          name = sym
          after = i + 2
        else
          out[#out + 1] = c
          i = i + 1
          goto continue
        end
      end

      -- \begin{env} ... \end{env}
      if name == "begin" then
        local env, ai = read_group(expr, after)
        local endpos = expr:find("\\end{" .. (env or "") .. "}", ai, true)
        if env and endpos then
          local body = expr:sub(ai, endpos - 1)
          out[#out + 1] = render_matrix(body, MATRIX_DELIM[env])
          i = expr:find("}", endpos, true) + 1
          goto continue
        end
      end

      if name == "end" then
        local _, ai = read_group(expr, after)
        i = ai
        goto continue
      end

      -- 分式
      if name == "frac" or name == "dfrac" or name == "tfrac" or name == "cfrac" then
        local num, ai = read_arg(expr, after)
        local den, ai2 = read_arg(expr, ai)
        out[#out + 1] = M.convert(num) .. "⁄" .. M.convert(den)
        i = ai2
        goto continue
      end

      -- 根号（支持 \sqrt[n]{x}）
      if name == "sqrt" then
        local idx, ai = nil, after
        if expr:sub(ai, ai) == "[" then
          local p = expr:find("]", ai, true)
          if p then
            idx = expr:sub(ai + 1, p - 1)
            ai = p + 1
          end
        end
        local body, ai2 = read_arg(expr, ai)
        if idx then
          out[#out + 1] = to_sup(M.convert(idx)) .. "√(" .. M.convert(body) .. ")"
        else
          out[#out + 1] = "√(" .. M.convert(body) .. ")"
        end
        i = ai2
        goto continue
      end

      -- \text / \mathrm / \mathbf 等：取原文
      if name == "text" or name == "textrm" or name == "mathrm" or name == "mathbf"
          or name == "mbox" or name == "textbf" or name == "textit"
          or name == "operatorname" or name == "mathsf" or name == "mathtt" then
        local body, ai = read_arg(expr, after)
        out[#out + 1] = body
        i = ai
        goto continue
      end

      -- 重音
      if ACCENTS[name] then
        local body, ai = read_arg(expr, after)
        out[#out + 1] = M.convert(body) .. ACCENTS[name]
        i = ai
        goto continue
      end

      -- \left \right \big 等定界符修饰
      if name == "left" or name == "right" or name == "big" or name == "Big"
          or name == "bigg" or name == "Bigg" or name == "middle" then
        -- 跳过空白后取一个定界符字符（可能是 \langle 这类命令）
        local ws = expr:match("^%s*", after) or ""
        local p = after + #ws
        if expr:sub(p, p) == "\\" then
          -- 形如 \langle / \rbrace / \Vert 的定界符命令
          local cmd = expr:match("^([%a]+)", p + 1)
          if cmd then
            out[#out + 1] = SYMBOLS[cmd] or GREEK[cmd] or ("\\" .. cmd)
            i = p + 1 + #cmd
            goto continue
          end
        end
        local d = expr:sub(p, p)
        if d ~= "" then
          out[#out + 1] = d
          i = p + 1
        else
          i = after
        end
        goto continue
      end

      -- 希腊字母
      if GREEK[name] then
        out[#out + 1] = GREEK[name]
        i = after
        goto continue
      end

      -- 符号表
      if SYMBOLS[name] then
        out[#out + 1] = SYMBOLS[name]
        i = after
        goto continue
      end

      -- 未知命令：保留原文
      out[#out + 1] = "\\" .. name
      i = after
      goto continue
    end

    -- 分组
    if c == "{" then
      local body, ni = read_group(expr, i)
      out[#out + 1] = M.convert(body)
      i = ni
      goto continue
    end
    if c == "}" then
      i = i + 1
      goto continue
    end

    -- 上标 / 下标
    if c == "^" then
      local arg, ni = read_arg(expr, i + 1)
      out[#out + 1] = to_sup(M.convert(arg))
      i = ni
      goto continue
    end
    if c == "_" then
      local arg, ni = read_arg(expr, i + 1)
      out[#out + 1] = to_sub(M.convert(arg))
      i = ni
      goto continue
    end

    -- 矩阵换行 / 列分隔
    if expr:sub(i, i + 1) == "\\\\" then
      out[#out + 1] = "\n"
      i = i + 2
      goto continue
    end
    if c == "&" then
      out[#out + 1] = "  "
      i = i + 1
      goto continue
    end

    -- 常见 ASCII 替换
    if c == "~" then out[#out + 1] = " "; i = i + 1; goto continue end
    if c == "%" then i = i + 1; goto continue end -- LaTeX 注释

    out[#out + 1] = c
    i = i + 1

    ::continue::
  end

  return table.concat(out)
end

--- 块级公式：转换后按行居中
--- 注意：若公式含 \begin{...}，必须整体转换——
--- 逐行转换会让跨行的 \begin / \end 各自找不到配对，矩阵会退化成原文。
function M.convert_block(value, width)
  local u = require("md-preview.util")
  if value:find("\\begin{", 1, true) then
    -- 环境块整体转换后作为一个整体居中：逐行居中会破坏矩阵内部的列对齐
    local parts = vim.split(M.convert(value), "\n", { plain = true })
    local maxw = 0
    for _, l in ipairs(parts) do maxw = math.max(maxw, u.width(l)) end
    local pad = 0
    if width and width > maxw then pad = math.floor((width - maxw) / 2) end
    local out = {}
    for _, l in ipairs(parts) do
      out[#out + 1] = string.rep(" ", pad) .. l
    end
    return out
  end

  local out = {}
  for _, l in ipairs(vim.split(value, "\n", { plain = true })) do
    local t = l:match("%S") and M.convert(l) or ""
    if width and width > 0 and t:match("%S") then
      local pad = math.floor((width - u.width(t)) / 2)
      if pad > 0 then t = string.rep(" ", pad) .. t end
    end
    out[#out + 1] = t
  end
  return out
end

return M
