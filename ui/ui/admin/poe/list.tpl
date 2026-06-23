{include file="sections/header.tpl"}
<!-- PoE management -->
<div class="row">
    <div class="col-sm-12">
        <div class="panel panel-hovered mb20 panel-primary">
            <div class="panel-heading">
                {Lang::T('PoE Management')}
                <div class="btn-group pull-right">
                    <button type="button" id="poe-refresh" class="btn btn-primary btn-xs">
                        <span class="glyphicon glyphicon-refresh"></span> {Lang::T('Refresh')}
                    </button>
                </div>
            </div>
            <div class="panel-body">
                <div class="row" style="margin-bottom:10px">
                    <div class="col-md-4">
                        <select id="poe-router" class="form-control input-sm">
                            <option value="">{Lang::T('Select a router')}...</option>
                            {foreach $routers as $r}
                                <option value="{$r['name']}">{$r['name']}</option>
                            {/foreach}
                        </select>
                    </div>
                    <div class="col-md-8 text-right">
                        <small class="text-muted" id="poe-updated"></small>
                    </div>
                </div>
                <div id="poe-errors"></div>
                <div class="table-responsive">
                    <table class="table table-bordered table-striped table-condensed">
                        <thead>
                            <tr>
                                <th>{Lang::T('Port')}</th>
                                <th>PoE-out</th>
                                <th>{Lang::T('Status')}</th>
                                <th>{Lang::T('Voltage')}</th>
                                <th>{Lang::T('Current')}</th>
                                <th>{Lang::T('Power')}</th>
                                <th>{Lang::T('Manage')}</th>
                            </tr>
                        </thead>
                        <tbody id="poe-body">
                            <tr><td colspan="7" class="text-center text-muted">{Lang::T('Select a router')}...</td></tr>
                        </tbody>
                    </table>
                </div>
                <div class="bs-callout bs-callout-info">
                    <p><b>{Lang::T('Power-cycle')}</b> {Lang::T('briefly cuts PoE power to reboot the connected device (CPE/AP). Requires RouterOS 6.45 or newer.')}</p>
                </div>
            </div>
        </div>
    </div>
</div>

<script>
    window.POE_CFG = {
        dataUrl: "{Text::url('poe/data')}",
        statusUrl: "{Text::url('poe/status')}",
        setUrl: "{Text::url('poe/set')}",
        cycleUrl: "{Text::url('poe/cycle')}",
        t: {
            selectRouter: "{Lang::T('Select a router')|escape:'javascript'}",
            none: "{Lang::T('No PoE-capable ports found')|escape:'javascript'}",
            off: "{Lang::T('Off')|escape:'javascript'}",
            auto: "{Lang::T('Auto')|escape:'javascript'}",
            forced: "{Lang::T('Forced')|escape:'javascript'}",
            reboot: "{Lang::T('Reboot')|escape:'javascript'}",
            confirmReboot: "{Lang::T('Power-cycle this port to reboot the connected device')|escape:'javascript'}",
            updated: "{Lang::T('Updated')|escape:'javascript'}",
            failed: "{Lang::T('Failed to load')|escape:'javascript'}"
        }
    };
