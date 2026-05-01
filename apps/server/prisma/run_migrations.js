const { Client } = require('pg');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

async function runMigrations() {
  const client = new Client({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false }
  });

  try {
    await client.connect();
    console.log('Connected to database');

    const sqlFiles = [
      '001_enable_postgis.sql',
      '002_spatial_columns.sql',
      '003_partitioning.sql',
      '004_functions_views.sql',
      '005_seed.sql'
    ];

    for (const file of sqlFiles) {
      console.log(`Running ${file}...`);
      const filePath = path.join(__dirname, 'advanced', file);
      const sql = fs.readFileSync(filePath, 'utf8');
      
      // Split by semicolon for simple execution, but better to use a tool that handles complex SQL
      // For now, let's try executing the whole block. 
      // PostgreSQL can handle multiple statements in one query call.
      await client.query(sql);
      console.log(`Finished ${file}`);
    }

    console.log('All migrations completed successfully');
  } catch (err) {
    console.error('Migration failed:', err);
    process.exit(1);
  } finally {
    await client.end();
  }
}

runMigrations();
