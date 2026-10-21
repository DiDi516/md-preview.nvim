-- init.lua — md-preview.nvim 插件入口
--
-- 设计约束（遵循本机既有习惯）：
--   * 不设置任何按键映射，只暴露命令，避免占用既有肌肉记忆
--   * 不修改 leader、不触碰任何原生 vim 行为
--   * 预览窗口为只读 scratch buffer，所有样式通过 extmark 施加
local config = require("md-preview.config")
local parse = require("md-preview.parse")
local render_term = require("md-preview.render_term")
local theme = require("md-preview.theme")
local sync = require("md-preview.sync")
local export = require("md-preview.export")

local M = {}

M.ns = vim.api.nvim_create_namespace("md-preview")

local state = {
  opts = nil,
  initialized = false,
  sessions = {}, -- [src_bufnr] = session
  global_augroup = nil,
}

--------------------------------------------------------------------------------
-- 工具
--------------------------------------------------------------------------------

local function valid_win(w)
  return w and vim.api.nvim_win_is_valid(w)
end

local function valid_buf(b)
  return b and vim.api.nvim_buf_is_valid(b)
end

local function is_md_buf(buf, opts)
  if not valid_buf(buf) then return false end
  local ft = vim.bo[buf].filetype
  for _, f in ipairs(opts.filetypes) do
    if ft == f then return true end
  end
  return false
end

--- 当前配置（未 setup 时先初始化默认值，保证命令可直接用）
local function opts()
  if not state.opts then
    state.opts = config.defaults
  end
  return state.opts
end

--------------------------------------------------------------------------------
-- 预览窗口
--------------------------------------------------------------------------------

local function setup_prev_buf(buf, src_name)
  pcall(vim.api.nvim_buf_set_name, buf, "mdpreview://" .. (src_name ~= "" and src_name or tostring(buf)))
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].buflisted = false
  vim.bo[buf].filetype = "mdpreview"
  vim.bo[buf].undolevels = -1
end

local function setup_prev_win(win, statusline)
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldenable = false
  vim.wo[win].colorcolumn = ""
  vim.wo[win].list = false
  vim.wo[win].cursorline = false
  vim.wo[win].cursorcolumn = false
  vim.wo[win].spell = false
  vim.wo[win].conceallevel = 0
  vim.wo[win].statusline = statusline or " MD Preview "
  vim.wo[win].winfixwidth = false
end

--- 打开预览窗口，返回 session
local function open_window(sess)
  local o = opts()
  local src_win = vim.api.nvim_get_current_win()
  sess.src_win = src_win

  local cmd
  if o.position == "left" then cmd = "leftabove vsplit"
  elseif o.position == "above" then cmd = "leftabove split"
  elseif o.position == "below" then cmd = "rightbelow split"
  else cmd = "rightbelow vsplit" end

  vim.cmd(cmd)
  local prev_win = vim.api.nvim_get_current_win()
  sess.prev_win = prev_win

  -- 调整尺寸
  local vertical = (o.position == "left" or o.position == "right")
  local size = o.size or 0.5
  if size <= 1 and size > 0 then
    if vertical then
      local total = vim.o.columns
      vim.cmd("vertical resize " .. math.max(10, math.floor(total * size)))
    else
      local total = vim.o.lines
      vim.cmd("resize " .. math.max(3, math.floor(total * size)))
    end
  end

  local prev_buf = vim.api.nvim_create_buf(false, true)
  sess.prev_buf = prev_buf
  local src_name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(sess.src_buf), ":t")
  setup_prev_buf(prev_buf, src_name)
  vim.api.nvim_win_set_buf(prev_win, prev_buf)
  setup_prev_win(prev_win)

  -- 回到源窗口
  vim.api.nvim_set_current_win(src_win)
end

--------------------------------------------------------------------------------
-- 渲染
--------------------------------------------------------------------------------

