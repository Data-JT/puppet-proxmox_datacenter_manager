# frozen_string_literal: true

require_relative 'proxmox_datacenter_manager'

# Filename-matched alias the Resource API resolves as the pdm_node_config provider.
class Puppet::Provider::PdmNodeConfig::PdmNodeConfig < Puppet::Provider::PdmNodeConfig::ProxmoxDatacenterManager; end
