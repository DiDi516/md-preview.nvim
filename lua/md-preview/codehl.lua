-- codehl.lua — 代码块词法着色
-- 通用扫描器 + 各语言关键字表。输出「类型化 token」（comment/string/keyword/...），
-- 终端后端映射为高亮组，HTML 后端映射为 CSS class，两个后端共用同一份词法结果。
local M = {}

local function set_of(list)
  local s = {}
  for _, v in ipairs(list) do s[v] = true end
  return s
end

--- 语言定义：
---   kw      关键字
---   cnst    常量字面量
---   ty      类型名
---   lc      行注释 pattern 列表
---   bc      块注释 {起始 pattern, 结束 pattern} 列表
---   str     字符串定界符（plain 字符串，按顺序尝试）
---   esc     字符串内转义符（默认 "\\"）
local LANGS = {}

LANGS.lua = {
  kw = set_of {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function",
    "goto", "if", "in", "local", "nil", "not", "or", "repeat", "return",
    "then", "true", "until", "while",
  },
  cnst = set_of { "true", "false", "nil" },
  ty = set_of { "self" },
  lc = { "%-%-" },
  bc = { { "%-%-%[%[", "%]%]" } },
  str = { '"', "'", "[[" },
  str_end = { ["[["] = "]]" },
}

LANGS.python = {
  kw = set_of {
    "and", "as", "assert", "async", "await", "break", "class", "continue",
    "def", "del", "elif", "else", "except", "finally", "for", "from",
    "global", "if", "import", "in", "is", "lambda", "nonlocal", "not",
    "or", "pass", "raise", "return", "try", "while", "with", "yield", "match", "case",
  },
  cnst = set_of { "True", "False", "None", "self", "cls" },
  ty = set_of { "int", "str", "float", "bool", "list", "dict", "set", "tuple", "bytes" },
  lc = { "#" },
  bc = {},
  str = { '"""', "'''", '"', "'" },
}

LANGS.javascript = {
  kw = set_of {
    "async", "await", "break", "case", "catch", "class", "const", "continue",
    "debugger", "default", "delete", "do", "else", "export", "extends",
    "finally", "for", "from", "function", "get", "if", "implements", "import",
    "in", "instanceof", "interface", "let", "new", "of", "package", "private",
    "protected", "public", "return", "set", "static", "super", "switch",
    "this", "throw", "try", "typeof", "var", "void", "while", "with", "yield",
  },
  cnst = set_of { "true", "false", "null", "undefined", "NaN", "Infinity" },
  ty = set_of { "string", "number", "boolean", "object", "symbol", "bigint", "any", "Promise" },
  lc = { "//" },
  bc = { { "/%*", "%*/" } },
  str = { '"', "'", "`" },
}

LANGS.typescript = {
  base = "javascript",
  kw = set_of {
    "abstract", "as", "async", "await", "break", "case", "catch", "class",
    "const", "continue", "declare", "default", "delete", "do", "else", "enum",
    "export", "extends", "finally", "for", "from", "function", "get", "if",
    "implements", "import", "in", "instanceof", "interface", "is", "keyof",
    "let", "namespace", "new", "of", "private", "protected", "public",
    "readonly", "return", "satisfies", "set", "static", "super", "switch",
    "this", "throw", "try", "type", "typeof", "var", "void", "while", "yield",
  },
  cnst = set_of { "true", "false", "null", "undefined", "never", "unknown", "any" },
  ty = set_of {
    "string", "number", "boolean", "object", "symbol", "bigint", "void",
    "Promise", "Array", "Record", "Partial", "Readonly", "Map", "Set",
  },
}

LANGS.json = {
  kw = set_of {},
  cnst = set_of { "true", "false", "null" },
  ty = set_of {},
  lc = {},
  bc = {},
  str = { '"' },
  number_key = true,
}

