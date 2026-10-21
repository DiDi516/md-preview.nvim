# md-preview.nvim

**在 Neovim 终端里实时预览 Markdown**——右侧分屏、边写边渲染、双向滚动同步。

纯 Lua + Neovim API，**零依赖**：不用 Node，不用 Python，不用开浏览器。

![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-57A143?logo=neovim&logoColor=white)
![Lua](https://img.shields.io/badge/Lua-LuaJIT-2C2D72?logo=lua&logoColor=white)
![Platform](https://img.shields.io/badge/platform-Windows%20%2F%20Linux%20%2F%20macOS-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)

---

## 效果

以下全部是**真实渲染输出**（Windows Terminal + Neovim 0.12.4 实测截取，未做修饰）。
想自己看，打开 `test/demo.md` 执行 `:MdPreviewToggle` 即可。

**表格**按显示宽度对齐，中英混排不错位；**代码块**带 Unicode 边框与词法着色：

```
┌────────────┬──────┬──────┬──────────────┐
│ 名称       │ 数量 │ 单价 │ 说明         │
├────────────┼──────┼──────┼──────────────┤
│ 苹果       │  3   │ 5.00 │ 水果         │
│ 中文列名   │  12  │ 1.50 │ 测试中文对齐 │
│ mixed 混合 │  8   │ 2.25 │ 中英混排     │
└────────────┴──────┴──────┴──────────────┘

╭─ lua ──────────────────────────╮
│ local function greet(name)     │
│   -- 问候某人                  │
│   local msg = "你好, " .. name │
│   return msg                   │
│ end                            │
╰────────────────────────────────╯
```

**Mermaid 流程图**（自动分层布局，含回边处理）：

```
┌──────┐
│ 开始 │
└──────┘
   │
   └───┐
       ▼
  ◇ 是否登录 ◇
     是│     否
     ┌─└─────────────┐
     │               │
     │               │
     ▼               ▼
┌──────────┐    ┌──────────┐
│ 进入主页 │    │ 跳转登录 │
└──────────┘    └──────────┘
     │               │
     └─────────────┐─┘
     ▼             ▼
┌──────────┐    ┌──────┐
│ 输入账号 │    │ 结束 │
└──────────┘    └──────┘
```

**时序图**（参与者生命线 + 消息箭头，虚线表示返回）：

```
客户端      服务端      数据库
   │           │           │
     请求数据
   │──────────▶│           │
     返回结果
   │◀┈┈┈┈┈┈┈┈┈┈│           │
             查询
   │──────────────────────▶│
             记录
   │◀┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈│

   │           │           │
```

**数学公式**：行内 `$E = mc^2$` → `E = mc²`；块级公式居中，矩阵用框线渲染：

```
         ∫₀∞ e⁻x² dx = √(π)⁄2

              ⎡ 1  2 ⎤
              ⎣ 3  4 ⎦
              ⎛ a ⎞
              ⎝ b ⎠
              =
         ⎛ a + 2b  ⎞
         ⎝ 3a + 4b ⎠
```

---

## 特性

- **零依赖**——不装 Node、不装 Python、不起 HTTP 服务、不开浏览器
- **终端内渲染**——样式通过 extmark 施加，不离开编辑器
- **双向滚动同步**——编辑时预览跟随，浏览预览时源光标跟随
- **中文按显示宽度对齐**——表格、列表缩进、代码块边框都不会错位
- **代码词法着色**——内置 20+ 语言（Lua / Python / JS / TS / Rust / Go / Java / C / C++ …）
- **数学公式**——LaTeX → Unicode：希腊字母、∑ ∫ ∞、上标下标、分式、根号、矩阵
- **Mermaid**——flowchart（TD / LR）与时序图渲染为字符画，其他类型降级为标注块
- **一键导出**——导出自包含 HTML，与预览内容完全一致（共用同一棵 AST）
- **不占用任何按键**——只提供命令，避免抢占既有肌肉记忆
- **配色跟随主题**——默认取 catppuccin 调色板，取不到时用内置色板，也可逐项覆盖

---

## 要求

- **Neovim >= 0.9**（用到 `WinScrolled` 事件与 extmark `priority`）。开发与测试环境为 0.12.4。
- **终端建议支持真彩色 + 粗体/斜体/下划线**：Windows Terminal、iTerm2、kitty、WezTerm、Alacritty 均可。
  不支持的终端可在 `attrs` 中关掉对应属性，自动退化为纯颜色。
- `catppuccin` 主题**可选**——未安装时使用内置 macchiato 色板，不影响功能。

---

## 安装

### lazy.nvim（推荐）

```lua
{
  "runtu/md-preview.nvim",
  ft = { "markdown", "md" },
  cmd = {
    "MdPreviewStart", "MdPreviewStop", "MdPreviewToggle",
    "MdPreviewRefresh", "MdPreviewExport",
  },
  opts = {
    position = "right",  -- 预览窗口位置
    size = 0.5,          -- 占比
  },
}
```

`opts` 会自动调用 `require("md-preview").setup(opts)`。需要更复杂的初始化可改用 `config`：

```lua
config = function()
  require("md-preview").setup({ position = "right", size = 0.5 })
end
```

### packer.nvim

```lua
use {
  "runtu/md-preview.nvim",
  ft = { "markdown", "md" },
  config = function() require("md-preview").setup() end,
}
```

### vim-plug

```vim
Plug 'runtu/md-preview.nvim'
" 之后在 init.lua 中调用 require("md-preview").setup()
```

### 手动

```bash
git clone https://github.com/runtu/md-preview.nvim \
  ~/.local/share/nvim/site/pack/plugins/start/md-preview.nvim
```

> **本地开发**：若你直接改本仓库源码而非通过插件管理器安装，用 lazy 的 `dir` 方式指向本地路径即可：
> ```lua
> { dir = "/path/to/md-preview.nvim", name = "md-preview", ft = "markdown", opts = {} }
> ```

---

## 使用

插件**刻意不绑定任何按键**，只提供命令：

| 命令 | 作用 |
|---|---|
| `:MdPreviewToggle` | 开关预览（最常用） |
| `:MdPreviewStart` | 启动预览 |
| `:MdPreviewStop` | 关闭预览 |
| `:MdPreviewRefresh` | 立即重新渲染 |
| `:MdPreviewExport [路径]` | 导出自包含 HTML，默认写到源文件同名 `.html` |

想绑快捷键的话自己加（默认未启用）：

```lua
vim.keymap.set("n", "<leader>mp", "<cmd>MdPreviewToggle<cr>", { desc = "Markdown 预览" })
```

完整文档见 `:help md-preview`。

---

## 配置

```lua
require("md-preview").setup({
  -- 窗口
  position = "right",        -- right | left | above | below
  size = 0.5,                -- 预览窗口占比
  auto_start = false,        -- 打开 markdown 时自动启动
  auto_close = true,         -- 源文件关闭时自动关闭预览

  -- 刷新
  debounce = 200,            -- 文本变更后的防抖毫秒数

  -- 渲染
  show_url = false,          -- 链接后是否附加 URL 文本
  image_icon = "▣",          -- 图片占位图标
  code_lang_label = true,    -- 代码块顶部显示语言名
  code_line_numbers = false, -- 代码块行号
  max_width = 0,             -- 渲染最大宽度，0 = 跟随预览窗口

  -- 滚动同步
  scroll_sync = true,        -- 源 → 预览
  scroll_sync_reverse = true,-- 预览 → 源
  sync_mode = "topline",     -- topline（顶部对齐）| cursor（光标行对齐）

  -- 终端能力：老旧终端不支持时关掉对应属性
  attrs = { bold = true, italic = true, underline = true, strikethrough = true },

  filetypes = { "markdown", "md", "mdx", "rmd", "qmd" },

  -- 导出（默认不引任何 CDN）
  export = {
    cdn = { katex = false, mermaid = false, highlight = false },
    extra_css = nil,
  },
})
```

### 自定义配色

配色默认取 catppuccin 当前 flavour。也可逐项覆盖任意高亮组：

```lua
require("md-preview").setup({
  highlights = {
    MdPreviewH1 = { fg = "#c6a0f6", bold = true },
    MdPreviewCodeBlock = { bg = "#1e2030" },
  },
})
```

可用高亮组见 `:help md-preview-highlights`。

---

## 支持的语法

| 元素 | 终端呈现 |
|---|---|
| H1 / H2 | 彩色粗体 + `━` / `─` 装饰线 |
| H3–H6 | 逐级配色 + `▍` `▎` `·` 标记 |
| 粗体 / 斜体 / 删除线 / `==高亮==` | bold / italic / strikethrough / 反显 |
| 行内代码 | 反显 + 底色 |
| 围栏代码块 | `╭─ lua ─╮` 边框 + 20+ 语言词法着色 |
| 表格 | Unicode 制表符，支持 `:---` `---:` `:-:` 三种对齐 |
| 列表 / 任务列表 | `•` `◦` `▪` + `[✓]` `[ ]`，任意层级嵌套 |
| 引用 | `▎` 竖条 + 暗色斜体 |
| 链接 / 引用式链接 | 彩色下划线，可选显示 URL |
| 数学 `$...$` `$$...$$` | LaTeX → Unicode（∑ ∫ α ² ₁ 等） |
| Mermaid | flowchart、时序图渲染为字符画 |
| 脚注 / front matter | 黄色标记 / 暗色原样 |

想快速看全部效果，打开 `test/demo.md` 后执行 `:MdPreviewToggle`。

---

## 架构

统一 AST + 双后端：解析一次，终端预览与 HTML 导出共用同一棵树，
因此**导出结果和预览内容永远一致**，不会出现两套解析器行为分叉。

```
markdown 源码
      │
      ▼
  parse.lua  ──►  统一 AST（块级 + 行内）
      │
      ├──► render_term.lua  ──►  终端行 { text, spans }   ← 实时预览
      └──► render_html.lua  ──►  自包含 HTML              ← 导出
```

```
lua/md-preview/
├── init.lua         入口：窗口管理、命令、防抖刷新
├── config.lua       默认配置
├── parse.lua        Markdown → AST（块级 + 行内）
├── render_term.lua  AST → 终端行 + span
├── render_html.lua  AST → HTML
├── codehl.lua       代码词法着色（20+ 语言）
├── math.lua         LaTeX → Unicode
├── mermaid.lua      Mermaid → 字符画
├── sync.lua         双向滚动同步
├── theme.lua        高亮组（跟随 catppuccin）
├── export.lua       HTML 导出
└── util.lua         字符串 / Unicode 宽度工具
```

---

## 与其他方案的对比

| | 浏览器方案（如 markdown-preview.nvim） | 本插件（终端内） |
|---|---|---|
| 依赖 | Node + 浏览器 | 无 |
| 启动 | 起 HTTP 服务 | 直接开 buffer |
| 跨机器复现 | 需重装依赖 | 拷目录即用 |
| 粗体 / 斜体 | 真字体 | 依赖终端能力 |
| 图片 | 可显示 | 占位符（终端硬限制） |
| Mermaid | 矢量图 | 字符画 |

---

## 测试

在仓库根目录执行：

```bash
nvim --headless -c "set rtp+=." -c "luafile test/unit.lua" -c "q"
nvim --headless -c "set columns=160 lines=48" -c "luafile test/ui.lua" -c "q!"
```

- `test/unit.lua`——解析、渲染、数学、Mermaid、代码高亮、HTML 导出（46 项断言）
- `test/ui.lua`——窗口创建、extmark 施加、滚动同步映射、导出文件（27 项）

---

## 已知限制

1. **图片无法在终端显示**，渲染为 `▣ alt` 占位符。
2. **粗体 / 斜体 / 删除线依赖终端能力**。不支持时可在 `attrs` 中关掉，退化为纯颜色区分。
3. **Mermaid 仅支持 flowchart 与 sequenceDiagram**，其余类型（classDiagram / gantt / pie 等）
   降级为标注块并保留源码，不丢信息。
4. 极端边缘的 Markdown 语法可能解析不精确，此时按纯文本处理，不会报错。
5. 预览窗口为只读 buffer，在其中编辑不会写回源文件。

---

## 贡献

欢迎 Issue 与 PR。提交前请确保两套测试通过；若新增语法支持，
请同时在 `test/demo.md` 中加一条样例，并在 `test/unit.lua` 中补断言。

---

## 协议

[MIT](LICENSE) © 2026 runtu
