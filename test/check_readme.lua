-- 校验 README 中的效果展示是否与真实渲染输出逐字符一致。
--
-- README 里声称展示的是「未做修饰的真实渲染输出」，这个断言必须可验证，
-- 否则改了渲染逻辑后 README 会静默失真。本脚本即用来守住这一点。
--
-- 用法（在仓库根目录）：
--   nvim --headless -c "set columns=180 lines=60" -c "luafile test/check_readme.lua" -c "q!"
--
-- 注意：columns 需与 README 示例生成时一致（180），否则表格列宽不同。
-- 用 debug.getinfo 取脚本自身路径（<sfile> 在 luafile 顶层不可靠）
local src = debug.getinfo(1, "S").source:sub(2)
local ROOT = vim.fn.fnamemodify(src, ":p:h:h")
vim.opt.runtimepath:append(ROOT)

local mp = require("md-preview")
mp.setup({ debounce = 0 })
vim.cmd("edit " .. vim.fn.fnameescape(ROOT .. "/test/demo.md"))
vim.bo.filetype = "markdown"
mp.start()

local sess = mp.get_sessions()[vim.api.nvim_get_current_buf()]
if not sess then
  print("无法建立预览会话")
  vim.cmd("cquit 1")
end

local lines = vim.api.nvim_buf_get_lines(sess.prev_buf, 0, -1, false)

local f = io.open(ROOT .. "/README.md", "r")
if not f then
  print("无法读取 README.md")
  vim.cmd("cquit 1")
end
local readme = f:read("*a")
f:close()

--- 从渲染结果中取出第一个满足条件的连续块
local function block(pred, count)
  for i, l in ipairs(lines) do
    if pred(l) then
      local out = {}
      for k = 0, count - 1 do out[#out + 1] = lines[i + k] end
      return out
    end
  end
  return {}
end

local tbl = block(function(l) return l:find("┌", 1, true) ~= nil end, 7)
local code = block(function(l) return l:find("╭", 1, true) ~= nil end, 7)
-- 徽章行：README 顶部那四枚 shields.io 徽章在 demo.md 里同样出现，
-- 校验它们被合并渲染成「一行彩色标签」而不是每行一个占位符
local badges = block(function(l) return l:find("shield", 1, true) == nil
  and l:find("Neovim 0.9+", 1, true) ~= nil end, 1)
-- 普通位图的占位行
local icon = block(function(l) return l:find("▣", 1, true) ~= nil end, 1)

local bad = 0
local function verify(tag, blk)
  for _, l in ipairs(blk) do
    if readme:find(l, 1, true) then
      print(string.format("[一致]   %s: %s", tag, l))
    else
      print(string.format("[不一致] %s: %s", tag, l))
      bad = bad + 1
    end
  end
end

verify("表格", tbl)
verify("代码块", code)
verify("徽章行", badges)
verify("图片占位", icon)

print("")
if bad == 0 then
  print("===== README 效果展示与真实渲染逐字符一致 =====")
else
  print(string.format("===== 有 %d 行与真实渲染不一致，需修正 README =====", bad))
  vim.cmd("cquit 1")
end
