# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pdm_sensitive_parameters'
require_relative 'pdm_transport_autorequire'

Puppet::ResourceApi.register_type(
  name: 'pdm_user',
  features: ['custom_insync'],
  docs: <<~DOC,
    @summary Manages a Proxmox Datacenter Manager user.

    Passwords are verified with crypt(3) against the hash in
    `/etc/proxmox-datacenter-manager/access/shadow.json`, so managing `password`
    requires the agent to run on the PDM node as root. See the README.

    @example Manage an automation user
      pdm_user { 'automation@pdm':
        ensure => present,
        enable => true,
        email  => 'automation@example.com',
      }
  DOC
  attributes: {
    ensure: { type: 'Enum[present, absent]', default: 'present', desc: 'Whether the user exists.' },
    userid: { type: 'String', behaviour: :namevar, desc: 'User ID in user@realm format.' },
    comment: { type: 'Optional[String]', desc: 'Human-readable comment.' },
    email: { type: 'Optional[String]', desc: 'Email address.' },
    enable: { type: 'Boolean', default: true, desc: 'Whether the account is enabled.' },
    expire: { type: 'Optional[Integer]', desc: 'Unix expiry timestamp; 0 means no expiry.' },
    firstname: { type: 'Optional[String]', desc: 'First name.' },
    lastname: { type: 'Optional[String]', desc: 'Last name.' },
    password: {
      type: 'Optional[Variant[String, Sensitive[String]]]',
      sensitive: true,
      desc: 'Account password. Verified against shadow.json on the PDM node and re-sent when it no longer matches.',
    },
    delete_properties: { type: 'Optional[Array[String]]', desc: 'PDM API property names to remove during an update.' },
  },
)

Puppet::Type::PdmTransportAutorequire.register(:pdm_user)
Puppet::Type::PdmSensitiveParameters.register(:pdm_user)
