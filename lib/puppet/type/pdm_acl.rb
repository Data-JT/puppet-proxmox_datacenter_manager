# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pdm_sensitive_parameters'
require_relative 'pdm_transport_autorequire'

Puppet::ResourceApi.register_type(
  name: 'pdm_acl',
  docs: <<~DOC,
    @summary Manages a PDM access control entry.

    Titles contain the object path, user/group/token ID, and role separated by pipes.

    @example Grant a token the Auditor role
      pdm_acl { '/|automation@pdm!ci|Auditor':
        ensure    => present,
        propagate => true,
      }
  DOC
  title_patterns: [
    {
      pattern: %r{^(?<acl_path>[^|]+)\|(?<ugid>[^|]+)\|(?<role>[^|]+)$},
      desc: 'acl_path, ugid and role separated by pipes',
    },
  ],
  attributes: {
    ensure: { type: 'Enum[present, absent]', default: 'present', desc: 'Whether the ACL exists.' },
    acl_path: { type: 'String', behaviour: :namevar, desc: 'ACL object path.' },
    ugid: { type: 'String', behaviour: :namevar, desc: 'User, group, or token ID.' },
    ugid_type: {
      type: "Optional[Enum['user', 'group', 'token']]",
      behaviour: :parameter,
      desc: 'ACL subject type. Inferred from ugid when omitted; token is accepted for imported ACLs.',
    },
    role: {
      type: 'String',
      behaviour: :namevar,
      # Puppet Strings cannot parse concatenated Resource API description strings.
      # rubocop:disable Layout/LineLength
      desc: 'PDM role name, e.g. Administrator, Auditor, or NoAccess. PDM ships no API to create custom roles, and the role list is not enumerated by the API, so this is a free-form string rather than a closed Enum.',
      # rubocop:enable Layout/LineLength
    },
    propagate: { type: 'Boolean', default: true, desc: 'Whether permissions propagate.' },
  },
)

Puppet::Type::PdmTransportAutorequire.register(:pdm_acl)
Puppet::Type::PdmSensitiveParameters.register(:pdm_acl)
