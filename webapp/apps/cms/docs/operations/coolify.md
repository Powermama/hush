# Deploy the CMS on Coolify

The CMS runs beside the website as its own Coolify resources, so neither can
reach the other's data or secrets.

| Resource | Coolify type | Settings |
| --- | --- | --- |
| `hush-cms-postgres` | Database, PostgreSQL 17 | Scheduled backups enabled; restore drill before the CMS holds the only copy of articles |
| `hush-cms` | Application, Dockerfile build pack | Base directory `/webapp`, Dockerfile location `/apps/cms/Dockerfile`, port `3100`, no public domain until the admin UI ships |

## `hush-cms` settings

1. **Environment variables**: `CMS_DATABASE_URL` from `hush-cms-postgres`'s
   internal connection URL, and the image bucket: `CMS_S3_BUCKET=hush-blog-media`,
   `CMS_S3_ENDPOINT` (`https://<account>.r2.cloudflarestorage.com`),
   `CMS_S3_ACCESS_KEY_ID` and `CMS_S3_SECRET_ACCESS_KEY` from an R2 API token
   limited to that bucket. Never the app-update bucket, which ships the Mac app.
   Nothing else from the website.
2. **Health check**: path `/health/ready`, port `3100`.
3. **Scheduled Tasks**: `bun run cms:publish-due`, frequency `* * * * *`,
   container `hush-cms`. Its output lists the posts it published.
4. **Watch Paths**: `webapp/apps/cms/**`, `webapp/packages/**`,
   `webapp/package.json`, `webapp/bun.lock`.

## First token

Open a terminal in the `hush-cms` container and run:

```sh
bun run cms:token --name owner --scopes posts:read,posts:write,posts:publish --days 90
```

The token is printed once; only its hash is stored. Agents get tokens without
`posts:publish` unless they should publish on their own.
