// receipt-notifier Lambda
//
// Trigger: S3 ObjectCreated event on the ticket-receipts bucket.
// Action: forwards the upload info to the Notifications service so a
//         notification fires automatically, with no manual step.

const http = require('http');
const { URL } = require('url');

const NOTIFICATIONS_URL = process.env.NOTIFICATIONS_URL || 'http://host.docker.internal:3004/notifications';

function postJson(urlString, payload) {
  return new Promise((resolve, reject) => {
    const url = new URL(urlString);
    const data = JSON.stringify(payload);

    const req = http.request(
      {
        hostname: url.hostname,
        port: url.port || 80,
        path: url.pathname,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(data)
        }
      },
      res => {
        let body = '';
        res.on('data', chunk => (body += chunk));
        res.on('end', () => resolve({ statusCode: res.statusCode, body }));
      }
    );

    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

exports.handler = async event => {
  console.log('Received S3 event:', JSON.stringify(event));

  const results = [];

  for (const record of event.Records || []) {
    const bucket = record.s3.bucket.name;
    const key = decodeURIComponent(record.s3.object.key.replace(/\+/g, ' '));

    // Receipts are expected to be named like: ticket-<ticketId>-receipt.<ext>
    const match = key.match(/ticket-([^-]+)-receipt/i);
    const ticketId = match ? match[1] : null;

    const payload = {
      bucket,
      key,
      ticketId,
      source: 'localstack-lambda',
      message: `Receipt "${key}" uploaded — ticket ${ticketId || '(unknown)'} purchase confirmed!`
    };

    try {
      const response = await postJson(NOTIFICATIONS_URL, payload);
      console.log('Forwarded to Notifications service:', response.statusCode, response.body);
      results.push({ key, forwarded: true, status: response.statusCode });
    } catch (err) {
      console.error('Failed to forward to Notifications service:', err.message);
      results.push({ key, forwarded: false, error: err.message });
    }
  }

  return { statusCode: 200, body: JSON.stringify({ processed: results.length, results }) };
};
