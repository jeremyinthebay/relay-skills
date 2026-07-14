#!/bin/zsh
# check-favicons.sh — does each brand domain actually resolve to that brand's real mark?
#
# Two things this catches that a naive check does not:
#   1. The favicon endpoint 301s. Without -L you conclude EVERY domain failed. (Note the -L below.)
#   2. When a domain can't be resolved, the service returns a GENERIC GLOBE with HTTP 200.
#      It looks like a logo. It is not. We fingerprint the globe and flag any match.
#
# Usage:  ./check-favicons.sh domains.txt
#         where domains.txt is lines of:   <id> <domain>
#
# A 200 means the server answered. It does not mean a logo was painted, and it does not mean
# the mark belongs to the brand you think. After running this, LOOK at the contact sheet.

set -u
FILE="${1:-domains.txt}"
TMP=$(mktemp -d)

# Fingerprint the generic globe by asking for a domain that cannot exist.
curl -sL -o "$TMP/globe.png" "https://www.google.com/s2/favicons?sz=64&domain=thisbrandcannotexist99999.com"
GLOBE=$(md5 -q "$TMP/globe.png" 2>/dev/null || md5sum "$TMP/globe.png" | cut -d' ' -f1)

printf "%-16s %-26s %5s %8s  %s\n" ID DOMAIN CODE BYTES "WHAT CAME BACK"
printf "%-16s %-26s %5s %8s  %s\n" ---- ------ ---- ----- --------------

globes=0; ok=0
while read -r id dom; do
  [ -z "${id:-}" ] && continue
  case "$id" in \#*) continue ;; esac

  code=$(curl -sL -o "$TMP/$id" -w "%{http_code}" "https://www.google.com/s2/favicons?sz=64&domain=$dom")
  bytes=$(wc -c < "$TMP/$id" | tr -d ' ')
  sum=$(md5 -q "$TMP/$id" 2>/dev/null || md5sum "$TMP/$id" | cut -d' ' -f1)

  if [ "$sum" = "$GLOBE" ]; then
    what="!! GENERIC GLOBE — unusable, use DIRECT or monogram"
    globes=$((globes+1))
  else
    what=$(file -b "$TMP/$id" | cut -c1-44)
    ok=$((ok+1))
  fi
  printf "%-16s %-26s %5s %8s  %s\n" "$id" "$dom" "$code" "$bytes" "$what"
done < "$FILE"

echo
echo "resolved to a real mark: $ok    generic globe: $globes"
[ "$globes" -gt 0 ] && echo "→ for each globe: try the brand's own https://<domain>/favicon.ico (often works when the proxy doesn't)"
echo "→ now render the contact sheet and LOOK at them. Pixel size does not tell you it's the right logo."
rm -rf "$TMP"
