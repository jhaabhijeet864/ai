import { createTypeSafeAi } from '../packages/typesafe-ai/src/typesafe-ai-provider';

async function runRoutingVerification() {
  // 1. Define the custom evaluation base URL to track transport metrics
  const targetVerificationURL = 'http://localhost:8080'; // Update with your local listener or test hub

  // 2. Initialize the provider instance with custom runtime arguments
  const provider = createTypeSafeAi({
    baseURL: targetVerificationURL,
    apiKey: 'sandbox-verification-token', // Dummy token for baseline transport mapping
  });

  // 3. Resolve the configured interface model
  const model = provider.decisionModel('jev-latest');

  try {
    console.log(`[Diagnostic] Dispatching structured verification payload to: ${targetVerificationURL}/systemone`);
    
    // Execute the standard structural process loop
    const result = await model.doDecide({
      questions: {
        q1: { type: 'boolean', criteria: {} },
      },
      state: {},
    });

    console.log('[Diagnostic Success] Response received successfully from destination endpoint!');
    console.log('[Diagnostic Result]', JSON.stringify(result, null, 2));
  } catch (error: any) {
    if (error?.cause?.code === 'ECONNREFUSED' || error?.message?.includes('fetch failed')) {
      console.error(`\n[Diagnostic Warning] Connection refused at ${targetVerificationURL}.`);
      console.error('[Diagnostic Hint] Ensure the diagnostic listener is started in another terminal using:');
      console.error('                  node reproduce/diagnostic-listener.mjs\n');
    } else {
      console.log('[Diagnostic Log] Request dispatched.');
      console.log('[Diagnostic Info]', error?.message ?? error);
    }
  }
}

runRoutingVerification();

