"""Trade-sourced report endpoints (/reports/trade-*)."""

import uuid
from datetime import date, timedelta

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _register_and_item_with_supplier():
    u = uuid.uuid4().hex[:10]
    email = f"rt{u}@test.hexa.local"
    r = client.post(
        "/v1/auth/register",
        json={"username": f"u{u}", "email": email, "password": "testpass12"},
    )
    assert r.status_code == 200, r.text
    access = r.json()["access_token"]
    h = {"Authorization": f"Bearer {access}"}
    br = client.get("/v1/me/businesses", headers=h)
    bid = br.json()[0]["id"]
    cat = client.post(
        f"/v1/businesses/{bid}/item-categories",
        headers=h,
        json={"name": "RTCat"},
    )
    assert cat.status_code == 201, cat.text
    cid = cat.json()["id"]
    types = client.get(
        f"/v1/businesses/{bid}/item-categories/{cid}/category-types",
        headers=h,
    )
    assert types.status_code == 200, types.text
    tid = types.json()[0]["id"]
    s = client.post(
        f"/v1/businesses/{bid}/suppliers",
        headers=h,
        json={"name": "RTSup", "phone": "9000000001", "gst_number": "32AAAAA0000A1Z1"},
    )
    assert s.status_code == 201, s.text
    sid = s.json()["id"]
    item = client.post(
        f"/v1/businesses/{bid}/catalog-items",
        headers=h,
        json={
            "category_id": cid,
            "name": "RTItem",
            "type_id": tid,
            "default_unit": "bag",
            "default_kg_per_bag": 50,
            "hsn_code": "10063090",
            "default_supplier_ids": [sid],
        },
    )
    assert item.status_code == 201, item.text
    iid = item.json()["id"]
    return h, bid, iid, sid, cid


def test_trade_items_suppliers_categories_endpoints():
    h, bid, iid, sid, _cid = _register_and_item_with_supplier()
    d0 = date.today() - timedelta(days=1)
    d1 = date.today()
    body = {
        "purchase_date": d0.isoformat(),
        "supplier_id": sid,
        "lines": [
            {
                "catalog_item_id": iid,
                "item_name": "RTItem",
                "qty": 10,
                "unit": "bag",
                "landing_cost": "2000",
                "kg_per_unit": 50,
                "landing_cost_per_kg": "40",
                "tax_percent": 0,
            },
        ],
    }
    pr = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
    assert pr.status_code == 201, pr.text

    q = f"from={d0.isoformat()}&to={d1.isoformat()}"
    ir = client.get(f"/v1/businesses/{bid}/reports/trade-items?{q}", headers=h)
    assert ir.status_code == 200, ir.text
    items = ir.json()
    assert len(items) >= 1
    row = next(x for x in items if x.get("item_name") == "RTItem")
    assert row["total_qty"] == 10.0
    assert row.get("catalog_item_id") == iid
    # Weight-priced line: qty * kg_per_unit * landing_cost_per_kg
    assert abs(float(row["total_purchase"]) - 20000.0) < 0.01

    sr = client.get(f"/v1/businesses/{bid}/reports/trade-suppliers?{q}", headers=h)
    assert sr.status_code == 200, sr.text
    sups = sr.json()
    assert any(s.get("supplier_name") == "RTSup" for s in sups)
    sup = next(s for s in sups if s.get("supplier_name") == "RTSup")
    assert sup["purchase_count"] >= 1
    assert float(sup["total_purchase"]) > 0

    cr = client.get(f"/v1/businesses/{bid}/reports/trade-categories?{q}", headers=h)
    assert cr.status_code == 200, cr.text
    cats = cr.json()
    assert len(cats) >= 1
    row_cat = next(c for c in cats if c.get("category_name") == "RTCat")
    assert float(row_cat["total_qty"]) == 10.0
    assert float(row_cat["total_purchase"]) > 0

    tr = client.get(f"/v1/businesses/{bid}/reports/trade-types?{q}", headers=h)
    assert tr.status_code == 200, tr.text
    types_rows = tr.json()
    assert len(types_rows) >= 1
    assert any(
        r.get("category_name") == "RTCat" and float(r.get("total_qty") or 0) > 0
        for r in types_rows
    )

    snap = client.get(
        f"/v1/businesses/{bid}/reports/trade-dashboard-snapshot?{q}", headers=h
    )
    assert snap.status_code == 200, snap.text
    sd = snap.json()
    su = sd.get("summary", {})
    assert float(su.get("total_purchase", 0)) > 0
    assert "total_selling" in su
    assert "total_landing" in su
    assert "total_profit" in su
    assert "profit_percent" in su
    assert "categories" in sd and isinstance(sd["categories"], list)
    for c in sd["categories"]:
        assert "subtitle_supplier" in c
        assert "subtitle_broker" in c
        for it in c.get("items") or []:
            assert "catalog_item_id" in it
    assert "recommendations" in sd

    ho = client.get(
        f"/v1/businesses/{bid}/reports/home-overview?{q}", headers=h
    )
    assert ho.status_code == 200, ho.text
    hod = ho.json()
    assert float(hod["summary"]["total_purchase"]) == float(
        sd["summary"]["total_purchase"]
    )
    assert int(hod["summary"].get("pending_delivery_count", -1)) >= 0
    assert int(sd["summary"].get("pending_delivery_count", -1)) >= 0

    ho_compact = client.get(
        f"/v1/businesses/{bid}/reports/home-overview?{q}&compact=true",
        headers=h,
    )
    assert ho_compact.status_code == 200, ho_compact.text
    hcompact = ho_compact.json()
    assert hcompact["item_slices"] == []
    assert hcompact["recommendations"] == []
    assert hcompact["consistency"]["portfolio_score"] is None
    for cat in hcompact.get("categories") or []:
        assert cat.get("items") == []

    ho_shell = client.get(
        f"/v1/businesses/{bid}/reports/home-overview?{q}&compact=true&shell_bundle=true",
        headers=h,
    )
    assert ho_shell.status_code == 200, ho_shell.text
    hs = ho_shell.json().get("home_shell")
    assert isinstance(hs, dict), hs
    assert "subcategories" in hs and "suppliers" in hs and "items" in hs
    assert isinstance(hs["items"], list)

    wider = f"from={(d1 - timedelta(days=40)).isoformat()}&to={d1.isoformat()}"
    too_long = client.get(
        f"/v1/businesses/{bid}/reports/home-overview?{wider}&max_span_days=10",
        headers=h,
    )
    assert too_long.status_code == 422, too_long.text

    mpr = client.get(
        f"/v1/businesses/{bid}/reports/trade-supplier-broker-map?{q}", headers=h
    )
    assert mpr.status_code == 200, mpr.text
    mpd = mpr.json()
    assert "rows" in mpd and "recommendations" in mpd
    assert any(r.get("catalog_item_id") == str(iid) for r in (mpd.get("rows") or []))


