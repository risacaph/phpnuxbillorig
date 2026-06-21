<?php

/**
 *  PHP Mikrotik Billing (https://github.com/hotspotbilling/phpnuxbill/)
 *
 *  Power-over-Ethernet management: view PoE-out status per ethernet port on a
 *  router, switch a port off / auto-on / forced-on, and power-cycle a port to
 *  remotely reboot the powered CPE/AP. JSON endpoints feed the UI.
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
        $r = ORM::for_table('tbl_routers')->where('name', _get('router'))->where('enabled', 1)->find_one();
        if (!$r) {
            echo json_encode(['success' => false, 'message' => Lang::T('Router not found')]);
            die();
        }
        try {
            $client = Mikrotik::getClient($r['ip_address'], $r['username'], $r['password']);
            $ports = Mikrotik::getPoePorts($client);
            $names = array_map(function ($p) {
                return $p['name'];
            }, $ports);
            $status = Mikrotik::getPoeStatus($client, $names);
            foreach ($ports as &$p) {
                $st = isset($status[$p['name']]) ? $status[$p['name']] : [];
                $p['poe_status'] = isset($st['poe-out-status']) ? $st['poe-out-status'] : '';
                $p['voltage']    = isset($st['poe-out-voltage']) ? $st['poe-out-voltage'] : '';
                $p['current']    = isset($st['poe-out-current']) ? $st['poe-out-current'] : '';
                $p['power']      = isset($st['poe-out-power']) ? $st['poe-out-power'] : '';
            }
            unset($p);
            echo json_encode(['success' => true, 'ports' => $ports, 'updated' => date('Y-m-d H:i:s')]);
        } catch (\Throwable $e) {
            echo json_encode(['success' => false, 'message' => $e->getMessage()]);
        }
        die();

    case 'set':
        header('Content-Type: application/json');
        $r = ORM::for_table('tbl_routers')->where('name', _post('router'))->where('enabled', 1)->find_one();
        if (!$r) {
            echo json_encode(['success' => false, 'message' => Lang::T('Router not found')]);
            die();
        }
        try {
            $client = Mikrotik::getClient($r['ip_address'], $r['username'], $r['password']);
            Mikrotik::setPoeOut($client, _post('port_id'), _post('state'));
            _log($admin['username'] . " set PoE " . _post('state') . " on port " . _post('port_id') . " router " . $r['name'], 'Network', $admin['id']);
            echo json_encode(['success' => true]);
        } catch (\Throwable $e) {
            echo json_encode(['success' => false, 'message' => $e->getMessage()]);
        }
        die();

    case 'cycle':
        header('Content-Type: application/json');
        $r = ORM::for_table('tbl_routers')->where('name', _post('router'))->where('enabled', 1)->find_one();
        if (!$r) {
            echo json_encode(['success' => false, 'message' => Lang::T('Router not found')]);
            die();
        }
        try {
            $client = Mikrotik::getClient($r['ip_address'], $r['username'], $r['password']);
            Mikrotik::poePowerCycle($client, _post('port_id'), (int) _post('duration', 5));
            _log($admin['username'] . " power-cycled PoE port " . _post('port_id') . " on router " . $r['name'], 'Network', $admin['id']);
            echo json_encode(['success' => true]);
        } catch (\Throwable $e) {
            echo json_encode(['success' => false, 'message' => $e->getMessage()]);
        }
        die();

    default:
        $ui->assign('_title', Lang::T('PoE Management'));
        $routers = ORM::for_table('tbl_routers')->where('enabled', 1)->order_by_asc('name')->find_array();
        $ui->assign('routers', $routers);
        $ui->display('admin/poe/list.tpl');
        break;
}
