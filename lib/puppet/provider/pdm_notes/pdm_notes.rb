# frozen_string_literal: true

require_relative 'proxmox_datacenter_manager'

# Filename-matched alias the Resource API resolves as the pdm_notes provider.
class Puppet::Provider::PdmNotes::PdmNotes < Puppet::Provider::PdmNotes::ProxmoxDatacenterManager; end
