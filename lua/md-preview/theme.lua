-- theme.lua — 高亮组定义与配色
-- 配色默认跟随 catppuccin 当前 flavour；取不到时使用内置 macchiato 色板。
-- 终端不支持真彩时，使用 xterm-256 近似色作为 ctermfg / ctermbg 降级。
local M = {}

--- 内置 macchiato 色板（catppuccin 不可用时兜底）
local BUILTIN = {
  rosewater = "#f4dbd6",
  flamingo  = "#f0c6c7",
  pink      = "#f5bde6",
  mauve     = "#c6a0f6",
  red       = "#ed8796",
  maroon    = "#ee99a0",
  peach     = "#f5a97f",
  yellow    = "#eed49f",
  green     = "#a6da95",
  teal      = "#8bd5ca",
  sky       = "#91d7e3",
  sapphire  = "#7dc4e4",
  blue      = "#8aadf4",
  lavender  = "#b7bdf8",
  text      = "#cad3f5",
  subtext1  = "#b8c0e0",
  subtext0  = "#a5adcb",
  overlay2  = "#939ab7",
  overlay1  = "#8087a2",
  overlay0  = "#6e738d",
  surface2  = "#5b6078",
  surface1  = "#494d64",
  surface0  = "#363a4f",
  base      = "#24273a",
  mantle    = "#1e2030",
  crust     = "#181926",
}

--- xterm-256 近似色索引
local CTERM = {
  rosewater = 224, flamingo = 218, pink = 219, mauve = 141,
  red = 210, maroon = 211, peach = 216, yellow = 222,
  green = 150, teal = 116, sky = 152, sapphire = 117,
  blue = 111, lavender = 147, text = 252, subtext1 = 250,
  subtext0 = 249, overlay2 = 248, overlay1 = 245, overlay0 = 243,
  surface2 = 241, surface1 = 239, surface0 = 237, base = 235,
  mantle = 234, crust = 233,
}

--- 取当前 catppuccin 调色板；失败返回 nil
local function catppuccin_palette()
  local ok, palettes = pcall(require, "catppuccin.palettes")
  if not ok then return nil end
  local flavour = "macchiato"
  local ok2, api = pcall(require, "catppuccin")
  if ok2 and api and api.flavour then flavour = api.flavour end
  -- 也尊重用户通过 vim.g 指定的 flavour
  if vim.g and vim.g.catppuccin_flavour then flavour = vim.g.catppuccin_flavour end
  local ok3, p = pcall(palettes.get_palette, flavour)
  if ok3 and type(p) == "table" and p.text then return p end
  return nil
end

--- 当前生效色板
function M.palette()
  return catppuccin_palette() or BUILTIN
end
M.BUILTIN = BUILTIN
M.CTERM = CTERM

--- 把色名转成 cterm 索引（未知色名返回 nil）
local function cterm_of(name)
  return CTERM[name]
end

-- 高亮组名常量，供渲染器引用
M.HL = {
  H1 = "MdPreviewH1", H2 = "MdPreviewH2", H3 = "MdPreviewH3",
  H4 = "MdPreviewH4", H5 = "MdPreviewH5", H6 = "MdPreviewH6",
  H1Bar = "MdPreviewH1Bar", H2Bar = "MdPreviewH2Bar",
  Bold = "MdPreviewBold", Italic = "MdPreviewItalic", Strike = "MdPreviewStrike",
  LinkB = "MdPreviewLinkB", LinkI = "MdPreviewLinkI", LinkBI = "MdPreviewLinkBI",
  -- 强调的组合态：终端里同一区间只能生效一个高亮组，
  -- 因此 粗/斜/删除线 的 7 种组合各定义一组，避免嵌套时互相覆盖。
  EmphB = "MdPreviewEmphB", EmphI = "MdPreviewEmphI", EmphBI = "MdPreviewEmphBI",
  EmphS = "MdPreviewEmphS", EmphBS = "MdPreviewEmphBS", EmphIS = "MdPreviewEmphIS",
  EmphBIS = "MdPreviewEmphBIS",
  Mark = "MdPreviewMark",
  InlineCode = "MdPreviewInlineCode",
  CodeBlock = "MdPreviewCodeBlock", CodeBorder = "MdPreviewCodeBorder",
  CodeLang = "MdPreviewCodeLang", CodeLineNr = "MdPreviewCodeLineNr",
  Quote = "MdPreviewQuote", QuoteBar = "MdPreviewQuoteBar",
  Bullet = "MdPreviewBullet", OrdMarker = "MdPreviewOrdMarker",
  TodoDone = "MdPreviewTodoDone", TodoPending = "MdPreviewTodoPending",
  TableBorder = "MdPreviewTableBorder", TableHead = "MdPreviewTableHead",
  TableCell = "MdPreviewTableCell",
  Hr = "MdPreviewHr",
  Link = "MdPreviewLink", LinkUrl = "MdPreviewLinkUrl",
  Image = "MdPreviewImage",
  Math = "MdPreviewMath", MathBlock = "MdPreviewMathBlock",
  Mermaid = "MdPreviewMermaid",
  Footnote = "MdPreviewFootnote", HtmlTag = "MdPreviewHtmlTag",
  -- 代码词法
  Keyword = "MdPreviewKeyword", Comment = "MdPreviewComment",
  String = "MdPreviewString", Number = "MdPreviewNumber",
  Func = "MdPreviewFunc", Operator = "MdPreviewOperator",
  Type = "MdPreviewType", Punct = "MdPreviewPunct",
  Constant = "MdPreviewConstant", Variable = "MdPreviewVariable",
}

