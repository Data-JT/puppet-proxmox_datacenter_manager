<a href="https://www.data-jt.de">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/Data-JT/.github/main/profile/banner-dark.svg">
    <img alt="Data JT" src="https://raw.githubusercontent.com/Data-JT/.github/main/profile/banner-light.svg" width="420">
  </picture>
</a>

# datajt-proxmox_datacenter_manager

Manage Proxmox Datacenter Manager configuration as Puppet code, through the PDM REST API.

## Table of contents

1. [Description](#description)
2. [Requirements](#requirements)
3. [Quick start](#quick-start)
4. [Resource types](#resource-types)
5. [Further documentation](#further-documentation)
6. [Limitations](#limitations)
7. [Contributing](#contributing)
8. [License](#license)
9. [About Data JT](#about-data-jt)

## Description

This module lets you describe the configuration of a [Proxmox Datacenter Manager](https://pdm.proxmox.com/)
(PDM) instance in Puppet code or Hiera: the PVE and PBS remotes it manages, users, API tokens,
permissions, authentication realms, resource views, the global notes and node settings. The
Puppet agent compares that description with the live configuration and changes only what differs.

### What it does

- Manages 8 kinds of PDM objects as native Puppet resource types (`pdm_*`).
- Declares all of them from Hiera through one class, `proxmox_datacenter_manager::resources`.
- Detects and enforces drift in secrets (remote tokens, LDAP bind passwords, OpenID client
  secrets, user passwords), and keeps them out of logs and reports.
- Ships a Bolt task for ad-hoc API calls and a checkout-only utility that imports an existing
  PDM into Hiera data.

### What it does not do

- It does not install PDM, manage its apt repository or its services. It configures an existing PDM.
- It does not operate the datacenter: guest power operations, migrations, updates and remote
  task control stay with the `pdm_api_request` task and are not modelled as resources.
- It does not use `puppet device`, a proxy agent or a Bolt transport. The agent runs on the PDM
  node (or, for resources without node-stored secrets, on any host that reaches the API).
- It does not purge PDM objects that are not declared in Puppet.
- It does not clear a value when you remove an attribute; use `delete_properties` for that.
- It cannot verify API token secrets after creation: PDM keeps only a hash.

### How it works

```text
Hiera / manifest                   declares the class and the resources
      │
      ▼
proxmox_datacenter_manager class   writes pdm_transport.yaml (token, 0600)
      │
      ▼
pdm_* types                        read that file on every agent run on the PDM node
      │
      ▼
PDM REST API                       https://localhost:8443
```

The `proxmox_datacenter_manager` class writes the API token and connection settings to a
transport file in the agent's confdir. The `pdm_*` types are built on the Puppet Resource API;
their providers read that file and call the PDM API on every agent run. Resources come from
manifests or from Hiera via `proxmox_datacenter_manager::resources`. Secrets PDM does not return
over the API are compared against PDM's own files under `/etc/proxmox-datacenter-manager/`,
which is why the agent runs as root on the node.

## Requirements

- Puppet or OpenVox 8 or 9 (`>= 8.0.0 < 10.0.0`). Testing is currently done on 8 (CI and production); on 9 the unit tests also run in CI
  (OpenVox 9.3), but there is no production use yet. No Forge dependencies; the Resource API ships with Puppet.
- Debian 13 with PDM 1.x. Tested against PDM 1.1.1. PDM 2.x is not supported until declared
  compatible; include the exact PDM version when reporting an issue.
- The Puppet agent running as root on the PDM node when remote tokens, realm bind passwords or
  user passwords are managed.
- A PDM API token with list/read and modify permissions for the objects you manage.

## Quick start

### 1. Prepare PDM

In the PDM web UI, create a dedicated user and an API token for it, and grant both a role on the
paths of the objects you manage. The providers discover existing objects before changing them,
so the token needs read visibility of every managed type as well as the modify permission;
incomplete visibility makes an existing object look absent and the creation fail. Do not use a
blanket `Administrator` grant where a narrower role or path is sufficient; confirm the
permissions of each method in the [PDM API viewer](https://pdm.proxmox.com/docs/api-viewer/index.html)
for the deployed version.

### 2. Manifest

```puppet
# site/profile/manifests/pdm.pp
class profile::pdm {
  include proxmox_datacenter_manager            # transport: token_id, token_secret from Hiera
  include proxmox_datacenter_manager::resources # pdm_* resources from Hiera

  # Resources can also be declared directly:
  pdm_node_config { 'localhost':
    email_from => 'pdm@example.com',
  }
}
```

### 3. Hiera

```yaml
# Class parameters. Keep secrets encrypted (hiera-eyaml) and convert them to Sensitive.
lookup_options:
  proxmox_datacenter_manager::token_secret:
    convert_to: Sensitive
  pdm::remotes::production_token:
    convert_to: Sensitive

proxmox_datacenter_manager::token_id: 'puppet@pdm!puppet'
proxmox_datacenter_manager::token_secret: ENC[PKCS7,...]
proxmox_datacenter_manager::ssl_ca_file: /etc/ssl/certs/example-ca.pem  # or ssl_verify: false on localhost

pdm::remotes::production_token: ENC[PKCS7,...]

# Resources
proxmox_datacenter_manager::resources::remotes:
  production:
    type: pve
    nodes:
      - pve01.example.com
      - pve02.example.com
    authid: 'pdm@pve!manager'
    token: "%{alias('pdm::remotes::production_token')}"   # alias keeps the Sensitive wrapper

proxmox_datacenter_manager::resources::users:
  automation@pdm:
    enable: true
    email: automation@example.com

proxmox_datacenter_manager::resources::api_tokens:
  'automation@pdm!ci':
    comment: CI automation
    secret_file: /etc/puppetlabs/puppet/pdm-ci-token.secret

proxmox_datacenter_manager::resources::acls:
  '/|automation@pdm!ci|Auditor':
    propagate: true

proxmox_datacenter_manager::resources::views:
  production:
    include: ['remote=production']
    include_all: false
```

`ensure` defaults to `present`. The resources class orders related entries it declares itself
(realms before users, users before tokens and ACLs, remotes before the views that reference
them). Run the first pass with `puppet agent -t --noop`.

## Resource types

| Type | Manages |
|---|---|
| `pdm_remote` | PVE and PBS remotes (nodes, auth ID, token) |
| `pdm_user` | PDM users, including `@pdm` passwords |
| `pdm_api_token` | API tokens of a user |
| `pdm_acl` | ACL entries (`path\|user-or-token\|role`) |
| `pdm_realm` | LDAP, Active Directory and OpenID Connect realms |
| `pdm_view` | Resource views (include and exclude rules, layout) |
| `pdm_notes` | The global Markdown notes (title `global`) |
| `pdm_node_config` | Node settings: sender address, proxy, UI language (title `localhost`) |

Every attribute, the class parameters and the `pdm_api_request` task are documented in
[REFERENCE.md](https://github.com/Data-JT/puppet-proxmox_datacenter_manager/blob/master/REFERENCE.md).

## Further documentation

- [Class parameters and TLS](https://github.com/Data-JT/puppet-proxmox_datacenter_manager/blob/master/docs/class-parameters.md): transport settings, certificate verification, the transport file.
- [Remotes and views](https://github.com/Data-JT/puppet-proxmox_datacenter_manager/blob/master/docs/remotes.md): connecting PVE and PBS instances, the remote token, views over them.
- [Authentication realms](https://github.com/Data-JT/puppet-proxmox_datacenter_manager/blob/master/docs/realms.md): LDAP, AD and OpenID examples and their credentials.
- [API tokens](https://github.com/Data-JT/puppet-proxmox_datacenter_manager/blob/master/docs/api-tokens.md): keeping the one-time secret with `secret_file`.
- [Secret drift detection](https://github.com/Data-JT/puppet-proxmox_datacenter_manager/blob/master/docs/secret-drift.md): how secrets are compared and redacted.
- [Clearing optional properties](https://github.com/Data-JT/puppet-proxmox_datacenter_manager/blob/master/docs/clearing-properties.md): removing a value on the PDM side with `delete_properties`.
- [Resource notes](https://github.com/Data-JT/puppet-proxmox_datacenter_manager/blob/master/docs/resource-notes.md): singletons, operational endpoints, ordering in the resources class.
- [Importing an existing PDM](https://github.com/Data-JT/puppet-proxmox_datacenter_manager/blob/master/docs/hiera-import.md): generate Hiera data from a live instance.
- [Ad-hoc API access](https://github.com/Data-JT/puppet-proxmox_datacenter_manager/blob/master/docs/api-access.md): the `pdm_api_request` Bolt task.

## Limitations

- Managing `pdm_remote.token`, `pdm_realm.bind_password` or `pdm_user.password` requires the
  agent on the PDM node as root. If a secret's store cannot be read, the run fails rather than
  reporting the resource in sync. Everything else, including `pdm_realm.client_key`, can be
  managed from an agent on any host.
- `pdm_node_config` must be titled `localhost` and `pdm_notes` must be titled `global`; PDM has
  exactly one of each, and `ensure => absent` on them is a logged no-op.
- `pdm_remote` needs `token` at creation, also when `create_token` is used.
- PDM 2.x is not supported until the module is explicitly declared compatible.

## Contributing

Issues and pull requests are welcome on
[GitHub](https://github.com/Data-JT/puppet-proxmox_datacenter_manager/issues); please open an
issue before significant work. See [CONTRIBUTING.md](https://github.com/Data-JT/puppet-proxmox_datacenter_manager/blob/master/CONTRIBUTING.md)
for the development workflow and [SECURITY.md](https://github.com/Data-JT/puppet-proxmox_datacenter_manager/blob/master/SECURITY.md)
for reporting vulnerabilities.

## License

Apache-2.0, see [LICENSE](https://github.com/Data-JT/puppet-proxmox_datacenter_manager/blob/master/LICENSE).

## About Data JT

This module is built and maintained by [Data JT](https://www.data-jt.de), an IT and data
protection consultancy near Freiburg, Germany. All our modules are on the
[Puppet Forge](https://forge.puppet.com/modules/datajt). For anything beyond issues and pull
requests, [get in touch](https://www.data-jt.de/kontakt).
