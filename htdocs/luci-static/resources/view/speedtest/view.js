'use strict';
'require baseclass';
'require view';
'require form';
'require uci';
'require ui';

function apiUrl(path){ return L.url('admin/network/speedtest/api', path); }
function apiGET(path, params){
  var url = apiUrl(path);
  if (params)
    url += '?' + Object.keys(params).map(k => encodeURIComponent(k)+'='+encodeURIComponent(params[k])).join('&');
  return fetch(url, { method:'GET', credentials:'include' }).then(function(r){
    if(!r.ok) throw new Error('HTTP '+r.status);
    return r.json();
  });
}

// --- helpers (anonimowa sekcja CBI) ---
function qByNameOrId(suffix){
  // trafiaj po name *i* po id (LuCI używa obu wariantów)
  var sel = 'input[name^="cbid.speedtest."][name$=".'+suffix+'"],'
          + 'textarea[name^="cbid.speedtest."][name$=".'+suffix+'"],'
          + 'select[name^="cbid.speedtest."][name$=".'+suffix+'"],'
          + 'input[id^="widget.cbid.speedtest."][id$=".'+suffix+'"],'
          + 'textarea[id^="widget.cbid.speedtest."][id$=".'+suffix+'"],'
          + 'select[id^="widget.cbid.speedtest."][id$=".'+suffix+'"]';
  return document.querySelector(sel);
}
function getSel(suffix, fallback){
  var el = qByNameOrId(suffix);
  return el && el.value != null && el.value !== '' ? el.value : (fallback || '');
}
function setSel(suffix, value){
  var el = qByNameOrId(suffix);
  if (el) {
    el.value = String(value == null ? '' : value);
    try { el.dispatchEvent(new Event('input',  {bubbles:true})); } catch(e){}
    try { el.dispatchEvent(new Event('change', {bubbles:true})); } catch(e){}
    return true;
  }
  return false;
}

return view.extend({
  load: function(){
    return Promise.all([
      L.resolveDefault(apiGET('detect'), {}),
      uci.load('speedtest')
    ]);
  },

  render: function(res){
    var detect = res[0] || {};
    var m = new form.Map('speedtest', _('Speedtest'),
      _('Test prędkości łącza z wyborem silnika i serwera.'));

    var s = m.section(form.TypedSection, 'speedtest', _('Ustawienia'));
    s.addremove = false;
    s.anonymous = true;

    var backend = s.option(form.ListValue, 'backend', _('Silnik testu'));
    backend.value('speedtestcpp','speedtestcpp (nieoficjalny)');
    backend.value('ookla','Ookla Speedtest CLI (oficjalny)');
    backend.value('librespeed','LibreSpeed CLI (open-source)');
    backend.default = 'speedtestcpp';

    var sid   = s.option(form.Value, 'server_id',   _('ID serwera'));
    sid.placeholder = _('wybierz z listy poniżej lub zostaw puste');

    var sname = s.option(form.Value, 'server_name', _('Opis serwera (etykieta)'));

    var timeout = s.option(form.Value, 'timeout', _('Timeout (s)'));
    timeout.datatype = 'uinteger';
    timeout.default  = 60;

    // --- LISTA SERWERÓW ---
    var listBtn = s.option(form.Button, '_list', _('Pobierz listę serwerów'));
    listBtn.inputstyle = 'action';
    listBtn.onclick = L.bind(function(){
      var b = getSel('backend', detect.backend || 'speedtestcpp');
      ui.addNotification(null, E('p', _('Pobieranie listy serwerów…')));
      return apiGET('list_servers', { backend:b }).then(function(r){
        if(!r || !r.ok){
          ui.addNotification(_('Błąd'), E('p', _(r && r.error || 'Brak odpowiedzi')));
          return;
        }
        var list = Array.isArray(r.servers) ? r.servers
                 : (r.servers && typeof r.servers === 'object') ? Object.values(r.servers)
                 : [];

        var items = list.map(function(srv){
          var id    = String(srv.id || '');
          var label = '['+id+'] '+(srv.sponsor||srv.name||'')+(srv.location?(' – '+srv.location):'');
          return E('li', {}, E('button', {
              'class':'btn',
              'click': function(){
                // wpisz do pól (DOM) + zapisz do UCI, żeby było trwale
                setSel('server_id',   id);
                setSel('server_name', label);
                // szybki save – bez reloadu całej strony
                m.save().finally(function(){
                  ui.addNotification(_('Wybrano serwer'), E('code', {}, label));
                  ui.hideModal();
                });
              }
          }, label));
        });

        if (!items.length)
          items = [E('li', {}, E('em', {}, _('Brak serwerów (sprawdź binarkę backendu).')))];

        ui.showModal(_('Serwery ('+(r.backend || b)+')'), [
          E('div', {}, [
            E('p', {}, _('Kliknij, aby wybrać serwer:')),
            E('ul', { 'class':'cbi-section' }, items)
          ]),
          E('div', { 'class':'right' }, [
            E('button', { 'class':'btn', 'click': ui.hideModal }, _('Zamknij'))
          ])
        ]);
      }).catch(function(e){
        ui.addNotification(_('Błąd'), E('p', e.message || String(e)));
      });
    }, this);

    // --- RUN ---
    var runBtn = s.option(form.Button, '_run', _('Uruchom test teraz'));
    runBtn.inputstyle = 'apply';
    runBtn.onclick = L.bind(function(){
      return m.save().then(function(){
        var b  = getSel('backend',  detect.backend || 'speedtestcpp');
        var id = getSel('server_id','');
        var to = getSel('timeout',  '60');

        ui.addNotification(null, E('p', _('Trwa test…')));
        return apiGET('run', { backend:b, server_id:id, timeout:to }).then(function(r){
          if(!r || !r.ok){
            ui.addNotification(_('Błąd'), E('p', _(r && r.error || 'Brak odpowiedzi')));
            return;
          }
          var text = (typeof r.raw === 'string') ? r.raw : JSON.stringify(r.raw, null, 2);
          var pre  = E('pre', { 'style':'max-height:50vh; overflow:auto' }, [ text ]);
          ui.showModal(_('Wynik (backend: '+(r.backend || b)+')'), [
            pre,
            E('div', { 'class':'right' }, [
              E('button', { 'class':'btn', 'click': ui.hideModal }, _('Zamknij'))
            ])
          ]);
        }).catch(function(e){
          ui.addNotification(_('Błąd'), E('p', e.message || String(e)));
        });
      });
    }, this);

    return m.render();
  }
});