--- 生成高亮定义表
--- @param opts table 配置项（attrs 控制 bold/italic/underline/strikethrough 是否启用）
function M.definitions(opts)
  local p = M.palette()
  local A = opts.attrs or {}
  local bold = A.bold ~= false
  local italic = A.italic ~= false
  local underline = A.underline ~= false
  local strike = A.strikethrough ~= false

  local function fg(name, extra)
    local d = { fg = p[name] or BUILTIN[name], ctermfg = cterm_of(name) }
    if extra then for k, v in pairs(extra) do d[k] = v end end
    return d
  end

  return {
    -- 标题：H1/H2 带装饰线，H3+ 逐级弱化
    [M.HL.H1] = fg("mauve", { bold = bold }),
    [M.HL.H2] = fg("blue", { bold = bold }),
    [M.HL.H3] = fg("teal", { bold = bold }),
    [M.HL.H4] = fg("sapphire", { bold = bold }),
    [M.HL.H5] = fg("lavender", { bold = bold }),
    [M.HL.H6] = fg("subtext1", { bold = bold }),
    [M.HL.H1Bar] = fg("mauve"),
    [M.HL.H2Bar] = fg("blue"),

    -- 行内强调：单一属性 + 组合态
    [M.HL.Bold] = { bold = bold, fg = p.text, ctermfg = cterm_of("text") },
    [M.HL.Italic] = { italic = italic, fg = p.text, ctermfg = cterm_of("text") },
    [M.HL.Strike] = { strikethrough = strike, fg = p.overlay1, ctermfg = cterm_of("overlay1") },
    [M.HL.EmphB] = { bold = bold, fg = p.text, ctermfg = cterm_of("text") },
    [M.HL.EmphI] = { italic = italic, fg = p.text, ctermfg = cterm_of("text") },
    [M.HL.EmphBI] = { bold = bold, italic = italic, fg = p.text, ctermfg = cterm_of("text") },
    [M.HL.EmphS] = { strikethrough = strike, fg = p.overlay1, ctermfg = cterm_of("overlay1") },
    [M.HL.EmphBS] = { bold = bold, strikethrough = strike, fg = p.overlay1, ctermfg = cterm_of("overlay1") },
    [M.HL.EmphIS] = { italic = italic, strikethrough = strike, fg = p.overlay1, ctermfg = cterm_of("overlay1") },
    [M.HL.EmphBIS] = {
      bold = bold, italic = italic, strikethrough = strike,
      fg = p.overlay1, ctermfg = cterm_of("overlay1"),
    },
    [M.HL.Mark] = { fg = p.base, bg = p.yellow, ctermfg = cterm_of("base"), ctermbg = cterm_of("yellow") },
    [M.HL.InlineCode] = {
      fg = p.peach, ctermfg = cterm_of("peach"),
      bg = p.surface0, ctermbg = cterm_of("surface0"),
    },

    -- 代码块
    [M.HL.CodeBlock] = { bg = p.surface0, ctermbg = cterm_of("surface0"), fg = p.text, ctermfg = cterm_of("text") },
    [M.HL.CodeBorder] = fg("surface2"),
    [M.HL.CodeLang] = fg("overlay1", { italic = italic }),
    [M.HL.CodeLineNr] = fg("overlay0"),

    -- 引用
    [M.HL.Quote] = fg("overlay2", { italic = italic }),
    [M.HL.QuoteBar] = fg("surface2"),

    -- 列表
    [M.HL.Bullet] = fg("mauve"),
    [M.HL.OrdMarker] = fg("peach"),
    [M.HL.TodoDone] = fg("green", { bold = bold }),
    [M.HL.TodoPending] = fg("overlay1"),

    -- 表格
    [M.HL.TableBorder] = fg("overlay0"),
    [M.HL.TableHead] = fg("lavender", { bold = bold }),
    [M.HL.TableCell] = fg("text"),

    [M.HL.Hr] = fg("surface2"),

    -- 链接（以及链接内叠加强调的组合组）
    [M.HL.Link] = fg("blue", { underline = underline }),
    [M.HL.LinkB] = fg("blue", { underline = underline, bold = bold }),
    [M.HL.LinkI] = fg("blue", { underline = underline, italic = italic }),
    [M.HL.LinkBI] = fg("blue", { underline = underline, bold = bold, italic = italic }),
    [M.HL.LinkUrl] = fg("overlay1", { italic = italic }),
    [M.HL.Image] = fg("pink"),

    -- 数学与图表
    [M.HL.Math] = fg("pink"),
    [M.HL.MathBlock] = fg("flamingo"),
    [M.HL.Mermaid] = fg("teal"),

    [M.HL.Footnote] = fg("yellow"),
    [M.HL.HtmlTag] = fg("overlay1"),

    -- 代码词法着色。
    -- 这些组统一带上代码块背景色：Neovim 中重叠的 extmark 高亮会整体覆盖，
    -- 若 token 不声明 bg，代码块底色会被 token 区间「吃掉」形成断裂。
    [M.HL.Keyword] = fg("mauve", { bg = p.surface0, ctermbg = cterm_of("surface0") }),
    [M.HL.Comment] = fg("overlay1", { italic = italic, bg = p.surface0, ctermbg = cterm_of("surface0") }),
    [M.HL.String] = fg("green", { bg = p.surface0, ctermbg = cterm_of("surface0") }),
    [M.HL.Number] = fg("peach", { bg = p.surface0, ctermbg = cterm_of("surface0") }),
    [M.HL.Func] = fg("blue", { bg = p.surface0, ctermbg = cterm_of("surface0") }),
    [M.HL.Operator] = fg("sky", { bg = p.surface0, ctermbg = cterm_of("surface0") }),
    [M.HL.Type] = fg("yellow", { bg = p.surface0, ctermbg = cterm_of("surface0") }),
    [M.HL.Punct] = fg("overlay2", { bg = p.surface0, ctermbg = cterm_of("surface0") }),
    [M.HL.Constant] = fg("peach", { bg = p.surface0, ctermbg = cterm_of("surface0") }),
    [M.HL.Variable] = fg("text", { bg = p.surface0, ctermbg = cterm_of("surface0") }),
  }
end

--- 应用高亮组
function M.setup(opts)
  local defs = M.definitions(opts)
  local custom = opts.highlights or {}
  for name, attr in pairs(defs) do
    local merged = attr
    if custom[name] then
      merged = vim.tbl_extend("force", attr, custom[name])
    end
    -- 已存在的用户定义优先（如用户在 colorscheme 之后手动改过）
    local ok = pcall(vim.api.nvim_set_hl, 0, name, merged)
    if not ok then
      -- 极旧版本不支持 strikethrough 等属性时，降级去掉该属性重试
      merged = vim.tbl_extend("force", {}, merged)
      merged.strikethrough = nil
      pcall(vim.api.nvim_set_hl, 0, name, merged)
    end
  end
  -- ColorScheme 变更时重新应用，保证切主题后颜色跟随
  if not M._autocmd_done then
    M._autocmd_done = true
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup("MdPreviewTheme", { clear = true }),
      callback = function() M.setup(opts) end,
    })
  end
end

return M
