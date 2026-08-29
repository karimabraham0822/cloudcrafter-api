const express = require('express');
const client = require('prom-client');
const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3003;

// -- Prometheus metrics --------------------------------------------------
const register = new client.Registry();
client.collectDefaultMetrics({ register, prefix: 'tickets_' });

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
    const labels = { service: 'tickets', method: req.method, route, status_code: res.statusCode };
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

const tickets = [
  { id: 't1', userId: 'u1', eventId: 'e1', status: 'confirmed' },
  { id: 't2', userId: 'u2', eventId: 'e2', status: 'confirmed' }
];

const SERVICE_VERSION = process.env.SERVICE_VERSION || '1.1.0';
app.get('/version', (req, res) => res.json({
  service: 'tickets',
  version: SERVICE_VERSION,
  gitSha: process.env.GIT_SHA || 'unknown'
}));

app.get('/health', (req, res) => res.json({ status: 'ok', service: 'tickets' }));

app.get('/tickets', (req, res) => res.json(tickets));

app.get('/tickets/:id', (req, res) => {
  const ticket = tickets.find(t => t.id === req.params.id);
  if (!ticket) return res.status(404).json({ error: 'not found' });
  res.json(ticket);
});

// Informational endpoint: real receipt files are uploaded directly to the
// LocalStack S3 bucket (see scripts/upload-receipt.sh), which is what
// actually triggers the Lambda -> Notifications flow in Part B.
app.get('/tickets/:id/receipt-status', (req, res) => {
  const ticket = tickets.find(t => t.id === req.params.id);
  if (!ticket) return res.status(404).json({ error: 'not found' });
  res.json({ ticketId: ticket.id, receiptFlow: 'upload to s3://ticket-receipts/ to trigger notification' });
});

app.listen(PORT, () => console.log(`tickets service listening on ${PORT}`));
