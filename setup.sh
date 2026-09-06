#!/data/data/com.termux/files/usr/bin/bash
#
# setup.sh — one-shot installer for the SIM Bank WhatsApp monitor.
# Run this after cloning the repo into ~ on a fresh Termux install.

set -e

echo "=========================================================="
echo "  SIM BANK MONITOR — SETUP"
echo "=========================================================="

echo "Installing Termux packages (nodejs, curl, jq, git)..."
pkg update -y
pkg install -y nodejs curl jq git

echo ""
echo "Installing PM2 (process manager for the WhatsApp gateway)..."
npm install -g pm2

echo ""
echo "Installing wa-broadcast dependencies..."
cd wa-broadcast
npm install --allow-git=all

echo ""
echo "Approving install scripts for baileys/protobufjs (needed on some npm versions)..."
npm install-scripts approve @whiskeysockets/baileys 2>/dev/null || true
npm install-scripts approve protobufjs 2>/dev/null || true
npm install --allow-git=all

cd ..
chmod +x sim_status.sh

echo ""
echo "=========================================================="
echo "  SETUP COMPLETE"
echo "=========================================================="
echo ""
echo "Next steps:"
echo "  1. Edit wa-broadcast/index.js and pair.js:"
echo "     - Set ALERT_RECIPIENTS to the WhatsApp numbers you want alerts sent to"
echo "     - Set the 'number' in pair.js to the number Bailey sends FROM"
echo "  2. Run the pairing script once to link WhatsApp:"
echo "       cd wa-broadcast && node pair.js"
echo "     Enter the pairing code shown into WhatsApp > Linked Devices >"
echo "     Link a Device > Link with phone number instead."
echo "  3. Start the gateway under PM2:"
echo "       npm run pm2:start --prefix wa-broadcast"
echo "  4. Test it:"
echo "       curl -X POST http://localhost:3000/send-alert \\"
echo "         -H 'Content-Type: application/json' \\"
echo "         -d '{\"message\": \"Test alert\"}'"
echo "  5. Run a manual status check:"
echo "       ./sim_status.sh"
echo "  6. Automate it every 15 minutes:"
echo "       pkg install -y cronie termux-services"
echo "       (crontab -l 2>/dev/null; echo \"*/15 * * * * \$HOME/sim_status.sh >> \$HOME/sim_status.log 2>&1\") | crontab -"
echo "       sv-enable crond"
echo ""
echo "See README.md for full details."
