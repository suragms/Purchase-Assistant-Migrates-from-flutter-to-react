# Media Storage Backend

Database-referenced images and uploaded file storage.

---

## Storage Backend (Current)

**Status:** Local disk storage. S3 is configured but optional.

### Configuration (`backend/app/config.py`)

```python
s3_bucket: str | None = None          # S3 bucket name (null = local disk)
s3_region: str = "ap-south-1"
s3_access_key: str | None = None
s3_secret_key: str | None = None
s3_endpoint: str | None = None
```

- When `s3_bucket` is **null** (default): files go to local disk at `backend/static/`
- When `s3_bucket` is **set**: S3 is initialized and media routes are activated

### Local Disk Setup (`backend/app/main.py`)

```python
_backend_root = Path(__file__).resolve().parent.parent  # backend/
_static_root = _backend_root / "static"
_static_root.mkdir(exist_ok=True)
(_static_root / "branding").mkdir(exist_ok=True)
app.mount("/static", StaticFiles(directory=str(_static_root)), name="static")
```

Files are served at `{BASE_URL}/static/...`. The `branding/` subdirectory holds uploaded logos.

### S3 Router (`backend/app/routers/media.py`)

Only includes `POST /v1/businesses/{business_id}/media/ocr` for OCR processing. Not used for image hosting.

---

## Database-Referenced Image Columns

### 1. `business.branding_logo_url`

| Column | Table | Type | Stored At |
|--------|-------|------|-----------|
| `branding_logo_url` | `businesses` | `varchar?` | `{BASE_URL}/static/branding/{id}.{ext}` or S3 URL |

**Upload endpoint:** `POST /v1/me/businesses/{business_id}/branding/logo` (multipart)

**Fallback behavior** (from Flutter code):
- `BusinessProfile` has `logoUrl` field mapped from `branding_logo_url`
- **Where it's displayed**: NOT in Flutter widget UI directly — used in **PDF generation** (purchase invoices, broker/supplier statements, reports)
- The PDF layout embeds `biz.logoUrl` as an image at the top of generated PDFs
- No fallback logo in the UI widgets; the PDF generation likely gracefully handles null

**React equivalent:**
- Include logo in PDF generation (when implemented)
- For any UI display, fall back to `public/brand/logo.webp` when null

### 2. `contacts.image_url`

| Column | Table | Type | Usage |
|--------|-------|------|-------|
| `image_url` | `suppliers` / `brokers` | `varchar?` | Contact photo |

**Fallback behavior** (from Flutter code):

**Broker detail page:**
- If `image_url` is non-empty → `Image.network(...)` 56×56 clipped with `ClipRRect`
- If empty → nothing (empty `SizedBox`)

**Purchase detail header (`_BrokerAvatar`):**
- If `imageUrl` non-empty → `CircleAvatar` with `NetworkImage` + silent error handler
- If empty → initials-based `CircleAvatar` (teal `#1B6B5A` background, white initials text, radius 14)

**Contact list:**
- Colored initials-based `CircleAvatar` (NO network images — uses palette of 6 colors: `#1A6B8A`, `#0D3D56`, `#5C6BC0`, `#00897B`, `#6D4C41`, `#AD1457`)
- Color selected by hashing the contact name

**React equivalent:**
- `Avatar` component with network image → teal initials fallback → generic icon fallback

### 3. `purchase_damage_report.photo_url` / `photo_urls[]`

| Column | Table | Type | Usage |
|--------|-------|------|-------|
| `photo_url` | `purchase_damage_reports` | `varchar?` | Single damage photo |
| `photo_urls` | `purchase_damage_reports` | `text[]` | Multiple damage photos |

**API:** `POST /v1/businesses/{businessId}/trade-purchases/{purchaseId}/damage-reports` sends `photo_url`

**Flutter capture:** Uses `image_picker` package for camera/gallery capture

**React equivalent:**
- `<input type="file" accept="image/*" capture>` for mobile camera parity
- After upload, render the array as the same multi-photo gallery/carousel the Flutter screen uses

### 4. `trade_purchase.broker_image_url`

| Column | Table | Type | Usage |
|--------|-------|------|-------|
| `broker_image_url` | `trade_purchases` | `varchar?` | Broker photo on purchase record |

**In Flutter:** The `TradePurchase` model has `brokerImageUrl` field (parsed from `broker_image_url` in JSON).
Displayed by `_BrokerAvatar` widget on purchase detail page (same fallback pattern as #2).

---

## Migration Constraint

**Do NOT change the storage backend or URL scheme during this migration.**

The database contains URLs like:
- `https://api.example.com/static/branding/{uuid}.png`
- `https://api.example.com/uploads/{path}`

Both the old Flutter app (during cutover) and the new React app need these to resolve identically.
The .NET backend (Infrastructure layer) must:

1. Serve `/static` from the **same local disk path** (or mount the same S3 bucket)
2. Return **exactly the same URL shape** so stored DB records work with both frontends
3. Implement the same upload endpoints (`POST /v1/me/businesses/{business_id}/branding/logo`, damage report photo uploads)

Switching storage backend or URL format is a **separate decision**, not a side-effect of framework migration.

### Current State in .NET

The .NET backend (`backend-dotnet/`) currently has:
- `Program.cs` with no `app.UseStaticFiles()` or `/static` mapping
- No branding logo upload endpoint
- No damage report photo handling

These must be added before cutover, preserving the same paths and URL format.
