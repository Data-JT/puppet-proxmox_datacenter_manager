# API tokens

Examples for `pdm_api_token`. All attributes are documented in
[REFERENCE.md](../REFERENCE.md#pdm_api_token).

The namevar is the full token ID in `user@realm!tokenname` format, the same string used to
authenticate API requests and to assign permissions via `pdm_acl`. `pdm_api_token` manages token
existence and metadata (`comment`, `enable`, `expire`).

```puppet
pdm_user { 'automation@pdm':
  ensure => present,
  enable => true,
  email  => 'automation@example.com',
}

pdm_api_token { 'automation@pdm!ci':
  ensure      => present,
  enable      => true,
  comment     => 'CI automation',
  secret_file => '/etc/puppetlabs/puppet/pdm-ci-token.secret',
}

pdm_acl { '/|automation@pdm!ci|Auditor':
  ensure    => present,
  propagate => true,
}
```

## Keeping the one-time secret

PDM returns the generated secret only once, during creation. Set `secret_file` to retain it on the
Puppet agent with mode `0600` without exposing it in reports or logs. The parent directory must
already exist and be writable by the Puppet agent. For safety, the destination cannot be a
symbolic link. Without `secret_file`, the provider still manages token existence and metadata but
deliberately does not place the secret in Puppet reports or logs, so it is lost.

Because PDM stores only a hash afterwards, a token secret cannot be checked for drift on later
runs. See [Secret drift detection](secret-drift.md).
