# frozen_string_literal: true

require_relative 'proxmox_datacenter_manager'

# Filename-matched alias the Resource API resolves as the pdm_acl provider.
class Puppet::Provider::PdmAcl::PdmAcl < Puppet::Provider::PdmAcl::ProxmoxDatacenterManager; end
