import { streamText } from 'ai';
import { openai } from '@ai-sdk/openai'; // Assuming OpenAI, but can be any model
import { zombieTool } from './zombie-tool';
import { NodeTracerProvider } from '@opentelemetry/sdk-trace-node';
import {
  SimpleSpanProcessor,
  InMemorySpanExporter,
} from '@opentelemetry/sdk-trace-base';

// OpenTelemetry Setup to track unclosed spans
const exporter = new InMemorySpanExporter();
const provider = new NodeTracerProvider();
provider.addSpanProcessor(new SimpleSpanProcessor(exporter));
provider.register();

function logMemorySnapshot(label: string) {
  const mem = process.memoryUsage();
  const toMB = (bytes: number) => (bytes / 1024 / 1024).toFixed(2);

  console.log(`[Memory - ${label}]`);
  console.log(`  Heap Used:  ${toMB(mem.heapUsed)} MB`);
  console.log(`  Heap Total: ${toMB(mem.heapTotal)} MB`);
  console.log(`  RSS:        ${toMB(mem.rss)} MB`);
  console.log(`  External:   ${toMB(mem.external)} MB`);
}

async function runReproduction() {
  const ITERATIONS = 500;
  console.log(`Starting reproduction: ${ITERATIONS} iterations of aborted zombie tool calls...`);

  for (let i = 0; i < ITERATIONS; i++) {
    const controller = new AbortController();

    try {
      // We trigger streamText. We ask the model specifically to use the zombie tool.
      const result = streamText({
        model: openai('gpt-4o'),
        tools: {
          zombie: zombieTool,
        },
        prompt: 'Please call the zombie tool immediately.',
        abortSignal: controller.signal,
      });

      // We don't await the stream to finish.
      // Instead, we immediately abort the connection.
      // This mimics a client disconnecting as soon as the tool execution is triggered.
      controller.abort();

      if (i % 50 === 0) {
        logMemorySnapshot(`Iteration ${i}`);
        console.log(`  Finished Spans: ${exporter.getFinishedSpans().length}`);
      }
    } catch (e) {
      // Abort errors are expected
    }
  }

  console.log('Completed iterations. If the server is still running, check memory usage.');
  logMemorySnapshot('Final');
  console.log(`Final Finished Spans: ${exporter.getFinishedSpans().length}`);
  console.log(`Expected Spans (approx): ${ITERATIONS * 2}`);
}

runReproduction().catch(console.error);
