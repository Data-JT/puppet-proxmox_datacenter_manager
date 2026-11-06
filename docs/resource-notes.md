# Resource notes

Behaviour of individual `pdm_*` types that is not obvious from their attribute lists, and what the
module leaves to the `pdm_api_request` task. The attributes themselves are documented in
[REFERENCE.md](../REFERENCE.md).

## Resource types and API endpoints

| Type | API endpoint |
|---|---|
| `pdm_remote` | `/remotes/remote` |
| `pdm_user` | `/access/users` |
| `pdm_api_token` | `/access/users/{userid}/token` |
| `pdm_acl` | `/access/acl` |
| `pdm_realm` | `/config/access/{ldap,ad,openid}` |
| `pdm_view` | `/config/views` |
| `pdm_notes` | `/config/notes` |
| `pdm_node_config` | `/nodes/localhost/config` |

The implementation follows the official [PDM API viewer](https://pdm.proxmox.com/docs/api-viewer/index.html).

## Operational endpoints are not resources

PDM's operational endpoints, such as guest power operations, migrations, update triggers and
remote task control, are intentionally exposed through the generic `pdm_api_request` task instead
of being modelled as convergent Puppet resources: they describe an action, not a desired state.
See [Ad-hoc API access](api-access.md).

## Singletons

`pdm_node_config` manages the node-level API and UI settings and must use the title `localhost`.
`pdm_notes` manages the global Markdown notes and must use the title `global`. PDM has exactly one
of each; `ensure => absent` on either is a no-op that logs a notice.

```puppet
pdm_notes { 'global':
  notes => "# Datacenter\n\nManaged by Puppet.\n",
}

pdm_node_config { 'localhost':
  default_lang => 'en',
  email_from   => 'pdm@example.com',
  http_proxy   => 'http://proxy.example.com:3128',
}
```

## Users and ACLs

`pdm_acl` is titled `path|ugid|role`, where `ugid` is a user ID or a full token ID. `pdm_user`
passwords are compared against PDM's `shadow.json`; see [Secret drift detection](secret-drift.md).

## Resources class ordering

`proxmox_datacenter_manager::resources` infers dependencies between related entries declared in
its Hiera hashes: realms before users, users before API tokens, users or tokens before ACLs, and
remotes before views that reference them. References to resources not declared through this class
are left unconstrained.
