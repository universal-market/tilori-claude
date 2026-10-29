/**
 * provision.ts writes config.json and agents/<handle>.key into --home. Pointed
 * at a real Tilori home it would overwrite the user's own config and keys, as
 * a test did on 2026-10-29 (UNI-457). So it takes only a fresh demo home: one
 * with no config.json and no agents/, which is not the user's real config dir.
 */
import { lstatSync, realpathSync } from 'node:fs';
import { userInfo } from 'node:os';
import { basename, dirname, join, resolve } from 'node:path';

/** realpath of p, or of its nearest existing ancestor plus the rest. */
const real = (p: string): string => {
  try {
    return realpathSync(p);
  } catch {}
  const parent = dirname(p);
  return parent === p ? p : join(real(parent), basename(p));
};

/** The home dir from the password database, so a faked $HOME can't hide the
 * real config dir (Bun's os.userInfo().homedir follows $HOME). */
function passwdHome(): string | undefined {
  const ask = (argv: string[]) => {
    try {
      const r = Bun.spawnSync(argv, { env: { PATH: '/usr/bin:/bin' }, stderr: 'ignore' });
      return r.exitCode === 0 ? r.stdout.toString() : '';
    } catch {
      return '';
    }
  };
  const uid = process.getuid?.();
  const home =
    (uid === undefined ? '' : ask(['getent', 'passwd', String(uid)]).split(':')[5]?.trim()) ||
    ask(['dscl', '.', '-read', `/Users/${userInfo().username}`, 'NFSHomeDirectory'])
      .replace(/^NFSHomeDirectory:\s*/, '')
      .trim();
  return home?.startsWith('/') ? home : undefined;
}

/** Throws unless `home` is a fresh demo home. Call before any request. */
export function checkFreshHome(home: string) {
  const dir = real(resolve(home));
  const pw = passwdHome();
  if (pw && dir === real(join(pw, '.config', 'tilori')))
    throw new Error(`Refusing --home ${home}: it is your real Tilori config dir.`);
  // lstat, so a dangling symlink counts too: writing through it would create
  // its target.
  const present = (p: string) => {
    try {
      lstatSync(p);
      return true;
    } catch {
      return false;
    }
  };
  for (const f of ['config.json', 'agents'])
    if (present(join(dir, f)))
      throw new Error(`Refusing --home ${home}: it already has ${f}; provision only builds a fresh demo home.`);
}
