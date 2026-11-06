# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- The Quality workflow also runs the unit tests on OpenVox 9.
- Data JT banner and an About section in the README; `metadata.json` names Data JT as the
  author.

## [0.1.0] - 2026-11-06

Initial release.

### Added

- Supports Puppet 8 and 9 (tested on 8) on Debian 13, managing PDM 1.x. The module has no
  Forge dependencies; the Resource API it builds on ships with Puppet.
- `proxmox_datacenter_manager` class that writes the API transport credentials to a
  `root:root` mode `0600` file, with the parameters `token_id`, `token_secret`, `host`,
  `port`, `ssl_verify`, `ssl_ca_file` and `config_file`. TLS certificates are verified by
  default. When `config_file` points elsewhere, a symlink is created at the provider
  discovery path. API requests time out after 10 seconds connecting and 60 seconds
  reading.
- The transport file and its provider discovery path follow the agent's own Puppet
  confdir (fact `proxmox_datacenter_manager_confdir`), not the compiling server's, so an
  OpenVox/AIO server can compile for a Debian-packaged agent.
- `proxmox_datacenter_manager::resources` class that declares resources from Hiera hashes
  and orders related entries declared through it.
- Resource types: `pdm_acl`, `pdm_api_token`, `pdm_node_config`, `pdm_notes`, `pdm_realm`,
  `pdm_remote`, `pdm_user` and `pdm_view`. `pdm_acl` accepts user, group and token
  subjects.
- Drift detection and enforcement for every managed secret: changing a secret in Hiera
  rotates it on the next run. `pdm_realm.client_key` is compared over the API;
  `pdm_remote.token`, `pdm_realm.bind_password` and `pdm_user.password` are compared
  against PDM's own copies under `/etc/proxmox-datacenter-manager`, which requires the
  agent to run on the PDM node as root. A declared secret whose store cannot be read
  fails the run.
- Secret attributes are redacted from change notices, report events, PuppetDB and
  `last_run_report.yaml`.
- `delete_properties` clears optional properties on `pdm_api_token`, `pdm_node_config`,
  `pdm_realm`, `pdm_remote`, `pdm_user` and `pdm_view`.
- Optional `secret_file` on `pdm_api_token` retains the one-time token secret on the agent
  with mode `0600`.
- `pdm_api_request` task for ad-hoc API calls, including PDM's operational endpoints.
- `tools/pdm_hiera_import.rb`, a checkout-only tool that generates Hiera data from an
  existing PDM instance. It is not part of the Forge package.

[Unreleased]: https://github.com/Data-JT/puppet-proxmox_datacenter_manager/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Data-JT/puppet-proxmox_datacenter_manager/releases/tag/v0.1.0
