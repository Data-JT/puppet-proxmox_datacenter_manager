# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pdm_sensitive_parameters'
require_relative 'pdm_transport_autorequire'

Puppet::ResourceApi.register_type(
  name: 'pdm_api_token',
  features: ['custom_insync'],
  docs: <<~DOC,
    @summary Manages PDM API token metadata.

    PDM returns a generated token secret only during creation. Set `secret_file` to
    retain it on the Puppet agent without exposing it in reports or logs.

    @example Create a token and retain its generated secret
      pdm_api_token { 'automation@pdm!ci':
        ensure      => present,
        enable      => true,
        comment     => 'CI automation',
        secret_file => '/etc/puppetlabs/puppet/pdm-ci-token.secret',
      }
  DOC
  attributes: {
    ensure: { type: 'Enum[present, absent]', default: 'present', desc: 'Whether the token exists.' },
    tokenid: { type: 'String', behaviour: :namevar, desc: 'Full token ID in user@realm!tokenname format.' },
    comment: { type: 'Optional[String]', desc: 'Human-readable comment.' },
    enable: { type: 'Optional[Boolean]', desc: 'Whether the token is enabled.' },
    expire: { type: 'Optional[Integer]', desc: 'Unix expiry timestamp; 0 means no expiry.' },
    secret_file: {
      type: 'Optional[String]',
      behaviour: :parameter,
      desc: 'Agent-local file receiving the one-time token secret on creation, written with mode 0600.',
    },
    delete_properties: { type: 'Optional[Array[String]]', desc: 'PDM API property names to remove during an update.' },
  },
)

Puppet::Type::PdmTransportAutorequire.register(:pdm_api_token)
Puppet::Type::PdmSensitiveParameters.register(:pdm_api_token)
