import { createTypeSafeAi } from '../packages/typesafe-ai/src/typesafe-ai-provider';

async function run() {
  console.log('--- Starting Unsafe Redirect PoC ---');

  // We target the Redirect Server (8091), which will redirect us to the Diagnostic Listener (8080)
  const provider = createTypeSafeAi({
    baseURL: 'http://localhost:8091',
    apiKey: 'redirect-test-token'
  });

  const model = provider.decisionModel('jev-latest');

  console.log('Sending request to Redirect Server (port 8091)...');
  try {
    await model.doDecide({
      questions: { q1: { type: 'boolean', criteria: {} } },
      state: {},
    });
  } catch (e) {
    // The request will likely fail with a 404 or error because the
    // diagnostic listener isn't a real TypeSafe AI API,
    // but the network trip is what matters.
    console.log('Request completed (expected failure at target).');
  }

  console.log('--- PoC Execution Finished ---');
}

run();
