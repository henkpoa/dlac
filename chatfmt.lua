-- dlac\chatfmt.lua -- the one place that defines dlac's chat look.
-- Header: pale-gold brackets + coral name (deliberately NOT LuaAshitacast's teal,
-- so the two are tellable at a glance). Body: white for messages, green/yellow/red
-- via good/warn/err. M.print is a drop-in print: lines starting "[dlac] " get the
-- colored header, anything else passes through untouched -- modules shadow their
-- `print` with it so no call site needs editing.
local ok, chat = pcall(require, 'chat');
ok = ok and type(chat) == 'table';

local M = {};
local rawprint = print;

M.header = ok and '\30\78[\30\08dlac\30\78]\30\01 ' or '[dlac] ';

-- Inline highlight for commands / filenames (cyan, then back to normal).
function M.hl(s)
    if ok then return '\30\06' .. tostring(s) .. '\30\01'; end
    return tostring(s);
end

function M.msg(s)  rawprint(M.header .. tostring(s)); end
function M.good(s) rawprint(M.header .. (ok and chat.success(tostring(s)) or tostring(s))); end
function M.warn(s) rawprint(M.header .. (ok and chat.warning(tostring(s)) or tostring(s))); end
function M.err(s)  rawprint(M.header .. (ok and chat.error(tostring(s))   or tostring(s))); end

function M.print(s)
    if type(s) == 'string' and s:sub(1, 7) == '[dlac] ' then
        M.msg(s:sub(8));
    else
        rawprint(s);
    end
end

return M;
