const express = require('express');
const client = require('prom-client');
const jwt = require('jsonwebtoken');
const fs = require('fs');
const crypto = require('crypto');
const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3001;

// -- JWT signing key -------------------------------------------------------
// The key is never baked into the image or the repo. It's mounted from a
// Kubernetes Secret as a file (see charts/users/templates/deployment.yaml +
// scripts/rotate-jwt-key.sh). The key is read once at process startup, so a
// rotation only takes effect once a pod restarts and re-reads the mount —
// which is exactly what the rolling restart in the rotation script triggers.
const JWT_SECRET_PATH = process.env.JWT_SECRET_PATH || '/etc/jwt/jwt-secret';

let JWT_SECRET;
try {
  JWT_SECRET = fs.readFileSync(JWT_SECRET_PATH, 'utf8').trim();
} catch (err) {
  // Local/dev fallback only — never used when the Secret is actually mounted.
  JWT_SECRET = process.env.JWT_SECRET || 'dev-only-insecure-secret-do-not-use-in-prod';
  console.warn(`Could not read JWT secret from ${JWT_SECRET_PATH} (${err.message}). Falling back to env/dev default.`);
}

// Logs a fingerprint (never the key itself) so you can visually confirm a
// rotation happened by watching pod logs change after a rolling restart.
const keyFingerprint = crypto.createHash('sha256').update(JWT_SECRET).digest('hex').slice(0, 12);
console.log(`JWT signing key loaded — fingerprint: ${keyFingerprint}`);

// -- Prometheus metrics --------------------------------------------------
const register = new client.Registry();
client.collectDefaultMetrics({ register, prefix: 'users_' });

const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['service', 'method', 'route', 'status_code'],
  buckets: [0.01, 0.05, 0.1, 0.3, 0.5, 1, 2, 5]
});
const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['service', 'method', 'route', 'status_code']
});
register.registerMetric(httpRequestDuration);
register.registerMetric(httpRequestsTotal);

app.use((req, res, next) => {
  const end = httpRequestDuration.startTimer();
  res.on('finish', () => {
    const route = req.route ? req.route.path : req.path;
    const labels = { service: 'users', method: req.method, route, status_code: res.statusCode };
    end(labels);
    httpRequestsTotal.inc(labels);
  });
  next();
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});
// -------------------------------------------------------------------------

const users = [
  { id: 'u1', name: 'Alice Demo', email: 'alice@cloudcrafter.dev' },
  { id: 'u2', name: 'Bob Demo', email: 'bob@cloudcrafter.dev' }
];

// Task 5 demo change: a visible, trivial version marker. Bumping
// SERVICE_VERSION and pushing is the "one final update" that flows through
// CI -> new image -> chart version bump -> Argo CD sync -> new pods.
const SERVICE_VERSION = process.env.SERVICE_VERSION || '1.1.0';
app.get('/version', (req, res) => res.json({
  service: 'users',
  version: SERVICE_VERSION,
  gitSha: process.env.GIT_SHA || 'unknown',
  jwtKeyFingerprint: keyFingerprint
}));

app.get('/health', (req, res) => res.json({ status: 'ok', service: 'users', jwtKeyFingerprint: keyFingerprint }));

app.get('/users', (req, res) => res.json(users));

app.get('/users/:id', (req, res) => {
  const user = users.find(u => u.id === req.params.id);
  if (!user) return res.status(404).json({ error: 'not found' });
  res.json(user);
});

// -- Auth ------------------------------------------------------------------
// Demo login: trades a known userId for a signed JWT. In a real system this
// would check a password/credential; the point here is proving key rotation
// behavior, not building full auth.
app.post('/auth/login', (req, res) => {
  const { userId } = req.body || {};
  const user = users.find(u => u.id === userId);
  if (!user) return res.status(401).json({ error: 'invalid userId' });

  const token = jwt.sign(
    { sub: user.id, name: user.name },
    JWT_SECRET,
    { algorithm: 'HS256', expiresIn: '15m' }
  );

  res.json({ token, signedWithKeyFingerprint: keyFingerprint });
});

// Verifies a bearer token against THIS pod's currently loaded key.
// After a key rotation + rolling restart, tokens signed with the old key
// fail here with a clear "invalid signature" reason — that failure is the
// proof the rotation actually took effect, not just that a Secret changed.
app.get('/auth/verify', (req, res) => {
  const authHeader = req.headers.authorization || '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
  if (!token) return res.status(401).json({ valid: false, error: 'missing bearer token' });

  try {
    const decoded = jwt.verify(token, JWT_SECRET, { algorithms: ['HS256'] });
    res.json({ valid: true, decoded, verifiedWithKeyFingerprint: keyFingerprint });
  } catch (err) {
    res.status(401).json({ valid: false, error: err.message, verifiedWithKeyFingerprint: keyFingerprint });
  }
});
// -------------------------------------------------------------------------

app.listen(PORT, () => console.log(`users service listening on ${PORT}`));
