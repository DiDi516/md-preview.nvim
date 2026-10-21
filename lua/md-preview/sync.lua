-- sync.lua — 源窗口与预览窗口的双向滚动同步
--
-- 实现要点：
--   1. 映射基于渲染时记录的 src_line（已做线性插值，见 render_term.build_maps）
--   2. 双向同步必须用 guard 阻断回调重入，否则 A→B→A 会无限循环
--   3. 监听 CursorMoved 与 WinScrolled：前者覆盖移动光标，后者覆盖纯滚动
local M = {}

--- 会话状态
--- @class SyncState
local state = {
  augroup = nil,
  src_win = nil,
  prev_win = nil,
  s2o = {},
  o2s = {},
  opts = {},
  guard = false,
  enabled = false,
}

local function valid_win(w)
  return w and vim.api.nvim_win_is_valid(w)
end

--- 设置窗口顶部行（同时把光标带过去，避免光标留在可视区外）
local function set_topline(win, line)
  if not valid_win(win) then return end
  vim.api.nvim_win_call(win, function()
    local last = vim.fn.line("$")
    local n = math.max(1, math.min(line, last))
    -- 光标需落在窗口内，否则 winrestview 之后会被强制拉回
    local cur = vim.fn.line(".")
    local target = cur
    if cur < n then target = n end
    local height = vim.api.nvim_win_get_height(win)
    if cur > n + height - 1 then target = n + height - 1 end
    if target > last then target = last end
    vim.fn.winrestview({ topline = n, lnum = target })
  end)
end

--- 设置窗口光标行（cursor 模式）
local function set_cursor_line(win, line)
  if not valid_win(win) then return end
  vim.api.nvim_win_call(win, function()
    local last = vim.fn.line("$")
    local n = math.max(1, math.min(line, last))
    pcall(vim.api.nvim_win_set_cursor, win, { n, 0 })
  end)
end

--- 在 guard 保护下执行，阻断回调重入
local function guarded(fn)
  if state.guard then return end
  state.guard = true
  local ok, err = pcall(fn)
  state.guard = false
  if not ok then
    vim.schedule(function()
      vim.notify("[md-preview] 滚动同步出错: " .. tostring(err), vim.log.levels.DEBUG)
    end)
  end
end

--- 取窗口中当前参考行
local function ref_line(win, mode)
  if not valid_win(win) then return nil end
  return vim.api.nvim_win_call(win, function()
    if mode == "cursor" then
      return vim.fn.line(".")
    end
    return vim.fn.line("w0") -- 窗口顶部行
  end)
end

--- 源 → 预览
local function sync_to_preview()
  if not state.opts.scroll_sync then return end
  if not (valid_win(state.src_win) and valid_win(state.prev_win)) then return end
  local src = ref_line(state.src_win, state.opts.sync_mode)
  if not src then return end
  local out = M.map_src_to_out(src)
  if not out then return end
  guarded(function()
    if state.opts.sync_mode == "cursor" then
      set_cursor_line(state.prev_win, out)
    else
      set_topline(state.prev_win, out)
    end
  end)
end

--- 预览 → 源
local function sync_to_source()
  if not state.opts.scroll_sync_reverse then return end
  if not (valid_win(state.src_win) and valid_win(state.prev_win)) then return end
  local out = ref_line(state.prev_win, state.opts.sync_mode)
  if not out then return end
  local src = M.map_out_to_src(out)
  if not src then return end
  guarded(function()
    if state.opts.sync_mode == "cursor" then
      set_cursor_line(state.src_win, src)
    else
      set_topline(state.src_win, src)
    end
  end)
end

--- 查找源行对应的渲染行（缺失时取最近的前一个映射）
function M.map_src_to_out(src)
  if state.s2o[src] then return state.s2o[src] end
  local best = nil
  for s, o in pairs(state.s2o) do
    if s <= src and (best == nil or s > best) then best = s end
  end
  return best and state.s2o[best] or nil
end

--- 查找渲染行对应的源行
function M.map_out_to_src(out)
  if state.o2s[out] then return state.o2s[out] end
  local best = nil
  for o, s in pairs(state.o2s) do
    if o <= out and (best == nil or o > best) then best = o end
  end
  return best and state.o2s[best] or nil
end

--- 更新映射（每次重渲染后调用）
function M.update_maps(s2o, o2s)
  state.s2o = s2o or {}
  state.o2s = o2s or {}
end

--- 挂载同步
--- @param src_win number 源窗口 id
--- @param prev_win number 预览窗口 id
--- @param s2o table
--- @param o2s table
--- @param opts table 配置
function M.attach(src_win, prev_win, s2o, o2s, opts)
  M.detach()
  state.src_win = src_win
  state.prev_win = prev_win
  state.s2o = s2o or {}
  state.o2s = o2s or {}
  state.opts = opts or {}
  state.enabled = true

  state.augroup = vim.api.nvim_create_augroup("MdPreviewSync", { clear = true })

  local events = { "CursorMoved", "WinScrolled" }
  vim.api.nvim_create_autocmd(events, {
    group = state.augroup,
    buffer = vim.api.nvim_win_get_buf(src_win),
    callback = function()
      if not state.enabled then return end
      -- 只在事件来自源窗口时同步
      if vim.api.nvim_get_current_win() ~= state.src_win then return end
      sync_to_preview()
    end,
  })

  vim.api.nvim_create_autocmd(events, {
    group = state.augroup,
    buffer = vim.api.nvim_win_get_buf(prev_win),
    callback = function()
      if not state.enabled then return end
      if vim.api.nvim_get_current_win() ~= state.prev_win then return end
      sync_to_source()
    end,
  })
end

--- 卸载同步
function M.detach()
  state.enabled = false
  if state.augroup then
    pcall(vim.api.nvim_clear_autocmds, { group = state.augroup })
    state.augroup = nil
  end
  state.src_win = nil
  state.prev_win = nil
end

--- 暂停/恢复（重渲染期间暂停可避免抖动）
function M.pause() state.enabled = false end
function M.resume() state.enabled = true end

function M.is_attached()
  return state.enabled
end

return M
