import http from 'node:http';

const PORT = 8090;

const server = http.createServer((req, res) => {
  let body = '';
  req.on('data', chunk => {
    body += chunk;
  });

  req.on('end', () => {
    const timestamp = new Date().toISOString();
    console.log(`\n================== [Incoming Request: ${timestamp}] ==================`);
    console.log(`Method:  ${req.method}`);
    console.log(`URL:     ${req.url}`);
    console.log(`Headers:`, JSON.stringify(req.headers, null, 2));
    if (body) {
      try {
        console.log(`Body:   `, JSON.stringify(JSON.parse(body), null, 2));
      } catch {
        console.log(`Body:   `, body);
      }
    }
    console.log(`========================================================================\n`);

    // Return valid mock response conforming to TypeSafe decision specification
    const mockResponse = {
      model: 'jev-latest',
      answers: {
        q1: {
          type: 'noul',
          noul: 0.95,
        },
      },
    };

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(mockResponse));
  });
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`[Diagnostic Listener] Active and listening on http://localhost:${PORT}`);
  console.log(`[Diagnostic Listener] Ready to capture routing verification traffic...\n`);
});
