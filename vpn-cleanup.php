<?php
// Nightly cron: delete expired VPN keys from Outline and data.json
// Schedule: 0 1 * * * php /opt/vpn-cleanup.php >> /var/log/vpn-cleanup.log 2>&1

$DB_FILE     = '/var/www/html/data.json';
$OUTLINE_API = 'https://127.0.0.1:58868/YDTex7EKiBiALhILr0L3Vw';
$today       = date('Y-m-d');
$ts          = date('c');

if (!file_exists($DB_FILE)) { echo "[$ts] ERROR: data.json not found
"; exit(1); }

$db = json_decode(file_get_contents($DB_FILE), true);
if (!isset($db['keys'])) { echo "[$ts] No keys in DB
"; exit(0); }

$deleted = 0;
$failed  = 0;
$keep    = [];

foreach ($db['keys'] as $entry) {
    if (!empty($entry['expires_at']) && $entry['expires_at'] <= $today) {
        $kid = $entry['key_id'];
        $ch  = curl_init();
        curl_setopt_array($ch, [
            CURLOPT_URL            => "$OUTLINE_API/access-keys/$kid",
            CURLOPT_CUSTOMREQUEST  => 'DELETE',
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_SSL_VERIFYPEER => false,
            CURLOPT_SSL_VERIFYHOST => false,
            CURLOPT_TIMEOUT        => 10,
        ]);
        curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $err  = curl_error($ch);
        curl_close($ch);

        if ($code === 204 || $code === 404) {
            echo "[$ts] Deleted key $kid (expired {$entry['expires_at']}) HTTP $code
";
            $deleted++;
        } else {
            echo "[$ts] FAILED key $kid HTTP $code $err
";
            $failed++;
            $keep[] = $entry;
        }
    } else {
        $keep[] = $entry;
    }
}

$db['keys'] = array_values($keep);
file_put_contents($DB_FILE, json_encode($db));
echo "[$ts] Done - deleted: $deleted, failed: $failed, remaining: " . count($keep) . "
";
