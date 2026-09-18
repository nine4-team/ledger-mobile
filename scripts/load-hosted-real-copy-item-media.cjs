// Authorized private Ledger QA copy only. No Firebase writes, public bucket,
// key persistence, overwrite fallback, project creation or billing changes.
const fs = require('node:fs');
const crypto = require('node:crypto');
const path = require('node:path');
const {execFileSync} = require('node:child_process');
const {planItemMedia, publicationSQL, uploadVerifiedOriginals} = require('./load-real-copy-item-media.cjs');
const {verifiedCopies} = require('./copy-authorized-project-media.cjs');
const {planSpaceMedia,spacePublicationSQL,planTransactionMedia,transactionPublicationSQL} = require('./real-copy-transaction-media.cjs');
const root='/Users/benjaminmackenzie/Dev/ledger_mobile_supabase';
const project='ybwviepljilrkrjoahbl';
const account='realcopy-b9d236394770-account';
const directory=root+'/tmp/real-project-copy/qa-copy-9e597cb852f5d204';
const mediaDirectory=root+'/tmp/real-project-copy/media-uW9OgI';
const scratch=root+'/tmp/ledger-hosted-qa';
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const q=value=>"'"+String(value).replaceAll("'","''")+"'";

function assertQAState(row) {
  if (!row || row.membership_count!==1 || row.qa_owner_count!==1 || row.private_bucket!==true
      || row.copied_item_count!==1375) throw Error('Hosted QA scope or private access changed');
}

