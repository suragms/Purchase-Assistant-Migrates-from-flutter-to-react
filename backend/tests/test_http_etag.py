"""Unit tests for JSON ETag helper."""

from starlette.requests import Request

from app.http_etag import json_response_with_etag


def test_json_response_with_etag_returns_304_when_match():
    scope = {
        "type": "http",
        "method": "GET",
        "path": "/",
        "headers": [(b"if-none-match", b'"abc"')],
    }
    request = Request(scope)
    payload = {"ok": True}
    first = json_response_with_etag(request, payload, cache_control="private, max-age=60")
    etag = first.headers["etag"]
    scope["headers"] = [(b"if-none-match", etag.encode())]
    request2 = Request(scope)
    second = json_response_with_etag(request2, payload, cache_control="private, max-age=60")
    assert second.status_code == 304
