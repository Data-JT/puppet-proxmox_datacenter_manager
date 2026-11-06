# frozen_string_literal: true

require_relative 'proxmox_datacenter_manager'

# Filename-matched alias the Resource API resolves as the pdm_user provider.
class Puppet::Provider::PdmUser::PdmUser < Puppet::Provider::PdmUser::ProxmoxDatacenterManager; end
