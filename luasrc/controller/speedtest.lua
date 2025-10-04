module("luci.controller.speedtest", package.seeall)

local http  = require "luci.http"
local util  = require "luci.util"
local uci   = require "luci.model.uci".cursor()
local fs    = require "nixio.fs"
local jsonc = require "luci.jsonc"

function index()
    if not fs.access("/etc/config/speedtest") then return end
    -- Menu daje JSON (root/usr/share/luci/menu.d). Tu tylko API:
    entry({"admin","network","speedtest","api","list_servers"}, call("api_list_servers")).leaf = true
    entry({"admin","network","speedtest","api","run"},          call("api_run")).leaf = true
    entry({"admin","network","speedtest","api","detect"},       call("api_detect")).leaf = true
end

local function which(cmd)
    local p = util.exec("command -v " .. util.shellquote(cmd)) or ""
    p = p:gsub("\n$", "")
    if p == "" then return nil end
    return p
end

local function cfg()
    return {
        backend   = uci:get("speedtest","general","backend") or "speedtestcpp",
        server_id = uci:get("speedtest","general","server_id") or "",
        timeout   = tonumber(uci:get("speedtest","general","timeout") or 60),
        bin = {
            ookla        = uci:get("speedtest","general","bin_ookla")        or "speedtest",
            librespeed   = uci:get("speedtest","general","bin_librespeed")   or "librespeed-cli",
            speedtestcpp = uci:get("speedtest","general","bin_speedtestcpp") or "speedtestpp",
        }
    }
end

local function json(data)
    http.prepare_content("application/json")
    http.write_json(data)
end

function api_detect()
    local c = cfg()
    json({
        backend = c.backend,
        bins = {
            ookla        = which(c.bin.ookla),
            librespeed   = which(c.bin.librespeed),
            speedtestcpp = which(c.bin.speedtestcpp)
        }
    })
end

-- Parsowanie tekstowej listy LibreSpeed:
-- "74: Poznan, Poland (INEA) (https://...)" "[Sponsor: ...]"
local function parse_librespeed_list(raw)
    local servers = {}
    for line in (raw or ""):gmatch("[^\r\n]+") do
        local id, rest = line:match("^%s*(%d+)%s*:%s*(.+)$")
        if id then
            local first_paren = rest:find("%(")
            local location = rest
            if first_paren then
                location = rest:sub(1, first_paren - 1):gsub("%s+$","")
            end
            local sponsor = rest:match("%[Sponsor:%s*([^%@%]]+)")
            if not sponsor then
                sponsor = rest:match("%(([^)%s][^)]+)%)") -- pierwszy nawias: zwykle provider
            end
            local url = rest:match("%((https?://[^)]+)%)")
            local name = sponsor or url or location
            servers[#servers+1] = {
                id       = id,
                name     = name or "",
                sponsor  = sponsor or "",
                location = location or "",
                url      = url
            }
        end
    end
    return servers
end

function api_list_servers()
    local c = cfg()
    local b = http.formvalue("backend") or c.backend

    if b == "ookla" then
        local bin = which(c.bin.ookla)
        if not bin then return json({ok=false, error="Ookla CLI not found"}) end
        local cmd = string.format("%s -L --format=json 2>&1", util.shellquote(bin))
        local raw = util.exec(cmd) or ""
        if raw == "" then return json({ok=false, error="empty_result"}) end

        local servers = {}
        local obj = jsonc.parse(raw)
        if obj and (obj.servers or obj) then
            local list = obj.servers or obj or {}
            for _, s in ipairs(list) do
                servers[#servers+1] = {
                    id       = tostring(s.id or s.ID or s.server or ""),
                    name     = s.name or s.Name or s.host or "",
                    sponsor  = s.sponsor or s.Sponsor or s.owner or "",
                    location = s.location or s.Location or s.city or "",
                    distance = s.distance or s.Distance
                }
            end
            return json({ok=true, backend=b, servers=servers})
        else
            return json({ok=false, error="json_parse_failed", raw=raw})
        end

    elseif b == "librespeed" then
        local bin = which(c.bin.librespeed)
        if not bin then return json({ok=false, error="librespeed-cli not found"}) end
        -- Twoja wersja wypisuje tekst – nie używamy --json przy listowaniu.
        local cmd = string.format("%s --list 2>&1", util.shellquote(bin))
        local raw = util.exec(cmd) or ""
        if raw == "" then return json({ok=false, error="empty_result"}) end
        local servers = parse_librespeed_list(raw)
        return json({ok=true, backend=b, servers=servers})

    else
        -- speedtestcpp: zwykle brak listy – zwracamy pustą
        return json({ok=true, backend=b, servers={}})
    end
end

function api_run()
    local c      = cfg()
    local b      = http.formvalue("backend") or c.backend
    local sid    = http.formvalue("server_id") or c.server_id or ""
    local to     = tonumber(http.formvalue("timeout")) or c.timeout or 60
    local cmd, bin

    if b == "ookla" then
        bin = which(c.bin.ookla)
        if not bin then return json({ok=false, error="Ookla CLI not found"}) end
        local args = { "--format=json", string.format("--timeout=%d", to) }
        if sid ~= "" then args[#args+1] = "-s " .. sid end
        cmd = util.shellquote(bin) .. " " .. table.concat(args, " ") .. " 2>&1"

    elseif b == "librespeed" then
        bin = which(c.bin.librespeed)
        if not bin then return json({ok=false, error="librespeed-cli not found"}) end
        -- Spróbujemy JSON podczas testu (jeśli nie wspiera, UI i tak pokaże surowy tekst):
        local args = {}
        if sid ~= "" then args[#args+1] = "--server " .. sid end
        args[#args+1] = "--json"
        cmd = util.shellquote(bin) .. " " .. table.concat(args, " ") .. " 2>&1"

    else -- speedtestcpp
        bin = which(c.bin.speedtestcpp) or which("speedtestcpp") or which("speedtest")
        if not bin then return json({ok=false, error="speedtestcpp not found"}) end
        local args = { "--json" }
        cmd = util.shellquote(bin) .. " " .. table.concat(args, " ") .. " 2>&1"
    end

    local raw = util.exec(cmd) or ""
    if raw == "" then return json({ok=false, error="empty_result"}) end
    return json({ok=true, backend=b, raw=raw})
end
