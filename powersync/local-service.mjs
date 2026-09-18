// Isolated Ledger development service beside its canonical stream configuration.
// Never connects to a linked/hosted project.
// Run with the repository's Node24 runtime. Runtime secrets stay under ignored tmp/.
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync, existsSync, chmodSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { SqlSyncRules } from '@powersync/service-sync-rules';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const runtime = path.join(root, 'tmp/ledger-powersync-local');
const database = 'supabase_db_ledger_target_supabase_local';
const network = 'ledger_target_local_loopback';
const container = 'ledger_powersync_local';
const image = 'journeyapps/powersync-service:1.24.0@sha256:0fc9f65e693c07f1206007acddb87141402c09ef20589e29a0dfe20d57ce80b6';
const run = (command, args, input) => execFileSync(command, args, {
  cwd: root, input, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], timeout: 60_000,
});
const sql = input => run('docker', ['exec', '-i', database, 'psql', '-U', 'supabase_admin',
  '-d', 'postgres', '-At', '-v', 'ON_ERROR_STOP=1'], input).trim();
process.umask(0o077);
let stage = 'validating the local environment';
try {
  if (process.env.DOCKER_HOST || process.env.DOCKER_CONTEXT) throw Error('Docker endpoint overrides are not allowed');
  const dockerHost = JSON.parse(run('docker', ['context', 'inspect', '--format', '{{json .Endpoints.docker.Host}}']));
  if (typeof dockerHost !== 'string' || !dockerHost.startsWith('unix://')) throw Error('Docker must use a local socket');
  const db = JSON.parse(run('docker', ['inspect', database]))[0];
  if (db.Config.Labels?.['com.supabase.cli.workdir'] !== root
      || db.Config.Labels?.['com.supabase.cli.project'] !== 'ledger_target_supabase_local'
      || !db.NetworkSettings.Networks[network]) throw Error('Unexpected database ownership/network');
  const status = JSON.parse(run('npx', ['--yes', 'supabase@2.116.0', 'status', '-o', 'json']));
  if (status.API_URL !== 'http://127.0.0.1:54321' || !status.JWT_SECRET) throw Error('Unexpected local API configuration');
  const streamsPath = path.join(root, 'powersync/sync-streams.yaml');
  stage = 'validating explicit stream source tables';
  const compiled = SqlSyncRules.fromYaml(readFileSync(streamsPath, 'utf8'), { defaultSchema: 'public', throwOnError: true });
  const tables = compiled.config.getSourceTables().map(table => {
    if (!['public', 'ledger_private'].includes(table.schema) || table.isWildcard || !/^[a-z_][a-z_0-9]*$/.test(table.tablePattern)) {
      throw Error('Only explicitly named Ledger source tables are allowed');
    }
    return `${table.schema}.${table.tablePattern}`;
  }).sort();
  if (!tables.length) throw Error('No replication sources');
  let existing;
  const matching = run('docker', ['ps', '-a', '--filter', `name=^/${container}$`, '--format', '{{.Names}}']).trim();
  if (matching) {
    existing = JSON.parse(run('docker', ['inspect', container]))[0];
    if (existing.Config.Labels?.['ledger.local-powersync'] !== root || existing.Config.Image !== image) {
      throw Error('Existing container is not this Ledger service');
    }
    const bindings = existing.HostConfig.PortBindings;
    if (Object.keys(bindings ?? {}).length !== 1 || bindings['8080/tcp']?.length !== 1
        || bindings['8080/tcp'][0].HostIp !== '127.0.0.1' || bindings['8080/tcp'][0].HostPort !== '5590'
        || Object.keys(existing.NetworkSettings.Networks ?? {}).join() !== network) {
      throw Error('Existing service network or loopback binding differs');
    }
    const mounts = existing.Mounts ?? [];
    const expectedMounts = [[path.join(runtime, 'service.json'), '/config/service.json'],
      [streamsPath, '/config/sync-streams.yaml']];
    if (mounts.length !== expectedMounts.length || !expectedMounts.every(([source, destination]) =>
      mounts.some(mount => mount.Type === 'bind' && mount.Source === source
        && mount.Destination === destination && mount.RW === false))) {
      throw Error('Existing service configuration mounts differ');
    }
  }
  mkdirSync(runtime, { recursive: true, mode: 0o700 });
  chmodSync(runtime, 0o700);
  const privateFile = (name, value) => {
    const file = path.join(runtime, name);
    writeFileSync(file, JSON.stringify(value), { mode: 0o600 });
    chmodSync(file, 0o600);
  };
  const passwordPath = path.join(runtime, 'database-passwords.json');
  const passwords = existsSync(passwordPath) ? JSON.parse(readFileSync(passwordPath, 'utf8')) : {
    replication: randomBytes(32).toString('hex'), storage: randomBytes(32).toString('hex'),
  };
  if (![passwords.replication, passwords.storage].every(value => /^[a-f0-9]{64}$/.test(value))) throw Error('Invalid credentials');
  privateFile('database-passwords.json', passwords);
  stage = 'configuring local replication roles';
  sql(`DO $$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='ledger_local_sync_replication') THEN
      CREATE ROLE ledger_local_sync_replication REPLICATION BYPASSRLS LOGIN PASSWORD '${passwords.replication}';
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='ledger_local_sync_storage') THEN
      CREATE ROLE ledger_local_sync_storage LOGIN PASSWORD '${passwords.storage}';
    END IF;
  END $$;
  GRANT CONNECT ON DATABASE postgres TO ledger_local_sync_replication;
  GRANT USAGE ON SCHEMA public,ledger_private TO ledger_local_sync_replication;
  GRANT SELECT ON ${tables.join(',')} TO ledger_local_sync_replication;`);
  // Keep service-owned bucket tables out of the application database/migrations.
  const owner = sql("SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname='ledger_powersync_bucket_local';");
  if (!owner) sql('CREATE DATABASE ledger_powersync_bucket_local OWNER ledger_local_sync_storage;');
  else if (owner !== 'ledger_local_sync_storage') throw Error('Bucket database has another owner');
  const publication = sql("SELECT puballtables FROM pg_publication WHERE pubname='powersync';");
  if (!publication) sql(`CREATE PUBLICATION powersync FOR TABLE ${tables.join(',')};`);
  else {
    const published = sql("SELECT schemaname||'.'||tablename FROM pg_publication_tables WHERE pubname='powersync' ORDER BY 1;").split('\n');
    // Retain the canonical thumbnail source while old and new rules overlap
    // during rollout. It remains private and does not add a stream output.
    const expected = published.filter(table => table !== 'public.item_card_thumbnails' || tables.includes(table));
    if (publication !== 'f' || JSON.stringify(expected) !== JSON.stringify(tables)) throw Error('Publication requires explicit reconciliation');
  }
  const config = {
    replication: { connections: [{ type: 'postgresql', uri: `postgresql://ledger_local_sync_replication:${passwords.replication}@${database}:5432/postgres`, sslmode: 'disable' }] },
    storage: { type: 'postgresql', uri: `postgresql://ledger_local_sync_storage:${passwords.storage}@${database}:5432/ledger_powersync_bucket_local`, sslmode: 'disable' },
    port: 8080, sync_config: { path: '/config/sync-streams.yaml' },
    client_auth: { supabase: true, supabase_jwt_secret: status.JWT_SECRET,
      jwks_uri: 'http://supabase_auth_ledger_target_supabase_local:9999/.well-known/jwks.json', audience: ['authenticated'] },
    telemetry: { disable_telemetry_sharing: true },
  };
  const configPath = path.join(runtime, 'service.json');
  if (existing && (!existsSync(configPath) || readFileSync(configPath, 'utf8') !== JSON.stringify(config))) {
    throw Error('Existing service configuration differs; review before restarting that container');
  }
  privateFile('service.json', config);
  privateFile('test-config.json', { url: status.API_URL, key: status.PUBLISHABLE_KEY ?? status.ANON_KEY,
    syncURL: 'http://127.0.0.1:5590' });
  stage = 'starting the Ledger-only service';
  if (existing) {
    if (process.argv.includes('--restart')) run('docker', ['restart', container]);
    else if (!existing.State.Running) run('docker', ['start', container]);
  } else {
    run('docker', ['run', '-d', '--name', container, '--label', `ledger.local-powersync=${root}`,
      '--network', network, '-p', '127.0.0.1:5590:8080',
      '-v', `${configPath}:/config/service.json:ro`, '-v', `${streamsPath}:/config/sync-streams.yaml:ro`,
      '-e', 'POWERSYNC_CONFIG_PATH=/config/service.json', image, 'start', '-r', 'unified']);
  }
  stage = 'waiting for local readiness';
  const deadline = Date.now() + 60_000;
  while (true) {
    const ready = await fetch('http://127.0.0.1:5590/probes/readiness', { signal: AbortSignal.timeout(2_000) }).catch(() => null);
    if (ready?.status === 200) break;
    if (Date.now() >= deadline) throw Error('Service did not become ready');
    await new Promise(resolve => setTimeout(resolve, 1_000));
  }
  console.log(`Ledger local PowerSync ready on 127.0.0.1:5590; ${tables.length} explicit source tables. Test configuration saved privately under tmp/ledger-powersync-local.`);
  if (existing?.State.Running && !process.argv.includes('--restart')) {
    console.log('Existing service retained. After stream configuration changes, use --restart to load them; readiness alone does not verify the loaded configuration.');
  }
} catch {
  // Child-process diagnostics can contain generated credentials; never echo them.
  console.error(`Ledger local PowerSync failed while ${stage}. No automatic reset/deletion was performed.`);
  process.exitCode = 1;
}