</script>
{literal}
<script>
(function () {
    var cfg = window.POE_CFG;
    var metaTok = document.querySelector('meta[name="csrf-token"]');
    var csrfToken = metaTok ? metaTok.getAttribute('content') : '';

    function esc(s) {
        return (s == null ? '' : String(s)).replace(/[&<>"']/g, function (c) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
        });
    }
    function curRouter() { return document.getElementById('poe-router').value; }

    function modeBtn(port, state, label) {
        var active = (port['poe-out'] === state) ? ' btn-primary active' : ' btn-default';
        return '<button class="btn btn-xs poe-set' + active + '" data-port="' + esc(port['.id']) +
            '" data-state="' + state + '">' + esc(label) + '</button>';
    }
    function statusLabel(s) {
        if (!s) return '<span class="text-muted">-</span>';
        var cls = 'label-default';
        if (s.indexOf('powered') >= 0 || s === 'powered-on') cls = 'label-success';
        else if (s.indexOf('short') >= 0 || s.indexOf('over') >= 0 || s.indexOf('fault') >= 0) cls = 'label-danger';
        else if (s === 'waiting-for-load') cls = 'label-warning';
        return '<span class="label ' + cls + '">' + esc(s) + '</span>';
    }
    function render(ports) {
        var body = document.getElementById('poe-body');
        if (!ports || !ports.length) {
            body.innerHTML = '<tr><td colspan="7" class="text-center text-muted">' + esc(cfg.t.none) + '</td></tr>';
            return;
        }
        body.innerHTML = ports.map(function (p) {
            var nm = esc(p.name);
            return '<tr data-name="' + nm + '">' +
                '<td><b>' + nm + '</b>' + (p.comment ? ' <small class="text-muted">' + esc(p.comment) + '</small>' : '') + '</td>' +
                '<td>' + esc(p['poe-out'] || '-') + '</td>' +
                '<td class="poe-st">' + statusLabel('') + '</td>' +
                '<td class="poe-v">-</td>' +
                '<td class="poe-c">-</td>' +
                '<td class="poe-p">-</td>' +
                '<td><div class="btn-group" role="group">' +
                modeBtn(p, 'off', cfg.t.off) +
                modeBtn(p, 'auto-on', cfg.t.auto) +
                modeBtn(p, 'forced-on', cfg.t.forced) +
                '</div> <button class="btn btn-xs btn-warning poe-cycle" data-port="' + esc(p['.id']) + '">' +
                '<i class="glyphicon glyphicon-refresh"></i> ' + esc(cfg.t.reboot) + '</button></td>' +
                '</tr>';
        }).join('');
        loadStatus();
    }
    function loadStatus() {
        var router = curRouter();
        if (!router) { return; }
        fetch(cfg.statusUrl + '&router=' + encodeURIComponent(router), { headers: { 'X-CSRF-Token': csrfToken } })
            .then(function (r) { return r.json(); })
            .then(function (d) {
                if (!d || !d.success || !d.status) { return; }
                Object.keys(d.status).forEach(function (name) {
                    var st = d.status[name] || {};
                    var sel = (window.CSS && CSS.escape) ? CSS.escape(name) : name.replace(/"/g, '\\"');
                    var row = document.querySelector('#poe-body tr[data-name="' + sel + '"]');
                    if (!row) { return; }
                    var stCell = row.querySelector('.poe-st');
                    if (stCell) { stCell.innerHTML = statusLabel(st['poe-out-status']); }
                    var v = row.querySelector('.poe-v'); if (v) { v.textContent = st['poe-out-voltage'] ? st['poe-out-voltage'] + ' V' : '-'; }
                    var c = row.querySelector('.poe-c'); if (c) { c.textContent = st['poe-out-current'] ? st['poe-out-current'] + ' mA' : '-'; }
                    var pw = row.querySelector('.poe-p'); if (pw) { pw.textContent = st['poe-out-power'] ? st['poe-out-power'] + ' W' : '-'; }
                });
                if (d.updated) { document.getElementById('poe-updated').textContent = cfg.t.updated + ': ' + d.updated; }
            })
            .catch(function () { /* live readings are optional */ });
    }
    function load() {
        var router = curRouter();
        var body = document.getElementById('poe-body');
        if (!router) {
            body.innerHTML = '<tr><td colspan="7" class="text-center text-muted">' + esc(cfg.t.selectRouter) + '...</td></tr>';
            return;
        }
        body.innerHTML = '<tr><td colspan="7" class="text-center text-muted">...</td></tr>';
        fetch(cfg.dataUrl + '&router=' + encodeURIComponent(router), { headers: { 'X-CSRF-Token': csrfToken } })
            .then(function (r) { return r.json(); })
            .then(function (d) {
                document.getElementById('poe-updated').textContent = d.updated ? (cfg.t.updated + ': ' + d.updated) : '';
                var errBox = document.getElementById('poe-errors');
                if (!d.success) {
                    errBox.innerHTML = '<div class="alert alert-warning" style="padding:6px 10px">' + esc(d.message || cfg.t.failed) + '</div>';
                    render([]);
                    return;
                }
                errBox.innerHTML = '';
                render(d.ports);
            })
            .catch(function () {
                body.innerHTML = '<tr><td colspan="7" class="text-center text-danger">' + esc(cfg.t.failed) + '</td></tr>';
            });
    }
    function post(url, params, cb) {
        var body = 'csrf_token=' + encodeURIComponent(csrfToken);
        for (var k in params) { body += '&' + k + '=' + encodeURIComponent(params[k]); }
        fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'X-CSRF-Token': csrfToken },
            body: body
        }).then(function (r) { return r.json(); }).then(cb).catch(function () { cb({ success: false }); });
    }
    document.getElementById('poe-refresh').addEventListener('click', load);
    document.getElementById('poe-router').addEventListener('change', load);
    document.getElementById('poe-body').addEventListener('click', function (e) {
        var t = e.target.closest ? e.target.closest('button') : null;
        if (!t) return;
        if (t.classList.contains('poe-set')) {
            t.disabled = true;
            post(cfg.setUrl, { router: curRouter(), port_id: t.getAttribute('data-port'), state: t.getAttribute('data-state') }, function () { load(); });
        } else if (t.classList.contains('poe-cycle')) {
            if (!confirm(cfg.t.confirmReboot + '?')) return;
            t.disabled = true;
            post(cfg.cycleUrl, { router: curRouter(), port_id: t.getAttribute('data-port'), duration: 5 }, function () { setTimeout(load, 6000); });
        }
    });
})();
</script>
{/literal}
{include file="sections/footer.tpl"}
