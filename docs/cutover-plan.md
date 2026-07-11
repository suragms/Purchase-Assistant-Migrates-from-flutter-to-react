# Cutover Plan — FastAPI + Flutter → ASP.NET Core + React

## Overview

Migrate from **Flutter web (PWA) + FastAPI (Python)** to **React (Vite PWA) + ASP.NET Core (.NET 10)**.
Both stacks share the same PostgreSQL database. Migration is phased to allow parallel validation
before legacy retirement.

---

## Phase 1: Deploy .NET API (DONE)

- [x] `render.yaml` deploys `backend-dotnet` Docker image as a Render web service
- [x] Health endpoints (`/health`, `/health/live`, `/health/ready`) respond
- [x] Auth endpoints (login, register, refresh, forgot/reset password) are live
- [x] Catalog endpoints (categories, items, variants, batch ops) are live
- [x] CI pipeline builds + tests .NET on every push to `main`/`develop`
- [ ] Remaining stubs (contacts, stock, dashboard, reports, operations, exports, media, realtime, notifications) need implementation

### API Status (17 controller groups)

| Controller | Status | Endpoints |
|-----------|--------|-----------|
| AuthController | ✅ Live | 6/6 |
| MeController | ✅ Live | 6/6 |
| CatalogController | ✅ Live | 25/25 |
| UsersController | ✅ Live | 14/14 |
| TradePurchaseController | ✅ Live | 27/27 |
| HealthController | 🟡 Partial | Returns 501 for all (5 endpoints) |
| BusinessesController | 🟡 Stub | 4 endpoints |
| ContactsController | 🟡 Stub | 11 endpoints |
| StockController | 🟡 Stub | 38 endpoints |
| StockAuditsController | 🟡 Stub | 7 endpoints |
| DashboardController | 🟡 Stub | 1 endpoint |
| ReportsController | 🟡 Stub | 6 endpoints |
| ReportsTradeController | 🟡 Stub | 3 endpoints |
| DamageReportsController | 🟡 Stub | 2 endpoints |
| ExportsController | 🟡 Stub | 4 endpoints |
| NotificationsController | 🟡 Stub | 7 endpoints |
| OperationsController | 🟡 Stub | 5 endpoints |
| MediaController | 🟡 Stub | 1 endpoint |
| PublicItemsController | 🟡 Stub | 1 endpoint |
| SearchController | 🟡 Stub | 1 endpoint |
| RealtimeController | 🟡 Stub | 1 endpoint |

---

## Phase 2: Deploy React Frontend (DONE)

- [x] `vercel.json` builds `frontend-react/dist` as static SPA
- [x] Configures Vite API proxy (`VITE_API_BASE_URL`) to point to .NET API
- [x] All 101 Flutter routes mirrored as React Router paths
- [x] Auth pages (splash, login, forgot/reset password) fully implemented
- [x] 75 additional routes scaffolded (placeholder stubs) for future implementation
- [x] Responsive shell: bottom nav <600px, rail 600-899px (collapsed), ≥900px (extended)
- [x] Auth guard with role-based routing (owner → `/home`, staff → `/staff/home`)

---

## Phase 3: Parallel Stacks (IN PROGRESS)

### Architecture

```
                    ┌──────────────┐
                    │  PostgreSQL  │
                    │  (Render DB) │
                    └──────┬───────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
              ▼            ▼            ▼
      ┌─────────────┐ ┌─────────┐ ┌──────────┐
      │ FastAPI     │ │ .NET    │ │          │
      │ (Python)    │ │ API     │ │ Same DB  │
      │ port 8000   │ │ port 8080│ │ schema   │
      └──────┬──────┘ └────┬────┘ └──────────┘
             │             │
             ▼             ▼
      ┌───────────┐ ┌──────────────┐
      │ Flutter   │ │ React (Vite) │
      │ (PWA)     │ │ (PWA)        │
      │ vercel.app│ │ (same Vercel)│
      └───────────┘ └──────────────┘
```

### Feature Flag Strategy

Two approaches (choose one):

**A. Subdomain (recommended for validation):**
- `app.mydomain.com` → React + .NET (new stack)
- `legacy.mydomain.com` → Flutter + FastAPI (old stack, read-only after cutover)
- Gradual DNS traffic shift via weighted records

