const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');
const { storageURL, verifiedCopies } = require('./copy-authorized-project-media.cjs');
const root = '/Users/benjaminmackenzie/Dev/ledger_mobile_supabase';
const directory = root + '/tmp/real-project-copy/qa-copy-9e597cb852f5d204';
const mediaDirectory = root + '/tmp/real-project-copy/media-uW9OgI';
const account = 'realcopy-b9d236394770-account';
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const targetID = (kind, source) => 'realcopy-b9d236394770-' + kind + '-' + hash(source).slice(0, 24);

function planItemMedia(source, copies) {
  const items = [], blocked = [], objects = new Map();
  for (const document of source.documents) {
    const prefix = source.account + '/items/';
    if (!document.name.startsWith(prefix) || document.name.slice(prefix.length).includes('/')) continue;
    const sourceID = document.name.slice(prefix.length), id = targetID('item', sourceID);
    const raw = document.fields?.images;
    if (raw && !('nullValue' in raw) && !('arrayValue' in raw)) {
      blocked.push({ sourceID, reason: 'invalid_gallery' }); continue;
    }
    const values = raw?.arrayValue?.values || [], images = [];
    let reason;
    for (const value of values) {
      const fields = value.mapValue?.fields;
      if (fields?.kind?.stringValue !== 'image' || !fields?.url?.stringValue) { reason = 'unsupported_reference'; break; }
      let object;
      try { object = storageURL(fields.url.stringValue).object; }
      catch { reason = 'unavailable_source_reference'; break; }
      const copy = copies.get(object);
      if (!copy || !/^image\/[a-z0-9.+-]+$/.test(copy.contentType)) { reason = 'original_not_copied'; break; }
      if (images.some(image => image.object === object)) { reason = 'duplicate_source_object'; break; }
      if (fields.isPrimary && !('nullValue' in fields.isPrimary) && typeof fields.isPrimary.booleanValue !== 'boolean') { reason = 'invalid_primary'; break; }
      images.push({ ...copy, id: targetID('image', object), primary: fields.isPrimary?.booleanValue === true });
    }
    if (reason) { blocked.push({ sourceID, reason }); continue; }
    // Frozen AttachmentPrimaryPolicy: first explicit primary, otherwise first
    // image. Preserve original order; do not add another viewer implementation.
    const explicit = images.findIndex(image => image.primary);
    items.push({ id, sourceID, images, primaryIndex: explicit < 0 ? 0 : explicit });
    for (const image of images) objects.set(image.id, image);
  }
  return { items, blocked, objects };
}

