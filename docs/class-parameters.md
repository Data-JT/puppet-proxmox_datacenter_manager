# Class parameters and TLS

The `proxmox_datacenter_manager` class configures how the providers reach the PDM API. The
generated parameter reference is in [REFERENCE.md](../REFERENCE.md#proxmox_datacenter_manager);
this page adds the context around it.

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `token_id` | `Pattern[/\A[^@!\s]+@[^@!\s]+![^!\s]+\z/]` | — | API token ID (`user@realm!tokenname`) |
| `token_secret` | `Sensitive[String]` | — | API token secret |
| `host` | `String` | `'localhost'` | PDM hostname or IP |
| `port` | `Integer` | `8443` | PDM HTTPS API port |
| `ssl_verify` | `Boolean` | `true` | Verify the PDM TLS certificate |
| `ssl_ca_file` | `Optional[Pattern[/\A\//]]` (absolute path) | `undef` | CA bundle path; `undef` uses the system trust store |
| `config_file` | `Pattern[/\A\//]` (absolute path) | `<agent confdir>/pdm_transport.yaml` | Where to write the transport credentials |

The module has no `task_timeout` parameter: no PDM endpoint the providers call runs as an
asynchronous task.

`token_secret` must be `Sensitive`. When it comes from Hiera, convert it with `lookup_options`:

```yaml
lookup_options:
  proxmox_datacenter_manager::token_secret:
    convert_to: Sensitive
```

In a manifest, wrap it explicitly:

```puppet
class { 'proxmox_datacenter_manager':
  host         => 'pdm.example.com',
  token_id     => 'puppet@pdm!puppet',
  token_secret => Sensitive(lookup('pdm::token_secret')),
  ssl_ca_file  => '/etc/ssl/certs/example-ca.pem',
}
```

PDM API tokens authenticate with the HTTP authorization scheme `PDMAPIToken=TOKENID:TOKENSECRET`;
the providers build that header from the two values.

## TLS verification

TLS verification is enabled by default. A fresh PDM installation serves a self-signed certificate
that fails verification, so either point `ssl_ca_file` at the CA certificate that signed the PDM
certificate (recommended), or explicitly set `ssl_verify => false`. Disabling verification allows
man-in-the-middle attacks on the API connection; it is only a reasonable trade-off when the API
traffic never leaves the node (`host => 'localhost'`, the default).

## The transport file

The class writes the credentials to `config_file` (mode `0600`, `root:root`), which the providers
read at agent run time. Declare the class on the agent that manages PDM, in `site.pp`, a role or a
profile. That agent can run on the PDM node or on another Puppet-managed host; see
[Secret drift detection](secret-drift.md) for the resources that need the node.

- All `pdm_*` types automatically require the managed transport file when it is present in the
  catalog. On a first run, providers wait for that file and refresh actual PDM state before
  creating or updating resources, so a single `puppet agent -t` applies the class and all
  `pdm_*` resources in the same pass. Credentials are reloaded when the file changes.
- When `config_file` points elsewhere, the class creates a symlink at the provider discovery path
  (`<agent confdir>/pdm_transport.yaml`).
- The default is the agent's own confdir (from the `proxmox_datacenter_manager_confdir` fact),
  not the compiling server's, since the two can differ.
