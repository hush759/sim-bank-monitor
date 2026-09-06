#!/data/data/com.termux/files/usr/bin/bash

DEVICE="192.168.1.100"
AUTH="admin:admin"
MAX_WAIT=40
THRESHOLD=30
JSON_OUT=~/.sim_status_latest.json
BAL_USSD_AIRTEL="*310#"
NUM_USSD_AIRTEL="*121*2*4#"

get_smskey() {
  curl -s -u "$AUTH" --max-time 20 "http://$DEVICE/default/en_US/tools.html?type=ussd" | grep -oP 'name="smskey" value="\K[^"]+'
}

send_ussd() {
  local LINE=$1 CODE=$2
  local SMSKEY=$(get_smskey)
  curl -s -u "$AUTH" --max-time 25 -X POST \
    --data-urlencode "line${LINE}=1" \
    --data-urlencode "smskey=$SMSKEY" \
    --data-urlencode "action=USSD" \
    --data-urlencode "telnum=$CODE" \
    --data-urlencode "send=Send" \
    "http://$DEVICE/default/en_US/ussd_info.html?type=ussd" > /dev/null
}

poll_reply() {
  local LINE=$1
  local ELAPSED=0 REPLY=""
  while [ -z "$REPLY" ] && [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    RESPONSE=$(curl -s -u "$AUTH" --max-time 20 "http://$DEVICE/default/en_US/send_sms_status.xml?line=${LINE}")
    REPLY=$(echo "$RESPONSE" | grep -oP "<error${LINE}>\K[^<]*")
  done
  echo "$REPLY"
}

alert() {
  local MESSAGE="$1"
  echo ""
  echo "Sending Report to WhatsApp..."
  PAYLOAD=$(jq -n --arg msg "$MESSAGE" '{"message": $msg}')
  curl -s -X POST "http://localhost:3000/send-alert" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD"
  echo ""
}

echo "=========================================================="
echo "  SIM BANK LIVE STATUS — $(date +'%Y-%m-%d %H:%M:%S')"
echo "=========================================================="

if ! ping -c 1 -W 3 "$DEVICE" > /dev/null 2>&1; then
  echo "DEVICE OFFLINE: Cannot reach SIM bank at $DEVICE."
  alert "⚠️ CRITICAL: SIM Bank Gateway ($DEVICE) is OFFLINE. Check power and router connection."
  echo "{\"device_online\": false, \"timestamp\": \"$(date -Iseconds)\", \"lines\": []}" > "$JSON_OUT"
  exit 1
fi

echo "Gateway online. Querying live data across 8 slots..."
JSON_LINES=""
REPORT_ITEMS=()

for LINE in 1 2 3 4 5 6 7 8; do
  printf "Line %d: " "$LINE"
  
  # Query Phone Number
  send_ussd "$LINE" "$NUM_USSD_AIRTEL"
  NUM_REPLY=$(poll_reply "$LINE")
  NUM_RAW=$(echo "$NUM_REPLY" | grep -oP 'number is \K[0-9]+')
  
  if [ -n "$NUM_RAW" ]; then
    NUM="0$NUM_RAW"
  else
    NUM="UNRESPONSIVE"
  fi

  # Query Balance
  send_ussd "$LINE" "$BAL_USSD_AIRTEL"
  BAL_REPLY=$(poll_reply "$LINE")
  BAL=$(echo "$BAL_REPLY" | grep -oP 'Bal:N\K[0-9.,]+' | tr -d ',' | head -n 1)

  if [ -z "$BAL" ]; then
    echo "NO RESPONSE | Phone: $NUM"
    BAL_JSON="null"
    REPORT_ITEMS+=("❌ Line ${LINE} (${NUM}): UNRESPONSIVE / NO REPLY")
  else
    echo "₦$BAL | Phone: $NUM"
    BAL_JSON="$BAL"
    
    IS_LOW=$(awk -v b="$BAL" -v t="$THRESHOLD" 'BEGIN{print (b<t)?"1":"0"}')
    if [ "$IS_LOW" = "1" ]; then
      REPORT_ITEMS+=("⚠️ Line ${LINE} (${NUM}): ₦${BAL} (LOW)")
    else
      REPORT_ITEMS+=("✅ Line ${LINE} (${NUM}): ₦${BAL}")
    fi
  fi

  NUM_JSON="null"
  [ "$NUM" != "UNRESPONSIVE" ] && NUM_JSON="\"$NUM\""
  
  LINE_JSON=$(cat <<EOFLINE
{"line": $LINE, "number": $NUM_JSON, "balance": $BAL_JSON}
EOFLINE
)
  if [ -z "$JSON_LINES" ]; then JSON_LINES="$LINE_JSON"; else JSON_LINES="$JSON_LINES,$LINE_JSON"; fi
done

# Format and dispatch report to WhatsApp
SUMMARY=$(printf "%s\n" "${REPORT_ITEMS[@]}")
TIMESTAMP=$(date +'%H:%M')
FORMATTED_REPORT=$(printf "📊 SIM BANK STATUS REPORT (%s) 📊\n\n%s\n\nThreshold: ₦%s" "$TIMESTAMP" "$SUMMARY" "$THRESHOLD")
alert "$FORMATTED_REPORT"

echo "=========================================================="
echo "Done. Snapshot saved to $JSON_OUT"
echo "=========================================================="
cat <<EOFJSON > "$JSON_OUT"
{"device_online": true, "timestamp": "$(date -Iseconds)", "lines": [$JSON_LINES]}
EOFJSON
