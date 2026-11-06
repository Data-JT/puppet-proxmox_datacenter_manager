# frozen_string_literal: true

require_relative 'proxmox_datacenter_manager'

# Filename-matched alias the Resource API resolves as the pdm_view provider.
class Puppet::Provider::PdmView::PdmView < Puppet::Provider::PdmView::ProxmoxDatacenterManager; end