def test_month_dashboard_uses_line_total_source_of_truth():
    h, bid, iid, sid, _cid = _register_and_item_with_supplier()
    today = date.today()
    body = {
        "purchase_date": today.isoformat(),
        "supplier_id": sid,
        "lines": [
            {
                "catalog_item_id": iid,
                "item_name": "RTItem 50 KG",
                "qty": 2,
                "unit": "bag",
                "landing_cost": "3000",
                "kg_per_unit": "50",
                "landing_cost_per_kg": "60",
                "selling_rate": "3100",
            },
        ],
    }
    pr = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
    assert pr.status_code == 201, pr.text

    q = f"from={today.isoformat()}&to={today.isoformat()}"
    summary = client.get(f"/v1/businesses/{bid}/reports/trade-summary?{q}", headers=h)
    assert summary.status_code == 200, summary.text
    month = client.get(
        f"/v1/businesses/{bid}/dashboard",
        headers=h,
        params={"month": today.strftime("%Y-%m")},
    )
    assert month.status_code == 200, month.text

    assert float(month.json()["total_purchase"]) == float(summary.json()["total_purchase"])


def test_month_dashboard_excludes_deleted_matches_trade_summary():
    """Soft-deleted purchases must not appear in GET /dashboard month aggregates."""
    h, bid, iid, sid, _cid = _register_and_item_with_supplier()
    today = date.today()
    body = {
        "purchase_date": today.isoformat(),
        "supplier_id": sid,
        "lines": [
            {
                "catalog_item_id": iid,
                "item_name": "DelTest 50 KG",
                "qty": 1,
                "unit": "bag",
                "landing_cost": "5000",
                "kg_per_unit": "50",
                "landing_cost_per_kg": "100",
                "selling_rate": "5100",
            },
        ],
    }
    pr = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
    assert pr.status_code == 201, pr.text
    pid = pr.json()["id"]

    q = f"from={today.isoformat()}&to={today.isoformat()}"
    month_param = {"month": today.strftime("%Y-%m")}

    def totals():
        summary = client.get(f"/v1/businesses/{bid}/reports/trade-summary?{q}", headers=h)
        assert summary.status_code == 200, summary.text
        month = client.get(
            f"/v1/businesses/{bid}/dashboard",
            headers=h,
            params=month_param,
        )
        assert month.status_code == 200, month.text
        return float(summary.json()["total_purchase"]), float(month.json()["total_purchase"])

    s0, d0 = totals()
    assert s0 == d0
    assert s0 > 0

    dr = client.delete(
        f"/v1/businesses/{bid}/trade-purchases/{pid}",
        headers=h,
    )
    assert dr.status_code == 204, dr.text

    s1, d1 = totals()
    assert s1 == d1
    assert s1 == 0.0


def test_trade_daily_profit_series_shape_and_422():
    h, bid, iid, sid, _cid = _register_and_item_with_supplier()
    today = date.today()
    body = {
        "purchase_date": today.isoformat(),
        "supplier_id": sid,
        "lines": [
            {
                "catalog_item_id": iid,
                "item_name": "DailyProfitSKU",
                "qty": 2,
                "unit": "bag",
                "landing_cost": "2000",
                "kg_per_unit": "50",
                "landing_cost_per_kg": "40",
                "selling_rate": "2100",
            },
        ],
    }
    pr = client.post(f"/v1/businesses/{bid}/trade-purchases", headers=h, json=body)
    assert pr.status_code == 201, pr.text
    q = f"from={today.isoformat()}&to={today.isoformat()}"
    dr = client.get(f"/v1/businesses/{bid}/reports/trade-daily-profit?{q}", headers=h)
    assert dr.status_code == 200, dr.text
    series = dr.json()
    assert isinstance(series, list)
    assert len(series) >= 1
    day_row = next(x for x in series if x.get("d") == today.isoformat())
    assert "profit" in day_row
    assert float(day_row["profit"]) > 0

    bad = client.get(
        f"/v1/businesses/{bid}/reports/trade-daily-profit?from={today.isoformat()}&to={(today - timedelta(days=1)).isoformat()}",
        headers=h,
    )
    assert bad.status_code == 422, bad.text
