# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pdm_sensitive_parameters'
require_relative 'pdm_transport_autorequire'

Puppet::ResourceApi.register_type(
  name: 'pdm_view',
  features: ['custom_insync'],
  docs: <<~DOC,
    @summary Manages a PDM resource view.

    @example Manage a view containing one remote
      pdm_view { 'production':
        ensure      => present,
        include     => ['remote=production'],
        include_all => false,
      }
  DOC
  attributes: {
    ensure: { type: 'Enum[present, absent]', default: 'present', desc: 'Whether the view exists.' },
    id: { type: 'String', behaviour: :namevar, desc: 'View ID.' },
    include: { type: 'Optional[Array[String]]', desc: 'Inclusion rules.' },
    exclude: { type: 'Optional[Array[String]]', desc: 'Exclusion rules.' },
    include_all: { type: 'Optional[Boolean]', desc: 'Include-all setting.' },
    layout: { type: 'Optional[String]', desc: 'JSON layout.' },
    delete_properties: { type: 'Optional[Array[String]]', desc: 'PDM API property names to remove during an update.' },
  },
)

Puppet::Type::PdmTransportAutorequire.register(:pdm_view)
Puppet::Type::PdmSensitiveParameters.register(:pdm_view)
