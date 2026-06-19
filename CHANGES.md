# VPN Manager — Updates (2026-06-20)

## Bug Fixes

### 1. Expired key deletion is now atomic (`index.html`)
**Problem:** If the Outline API call to delete a key failed, the key was still removed from `data.json`. This caused "ghost" keys — deleted from your records but still active in Outline.

**Fix:** The DB entry (`data.json`) is only removed **after** a confirmed successful delete from the Outline API (HTTP 204). If Outline returns an error, the key stays in `data.json` and a console error is logged so you can see what failed.

For admin user cleanup, all keys must delete successfully before the admin user record is removed. If any key fails, the user record is kept so nothing falls out of sync.

---

### 2. Expiry comparison now includes keys expiring today (`index.html`)
**Problem:** The expiry check used a strict less-than comparison (`expires_at < today`), so a key set to expire on today's date would not be deleted until tomorrow.

**Fix:** Changed to `expires_at <= today` so keys are deleted on their expiry date.

---

### 3. Server-side nightly cleanup cron job (`vpn-cleanup.php`)
**Problem:** Expired keys were only deleted when the owner actively logged into the dashboard. If the owner didn't log in for days, expired keys kept working in Outline.

**Fix:** Added `/opt/vpn-cleanup.php` — a standalone PHP script that runs on the server every night at 01:00 (server time) via cron, regardless of whether anyone is logged in.

**Cron entry added to server:**
```
0 1 * * * php /opt/vpn-cleanup.php >> /var/log/vpn-cleanup.log 2>&1
```

**What it does:**
- Reads `data.json` for all keys with an `expires_at` date on or before today
- Sends a `DELETE` request to the Outline API for each one
- Only removes the entry from `data.json` if Outline confirms deletion (HTTP 204) or the key is already gone (HTTP 404)
- Logs every action to `/var/log/vpn-cleanup.log` with timestamps

---

## Files Changed

| File | Type | Description |
|------|------|-------------|
| `index.html` | Modified | Fixed `checkCleanup` — atomic deletes, corrected expiry comparison |
| `api.php` | No change | Proxy DELETE to Outline API was already correct |
| `vpn-cleanup.php` | New | Server-side nightly cron cleanup script |

## Deployment Notes

- `vpn-cleanup.php` must be placed at `/opt/vpn-cleanup.php` on the server
- Cron job is already active on the VPS (5.231.58.198)
- CDN scripts (React, Babel, Tailwind) are now hosted locally at `/var/www/html/js/` to remove external CDN dependency
