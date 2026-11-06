# Remotes and views

Examples for `pdm_remote`, which connects a PVE cluster or PBS server to PDM, and `pdm_view`,
which groups remotes for the UI. All attributes are documented in
[REFERENCE.md](../REFERENCE.md#pdm_remote).

## Remotes

```puppet
pdm_remote { 'production':
  ensure => present,
  type   => 'pve',
  nodes  => ['pve01.example.com', 'pve02.example.com'],
  authid => 'pdm@pve!manager',
  token  => Sensitive(lookup('pdm::remotes::production_token')),
}

pdm_remote { 'backups':
  ensure => present,
  type   => 'pbs',
  nodes  => ['pbs01.example.com'],
  authid => 'pdm@pbs!manager',
  token  => Sensitive(lookup('pdm::remotes::backups_token')),
}
```

- `authid` is the user or API token PDM authenticates with on the remote; `token` is that token's
  secret. Create them on the PVE or PBS side first (for example with the sibling modules'
  `pve_api_token` or `pbs_api_token`).
- `token` is required during creation, including when `create_token` is used to have PDM create
  the token on the remote.
- `web_url` overrides the URL the UI links to for this remote.

In Hiera, keep the token encrypted and preserve its `Sensitive` wrapper with `alias`:

```yaml
lookup_options:
  pdm::remotes::production_token:
    convert_to: Sensitive

pdm::remotes::production_token: ENC[PKCS7,...]

proxmox_datacenter_manager::resources::remotes:
  production:
    type: pve
    nodes:
      - pve01.example.com
    authid: 'pdm@pve!manager'
    token: "%{alias('pdm::remotes::production_token')}"
```

A plain `%{lookup(...)}` interpolation would convert the value to a string; `alias` keeps the
`Sensitive` object.

## The remote token

PDM persists the remote token in `/etc/proxmox-datacenter-manager/remotes.shadow`
(`0640 www-data:www-data`) and does not return it over the API: `GET /remotes/remote` declares the
field and then blanks it. The provider compares the declared token against that file, so changing
it in Hiera rotates it on the next run, and managing it requires the agent on the PDM node as
root. See [Secret drift detection](secret-drift.md).

## Views

```puppet
pdm_view { 'production':
  ensure      => present,
  include     => ['remote=production'],
  include_all => false,
}
```

`include` and `exclude` take PDM's rule strings; `layout` is the JSON layout the UI stores. The
resources class orders remotes before the views that reference them.
