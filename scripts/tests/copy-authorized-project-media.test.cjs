const test = require('node:test');
const assert = require('node:assert/strict');
const { storageURL, collectMediaReferences, collectSpaceOriginals, verifiedCopies } = require('../copy-authorized-project-media.cjs');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const base = 'https://firebasestorage.googleapis.com/v0/b/ledger-nine4.firebasestorage.app/o/';
test('Space selection copies only exact-account Space gallery originals', () => {
  const gallery={arrayValue:{values:[{mapValue:{fields:{url:{stringValue:base+'original.jpg'}}}}]}};
  const source={account:'accounts/a',documents:[
    {name:'accounts/a/spaces/one',fields:{images:gallery,mainImageThumbUrlSm:{stringValue:base+'thumbnail.jpg'}}},
    {name:'accounts/a/spaces/empty',fields:{}},
    ...['accounts/a/items/one','accounts/other/spaces/one','accounts/a/spaces/one/notes/child'].map(name=>({name,fields:{images:{arrayValue:{values:[{mapValue:{fields:{url:{stringValue:'https://unapproved.invalid/never-fetch'}}}}]}}}}))
  ]};
  assert.deepEqual([...collectSpaceOriginals(source).refs.keys()],['original.jpg']);
});
test('preserves token and encoded object name, requests bytes', () => {
  const result = storageURL(base + 'accounts%2Fexample%2Fimage.jpg?token=example');
  assert.equal(result.object, 'accounts/example/image.jpg');
  assert.equal(new URL(result.url).searchParams.get('token'), 'example');
  assert.equal(new URL(result.url).searchParams.get('alt'), 'media');
});
test('normalizes same-bucket gs references without adding credentials', () => {
  assert.equal(storageURL('gs://ledger-nine4.firebasestorage.app/example/image.jpg').url,
    base + 'example%2Fimage.jpg?alt=media');
});
test('rejects alternate hosts, buckets, insecure transport and embedded credentials', () => {
  for (const url of [base.replace('https:', 'http:') + 'x', base.replace('ledger-nine4', 'other') + 'x',
    'https://example.com/x', 'gs://other/x', base.replace('https://', 'https://user:secret@') + 'x', base + 'x#fragment']) {
    assert.throws(() => storageURL(url));
  }
});
test('rejects empty and traversing object names', () => {
  for (const value of ['', '..%2Fx', 'x%2F..%2Fy', 'x%2F.%2Fy']) assert.throws(() => storageURL(base + value));
});
test('retains device-only media as unavailable while collecting downloadable references', () => {
  const doc = { name: 'private-owner', fields: { images: { arrayValue: { values: [
    { mapValue: { fields: { url: { stringValue: 'offline://device-image' } } } },
    { mapValue: { fields: { url: { stringValue: base + 'image.jpg' } } } }
  ] } } } };
  const result = collectMediaReferences([doc]);
  assert.equal(result.refs.size, 1);
  assert.deepEqual(result.unavailable, [{ owner: 'private-owner', field: 'url',
    reference: 'offline://device-image', status: 'unavailable', reason: 'source_device_local' }]);
  assert.throws(() => collectMediaReferences([{ name: 'owner', fields: { url: { stringValue: 'https://example.com/image' } } }]));
});
test('resume reuses only verified bytes and refuses corruption or redirected files', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'ledger-media-resume-test-'));
  try {
    const object = 'example/image', bytes = Buffer.from('test bytes');
    const file = crypto.createHash('sha256').update(object).digest('hex');
    const row = { object, file, bytes: bytes.length,
      sha256: crypto.createHash('sha256').update(bytes).digest('hex'), status: 'copied' };
    fs.writeFileSync(path.join(directory, file), bytes);
    fs.writeFileSync(path.join(directory, 'results.jsonl'), JSON.stringify(row) + '\n'
      + JSON.stringify({ object: 'other', status: 'unavailable', reason: 'download_failed' }) + '\n');
    assert.deepEqual([...verifiedCopies(directory).keys()], [object]);
    fs.writeFileSync(path.join(directory, file), 'bad bytes!');
    assert.throws(() => verifiedCopies(directory), /Copied bytes changed/);
    fs.unlinkSync(path.join(directory, file));
    fs.symlinkSync(path.join(directory, 'results.jsonl'), path.join(directory, file));
    assert.throws(() => verifiedCopies(directory), /Copied bytes changed/);
    fs.writeFileSync(path.join(directory, 'results.jsonl'), JSON.stringify({ ...row, file: '../outside' }) + '\n');
    assert.throws(() => verifiedCopies(directory), /Invalid copied file identity/);
  } finally { fs.rmSync(directory, { recursive: true }); }
});
