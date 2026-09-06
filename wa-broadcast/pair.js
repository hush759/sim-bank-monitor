const { default: makeWASocket, useMultiFileAuthState, DisconnectReason } = require('@whiskeysockets/baileys');
const { Boom } = require('@hapi/boom');

async function startPairing() {
  const { state, saveCreds } = await useMultiFileAuthState('auth_info');
  const sock = makeWASocket({
    auth: state,
    printQRInTerminal: false
  });

  sock.ev.on('creds.update', saveCreds);

  if (!sock.authState.creds.registered) {
    const number = '2349131382030';
    setTimeout(async () => {
      try {
        const code = await sock.requestPairingCode(number);
        console.log('\n==================================================');
        console.log(`  YOUR PAIRING CODE: ${code}`);
        console.log('==================================================\n');
        console.log('On phone (09131382030): WhatsApp > Settings > Linked Devices > Link with phone number');
      } catch (err) {
        console.error('Error requesting code:', err.message);
      }
    }, 2000);
  }

  sock.ev.on('connection.update', (update) => {
    const { connection, lastDisconnect } = update;

    if (connection === 'close') {
      const statusCode = new Boom(lastDisconnect?.error)?.output?.statusCode;
      const isLoggedOut = statusCode === DisconnectReason.loggedOut;

      if (!isLoggedOut) {
        console.log('Restarting connection to finalize pairing...');
        startPairing();
      } else {
        console.log('Logged out.');
      }
    } else if (connection === 'open') {
      console.log('\n==================================================');
      console.log('  SUCCESS: WhatsApp Linked and Online!');
      console.log('==================================================\n');
      process.exit(0);
    }
  });
}

startPairing();