--- 把渲染结果写入预览 buffer 并施加 extmark
local function apply(sess, lines)
  local buf = sess.prev_buf
  if not valid_buf(buf) then return end

  -- 暂停同步，避免写入过程中触发抖动
  sync.pause()

  local texts = {}
  for i, l in ipairs(lines) do texts[i] = l.text end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, texts)
  vim.bo[buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  for i, l in ipairs(lines) do
    local row = i - 1
    local maxcol = #l.text
    for idx, sp in ipairs(l.spans) do
      local s, e = sp[1], sp[2]
      if s < 0 then s = 0 end
      if e > maxcol then e = maxcol end
      if e > s then
        pcall(vim.api.nvim_buf_set_extmark, buf, M.ns, row, s, {
          end_row = row,
          end_col = e,
          hl_group = sp[3],
          -- 数组靠后的 span 优先级更高：先创建的整行底色会被行内样式覆盖
          priority = 100 + idx,
        })
      end
    end
  end

  local s2o, o2s = render_term.build_maps(lines)
  sync.update_maps(s2o, o2s)
  sync.resume()
end

--- 渲染一次
function M.render_session(sess)
  if not valid_buf(sess.src_buf) or not valid_buf(sess.prev_buf) then return end
  local o = opts()

  local lines = vim.api.nvim_buf_get_lines(sess.src_buf, 0, -1, false)
  local text = table.concat(lines, "\n")

  local ok, ast = pcall(parse.parse, text)
  if not ok or not ast then
    vim.schedule(function()
      vim.notify("[md-preview] 解析失败: " .. tostring(ast), vim.log.levels.ERROR)
    end)
    return
  end

  local width = vim.api.nvim_win_get_width(sess.prev_win) - 1
  if o.max_width and o.max_width > 0 then
    width = math.min(width, o.max_width)
  end
  if width < 20 then width = 20 end

  local ropts = vim.tbl_extend("force", {}, o, { width = width })
  local ok2, rendered = pcall(render_term.render, ast, ropts)
  if not ok2 or not rendered then
    vim.schedule(function()
      vim.notify("[md-preview] 渲染失败: " .. tostring(rendered), vim.log.levels.ERROR)
    end)
    return
  end

  apply(sess, rendered)
  sess.rendered = rendered
end

--- 防抖渲染
local function schedule_render(sess)
  if sess.timer then
    pcall(function() sess.timer:stop() end)
    sess.timer = nil
  end
  local delay = opts().debounce or 150
  if delay <= 0 then
    vim.schedule(function() M.render_session(sess) end)
    return
  end
  sess.timer = vim.defer_fn(function()
    sess.timer = nil
    if valid_buf(sess.src_buf) and valid_buf(sess.prev_buf) then
      M.render_session(sess)
    end
  end, delay)
end

--------------------------------------------------------------------------------
-- 会话管理
--------------------------------------------------------------------------------

local function close_session(src_bufnr, restore_win)
  local sess = state.sessions[src_bufnr]
  if not sess then return end
  state.sessions[src_bufnr] = nil

  if sess.timer then pcall(function() sess.timer:stop() end) end
  if sess.augroup then
    pcall(vim.api.nvim_clear_autocmds, { group = sess.augroup })
  end
  sync.detach()

  if valid_win(sess.prev_win) then
    if valid_buf(sess.prev_buf) then
      pcall(vim.api.nvim_buf_clear_namespace, sess.prev_buf, M.ns, 0, -1)
    end
    -- 关闭预览窗口（不误伤源 buffer）
    pcall(vim.api.nvim_win_close, sess.prev_win, true)
  end
  if valid_buf(sess.prev_buf) then
    pcall(vim.api.nvim_buf_delete, sess.prev_buf, { force = true })
  end

  if restore_win and valid_win(sess.src_win) then
    pcall(vim.api.nvim_set_current_win, sess.src_win)
  end
end

--- 启动预览
--- @param src_bufnr number|nil
function M.start(src_bufnr)
  src_bufnr = src_bufnr or vim.api.nvim_get_current_buf()
  local o = opts()

  if not is_md_buf(src_bufnr, o) then
    vim.notify("[md-preview] 当前文件类型不是 markdown（" .. vim.bo[src_bufnr].filetype .. "）",
      vim.log.levels.WARN)
    return false
  end

  -- 已有会话：若窗口仍有效则复用
  local sess = state.sessions[src_bufnr]
  if sess and valid_win(sess.prev_win) and valid_buf(sess.prev_buf) then
    M.render_session(sess)
    return true
  end
  if sess then close_session(src_bufnr, false) end

  sess = { src_buf = src_bufnr }
  state.sessions[src_bufnr] = sess

  open_window(sess)

  -- buffer 局部自动命令：文本变更即刷新
  sess.augroup = vim.api.nvim_create_augroup("MdPreviewBuf" .. src_bufnr, { clear = true })
  vim.api.nvim_create_autocmd(o.refresh_events or { "TextChanged", "TextChangedI" }, {
    group = sess.augroup,
    buffer = src_bufnr,
    callback = function() schedule_render(sess) end,
  })
  -- 源 buffer 关闭时收摊
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete", "BufUnload" }, {
    group = sess.augroup,
    buffer = src_bufnr,
    callback = function()
      if o.auto_close then close_session(src_bufnr, false) end
    end,
  })
  -- 预览窗口尺寸变化时按新宽度重排
  vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
    group = sess.augroup,
    callback = function()
      if valid_win(sess.prev_win) then schedule_render(sess) end
    end,
  })

  M.render_session(sess)

  if o.scroll_sync then
    local s2o, o2s = render_term.build_maps(sess.rendered or {})
    sync.attach(sess.src_win, sess.prev_win, s2o, o2s, o)
  end
  return true
