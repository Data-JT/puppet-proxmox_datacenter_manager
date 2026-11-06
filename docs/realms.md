# Authentication realms

Examples for `pdm_realm`, which manages external authentication realms. All attributes are
documented in [REFERENCE.md](../REFERENCE.md#pdm_realm).

The `type` attribute selects the backend and routes to the corresponding PDM API endpoint
(`/config/access/{ldap,ad,openid}`). The API has no way to move a realm between endpoints, so to
switch types set `ensure => absent` for one run and re-create the realm with the new type.

## LDAP

```puppet
pdm_realm { 'corp-ldap':
  ensure        => present,
  type          => 'ldap',
  server1       => 'ldap.example.com',
  base_dn       => 'dc=example,dc=com',
  user_attr     => 'uid',
  bind_dn       => 'cn=search,dc=example,dc=com',
  bind_password => Sensitive(lookup('pdm::ldap_bind_password')),
  mode          => 'ldap+starttls',
  verify        => true,
}
```

## Active Directory

```puppet
pdm_realm { 'corp-ad':
  ensure        => present,
  type          => 'ad',
  server1       => 'ad.example.com',
  base_dn       => 'dc=example,dc=com',
  bind_dn       => 'cn=search,dc=example,dc=com',
  bind_password => Sensitive(lookup('pdm::ad_bind_password')),
  mode          => 'ldaps',
  verify        => true,
}
```

## OpenID Connect

```puppet
pdm_realm { 'sso':
  ensure         => present,
  type           => 'openid',
  issuer_url     => 'https://sso.example.com',
  client_id      => 'proxmox-datacenter-manager',
  client_key     => Sensitive(lookup('pdm::oidc_client_secret')),
  username_claim => 'email',
  autocreate     => true,
  scopes         => 'openid email profile',
}
```

## Realm credentials

Both realm credentials are enforced, by different means:

- `bind_password` (LDAP/AD) is never returned by the API. Drift is detected against
  `/etc/proxmox-datacenter-manager/access/ldap-passwords.json` (`0600 root:root`), which needs
  the agent on the PDM node as root.
- `client_key` (OpenID) is returned by the API, verbatim. It needs no on-node access and is
  compared like any ordinary property. PDM stores it in cleartext in
  `/etc/proxmox-datacenter-manager/access/domains.cfg`, which is readable by the web-server user,
  and returns it to anyone holding `System.Audit` on `/access/domains`. That is PDM's design
  rather than this module's, but it is worth knowing when deciding where a secret may live.

Changing either value in Hiera rotates it on the next run. See
[Secret drift detection](secret-drift.md).
