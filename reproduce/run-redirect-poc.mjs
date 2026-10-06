import { spawn } from 'child_process';
import path from 'path';

async function run() {
  console.log('Starting PoC Environment...');

  const listener = spawn('node', ['reproduce/diagnostic-listener.mjs']);
  const redirectServer = spawn('node', ['reproduce/redirect-server.mjs']);

  listener.stdout.on('data', (data) => console.log(`[LISTENER] ${data}`));
  listener.stderr.on('data', (data) => console.error(`[LISTENER ERR] ${data}`));
  redirectServer.stdout.on('data', (data) => console.log(`[REDIRECT] ${data}`));
  redirectServer.stderr.on('data', (data) => console.error(`[REDIRECT ERR] ${data}`));

  await new Promise(r => setTimeout(r, 2000));

  console.log('Executing Exploit...');
  // Using shell: true to ensure npx is found in the path
  const exploit = spawn('npx tsx reproduce/verify-redirect.ts', { shell: true });
  exploit.stdout.on('data', (data) => console.log(`[EXPLOIT] ${data}`));
  exploit.stderr.on('data', (data) => console.error(`[EXPLOIT ERR] ${data}`));

  await new Promise((resolve) => {
    exploit.on('close', resolve);
  });

  console.log('Cleaning up...');
  listener.kill();
  redirectServer.kill();
}

run();
