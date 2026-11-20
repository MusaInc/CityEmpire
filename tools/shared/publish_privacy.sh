#!/usr/bin/env bash
# Publishes the NEVER STOP and WORLDSTATE privacy pages at
#   https://musastudios.co.uk/privacy/neverstop
#   https://musastudios.co.uk/privacy/worldstate
# the same way /privacy/cityswing is served (Caddy, /srv/musa-builds/privacy).
# Run by the owner:  sudo bash tools/shared/publish_privacy.sh
# Backs up the Caddyfile, validates before reloading, restores it on failure.
set -euo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
ns="$here/../NeverStop/store/privacy-neverstop.html"
ws="$here/store/privacy-worldstate.html"
cf=/etc/caddy/Caddyfile
install -m 644 "$ns" /srv/musa-builds/privacy/neverstop.html
install -m 644 "$ws" /srv/musa-builds/privacy/worldstate.html
if grep -q "handle /privacy/worldstate" "$cf" && grep -q "handle /privacy/neverstop" "$cf"; then
  echo "routes already present"; systemctl reload caddy; exit 0
fi
bak="$cf.bak-before-privacy-$(date -u +%Y%m%dT%H%M%S)"
cp "$cf" "$bak"
python3 - "$cf" <<'PY'
import sys, re
p = sys.argv[1]; s = open(p).read()
m = re.search(r"([ \t]*)handle /privacy/cityswing \{.*?\n\1\}\n", s, re.S)
assert m, "cityswing privacy route not found"
ind = m.group(1)
add = ""
for app in ("neverstop", "worldstate"):
    if f"handle /privacy/{app}" in s:
        continue
    add += m.group(0).replace("cityswing", app)
    add += "\n"
s = s[:m.end()] + "\n" + add + s[m.end():]
open(p, "w").write(s)
PY
if caddy validate --config "$cf" --adapter caddyfile; then
  systemctl reload caddy
  for u in neverstop worldstate; do printf "%s " $u; curl -s -o /dev/null -w "%{http_code}\n" "https://musastudios.co.uk/privacy/$u"; done
else
  cp "$bak" "$cf"; echo "validation failed: Caddyfile restored"; exit 1
fi
