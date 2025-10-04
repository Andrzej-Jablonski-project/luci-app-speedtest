#!/usr/bin/env bash
set -euo pipefail

# --- Ścieżki ---
mkdir -p root/etc/config
mkdir -p root/usr/share/luci/menu.d
mkdir -p luasrc/controller
mkdir -p luasrc/view/speedtest
mkdir -p htdocs/luci-static/resources/view/speedtest

# --- 1) UCI config ---
cat > root/etc/config/speedtest <<'EOF'
config speedtest 'general'
        option backend 'speedtestcpp'   # ookla | librespeed | speedtestcpp
        option server_id ''             # np. 12345 (ID serwera z listy)
        option server_name ''           # pole opisowe (UI)
        option timeout '60'             # maksymalny czas testu (s)
        option bin_ookla 'speedtest'    # ścieżka do Ookla CLI
        option bin_librespeed 'librespeed-cli' # ścieżka do LibreSpeed CLI
        option bin_speedtestcpp 'speedtestpp'  # nazwa/ścieżka do speedtestcpp
EOF

# --- 2) Menu JSON ---
cat > root/usr/share/luci/menu.d/luci-app-speedtest.json <<'EOF'
{
  "admin/network/speedtest": {
    "title": "Speedtest",
    "order": 60,
    "action": {
      "type": "view",
      "path": "speedtest/view"
    }
  }
}
EOF

# --- 3) Widok HTML ---
cat > luasrc/view/speedtest/view.htm <<'EOF'
<%+header%>
<h2><%:Speedtest%></h2>
<div id="view"></div>
<script type="module" src="<%=resource%>/view/speedtest/view.js"></script>
<%+footer%>
EOF

# --- 4) Kontroler (API) ---
cat > luasrc/controller/speedtest.lua <<'EOF'
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
EOF

# --- 5) Widok JS (bez 'fs', z 'uci') ---
cat > htdocs/luci-static/resources/view/speedtest/view.js <<'EOF'
'use strict';
'require baseclass';
'require view';
'require form';
'require uci';
var ui = require('ui');

function apiUrl(path) {
    return L.url('admin/network/speedtest/api', path);
}

function apiGET(path, params) {
    var url = apiUrl(path);
    if (params) url += '?' + Object.keys(params).map(k => encodeURIComponent(k) + '=' + encodeURIComponent(params[k])).join('&');
    return L.fetch(url, { method: 'GET', credentials: 'include' }).then(r => r.json());
}

return view.extend({
    load: function() {
        return Promise.all([
            L.resolveDefault(apiGET('detect'), {}),
            uci.load('speedtest')
        ]);
    },

    render: function(res) {
        var detect = res[0] || {};
        var m = new form.Map('speedtest', _('Speedtest'), _('Test prędkości łącza z wyborem silnika i serwera.'));

        var s = m.section(form.TypedSection, 'speedtest', _('Ustawienia'));
        s.addremove = false;
        s.anonymous = true;

        var backend = s.option(form.ListValue, 'backend', _('Silnik testu'));
        backend.value('speedtestcpp', 'speedtestcpp (nieoficjalny)');
        backend.value('ookla', 'Ookla Speedtest CLI (oficjalny)');
        backend.value('librespeed', 'LibreSpeed CLI (open-source)');
        backend.default = 'speedtestcpp';

        var sid = s.option(form.Value, 'server_id', _('ID serwera'));
        sid.placeholder = _('wybierz z listy poniżej lub zostaw puste');

        var sname = s.option(form.Value, 'server_name', _('Opis serwera (etykieta)'));

        var timeout = s.option(form.Value, 'timeout', _('Timeout (s)'));
        timeout.datatype = 'uinteger';
        timeout.default = 60;

        var listBtn = s.option(form.Button, '_list', _('Pobierz listę serwerów'));
        listBtn.inputstyle = 'action';
        listBtn.onclick = L.bind(function(ev) {
            var b = backend.formvalue('speedtest', 'backend') || 'speedtestcpp';
            ui.addNotification(null, E('p', _('Pobieranie listy serwerów…')));
            return apiGET('list_servers', { backend: b }).then(function(r) {
                if (!r || !r.ok) {
                    ui.addNotification(_('Błąd'), E('p', _(r && r.error || 'Brak odpowiedzi')));
                    return;
                }
                var list = r.servers || [];
                var body = E('div', {}, [
                    E('p', {}, _('Kliknij, aby wybrać serwer:')),
                    E('ul', { 'class': 'cbi-section' }, list.map(function(srv) {
                        var label = '[' + (srv.id || '?') + '] ' + (srv.sponsor || srv.name || '') + (srv.location ? (' – ' + srv.location) : '');
                        return E('li', {}, E('button', {
                            'class': 'btn',
                            'click': function() {
                                sid.setValue(srv.id);
                                sname.setValue(label);
                                ui.hideModal();
                            }
                        }, label));
                    }))
                ]);
                ui.showModal(_('Serwery (' + (r.backend || '') + ')'), [ body, E('div', { 'class': 'right' }, [ E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Zamknij')) ]) ]);
            });
        }, this);

        var runBtn = s.option(form.Button, '_run', _('Uruchom test teraz'));
        runBtn.inputstyle = 'apply';
        runBtn.onclick = L.bind(function(ev) {
            return m.save().then(function() {
                var b = backend.formvalue('speedtest', 'backend') || 'speedtestcpp';
                var id = sid.formvalue('speedtest', 'server_id') || '';
                var to = timeout.formvalue('speedtest', 'timeout') || '60';
                ui.addNotification(null, E('p', _('Trwa test…')));
                return apiGET('run', { backend: b, server_id: id, timeout: to }).then(function(r) {
                    if (!r || !r.ok) {
                        ui.addNotification(_('Błąd'), E('p', _(r && r.error || 'Brak odpowiedzi')));
                        return;
                    }
                    var pre = E('pre', { 'style': 'max-height:50vh; overflow:auto' }, [ r.raw ]);
                    ui.showModal(_('Wynik (backend: ' + (r.backend || '') + ')'), [ pre, E('div', { 'class': 'right' }, [ E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Zamknij')) ]) ]);
                });
            });
        }, this);

        return m.render();
    }
});
EOF

# --- 6) Makefile: dopnij zależności/deskrypcję idempotentnie ---
# include rules.mk (jeśli brak)
grep -q 'include $(TOPDIR)/rules.mk' Makefile || sed -i '1i include $(TOPDIR)/rules.mk' Makefile
# zależności
if grep -q 'LUCI_DEPENDS:=' Makefile; then
  sed -i -E 's/^(LUCI_DEPENDS:=.*)/\1 +libuci-lua +luci-lib-jsonc +lua-dkjson/' Makefile
else
  printf '\nLUCI_DEPENDS:=+luci-base +luci-compat +libuci-lua +luci-lib-jsonc +lua-dkjson\n' >> Makefile
fi
# tytuł/opis/licencja (jeśli brak)
grep -q '^LUCI_TITLE:=' Makefile || echo 'LUCI_TITLE:=LuCI app: Speedtest (server selection)' >> Makefile
grep -q '^LUCI_DESCRIPTION:=' Makefile || echo 'LUCI_DESCRIPTION:=LuCI interface for internet speed tests with server selection (Ookla/LibreSpeed/speedtestcpp)' >> Makefile
grep -q '^PKG_LICENSE:=' Makefile || echo 'PKG_LICENSE:=Apache-2.0' >> Makefile

echo "OK: pliki utworzone. Teraz: git add -A && git commit && build w SDK."