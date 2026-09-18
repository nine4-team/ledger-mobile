#!/usr/bin/env node
// Offline only: consumes existing rollout JSONL, never calls a model or service.
import { createReadStream } from 'node:fs';
import { createInterface } from 'node:readline';
import { pathToFileURL } from 'node:url';

const fields = ['input_tokens', 'cached_input_tokens', 'cache_write_input_tokens', 'output_tokens', 'total_tokens'];
const zeros = () => Object.fromEntries(fields.map(k => [k, 0]));
function readable(value) {
  if (typeof value === 'string') return /^(gAAAAA|data:image\/)/.test(value) ? '' : value;
  if (Array.isArray(value)) return value.map(readable).join('');
  if (!value || typeof value !== 'object' || value.type === 'encrypted_content') return '';
  return typeof value.text === 'string' ? readable(value.text) : '';
}
function category(p, calls) {
  if (p.type === 'message') return ['system', 'developer'].includes(p.role) ? 'instructions' : 'conversation';
  if (p.type === 'agent_message') return 'agent_exchanges';
  if (p.type === 'reasoning') return 'visible_reasoning';
  if (/call_output$/.test(p.type)) {
    const command = calls.get(p.call_id) || '';
    if (/AGENTS\.md|SKILL\.md|docs\//.test(command)) return 'guidance_spec_reads';
    if (/\b(sed|cat|rg|head)\b|git diff/.test(command)) return 'source_search_or_mixed_reads';
    return 'other_tool_results';
  }
  return /apply_patch|Begin Patch/.test(p.input || p.arguments || '') ? 'patches' : 'tool_commands';
}
function action(p) {
  const text = `${p.name || ''} ${p.input || p.arguments || ''}`;
  if (/wait_agent|write_stdin|gh run watch|tools\.wait|"cell_id"/.test(text)) return 'waiting_or_polling';
  if (/send_message|list_agents/.test(text)) return 'coordination';
  if (/apply_patch|Begin Patch/.test(text)) return 'editing';
  if (/\b(test|xcodebuild|swift|pytest)\b/.test(text)) return 'test_or_build_command';
  if (/\b(rg|sed|cat|head|tail)\b|git diff/.test(text)) return 'reading_or_inspection';
  return 'other_or_mixed';
}

export async function analyze(records, { from, to } = {}) {
  const usage = zeros(), calls = new Map(), recordedCharacters = {}, exposure = {}, actions = {};
  let retained = {}, previous = zeros(), requests = 0, duplicates = 0, resets = 0;
  let missingDeltaMatches = 0, opaqueRecords = 0, compactions = 0, pendingActions = new Set();
  let firstTime, lastTime, firstInput, lastInput, maxInput = 0, minimumInput = Infinity;
  for await (const r of records) {
    if (to && r.timestamp > to) break;
    const inRange = !from || r.timestamp >= from;
    const p = r.payload || {};
    if (r.type === 'compacted') {
      retained = {}; // Do not pretend old recorded text remains in the prompt.
      if (inRange) compactions++;
      // Replacement summaries may be encrypted/unavailable; report unknown.
      continue;
    }
    if (r.type === 'response_item') {
      const c = category(p, calls);
      let value = p.content ?? p.output ?? p.input ?? p.arguments ?? p.summary;
      // Function arguments can contain encrypted strings inside JSON.
      if (p.arguments) {
        try { value = Object.values(JSON.parse(p.arguments)).filter(x => typeof x === 'string').map(readable).join(''); }
        catch { value = ''; }
      }
      const size = readable(value).length;
      if (inRange && (p.encrypted_content || JSON.stringify(p.content || '').includes('encrypted_content') || /gAAAAA/.test(p.arguments || ''))) opaqueRecords++;
      retained[c] = (retained[c] || 0) + size;
      if (inRange) recordedCharacters[c] = (recordedCharacters[c] || 0) + size;
      if (/call$/.test(p.type)) {
        calls.set(p.call_id, readable(p.input || p.arguments));
        if (inRange) pendingActions.add(action(p));
      }
    }
    if (r.type !== 'event_msg' || p.type !== 'token_count' || !p.info?.total_token_usage) continue;
    const current = Object.fromEntries(fields.map(k => [k, p.info.total_token_usage[k] || 0]));
    if (!fields.every(k => Number.isSafeInteger(current[k]) && current[k] >= 0)) throw Error('Invalid usage counter');
    if (fields.every(k => current[k] === previous[k])) { if (inRange) duplicates++; continue; }
    const reset = fields.some(k => current[k] < previous[k]);
    const delta = Object.fromEntries(fields.map(k => [k, current[k] - (reset ? 0 : previous[k])]));
    previous = current;
    if (!inRange) { pendingActions.clear(); continue; }
    if (reset) resets++;
    requests++;
    for (const k of fields) usage[k] += delta[k];
    const last = p.info.last_token_usage;
    if (!last || fields.some(k => (last[k] || 0) !== delta[k])) missingDeltaMatches++;
    const input = last?.input_tokens;
    if (Number.isSafeInteger(input)) {
      firstInput ??= input; lastInput = input;
      maxInput = Math.max(maxInput, input); minimumInput = Math.min(minimumInput, input);
    }
    firstTime ??= r.timestamp; lastTime = r.timestamp;
    for (const [k, n] of Object.entries(retained)) exposure[k] = (exposure[k] || 0) + n;
    const label = pendingActions.size === 1 ? [...pendingActions][0] : pendingActions.size ? 'mixed_actions' : 'no_recorded_tool_action';
    const bucket = actions[label] ??= { requests: 0, ...zeros() };
    bucket.requests++;
    for (const k of fields) bucket[k] += delta[k];
    pendingActions.clear();
  }
  return {
    firstTime, lastTime, elapsedSecondsBetweenUsageEvents: firstTime ? (Date.parse(lastTime) - Date.parse(firstTime)) / 1000 : null,
    requests, duplicateStatusEvents: duplicates, counterResets: resets, deltaLastUsageMismatches: missingDeltaMatches,
    usage: { ...usage, uncached_input_tokens: usage.input_tokens - usage.cached_input_tokens - usage.cache_write_input_tokens },
    requestInput: { first: firstInput, last: lastInput, min: requests ? minimumInput : null, max: maxInput },
    heuristicRequestActions: actions,
    contentProxy: { unit: 'readable JavaScript string characters, NOT tokens', recordedCharacters, repeatedRecordedCharacterExposure: exposure, opaqueRecords, compactions },
    limitations: [
      'Not exact request payloads or cached-token category attribution. Tool definitions, encrypted content, images and retention/truncation are not reconstructed.',
      'Read categories are command heuristics; mixed reads can include code, guidance or logs. Exposure sums observed retained text at usage events, not a billed-token allocation.',
      'Action labels describe recorded tool calls near usage events, NOT time/activity attribution or avoidable waste. Review mixed/no-action events rather than guessing.',
      'Counter resets and last-usage mismatches require review. A resumed/incomplete file without a prior baseline can overcount. Reasoning is already in output.',
      'Elapsed time covers usage events only. Record task start/end separately; subscription consumption is not derivable.'
    ]
  };
}

async function* jsonl(path) {
  for await (const line of createInterface({ input: createReadStream(path), crlfDelay: Infinity })) {
    if (!line.trim()) continue;
    yield JSON.parse(line); // Fail visibly on an incomplete record; retry after flush.
  }
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = process.argv.slice(2), options = {}, paths = [];
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--from' || args[i] === '--to') {
      const key = args[i].slice(2), value = args[++i];
      if (!value || !Number.isFinite(Date.parse(value))) throw Error(`Invalid --${key}`);
      options[key] = new Date(value).toISOString();
    } else if (args[i].startsWith('--')) throw Error(`Unknown argument ${args[i]}`);
    else paths.push(args[i]);
  }
  if (!paths.length || new Set(paths).size !== paths.length) throw Error('Supply unique rollout paths; optional --from ISO --to ISO');
  if (options.from && options.to && options.from > options.to) throw Error('Reversed time range');
  for (const path of paths) console.log(JSON.stringify({ path, ...await analyze(jsonl(path), options) }));
}
