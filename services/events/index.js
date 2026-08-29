const express = require('express');
const client = require('prom-client');
const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3002;

// -- Prometheus metrics --------------------------------------------------
const register = new client.Registry();
client.collectDefaultMetrics({ register, prefix: 'events_' });

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
    const labels = { service: 'events', method: req.method, route, status_code: res.statusCode };
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

const events = [
  { id: 'e1', name: 'Indie Rock Night', venue: 'The Loft', date: '2026-09-12' },
  { id: 'e2', name: 'City Marathon Finish Concert', venue: 'Downtown Square', date: '2026-10-03' }
];

const SERVICE_VERSION = process.env.SERVICE_VERSION || '1.1.0';
app.get('/version', (req, res) => res.json({
  service: 'events',
  version: SERVICE_VERSION,
  gitSha: process.env.GIT_SHA || 'unknown'
}));

app.get('/health', (req, res) => res.json({ status: 'ok', service: 'events' }));

app.get('/events', (req, res) => res.json(events));

app.get('/events/:id', (req, res) => {
  const event = events.find(e => e.id === req.params.id);
  if (!event) return res.status(404).json({ error: 'not found' });
  res.json(event);
});

app.listen(PORT, () => console.log(`events service listening on ${PORT}`));
