#!/usr/bin/env node
/**
 * alexa-auth.js — One-time proxy-based Amazon Alexa authentication.
 *
 * Starts a local proxy on PORT (default 3456). Navigate to the proxy URL
 * in a browser, log in to Amazon, and the cookie is captured automatically
 * and saved to .instar/state/alexa-cookie.json.
 *
 * Usage:
 *   node alexa-auth.js [--port 3456]
 *
 * After auth completes, the cookie file is written and the process exits.
 */

const Alexa = require('alexa-remote2');
const path = require('path');
const fs = require('fs');

const PROXY_PORT = parseInt(process.env.ALEXA_PROXY_PORT || '3456', 10);
const PROXY_OWN_IP = process.env.ALEXA_PROXY_IP || 'localhost';
const COOKIE_FILE = path.resolve(__dirname, '../../.instar/state/alexa-cookie.json');
const STATE_DIR = path.dirname(COOKIE_FILE);

// Ensure state dir exists
if (!fs.existsSync(STATE_DIR)) {
  fs.mkdirSync(STATE_DIR, { recursive: true });
}

const alexa = new Alexa();

alexa.on('cookie', (cookie, csrf, macDms) => {
  const cookieData = alexa.cookieData || {};
  const state = {
    cookie,
    csrf,
    macDms,
    cookieData,
    savedAt: new Date().toISOString(),
  };
  fs.writeFileSync(COOKIE_FILE, JSON.stringify(state, null, 2));
  console.log(`\n✅ Alexa cookie saved to ${COOKIE_FILE}`);
  console.log('Authentication complete. You can close this process.');
  setTimeout(() => process.exit(0), 2000);
});

alexa.init(
  {
    proxyOnly: true,
    proxyOwnIp: PROXY_OWN_IP,
    proxyPort: PROXY_PORT,
    proxyLogLevel: 'warn',
    alexaServiceHost: 'pitangui.amazon.com', // US Amazon
    amazonPage: 'amazon.com',                // US login page (no www prefix)
    acceptLanguage: 'en-US,en;q=0.9',
    amazonPageProxyLanguage: 'en_US',        // default is de_DE — must override
    logger: (msg) => {
      if (msg && !msg.includes('body:')) console.log(msg);
    },
  },
  (err) => {
    if (err) {
      // proxyOnly mode: error here just means no existing cookie, proxy is running
      if (err.message && err.message.includes('proxy')) {
        console.log(`\n🔐 Alexa proxy running on port ${PROXY_PORT}`);
        console.log(`Open this URL in a browser to authenticate:`);
        console.log(`  http://${PROXY_OWN_IP}:${PROXY_PORT}`);
        console.log('\nWaiting for authentication...');
        return;
      }
    }
    console.log(`\n🔐 Alexa proxy running on port ${PROXY_PORT}`);
    console.log(`Open this URL in a browser to authenticate:`);
    console.log(`  http://${PROXY_OWN_IP}:${PROXY_PORT}`);
    console.log('\nWaiting for authentication...');
  }
);
