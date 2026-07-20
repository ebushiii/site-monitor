#!/usr/bin/env bash
# Site monitor: checks every URL in sites.txt, compares against state.json,
# and sends a Twilio SMS on each transition (up -> down, down -> up).
# Exits non-zero only when a NEW outage is detected, so the GitHub workflow
# fails once per outage (one email), not once per 5-minute run.
set -uo pipefail

SITES_FILE="sites.txt"
STATE_FILE="state.json"
FROM_NUMBER="${TWILIO_FROM:-+17739856816}"

now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
now_ct=$(TZ=America/Chicago date +"%-I:%M %p %Z on %b %-d")

[[ -f "$STATE_FILE" ]] || echo '{}' > "$STATE_FILE"

check_site() {
  local url=$1 code attempt
  for attempt in 1 2 3; do
    code=$(curl -sL -o /dev/null -w '%{http_code}' --max-time 15 "$url" || echo "000")
    if [[ "$code" =~ ^[23] ]]; then echo "up $code"; return; fi
    [[ $attempt -lt 3 ]] && sleep 10
  done
  echo "down $code"
}

send_sms() {
  local body=$1
  if [[ -z "${TWILIO_ACCOUNT_SID:-}" || -z "${TWILIO_AUTH_TOKEN:-}" || -z "${ALERT_PHONE:-}" ]]; then
    echo "  (SMS not configured — would have texted: $body)"
    return
  fi
  if curl -s --fail -X POST "https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/Messages.json" \
      -u "${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}" \
      --data-urlencode "From=${FROM_NUMBER}" \
      --data-urlencode "To=${ALERT_PHONE}" \
      --data-urlencode "Body=${body}" > /dev/null; then
    echo "  SMS sent."
  else
    echo "  SMS send FAILED (check Twilio secrets/balance)."
  fi
}

new_state='{}'
outage_detected=0

while IFS= read -r url; do
  url=$(echo "$url" | xargs)
  [[ -z "$url" || "$url" == \#* ]] && continue

  read -r status code <<< "$(check_site "$url")"
  prev_status=$(jq -r --arg u "$url" '.[$u].status // "unknown"' "$STATE_FILE")
  prev_since=$(jq -r --arg u "$url" '.[$u].since // ""' "$STATE_FILE")
  since=$prev_since
  echo "$url -> $status (HTTP $code, was: $prev_status)"

  if [[ "$status" != "$prev_status" ]]; then
    since=$now_iso
    if [[ "$status" == "down" ]]; then
      outage_detected=1
      send_sms "🚨 SITE DOWN: ${url} is not responding (HTTP ${code}) as of ${now_ct}. — Eugenius Monitor"
    elif [[ "$prev_status" == "down" ]]; then
      mins="?"
      if [[ -n "$prev_since" ]]; then
        down_epoch=$(date -u -d "$prev_since" +%s 2>/dev/null || echo "")
        [[ -n "$down_epoch" ]] && mins=$(( ( $(date -u +%s) - down_epoch ) / 60 ))
      fi
      send_sms "✅ RECOVERED: ${url} is back up as of ${now_ct} (was down ~${mins} min). — Eugenius Monitor"
    fi
  fi

  new_state=$(jq --arg u "$url" --arg s "$status" --arg c "$code" --arg t "$since" \
    '.[$u]={status:$s,last_code:$c,since:$t}' <<< "$new_state")
done < "$SITES_FILE"

echo "$new_state" | jq . > "$STATE_FILE"

exit $outage_detected
