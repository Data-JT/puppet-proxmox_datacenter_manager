# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pdm_sensitive_parameters'
require_relative 'pdm_transport_autorequire'

Puppet::ResourceApi.register_type(
  name: 'pdm_node_config',
  features: ['custom_insync'],
  docs: <<~DOC,
    @summary Manages singleton PDM node-level API and UI configuration.

    The only valid resource title is `localhost`. PDM does not allow this object to be
    deleted, so `ensure => absent` performs no deletion; to stop managing it, remove the
    resource from the catalog rather than setting `ensure => absent`.

    @example Configure node defaults
      pdm_node_config { 'localhost':
        default_lang => 'en',
        email_from   => 'pdm@example.com',
        http_proxy   => 'http://proxy.example.com:3128',
      }
  DOC
  attributes: {
    ensure: { type: 'Enum[present, absent]', default: 'present', desc: 'Always-present object; absent performs no deletion. Remove the resource from the catalog to stop managing it.' },
    node: {
      type: "Enum['localhost']",
      behaviour: :namevar,
      desc: 'Singleton node configuration resource.',
    },
    email_from: { type: 'Optional[String]', desc: 'Sender email.' },
    http_proxy: { type: 'Optional[String]', desc: 'HTTP proxy.' },
    default_lang: { type: 'Optional[String]', desc: 'Default language.' },
    ciphers_tls_1_2: { type: 'Optional[String]', desc: 'TLS 1.2 cipher list.' },
    ciphers_tls_1_3: { type: 'Optional[String]', desc: 'TLS 1.3 ciphersuites.' },
    delete_properties: { type: 'Optional[Array[String]]', desc: 'PDM API property names to remove during an update.' },
  },
)

Puppet::Type::PdmTransportAutorequire.register(:pdm_node_config)
Puppet::Type::PdmSensitiveParameters.register(:pdm_node_config)
