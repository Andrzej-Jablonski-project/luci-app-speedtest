module("luci.controller.speedtest", package.seeall)

local http = require "luci.http"
local util = require "luci.util"
local uci  = require "luci.model.uci".cursor()
local fs   = require "nixio.fs"

function index()
    if not fs.access("/etc/config/speedtest") then return end
    -- Menu zapewnia JSON (root/usr/share/luci/menu.d). Tu tylko API:
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
    local c = {
        backend = uci:get("speedtest","general","backend") or "speedtestcpp",
        server_id = uci:get("speedtest","general","server_id") or "",
        timeout   = tonumber(uci:get("speedtest","general","timeout") or 60),
        bin = {
            ookla = uci:get("speedtest","general","bin_ookla") or "speedtest",
            librespeed = uci:get("speedtest","general","bin_librespeed") or "librespeed-cli",
            speedtestcpp = uci:get("speedtest","general","bin_speedtestcpp") or "speedtestpp"
        }
    }
    return c
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
            ookla = which(c.bin.ookla),
            librespeed = which(c.bin.librespeed),
            speedtestcpp = which(c.bin.speedtestcpp)
        }
    })
end

function api_list_servers()
    local c = cfg()
    local b = http.formvalue("backend") or c.backend

    local cmd
    if b == "ookla" then
        local bin = which(c.bin.ookla)
        if not bin then return json({ok=false, error="Ookla CLI not found"}) end
        cmd = string.format("%s -L --format=json 2>/dev/null", util.shellquote(bin))
    elseif b == "librespeed" then
        local bin = which(c.bin.librespeed)
        if not bin then return json({ok=false, error="librespeed-cli not found"}) end
        cmd = string.format("%s --list --json 2>/dev/null", util.shellquote(bin))
    else
        return json({ok=true, backend=b, servers={}})
    end

    local raw = util.exec(cmd) or ""
    if raw == "" then return json({ok=false, error="empty_result"}) end

    local servers = {}
    local dk = require("dkjson")
    local obj, _, err = dk.decode(raw)
    if not obj then return json({ok=false, error="json_decode_failed:"..tostring(err)}) end

    if b == "ookla" then
        local list = obj.servers or obj or {}
        for _,s in ipairs(list) do
            servers[#servers+1] = {
                id = tostring(s.id or s.ID or s.server or ""),
                name = s.name or s.Name or s.host or "",
                sponsor = s.sponsor or s.Sponsor or s.owner or "",
                location = s.location or s.Location or s.city or "",
                distance = s.distance or s.Distance or nil
            }
        end
    elseif b == "librespeed" then
        local list = obj.servers or obj or {}
        for _,s in ipairs(list) do
            servers[#servers+1] = {
                id = tostring(s.id or s.ID or s.server or ""),
                name = s.name or s.name_friendly or s.host or "",
                sponsor = s.sponsor or s.owner or "",
                location = s.location or s.city or "",
                distance = s.distance or nil
            }
        end
    end

    json({ok=true, backend=b, servers=servers})
end

function api_run()
    local c = cfg()
    local b = http.formvalue("backend") or c.backend
    local sid = http.formvalue("server_id") or c.server_id or ""
    local timeout = tonumber(http.formvalue("timeout")) or c.timeout or 60

    local cmd, bin
    if b == "ookla" then
        bin = which(c.bin.ookla)
        if not bin then return json({ok=false, error="Ookla CLI not found"}) end
        local args = { "--format=json", string.format("--timeout=%d", timeout) }
        if sid ~= "" then args[#args+1] = "-s "..sid end
        cmd = util.shellquote(bin) .. " " .. table.concat(args, " ") .. " 2>/dev/null"
    elseif b == "librespeed" then
        bin = which(c.bin.librespeed)
        if not bin then return json({ok=false, error="librespeed-cli not found"}) end
        local args = { "--json" }
        if sid ~= "" then args[#args+1] = "--server "..sid end
        cmd = util.shellquote(bin) .. " " .. table.concat(args, " ") .. " 2>/dev/null"
    else
        bin = which(c.bin.speedtestcpp) or which("speedtestcpp") or which("speedtest")
        if not bin then return json({ok=false, error="speedtestcpp not found"}) end
        local args = { "--json" }
        cmd = util.shellquote(bin) .. " " .. table.concat(args, " ") .. " 2>/dev/null"
    end

    local raw = util.exec(cmd) or ""
    if raw == "" then return json({ok=false, error="empty_result"}) end

    json({ok=true, backend=b, raw=raw})
end