async function main() {
  if (process.cwd() !== root || process.argv.length !== 3 || !['--plan', '--apply'].includes(process.argv[2])) throw Error('Use --plan or --apply in Supabase worktree');
  const manifest = JSON.parse(fs.readFileSync(directory + '/manifest.json'));
  const sourceBytes = fs.readFileSync(directory + '/source.json');
  if (manifest.accountID !== account || manifest.kind !== 'partial-real-data-qa-copy' || hash(sourceBytes) !== manifest.sourceSHA256) throw Error('Unexpected QA source');
  const source = JSON.parse(sourceBytes);
  if (source.account !== 'projects/ledger-nine4/databases/(default)/documents/accounts/1dd4fd75-8eea-4f7a-98e7-bf45b987ae94') throw Error('Unexpected source Account');
  const plan = planItemMedia(source, verifiedCopies(mediaDirectory));
  console.log(JSON.stringify({ completeGalleries: plan.items.length, blockedGalleries: plan.blocked.length, originalObjects: plan.objects.size }));
  if (process.argv[2] === '--plan') return;
  if (process.env.DOCKER_HOST || process.env.DOCKER_CONTEXT) throw Error('No remote Docker overrides');
  const docker = (args, input) => execFileSync('docker', args, { input, encoding: 'utf8', timeout: 30000, stdio: ['pipe', 'pipe', 'pipe'] });
  if (!JSON.parse(docker(['context','inspect','--format','{{json .Endpoints.docker.Host}}'])).startsWith('unix:///')) throw Error('Local Docker required');
  const container = 'supabase_db_ledger_target_supabase_local';
  const info = JSON.parse(docker(['inspect',container,'--format','{{json .}}']));
  if (info.Config.Labels['com.supabase.cli.project'] !== 'ledger_target_supabase_local'
      || info.Config.Labels['com.supabase.cli.workdir'] !== root) throw Error('Wrong database');
  const bindings = Object.values(info.NetworkSettings.Ports).flatMap(x => x || []);
  if (!bindings.length || bindings.some(x => !['127.0.0.1','::1'].includes(x.HostIp))) throw Error('Database must be private');
  const q = value => "'" + String(value).replaceAll("'", "''") + "'";
  const sql = input => docker(['exec','-i',container,'psql','-X','-q','-A','-t','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-v','VERBOSITY=terse'], input).trim();
  if (sql(`select count(*) from public.spike_account_memberships where account_id=${q(account)};`) !== '1'
      || sql(`select count(*) from public.spike_account_memberships where account_id=${q(account)} and principal_id=${q(manifest.qaPrincipalID)} and role='owner' and state='active';`) !== '1') throw Error('QA access changed');
  if (sql("select public from storage.buckets where id='ledger-attachments';") !== 'f') throw Error('Private attachment bucket required');
  const local = JSON.parse(execFileSync('npx',['--offline','--yes','supabase@2.116.0','status','-o','json'], { encoding:'utf8',timeout:15000,stdio:['ignore','pipe','ignore'] }));
  if (local.API_URL !== 'http://127.0.0.1:54321' || !local.SERVICE_ROLE_KEY) throw Error('Local Storage unavailable');
  const headers = { apikey: local.SERVICE_ROLE_KEY, Authorization: 'Bearer ' + local.SERVICE_ROLE_KEY };
  const originals = [...plan.objects.values()];
  await uploadVerifiedOriginals(plan, { apiURL:local.API_URL, headers, mediaDirectory });
  sql(publicationSQL(plan, manifest.qaPrincipalID));
  fs.writeFileSync(directory + '/item-media-review.json',JSON.stringify({ blocked:plan.blocked,items:plan.items.length,objects:originals.length }),{mode:0o600});
  console.log(JSON.stringify({ publishedGalleries:plan.items.length,verifiedOriginals:originals.length,blockedGalleries:plan.blocked.length,thumbnailsImported:false }));
}

async function uploadVerifiedOriginals(plan, { apiURL, headers, mediaDirectory, fetchImpl=fetch, onProgress=()=>{}, targetAccountID=account, allowUpload=true }) {
  if (!['http://127.0.0.1:54321','https://ybwviepljilrkrjoahbl.supabase.co'].includes(apiURL)) throw Error('Unapproved Storage endpoint');
  if (!/^realcopy-b9d236394770(?:-check-[a-f0-9]{12})?-account$/.test(targetAccountID)) throw Error('Unapproved QA Account');
  const originals = [...plan.objects.values()];
  let index = 0;
  let completed = 0, failure;
  async function worker() {
    while (!failure && index < originals.length) {
      const image = originals[index++];
      image.storagePath = `accounts/${targetAccountID}/attachments/${image.id}/${image.sha256}`;
      const suffix = image.storagePath.split('/').map(encodeURIComponent).join('/');
      const readURL = apiURL + '/storage/v1/object/authenticated/ledger-attachments/' + suffix;
      let response = await fetchImpl(readURL, { headers, redirect:'error',signal:AbortSignal.timeout(30000) });
      if (!response.ok) {
        if (![400,404].includes(response.status)) throw Error('Storage read failed');
        await response.body?.cancel();
        if (!allowUpload) throw Error('Original is not published; check mode never uploads');
        const original = fs.readFileSync(path.join(mediaDirectory,image.file));
        if (original.length !== image.bytes || hash(original) !== image.sha256) throw Error('Original bytes changed');
        const upload = await fetchImpl(apiURL + '/storage/v1/object/ledger-attachments/' + suffix, {
          method:'POST',headers:{...headers,'Content-Type':image.contentType,'x-upsert':'false'},
          body:original,redirect:'error',signal:AbortSignal.timeout(60000)
        });
        if (!upload.ok) throw Error('Storage upload failed');
        await upload.body?.cancel();
        response = await fetchImpl(readURL,{headers,redirect:'error',signal:AbortSignal.timeout(30000)});
      }
      if (!response.ok) throw Error('Uploaded bytes unavailable');
      const bytes = Buffer.from(await response.arrayBuffer());
      if (bytes.length !== image.bytes || hash(bytes) !== image.sha256) throw Error('Storage bytes do not match source');
      completed += 1;
      if (completed % 25 === 0 || completed === originals.length) onProgress(completed, originals.length);
    }
  }
  // Finish at most the already in-flight requests after the first failure.
  await Promise.all(Array.from({length:4},()=>worker().catch(error=>{ failure ||= error; })));
  if (failure) throw failure;
}

