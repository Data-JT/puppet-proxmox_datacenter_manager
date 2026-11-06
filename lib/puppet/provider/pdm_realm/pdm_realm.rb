# frozen_string_literal: true

require_relative 'proxmox_datacenter_manager'

# Filename-matched alias the Resource API resolves as the pdm_realm provider.
class Puppet::Provider::PdmRealm::PdmRealm < Puppet::Provider::PdmRealm::ProxmoxDatacenterManager; end
