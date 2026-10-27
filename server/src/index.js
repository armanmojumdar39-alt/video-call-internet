require('dotenv').config();
const http = require('http');
const crypto = require('crypto');
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const jwt = require('jsonwebtoken');
const { Server } = require('socket.io');

const store = require('./store');
const { sendSms } = require('./sms');
const push = require('./push');

const PORT = process.env.PORT || 3000;
const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret-change-me';
if (!process.env.JWT_SECRET) console.warn('[warn] JWT_SECRET not set, using insecure dev secret');

// OTP_MODE=sms (default, secure) | off (no SMS; anyone can claim any number - private/family use only)
const OTP_ON = (process.env.OTP_MODE || 'sms') !== 'off';
if (!OTP_ON) console.warn('[warn] OTP_MODE=off: phone numbers are NOT verified. Use only for private testing.');

push.init();

const app = express();
app.use(helmet());
app.use(cors());
app.use(express.json({ limit: '2mb' }));

const otpLimiter = rateLimit({ windowMs: 10 * 60 * 1000, max: OTP_ON ? 5 : 30, standardHeaders: true });
const generalLimiter = rateLimit({ windowMs: 60 * 1000, max: 60, standardHeaders: true });
app.use(generalLimiter);

function auth(req, res, next) {
  const h = req.headers.authorization || '';
  try {
    req.user = jwt.verify(h.replace('Bearer ', ''), JWT_SECRET);
    store.upsertUser(req.user.phone); // re-register after server restart (store is in-memory)
    next();
  } catch {
    res.status(401).json({ error: 'unauthorized' });
  }
}

app.get('/health', (_req, res) => res.json({ ok: true }));
app.get('/config', (_req, res) => res.json({ otpRequired: OTP_ON }));

// 1) Request OTP
app.post('/auth/request-otp', otpLimiter, async (req, res) => {
  const phone = store.normalizePhone(req.body.phone);
  if (!phone) return res.status(400).json({ error: 'invalid phone' });
  if (!OTP_ON) return res.json({ ok: true, phone });
  const code = String(crypto.randomInt(100000, 1000000));
  store.otps.set(phone, { code, expires: Date.now() + 5 * 60 * 1000, attempts: 0 });
  try {
    await sendSms(phone, `Connecto code: ${code}`);
    res.json({ ok: true, phone });
  } catch (e) {
    console.error(e.message);
    res.status(500).json({ error: 'sms failed' });
  }
});

// 2) Verify OTP -> JWT
app.post('/auth/verify-otp', otpLimiter, (req, res) => {
  const phone = store.normalizePhone(req.body.phone);
  if (!phone) return res.status(400).json({ error: 'invalid phone' });
  if (OTP_ON) {
    const rec = store.otps.get(phone);
    if (!rec || rec.expires < Date.now()) return res.status(400).json({ error: 'code expired' });
    if (++rec.attempts > 5) {
      store.otps.delete(phone);
      return res.status(429).json({ error: 'too many attempts' });
    }
    if (String(req.body.code) !== rec.code) return res.status(400).json({ error: 'wrong code' });
    store.otps.delete(phone);
  }
  store.upsertUser(phone);
  const token = jwt.sign({ phone }, JWT_SECRET, { expiresIn: '90d' });
  res.json({ token, phone });
});

app.post('/me/fcm-token', auth, (req, res) => {
  const u = store.upsertUser(req.user.phone);
  u.fcmToken = req.body.token || null;
  res.json({ ok: true });
});

// 3) Contact match: client sends sha256 hashes, server returns which are registered.
app.post('/contacts/match', auth, rateLimit({ windowMs: 60 * 1000, max: 10 }), (req, res) => {
  const hashes = Array.isArray(req.body.hashes) ? req.body.hashes.slice(0, 5000) : [];
  const matched = hashes.filter((h) => store.hashIndex.has(h));
  res.json({ matched });
});

// 4) ICE servers. TURN is what makes calls work over mobile data / strict NAT.
// Option A (easiest, free tier): METERED_APP + METERED_API_KEY from metered.ca (Open Relay)
// Option B: your own coturn via TURN_URL + TURN_SECRET
let meteredCache = { at: 0, servers: null };
async function meteredServers() {
  const { METERED_APP, METERED_API_KEY } = process.env;
  if (!METERED_APP || !METERED_API_KEY) return null;
  if (meteredCache.servers && Date.now() - meteredCache.at < 30 * 60 * 1000) return meteredCache.servers;
  try {
    const r = await fetch(`https://${METERED_APP}.metered.live/api/v1/turn/credentials?apiKey=${METERED_API_KEY}`);
    if (!r.ok) throw new Error('status ' + r.status);
    meteredCache = { at: Date.now(), servers: await r.json() };
    return meteredCache.servers;
  } catch (e) {
    console.error('[ice] metered failed:', e.message);
    return meteredCache.servers; // stale is better than none
  }
}

