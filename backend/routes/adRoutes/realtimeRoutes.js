import express from 'express';

const router = express.Router();

// In-memory list of SSE clients
const sseClients = new Set();

// Broadcast helper
export function broadcastAdUpdate(update) {
  const data = JSON.stringify({
    type: 'ad_update',
    ...update,
    timestamp: new Date().toISOString(),
  });

  for (const client of sseClients) {
    try {
      client.res.write(`data: ${data}\n\n`);
    } catch (e) {
      sseClients.delete(client);
    }
  }
}

// SSE endpoint
router.get('/ws', (req, res) => {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    Connection: 'keep-alive',
    'Access-Control-Allow-Origin': '*',
  });

  const client = { id: Date.now() + Math.random(), res };
  sseClients.add(client);

  // initial message
  res.write(`data: ${JSON.stringify({ type: 'connected', clientId: client.id })}\n\n`);

  req.on('close', () => {
    sseClients.delete(client);
  });
});

export default router;


