const crypto = require('node:crypto');
const {storageURL} = require('./copy-authorized-project-media.cjs');
const {publicationSQL} = require('./load-real-copy-item-media.cjs');
const account = 'realcopy-b9d236394770-account';
const id = (kind, value) => 'realcopy-b9d236394770-' + kind + '-' + crypto.createHash('sha256').update(value).digest('hex').slice(0,24);
const q = value => value == null ? 'null' : "'" + String(value).replaceAll("'", "''") + "'";

// Shared by Transaction sections and Expense receipt migration. This plans
// references only: copies must come from verifiedCopies, and publication still
// requires uploadVerifiedOriginals. Keep the exact source reference for binding.
function planMediaReferences(raw, copies, section) {
  if (raw && !('nullValue' in raw) && !('arrayValue' in raw)) return {reason:'invalid_section'};
  const values = raw?.arrayValue?.values ?? [];
  if (!Array.isArray(values)) return {reason:'invalid_section'};
  const images = [];
  for (const value of values) {
    const fields = value?.mapValue?.fields;
    let object;
    try { object = storageURL(fields?.url?.stringValue).object; }
    catch { return {reason:'unavailable_source_reference'}; }
    const copy = copies.get(object);
    if (!copy) return {reason:'original_not_copied'};
    const image = fields.kind?.stringValue === 'image' && /^image\/[a-z0-9.+-]+$/.test(copy.contentType);
    const pdf = fields.kind?.stringValue === 'pdf' && section === 'receipts' && copy.contentType === 'application/pdf';
    if (!image && !pdf) return {reason:'unsupported_media'};
    if (images.some(x=>x.object===object)) return {reason:'duplicate_source_object'};
    if (fields.isPrimary && !('nullValue' in fields.isPrimary) && typeof fields.isPrimary.booleanValue !== 'boolean') return {reason:'invalid_primary'};
    if (fields.fileName && !('nullValue' in fields.fileName) && typeof fields.fileName.stringValue !== 'string') return {reason:'invalid_filename'};
    images.push({...copy,id:id('tx-media',object),primary:fields.isPrimary?.booleanValue===true,fileName:fields.fileName?.stringValue??null,sourceReference:value});
  }
  return {images};
}

// Only already-imported Transactions are eligible. A missing original blocks
// its whole section, never turns a partial import into an apparently empty one.
function planSpaceMedia(source, copies, spaceIDs) {
  const spaces = [], blocked = [], objects = new Map();
  for (const document of source.documents) {
    const prefix = source.account + '/spaces/';
    if (!document.name.startsWith(prefix) || document.name.slice(prefix.length).includes('/')) continue;
    const sourceID = document.name.slice(prefix.length), space = id('space',sourceID);
    if (!spaceIDs.has(space)) continue;
    // Space galleries permit both original images and PDFs. Reuse the same
    // verified-copy and exact-reference validation as receipt attachments.
    const planned = planMediaReferences(document.fields?.images,copies,'receipts');
    if (planned.reason) { blocked.push({sourceID,reason:planned.reason}); continue; }
    const images = planned.images;
    const explicit = images.findIndex(image => image.primary);
    spaces.push({id:id('space-set',sourceID),space,sourceID,images,primaryIndex:explicit < 0 ? 0 : explicit});
    for (const image of images) objects.set(image.id,image);
  }
  return {spaces,blocked,objects};
}

function planTransactionMedia(source, copies, transactionIDs) {
  const sections = [], blocked = [], objects = new Map();
  for (const document of source.documents) {
    const prefix = source.account + '/transactions/';
    if (!document.name.startsWith(prefix) || document.name.slice(prefix.length).includes('/')) continue;
    const sourceID = document.name.slice(prefix.length), transaction = id('transaction',sourceID);
    if (!transactionIDs.has(transaction)) continue;
    for (const [field,section] of [['receiptImages','receipts'],['otherImages','other']]) {
      const planned = planMediaReferences(document.fields?.[field], copies, section);
      const images = planned.images || [];
      let reason = planned.reason;
      if (document.fields?.transactionImages?.arrayValue?.values?.length) reason = 'legacy_section_needs_review';
      if (reason) { blocked.push({transaction,section,reason}); continue; }
      const explicit = images.findIndex(x=>x.primary);
      sections.push({id:id('tx-set',sourceID+':'+section),transaction,section,images,primaryIndex:explicit<0?0:explicit});
      for (const image of images) objects.set(image.id,image);
    }
  }
  return {sections,blocked,objects};
}

