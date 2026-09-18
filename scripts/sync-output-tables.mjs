// This validates the repository's SQL-block format and primary output names,
// not the full PowerSync SQL grammar or hosted replication behavior.
export function validateSyncOutputTables(yaml, swiftSchema) {
  const tables = new Set([...swiftSchema.matchAll(/public static let \w+ = "([a-z_]+)"/g)].map(m => m[1]));
  if (!tables.size) throw new Error('No client table names found');
  const markers = [...yaml.matchAll(/^[ \t]*(?:-[ \t]*|query:[ \t]*)\|[ \t]*$/gm)];
  const blocks = markers.map((marker, index) => yaml.slice(marker.index + marker[0].length,
    markers[index + 1]?.index ?? yaml.length));
  if (!blocks.length) throw new Error('No supported SQL query blocks found');
  for (const block of blocks) {
    const source = block.match(/\bFROM\s+((?:[a-z_][a-z_0-9]*\.)?[a-z_][a-z_0-9]*)(?:\s+AS\s+"?([a-z_][a-z_0-9]*)"?)?/i);
    if (!source) throw new Error('Missing supported primary table');
    const table = source[1].split('.').at(-1), output = source[2] ?? table;
    const returnProjection = source[1] === 'ledger_private.item_return_reviews'
      && ['return_charge_sources','return_live_memberships','return_paid_memberships','item_return_history'].includes(output);
    const mediaProjection = (source[1] === 'ledger_private.media_sync_objects' && output === 'item_image_objects')
      || (source[1] === 'ledger_private.media_sync_thumbnails' && output === 'item_card_thumbnails');
    if ((!returnProjection && !mediaProjection && output !== table) || !tables.has(output)) {
      throw new Error(`Sync output ${output} from ${table} does not match its client table`);
    }
  }
  return blocks.length;
}
