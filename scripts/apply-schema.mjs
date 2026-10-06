import fs from 'fs';
import path from 'path';
import pg from 'pg';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, '..');

const conn = process.env.DATABASE_URL;
if (!conn) {
  console.error('Set DATABASE_URL (Supabase → Project Settings → Database → connection string).');
  process.exit(1);
}

const files = [
  'parrot_schema.sql',
  'parrot_schema_part2.sql',
  'parrot_schema_part3_privacy.sql',
  'parrot_schema_part4_description.sql',
  'parrot_schema_part5_hide_genotype.sql',
  'parrot_schema_part6_hide_phenotype.sql',
];

const client = new pg.Client({ connectionString: conn, ssl: { rejectUnauthorized: false } });

await client.connect();
for (const f of files) {
  const sql = fs.readFileSync(path.join(root, f), 'utf8');
  console.log('Running', f, '...');
  try {
    await client.query(sql);
    console.log('OK', f);
  } catch (e) {
    console.error('Error in', f, e.message);
    throw e;
  }
}
await client.end();
console.log('Schema applied.');
