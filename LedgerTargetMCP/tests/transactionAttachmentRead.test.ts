import assert from "node:assert/strict";
import test from "node:test";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { attachmentResponseJSON, transactionAttachmentPage } from "../src/transactionAttachmentRead.js";
import { SupabaseTransactionDetailReader } from "../src/transactionDetailRead.js";
import { createTargetServer } from "../src/server.js";

const context = { accountId: "account", principalId: "member",
  accessToken: `e30.${Buffer.from(JSON.stringify({role:"authenticated"})).toString("base64url")}.signature` };
const input = { transactionId: "transaction", section: "receipts" } as const;
const page = () => ({ accountId: "account", principalId: "member", transactionId: "transaction",
  scopeKind: "business_inventory", projectId: null, clientId: null, section: "receipts", revision: "9007199254740993",
  expectedCount: 1, startPosition: 0, isComplete: true, nextPosition: null,
  attachments: [{id:"reference",position:0,isPrimary:true,kind:"pdf",fileName:"Receipt.pdf"}] });

test("known, empty and unknown attachment sections remain distinct", () => {
  assert.deepEqual(transactionAttachmentPage(page(),input,context),page());
  const empty = {...page(),expectedCount:0,attachments:[]};
  assert.equal(transactionAttachmentPage(empty,input,context).isComplete,true);
  const unknown = {...empty,expectedCount:null,revision:null,isComplete:false};
  assert.deepEqual(transactionAttachmentPage(unknown,input,context),unknown);
  assert.throws(()=>transactionAttachmentPage({...unknown,isComplete:true},input,context));
});
test("ordered page coverage, next cursor and exact revision are verified", () => {
  const first = {...page(),expectedCount:2,isComplete:false,nextPosition:1};
  assert.deepEqual(transactionAttachmentPage(first,{...input,limit:1},context),first);
  const last = {...first,startPosition:1,nextPosition:null,attachments:[{...page().attachments[0],position:1}]};
  const cursor = {...input,startPosition:1,limit:1,revision:first.revision};
  assert.deepEqual(transactionAttachmentPage(last,cursor,context),last);
  for (const patch of [{isComplete:true},{nextPosition:2},{revision:"2"},{startPosition:0},{expectedCount:3},
    {attachments:[]},{attachments:[{...last.attachments[0],position:2}]}]) {
    assert.throws(()=>transactionAttachmentPage({...last,...patch},cursor,context),{code:"transaction_attachment_server_result_mismatch"});
  }
});
test("identity and private/provider metadata cannot enter a public attachment page", () => {
  for (const patch of [{accountId:"foreign"},{principalId:"foreign"},{transactionId:"other"},{section:"other"},
    {projectId:"foreign"},{clientId:"foreign"},{storagePath:"secret"},
    {attachments:[{...page().attachments[0],storagePath:"secret"}]},
    {attachments:[{...page().attachments[0],kind:"html"}]}]) {
    assert.throws(()=>transactionAttachmentPage({...page(),...patch},input,context),{code:"transaction_attachment_server_result_mismatch"});
  }
});
test("HTTP uses host identity, bounded inputs, safe errors and exact page parsing", async () => {
  let calls=0,status=200;
  const reader = new SupabaseTransactionDetailReader(new URL("https://target.invalid"),"sb_publishable_fixture",async(url,init)=>{
    calls++;
    assert.equal(String(url),"https://target.invalid/rest/v1/rpc/spike_read_transaction_attachments");
    assert.equal(init?.redirect,"error");
    assert.equal(new Headers(init?.headers).get("Authorization"),`Bearer ${context.accessToken}`);
    assert.deepEqual(JSON.parse(init?.body as string),{p_account_id:"account",p_transaction_id:"transaction",p_section:"receipts",
      p_start_position:0,p_limit:50,p_revision:null});
    return Response.json(status===200?page():{secret:"never disclose"},{status});
  });
  assert.deepEqual(await reader.attachments(input,context),page());
  for(const [code,error] of [[401,"authentication_required"],[403,"transaction_not_available"],
    [409,"transaction_attachment_revision_changed"],[500,"transaction_attachment_read_failed"]] as const){
    status=code; await assert.rejects(reader.attachments(input,context),{code:error});
  }
  for(const patch of [{accountId:"foreign"},{limit:101},{limit:0},{startPosition:1},{revision:"01"},
    ...["0"," 1","1\n","1x","9223372036854775808"].map(revision=>({revision})),{section:"bad"}]) {
    await assert.rejects(reader.attachments({...input,...patch} as never,context),{code:"transaction_attachment_page_invalid"});
  }
  assert.equal(calls,5);
});
test("decoded body cap cancels an oversized response", async () => {
  let cancelled=false;
  const response = new Response(new ReadableStream({
    start(controller){controller.enqueue(new Uint8Array(2*1024*1024+1));},cancel(){cancelled=true;},
  }));
  await assert.rejects(attachmentResponseJSON(response),{code:"transaction_attachment_response_too_large"});
  assert.equal(cancelled,true);
});
test("MCP registers a read-only paginated capability on the existing Transaction reader", async () => {
  const reader = {read:async()=>assert.fail("wrong read"),attachments:async(args:typeof input,identity:typeof context)=>{
    assert.deepEqual(identity,context); return transactionAttachmentPage(page(),args,identity);
  }};
  const server=createTargetServer({read:async()=>assert.fail("wrong tool")},context,undefined,undefined,undefined,reader);
  const client=new Client({name:"attachment-test",version:"1"});
  const [a,b]=InMemoryTransport.createLinkedPair(); await server.connect(a); await client.connect(b);
  try{
    const tool=(await client.listTools()).tools.find(v=>v.name==="get_transaction_attachments");
    assert.equal(tool?.annotations?.readOnlyHint,true);
    assert.notEqual((await client.callTool({name:tool!.name,arguments:input})).isError,true);
    assert.equal((await client.callTool({name:tool!.name,arguments:{...input,accountId:"foreign"}})).isError,true);
  }finally{await client.close();await server.close();}
});