async function main() {
  const spacePlan=process.argv[2]==='--plan-spaces';
  const spaceMode=['--plan-spaces','--apply-spaces','--verify-spaces'].includes(process.argv[2]);
  if(process.cwd()!==root || !(process.argv.length===3 || (spaceMode && process.argv.length===4)) || !['--plan','--apply','--verify','--prepare-thumbnails','--publish-thumbnails','--plan-transactions','--apply-transactions','--verify-transactions','--plan-spaces','--apply-spaces','--verify-spaces'].includes(process.argv[2])) throw Error('Unexpected loader command or worktree');
  if(spaceMode && !spacePlan && !process.argv[3]) throw Error('Verified Space original directory required');
  const bytes=fs.readFileSync(directory+'/source.json');
  const manifest=JSON.parse(fs.readFileSync(directory+'/manifest.json'));
  if(hash(bytes)!=='9e597cb852f5d2048f774f4b20dd76c77fc9eec9bc93fc6ceaa8d6693c348183'
      || manifest.sourceSHA256!==hash(bytes) || manifest.accountID!==account || manifest.kind!=='partial-real-data-qa-copy') throw Error('Unexpected source copy');
  let selectedMediaDirectory=mediaDirectory;
  if(spaceMode && process.argv[3]) {
    selectedMediaDirectory=path.resolve(process.argv[3]);
    if(path.dirname(selectedMediaDirectory)!==root+'/tmp/real-project-copy'
      || !path.basename(selectedMediaDirectory).startsWith('media-')
      || fs.lstatSync(selectedMediaDirectory).isSymbolicLink()) throw Error('Unexpected Space copy directory');
    const identity=JSON.parse(fs.readFileSync(selectedMediaDirectory+'/source.json'));
    if(identity.sha256!==hash(bytes) || identity.selection!=='space_originals') throw Error('Space copy source differs');
  }
  const copies=verifiedCopies(selectedMediaDirectory);
  if(process.argv[2]==='--plan-spaces') {
    const source=JSON.parse(bytes),prefix=source.account+'/spaces/';
    const spaces=new Set(source.documents.filter(d=>d.name.startsWith(prefix) && !d.name.slice(prefix.length).includes('/'))
      .map(d=>'realcopy-b9d236394770-space-'+hash(d.name.slice(prefix.length)).slice(0,24)));
    const planned=planSpaceMedia(source,copies,spaces);
    console.log(JSON.stringify({planOnly:true,sourceSpaces:spaces.size,completeGalleries:planned.spaces.length,
      references:planned.spaces.reduce((n,s)=>n+s.images.length,0),objects:planned.objects.size,
      blocked:planned.blocked.length,blockedReasons:planned.blocked.reduce((r,b)=>(r[b.reason]=(r[b.reason]||0)+1,r),{})}));
    return; // Local saved snapshot only; no hosted query, upload or publication.
  }
  const plan=spaceMode ? {items:[],objects:new Map(),blocked:[]} : planItemMedia(JSON.parse(bytes),copies);
  const totalBytes=[...plan.objects.values()].reduce((n,image)=>n+image.bytes,0);
  if(!spaceMode && (plan.items.length!==725 || plan.objects.size!==819 || totalBytes!==1956762995)) throw Error('Reviewed image scope changed');
  if(!spaceMode) console.log(JSON.stringify({plan:true,galleries:plan.items.length,objects:plan.objects.size,bytes:totalBytes,blocked:plan.blocked.length}));
  if(process.argv[2]==='--plan') return;
  if(process.argv[2]==='--prepare-thumbnails') {
    prepareThumbnails(plan);
    return;
  }
  const auth=JSON.parse(fs.readFileSync(scratch+'/auth.json'));
  if(auth.principalId!==manifest.qaPrincipalID || !auth.email.endsWith('@ledger-tests.invalid')) throw Error('Unexpected QA identity');
  const cli=args=>execFileSync('npx',['--offline','--yes','supabase@2.116.0',...args],
    {encoding:'utf8',timeout:60000,stdio:['ignore','pipe','pipe']});
  const sqlFile=(name,sql)=>{
    const file=scratch+'/'+name;
    fs.writeFileSync(file,sql,{mode:0o600});
    fs.chmodSync(file,0o600);
    return file;
  };
  const preflight=sqlFile('media-preflight.sql',`select
    (select count(*) from public.spike_account_memberships where account_id=${q(account)}) as membership_count,
    (select count(*) from public.spike_account_memberships m join public.spike_principals p on p.id=m.principal_id
      join auth.users u on u.id=p.auth_user_id where m.account_id=${q(account)} and m.principal_id=${q(auth.principalId)}
      and m.role='owner' and m.state='active' and u.id=${q(auth.userId)}::uuid and u.email=${q(auth.email)}) as qa_owner_count,
    (select not public from storage.buckets where id='ledger-attachments') as private_bucket,
    (select count(*) from public.spike_items where account_id=${q(account)} and starts_with(id,'realcopy-b9d236394770-item-')) as copied_item_count,
    (select count(*) from public.item_image_objects where account_id=${q(account)} and id like 'realcopy-b9d236394770-image-%') as image_object_count,
    (select count(*) from public.item_image_sets where account_id=${q(account)}) as image_set_count,
    (select count(*) from public.item_image_references where account_id=${q(account)}) as image_reference_count,
    (select count(*) from public.item_card_thumbnails where account_id=${q(account)} and id like 'realcopy-b9d236394770-thumb-link-%') as thumbnail_count;`);
  const query=file=>JSON.parse(cli(['db','query','--linked','--project-ref',project,'--file',file]));
  const state=query(preflight).rows?.[0];
  assertQAState(state);
  let spacePublication;
  if(spaceMode) {
    const rows=query(sqlFile('space-media-preflight.sql',`select id from public.spike_spaces where account_id=${q(account)} order by id;`)).rows;
    if(rows?.length!==62 || rows.some(row=>!row.id.startsWith('realcopy-b9d236394770-space-'))) throw Error('Reviewed Spaces changed');
    spacePublication=planSpaceMedia(JSON.parse(bytes),copies,new Set(rows.map(row=>row.id)));
    if(spacePublication.spaces.length!==60 || spacePublication.objects.size!==206
      || spacePublication.spaces.reduce((n,s)=>n+s.images.length,0)!==206
      || spacePublication.blocked.length!==2 || spacePublication.blocked.some(b=>b.reason!=='unavailable_source_reference')) throw Error('Space coverage differs from reviewed plan');
    console.log(JSON.stringify({spaceGalleries:60,spaceReferences:206,spaceObjects:206,blockedGalleries:2}));
    const observed=query(sqlFile('space-media-schema.sql',`select
      (select count(*) from public.space_media_sets where account_id=${q(account)}) as galleries,
      (select count(*) from public.space_media_references where account_id=${q(account)}) as refs;`)).rows[0];
    if(process.argv[2]==='--verify-spaces') {
      if(observed.galleries!==60 || observed.refs!==206) throw Error('Space publication counts differ');
      const objects=[...spacePublication.objects.values()].sort((a,b)=>a.bytes-b.bytes);
      for(const object of [objects.find(x=>x.contentType.startsWith('image/')),objects.find(x=>x.contentType==='application/pdf')].filter(Boolean)) {
        await verifyOwnerImageRead(spacePublication,auth,object.id);
      }
      console.log(JSON.stringify({verifiedSpaceGalleries:60,verifiedSpaceReferences:206,blockedGalleries:2,ownerBytesVerified:true,anonymousDenied:true}));
      return;
    }
  }
  let transactionPlan;
  if(['--plan-transactions','--apply-transactions','--verify-transactions'].includes(process.argv[2])) {
    const rows=query(sqlFile('transaction-media-preflight.sql',`select id from public.spike_transactions where account_id=${q(account)} order by id;`)).rows;
    if(rows?.length!==48 || rows.some(row=>!row.id.startsWith('realcopy-b9d236394770-transaction-'))) throw Error('Reviewed Transactions changed');
    transactionPlan=planTransactionMedia(JSON.parse(bytes),copies,new Set(rows.map(row=>row.id)));
    console.log(JSON.stringify({transactionSections:transactionPlan.sections.length,transactionReferences:transactionPlan.sections.reduce((n,s)=>n+s.images.length,0),transactionObjects:transactionPlan.objects.size,blockedSections:transactionPlan.blocked.length,blockedReasons:transactionPlan.blocked.reduce((r,b)=>(r[b.reason]=(r[b.reason]||0)+1,r),{})}));
    if(process.argv[2]==='--plan-transactions') return;
    if(transactionPlan.blocked.length || transactionPlan.sections.length!==96 || transactionPlan.sections.reduce((n,s)=>n+s.images.length,0)!==115) throw Error('Transaction attachment coverage needs review');
    if(process.argv[2]==='--verify-transactions') {
      const observed=query(sqlFile('transaction-media-verify.sql',`select
        (select count(*) from public.transaction_attachment_sets where account_id=${q(account)}) as sections,
        (select count(*) from public.transaction_attachment_references where account_id=${q(account)} and id like 'realcopy-b9d236394770-tx-ref-%') as refs;`)).rows[0];
      if(observed.sections!==96 || observed.refs!==115) throw Error('Transaction publication counts differ');
      const objects=[...transactionPlan.objects.values()].sort((a,b)=>a.bytes-b.bytes);
      for(const object of [objects.find(x=>x.contentType.startsWith('image/')),objects.find(x=>x.contentType==='application/pdf')].filter(Boolean)) {
        await verifyOwnerImageRead(transactionPlan,auth,object.id);
      }
      console.log(JSON.stringify({verifiedTransactionSections:96,verifiedTransactionReferences:115,ownerBytesVerified:true,anonymousDenied:true}));
      return;
    }
  }
  if(process.argv[2]==='--verify') {
    if(state.image_object_count!==plan.objects.size || state.image_set_count!==plan.items.length
        || state.image_reference_count!==plan.items.reduce((n,item)=>n+item.images.length,0)) throw Error('Published gallery counts differ');
    await verifyOwnerImageRead(plan,auth);
    console.log(JSON.stringify({verifiedOwnerRead:true,anonymousDenied:true,galleries:state.image_set_count,
      objects:state.image_object_count,references:state.image_reference_count,thumbnails:state.thumbnail_count}));
    return;
  }
  // The existing CLI credential reads this existing key; never print or save it.
  const keys=JSON.parse(cli(['projects','api-keys','--project-ref',project,'-o','json']));
  const key=keys.find(entry=>entry.name==='service_role')?.api_key;
  if(typeof key!=='string' || !key.startsWith('eyJ')) throw Error('Existing service key unavailable');
  if(spacePublication) {
    await uploadVerifiedOriginals(spacePublication,{apiURL:'https://'+project+'.supabase.co',
      mediaDirectory:selectedMediaDirectory,headers:{apikey:key,Authorization:'Bearer '+key},
      onProgress:(verified,total)=>console.log(JSON.stringify({verifiedSpaceObjects:verified,total}))});
    assertQAState(query(preflight).rows?.[0]);
    query(sqlFile('space-media-publication.sql',spacePublicationSQL(spacePublication,auth.principalId)));
    console.log(JSON.stringify({publishedSpaceGalleries:60,publishedSpaceReferences:206,blockedGalleries:2}));
    return;
  }
  if(transactionPlan) {
    await uploadVerifiedOriginals(transactionPlan,{apiURL:'https://'+project+'.supabase.co',
      mediaDirectory,headers:{apikey:key,Authorization:'Bearer '+key},
      onProgress:(verified,total)=>console.log(JSON.stringify({verifiedTransactionObjects:verified,total}))});
    assertQAState(query(preflight).rows?.[0]);
    query(sqlFile('transaction-media-publication.sql',transactionPublicationSQL(transactionPlan,auth.principalId)));
    console.log(JSON.stringify({publishedTransactionSections:transactionPlan.sections.length,publishedTransactionReferences:115}));
    return;
  }
  if(process.argv[2]==='--publish-thumbnails') {
    if(state.image_object_count!==819 || state.image_set_count!==725) throw Error('Publish originals first');
    const prepared=JSON.parse(fs.readFileSync(scratch+'/thumbnails/manifest.json'));
    if(prepared.blocked.length!==0 || prepared.records.length!==819) throw Error('Thumbnail coverage needs review');
    const statements=thumbnailPublicationSQL(plan,prepared.records,auth.principalId);
    const objects=new Map(prepared.records.map(record=>[record.thumbnail.id,record.thumbnail]));
    await uploadVerifiedOriginals({objects},{apiURL:'https://'+project+'.supabase.co',
      mediaDirectory:scratch+'/thumbnails',headers:{apikey:key,Authorization:'Bearer '+key},
      onProgress:(verified,total)=>console.log(JSON.stringify({verifiedThumbnails:verified,total}))});
    assertQAState(query(preflight).rows?.[0]);
    query(sqlFile('thumbnail-publication.sql',statements));
    console.log(JSON.stringify({publishedThumbnails:objects.size}));
    return;
  }
  await uploadVerifiedOriginals(plan,{
    apiURL:'https://'+project+'.supabase.co',mediaDirectory,
    headers:{apikey:key,Authorization:'Bearer '+key},
    onProgress:(verified,total)=>console.log(JSON.stringify({verified,total}))
  });
  assertQAState(query(preflight).rows?.[0]);
  query(sqlFile('media-publication.sql',publicationSQL(plan,auth.principalId)));
  console.log(JSON.stringify({publishedGalleries:plan.items.length,verifiedOriginals:plan.objects.size,
    blockedGalleries:plan.blocked.length,thumbnailsImported:false}));
}

