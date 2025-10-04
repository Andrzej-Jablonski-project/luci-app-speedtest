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
