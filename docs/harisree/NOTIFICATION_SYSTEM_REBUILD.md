# NOTIFICATION SYSTEM REBUILD

## Key Failures
- Count/list mismatch from category mapping and suppression behavior.
- Missing realtime publish in one server notification path.
- User-visible blank list with active counts under filtered tabs.

## Implemented Fixes
- Expanded category mapping for staff-related kinds.
- Suppression of synthetic warehouse rows now depends on unread server rows only.
- Added realtime publish for stock owner-notify route.
- Notification row rendering simplified for guaranteed visibility in page list.
- **2026-05-28:** `IntrinsicHeight` on `NotificationAlertCard` + grouped-tiles fallback (fixes blank cards under TODAY header).

## Remaining
- Normalize all backend `kind` values into explicit category table.
- Add integration tests for count-vs-list parity by role and tab.
