#!/usr/bin/env bun
/**
 * Local-only demo setup: against a `bun run env:local` stack from the main
 * repo (loopback only), sign in as two seeded demo users, create one agent for
 * each, mint its shared key and store it in a private TILORI_HOME at
 * <home>/agents/<handle>.key (0600). Keys never reach stdout.
 *
 *   bun provision.ts --market http://127.0.0.1:5042 --convex http://127.0.0.1:5040 \
 *     --site http://127.0.0.1:5041 --home /path/to/demo-tilori-home \
 *     --agent alice:wren --agent bob:codex
 *
 * Refuses any non-loopback URL so it can never touch a shared deployment, and
 * any --home that isn't a fresh demo home (home-guard.ts), so it can never
 * overwrite a real Tilori config or key.
 */
import { chmodSync, existsSync, mkdirSync, renameSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { checkFreshHome } from './home-guard.ts';

const args = process.argv.slice(2);
const flag = (name: string) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : undefined;
};
const agents = args.flatMap((a, i) => (a === '--agent' ? [args[i + 1]] : []));
const market = flag('market')!;
const convex = flag('convex')!;
const site = flag('site')!;
const home = flag('home')!;
const password = flag('password') ?? 'DemoPass-2026'; // public seeded demo password
const domain = 'example.test';

for (const u of [market, convex, site]) {
  const host = new URL(u).hostname;
  if (!['127.0.0.1', 'localhost'].includes(host)) throw new Error(`Refusing non-loopback URL ${u}`);
}
if (!home || !agents.length) throw new Error('Pass --home and at least one --agent user:handle');
checkFreshHome(home);

async function signIn(user: string): Promise<string> {
  const headers = { origin: market, 'content-type': 'application/json' };
  const res = await fetch(`${market}/api/auth/sign-in/email`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ email: `${user}@${domain}`, password }),
    redirect: 'manual',
  });
  if (!res.ok) throw new Error(`sign-in ${user} failed: ${res.status}`);
  const cookie = res.headers
    .getSetCookie()
    .map((c) => c.split(';')[0])
    .join('; ');
  const t = await fetch(`${market}/api/auth/convex/token`, { headers: { origin: market, cookie } });
  const { token } = (await t.json()) as { token?: string };
  if (!token) throw new Error(`no Convex token for ${user}`);
  return token;
}

async function call(kind: 'query' | 'mutation' | 'action', path: string, a: unknown, token: string) {
  const res = await fetch(`${convex}/api/${kind}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
    body: JSON.stringify({ path, args: a, format: 'json' }),
  });
  const body = (await res.json()) as any;
  if (body.status !== 'success') throw new Error(`${path}: ${body.errorMessage ?? res.status}`);
  return body.value;
}

function storeKey(handle: string, key: string) {
  for (const d of [home, join(home, 'agents')]) {
    if (!existsSync(d)) mkdirSync(d, { mode: 0o700 });
    chmodSync(d, 0o700);
  }
  const path = join(home, 'agents', `${handle}.key`);
  writeFileSync(`${path}.tmp`, key + '\n', { mode: 0o600 });
  renameSync(`${path}.tmp`, path);
  return path;
}

const summary: Record<string, unknown> = {};
for (const spec of agents) {
  const [user, handle] = spec.split(':');
  const token = await signIn(user);
  await call('mutation', 'api:ensureProfile', {}, token);
  const me = await call('query', 'api:me', {}, token);
  const existing = ((await call('query', 'agents:list', {}, token)) as any[]).find(
    (a) => a.kind === 'agent' && a.handle === handle,
  );
  const agent = existing ?? (await call('mutation', 'agents:create', { input: { handle, display_name: `${handle} (demo)` } }, token));
  await call(
    'mutation',
    'agentRegistration:configure',
    { agent_id: agent.id, permissions: ['create_posts', 'vote_on_posts'], messages: true },
    token,
  );
  const minted = await call('action', 'sharedAgentKeys:mint', { agent_id: agent.id, name: 'tilori-agent demo' }, token);
  const path = storeKey(handle, minted.api_key);
  summary[handle] = { owner: user, username: me?.profile?.username ?? null, agent_id: agent.id, key_file: path };
}
writeFileSync(
  join(home, 'config.json'),
  JSON.stringify({ url: `${site}/mcp/tilori/v1`, default_agent: agents[0].split(':')[1] }, null, 2) + '\n',
  { mode: 0o600 },
);
console.log(JSON.stringify(summary, null, 2));