LANGS.bash = {
  alias = { "sh", "zsh", "shell", "console", "fish", "powershell", "ps1", "bat", "cmd" },
  kw = set_of {
    "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done",
    "case", "esac", "function", "in", "select", "return", "local", "export",
    "source", "alias", "set", "unset", "trap", "exit", "shift", "eval", "exec",
  },
  cnst = set_of { "true", "false" },
  ty = set_of {},
  lc = { "#" },
  bc = {},
  str = { '"', "'" },
}

LANGS.c = {
  kw = set_of {
    "auto", "break", "case", "char", "const", "continue", "default", "do",
    "double", "else", "enum", "extern", "float", "for", "goto", "if", "inline",
    "int", "long", "register", "restrict", "return", "short", "signed",
    "sizeof", "static", "struct", "switch", "typedef", "union", "unsigned",
    "void", "volatile", "while", "_Bool", "include", "define", "ifdef",
    "ifndef", "endif", "pragma",
  },
  cnst = set_of { "NULL", "true", "false" },
  ty = set_of { "int", "char", "float", "double", "void", "long", "short", "unsigned", "signed", "size_t", "bool" },
  lc = { "//" },
  bc = { { "/%*", "%*/" } },
  str = { '"', "'" },
}

LANGS.cpp = {
  base = "c",
  kw = set_of {
    "alignas", "alignof", "auto", "bool", "break", "case", "catch", "char",
    "class", "const", "constexpr", "const_cast", "continue", "decltype",
    "default", "delete", "do", "double", "dynamic_cast", "else", "enum",
    "explicit", "export", "extern", "false", "float", "for", "friend",
    "goto", "if", "inline", "int", "long", "mutable", "namespace", "new",
    "noexcept", "nullptr", "operator", "private", "protected", "public",
    "register", "reinterpret_cast", "return", "short", "signed", "sizeof",
    "static", "static_assert", "static_cast", "struct", "switch", "template",
    "this", "throw", "true", "try", "typedef", "typeid", "typename", "union",
    "unsigned", "using", "virtual", "void", "volatile", "while",
  },
  cnst = set_of { "nullptr", "true", "false", "NULL" },
  ty = set_of { "std", "string", "vector", "map", "unordered_map", "set", "shared_ptr", "unique_ptr", "size_t", "auto" },
}

LANGS.java = {
  kw = set_of {
    "abstract", "assert", "boolean", "break", "byte", "case", "catch", "char",
    "class", "const", "continue", "default", "do", "double", "else", "enum",
    "extends", "final", "finally", "float", "for", "goto", "if", "implements",
    "import", "instanceof", "int", "interface", "long", "native", "new",
    "package", "private", "protected", "public", "return", "short", "static",
    "strictfp", "super", "switch", "synchronized", "this", "throw", "throws",
    "transient", "try", "void", "volatile", "while", "record", "sealed", "var", "yield",
  },
  cnst = set_of { "true", "false", "null" },
  ty = set_of { "String", "Integer", "Long", "Double", "Boolean", "List", "Map", "Set", "Optional", "Object" },
  lc = { "//" },
  bc = { { "/%*", "%*/" } },
  str = { '"', "'" },
}

LANGS.go = {
  kw = set_of {
    "break", "case", "chan", "const", "continue", "default", "defer", "else",
    "fallthrough", "for", "func", "go", "goto", "if", "import", "interface",
    "map", "package", "range", "return", "select", "struct", "switch", "type", "var",
  },
  cnst = set_of { "true", "false", "nil", "iota" },
  ty = set_of { "string", "int", "int8", "int16", "int32", "int64", "uint", "float32", "float64", "bool", "byte", "rune", "error", "any" },
  lc = { "//" },
  bc = { { "/%*", "%*/" } },
  str = { '"', "'", "`" },
}

