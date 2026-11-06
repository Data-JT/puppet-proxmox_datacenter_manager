# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pdm_sensitive_parameters'
require_relative 'pdm_transport_autorequire'

Puppet::ResourceApi.register_type(
  name: 'pdm_notes',
  docs: <<~DOC,
    @summary Manages the singleton global PDM Markdown notes.

    The only valid resource title is `global`. PDM does not allow this object to be
    deleted, so `ensure => absent` performs no deletion; to stop managing it, remove the
    resource from the catalog rather than setting `ensure => absent`.

    @example Manage global notes
      pdm_notes { 'global':
        notes => "# Datacenter\n\nManaged by Puppet.\n",
      }
  DOC
  attributes: {
    ensure: { type: 'Enum[present, absent]', default: 'present', desc: 'Always-present object; absent performs no deletion. Remove the resource from the catalog to stop managing it.' },
    name: { type: "Enum['global']", behaviour: :namevar, desc: 'Singleton resource name.' },
    notes: { type: 'String', desc: 'Global notes in Markdown.' },
  },
)

Puppet::Type::PdmTransportAutorequire.register(:pdm_notes)
Puppet::Type::PdmSensitiveParameters.register(:pdm_notes)
