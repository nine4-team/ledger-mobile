// Copies referenced source media only. No source writes, uploads, or Auth calls.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const workspace = '/Users/benjaminmackenzie/Dev/ledger_mobile_supabase';
const root = path.join(workspace, 'tmp/real-project-copy');
const bucket = 'ledger-nine4.firebasestorage.app';
function storageURL(value) {
  let url = new URL(value);
  if (url.protocol === 'gs:' && url.hostname === bucket && !url.username && !url.password && !url.port && !url.search && !url.hash) {
    url = new URL('https://firebasestorage.googleapis.com/v0/b/' + bucket + '/o/' + encodeURIComponent(decodeURIComponent(url.pathname.slice(1))));
  }
  if (url.protocol !== 'https:' || url.hostname !== 'firebasestorage.googleapis.com'
      || url.port || url.username || url.password || url.hash
      || !url.pathname.startsWith('/v0/b/' + bucket + '/o/')) throw Error('Unapproved media origin');
  const object = decodeURIComponent(url.pathname.slice(('/v0/b/' + bucket + '/o/').length));
  if (!object || object.split('/').some(part => part === '..' || part === '.')) throw Error('Invalid object');
  url.searchParams.set('alt', 'media');
  return { url: url.href, object };
}
function collectMediaReferences(documents) {
  const refs = new Map(), unavailable = [];
  function walk(value, owner, field) {
    if (value.stringValue && ['url', 'thumbnailUrlSm', 'thumbnailUrlMd', 'mainImageUrl', 'mainImageThumbUrlSm', 'mainImageThumbUrlMd'].includes(field)) {
      // A device-local reference is evidence of missing source bytes, not a URL
      // this machine can fetch. Preserve it without substituting another image.
      if (value.stringValue.startsWith('offline://')) {
        unavailable.push({ owner, field, reference: value.stringValue, status: 'unavailable', reason: 'source_device_local' });
      } else {
        const parsed = storageURL(value.stringValue);
        const entry = refs.get(parsed.object) || { ...parsed, owners: [] };
        entry.owners.push(owner);
        refs.set(parsed.object, entry);
      }
    }
    for (const [key, child] of Object.entries(value.mapValue?.fields || {})) walk(child, owner, key);
    for (const child of value.arrayValue?.values || []) walk(child, owner, field);
  }
  for (const doc of documents) for (const [key, value] of Object.entries(doc.fields || {})) walk(value, doc.name, key);
  return { refs, unavailable };
}
function verifiedCopies(directory, selectedObjects = null) {
  const resultsPath = path.join(directory, 'results.jsonl');
  const copies = new Map();
  if (!fs.existsSync(resultsPath)) return copies;
  if (!fs.lstatSync(resultsPath).isFile() || fs.lstatSync(resultsPath).isSymbolicLink()) throw Error('Invalid result file');
  for (const line of fs.readFileSync(resultsPath, 'utf8').split('\n').filter(Boolean)) {
    const row = JSON.parse(line);
    if (row.status !== 'copied') continue;
    if (selectedObjects && !selectedObjects.has(row.object)) continue;
    const expected = crypto.createHash('sha256').update(row.object).digest('hex');
    if (row.file !== expected) throw Error('Invalid copied file identity');
    const file = path.join(directory, expected);
    const info = fs.lstatSync(file);
    if (!info.isFile() || info.isSymbolicLink() || info.size !== row.bytes || info.size > 40 * 1024 * 1024
        || crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex') !== row.sha256) {
      throw Error('Copied bytes changed; refusing overwrite');
    }
    copies.set(row.object, row);
  }
  return copies;
}
function collectSpaceOriginals(source) {
  const prefix = source.account + '/spaces/';
  return collectMediaReferences(source.documents
    .filter(doc => doc.name.startsWith(prefix) && !doc.name.slice(prefix.length).includes('/'))
    .map(doc => ({name:doc.name,fields:{images:{arrayValue:{values:
      (doc.fields?.images?.arrayValue?.values ?? []).map(value => ({mapValue:{fields:
        value.mapValue?.fields?.url ? {url:value.mapValue.fields.url} : {}}}))
    }}}})));
}
async function main() {
  const flags = process.argv.slice(2);
  const spacesOnly = flags.includes('--spaces-only');
  if (flags.filter(value => value === '--spaces-only').length > 1) throw Error('Duplicate selection flag');
  const args = flags.filter(value => value !== '--spaces-only');
  const resume = args.length === 3 && args[1] === '--resume';
  if (process.cwd() !== workspace || (args.length !== 1 && !resume)) throw Error('Expected source snapshot [--resume directory] [--spaces-only] in Supabase worktree');
  const input = path.resolve(args[0]);
  if (path.dirname(input) !== root || fs.lstatSync(input).isSymbolicLink()) throw Error('Invalid input');
  const sourceBytes = fs.readFileSync(input);
  const source = JSON.parse(sourceBytes);
  if (source.sourceProject !== 'ledger-nine4' || source.projectId !== '5abd46c9-9886-4b3e-b2b1-19f6cf995a44'
      || source.account !== 'projects/ledger-nine4/databases/(default)/documents/accounts/1dd4fd75-8eea-4f7a-98e7-bf45b987ae94') throw Error('Invalid source scope');
  const { refs, unavailable } = spacesOnly ? collectSpaceOriginals(source) : collectMediaReferences(source.documents);
  if (refs.size > 10000) throw Error('Unexpected media count');
  const directory = resume ? path.resolve(args[2]) : fs.mkdtempSync(path.join(root, 'media-'));
  if (path.dirname(directory) !== root || !path.basename(directory).startsWith('media-')
      || fs.lstatSync(directory).isSymbolicLink() || !fs.lstatSync(directory).isDirectory()) throw Error('Invalid copy directory');
  const sourceIdentity = { input, sha256: crypto.createHash('sha256').update(sourceBytes).digest('hex'), expectedObjects: refs.size };
  if (spacesOnly) sourceIdentity.selection = 'space_originals';
  if (resume) {
    const saved = path.join(directory, 'source.json');
    if (fs.lstatSync(saved).isSymbolicLink()) throw Error('Invalid saved source');
    const previous = JSON.parse(fs.readFileSync(saved, 'utf8'));
    if ((previous.selection ?? 'all') !== (sourceIdentity.selection ?? 'all')) throw Error('Resume selection changed');
    if (Object.keys(sourceIdentity).some(key => previous[key] !== sourceIdentity[key])) throw Error('Resume source changed');
  }
  fs.chmodSync(directory, 0o700);
  // Do not remove a lock after a crash without checking the saved process. A
  // timeout in the observing agent is not evidence that copying has stopped.
  const lockPath = path.join(directory, '.copy.lock');
  const lock = fs.openSync(lockPath, 'wx', 0o600);
  fs.writeFileSync(lock, String(process.pid));
  fs.closeSync(lock);
  try {
  const existing = resume ? verifiedCopies(directory) : new Map();
  if ([...existing.keys()].some(object => !refs.has(object))) throw Error('Saved copy outside snapshot');
  const reusedBytes = [...existing.values()].reduce((sum, row) => sum + row.bytes, 0);
  let total = reusedBytes, transferredBytes = 0, index = 0;
  const entries = [...refs.values()].filter(ref => !existing.has(ref.object));
  const results = [...existing.values(), ...unavailable];
  if (!resume && unavailable.length) fs.writeFileSync(path.join(directory, 'results.jsonl'),
    unavailable.map(row => JSON.stringify(row) + '\n').join(''), { mode: 0o600, flag: 'wx' });
  async function worker() {
    while (index < entries.length) {
      const ref = entries[index++];
      const name = crypto.createHash('sha256').update(ref.object).digest('hex');
      const destination = path.join(directory, name);
      let handle;
      let size = 0;
      try {
        const response = await fetch(ref.url, { redirect: 'error', signal: AbortSignal.timeout(45000) });
        if (!response.ok) throw Error('http_' + response.status);
        if (Number(response.headers.get('content-length') || 0) > 40 * 1024 * 1024) throw Error('file_size_limit');
        handle = fs.openSync(destination + '.part', 'wx', 0o600);
        const hash = crypto.createHash('sha256');
        for await (const chunk of response.body) {
          size += chunk.length;
          total += chunk.length;
          transferredBytes += chunk.length;
          if (size > 40 * 1024 * 1024 || total > 4 * 1024 ** 3) throw Error('copy_size_limit');
          hash.update(chunk);
          fs.writeFileSync(handle, chunk);
        }
        fs.closeSync(handle); handle = undefined;
        fs.renameSync(destination + '.part', destination);
        const result = { object: ref.object, owners: ref.owners, file: name, bytes: size, sha256: hash.digest('hex'), contentType: response.headers.get('content-type'), status: 'copied' };
        results.push(result);
        fs.appendFileSync(path.join(directory, 'results.jsonl'), JSON.stringify(result) + '\n', { mode: 0o600 });
      } catch (error) {
        if (handle !== undefined) fs.closeSync(handle);
        if (fs.existsSync(destination + '.part')) fs.unlinkSync(destination + '.part');
        const result = { object: ref.object, owners: ref.owners, status: 'unavailable', reason: /^http_\d+$|^(file|copy)_size_limit$/.test(error.message) ? error.message : 'download_failed' };
        results.push(result);
        fs.appendFileSync(path.join(directory, 'results.jsonl'), JSON.stringify(result) + '\n', { mode: 0o600 });
      }
    }
  }
  if (!resume) fs.writeFileSync(path.join(directory, 'source.json'), JSON.stringify(sourceIdentity), { mode: 0o600, flag: 'wx' });
  console.log(JSON.stringify({ directory, expectedObjects: refs.size, reused: existing.size, remaining: entries.length, started: true }));
  await Promise.all(Array.from({ length: 4 }, worker));
  const failures = {};
  for (const row of results) if (row.status !== 'copied') failures[row.reason] = (failures[row.reason] || 0) + 1;
  console.log(JSON.stringify({ directory, copied: results.filter(x => x.status === 'copied').length, failures, reusedBytes, transferredBytes }));
  } finally { fs.unlinkSync(lockPath); }
}
module.exports = { storageURL, collectMediaReferences, collectSpaceOriginals, verifiedCopies };
if (require.main === module) main().catch(error => { console.error('Media copy failed:', error.code || error.name); process.exitCode = 1; });
