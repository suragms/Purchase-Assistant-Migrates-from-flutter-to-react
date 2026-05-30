# Barcode workflow (Harisree)

## Roles

| Role | Scan lookup | Assign barcode / item code | Update stock from scan | Bulk print |
|------|-------------|----------------------------|------------------------|------------|
| Owner / Admin / Manager | Yes | Yes | Yes | Yes |
| Staff | Yes | Yes | Yes | Yes |
| Custom read-only (`stock_edit: false`) | Yes | No | No | If `barcode_print` |

Permissions come from `/v1/me/businesses` → `permissions` (role defaults + per-user overrides).

## Flows

### 1. Warehouse scan (`/barcode/scan`)

1. Align **packaging barcode** in the green frame (Code128 / EAN / UPC / QR on labels).
2. On match → quick stock sheet or item actions.
3. **Unknown barcode** → assign to existing item, create item, or manual entry (edit roles only).
4. **Public QR** on printed labels → `/scan/{token}` (no login, read-only stock).

### 2. Missing labels (`/stock/missing-barcodes`)

1. Tab **Missing barcode** — sorted by highest stock first.
2. **Assign** → type or **Scan packaging barcode**.
3. **Print label** → single label PDF; stick on shelf.
4. Staff: **Inform owner** → owner notification (`missing_barcode`).

### 3. Bulk print (`/barcode/bulk-print`)

1. Select items (max **100** per PDF batch on web).
2. Use **A4 + Code128** for large runs (50 labels per file).
3. After printing, scan each label QR to verify (public page) or in-app scan for stock.

## Deploy checklist

- Backend: `alembic upgrade head` (no new migration for this doc; API permission guards live in routers).
- Render API deploy.
- Vercel / app build — users should **sign out and in** once to refresh `permissions` on session.

## Manual QA

| Step | Pass |
|------|------|
| Scan known item → opens stock sheet | [ ] |
| Scan unknown → clear message + assign/create | [ ] |
| Missing labels → assign + print + staff inform owner | [ ] |
| Bulk 50+ labels → PDF chunks, no browser crash | [ ] |
| Read-only user → scan works, assign/save blocked | [ ] |
| QR on label in browser (logged out) → public item page | [ ] |
