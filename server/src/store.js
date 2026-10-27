// In-memory store. Replace with PostgreSQL/Redis before production (see PLAN.md, step 5).
const crypto = require('crypto');

const otps = new Map();      // phone -> { code, expires, attempts }
const users = new Map();     // phone -> { phone, hash, fcmToken }
const hashIndex = new Map(); // sha256(phone) -> phone
const sockets = new Map();   // phone -> socket id

function sha256(s) {
  return crypto.createHash('sha256').update(s).digest('hex');
}

// Normalize to digits only; Bangladesh: 01XXXXXXXXX -> 8801XXXXXXXXX
function normalizePhone(raw, defaultCountry = '880') {
  let d = String(raw || '').replace(/[^\d]/g, '');
  if (d.startsWith('00')) d = d.slice(2);
  if (d.startsWith('0')) d = defaultCountry + d.slice(1);
  if (d.length < 8 || d.length > 15) return null;
  return d;
}

function upsertUser(phone) {
  let u = users.get(phone);
  if (!u) {
    u = { phone, hash: sha256(phone), fcmToken: null };
    users.set(phone, u);
    hashIndex.set(u.hash, phone);
  }
  return u;
}

module.exports = { otps, users, hashIndex, sockets, sha256, normalizePhone, upsertUser };