**B. Query-parameter feature flag:**
- URL param `?stack=new` switches React to use .NET API
- Without param, React uses FastAPI (or vice versa)
- Suitable for internal testing, not for broad rollout

### Verification Gates

Before directing real traffic to .NET + React:

| Gate | Check | Method |
|------|-------|--------|
| Auth | Login, register, refresh, forgot/reset work identically | Manual + contract tests |
| Catalog | CRUD categories, items, variants, batch ops | Contract tests |
| Trade Purchases | Full lifecycle: draft → create → dispatch → arrive → commit-stock | E2E tests |
| Reports | Trade summary, supplier-wise, item-wise, category-wise numbers match | **BLOCKED** — .NET stubs |
| Contacts | Supplier/broker CRUD, metrics | **BLOCKED** — .NET stubs |
| Stock | List, detail, adjustments, physical count, barcode lookup | **BLOCKED** — .NET stubs |
| Dashboard | Home overview numbers match | **BLOCKED** — .NET stubs |

---

## Phase 4: Contract Testing

### Approach

Run `node scripts/contract-tests.js` with both APIs running against the same database:

```bash
# Start both backends
cd backend && uvicorn app.main:app --port 8000
cd backend-dotnet && dotnet run --project src/Api --urls http://localhost:5131

# Run contract tests
node scripts/contract-tests.js --old-api http://localhost:8000 --new-api http://localhost:5131
```

### What's compared

For each endpoint in [api-contract.md](docs/migration/api-contract.md):

1. **Status code** — must match
2. **Response shape** — key names normalized to snake_case, compared recursively
3. **Data values** — for authenticated read endpoints, values must be identical (same DB)

### Current coverage

The contract test script currently covers 4 basic endpoints (auth 401, health). It needs expansion
to cover all ~100+ endpoints from the API contract. See `scripts/contract-tests.js` for the
extensible endpoint list format.

---

## Phase 5: DNS Cutover

### Prerequisites
- [ ] All .NET API stubs implemented and tested
- [ ] Contract tests pass with 0 drift for all live endpoints
- [ ] React has feature parity with Flutter for all 101 routes
- [ ] Report numbers verified identical
- [ ] UAT sign-off from business users

### Steps

1. **Update DNS:**
   - Point `api.mydomain.com` CNAME → Render .NET service
   - Point Vercel custom domain to React app (already configured)

2. **Keep old stack running (2 weeks observation):**
   - FastAPI remains on `api-legacy.mydomain.com`
   - Flutter app remains on `legacy.mydomain.com` (Vercel redirect)
   - Both read from same PostgreSQL database

3. **Monitor:**
   - API error rates (<0.1% on new stack)
   - Report number diff checks (hourly cron)
   - User-reported issues

4. **Rollback plan:**
   - FastAPI can be restored to primary DNS within 5 minutes
   - Flutter app can be restored via Vercel deployment rollback

---

## Phase 6: Legacy Retirement

### Cleanup checklist

- [ ] 2 weeks without critical issues on new stack
- [ ] Business users confirm parity
- [ ] Delete `backend/` directory (FastAPI code)
- [ ] Delete `flutter_app/` directory (Flutter code)
- [ ] Update CI to remove Python test workflows
- [ ] Update README to remove legacy references
- [ ] Archive legacy repos/branches (git tag `legacy/flutter-fastapi`)

### Data cleanup

- [ ] Remove deprecated FastAPI-specific DB columns (if any)
- [ ] Consolidate any duplicated indexes created by different ORM conventions
- [ ] Verify all triggers/functions in PG are used by the new stack

---

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Decimal rounding differences (Python `decimal` vs .NET `decimal`) | Report numbers off by pennies | Run side-by-side comparison for all report endpoints with real data |
| SQL dialect differences (asyncpg vs Npgsql) | Queries return different results | Contract tests catch drift |
| JWT token format differences | Auth failures | Both use HS256; .NET uses same secret length |
| EF Core vs SQLAlchemy migration state | Schema drift | Both use same PG schema; run `alembic check` before cutover |
| Flutter → React UI behavioral differences | User confusion | Screen-by-screen UX walkthrough during UAT |
