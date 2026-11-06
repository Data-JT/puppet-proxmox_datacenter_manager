# frozen_string_literal: true

require_relative 'proxmox_datacenter_manager'

# Filename-matched alias the Resource API resolves as the pdm_api_token provider.
class Puppet::Provider::PdmApiToken::PdmApiToken < Puppet::Provider::PdmApiToken::ProxmoxDatacenterManager; end
