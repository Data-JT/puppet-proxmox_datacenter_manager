# frozen_string_literal: true

require_relative 'proxmox_datacenter_manager'

# Filename-matched alias the Resource API resolves as the pdm_remote provider.
class Puppet::Provider::PdmRemote::PdmRemote < Puppet::Provider::PdmRemote::ProxmoxDatacenterManager; end
