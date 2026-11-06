# Importing an existing PDM into Hiera

How to adopt a PDM instance that is already configured, by generating Hiera data from its live
API.

`tools/pdm_hiera_import.rb` generates Hiera data for the `proxmox_datacenter_manager::resources`
class from the live PDM API, so Puppet can adopt resources that already exist. It is a
checkout-only utility and is intentionally not included in the Puppet Forge package. It verifies
TLS certificates by default; use `--no-ssl-verify` only on a trusted network when verification
cannot be configured.

## Running the import

First make sure the API token can read the resource types you want to import.

The importer exports the non-secret parts of existing remotes, users, API tokens, ACLs, realms,
views, node configuration and notes. It reads the token secret from the `PDM_TOKEN_SECRET`
environment variable, never from the command line:

```sh
read -rsp 'PDM token secret: ' PDM_TOKEN_SECRET
printf '\n'
export PDM_TOKEN_SECRET

ruby tools/pdm_hiera_import.rb \
  --host pdm.example.com \
  --token-id 'puppet@pdm!puppet' \
  --output pdm-import.yaml

unset PDM_TOKEN_SECRET
```

Pass `--ssl-ca-file` for a private CA. Run `ruby tools/pdm_hiera_import.rb --help` for all options.

## Adopting the data

Add the generated data to the node's Hiera hierarchy and include
`proxmox_datacenter_manager::resources` together with the main class. Run the first adoption pass
in no-op mode and review the proposed changes before applying normally:

```sh
puppet agent -t --noop
```

Existing PDM resources that are absent from the Hiera data are not purged by this module. Remote
tokens, bind passwords and user passwords are not exported; add them encrypted, or leave the
attribute out to keep the stored value unmanaged.