// Shared publication for the same authorized QA copy. Transport-specific callers
// must verify destination, private bucket and uploaded bytes before invoking it.
function publicationSQL(plan, qaPrincipalID) {
  if (typeof qaPrincipalID !== 'string' || !qaPrincipalID.startsWith('upload-http-owner-')) throw Error('Unexpected QA principal');
  const q = value => "'" + String(value).replaceAll("'", "''") + "'";
  const originals = [...plan.objects.values()];
  for (const image of originals) {
    if (image.storagePath !== `accounts/${account}/attachments/${image.id}/${image.sha256}`) throw Error('Unexpected object destination');
  }
  const statements = ['begin;', `select pg_advisory_xact_lock(hashtextextended(${q(account)},0));`];
  statements.push(`do $$ begin if (select count(*) from public.spike_account_memberships where account_id=${q(account)})<>1 or not exists(select 1 from public.spike_account_memberships where account_id=${q(account)} and principal_id=${q(qaPrincipalID)} and role='owner' and state='active') then raise exception 'QA access changed'; end if; end $$;`);
  for (const image of originals) {
    statements.push(`insert into public.item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path)
      values(${q(image.id)},${q(account)},${q(image.sha256)},${image.bytes},${q(image.contentType)},${q(image.storagePath)}) on conflict(id) do nothing;`);
    statements.push(`do $$ begin if not exists(select 1 from public.item_image_objects where id=${q(image.id)} and account_id=${q(account)} and content_sha256=${q(image.sha256)} and byte_count=${image.bytes} and media_type=${q(image.contentType)} and storage_path=${q(image.storagePath)}) then raise exception 'Existing image differs'; end if; end $$;`);
  }
  for (const item of plan.items) {
    statements.push(`insert into public.item_image_sets(id,account_id,item_id,revision,expected_count) values(${q(item.id)},${q(account)},${q(item.id)},1,${item.images.length}) on conflict(id) do nothing;`);
    statements.push(`do $$ begin if not exists(select 1 from public.item_image_sets where id=${q(item.id)} and account_id=${q(account)} and revision=1 and expected_count=${item.images.length}) then raise exception 'Existing gallery differs'; end if; end $$;`);
    item.images.forEach((image,position) => {
      const id = targetID('image-ref',item.sourceID + ':' + position);
      statements.push(`insert into public.item_image_references(id,account_id,item_id,attachment_id,set_revision,position,is_primary) values(${q(id)},${q(account)},${q(item.id)},${q(image.id)},1,${position},${position===item.primaryIndex}) on conflict(id) do nothing;`);
      statements.push(`do $$ begin if not exists(select 1 from public.item_image_references where id=${q(id)} and account_id=${q(account)} and item_id=${q(item.id)} and attachment_id=${q(image.id)} and set_revision=1 and position=${position} and is_primary=${position===item.primaryIndex}) then raise exception 'Existing gallery reference differs'; end if; end $$;`);
    });
  }
  statements.push('set constraints all immediate;','commit;');
  return statements.join('\n');
}
module.exports = { planItemMedia, publicationSQL, uploadVerifiedOriginals };
if (require.main === module) main().catch(() => { console.error('Private Item-media load failed; no source writes or overwrite fallback. Inspect local state before retry.');process.exitCode=1; });
