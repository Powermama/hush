import { drizzle } from "drizzle-orm/postgres-js";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import postgres from "postgres";

const connectionString = process.env.DATABASE_URL;
if (!connectionString) throw new Error("DATABASE_URL is required");

// One session holds the advisory lock for the whole migration, so two
// instances starting together (rolling update, manual restart) never apply the
// same migration concurrently. Migrations must stay additive: the previous
// release keeps serving from this schema until the replacement is healthy.
const MIGRATION_LOCK_ID = 7_316_504_211;
const client = postgres(connectionString, { max: 1, prepare: false });
try {
  await client`select pg_advisory_lock(${MIGRATION_LOCK_ID})`;
  await migrate(drizzle(client), { migrationsFolder: "server/db/migrations" });
  console.info("Hush provenance database is current.");
} finally {
  await client`select pg_advisory_unlock(${MIGRATION_LOCK_ID})`.catch(() => {});
  await client.end({ timeout: 5 });
}