LANGS.rust = {
  kw = set_of {
    "as", "async", "await", "break", "const", "continue", "crate", "dyn",
    "else", "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let",
    "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self",
    "Self", "static", "struct", "super", "trait", "true", "type", "unsafe",
    "use", "where", "while",
  },
  cnst = set_of { "true", "false", "None", "Some", "Ok", "Err" },
  ty = set_of { "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "usize", "isize", "f32", "f64", "bool", "char", "str", "String", "Vec", "Option", "Result" },
  lc = { "//" },
  bc = { { "/%*", "%*/" } },
  str = { '"', "'" },
}

LANGS.ruby = {
  kw = set_of {
    "begin", "break", "case", "class", "def", "do", "else", "elsif", "end",
    "ensure", "for", "if", "in", "module", "next", "nil", "redo", "rescue",
    "retry", "return", "self", "super", "then", "true", "false", "unless",
    "until", "when", "while", "yield", "lambda", "proc",
  },
  cnst = set_of { "true", "false", "nil" },
  ty = set_of {},
  lc = { "#" },
  bc = { { "=begin", "=end" } },
  str = { '"', "'" },
}

LANGS.php = {
  kw = set_of {
    "abstract", "and", "array", "as", "break", "callable", "case", "catch",
    "class", "clone", "const", "continue", "declare", "default", "do", "echo",
    "else", "elseif", "empty", "enddeclare", "endfor", "endforeach", "endif",
    "endswitch", "endwhile", "extends", "final", "finally", "for", "foreach",
    "function", "global", "if", "implements", "include", "include_once",
    "instanceof", "insteadof", "interface", "isset", "list", "namespace",
    "new", "or", "print", "private", "protected", "public", "require",
    "require_once", "return", "static", "switch", "throw", "trait", "try",
    "unset", "use", "var", "while", "xor", "yield", "match", "fn",
  },
  cnst = set_of { "true", "false", "null", "TRUE", "FALSE", "NULL" },
  ty = set_of {},
  lc = { "//", "#" },
  bc = { { "/%*", "%*/" } },
  str = { '"', "'" },
}

LANGS.html = {
  alias = { "xml", "vue", "svelte", "jsx", "tsx", "astro" },
  kw = set_of {},
  cnst = set_of {},
  ty = set_of {},
  lc = {},
  bc = { { "<!%-%-", "%-%->" } },
  str = { '"', "'" },
  tags = true,
}

LANGS.css = {
  alias = { "scss", "sass", "less" },
  kw = set_of {
    "important", "media", "import", "charset", "supports", "keyframes", "font-face",
  },
  cnst = set_of { "inherit", "initial", "unset", "auto", "none" },
  ty = set_of {},
  lc = {},
  bc = { { "/%*", "%*/" } },
  str = { '"', "'" },
}

LANGS.sql = {
  kw = set_of {
    "SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET",
    "DELETE", "CREATE", "TABLE", "DROP", "ALTER", "ADD", "COLUMN", "INDEX",
    "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "ON", "GROUP", "BY", "ORDER",
    "HAVING", "LIMIT", "OFFSET", "AS", "AND", "OR", "NOT", "NULL", "IS",
    "IN", "LIKE", "BETWEEN", "DISTINCT", "UNION", "ALL", "CASE", "WHEN",
    "THEN", "ELSE", "END", "PRIMARY", "KEY", "FOREIGN", "REFERENCES",
    "DEFAULT", "CONSTRAINT", "VIEW", "TRIGGER", "BEGIN", "COMMIT",
  },
  ci = true, -- 大小写不敏感
  cnst = set_of { "NULL", "TRUE", "FALSE" },
  ty = set_of { "INT", "VARCHAR", "TEXT", "DATE", "TIMESTAMP", "BOOLEAN", "DECIMAL", "BIGINT" },
  lc = { "%-%-" },
  bc = { { "/%*", "%*/" } },
  str = { '"', "'" },
}

LANGS.yaml = {
  alias = { "yml" },
  kw = set_of { "true", "false", "null", "yes", "no", "on", "off" },
  cnst = set_of { "true", "false", "null" },
  ty = set_of {},
  lc = { "#" },
  bc = {},
  str = { '"', "'" },
}

LANGS.toml = {
  alias = { "ini", "conf", "properties", "env" },
  kw = set_of { "true", "false" },
  cnst = set_of { "true", "false" },
  ty = set_of {},
  lc = { "#" },
  bc = {},
  str = { '"', "'" },
}

LANGS.vim = {
  alias = { "viml" },
  kw = set_of {
    "function", "endfunction", "if", "endif", "else", "elseif", "while",
    "endwhile", "for", "endfor", "return", "let", "set", "call", "autocmd",
    "augroup", "command", "noremap", "map", "lua", "require", "local",
  },
  cnst = set_of { "v:true", "v:false", "v:null" },
  ty = set_of {},
  lc = { '"' },
  bc = {},
  str = { "'" },
}

LANGS.diff = {
  kw = set_of {},
  cnst = set_of {},
  ty = set_of {},
  lc = {},
  bc = {},
  str = {},
  diff = true,
}

LANGS.markdown = {
  alias = { "md" },
  kw = set_of {},
  cnst = set_of {},
  ty = set_of {},
  lc = {},
  bc = {},
  str = {},
  plain = true,
}

-- 展开 alias
do
  local extra = {}
  for name, def in pairs(LANGS) do
    if def.alias then
      for _, a in ipairs(def.alias) do
        if not LANGS[a] then extra[a] = def end
      end
    end
  end
  for k, v in pairs(extra) do LANGS[k] = v end
end

--- 取语言定义（未知语言返回 nil）
function M.lang_def(lang)
  if not lang or lang == "" then return nil end
  local key = lang:lower()
  return LANGS[key]
end

--- 是否有该语言的定义
function M.supported(lang)
  return M.lang_def(lang) ~= nil
end

M.LANGS = LANGS

local IDENT_START = "[%a_%$@]"
local IDENT = "[%w_%$@]"

--- 词法扫描一行
--- @param line string 代码行
--- @param def table 语言定义
--- @param state table 跨行状态（块注释 / 块字符串），会被就地修改
--- @return table tokens {{s, e, type}}，0-based [s, e) 字节区间
function M.tokenize_line(line, def, state)
  local tokens = {}
  local i, n = 1, #line
  state = state or {}

  local function add(s, e, ty)
    if e > s then tokens[#tokens + 1] = { s - 1, e, ty } end
  end

  if not def or def.plain then
    return tokens
  end

  local kw = def.kw or {}
  local cnst = def.cnst or {}
  local ty = def.ty or {}
  local ci = def.ci
  local function lookup(tbl, word)
    if ci then return tbl[word:upper()] or tbl[word] end
    return tbl[word]
  end

  while i <= n do
    local c = line:sub(i, i)

    -- 仍处于块注释中
    if state.bc_end then
      local p = line:find(state.bc_end, i, true)
      if p then
        add(i, p + #state.bc_end - 1, "comment")
        i = p + #state.bc_end
        state.bc_end = nil
      else
        add(i, n, "comment")
        i = n + 1
      end
      goto continue
    end

    -- 仍处于多行字符串中
    if state.str_end then
      local p = line:find(state.str_end, i, true)
      if p then
        add(i, p + #state.str_end - 1, "string")
        i = p + #state.str_end
        state.str_end = nil
      else
        add(i, n, "string")
        i = n + 1
      end
      goto continue
    end

    -- 空白
    if c:match("%s") then
      local j = i
      while j <= n and line:sub(j, j):match("%s") do j = j + 1 end
      i = j
      goto continue
    end

    -- 行注释
    local hit = false
    for _, lc in ipairs(def.lc or {}) do
      if line:find("^" .. lc, i) then
        add(i, n, "comment")
        i = n + 1
        hit = true
        break
      end
    end
    if hit then goto continue end

    -- 块注释开始
    for _, bc in ipairs(def.bc or {}) do
      if line:find("^" .. bc[1], i) then
        local p = line:find(bc[2], i + 1, true)
        if p then
          add(i, p + #bc[2] - 1, "comment")
          i = p + #bc[2]
        else
          add(i, n, "comment")
          state.bc_end = bc[2]
          i = n + 1
        end
        hit = true
        break
      end
    end
    if hit then goto continue end

    -- 字符串
    for _, q in ipairs(def.str or {}) do
      if line:sub(i, i + #q - 1) == q then
        local j = i + #q
        local closed = false
        while j <= n do
          if line:sub(j, j) == "\\" then
            j = j + 2
          elseif line:sub(j, j + #q - 1) == q then
            closed = true
            break
          else
            j = j + 1
          end
        end
        if closed then
          add(i, j + #q - 1, "string")
          i = j + #q
        else
          -- 跨行字符串
          add(i, n, "string")
          state.str_end = q
          i = n + 1
        end
        hit = true
        break
      end
    end
    if hit then goto continue end

    -- 数字
    if c:match("%d") or (c == "." and line:sub(i + 1, i + 1):match("%d")) then
      local j = i
      if line:sub(i, i + 1):lower() == "0x" then
        j = i + 2
        while j <= n and line:sub(j, j):match("[%da-fA-F]") do j = j + 1 end
      else
        while j <= n and line:sub(j, j):match("[%d_]") do j = j + 1 end
        if line:sub(j, j) == "." then
          j = j + 1
          while j <= n and line:sub(j, j):match("[%d_]") do j = j + 1 end
        end
        local e = line:sub(j, j)
        if e == "e" or e == "E" then
          j = j + 1
          if line:sub(j, j) == "+" or line:sub(j, j) == "-" then j = j + 1 end
          while j <= n and line:sub(j, j):match("%d") do j = j + 1 end
        end
      end
      -- 单位后缀（如 10px、100ms）
      while j <= n and line:sub(j, j):match("[%a]") do j = j + 1 end
      add(i, j - 1, "number")
      i = j
      goto continue
    end

    -- 标识符 / 关键字
    if c:match(IDENT_START) then
      local j = i
      while j <= n and line:sub(j, j):match(IDENT) do j = j + 1 end
      local word = line:sub(i, j - 1)
      -- 后跟 '(' 视为函数调用
      local after = line:sub(j, j)
      if cnst[word] or (ci and cnst[word:upper()]) then
        add(i, j - 1, "constant")
      elseif lookup(kw, word) then
        add(i, j - 1, "keyword")
      elseif ty[word] or (ci and ty[word:upper()]) then
        add(i, j - 1, "type")
      elseif after == "(" then
        add(i, j - 1, "func")
      elseif word:match("^[A-Z]") then
        add(i, j - 1, "type")
      else
        add(i, j - 1, "variable")
      end
      i = j
      goto continue
    end

    -- 运算符
    if c:match("[-+*/%%=<>~!&|^?:]") then
      local j = i
      while j <= n and line:sub(j, j):match("[-+*/%%=<>~!&|^?:]") do j = j + 1 end
      add(i, j - 1, "operator")
      i = j
      goto continue
    end

    -- 其他标点
    if c:match("[%(%)%[%]{};,%.]") then
      add(i, i, "punct")
      i = i + 1
      goto continue
    end

    i = i + 1

    ::continue::
  end

  return tokens
end

--- 扫描整段代码，返回每行的 token 列表
--- @param code string
--- @param lang string
--- @return table 行数组，每行为 {{s,e,type}}
function M.tokenize(code, lang)
  local def = M.lang_def(lang)
  local lines = vim.split(code, "\n", { plain = true })
  local out = {}
  local state = {}
  for _, l in ipairs(lines) do
    out[#out + 1] = M.tokenize_line(l, def, state)
  end
  return out
end

return M