function transactionPublicationSQL(plan, principal) {
  const statements = [];
  for (const section of plan.sections) {
    const values = [section.id,account,section.transaction,section.section].map(q).join(',');
    statements.push(`insert into public.transaction_attachment_sets(id,account_id,transaction_id,section,revision,expected_count) values(${values},1,${section.images.length}) on conflict(id) do nothing;`);
    statements.push(`do $$ begin if not exists(select 1 from public.transaction_attachment_sets where id=${q(section.id)} and account_id=${q(account)} and transaction_id=${q(section.transaction)} and section=${q(section.section)} and revision=1 and expected_count=${section.images.length}) then raise exception 'Existing Transaction section differs'; end if; end $$;`);
    section.images.forEach((image,position)=>{
      const reference=id('tx-ref',section.id+':'+position),primary=position===section.primaryIndex;
      statements.push(`insert into public.transaction_attachment_references(id,account_id,transaction_id,section,attachment_id,set_revision,position,is_primary,file_name) values(${[reference,account,section.transaction,section.section,image.id].map(q).join(',')},1,${position},${primary},${q(image.fileName)}) on conflict(id) do nothing;`);
      statements.push(`do $$ begin if not exists(select 1 from public.transaction_attachment_references where id=${q(reference)} and account_id=${q(account)} and transaction_id=${q(section.transaction)} and section=${q(section.section)} and attachment_id=${q(image.id)} and set_revision=1 and position=${position} and is_primary=${primary} and file_name is not distinct from ${q(image.fileName)}) then raise exception 'Existing Transaction attachment differs'; end if; end $$;`);
    });
  }
  return publicationSQL({items:[],objects:plan.objects},principal).replace('set constraints all immediate;',()=>statements.join('\n')+'\nset constraints all immediate;');
}
function spacePublicationSQL(plan, principal) {
  const statements=[];
  for(const gallery of plan.spaces) {
    statements.push(`insert into public.space_media_sets(id,account_id,space_id,revision,expected_count) values(${[gallery.id,account,gallery.space].map(q).join(',')},1,${gallery.images.length}) on conflict(id) do nothing;`);
    statements.push(`do $$ begin if not exists(select 1 from public.space_media_sets where id=${q(gallery.id)} and account_id=${q(account)} and space_id=${q(gallery.space)} and revision=1 and expected_count=${gallery.images.length}) then raise exception 'Existing Space gallery differs'; end if; end $$;`);
    gallery.images.forEach((image,position)=>{
      const reference=id('space-ref',gallery.sourceID+':'+position),primary=position===gallery.primaryIndex;
      statements.push(`insert into public.space_media_references(id,account_id,space_id,attachment_id,set_revision,position,is_primary,file_name) values(${[reference,account,gallery.space,image.id].map(q).join(',')},1,${position},${primary},${q(image.fileName)}) on conflict(id) do nothing;`);
      statements.push(`do $$ begin if not exists(select 1 from public.space_media_references where id=${q(reference)} and account_id=${q(account)} and space_id=${q(gallery.space)} and attachment_id=${q(image.id)} and set_revision=1 and position=${position} and is_primary=${primary} and file_name is not distinct from ${q(image.fileName)}) then raise exception 'Existing Space reference differs'; end if; end $$;`);
    });
  }
  return publicationSQL({items:[],objects:plan.objects},principal).replace('set constraints all immediate;',()=>statements.join('\n')+'\nset constraints all immediate;');
}
// Receipt planning for the Swift financial importer. It supplies the accepted
// source IDs only after complete Invoice validation; no rejected Invoice's
// originals are uploaded. Source references stay in the original snapshot.
function planExpenseReceipts(source, copies, targetAccountID, sourceIDs) {
  if (!/^realcopy-b9d236394770(?:-check-[a-f0-9]{12})?-account$/.test(targetAccountID)) throw Error('Unapproved QA Account');
  const receipts=[], blocked=[], objects=new Map();
  const selected=new Set(sourceIDs), seen=new Set();
  for (const document of source.documents) {
    const prefix=source.account+'/transactions/';
    if (!document.name.startsWith(prefix)) continue;
    const sourceID=document.name.slice(prefix.length);
    if (sourceID.includes('/') || !selected.has(sourceID)) continue;
    if (seen.has(sourceID)) throw Error('Duplicate receipt source');
    seen.add(sourceID);
    const plan=planMediaReferences(document.fields?.receiptImages,copies,'receipts');
    if (plan.reason) { blocked.push({sourceID,reason:plan.reason}); continue; }
    const images=plan.images.map(image=>{
      const objectID=targetAccountID.slice(0,-'-account'.length)+'-tx-media-'+crypto.createHash('sha256').update(image.object).digest('hex').slice(0,24);
      return {...image,id:objectID,storagePath:`accounts/${targetAccountID}/attachments/${objectID}/${image.sha256}`};
    });
    receipts.push({sourceID,images});
    for (const image of images) objects.set(image.id,image);
  }
  if ([...selected].some(sourceID=>!seen.has(sourceID))) throw Error('Missing receipt source');
  return {receipts,blocked,objects};
}

