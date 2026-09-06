# SIM Bank WhatsApp Monitor

Monitors a GoIP8 SIM bank's 8 lines (phone number + Airtel airtime
balance) via USSD, and sends a formatted status report to WhatsApp
every time it runs. Designed to run on a schedule (cron, every 15 min)
inside Termux.

No auto-recharge — this is status/alerting only.

## What's in this repo

- `sim_status.sh` — the main script. Checks all 8 SIM bank lines,
  posts a summary report to WhatsApp via the local `wa-broadcast`
  gateway, and saves a JSON snapshot to `~/.sim_status_latest.json`.
- `wa-broadcast/index.js` — a small Express server + Baileys
  WhatsApp client. Exposes `POST http://localhost:3000/send-alert`
  which broadcasts a message to a fixed list of WhatsApp numbers.
- `wa-broadcast/pair.js` — one-off script to link a WhatsApp number
  to this bot via pairing code (no QR needed). Prompts for the
  number interactively — nothing hardcoded.
- `wa-broadcast/package.json` — dependencies + npm shortcuts.
- `setup.sh` — installs everything on a fresh Termux install.

## Requirements

- Termux (Android), F-Droid build recommended
- The SIM bank (GoIP8) reachable at `192.168.1.100` on the same
  WiFi network as the phone running this
- A WhatsApp number to send FROM (a spare number works fine — it
  just needs to be linkable as a "linked device")

## Setup (fresh Termux install)

```bash
pkg install git -y
git clone <this-repo-url> ~/sim-bank-monitor
cd ~/sim-bank-monitor
chmod +x setup.sh
./setup.sh
```

`setup.sh` installs Node, PM2, and all dependencies, and prints the
remaining manual steps (editing recipient numbers, pairing WhatsApp,
starting the gateway, setting up cron).

## Configuration

**`wa-broadcast/index.js`** — the numbers that RECEIVE alerts, edit this list:
```js
const ALERT_RECIPIENTS = [
  '2349033094296@s.whatsapp.net',
  '2348028592387@s.whatsapp.net',
  '2348035053804@s.whatsapp.net',
  '2347036935000@s.whatsapp.net'
];
```

The number Bailey sends FROM is **not** hardcoded — `pair.js` asks
for it interactively the first time you run it (see below).

Also check `sim_status.sh` if your SIM bank isn't at `192.168.1.100`,
uses different admin credentials, or you want to change the low
balance threshold (default ₦30):
```bash
DEVICE="192.168.1.100"
AUTH="admin:admin"
THRESHOLD=30
```

`BAL_USSD_AIRTEL` and `NUM_USSD_AIRTEL` are the USSD codes used —
these are Airtel Nigeria specific (`*310#` balance, `*121*2*4#` own
number). Different carriers need different codes.

## First-time pairing

```bash
cd wa-broadcast
node pair.js
```

It will ask:
```
Enter the WhatsApp number to pair (intl format, no +, e.g. 2348012345678):
```

Type in the number you want this instance to send alerts FROM, press
Enter, and it prints an 8-character pairing code. On that phone:
**WhatsApp → Settings → Linked Devices → Link a Device → Link with
phone number instead** — enter the code shown.

Once it prints `SUCCESS: WhatsApp Linked and Online!`, the session
is saved in `wa-broadcast/auth_info/` and you won't need to pair
again unless you unlink the device or delete that folder. Each
device/clone of this repo needs its own one-time pairing — session
credentials aren't portable between machines.

## Running it

**Start the WhatsApp gateway** (keep running in the background):
```bash
cd ~/sim-bank-monitor/wa-broadcast
npm run pm2:start
```
PM2 keeps it alive and auto-restarts on disconnect. Useful commands:
```bash
npm run pm2:logs      # tail live logs
npm run pm2:restart   # restart the gateway
```

**Test the alert path:**
```bash
curl -X POST http://localhost:3000/send-alert \
  -H "Content-Type: application/json" \
  -d '{"message": "Test alert"}'
```
All numbers in `ALERT_RECIPIENTS` should receive this on WhatsApp.

**Run a status check manually:**
```bash
cd ~/sim-bank-monitor
./sim_status.sh
```
This takes a few minutes (up to ~40s per line if a SIM is slow to
respond) and ends by sending a full report to WhatsApp, e.g.:

```
📊 SIM BANK STATUS REPORT (14:32) 📊

✅ Line 1 (07089017112): ₦245
✅ Line 2 (09127480473): ₦180
⚠️ Line 3 (09016759039): ₦18 (LOW)
❌ Line 4 (UNRESPONSIVE): UNRESPONSIVE / NO REPLY
...

Threshold: ₦30
```

**Automate it every 15 minutes:**
```bash
pkg install -y cronie termux-services
(crontab -l 2>/dev/null; echo "*/15 * * * * $HOME/sim-bank-monitor/sim_status.sh >> $HOME/sim_status.log 2>&1") | crontab -
sv-enable crond
```

## Notes / known quirks

- A SIM briefly failing to respond is normal (weak signal, momentary
  carrier deregistration) — it's reported as UNRESPONSIVE in that
  run's report, not treated as a permanent failure.
- The balance regex uses `head -n 1` because some carrier USSD
  replies include extra multi-line bonus/data-balance text after the
  main balance line, which could otherwise leak a stray match.
- This is Airtel-Nigeria-specific right now (`*310#` / `*121*2*4#`).
  Supporting multiple carriers would mean detecting each SIM's
  network and picking the right USSD codes per line.
- No auto-recharge is wired in. This system only reports status.
