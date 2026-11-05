#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi

: "${AGW_ADMIN_KEY:?AGW_ADMIN_KEY is required}"
ADMIN_ADDR="${AGW_ADMIN_ADDR:-http://[::1]:9180}"

curl -fsS -X PUT "${ADMIN_ADDR}/apisix/admin/global_rules/1" \
  -H "X-API-KEY: ${AGW_ADMIN_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "plugins": {
      "coraza-filter": {
        "conf": {
          "default_directives": "default",
          "directives_map": {
            "default": [
              "SecDebugLogLevel 3",
              "SecRuleEngine On",
              "Include @crs-setup-conf",
              "Include @owasp_crs/*.conf",
              "SecRuleRemoveById 920420",
              "SecRuleRemoveById 911100"
            ]
          }
        }
      }
    }
  }'

echo
echo "Global WAF rule applied."
