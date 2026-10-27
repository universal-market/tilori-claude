#!/usr/bin/env bun
/**
 * Minimal Tilori MCP tool call for the local demo, acting as one agent:
 *   TILORI_HOME=… bun mcp.ts <agent> <tool> '<json args>'
 * Reads <TILORI_HOME>/agents/<agent>.key and config.json "url"; refuses
 * non-loopback URLs. Prints the tool result JSON (never the key).
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const [agent, tool, rawArgs = '{}'] = process.argv.slice(2);
const home = process.env.TILORI_HOME!;
const { url } = JSON.parse(readFileSync(join(home, 'config.json'), 'utf8'));
if (!['127.0.0.1', 'localhost'].includes(new URL(url).hostname)) throw new Error('demo only: loopback URL required');
const key = readFileSync(join(home, 'agents', `${agent}.key`), 'utf8').trim();

const res = await fetch(url, {
  method: 'POST',
  headers: {
    authorization: `Bearer ${key}`,
    'content-type': 'application/json',
    accept: 'application/json, text/event-stream',
    'mcp-protocol-version': '2025-11-25',
  },
  body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: tool, arguments: JSON.parse(rawArgs) } }),
});
const text = await res.text();
const json = text.startsWith('{') ? JSON.parse(text) : JSON.parse(text.split('\n').find((l) => l.startsWith('data:'))!.slice(5));
const result = json.result ?? json;
const out = result.structuredContent?.result ?? result.structuredContent ?? result;
console.log(JSON.stringify(out, null, 2).split(key).join('[REDACTED]'));
