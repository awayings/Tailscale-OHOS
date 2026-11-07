import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const projectRoot = fileURLToPath(new URL('..', import.meta.url));
const etsRoot = join(projectRoot, 'entry/src/main/ets');
const scriptsRoot = join(projectRoot, 'scripts');
const appJson5 = readFileSync(join(projectRoot, 'AppScope/app.json5'), 'utf8');
const configuredName = /"bundleName"\s*:\s*"([^"]+)"/.exec(appJson5)?.[1] ?? '';

function filesUnder(dir, extension) {
  const result = [];
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) {
      result.push(...filesUnder(path, extension));
    } else if (path.endsWith(extension)) {
      result.push(path);
    }
  }
  return result;
}

function read(relativePath) {
  return readFileSync(join(projectRoot, relativePath), 'utf8');
}

test('app.json5 declares a bundle name', () => {
  assert.match(configuredName, /^[a-zA-Z][a-zA-Z0-9_.]+$/);
});

test('runtime fallback stays in sync with app.json5', () => {
  const source = read('entry/src/main/ets/services/AppIdentity.ets');
  const fallback = /FALLBACK_BUNDLE_NAME:\s*string\s*=\s*'([^']+)'/.exec(source)?.[1];
  assert.equal(fallback, configuredName,
    'AppIdentity fallback must match AppScope/app.json5 (rename both together)');
});

test('ArkTS sources never hard-code a bundle name outside AppIdentity', () => {
  const bundleLiteral = /['"](io\.github\.tailscale[a-zA-Z0-9_.]*)['"]/g;
  for (const path of filesUnder(etsRoot, '.ets')) {
    const name = relative(projectRoot, path);
    if (name.endsWith('services/AppIdentity.ets')) {
      continue;
    }
    const stale = [...readFileSync(path, 'utf8').matchAll(bundleLiteral)]
      .map(match => match[1]);
    assert.deepEqual(stale, [], `${name} hard-codes ${stale.join(', ')}; use AppIdentity.bundleName()`);
  }
});

test('VPN routing uses the runtime bundle identity', () => {
  const vpnExtension = read('entry/src/main/ets/vpnextensionability/TailscaleVpnExtensionAbility.ets');
  const bridgeStatus = read('entry/src/main/ets/components/BridgeStatus.ets');
  assert.match(vpnExtension, /trustedApplications:\s*\[AppIdentity\.bundleName\(\)\]/);
  assert.match(vpnExtension, /blockedApplications:\s*\[AppIdentity\.bundleName\(\)\]/);
  assert.match(bridgeStatus, /bundleName:\s*AppIdentity\.bundleName\(\)/);
});

test('device probe scripts derive the bundle name from app.json5', () => {
  const probes = filesUnder(scriptsRoot, '.ps1').filter(path =>
    path.endsWith('device-') || path.includes('device-'));
  const bundleProbes = filesUnder(scriptsRoot, '.ps1').filter(path =>
    readFileSync(path, 'utf8').includes('$bundleName'));
  assert.ok(bundleProbes.length > 0);
  for (const path of bundleProbes) {
    const name = relative(projectRoot, path);
    const source = readFileSync(path, 'utf8');
    assert.ok(!source.includes('io.github.tailscaleohos'),
      `${name} still points at the upstream bundle name`);
    assert.match(source, /AppScope[\\/]app\.json5/,
      `${name} must read the bundle name from AppScope/app.json5`);
  }
  assert.ok(probes.length >= bundleProbes.length);
});
