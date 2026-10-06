import { z } from 'zod';
import type { Tool } from 'ai';

export const zombieTool: Tool = {
  description: 'A tool that never finishes and ignores abort signals',
  parameters: z.object({}),
  execute: async ({ abortSignal }: { abortSignal: AbortSignal }) => {
    console.log('Zombie Tool: Execution started. I will ignore the abort signal...');

    // To prove the leak, we create a promise that never resolves.
    // Even if the client aborts the stream, this promise stays in the Node.js
    // event loop, keeping the entire closure (and the request context) in memory.
    return new Promise(() => {
      // This never calls resolve() or reject()
    });
  },
};
