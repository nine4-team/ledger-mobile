const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const network = 'ledger_target_local_loopback';
const run = (cmd, args) => execFileSync(cmd, args, { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
process.umask(0o077);
try {
  if (root !== '/Users/benjaminmackenzie/Dev/ledger_mobile_supabase' || process.env.DOCKER_HOST || process.env.DOCKER_CONTEXT) throw Error('Unexpected environment');
  const context = JSON.parse(run('docker', ['context', 'inspect']));
  if (!context[0]?.Endpoints?.docker?.Host?.startsWith('unix://')) throw Error('Requires local Docker');
  const names = run('docker', ['network', 'ls', '--format', '{{.Name}}']).trim().split('\n');
  if (!names.includes(network)) run('docker', ['network', 'create', '--driver', 'bridge', '--opt', 'com.docker.network.bridge.host_binding_ipv4=127.0.0.1', network]);
  const info = JSON.parse(run('docker', ['network', 'inspect', network]))[0];
  if (info.Options?.['com.docker.network.bridge.host_binding_ipv4'] !== '127.0.0.1') throw Error('Network is not loopback-only');
  const logDirectory = path.join(root, 'tmp/ledger-powersync-local');
  fs.mkdirSync(logDirectory, { recursive: true, mode: 0o700 });
  let output;
  try { output = run('npx', ['--yes', 'supabase@2.116.0', 'start', '--network-id', network]); }
  catch (error) {
    fs.writeFileSync(path.join(logDirectory, 'supabase-start.log'), String(error.stdout || '') + String(error.stderr || ''), { mode: 0o600 });
    throw Error('Local startup failed; private log retained');
  }
  fs.writeFileSync(path.join(logDirectory, 'supabase-start.log'), output, { mode: 0o600 });
  const ids = run('docker', ['ps', '-q', '--filter', 'label=com.supabase.cli.project=ledger_target_supabase_local']).trim().split('\n').filter(Boolean);
  if (!ids.length) throw Error('No Ledger services');
  for (const container of JSON.parse(run('docker', ['inspect', ...ids]))) {
    if (!container.NetworkSettings.Networks[network]) throw Error('Unexpected service network');
    for (const bindings of Object.values(container.NetworkSettings.Ports || {})) {
      for (const binding of bindings || []) if (!['127.0.0.1', '::1'].includes(binding.HostIp)) throw Error('Non-loopback service port');
    }
  }
  console.log('Ledger local Supabase started; all published service ports verified loopback-only.');
} catch (error) { console.error(error.message); process.exitCode = 1; }
