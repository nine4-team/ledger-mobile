const test = require('node:test');
const assert = require('node:assert/strict');
const { planItemMedia, publicationSQL, uploadVerifiedOriginals } = require('../load-real-copy-item-media.cjs');
const { assertQAState, thumbnailPublicationSQL } = require('../load-hosted-real-copy-item-media.cjs');
const base = 'https://firebasestorage.googleapis.com/v0/b/ledger-nine4.firebasestorage.app/o/';
const ref = (object, primary) => ({ mapValue:{fields:{url:{stringValue:base+object},kind:{stringValue:'image'},
  ...(primary === undefined ? {} : {isPrimary:{booleanValue:primary}})}} });
const source = images => ({ account:'accounts/test', documents:[{name:'accounts/test/items/item',fields:{images:{arrayValue:{values:images}}}}] });
const copies = new Map(['one','two'].map(object=>[object,{object,contentType:'image/jpeg',sha256:'a'.repeat(64),bytes:10,file:object}]));
test('preserves order and shipped first-primary fallback without inventing a viewer',()=>{
  let plan=planItemMedia(source([ref('one'),ref('two',true)]),copies);
  assert.equal(plan.items[0].primaryIndex,1);
  assert.deepEqual(plan.items[0].images.map(x=>x.object),['one','two']);
  assert.equal(planItemMedia(source([ref('one'),ref('two')]),copies).items[0].primaryIndex,0);
  assert.equal(planItemMedia(source([ref('one',true),ref('two',true)]),copies).items[0].primaryIndex,0);
});
test('missing bytes and duplicate references do not become truncated galleries',()=>{
  for(const images of [[ref('one'),ref('missing')],[ref('one'),ref('one')]]) {
    const plan=planItemMedia(source(images),copies);
    assert.equal(plan.items.length,0);assert.equal(plan.objects.size,0);assert.equal(plan.blocked.length,1);
  }
});
test('known empty legacy galleries remain distinct from malformed galleries',()=>{
  assert.equal(planItemMedia(source([]),copies).items[0].images.length,0);
  const bad=source([]);bad.documents[0].fields.images={stringValue:'invalid'};
  assert.equal(planItemMedia(bad,copies).items.length,0);
});
test('shared publication retains exact private QA membership and non-overwrite checks',()=>{
  const plan=planItemMedia(source([ref('one')]),copies);
  for(const image of plan.objects.values()) image.storagePath=`accounts/realcopy-b9d236394770-account/attachments/${image.id}/${image.sha256}`;
  const sql=publicationSQL(plan,'upload-http-owner-test');
  assert.match(sql,/pg_advisory_xact_lock/);
  assert.match(sql,/QA access changed/);
  assert.match(sql,/Existing image differs/);
  assert.match(sql,/Existing gallery reference differs/);
  assert.match(sql,/on conflict\(id\) do nothing/);
  assert.ok(sql.endsWith('set constraints all immediate;\ncommit;'));
  assert.throws(()=>publicationSQL(plan,'real-user'),/Unexpected QA principal/);
  plan.objects.values().next().value.storagePath='accounts/other/attachments/file';
  assert.throws(()=>publicationSQL(plan,'upload-http-owner-test'),/Unexpected object destination/);
});
test('hosted publication requires one verified QA owner and a private bucket',()=>{
  const valid={membership_count:1,qa_owner_count:1,private_bucket:true,copied_item_count:1375};
  assert.doesNotThrow(()=>assertQAState(valid));
  // App-created QA Items must not invalidate the unchanged source-copy scope.
  assert.doesNotThrow(()=>assertQAState({...valid,item_count:1394}));
  for(const [key,value] of Object.entries({membership_count:2,qa_owner_count:0,private_bucket:false,copied_item_count:0})) {
    assert.throws(()=>assertQAState({...valid,[key]:value}),/QA scope/);
  }
});
test('thumbnail publication binds the existing producer output to its exact original',()=>{
  const crypto=require('node:crypto');
  const plan=planItemMedia(source([ref('one')]),copies);
  const original=plan.objects.values().next().value;
  const basename=crypto.createHash('sha256').update(original.id).digest('hex');
  const record={originalId:original.id,originalSHA256:original.sha256,recipe:'item-card-300-jpeg-v1',
    width:200,height:100,thumbnail:{id:'realcopy-b9d236394770-thumb-'+basename.slice(0,24),
      file:basename+'.jpg',bytes:20,sha256:'b'.repeat(64),contentType:'image/jpeg'}};
  const sql=thumbnailPublicationSQL(plan,[record],'upload-http-owner-test');
  assert.match(sql,/publish_item_card_thumbnail/);
  assert.match(sql,/QA access changed/);
  assert.ok(sql.includes(original.id));
  assert.throws(()=>thumbnailPublicationSQL(plan,[record,record],'upload-http-owner-test'),/Invalid prepared/);
  assert.throws(()=>thumbnailPublicationSQL(plan,[{...record,originalSHA256:'c'.repeat(64)}],'upload-http-owner-test'),/Invalid prepared/);
  assert.throws(()=>thumbnailPublicationSQL(plan,[{...record,thumbnail:{...record.thumbnail,file:'../other'}}],'upload-http-owner-test'),/Invalid prepared/);
});
test('transport verifies existing originals without overwriting or accepting corrupt data',async()=>{
  const crypto=require('node:crypto');
  const bytes=Buffer.from('original');
  const plan={objects:new Map([['one',{id:'one',file:'unused',bytes:bytes.length,sha256:crypto.createHash('sha256').update(bytes).digest('hex')}]])};
  const options={apiURL:'https://ybwviepljilrkrjoahbl.supabase.co',headers:{},mediaDirectory:'/unused'};
  let reads=0;
  await uploadVerifiedOriginals(plan,{...options,fetchImpl:async(url,request)=>{
    reads++;assert.equal(request.method,undefined);assert.equal(request.redirect,'error');
    assert.match(url,/accounts\/realcopy-b9d236394770-account\/attachments\/one\//);
    return new Response(bytes);
  }});
  assert.equal(reads,1);
  await assert.rejects(uploadVerifiedOriginals(plan,{...options,fetchImpl:async()=>new Response('corrupt')}),/do not match/);
  await assert.rejects(uploadVerifiedOriginals(plan,{...options,apiURL:'https://other.supabase.co'}),/Unapproved/);
});
test('missing original uploads once without upsert, then verifies stored bytes',async()=>{
  const fs=require('node:fs'), os=require('node:os'), path=require('node:path'), crypto=require('node:crypto');
  const directory=fs.mkdtempSync(path.join(os.tmpdir(),'ledger-media-transport-'));
  const bytes=Buffer.from('verified source bytes');
  fs.writeFileSync(path.join(directory,'image'),bytes);
  const plan={objects:new Map([['one',{id:'one',file:'image',bytes:bytes.length,contentType:'image/jpeg',sha256:crypto.createHash('sha256').update(bytes).digest('hex')}]])};
  const calls=[];
  try {
    await uploadVerifiedOriginals(plan,{apiURL:'http://127.0.0.1:54321',headers:{},mediaDirectory:directory,
      fetchImpl:async(url,request)=>{
        calls.push(request.method||'GET');
        if(calls.length===1) return new Response('',{status:404});
        if(request.method==='POST') {
          assert.equal(request.headers['x-upsert'],'false');
          assert.deepEqual(request.body,bytes);
          return new Response('{}');
        }
        return new Response(bytes);
      }});
    assert.deepEqual(calls,['GET','POST','GET']);
    fs.writeFileSync(path.join(directory,'image'),'changed');
    let requests=0;
    await assert.rejects(uploadVerifiedOriginals(plan,{apiURL:'http://127.0.0.1:54321',headers:{},mediaDirectory:directory,
      fetchImpl:async()=>{requests++;return new Response('',{status:404});}}),/Original bytes changed/);
    assert.equal(requests,1,'Changed source is rejected before any upload');
  } finally { fs.rmSync(directory,{recursive:true}); }
});
test('check mode never uploads missing bytes and honors the isolated receipt Account',async()=>{
  const account='realcopy-b9d236394770-check-0123456789ab-account';
  const plan={objects:new Map([['one',{id:'one',file:'unused',bytes:1,sha256:'a'.repeat(64)}]])};
  let requests=0;
  await assert.rejects(uploadVerifiedOriginals(plan,{apiURL:'http://127.0.0.1:54321',headers:{},mediaDirectory:'/unused',targetAccountID:account,allowUpload:false,
    fetchImpl:async(url,request)=>{
      requests++;assert.equal(request.method,undefined);assert.ok(url.includes(`/accounts/${account}/`));
      return new Response('',{status:404});
    }}),/check mode never uploads/);
  assert.equal(requests,1);
  await assert.rejects(uploadVerifiedOriginals(plan,{apiURL:'http://127.0.0.1:54321',targetAccountID:'foreign'}),/Unapproved QA/);
});
