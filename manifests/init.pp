# @summary Configures the transport used by the PDM Resource API providers.
#
# Writes the PDM API connection settings to a YAML transport file. Declare this class
# before classes that contain `pdm_*` resources so providers can discover the transport
# before they retrieve existing resources.
#
# @example Configure a PDM connection
#   class { 'proxmox_datacenter_manager':
#     host         => 'pdm.example.com',
#     token_id     => 'puppet@pdm!puppet',
#     token_secret => Sensitive(lookup('pdm::token_secret')),
#     ssl_ca_file  => '/etc/ssl/certs/internal-ca.pem',
#   }
#
# @param token_id PDM API token ID in user@realm!tokenname format.
# @param token_secret PDM API token secret.
# @param host PDM hostname or IP address.
# @param port PDM HTTPS API port.
# @param ssl_verify Whether to verify the PDM TLS certificate.
# @param ssl_ca_file CA bundle used for PDM certificate verification, or `undef` to use the system trust store.
# @param config_file Absolute path for the transport configuration. A symlink is created at the provider discovery path when this differs.
#   Defaults to the agent's own confdir (fact `proxmox_datacenter_manager_confdir`), which is
#   where the providers look; the compiling server's confdir may differ.
class proxmox_datacenter_manager (
  Pattern[/\A[^@!\s]+@[^@!\s]+![^!\s]+\z/] $token_id,
  Sensitive[String]                        $token_secret,
  String                                   $host        = 'localhost',
  Integer                                  $port        = 8443,
  Boolean                                  $ssl_verify  = true,
  Optional[Pattern[/\A\//]]                $ssl_ca_file = undef,
  # The agent's confdir, from the proxmox_datacenter_manager_confdir fact: the
  # providers read Puppet.settings[:confdir] on the node, while
  # $settings::confdir here is the COMPILING server's, which differs when
  # server and agent use different layouts (AIO server, Debian agent).
  # $settings::confdir only before the fact has been pluginsynced.
  Pattern[/\A\//]                          $config_file = "${$facts['proxmox_datacenter_manager_confdir'].lest || { $settings::confdir }}/pdm_transport.yaml",
) {
  file { $config_file:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    content => Sensitive(epp('proxmox_datacenter_manager/pdm_transport.epp', {
          'host'         => $host,
          'port'         => $port,
          'token_id'     => $token_id,
          'token_secret' => $token_secret.unwrap,
          'ssl_verify'   => $ssl_verify,
          'ssl_ca_file'  => $ssl_ca_file,
    })),
  }

  $provider_config_file = "${$facts['proxmox_datacenter_manager_confdir'].lest || { $settings::confdir }}/pdm_transport.yaml"
  if $config_file != $provider_config_file {
    file { $provider_config_file:
      ensure  => link,
      target  => $config_file,
      require => File[$config_file],
    }
  }
}
