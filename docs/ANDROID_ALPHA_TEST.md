# Android Alpha physical-device gate

This gate validates the Flutter Android Alpha against BMA **staging** on one
Samsung Fold 7 or S24 Ultra. It does not authorize production or Store release.

## Preconditions

- Branch: `codex/terminal-bridge-v0-3`.
- Canonical staging integration must eventually show both
  `PostgreSQL scalar preflight: PASS` and final `Result : PASS`.
- Android artifact build metadata must contain:
  - package: `com.binhminh.bma`
  - ABI: `arm64-v8a`
  - API: `https://gateway.redtigerhead.com/bmapp-staging/api/v1`
- Use synthetic Alpha accounts only. Do not put passwords or keys in chat.
- Connect exactly one Android pilot device with USB debugging authorized.

## Install and launch

1. Download the latest `bma-android-alpha-staging` artifact from the PR's
   successful BMA CI run. Keep the ZIP intact.
2. Pull the matching branch on MinhComp.
3. Run:

```powershell
Set-Location "C:\ABMT\BMA_BinhMinhApp"
git switch codex/terminal-bridge-v0-3
git pull --ff-only

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\infra\scripts\install-android-alpha.ps1 `
  -ArtifactPath "C:\path\to\bma-android-alpha-staging.zip"
```

The script verifies SHA-256 before using ADB, requires exactly one authorized
device, installs the APK, verifies `com.binhminh.bma`, launches it, and finishes
with `Result : PASS`.

If installation reports `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, the phone has an
older Alpha signed with a different temporary CI key. Do not let the script
uninstall it automatically. Confirm that losing its local Alpha session/cache is
acceptable, then uninstall that old Alpha manually and rerun.

## Ten-minute acceptance pass

| ID | Check | Pass condition |
| --- | --- | --- |
| AA-01 | Cold launch | App opens as **Bình Minh App** without crash or debug banner. |
| AA-02 | Account status | Pending/rejected/disabled account messages are clear; an approved synthetic account can log in. |
| AA-03 | Session | Force-close and reopen; the approved session remains available. |
| AA-04 | Overview | Plant state, runtime and schedule load without a fake zero for missing data. |
| AA-05 | Quality | Published/freshness data loads; missing fineness remains “Chưa cập nhật/Chưa có dữ liệu”. |
| AA-06 | Attendance/Profile | Both screens load; data remains scoped to the signed-in user. |
| AA-07 | Announcements | Inbox loads and read/unread interaction does not duplicate an item. Real FCM push is Week 2, not this gate. |
| AA-08 | Offline cache | After opening data online, disable Wi-Fi/mobile data, reopen a cached screen and see the saved-data/stale indicator. |
| AA-09 | Logout | Logout clears the session and returns to Login even if the network is unavailable. |

## Evidence to return

Do not send credentials. Return only:

```text
AndroidInstall       : PASS/FAIL
LoginApproved        : PASS/FAIL
SessionPersistence   : PASS/FAIL
FiveMainScreens      : PASS/FAIL
AttendanceSynthetic : PASS/FAIL/NOT_RUN
AttendancePhysical  : DEFERRED/PASS/FAIL
OfflineCache         : PASS/FAIL
Logout               : PASS/FAIL
BlockingIssue        : NONE/<short description>
AndroidAlphaGate     : PASS/FAIL
```

A failed row keeps the Android gate at **NO-GO** but does not require repeating
Docker, Cloudflare, database migration or the staging infrastructure smoke test.

## Home-safe pass without the physical Terminal

The Android and backend gates can proceed remotely with synthetic data. Complete
AA-01 through AA-05 and AA-07 through AA-09. For AA-06, use an approved account
already linked to a synthetic `employee_code`, inject `EMPLOYEE_SCAN` through the
staging integration API, and verify that attendance remains scoped to that user.

The backend CI smoke test creates that profile/account pair, approves it through
the Admin flow, checks `/profile/me`, posts an Entry-window and Exit-window
`EMPLOYEE_SCAN`, then requires a confirmed 480-minute session from
`/attendance/me`. It also posts one synthetic `QUALITY_RESULT_PUBLISHED` event to
verify BMA's BMKCS projection path. This proves BMA ingest/projection only; it
does not prove the BMKCS desktop Gateway adapter is deployed.

Keep `AttendancePhysical` at `DEFERRED` until Terminal `1605063`, Bridge mapping,
PostgreSQL projection and BMA mobile display can be checked together at the
factory. A synthetic pass never replaces that physical Entry/Exit gate.
