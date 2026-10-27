// Firebase Cloud Messaging push. Optional: works only if a service account is configured.
let messaging = null;

function init() {
  const path = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!path) {
    console.log('[push] FIREBASE_SERVICE_ACCOUNT not set - push disabled');
    return;
  }
  try {
    const admin = require('firebase-admin');
    admin.initializeApp({ credential: admin.credential.cert(require(require('path').resolve(path))) });
    messaging = admin.messaging();
    console.log('[push] Firebase initialised');
  } catch (e) {
    console.error('[push] init failed:', e.message);
  }
}

async function sendCallPush(token, { callId, fromPhone }) {
  if (!messaging || !token) return false;
  try {
    await messaging.send({
      token,
      data: { type: 'incoming_call', callId, fromPhone },
      android: { priority: 'high' },
      apns: { headers: { 'apns-priority': '10' }, payload: { aps: { 'content-available': 1 } } },
    });
    return true;
  } catch (e) {
    console.error('[push] send failed:', e.message);
    return false;
  }
}

module.exports = { init, sendCallPush };
