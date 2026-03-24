#!/usr/bin/env tsx
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
for (const envFile of ['.env.local', '.env']) {
  const p = resolve(process.cwd(), envFile);
  if (!existsSync(p)) continue;
  for (const line of readFileSync(p, 'utf8').split('\n')) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const eq = t.indexOf('=');
    if (eq === -1) continue;
    const k = t.slice(0, eq).trim();
    const v = t.slice(eq + 1).trim().replace(/^["']|["']$/g, '');
    if (!(k in process.env)) process.env[k] = v;
  }
}
import { initFirestore } from './firestore-writer.js';

async function main() {
  const db = initFirestore('production', 'ledger-nine4');

  for (const [name, accountId] of [
    ['Assiist Biz', '2d612868-852e-4a80-9d02-9d10383898d4'],
    ['1584 Design', '1dd4fd75-8eea-4f7a-98e7-bf45b987ae94'],
  ]) {
    console.log(`\n=== ${name} ===`);

    // Find items WITH images
    const allItems = await db.collection(`accounts/${accountId}/items`).get();
    let withImages = 0, withThumbSm = 0, withThumbMd = 0, offlineThumb = 0, gsThumb = 0;

    let sampleShown = false;
    for (const doc of allItems.docs) {
      const images = doc.data().images;
      if (!images || !Array.isArray(images) || images.length === 0) continue;
      withImages++;

      for (const img of images) {
        if (img.thumbnailUrlSm) {
          withThumbSm++;
          if (img.thumbnailUrlSm.startsWith('gs://')) gsThumb++;
          else if (img.thumbnailUrlSm.startsWith('offline://')) offlineThumb++;
        }
        if (img.thumbnailUrlMd) withThumbMd++;

        if (!sampleShown) {
          console.log(`  Sample (${doc.id}):`);
          console.log(`    url: ${img.url}`);
          console.log(`    thumbSm: ${img.thumbnailUrlSm ?? '(missing)'}`);
          console.log(`    thumbMd: ${img.thumbnailUrlMd ?? '(missing)'}`);
          sampleShown = true;
        }
      }
    }

    console.log(`  Items with images: ${withImages} / ${allItems.docs.length}`);
    console.log(`  Thumb SM present: ${withThumbSm}, Thumb MD present: ${withThumbMd}`);
    console.log(`  Thumb gs://: ${gsThumb}, Thumb offline://: ${offlineThumb}`);
  }
}

main().catch(console.error);
