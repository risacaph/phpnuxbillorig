<?php

/**
 *  PHP Mikrotik Billing (https://github.com/hotspotbilling/phpnuxbill/)
 *
 *  Live connection monitor: aggregates active Hotspot + PPPoE sessions across
 *  all enabled routers, with disconnect actions. JSON endpoints feed the
 *  auto-refreshing UI.
 **/

_admin();
$ui->assign('_system_menu', 'network');
$ui->assign('_admin', $admin);

if (!in_array($admin['user_type'], ['SuperAdmin', 'Admin'])) {
    _alert(Lang::T('You do not have permission to access this page'), 'danger', "dashboard");
}

$action = isset($routes['1']) ? $routes['1'] : '';

switch ($action) {
    case 'data':
        header('Content-Type: application/json');
        $filter = _get('router');
        $query = ORM::for_table('tbl_routers')->where('enabled', 1)->order_by_asc('name');
        if (!empty($filter)) {
            $query->where('name', $filter);
        }
        $routers = $query->find_array();
        $sessions = [];
        $errors = [];
        foreach ($routers as $r) {
            try {
                $client = Mikrotik::getClient($r['ip_address'], $r['username'], $r['password']);
                if (!$client) {
                    continue;
                }
                foreach (Mikrotik::getActiveHotspot($client) as $h) {
                    $sessions[] = [
                        'router'    => $r['name'],
                        'type'      => 'Hotspot',
                        'id'        => $h['.id'],
                        'user'      => $h['user'],
                        'address'   => $h['address'],
                        'mac'       => $h['mac-address'],
                        'uptime'    => $h['uptime'],
                        'bytes_in'  => $h['bytes-in'],
                        'bytes_out' => $h['bytes-out'],
                    ];
                }
                foreach (Mikrotik::getActivePppoe($client) as $p) {
                    $sessions[] = [
                        'router'    => $r['name'],
                        'type'      => 'PPPoE',
                        'id'        => $p['.id'],
                        'user'      => $p['name'],
                        'address'   => $p['address'],
                        'mac'       => $p['caller-id'],
                        'uptime'    => $p['uptime'],
                        'bytes_in'  => null,
                        'bytes_out' => null,
                    ];
                }
            } catch (\Throwable $e) {
                $errors[] = $r['name'] . ': ' . $e->getMessage();
            }
        }
        echo json_encode([
            'success'  => true,
            'count'    => count($sessions),
            'sessions' => $sessions,
            'errors'   => $errors,
            'updated'  => date('Y-m-d H:i:s'),
        ]);
        die();

    case 'disconnect':
        header('Content-Type: application/json');
        $routerName = _post('router');
        $type = _post('type');
        $id = _post('id');
        if (empty($routerName) || empty($id)) {
            echo json_encode(['success' => false, 'message' => 'Missing parameters']);
            die();
        }
        $r = ORM::for_table('tbl_routers')->where('name', $routerName)->find_one();
        if (!$r) {
            echo json_encode(['success' => false, 'message' => Lang::T('Router not found')]);
            die();
        }
        try {
            $client = Mikrotik::getClient($r['ip_address'], $r['username'], $r['password']);
            if (strtolower($type) === 'pppoe') {
                Mikrotik::disconnectPppoeById($client, $id);
            } else {
                Mikrotik::disconnectHotspotById($client, $id);
            }
            _log($admin['username'] . " disconnected $type session ($id) on router $routerName", 'Network', $admin['id']);
            echo json_encode(['success' => true]);
        } catch (\Throwable $e) {
            echo json_encode(['success' => false, 'message' => $e->getMessage()]);
        }
        die();

    default:
        $ui->assign('_title', Lang::T('Active Connections'));
        $routers = ORM::for_table('tbl_routers')->where('enabled', 1)->order_by_asc('name')->find_array();
        $ui->assign('routers', $routers);
        $ui->display('admin/monitor/active.tpl');
        break;
}
