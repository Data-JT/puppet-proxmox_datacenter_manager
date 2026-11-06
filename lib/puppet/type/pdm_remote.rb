# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pdm_sensitive_parameters'
require_relative 'pdm_transport_autorequire'

Puppet::ResourceApi.register_type(
  name: 'pdm_remote',
  features: ['custom_insync'],
  docs: <<~DOC,
    @summary Manages a Proxmox VE or Proxmox Backup Server remote in PDM.

    The PDM API blanks the remote token on read, so drift is detected against the copy
    PDM keeps in `/etc/proxmox-datacenter-manager/remotes.shadow`. Managing `token`
    therefore requires the agent to run on the PDM node as root; see the README.

    @example Manage a Proxmox VE remote
      pdm_remote { 'production':
        ensure => present,
        type   => 'pve',
        nodes  => ['pve01.example.com', 'pve02.example.com'],
        authid => 'pdm@pve!manager',
        token  => Sensitive(lookup('pdm::remotes::production_token')),
      }
  DOC
  attributes: {
    ensure: { type: 'Enum[present, absent]', default: 'present', desc: 'Whether the remote exists.' },
    id: { type: 'String', behaviour: :namevar, desc: 'Remote ID.' },
    type: {
      type: "Enum['pve', 'pbs']",
      behaviour: :init_only,
      desc: 'Remote product type. Cannot be changed after creation.',
    },
    nodes: { type: 'Array[String, 1]', desc: 'Cluster node hostnames or IP addresses.' },
    authid: { type: 'String', desc: 'Authentication ID used on the remote.' },
    token: {
      type: 'Optional[Variant[String, Sensitive[String]]]',
      sensitive: true,
      desc: 'Remote API token secret. Compared against remotes.shadow on the PDM node and re-sent when it differs.',
    },
    create_token: {
      type: 'Optional[String]',
      behaviour: :parameter,
      desc: 'Ask PDM to create this token on the remote during creation.',
    },
    web_url: { type: 'Optional[String]', desc: 'Web UI URL configuration.' },
    delete_properties: { type: 'Optional[Array[String]]', desc: 'PDM API property names to remove during an update.' },
  },
)

Puppet::Type::PdmTransportAutorequire.register(:pdm_remote)
Puppet::Type::PdmSensitiveParameters.register(:pdm_remote)
