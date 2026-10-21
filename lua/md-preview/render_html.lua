-- render_html.lua — AST → 自包含 HTML（导出用）
-- 复用同一棵 AST，保证导出的 HTML 与终端预览内容一致。
-- 默认不引入任何 CDN；开启 export.cdn 后会加载 KaTeX / Mermaid / highlight.js。
local util = require("md-preview.util")
local codehl = require("md-preview.codehl")

local M = {}

local function esc(s)
  return util.escape_html(s or "")
end

--------------------------------------------------------------------------------
-- 行内
--------------------------------------------------------------------------------

local function inline(nodes)
  local out = {}
  for _, n in ipairs(nodes) do
    local t = n.t
    if t == "text" then
      out[#out + 1] = esc(n.value):gsub("\n", " ")
    elseif t == "code" then
      out[#out + 1] = "<code>" .. esc(n.value) .. "</code>"
    elseif t == "strong" then
      out[#out + 1] = "<strong>" .. inline(n.children) .. "</strong>"
    elseif t == "em" then
      out[#out + 1] = "<em>" .. inline(n.children) .. "</em>"
    elseif t == "del" then
      out[#out + 1] = "<del>" .. inline(n.children) .. "</del>"
    elseif t == "mark" then
      out[#out + 1] = "<mark>" .. inline(n.children) .. "</mark>"
    elseif t == "link" then
      out[#out + 1] = string.format('<a href="%s"%s>%s</a>',
        esc(n.url),
        n.title and (' title="' .. esc(n.title) .. '"') or "",
        inline(n.children))
    elseif t == "autolink" then
      out[#out + 1] = string.format('<a href="%s">%s</a>', esc(n.url), esc(n.url))
    elseif t == "image" then
      out[#out + 1] = string.format('<img src="%s" alt="%s"%s />',
        esc(n.url), esc(n.alt or ""),
        n.title and (' title="' .. esc(n.title) .. '"') or "")
    elseif t == "math" then
      out[#out + 1] = '<span class="math">' .. esc(n.value) .. "</span>"
    elseif t == "footnote_ref" then
      out[#out + 1] = string.format('<sup class="fnref"><a href="#fn-%s">%s</a></sup>',
        esc(n.label), esc(n.label))
    elseif t == "br" then
      out[#out + 1] = "<br />"
    elseif t == "html" then
      out[#out + 1] = n.value
    end
  end
  return table.concat(out)
end

--------------------------------------------------------------------------------
-- 代码块（可选词法着色）
--------------------------------------------------------------------------------

local function code_block(b, use_hl)
  local lang = b.lang or ""
  local lines = vim.split(b.code, "\n", { plain = true })
  local body
  if use_hl and codehl.supported(lang) then
    local def = codehl.lang_def(lang)
    local st = {}
    local buf = {}
    for _, l in ipairs(lines) do
      local toks = codehl.tokenize_line(l, def, st)
      if #toks == 0 then
        buf[#buf + 1] = esc(l)
      else
        local parts = {}
        local pos = 1
        for _, tk in ipairs(toks) do
          if tk[1] + 1 > pos then
            parts[#parts + 1] = esc(l:sub(pos, tk[1]))
          end
          parts[#parts + 1] = string.format('<span class="tok-%s">%s</span>',
            tk[3], esc(l:sub(tk[1] + 1, tk[2])))
          pos = tk[2] + 1
        end
        if pos <= #l then parts[#parts + 1] = esc(l:sub(pos)) end
        buf[#buf + 1] = table.concat(parts)
      end
    end
    body = table.concat(buf, "\n")
  else
    body = esc(b.code)
  end
  return string.format('<pre><code class="language-%s">%s</code></pre>', esc(lang), body)
end

--------------------------------------------------------------------------------
-- 块级
--------------------------------------------------------------------------------

local function blocks(list, o)
  local out = {}
  for _, b in ipairs(list) do
    local t = b.t
    if t == "heading" then
      out[#out + 1] = string.format("<h%d>%s</h%d>", b.level, inline(b.inline), b.level)
    elseif t == "paragraph" then
      out[#out + 1] = "<p>" .. inline(b.inline) .. "</p>"
    elseif t == "code" then
      out[#out + 1] = code_block(b, o.cdn and o.cdn.highlight)
    elseif t == "blockquote" then
      out[#out + 1] = "<blockquote>" .. blocks(b.blocks, o) .. "</blockquote>"
    elseif t == "list" then
      local tag = b.ordered and "ol" or "ul"
      local start = (b.ordered and b.start and b.start ~= 1) and (' start="' .. b.start .. '"') or ""
      local items = {}
      local cls = ""
      for _, item in ipairs(b.items) do
        if item.checked ~= nil then cls = ' class="contains-task-list"' end
      end
      for _, item in ipairs(b.items) do
        local inner = blocks(item.blocks, o)
        if item.checked ~= nil then
          local cb = string.format('<input type="checkbox" disabled%s /> ', item.checked and " checked" or "")
          inner = cb .. inner
          items[#items + 1] = '<li class="task-list-item">' .. inner .. "</li>"
        else
          items[#items + 1] = "<li>" .. inner .. "</li>"
        end
      end
      out[#out + 1] = string.format("<%s%s%s>%s</%s>", tag, start, cls, table.concat(items), tag)
    elseif t == "table" then
      local aligns = {}
      for i, a in ipairs(b.aligns) do
        aligns[i] = string.format(' style="text-align:%s"', a)
      end
      local head = {}
      for i, c in ipairs(b.header) do
        head[#head + 1] = string.format("<th%s>%s</th>", aligns[i] or "", inline(c))
      end
      local rows = {}
      for _, r in ipairs(b.rows) do
        local cells = {}
        for i, c in ipairs(r) do
          cells[#cells + 1] = string.format("<td%s>%s</td>", aligns[i] or "", inline(c))
        end
        rows[#rows + 1] = "<tr>" .. table.concat(cells) .. "</tr>"
      end
      out[#out + 1] = string.format(
        "<table>\n<thead><tr>%s</tr></thead>\n<tbody>\n%s\n</tbody>\n</table>",
        table.concat(head), table.concat(rows, "\n"))
    elseif t == "hr" then
      out[#out + 1] = "<hr />"
    elseif t == "math" then
      out[#out + 1] = string.format('<div class="math-block">$$%s$$</div>', esc(b.value))
    elseif t == "mermaid" then
      out[#out + 1] = string.format('<pre class="mermaid">%s</pre>', esc(b.code))
    elseif t == "html" then
      out[#out + 1] = b.raw
    elseif t == "footnote" then
      out[#out + 1] = string.format('<div class="footnote" id="fn-%s">[^%s]: %s</div>',
        esc(b.label), esc(b.label), blocks(b.blocks, o))
    elseif t == "frontmatter" then
      -- front matter 是元数据，导出时隐藏
    end
  end
  return table.concat(out, "\n")
end

--------------------------------------------------------------------------------
-- 样式
--------------------------------------------------------------------------------

local CSS = [[
:root { color-scheme: dark; }
body {
  margin: 0 auto; padding: 2rem 1.5rem; max-width: 860px;
  background: #24273a; color: #cad3f5;
  font-family: -apple-system, "Segoe UI", "Microsoft YaHei", "PingFang SC", sans-serif;
  font-size: 15px; line-height: 1.75;
}
h1, h2, h3, h4, h5, h6 { line-height: 1.3; margin: 1.6em 0 .6em; font-weight: 700; }
h1 { color: #c6a0f6; border-bottom: 2px solid #c6a0f6; padding-bottom: .3em; font-size: 1.9em; }
h2 { color: #8aadf4; border-bottom: 1px solid #494d64; padding-bottom: .25em; font-size: 1.5em; }
h3 { color: #8bd5ca; font-size: 1.25em; }
h4 { color: #7dc4e4; } h5 { color: #b7bdf8; } h6 { color: #b8c0e0; }
p { margin: .8em 0; }
a { color: #8aadf4; text-decoration: none; border-bottom: 1px solid #494d64; }
a:hover { border-bottom-color: #8aadf4; }
code {
  background: #363a4f; color: #f5a97f; padding: .15em .4em;
  border-radius: 4px; font-size: .9em;
  font-family: "Cascadia Code", "JetBrains Mono", Consolas, monospace;
}
pre {
  background: #1e2030; border: 1px solid #363a4f; border-radius: 8px;
  padding: 1rem; overflow-x: auto; line-height: 1.55;
}
pre code { background: none; color: #cad3f5; padding: 0; font-size: .88em; }
blockquote {
  margin: 1em 0; padding: .2em 1em; color: #939ab7;
  border-left: 4px solid #5b6078; background: #1e2030; border-radius: 0 6px 6px 0;
}
table { border-collapse: collapse; margin: 1em 0; display: block; overflow-x: auto; }
th, td { border: 1px solid #494d64; padding: .45em .8em; }
th { background: #363a4f; color: #b7bdf8; font-weight: 700; }
tr:nth-child(even) td { background: #1e2030; }
hr { border: none; border-top: 1px solid #494d64; margin: 2em 0; }
img { max-width: 100%; border-radius: 6px; }
ul, ol { padding-left: 1.6em; }
li { margin: .25em 0; }
.task-list-item { list-style: none; margin-left: -1.2em; }
mark { background: #eed49f; color: #24273a; padding: 0 .2em; border-radius: 3px; }
del { color: #8087a2; }
.footnote { color: #eed49f; font-size: .9em; border-top: 1px solid #363a4f; margin-top: 2em; padding-top: .5em; }
.math, .math-block { color: #f5bde6; }
.math-block { text-align: center; padding: .6em 0; }
.tok-keyword { color: #c6a0f6; }
.tok-string { color: #a6da95; }
.tok-comment { color: #8087a2; font-style: italic; }
.tok-number { color: #f5a97f; }
.tok-func { color: #8aadf4; }
.tok-type { color: #eed49f; }
.tok-operator { color: #91d7e3; }
.tok-punct { color: #939ab7; }
.tok-constant { color: #f5a97f; }
.tok-variable { color: #cad3f5; }
]]

local CDN = {
  katex = [[
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css">
<script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js"></script>
<script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/contrib/auto-render.min.js"
  onload="renderMathInElement(document.body,{delimiters:[{left:'$$',right:'$$',display:true},{left:'$',right:'$',display:false}]});"></script>
]],
  mermaid = [[
<script type="module">
  import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs';
  mermaid.initialize({ startOnLoad: true, theme: 'dark' });
</script>
]],
  highlight = [[
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/highlight.js@11.9.0/styles/github-dark.min.css">
<script src="https://cdn.jsdelivr.net/npm/highlight.js@11.9.0/lib/highlight.min.js"></script>
<script>document.addEventListener('DOMContentLoaded',()=>hljs.highlightAll());</script>
]],
}

--------------------------------------------------------------------------------
-- 入口
--------------------------------------------------------------------------------

--- 渲染完整 HTML 文档
--- @param ast table parse.parse() 的结果
--- @param opts table export 配置段
--- @param meta table|nil { title = "…" }
function M.render(ast, opts, meta)
  opts = opts or {}
  meta = meta or {}
  local cdn = opts.cdn or {}
  local head = {}
  head[#head + 1] = '<meta charset="utf-8" />'
  head[#head + 1] = '<meta name="viewport" content="width=device-width, initial-scale=1" />'
  head[#head + 1] = "<title>" .. esc(meta.title or "Markdown 导出") .. "</title>"
  head[#head + 1] = "<style>" .. CSS .. (opts.extra_css or "") .. "</style>"
  for _, k in ipairs({ "katex", "mermaid", "highlight" }) do
    if cdn[k] then head[#head + 1] = CDN[k] end
  end

  local body = blocks(ast.blocks, opts)
  return table.concat({
    "<!DOCTYPE html>",
    "<html lang=\"zh-CN\">",
    "<head>", table.concat(head, "\n"), "</head>",
    "<body>", body, "</body>",
    "</html>",
  }, "\n")
end

return M
