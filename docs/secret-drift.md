# Secret drift detection

How the module detects and enforces secrets that PDM does not return over its API, and how it
keeps them out of logs and reports.

Every secret this module manages is detected and enforced: changing a secret in Hiera, and
nothing else, rotates it on the next run.

## Where secrets are compared

PDM does not return most of these secrets over its API, but it persists them on the node. The
module reads those copies to decide whether the stored secret still matches the declared one.

| Attribute | Compared against | Needs node access |
|---|---|---|
| `pdm_realm.client_key` | the value PDM returns from `GET /config/access/openid/{realm}` | no |
| `pdm_remote.token` | `/etc/proxmox-datacenter-manager/remotes.shadow` | yes |
| `pdm_realm.bind_password` | `/etc/proxmox-datacenter-manager/access/ldap-passwords.json` | yes |
| `pdm_user.password` | `crypt(3)` against `/etc/proxmox-datacenter-manager/access/shadow.json` | yes |

The API is not a usable source for the bottom three. `GET /remotes/remote` declares it returns the
remote token and then blanks it, and neither the realm bind password nor a user password is
returned in any form. PDM does persist all three on the node, which is what makes comparison
possible. `ldap-passwords.json` and `shadow.json` are mode `0600 root:root`; `remotes.shadow` is
`0640 www-data:www-data`.

`pdm_api_token` secrets are the exception: PDM returns a generated token secret once, at creation,
and stores only a hash afterwards, so there is nothing to compare against. See
[API tokens](api-tokens.md).

## Requirements and failure mode

Reading those copies requires the Puppet agent to run on the PDM node as root. If a resource
declares such a secret and its store cannot be read, the run fails with an error naming the
attribute and the path. It does not report the resource as in sync: that would silently stop
enforcing the secret precisely where nobody can see it. Resources that declare no node-stored
secret are unaffected, so a catalog without remote tokens, bind passwords and user passwords can
run on any host that reaches the API.

## Secrets in logs and reports

Secret attributes are marked sensitive, so their values are redacted from change notices, from
report events (and therefore from PuppetDB), and from the agent-local `last_run_report.yaml`. The
current value is reported as a fixed placeholder, `[secret managed]`, never as the stored value,
hash or ciphertext: a placeholder that varied between runs would itself read as drift.

A rotation logs `changed [redacted] to [redacted]`, and the report event is flagged `redacted`.
The value PDM returns for `client_key` is never placed in the resource either: all four report the
placeholder and the comparison happens out of band.

Declaring a secret with `Sensitive()` is still worthwhile: it keeps the plaintext out of the
compiled catalog, but redaction no longer depends on it.