function thumbnailPublicationSQL(plan,records,principal) {
  const seen=new Set(), statements=[];
  for(const record of records) {
    const original=plan.objects.get(record.originalId), thumbnail=record.thumbnail;
    const basename=hash(record.originalId);
    if(!original || seen.has(original.id) || original.sha256!==record.originalSHA256
        || record.recipe!=='item-card-300-jpeg-v1' || thumbnail.contentType!=='image/jpeg'
        || thumbnail.id!=='realcopy-b9d236394770-thumb-'+basename.slice(0,24)
        || thumbnail.file!==basename+'.jpg' || !/^[a-f0-9]{64}$/.test(thumbnail.sha256)
        || !Number.isSafeInteger(thumbnail.bytes) || thumbnail.bytes<1
        || !Number.isInteger(record.width) || !Number.isInteger(record.height)
        || record.width<1 || record.width>300 || record.height<1 || record.height>300) throw Error('Invalid prepared thumbnail');
    seen.add(original.id);
    const originalPath=`accounts/${account}/attachments/${original.id}/${original.sha256}`;
    const thumbnailPath=`accounts/${account}/attachments/${thumbnail.id}/${thumbnail.sha256}`;
    statements.push(`select ledger_private.publish_item_card_thumbnail(${q(account)},${q(original.id)},${q(original.sha256)},
      ${original.bytes},${q(original.contentType)},${q(originalPath)},${q(thumbnail.id)},${q(thumbnail.sha256)},
      ${thumbnail.bytes},'image/jpeg',${q(thumbnailPath)},${q('realcopy-b9d236394770-thumb-link-'+basename.slice(0,24))},
      ${q(record.recipe)},${record.width},${record.height});`);
  }
  // Reuse the same private Account lock and exact single-QA-owner gate.
  return publicationSQL({objects:new Map(),items:[]},principal).replace('set constraints all immediate;\ncommit;',
    statements.join('\n')+'\nset constraints all immediate;\ncommit;');
}

