const express = require('express');
const client = require('prom-client');
const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3004;

// In-memory store just for demo/verification purposes.
const notifications = [];

// -- Prometheus metrics --------------------------------------------------
const register = new client.Registry();
client.collectDefaultMetrics({ register, prefix: 'notifications_' });

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
const notificationsFiredTotal = new client.Counter({
  name: 'notifications_fired_total',
  help: 'Total number of notifications fired (from the S3->Lambda event flow or direct calls)',
  labelNames: ['source']
});
register.registerMetric(httpRequestDuration);
register.registerMetric(httpRequestsTotal);
register.registerMetric(notificationsFiredTotal);

app.use((req, res, next) => {
  const end = httpRequestDuration.startTimer();
  res.on('finish', () => {
    const route = req.route ? req.route.path : req.path;
    const labels = { service: 'notifications', method: req.method, route, status_code: res.statusCode };
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

const SERVICE_VERSION = process.env.SERVICE_VERSION || '1.1.0';
app.get('/version', (req, res) => res.json({
  service: 'notifications',
  version: SERVICE_VERSION,
  gitSha: process.env.GIT_SHA || 'unknown'
}));

app.get('/health', (req, res) => res.json({ status: 'ok', service: 'notifications' }));

// Called by the Lambda function (Part B) whenever a receipt lands in S3.
app.post('/notifications', (req, res) => {
  const { bucket, key, ticketId, message, source } = req.body || {};

  if (!key) {
    return res.status(400).json({ error: 'missing "key" (uploaded object key) in payload' });
  }

  const notification = {
    id: `n${notifications.length + 1}`,
    bucket: bucket || 'unknown',
    key,
    ticketId: ticketId || null,
    message: message || `Receipt ${key} received — your ticket purchase is confirmed!`,
    source: source || 'unknown',
    receivedAt: new Date().toISOString()
  };

  notifications.push(notification);
  notificationsFiredTotal.inc({ source: notification.source });
  console.log('Notification fired:', JSON.stringify(notification));
  res.status(201).json(notification);
});

// Lets you prove, end to end, that the event-driven flow worked.
app.get('/notifications', (req, res) => res.json(notifications));

app.listen(PORT, () => console.log(`notifications service listening on ${PORT}`));
