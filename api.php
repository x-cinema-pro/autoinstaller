<?php
error_reporting(0);
ini_set('display_errors', 0);

header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Headers: Content-Type");
header("Content-Type: application/json");

session_start();

// --- CONFIGURATION ---
$DB_FILE = 'data.json';
// OUTLINE SERVER LOCAL ADDRESS
$OUTLINE_API_URL = "https://127.0.0.1:25336/4dHT4CobLHTcrSIyNIJqTw"; 

// --- DATABASE ENGINE ---
function getDB() {
    global $DB_FILE;
    if (!file_exists($DB_FILE)) {
        // Default Owner (data_limit: 0 means unlimited)
        $default = [
            "users" => [
                ["id" => 1, "username" => "owner", "password" => password_hash("password", PASSWORD_DEFAULT), "role" => "owner", "expires_at" => null, "data_limit" => 0]
            ],
            "keys" => [] 
        ];
        file_put_contents($DB_FILE, json_encode($default));
        return $default;
    }
    $data = json_decode(file_get_contents($DB_FILE), true);
    if (!isset($data['keys'])) $data['keys'] = [];
    if (!isset($data['users'])) $data['users'] = [];
    return $data;
}

function saveDB($data) {
    global $DB_FILE;
    file_put_contents($DB_FILE, json_encode($data));
}

$action = $_GET['action'] ?? '';
$input = json_decode(file_get_contents('php://input'), true);
$db = getDB();

// --- SESSION CHECK ---
if ($action === 'check_session') {
    if (isset($_SESSION['user'])) {
        $u = $_SESSION['user'];
        // Refresh user data from DB to get latest limit/expiry
        foreach($db['users'] as $dbUser) {
            if($dbUser['id'] == $u['id']) {
                $u = $dbUser;
                break;
            }
        }
        
        if ($u['role'] !== 'owner' && $u['expires_at'] && new DateTime($u['expires_at']) < new DateTime()) {
            session_destroy();
            echo json_encode(["logged_in" => false]);
        } else {
            unset($u['password']);
            echo json_encode(["logged_in" => true, "user" => $u]);
        }
    } else {
        echo json_encode(["logged_in" => false]);
    }
    exit;
}

if ($action === 'logout') {
    session_destroy();
    echo json_encode(["success" => true]);
    exit;
}

// --- PROXY (Fixes SSL Issues) ---
if ($action === 'proxy') {
    if (!isset($_SESSION['user'])) { http_response_code(401); exit; }

    $endpoint = $_GET['endpoint'] ?? '';
    $method = $_GET['method'] ?? 'GET';
    $url = $OUTLINE_API_URL . $endpoint;

    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_CUSTOMREQUEST, $method);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false); // Fix SSL
    curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false); // Fix SSL

    if (!empty($input) && in_array($method, ['POST', 'PUT'])) {
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($input));
        curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
    }

    $res = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    http_response_code($httpCode);
    echo $res;
    exit;
}

// 1. LOGIN
if ($action === 'login') {
    $u = $input['username'] ?? '';
    $p = $input['password'] ?? '';
    
    foreach ($db['users'] as $user) {
        if ($user['username'] === $u && password_verify($p, $user['password'])) {
            if ($user['role'] !== 'owner' && $user['expires_at'] && new DateTime($user['expires_at']) < new DateTime()) {
                echo json_encode(["error" => "Account Expired"]); exit;
            }
            $_SESSION['user'] = $user;
            unset($user['password']);
            echo json_encode(["success" => true, "user" => $user]);
            exit;
        }
    }
    echo json_encode(["error" => "Invalid Credentials"]);
    exit;
}

// 2. GET DATA
if ($action === 'get_data') {
    $safeUsers = array_map(function($u) { unset($u['password']); return $u; }, $db['users']);
    echo json_encode(["users" => array_values($safeUsers), "assignments" => $db['keys']]);
    exit;
}

// 3. ASSIGN KEY
if ($action === 'assign_key') {
    $db['keys'][] = ["key_id" => $input['key_id'], "user_id" => $input['user_id'], "expires_at" => $input['expires_at'] ?: null];
    saveDB($db); echo json_encode(["success" => true]); exit;
}

// 4. UPDATE KEY EXPIRY
if ($action === 'update_key_expiry') {
    foreach ($db['keys'] as &$k) { if ($k['key_id'] == $input['key_id']) { $k['expires_at'] = $input['expires_at'] ?: null; break; } }
    saveDB($db); echo json_encode(["success" => true]); exit;
}

// 5. UNASSIGN KEY
if ($action === 'unassign_key') {
    $tid = $_GET['id'];
    $db['keys'] = array_values(array_filter($db['keys'], function($k) use ($tid) { return $k['key_id'] != $tid; }));
    saveDB($db); echo json_encode(["success" => true]); exit;
}

// 6. ADMIN MANAGEMENT
if ($action === 'add_user') {
    foreach ($db['users'] as $u) if ($u['username'] === $input['username']) { echo json_encode(["error" => "Taken"]); exit; }
    $newId = count($db['users']) > 0 ? max(array_column($db['users'], 'id')) + 1 : 1;
    $db['users'][] = [
        "id" => $newId, 
        "username" => $input['username'], 
        "password" => password_hash($input['password'], PASSWORD_DEFAULT), 
        "role" => "admin", 
        "expires_at" => $input['expires_at'] ?: null,
        "data_limit" => $input['data_limit'] ? (int)$input['data_limit'] : 0
    ];
    saveDB($db); echo json_encode(["success" => true]); exit;
}
if ($action === 'delete_user') {
    $uid = $_GET['id']; if ($uid == 1) exit; 
    $db['users'] = array_values(array_filter($db['users'], function($u) use ($uid) { return $u['id'] != $uid; }));
    $db['keys'] = array_values(array_filter($db['keys'], function($k) use ($uid) { return $k['user_id'] != $uid; }));
    saveDB($db); echo json_encode(["success" => true]); exit;
}
if ($action === 'update_user') {
    foreach ($db['users'] as &$u) { if ($u['id'] == $input['id']) { $u['expires_at'] = $input['expires_at'] ?: null; break; } }
    saveDB($db); echo json_encode(["success" => true]); exit;
}
?>