app.get('/ice', auth, async (req, res) => {
  const servers = [{ urls: 'stun:stun.l.google.com:19302' }, { urls: 'stun:stun1.l.google.com:19302' }];
  const metered = await meteredServers();
  if (metered) servers.push(...metered);
  if (process.env.TURN_URL && process.env.TURN_SECRET) {
    const expiry = Math.floor(Date.now() / 1000) + 3600;
    const username = `${expiry}:${req.user.phone}`;
    const credential = crypto.createHmac('sha1', process.env.TURN_SECRET).update(username).digest('base64');
    servers.push({ urls: process.env.TURN_URL, username, credential });
  }
  res.json({ iceServers: servers, hasTurn: servers.length > 2 });
});

// ---- Signaling ----
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: '*' } });

const calls = new Map(); // callId -> { from, to, state, timer }

io.use((socket, next) => {
  try {
    socket.data.phone = jwt.verify(socket.handshake.auth.token, JWT_SECRET).phone;
    next();
  } catch {
    next(new Error('unauthorized'));
  }
});

function emitTo(phone, event, payload) {
  const sid = store.sockets.get(phone);
  if (sid) io.to(sid).emit(event, payload);
  return !!sid;
}

function endCall(callId, reason, notifyBoth = true) {
  const c = calls.get(callId);
  if (!c) return;
  clearTimeout(c.timer);
  calls.delete(callId);
  if (notifyBoth) {
    emitTo(c.from, 'call:ended', { callId, reason });
    emitTo(c.to, 'call:ended', { callId, reason });
  }
}

io.on('connection', (socket) => {
  const me = socket.data.phone;
  store.upsertUser(me);
  store.sockets.set(me, socket.id);

  // Deliver a ringing call that arrived while we were offline (via push tap)
  for (const [callId, c] of calls) {
    if (c.to === me && c.state === 'ringing') socket.emit('call:incoming', { callId, from: c.from });
  }

  socket.on('call:invite', async ({ to }, ack) => {
    const callee = store.normalizePhone(to);
    if (!callee || callee === me) return ack?.({ error: 'invalid' });
    const user = store.users.get(callee);
    if (!user) return ack?.({ error: 'not_registered' });
    for (const c of calls.values()) {
      if (c.to === callee || c.from === callee) return ack?.({ error: 'busy' });
    }
    const callId = crypto.randomUUID();
    const timer = setTimeout(() => endCall(callId, 'no_answer'), 45000);
    calls.set(callId, { from: me, to: callee, state: 'ringing', timer });
    const online = emitTo(callee, 'call:incoming', { callId, from: me });
    if (!online) await push.sendCallPush(user.fcmToken, { callId, fromPhone: me });
    ack?.({ callId, online });
  });

  socket.on('call:accept', ({ callId }) => {
    const c = calls.get(callId);
    if (!c || c.to !== me) return;
    clearTimeout(c.timer);
    c.state = 'active';
    emitTo(c.from, 'call:accepted', { callId });
  });

  socket.on('call:reject', ({ callId }) => {
    const c = calls.get(callId);
    if (c && c.to === me) endCall(callId, 'rejected');
  });

  socket.on('call:end', ({ callId }) => {
    const c = calls.get(callId);
    if (c && (c.from === me || c.to === me)) endCall(callId, 'ended');
  });

  // Relay WebRTC offer/answer/ICE to the other party
  socket.on('signal', ({ callId, data }) => {
    const c = calls.get(callId);
    if (!c || (c.from !== me && c.to !== me)) return;
    emitTo(c.from === me ? c.to : c.from, 'signal', { callId, data });
  });

  socket.on('disconnect', () => {
    if (store.sockets.get(me) === socket.id) store.sockets.delete(me);
    for (const [callId, c] of calls) {
      if (c.state === 'active' && (c.from === me || c.to === me)) endCall(callId, 'disconnected');
    }
  });
});

server.listen(PORT, () => console.log(`Connecto server listening on :${PORT}`));
