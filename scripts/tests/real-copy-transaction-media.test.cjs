const test=require('node:test'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {planMediaReferences,planTransactionMedia,transactionPublicationSQL,planExpenseReceipts}=require('../real-copy-transaction-media.cjs');
const transaction='realcopy-b9d236394770-transaction-'+crypto.createHash('sha256').update('one').digest('hex').slice(0,24);
const ids=new Set([transaction]);
const ref=(object,kind='image')=>({mapValue:{fields:{url:{stringValue:'https://firebasestorage.googleapis.com/v0/b/ledger-nine4.firebasestorage.app/o/'+object},kind:{stringValue:kind}}}});
const source=fields=>({account:'accounts/test',documents:[{name:'accounts/test/transactions/one',fields}]});
const array=values=>({arrayValue:{values}});
const copies=new Map(['image','pdf'].map(object=>[object,{object,contentType:object==='pdf'?'application/pdf':'image/jpeg',bytes:10,sha256:'a'.repeat(64),file:object}]));
test('shared receipt planning retains exact reference evidence and refuses partial mappings',()=>{
  const references=[ref('pdf','pdf'),ref('image')];
  references[0].mapValue.fields.fileName={stringValue:'Original receipt.pdf'};
  const plan=planMediaReferences(array(references),copies,'receipts');
  assert.deepEqual(plan.images.map(x=>x.sourceReference),references);
  assert.equal(plan.images[0].fileName,'Original receipt.pdf');
  assert.equal(planMediaReferences(array([...references,ref('missing')]),copies,'receipts').images,undefined);
  assert.equal(planMediaReferences({arrayValue:{values:{bad:true}}},copies,'receipts').reason,'invalid_section');
});
test('Expense receipts share validation but bind object IDs to the selected QA Account',()=>{
  const snapshot=source({receiptImages:array([ref('pdf','pdf'),ref('image')])});
  const account='realcopy-b9d236394770-check-0123456789ab-account';
  const plan=planExpenseReceipts(snapshot,copies,account,['one']);
  assert.equal(plan.blocked.length,0);
  assert.deepEqual(plan.receipts[0].images.map(x=>x.object),['pdf','image']);
  for(const image of plan.objects.values()) assert.equal(image.storagePath,`accounts/${account}/attachments/${image.id}/${image.sha256}`);
  assert.equal(planExpenseReceipts(snapshot,copies,account,[]).objects.size,0);
  assert.throws(()=>planExpenseReceipts(snapshot,copies,'foreign-account',['one']),/Unapproved/);
  assert.throws(()=>planExpenseReceipts(snapshot,copies,account,['missing']),/Missing/);
  const missing=planExpenseReceipts(snapshot,new Map(),account,['one']);
  assert.equal(missing.objects.size,0);assert.equal(missing.receipts.length,0);
  assert.equal(missing.blocked[0].reason,'original_not_copied');
});
test('only imported Transactions; image/PDF receipt order and empty other section preserved',()=>{
  const s=source({receiptImages:array([ref('pdf','pdf'),ref('image')])});
  assert.equal(planTransactionMedia(s,copies,new Set()).sections.length,0);
  const plan=planTransactionMedia(s,copies,ids);
  assert.equal(plan.sections.length,2);assert.equal(plan.blocked.length,0);
  assert.deepEqual(plan.sections[0].images.map(x=>x.object),['pdf','image']);
  assert.equal(plan.sections[1].images.length,0);
  for(const image of plan.objects.values()) image.storagePath=`accounts/realcopy-b9d236394770-account/attachments/${image.id}/${image.sha256}`;
  const sql=transactionPublicationSQL(plan,'upload-http-owner-test');
  assert.match(sql,/QA access changed/);assert.match(sql,/Existing Transaction attachment differs/);
  assert.match(sql,/file_name is not distinct from null/);assert.match(sql,/set constraints all immediate;/);
  assert.ok(!sql.includes('do $ begin'));assert.match(sql,/do \$\$ begin/);
});
test('unavailable, duplicate, malformed and unsupported sections never publish partial contents',()=>{
  for(const values of [[ref('image'),ref('missing')],[ref('image'),ref('image')],[ref('pdf','file')]]){
    const plan=planTransactionMedia(source({receiptImages:array(values)}),copies,ids);
    assert.equal(plan.blocked.length,1);assert.equal(plan.sections[0].section,'other');assert.equal(plan.objects.size,0);
  }
  assert.equal(planTransactionMedia(source({receiptImages:{stringValue:'bad'}}),copies,ids).blocked.length,1);
  assert.equal(planTransactionMedia(source({otherImages:array([ref('pdf','pdf')])}),copies,ids).blocked.length,1);
  assert.equal(planTransactionMedia(source({transactionImages:array([ref('image')])}),copies,ids).sections.length,0);
});
