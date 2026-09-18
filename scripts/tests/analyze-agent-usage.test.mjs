import assert from 'node:assert/strict';
import test from 'node:test';
import { analyze } from '../analyze-agent-usage.mjs';
const usage = (input, cached, output = 2) => ({ input_tokens: input, cached_input_tokens: cached, output_tokens: output, total_tokens: input + output });
const count = (time, total, last = total) => ({ timestamp: `2026-09-18T00:00:${time}.000Z`, type: 'event_msg', payload: { type: 'token_count', info: { total_token_usage: total, last_token_usage: last } } });
const item = (payload) => ({ timestamp: '2026-09-18T00:00:01.000Z', type: 'response_item', payload });
test('cumulative counters, duplicates and reasoning never double count', async () => {
  const a = usage(100, 80), b = usage(250, 200, 7), delta = usage(150, 120, 5);
  delta.reasoning_output_tokens = 3;
  const r = await analyze([count('00', a), count('00', a), count('02', b, delta)]);
  assert.equal(r.requests, 2); assert.equal(r.duplicateStatusEvents, 1);
  assert.equal(r.usage.total_tokens, 257); assert.equal(r.usage.uncached_input_tokens, 50);
  assert.equal(r.deltaLastUsageMismatches, 0);
});
test('time boundary subtracts previous counter and excludes later events', async () => {
  const r = await analyze([count('00', usage(100,80)), count('02',usage(150,100,4),usage(50,20)), count('04',usage(300,200,6))], { from:'2026-09-18T00:00:01.000Z', to:'2026-09-18T00:00:03.000Z' });
  assert.equal(r.requests,1); assert.equal(r.usage.input_tokens,50);
});
test('reset and missing increment evidence stay explicit', async () => {
  const r = await analyze([count('00',usage(100,80)), count('02',usage(30,20)), count('03',usage(60,40))]);
  assert.equal(r.counterResets,1); assert.equal(r.usage.input_tokens,160);
  assert.equal(r.deltaLastUsageMismatches,1);
});
test('content proxies exclude ciphertext and classify reads without inventing tokens', async () => {
  const r = await analyze([
    item({type:'message',role:'developer',content:[{text:'rules'}]}),
    item({type:'agent_message',content:[{type:'encrypted_content',encrypted_content:'gAAAAAsecret'}]}),
    item({type:'custom_tool_call',call_id:'x',input:'cat docs/spec.md',name:'exec'}),
    item({type:'custom_tool_call_output',call_id:'x',output:[{text:'spec text'}]}),
    count('02',usage(100,80)), count('03',usage(200,160,4),usage(100,80))
  ]);
  assert.equal(r.contentProxy.recordedCharacters.guidance_spec_reads,9);
  assert.equal(r.contentProxy.repeatedRecordedCharacterExposure.instructions,10);
  assert.equal(r.contentProxy.opaqueRecords,1);
  assert.equal(r.heuristicRequestActions.reading_or_inspection.requests,1);
});
test('compaction does not pretend old text remains retained', async () => {
  const r = await analyze([item({type:'message',role:'developer',content:[{text:'rules'}]}),count('02',usage(100,80)),{type:'compacted',timestamp:'2026-09-18T00:00:03.000Z',payload:{}},count('04',usage(200,160,4),usage(100,80))]);
  assert.equal(r.contentProxy.compactions,1);
  assert.equal(r.contentProxy.repeatedRecordedCharacterExposure.instructions,5);
});
test('cache writes are separate from ordinary uncached input', async () => {
  const u = {...usage(100,60), cache_write_input_tokens:10};
  const r = await analyze([count('00',u)]);
  assert.equal(r.usage.uncached_input_tokens,30);
  assert.equal(r.usage.cache_write_input_tokens,10);
});
test('encrypted function arguments are not treated as readable context', async () => {
  const r = await analyze([item({type:'function_call',name:'send_message',arguments:JSON.stringify({message:'gAAAAAsecret',target:'worker'})}),count('02',usage(100,80))]);
  assert.equal(r.contentProxy.recordedCharacters.tool_commands,6);
  assert.equal(r.contentProxy.opaqueRecords,1);
  assert.equal(r.heuristicRequestActions.coordination.requests,1);
});
test('empty measurements remain empty, malformed counters fail visibly', async () => {
  const r = await analyze([]);
  assert.equal(r.requests,0); assert.equal(r.usage.total_tokens,0);
  await assert.rejects(analyze([count('00',usage(-1,0))]),/Invalid usage/);
});
