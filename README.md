# HEXA Purchase Assistant

Warehouse ERP for **New Harisree Agency** — trade purchases, stock ledger, barcode ops, and owner reports.
**React (Vite) + ASP.NET Core (.NET 10) + PostgreSQL**, deployed as a **PWA** (Vercel) with API on **Render**.

## Product overview

| Area | Detail |
|------|--------|
| **Stack** | React 19 (Vite + TypeScript + Tailwind v4) . ASP.NET Core 10 Web API . PostgreSQL 16 (Render) . optional Redis . GitHub Actions (CI, DB backup, API keep-alive) |
| **Platforms** | **PWA** (Chrome/Safari/Firefox), **desktop/tablet** (responsive NavigationRail shell), native pending |
| **State** | Zustand (business state) + TanStack Query v5 (server cache) + react-router v7 (data router) |
| **UI** | Tailwind CSS v4 with extracted Flutter design tokens (PlusJakartaSans, 8px grid, brand palette `#0E4F46`) |
| **Auth** | JWT (access + refresh tokens), WebAuthn biometric login, email+password, Google OAuth stub |
| **Purchases** | Trade purchases (`trade_purchases` + `trade_purchase_lines`) — preview → confirm save; delivery pipeline; damage reports |
| **Stock** | Catalog-linked qty, physical count vs system ledger, optimistic version + 409 retry, low-stock alerts |
| **Barcode** | Camera scan (WASM), manual search, unknown code → create item or assign barcode |
| **Reports** | Trade-backed KPIs (`/reports/trade-*`) — **not** legacy `entries` analytics |
| **Roles** | Owner, manager, staff — permissions on stock edit, export, reports |

**Data truth:** Spend KPIs and report tables use **trade** endpoints. Line money: weight lines → `qty × kg_per_unit × landing_cost_per_kg`; else `qty × landing_cost`.

**Ops:** [Backup setup](docs/backup/BACKUP_SETUP.md) . [Migration index](backend/sql/MIGRATION_INDEX.md) . [Pre-client audit](PRE_CLIENT_AUDIT_RESULT.md) . [TASKS.md](TASKS.md) . [Harisree master reference](docs/harisree/MASTER_REFERENCE.md) . [Cutover plan](docs/cutover-plan.md)

## Docs

| Doc | Description |
|-----|-------------|
| [Master PRD](docs/master-prd.md) | Product scope, roles, non-goals |
| [Architecture](docs/architecture.md) | System diagram and modules |
| [Data model](docs/data-model.md) | Entities and relationships |
| [API contract](docs/migration/api-contract.md) | All endpoints, request/response shapes, business rules |
| [Screen map & UX](docs/ux/screen-map.md) | Routes, implementation status, Flutter comparison |
| [Design tokens](docs/migration/design-tokens.md) | Extracted Flutter → React theme |
| [Cutover plan](docs/cutover-plan.md) | Phased migration from FastAPI + Flutter |
| [Delivery phases](docs/delivery-phases.md) | MVP → Phase 4 + testing |

## Quick start

### Prerequisites
- .NET 10 SDK
- Node.js 22+
- PostgreSQL 16 (or `docker compose up -d`)

### Database
```bash
docker compose up -d  # starts Postgres on port 5432 + Redis on 6379
```

### API
```bash
cd backend-dotnet
dotnet restore
# Set connection string (default: Host=localhost;Database=hexa;Username=hexa;Password=hexa)
dotnet run --project src/Api/PurchaseAssistant.Api.csproj
# API at http://localhost:5131, Swagger at http://localhost:5131/swagger
```

### Frontend
```bash
cd frontend-react
npm install
npx vite --host
# App at http://localhost:5173
```

### Run tests

**Backend (.NET):**
```bash
cd backend-dotnet
dotnet test tests/PurchaseAssistant.Tests.csproj
```

**Frontend (React):**
```bash
cd frontend-react
npm run lint
npm run build      # type-check + production build
```

**Contract tests (requires both APIs running):**
```bash
node scripts/contract-tests.js --old-api http://localhost:8000 --new-api http://localhost:5131
```

## Migration Status

### API Implementation (21 controller groups)

| Group | Status | Endpoints |
|-------|--------|-----------|
| Auth | ✅ Live | 6/6 |
| Me/Profile | ✅ Live | 6/6 |
| Catalog | ✅ Live | 25/25 |
| Users | ✅ Live | 14/14 |
| Trade Purchases | ✅ Live | 27/27 |
| Health | 🟡 Live | 5/5 (returns 501) |
| Businesses | 🟡 Stub | 4/4 |
| Contacts | 🟡 Stub | 11/11 |
| Stock | 🟡 Stub | 38/38 |
| Stock Audits | 🟡 Stub | 7/7 |
| Dashboard | 🟡 Stub | 1/1 |
| Reports Trade | 🟡 Stub | 3/3 |
| Reports | 🟡 Stub | 6/6 |
| Damage Reports | 🟡 Stub | 2/2 |
| Exports | 🟡 Stub | 4/4 |
| Notifications | 🟡 Stub | 7/7 |
| Operations | 🟡 Stub | 5/5 |
| Media/OCR | 🟡 Stub | 1/1 |
| Public Items | 🟡 Stub | 1/1 |
| Search | 🟡 Stub | 1/1 |
| Realtime | 🟡 Stub | 1/1 |
| **Total** | **5/21 live** | **140 open endpoints** |

### Frontend Implementation (101 routes)

| Category | Total | ✅ Live | 🟡 Stub | 🔄 Redirect | ❌ Missing |
|----------|-------|---------|---------|-------------|------------|
| Public | 8 | 6 | 1 | 1 | 0 |
| Owner Shell | 7 | — | 7 | — | — |
| Staff Shell | 7 | — | 5 | — | 1 |
| All others | 79 | — | 62 | 17 | — |
| **Total** | **101** | **6** | **75** | **18** | **1** |

See [Screen map & UX](docs/ux/screen-map.md) for full route-by-route comparison.

## Repo layout

```
backend-dotnet/       ASP.NET Core Web API (.NET 10)
├── src/
│   ├── Api/          Controllers, middleware, Program.cs
│   ├── Application/  DTOs, interfaces, services, validators
│   ├── Domain/       Entities, enums, value objects
│   └── Infrastructure/ DbContext, JWT, OAuth, background services
└── tests/
    └── PurchaseAssistant.Tests.csproj  41 xUnit integration tests

frontend-react/       React SPA (Vite + TypeScript + Tailwind)
├── src/
│   ├── components/   UI primitives + shell layout
│   ├── features/     Feature modules (auth, catalog, purchase, ...)
│   ├── lib/          API client, Zustand stores, calc engine, types
│   ├── pages/        101 route pages (4 live, 75 stubs, 18 redirects)
│   └── router.tsx    React Router data router (all routes)

flutter_app/          LEGACY Flutter client (being retired, keep until cutover stable)
backend/              LEGACY FastAPI server (being retired, keep until cutover stable)
```

## Stack migration

The app is being migrated from **Flutter + FastAPI** to **React + ASP.NET Core**.
Both stacks run against the same PostgreSQL schema. See [cutover plan](docs/cutover-plan.md) for the
6-phase approach: deploy → verify → parallel stacks → contract test → DNS cutover → retire.

**Current phase:** Phase 3 (Parallel Stacks). 5 of 21 API controllers are live. ~75 frontend routes are stubs.

## Principles

- **Landing cost** is always **manual** at entry.
- **Preview → confirm** before persisting any entry.
- **No toast/snackbar** for field validation — use inline error text instead.
- **Currency** formatted as ₹ with Indian digit grouping (#,##,###).
