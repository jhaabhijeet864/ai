import { streamText } from 'ai';
import { openai } from '@ai-sdk/openai'; // Assuming OpenAI, but can be any model
import { zombieTool } from './zombie-tool';

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
        const mem = process.memoryUsage();
        console.log(`Iteration ${i}: RSS = ${Math.round(mem.rss / 1024 / 1024)} MB`);
      }
    } catch (e) {
      // Abort errors are expected
    }
  }

  console.log('Completed iterations. If the server is still running, check memory usage.');
}

runReproduction().catch(console.error);
