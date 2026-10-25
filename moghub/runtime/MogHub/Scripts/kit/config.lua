-- ini files: read as key = value (sections only group lines for people; keys are unique per file) and written back
-- one key at a time, keeping comments, order and layout. Also the kit's own config.ini.
local M = {}
local kit

function M.read(path)
    local values = {}
    local text = kit.readFile(path)
    if not text then return values, nil end
    for line in text:gmatch("[^\r\n]+") do
        local k, v = line:match("^%s*([%w_%.]+)%s*=%s*(.-)%s*$")
        if k and not line:match("^%s*;") then values[k] = v end
    end
    return values, text
end

-- sets `key` in `section` (created at the end if missing); the first `key =` line anywhere wins
function M.write(path, key, value, section)
    local text = kit.readFile(path) or ""
    local nl = text:find("\r\n", 1, true) and "\r\n" or "\n"
    local lines = {}
    for line in (text .. nl):gmatch("(.-)\r?\n") do lines[#lines + 1] = line end
    if lines[#lines] == "" then lines[#lines] = nil end
    local entry = key .. " = " .. tostring(value)
    for i, line in ipairs(lines) do
        if line:match("^%s*" .. key:gsub("%p", "%%%0") .. "%s*=") then
            lines[i] = entry
            return kit.writeFile(path, table.concat(lines, nl) .. nl)
        end
    end
    local at = #lines + 1
    if section then
        local start
        for i, line in ipairs(lines) do
            if line:match("^%s*%[(.-)%]%s*$") == section then start = i; break end
        end
        if start then
            -- after the section's last line that isn't blank
            at = start + 1
            for i = start + 1, #lines do
                if lines[i]:match("^%s*%[") then break end
                if lines[i]:match("%S") then at = i + 1 end
            end
        else
            if #lines > 0 and lines[#lines] ~= "" then lines[#lines + 1] = "" end
            lines[#lines + 1] = "[" .. section .. "]"
            at = #lines + 1
        end
    end
    table.insert(lines, at, entry)
    return kit.writeFile(path, table.concat(lines, nl) .. nl)
end

function M.bool(text, default)
    if text == nil or text == "" then return default end
    text = tostring(text):lower()
    return text == "1" or text == "true" or text == "on" or text == "yes"
end

-- the kit's own settings (Mods/MogHub/config.ini)
local kitValues = {}
function M.init(k)
    kit = k
    M.kitPath = kit.dir .. "/config.ini"
    kitValues = M.read(M.kitPath)
end
function M.kitValue(key, default)
    local v = kitValues[key]
    if v == nil or v == "" then return default end
    return v
end
function M.kitBool(key, default) return M.bool(kitValues[key], default) end
function M.pluginEnabled(folder) return M.bool(kitValues[folder], true) end
function M.setPluginEnabled(folder, on)
    kitValues[folder] = on and "1" or "0"
    M.write(M.kitPath, folder, on and 1 or 0, "Plugins")
end

return M
