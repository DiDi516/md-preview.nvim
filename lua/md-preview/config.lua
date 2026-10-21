-- config.lua — 默认配置
-- 所有选项都可在 setup() 中覆盖。
local util = require("md-preview.util")

local M = {}

--- 默认配置
M.defaults = {
  -- ── 窗口 ──────────────────────────────────────────────
  position = "right",    -- 预览窗口位置：right | left | above | below
  size = 0.5,            -- 占据比例（0.0 ~ 1.0）
  auto_start = false,    -- 打开 markdown 文件时自动启动预览
  auto_close = true,     -- 源文件关闭时自动关闭预览窗口

  -- ── 刷新 ──────────────────────────────────────────────
  debounce = 200,        -- 文本变更后的防抖毫秒数
  refresh_events = { "TextChanged", "TextChangedI", "InsertLeave", "BufWritePost" },

  -- ── 渲染 ──────────────────────────────────────────────
  show_url = false,      -- 链接后是否附加 URL 文本
  image_icon = "▣",      -- 图片占位图标
  code_lang_label = true,-- 代码块顶部是否显示语言名
  code_line_numbers = false,
  quote_bar = "▎",       -- 引用块竖条
  todo_done = "[✓]",
  todo_pending = "[ ]",
  -- 标题标记（索引 1~6 对应 H1~H6；H1/H2 用装饰线，此处仅 H3~H6 生效）
  heading_markers = { "", "", "▍", "▎", "·", "·" },
  max_width = 0,         -- 渲染最大宽度，0 表示跟随预览窗口宽度

  -- ── 滚动同步 ──────────────────────────────────────────
  scroll_sync = true,     -- 源 → 预览
  scroll_sync_reverse = true, -- 预览 → 源
  sync_mode = "topline",  -- topline（顶部对齐）| cursor（光标行对齐）

  -- ── 终端能力 ──────────────────────────────────────────
  -- 老旧终端不支持斜体 / 删除线时，可在此关掉对应属性
  attrs = {
    bold = true,
    italic = true,
    underline = true,
    strikethrough = true,
  },

  -- ── 文件类型 ──────────────────────────────────────────
  filetypes = { "markdown", "md", "mdx", "rmd", "qmd" },

  -- ── 导出 ──────────────────────────────────────────────
  export = {
    -- 导出 HTML 时是否内嵌 CDN 脚本（KaTeX / Mermaid / highlight.js）
    cdn = {
      katex = false,
      mermaid = false,
      highlight = false,
    },
    -- 自定义 <style> 追加内容
    extra_css = nil,
    title = nil, -- 默认取文件名
  },

  -- ── 高亮组覆盖 ────────────────────────────────────────
  highlights = {},
}

--- 合并用户配置
function M.resolve(opts)
  return util.merge(M.defaults, opts or {})
end

return M
