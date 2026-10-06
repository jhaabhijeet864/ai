import http from 'http';

const PORT = 8091;
const REDIRECT_TARGET = 'http://localhost:8090/systemone';

const server = http.createServer((req, res) => {
  console.log(`[Redirect Server] Received request for: ${req.url}`);
  console.log(`[Redirect Server] Redirecting to: ${REDIRECT_TARGET}`);

  res.writeHead(302, { 'Location': REDIRECT_TARGET });
  res.end();
});

server.listen(PORT, () => {
  console.log(`🚀 Redirect Server running on http://localhost:${PORT}`);
  console.log(`🔗 Redirecting all requests to ${REDIRECT_TARGET}`);
});