async function expenseReceiptCommand() {
  const fs=require('node:fs'),path=require('node:path'),{execFileSync}=require('node:child_process');
  const {verifiedCopies}=require('./copy-authorized-project-media.cjs');
  const {uploadVerifiedOriginals}=require('./load-real-copy-item-media.cjs');
  const root='/Users/benjaminmackenzie/Dev/ledger_mobile_supabase', privateRoot=root+'/tmp/real-project-copy';
  const mode=process.argv[2];
  if (process.cwd()!==root || process.argv.length!==3 || !['--plan-expense-receipts','--verify-expense-receipts','--upload-expense-receipts'].includes(mode)) throw Error('Unexpected receipt command');
  const request=JSON.parse(fs.readFileSync(0,'utf8'));
  const snapshot=path.resolve(request.snapshotPath), directory=path.resolve(request.mediaDirectory);
  if (path.dirname(snapshot)!==privateRoot || path.dirname(directory)!==privateRoot || !path.basename(directory).startsWith('media-')) throw Error('Private media paths required');
  for (const [file,isDirectory] of [[snapshot,false],[directory,true],[path.join(directory,'source.json'),false]]) {
    const stat=fs.lstatSync(file);
    if (stat.isSymbolicLink() || (isDirectory?!stat.isDirectory():!stat.isFile()) || stat.uid!==process.getuid() || (stat.mode&0o077)) throw Error('Private ordinary media artifact required');
  }
  const bytes=fs.readFileSync(snapshot), sourceSHA256=crypto.createHash('sha256').update(bytes).digest('hex');
  const identity=JSON.parse(fs.readFileSync(path.join(directory,'source.json')));
  if (identity.sha256!==sourceSHA256 || identity.input!==snapshot) throw Error('Copied media belongs to another snapshot');
  const source=JSON.parse(bytes);
  if (source.account!=='projects/ledger-nine4/databases/(default)/documents/accounts/1dd4fd75-8eea-4f7a-98e7-bf45b987ae94') throw Error('Unexpected source Account');
  const checkAccount='realcopy-b9d236394770-check-'+sourceSHA256.slice(0,12)+'-account';
  if (![checkAccount,'realcopy-b9d236394770-account'].includes(request.targetAccountID)) throw Error('Unexpected target Account');
  if (!Array.isArray(request.sourceIDs) || request.sourceIDs.some(x=>typeof x!=='string') || new Set(request.sourceIDs).size!==request.sourceIDs.length) throw Error('Invalid selected receipt sources');
  const selectedObjects=new Set();
  for (const doc of source.documents) {
    if (!request.sourceIDs.some(sourceID=>doc.name===source.account+'/transactions/'+sourceID)) continue;
    const values=doc.fields?.receiptImages?.arrayValue?.values;
    if (!Array.isArray(values)) continue;
    for (const value of values) {
      try { selectedObjects.add(storageURL(value?.mapValue?.fields?.url?.stringValue).object); }
      catch { /* Planner records an unavailable reference; never fetch it. */ }
    }
  }
  const plan=planExpenseReceipts(source,verifiedCopies(directory,selectedObjects),request.targetAccountID,request.sourceIDs);
  if (mode!=='--plan-expense-receipts') {
    if (plan.blocked.length) throw Error('Accepted Expense media is incomplete');
    if (mode==='--upload-expense-receipts' && request.targetAccountID!==account) throw Error('Check Accounts cannot upload');
    if (plan.objects.size) {
      if (process.env.DOCKER_HOST || process.env.DOCKER_CONTEXT) throw Error('No remote Docker overrides');
      const local=JSON.parse(execFileSync('npx',['--offline','--yes','supabase@2.116.0','status','-o','json'],{encoding:'utf8',timeout:15000,stdio:['ignore','pipe','ignore']}));
      if (local.API_URL!=='http://127.0.0.1:54321' || !local.SERVICE_ROLE_KEY) throw Error('Local Storage unavailable');
      const headers={apikey:local.SERVICE_ROLE_KEY,Authorization:'Bearer '+local.SERVICE_ROLE_KEY};
      await uploadVerifiedOriginals(plan,{apiURL:local.API_URL,headers,mediaDirectory:directory,targetAccountID:request.targetAccountID,allowUpload:mode==='--upload-expense-receipts'});
    }
  }
  // Omit URL/token-bearing references from output. Swift binds ordered metadata
  // to its own decoded copy of this exact snapshot, then validates the draft.
  console.log(JSON.stringify({sourceSHA256,accountID:request.targetAccountID,blocked:plan.blocked,
    receipts:plan.receipts.map(({sourceID,images})=>({sourceID,images:images.map(image=>({id:image.id,sha256:image.sha256,byteCount:String(image.bytes),mediaType:image.contentType,storagePath:image.storagePath}))}))}));
}
module.exports={planMediaReferences,planSpaceMedia,spacePublicationSQL,planTransactionMedia,transactionPublicationSQL,planExpenseReceipts};
if (require.main===module) expenseReceiptCommand().catch(()=>{console.error('Expense receipt preparation failed; no financial import authorized.');process.exitCode=1;});
