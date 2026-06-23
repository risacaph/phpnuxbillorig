{include file="sections/header.tpl"}
<!-- active connections monitor -->
<div class="row">
    <div class="col-sm-12">
        <div class="panel panel-hovered mb20 panel-primary">
            <div class="panel-heading">
                {Lang::T('Active Connections')}
                <div class="btn-group pull-right">
                    <button type="button" id="ac-refresh" class="btn btn-primary btn-xs">
                        <span class="glyphicon glyphicon-refresh"></span> {Lang::T('Refresh')}
                    </button>
                </div>
            </div>
            <div class="panel-body">
                <div class="row" style="margin-bottom:10px">
                    <div class="col-md-3">
                        <select id="ac-router" class="form-control input-sm">
                            <option value="">{Lang::T('All Routers')}</option>
                            {foreach $routers as $r}
                                <option value="{$r['name']}">{$r['name']}</option>
                            {/foreach}
                        </select>
                    </div>
                    <div class="col-md-3">
                        <input type="text" id="ac-search" class="form-control input-sm"
                            placeholder="{Lang::T('Search')} user / IP / MAC...">
                    </div>
                    <div class="col-md-3">
                        <label class="checkbox-inline">
                            <input type="checkbox" id="ac-auto" checked> {Lang::T('Auto-refresh')} (15s)
                        </label>
                    </div>
                    <div class="col-md-3 text-right">
                        <span class="label label-success"><span id="ac-count">0</span> {Lang::T('online')}</span>
                        <br><small class="text-muted" id="ac-updated"></small>
                    </div>
                </div>
                <div id="ac-errors"></div>
                <div class="table-responsive">
                    <table class="table table-bordered table-striped table-condensed">
                        <thead>
                            <tr>
                                <th>{Lang::T('Router')}</th>
                                <th>{Lang::T('Type')}</th>
                                <th>{Lang::T('User')}</th>
                                <th>{Lang::T('IP Address')}</th>
                                <th>MAC</th>
                                <th>{Lang::T('Uptime')}</th>
                                <th>{Lang::T('Download')}</th>
                                <th>{Lang::T('Upload')}</th>
                                <th>{Lang::T('Manage')}</th>
                            </tr>
                        </thead>
                        <tbody id="ac-body">
                            <tr><td colspan="9" class="text-center text-muted">{Lang::T('Loading')}...</td></tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </div>
</div>

<script>
    window.AC_CFG = {
        dataUrl: "{Text::url('monitor/data')}",
        disconnectUrl: "{Text::url('monitor/disconnect')}",
        t: {
            none: "{Lang::T('No active connections')|escape:'javascript'}",
            disconnect: "{Lang::T('Disconnect')|escape:'javascript'}",
            confirm: "{Lang::T('Disconnect this session')|escape:'javascript'}",
            updated: "{Lang::T('Updated')|escape:'javascript'}",
            unreachable: "{Lang::T('Unreachable routers')|escape:'javascript'}",
            failed: "{Lang::T('Failed to load')|escape:'javascript'}"
        }
    };