end

--- 停止预览
function M.stop(src_bufnr)
  src_bufnr = src_bufnr or vim.api.nvim_get_current_buf()
  if not state.sessions[src_bufnr] then
    return false
  end
  close_session(src_bufnr, true)
  return true
end

--- 切换
function M.toggle(src_bufnr)
  src_bufnr = src_bufnr or vim.api.nvim_get_current_buf()
  if state.sessions[src_bufnr] and valid_win(state.sessions[src_bufnr].prev_win) then
    return M.stop(src_bufnr)
  end
  return M.start(src_bufnr)
end

--- 是否处于预览状态
function M.is_active(src_bufnr)
  src_bufnr = src_bufnr or vim.api.nvim_get_current_buf()
  local s = state.sessions[src_bufnr]
  return s ~= nil and valid_win(s.prev_win)
end

--- 手动刷新
function M.refresh(src_bufnr)
  src_bufnr = src_bufnr or vim.api.nvim_get_current_buf()
  local sess = state.sessions[src_bufnr]
  if not sess then return false end
  M.render_session(sess)
  return true
end

--------------------------------------------------------------------------------
-- 命令与自动命令（不创建任何按键映射）
--------------------------------------------------------------------------------

local function register_commands()
  vim.api.nvim_create_user_command("MdPreviewStart", function()
    M.start()
  end, { desc = "启动 Markdown 实时预览" })

  vim.api.nvim_create_user_command("MdPreviewStop", function()
    M.stop()
  end, { desc = "关闭 Markdown 实时预览" })

  vim.api.nvim_create_user_command("MdPreviewToggle", function()
    M.toggle()
  end, { desc = "切换 Markdown 实时预览" })

  vim.api.nvim_create_user_command("MdPreviewRefresh", function()
    M.refresh()
  end, { desc = "立即重新渲染预览" })

  vim.api.nvim_create_user_command("MdPreviewExport", function(a)
    local path = (a.args and a.args ~= "") and a.args or nil
    local ok, res = export.export(vim.api.nvim_get_current_buf(), path, opts())
    if ok then
      vim.notify("[md-preview] 已导出: " .. res, vim.log.levels.INFO)
    else
      vim.notify("[md-preview] 导出失败: " .. tostring(res), vim.log.levels.ERROR)
    end
  end, {
    desc = "导出当前文档为自包含 HTML",
    nargs = "?",
    complete = "file",
  })
end

local function register_autocmds()
  if state.global_augroup then return end
  state.global_augroup = vim.api.nvim_create_augroup("MdPreviewGlobal", { clear = true })

  -- 自动启动（默认关闭）
  vim.api.nvim_create_autocmd("FileType", {
    group = state.global_augroup,
    pattern = opts().filetypes,
    callback = function(ev)
      if opts().auto_start then
        vim.schedule(function() M.start(ev.buf) end)
      end
    end,
  })
end

--------------------------------------------------------------------------------
-- setup
--------------------------------------------------------------------------------

--- 初始化插件
--- @param user_opts table|nil
function M.setup(user_opts)
  if state.initialized then
    -- 配置变更：重新合并并刷新高亮
    state.opts = config.resolve(user_opts)
    theme.setup(state.opts)
    return
  end
  state.opts = config.resolve(user_opts)
  theme.setup(state.opts)
  register_commands()
  register_autocmds()
  state.initialized = true
end

--- 供外部读取当前配置（调试用）
function M.get_opts()
  return opts()
end

--- 供外部读取会话（调试用）
function M.get_sessions()
  return state.sessions
end

return M