function prepareThumbnails(plan) {
  const output=scratch+'/thumbnails';
  fs.accessSync(root+'/LedgeriOS/.build/debug/LedgerItemThumbnail',fs.constants.X_OK);
  fs.mkdirSync(output,{recursive:true,mode:0o700});
  if(fs.lstatSync(output).isSymbolicLink()) throw Error('Unexpected thumbnail directory');
  const records=[], blocked=[];
  for(const original of plan.objects.values()) {
    const basename=hash(original.id), descriptor=output+'/'+basename+'.json', file=basename+'.jpg';
    if(fs.existsSync(descriptor)) {
      const saved=JSON.parse(fs.readFileSync(descriptor));
      const bytes=fs.readFileSync(output+'/'+file);
      if(saved.originalId!==original.id || saved.originalSHA256!==original.sha256
          || saved.recipe!=='item-card-300-jpeg-v1'
          || saved.thumbnail.id!=='realcopy-b9d236394770-thumb-'+basename.slice(0,24)
          || saved.thumbnail.file!==file || saved.thumbnail.sha256!==hash(bytes)
          || saved.thumbnail.bytes!==bytes.length) throw Error('Saved thumbnail changed');
      records.push(saved);
      continue;
    }
    const bytes=fs.readFileSync(mediaDirectory+'/'+original.file);
    if(hash(bytes)!==original.sha256 || bytes.length!==original.bytes) throw Error('Original changed');
    let generated;
    try {
      generated=JSON.parse(execFileSync(root+'/LedgeriOS/.build/debug/LedgerItemThumbnail',[],{
        input:JSON.stringify({accountId:account,attachmentId:original.id,sha256:original.sha256,
          byteCount:String(original.bytes),mediaType:original.contentType,
          storagePath:`accounts/${account}/attachments/${original.id}/${original.sha256}`,base64:bytes.toString('base64')}),
        encoding:'utf8',timeout:30000,maxBuffer:2*1024*1024,stdio:['pipe','pipe','pipe']
      }));
    } catch(error) {
      if(error.status!==1) throw Error('Native thumbnail producer could not run');
      blocked.push({originalId:original.id,reason:'native_producer_rejected'});
      continue;
    }
    const thumbnailBytes=Buffer.from(generated.base64,'base64');
    if(generated.recipe!=='item-card-300-jpeg-v1' || generated.mediaType!=='image/jpeg'
        || hash(thumbnailBytes)!==generated.sha256 || String(thumbnailBytes.length)!==generated.byteCount
        || !Number.isInteger(generated.width) || !Number.isInteger(generated.height)
        || generated.width<1 || generated.width>300 || generated.height<1 || generated.height>300) throw Error('Invalid native thumbnail');
    const record={originalId:original.id,originalSHA256:original.sha256,recipe:generated.recipe,
      width:generated.width,height:generated.height,thumbnail:{id:'realcopy-b9d236394770-thumb-'+basename.slice(0,24),
        file,bytes:thumbnailBytes.length,sha256:generated.sha256,contentType:'image/jpeg'}};
    if(fs.existsSync(output+'/'+file)) {
      if(hash(fs.readFileSync(output+'/'+file))!==generated.sha256) throw Error('Conflicting thumbnail bytes');
    } else fs.writeFileSync(output+'/'+file,thumbnailBytes,{mode:0o600,flag:'wx'});
    fs.writeFileSync(descriptor,JSON.stringify(record),{mode:0o600,flag:'wx'});
    records.push(record);
  }
  fs.writeFileSync(output+'/manifest.json',JSON.stringify({records,blocked}),{mode:0o600});
  console.log(JSON.stringify({preparedThumbnails:records.length,blocked:blocked.length,
    bytes:records.reduce((n,record)=>n+record.thumbnail.bytes,0),uploaded:false}));
}

