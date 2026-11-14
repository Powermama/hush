# Server hardening

The hush services run on Hetzner Cloud servers managed by Coolify. This page
records the network and SSH hardening so it can be checked and rebuilt.

## Network

| Server | Role | Hetzner Cloud Firewall | Private network |
| --- | --- | --- | --- |
| `coolify` | Coolify itself | `coolify-host` | `172.16.0.2` |
| `automation` | behu.sh, the CMS and other apps | `app-servers` | `172.16.0.3` |

Both firewalls allow 80 and 443 only from Cloudflare's ranges
(https://www.cloudflare.com/ips/), plus SSH and ICMP. Every public domain on
these servers is proxied by Cloudflare, so nothing reaches the origins around
Cloudflare: not the IP, not Coolify's `sslip.io` addresses, and not Coolify's
ports 8000, 6001 and 6002 (the dashboard, realtime and terminal run on 443).
Hetzner Cloud Firewalls filter before Docker, which bypasses UFW for published
ports. Traffic on the private network `hush-private` (`172.16.0.0/16`) is not
filtered; the CMS reaches Coolify's API there
(`webapp/apps/cms/docs/operations/coolify.md`).

When Cloudflare publishes new ranges, rebuild both rule sets from
https://www.cloudflare.com/ips-v4/ and https://www.cloudflare.com/ips-v6/.

## SSH

All four servers (`coolify`, `automation`, `services`, `supabase`) accept keys
only. `/etc/ssh/sshd_config.d/00-hardening.conf`:

```
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
```

The `00-` prefix matters: sshd keeps the first value it reads, and Ubuntu cloud
images ship `50-cloud-init.conf` with `PasswordAuthentication yes`. Apply with
`sshd -t && systemctl reload ssh`, then check `sshd -T`. Coolify logs in with its
own key; the Hetzner web console works independently of SSH.

## Checks

- From outside, password login is refused:
  `ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password root@<ip>`
  answers `Permission denied (publickey)`.
- Ports 8000, 6001 and 6002 on the Coolify server and 80/443 on the IPs
  directly do not answer; every site answers through its domain.
