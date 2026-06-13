"""JSON ETag helpers for conditional GET responses."""

from __future__ import annotations

import hashlib
import json
from typing import Any

from starlette.requests import Request
from starlette.responses import JSONResponse, Response


def payload_etag(body: bytes) -> str:
    return '"' + hashlib.md5(body).hexdigest()[:16] + '"'


def json_bytes(payload: dict[str, Any]) -> bytes:
    return json.dumps(payload, sort_keys=True, default=str).encode()


def json_response_with_etag(
    request: Request,
    payload: dict[str, Any],
    *,
    cache_control: str | None = None,
) -> Response:
    body = json_bytes(payload)
    etag = payload_etag(body)
    headers: dict[str, str] = {"ETag": etag}
    if cache_control:
        headers["Cache-Control"] = cache_control
    if request.headers.get("if-none-match") == etag:
        return Response(status_code=304, headers=headers)
    return JSONResponse(content=payload, headers=headers)
