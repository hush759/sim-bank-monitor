const { default: makeWASocket, useMultiFileAuthState, DisconnectReason } = require('@whiskeysockets/baileys');
const { Boom } = require('@hapi/boom');
const readline = require('readline');

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
const question = (text) => new Promise((resolve) => rl.question(text, resolve));

async function startPairing() {
  const { state, saveCreds } = await useMultiFileAuthState('auth_info');
  const sock = makeWASocket({
    auth: state,
    printQRInTerminal: false
  });

  sock.ev.on('creds.update', saveCreds);

  if (!sock.authState.creds.registered) {
    let number = await question('Enter the WhatsApp number to pair (intl format, no +, e.g. 2348012345678): ');
    number = number.trim().replace(/[^0-9]/g, '');
    rl.close();

    try {
      const code = await sock.requestPairingCode(number);
      console.log('\n==================================================');
      console.log(`  YOUR PAIRING CODE: ${code}`);
      console.log('==================================================\n');
      console.log(`On phone (${number}): WhatsApp > Settings > Linked Devices > Link a Device > Link with phone number instead`);
    } catch (err) {
      console.error('Error requesting code:', err.message);
      process.exit(1);
    }
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
