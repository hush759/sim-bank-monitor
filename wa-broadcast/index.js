const { default: makeWASocket, useMultiFileAuthState, DisconnectReason } = require('@whiskeysockets/baileys');
const { Boom } = require('@hapi/boom');
const express = require('express');

const ALERT_RECIPIENTS = [
  '2349033094296@s.whatsapp.net',
  '2348028592387@s.whatsapp.net',
  '2348035053804@s.whatsapp.net',
  '2347036935000@s.whatsapp.net'
];

const PORT = 3000;
let sock;
let isConnected = false;

async function startSock() {
  const { state, saveCreds } = await useMultiFileAuthState('auth_info');
  sock = makeWASocket({
    auth: state,
    printQRInTerminal: false
  });

  sock.ev.on('creds.update', saveCreds);

  sock.ev.on('connection.update', (update) => {
    const { connection, lastDisconnect } = update;

    if (connection === 'close') {
      isConnected = false;
      const statusCode = new Boom(lastDisconnect?.error)?.output?.statusCode;
      const isLoggedOut = statusCode === DisconnectReason.loggedOut;

      console.log(`Connection dropped (Status Code: ${statusCode}). Reconnecting...`);

      if (!isLoggedOut) {
        setTimeout(startSock, 3000);
      } else {
        console.log('Logged out. Clear auth_info and re-pair.');
      }
    } else if (connection === 'open') {
      isConnected = true;
      console.log('SUCCESS: WhatsApp Alert Gateway Online & Connected!');
    }
  });
}

// Ensure connection is ready before sending
async function ensureConnected(timeoutMs = 15000) {
  const start = Date.now();
  while (!isConnected || !sock) {
    if (Date.now() - start > timeoutMs) {
      throw new Error('WhatsApp connection timeout - socket not ready');
    }
    await new Promise(r => setTimeout(r, 1000));
  }
}

async function broadcastAlert(message) {
  await ensureConnected();
  const results = [];
  for (const recipient of ALERT_RECIPIENTS) {
    try {
      await sock.sendMessage(recipient, { text: message });
      results.push({ recipient, status: 'sent' });
    } catch (err) {
      results.push({ recipient, status: 'failed', error: err.message });
    }
  }
  return results;
}

const app = express();
app.use(express.json());

app.post('/send-alert', async (req, res) => {
  const { message } = req.body;
  if (!message) return res.status(400).json({ error: 'Missing message parameter' });

  try {
    const results = await broadcastAlert(message);
    res.json({ ok: true, results });
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

app.listen(PORT, () => {
  console.log(`Alert listener online on http://localhost:${PORT}`);
  startSock();
});
