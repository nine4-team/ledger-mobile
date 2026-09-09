import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash, createHmac, randomUUID } from 'node:crypto';
import { realpathSync } from 'node:fs';

// Real bytes through the native producer, local Storage HTTP and private SQL.
// No user-supplied endpoints/credentials/files and no hosted fallback.
assert.ok(!process.env.DOCKER_HOST && !process.env.DOCKER_CONTEXT);
const docker = args => execFileSync('docker',args,{encoding:'utf8',timeout:10000});
assert.match(JSON.parse(docker(['context','inspect','--format','{{json .Endpoints.docker.Host}}'])),/^unix:\/\//);
const container = 'supabase_db_ledger_target_supabase_local';
const labels = JSON.parse(docker(['inspect','--format','{{json .Config.Labels}}',container]));
assert.equal(labels['com.supabase.cli.project'],'ledger_target_supabase_local');
assert.equal(realpathSync(labels['com.supabase.cli.workdir']),realpathSync(process.cwd()));
let local;
try {
  local = JSON.parse(execFileSync('npx',['--offline','--yes','supabase@2.116.0','status','-o','json'],
    {encoding:'utf8',stdio:['ignore','pipe','ignore'],timeout:15000}));
} catch { throw new Error('Cannot read isolated local Supabase credentials; no fallback'); }
assert.equal(local.API_URL,'http://127.0.0.1:54321');
const q = value => `'${String(value).replaceAll("'","''")}'`;
const sql = query => execFileSync('docker',['exec','-i',container,'psql','-X','-q','-A','-t','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],
  {input:query,encoding:'utf8',timeout:10000}).trim();
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const suffix = randomUUID(), originalId = `thumb-http-original-${suffix}`, smallId = `thumb-http-small-${suffix}`;
const item = `thumb-http-item-${suffix}`, link = `thumb-http-link-${suffix}`;
const originalBytes = Buffer.from('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7','base64');
const pathFor = (id,hash) => `accounts/account-primary/attachments/${id}/${hash}`;
const original = {accountId:'account-primary',attachmentId:originalId,sha256:digest(originalBytes),
  byteCount:String(originalBytes.length),mediaType:'image/gif',storagePath:pathFor(originalId,digest(originalBytes)),
  base64:originalBytes.toString('base64')};
const generated = JSON.parse(execFileSync('LedgeriOS/.build/debug/LedgerItemThumbnail',[],
  {input:JSON.stringify(original),encoding:'utf8',timeout:15000}));
const rejected = spawnSync('LedgeriOS/.build/debug/LedgerItemThumbnail',[],
  {input:JSON.stringify({...original,sha256:'0'.repeat(64)}),encoding:'utf8',timeout:15000});
assert.equal(rejected.status,1); assert.equal(rejected.stdout,'');
assert.equal(rejected.stderr,'Thumbnail generation rejected input.\n');
const bytes = Buffer.from(generated.base64,'base64');
assert.equal(digest(bytes),generated.sha256);
assert.equal(String(bytes.length),generated.byteCount);
assert.equal(generated.mediaType,'image/jpeg');
assert.equal(generated.width,1); assert.equal(generated.height,1);
const smallPath = pathFor(smallId,generated.sha256);
const segmentPath = path => path.split('/').map(encodeURIComponent).join('/');
async function request(method,path,token,body,mediaType) {
  return fetch(`${local.API_URL}/storage/v1/object/${path}`,{
    method,redirect:'error',signal:AbortSignal.timeout(10000),
    headers:{apikey:local.ANON_KEY,Authorization:`Bearer ${token}`,
      ...(body ? {'Content-Type':mediaType,'x-upsert':'false'} : {})},body
  });
}
async function read(path,token) {
  return request('GET',`authenticated/ledger-attachments/${segmentPath(path)}`,token);
}
async function uploadAndVerify(path,bytes,hash,mediaType) {
  assert.equal(digest(bytes),hash,'Reject incorrect local bytes before sending');
  const uploaded = await request('POST',`ledger-attachments/${segmentPath(path)}`,local.SERVICE_ROLE_KEY,bytes,mediaType);
  // Existing immutable paths are never overwritten. A duplicate is success
  // only after authenticated readback verifies exact bytes, length and MIME.
  assert.ok(uploaded.ok || [400,409].includes(uploaded.status),`Upload status ${uploaded.status}`);
  const downloaded = await read(path,local.SERVICE_ROLE_KEY);
  assert.equal(downloaded.status,200);
  assert.equal(downloaded.headers.get('content-type')?.split(';')[0],mediaType);
  const actual = Buffer.from(await downloaded.arrayBuffer());
  assert.equal(actual.length,bytes.length,'Remote byte length mismatch');
  assert.equal(digest(actual),hash,'Remote checksum mismatch');
  return uploaded.status;
}
function token(sub) {
  const encode = object => Buffer.from(JSON.stringify(object)).toString('base64url');
  const unsigned = `${encode({alg:'HS256',typ:'JWT'})}.${encode({sub,role:'authenticated',exp:Math.floor(Date.now()/1000)+300})}`;
  return `${unsigned}.${createHmac('sha256',local.JWT_SECRET).update(unsigned).digest('base64url')}`;
}
const member = token('10000000-0000-0000-0000-000000000002');
await uploadAndVerify(original.storagePath,originalBytes,original.sha256,original.mediaType);
sql(`begin;
 insert into public.spike_items(id,account_id,description,created_by_principal_id)
 values(${q(item)},'account-primary','Synthetic thumbnail HTTP evidence','principal-owner');
 insert into public.item_image_objects values(${q(originalId)},'account-primary',${q(original.sha256)},${original.byteCount},'image/gif',${q(original.storagePath)});
 insert into public.item_image_sets values(${q(item)},'account-primary',${q(item)},1,1);
 insert into public.item_image_references values(${q(`ref-${suffix}`)},'account-primary',${q(item)},${q(originalId)},1,0,true);
 commit;`);
assert.equal((await read(original.storagePath,member)).status,200);
await uploadAndVerify(smallPath,bytes,generated.sha256,generated.mediaType);
assert.ok([400,403,404].includes((await read(smallPath,member)).status),'Uploaded bytes are not authority before the link exists');
assert.equal(sql(`select count(*) from public.item_card_thumbnails where id=${q(link)};`),'0');
// Retry after a simulated stop between byte upload and metadata publication.
const duplicateStatus = await uploadAndVerify(smallPath,bytes,generated.sha256,generated.mediaType);
assert.ok([400,409].includes(duplicateStatus));
await assert.rejects(uploadAndVerify(smallPath,Buffer.from([1]),generated.sha256,generated.mediaType));
// A pre-existing remote object is not accepted merely because its path claims
// the expected checksum. Readback mismatch must prevent publication.
const badId = `thumb-http-corrupt-${suffix}`,badPath = pathFor(badId,generated.sha256);
assert.ok((await request('POST',`ledger-attachments/${segmentPath(badPath)}`,local.SERVICE_ROLE_KEY,
  Buffer.alloc(bytes.length),'image/jpeg')).ok);
await assert.rejects(uploadAndVerify(badPath,bytes,generated.sha256,generated.mediaType),
  error => error instanceof assert.AssertionError && error.message.includes('Remote checksum mismatch'));
assert.equal(sql(`select count(*) from public.item_image_objects where id=${q(badId)};`),'0');
const publish = `select ledger_private.publish_item_card_thumbnail('account-primary',${q(originalId)},${q(original.sha256)},${original.byteCount},'image/gif',${q(original.storagePath)},
 ${q(smallId)},${q(generated.sha256)},${generated.byteCount},'image/jpeg',${q(smallPath)},${q(link)},${q(generated.recipe)},${generated.width},${generated.height});`;
assert.equal(sql(publish),link); assert.equal(sql(publish),link);
const authorized = await read(smallPath,member);
assert.equal(authorized.status,200);
assert.equal(digest(Buffer.from(await authorized.arrayBuffer())),generated.sha256);
assert.equal(sql(`select count(*) from public.item_card_thumbnails where original_attachment_id=${q(originalId)};`),'1');
assert.equal(sql(`select count(*) from storage.objects where bucket_id='ledger-attachments' and name=${q(smallPath)};`),'1');
const other = token('10000000-0000-0000-0000-000000000003');
assert.ok([400,403,404].includes((await read(smallPath,other)).status),'Other Account cannot retrieve bytes');
sql(`update public.item_image_sets set revision=2,expected_count=0 where id=${q(item)};`);
assert.ok([400,403,404].includes((await read(smallPath,member)).status),'Old reference cannot retrieve bytes');
assert.equal((await read(smallPath,local.SERVICE_ROLE_KEY)).status,200,'Reference removal does not silently purge bytes');
console.log(`thumbnail-storage: native JPEG→real local upload/readback→retry→SQL publication→member GET→reference denial passed; synthetic suffix ${suffix} retained: original+small+intentionally corrupt Storage object (corrupt object has no metadata link)`);
