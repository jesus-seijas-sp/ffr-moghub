-- Development (Debug = 1 in config.ini): a dev_eval.lua dropped in the kit's folder runs once inside the game,
-- with the kit in reach; what it passes to out(...) lands in dev_eval_out.txt. The file is removed when read.
local M = {}

function M.start(kit)
    if not kit.debug then return end
    local EVAL, OUT = kit.dir .. "/dev_eval.lua", kit.dir .. "/dev_eval_out.txt"
    os.remove(EVAL)
    kit.every(500, function()
        local code = kit.readFile(EVAL)
        if not code then return end
        os.remove(EVAL)
        local out = {}
        local env = setmetatable({
            kit = kit,
            out = function(...)
                local parts = {}
                for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
                out[#out + 1] = table.concat(parts, " ")
            end,
        }, { __index = _G })
        local chunk, err = load(code, "dev_eval", "t", env)
        local ok, res = false, err
        if chunk then ok, res = pcall(chunk) end
        if not ok then out[#out + 1] = "ERROR: " .. tostring(res) end
        kit.writeFile(OUT, table.concat(out, "\n") .. "\n")
    end, "dev eval", { loading = true })
end

return M
