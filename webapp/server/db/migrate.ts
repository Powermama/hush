import { drizzle } from "drizzle-orm/postgres-js";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import postgres from "postgres";

const connectionString = process.env.DATABASE_URL;
if (!connectionString) throw new Error("DATABASE_URL is required");

const client = postgres(connectionString, { max: 1, prepare: false });
try {
  await migrate(drizzle(client), { migrationsFolder: "server/db/migrations" });
  console.info("Hush provenance database is current.");
} finally {
  await client.end({ timeout: 5 });
}
