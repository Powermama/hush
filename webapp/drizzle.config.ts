import { defineConfig } from "drizzle-kit";

export default defineConfig({
  dialect: "postgresql",
  schema: "./server/db/schema.ts",
  out: "./server/db/migrations",
  dbCredentials: {
    url: process.env.DATABASE_URL ?? "postgres://hush:hush@127.0.0.1:5432/hush",
  },
  strict: true,
  verbose: true,
});
