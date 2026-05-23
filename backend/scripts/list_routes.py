"""List FastAPI routes from app/routers."""
import re
from pathlib import Path

routes = []
for p in sorted(Path("app/routers").glob("*.py")):
    text = p.read_text(encoding="utf-8", errors="ignore")
    prefix_m = re.search(r'prefix\s*=\s*["\']([^"\']*)["\']', text)
    prefix = prefix_m.group(1) if prefix_m else ""
    for m in re.finditer(
        r'@router\.(get|post|put|patch|delete)\(\s*["\']([^"\']*)["\']', text
    ):
        routes.append((p.stem, m.group(1).upper(), prefix + m.group(2)))

print(f"Total: {len(routes)}")
for stem, method, path in routes:
    print(f"{method:6} {path:55} [{stem}]")