async function verifyOwnerImageRead(plan,auth,imageID='realcopy-b9d236394770-image-9533fb01014edb7d969cfdd8') {
  const base='https://'+project+'.supabase.co';
  const apikey='sb_publishable_oAx8Wobv1rd1OZ9m_nrE1A_bOuo1T-H';
  const login=await fetch(base+'/auth/v1/token?grant_type=password',{
    method:'POST',headers:{apikey,'Content-Type':'application/json'},
    body:JSON.stringify({email:auth.email,password:auth.password}),redirect:'error',signal:AbortSignal.timeout(20000)
  });
  if(!login.ok) throw Error('QA sign-in failed');
  const session=await login.json();
  try {
    const image=plan.objects.get(imageID);
    if(!image) throw Error('Reviewed image missing');
    const objectPath=`accounts/${account}/attachments/${image.id}/${image.sha256}`.split('/').map(encodeURIComponent).join('/');
    const url=base+'/storage/v1/object/authenticated/ledger-attachments/'+objectPath;
    const owner=await fetch(url,{headers:{apikey,Authorization:'Bearer '+session.access_token},redirect:'error',signal:AbortSignal.timeout(20000)});
    if(!owner.ok) throw Error('Authorized image unavailable');
    const bytes=Buffer.from(await owner.arrayBuffer());
    if(bytes.length!==image.bytes || hash(bytes)!==image.sha256) throw Error('Owner received incorrect image');
    for(const endpoint of [url,url.replace('/authenticated/','/public/')]) {
      const anonymous=await fetch(endpoint,{headers:{apikey},redirect:'error',signal:AbortSignal.timeout(20000)});
      await anonymous.body?.cancel();
      if(![400,401,403,404].includes(anonymous.status)) throw Error('Anonymous image access was not denied');
    }
  } finally {
    await fetch(base+'/auth/v1/logout?scope=local',{method:'POST',headers:{apikey,Authorization:'Bearer '+session.access_token},
      redirect:'error',signal:AbortSignal.timeout(20000)});
  }
}
module.exports={assertQAState,thumbnailPublicationSQL};
if(require.main===module) main().catch(error=>{
  // CLI failures may contain credentials: expose only known transport failures.
  const safeMessages=['Hosted QA scope or private access changed','Reviewed Spaces changed','Space coverage differs from reviewed plan','Space publication counts differ','Storage read failed','Storage upload failed','Original bytes changed','Uploaded bytes unavailable','Storage bytes do not match source','Transaction publication counts differ','QA sign-in failed','Reviewed image missing','Authorized image unavailable','Owner received incorrect image','Anonymous image access was not denied'];
  const category=safeMessages.includes(error.message)?error.message:
    ['TimeoutError','AbortError'].includes(error.name)?error.name:'private_operation_failed';
  console.error('Hosted private media load stopped ('+category+'). No overwrite fallback; inspect retained state before retry.');
  process.exitCode=1;
});