</script>
{literal}
<script>
(function () {
    var cfg = window.AC_CFG;
    var metaTok = document.querySelector('meta[name="csrf-token"]');
    var csrfToken = metaTok ? metaTok.getAttribute('content') : '';
    var timer = null;
    var lastSessions = [];

    function fmtBytes(b) {
        b = parseInt(b, 10);
        if (isNaN(b) || b <= 0) return '-';
        var u = ['B', 'KB', 'MB', 'GB', 'TB'], i = 0;
        while (b >= 1024 && i < u.length - 1) { b /= 1024; i++; }
        return b.toFixed(i ? 1 : 0) + ' ' + u[i];
    }
    function esc(s) {
        return (s == null ? '' : String(s)).replace(/[&<>"']/g, function (c) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
        });
    }
    function render() {
        var q = (document.getElementById('ac-search').value || '').toLowerCase();
        var body = document.getElementById('ac-body');
        var rows = lastSessions.filter(function (s) {
            if (!q) return true;
            return ((s.user || '') + ' ' + (s.address || '') + ' ' + (s.mac || '')).toLowerCase().indexOf(q) >= 0;
        });
        if (!rows.length) {
            body.innerHTML = '<tr><td colspan="9" class="text-center text-muted">' + esc(cfg.t.none) + '</td></tr>';
            return;
        }
        body.innerHTML = rows.map(function (s) {
            var cls = s.type === 'PPPoE' ? 'label-info' : 'label-warning';
            return '<tr>' +
                '<td>' + esc(s.router) + '</td>' +
                '<td><span class="label ' + cls + '">' + esc(s.type) + '</span></td>' +
                '<td>' + esc(s.user) + '</td>' +
                '<td>' + esc(s.address) + '</td>' +
                '<td>' + esc(s.mac) + '</td>' +
                '<td>' + esc(s.uptime) + '</td>' +
                '<td>' + fmtBytes(s.bytes_in) + '</td>' +
                '<td>' + fmtBytes(s.bytes_out) + '</td>' +
                '<td><button class="btn btn-danger btn-xs ac-kill" data-router="' + esc(s.router) +
                '" data-type="' + esc(s.type) + '" data-id="' + esc(s.id) + '">' +
                '<i class="glyphicon glyphicon-remove"></i> ' + esc(cfg.t.disconnect) + '</button></td>' +
                '</tr>';
        }).join('');
    }
    function load() {
        var router = document.getElementById('ac-router').value;
        fetch(cfg.dataUrl + (router ? ('&router=' + encodeURIComponent(router)) : ''), {
            headers: { 'X-CSRF-Token': csrfToken }
        }).then(function (r) { return r.json(); })
            .then(function (d) {
                lastSessions = d.sessions || [];
                document.getElementById('ac-count').textContent = d.count || 0;
                document.getElementById('ac-updated').textContent = cfg.t.updated + ': ' + (d.updated || '');
                var errBox = document.getElementById('ac-errors');
                if (d.errors && d.errors.length) {
                    errBox.innerHTML = '<div class="alert alert-warning" style="padding:6px 10px">' +
                        '<b>' + esc(cfg.t.unreachable) + ':</b> ' + esc(d.errors.join(' | ')) + '</div>';
                } else {
                    errBox.innerHTML = '';
                }
                render();
            })
            .catch(function () {
                document.getElementById('ac-body').innerHTML =
                    '<tr><td colspan="9" class="text-center text-danger">' + esc(cfg.t.failed) + '</td></tr>';
            });
    }
    function schedule() {
        if (timer) { clearInterval(timer); }
        if (document.getElementById('ac-auto').checked) { timer = setInterval(load, 15000); }
    }
    document.getElementById('ac-refresh').addEventListener('click', load);
    document.getElementById('ac-router').addEventListener('change', load);
    document.getElementById('ac-search').addEventListener('input', render);
    document.getElementById('ac-auto').addEventListener('change', schedule);
    document.getElementById('ac-body').addEventListener('click', function (e) {
        var btn = e.target.closest ? e.target.closest('.ac-kill') : null;
        if (!btn) { return; }
        if (!confirm(cfg.t.confirm + '?')) { return; }
        var body = 'router=' + encodeURIComponent(btn.getAttribute('data-router')) +
            '&type=' + encodeURIComponent(btn.getAttribute('data-type')) +
            '&id=' + encodeURIComponent(btn.getAttribute('data-id')) +
            '&csrf_token=' + encodeURIComponent(csrfToken);
        btn.disabled = true;
        fetch(cfg.disconnectUrl, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'X-CSRF-Token': csrfToken },
            body: body
        }).then(function (r) { return r.json(); })
            .then(function () { load(); })
            .catch(function () { btn.disabled = false; });
    });
    load();
    schedule();
})();
</script>
{/literal}
{include file="sections/footer.tpl"}
