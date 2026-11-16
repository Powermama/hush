<!-- SPDX-License-Identifier: AGPL-3.0-only -->
<!-- Copyright (c) 2026 Clemens Kressmann -->

# Deployment secrets

Each file here is one service's production environment, encrypted with
[SOPS](https://github.com/getsops/sops) and [age](https://age-encryption.org):
the variable names stay readable, every value is encrypted. These files are
the source of truth; a platform's secret store is filled from them, never the
other way round, so moving to another platform starts from here
([deploy anywhere](../../docs/reference/deploy-anywhere.md)).

| File | Service |
| --- | --- |
| `production/cms.env` | The CMS API and scheduler |

## Read and change

The owner's age key lives in their password manager and, on their Mac, in
`~/Library/Application Support/sops/age/keys.txt` (where SOPS looks on macOS).

Run SOPS from `webapp/`, where it finds its rules (`webapp/.sops.yaml`):

```sh
cd webapp
sops deploy/production/cms.env          # edit in place, re-encrypted on save
sops decrypt deploy/production/cms.env  # print, for filling a platform
```

After a change, update the platform (on Coolify: the environment's shared
variables, see the [CMS guide](../apps/cms/docs/operations/coolify.md)) and
redeploy. To rotate a credential, create the new one at its issuer, put it here,
update the platform, deploy, then revoke the old one.

To give another person or a CI system access, add their age public key to
`webapp/.sops.yaml` and run `sops updatekeys deploy/production/cms.env` in `webapp/`.
