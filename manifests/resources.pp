# @summary Declares PDM resources from Hiera data.
#
# This convenience class turns hashes into the corresponding `pdm_*` resources. It does
# not configure the provider transport; declare `proxmox_datacenter_manager` before this
# class.
#
# @example Declare resources directly
#   class { 'proxmox_datacenter_manager::resources':
#     remotes => {
#       'production' => {
#         type   => 'pve',
#         nodes  => ['pve01.example.com'],
#         authid => 'pdm@pve!manager',
#         token  => Sensitive(lookup('pdm::remotes::production_token')),
#       },
#     },
#   }
#
# @param remotes Hash of pdm_remote resources.
# @param users Hash of pdm_user resources.
# @param api_tokens Hash of pdm_api_token resources.
# @param acls Hash of pdm_acl resources.
# @param realms Hash of pdm_realm resources.
# @param views Hash of pdm_view resources.
# @param node_config Hash of pdm_node_config resources.
# @param notes Hash of pdm_notes resources.
class proxmox_datacenter_manager::resources (
  Hash[String, Hash] $remotes     = {},
  Hash[String, Hash] $users       = {},
  Hash[String, Hash] $api_tokens  = {},
  Hash[String, Hash] $acls        = {},
  Hash[String, Hash] $realms      = {},
  Hash[String, Hash] $views       = {},
  Hash[String, Hash] $node_config = {},
  Hash[String, Hash] $notes       = {},
) {
  $remotes.each |String $title, Hash $attributes| {
    pdm_remote { $title: * => $attributes }
  }
  $users.each |String $title, Hash $attributes| {
    pdm_user { $title: * => $attributes }
  }
  $api_tokens.each |String $title, Hash $attributes| {
    pdm_api_token { $title: * => $attributes }
  }
  $acls.each |String $title, Hash $attributes| {
    pdm_acl { $title: * => $attributes }
  }
  $realms.each |String $title, Hash $attributes| {
    pdm_realm { $title: * => $attributes }
  }
  $views.each |String $title, Hash $attributes| {
    pdm_view { $title: * => $attributes }
  }
  $node_config.each |String $title, Hash $attributes| {
    pdm_node_config { $title: * => $attributes }
  }
  $notes.each |String $title, Hash $attributes| {
    pdm_notes { $title: * => $attributes }
  }

  # Order related resources only when both are managed by this Hiera class.
  $users.each |String $title, Hash $attributes| {
    $realm = $title.split('@')[-1]
    if $realm in $realms {
      Pdm_realm[$realm] -> Pdm_user[$title]
    }
  }

  $api_tokens.each |String $title, Hash $attributes| {
    $userid = $title.split('!')[0]
    if $userid in $users {
      Pdm_user[$userid] -> Pdm_api_token[$title]
    }
  }

  $acls.each |String $title, Hash $attributes| {
    $ugid = $title.split('[|]')[1]
    if $ugid in $users {
      Pdm_user[$ugid] -> Pdm_acl[$title]
    }
    if $ugid in $api_tokens {
      Pdm_api_token[$ugid] -> Pdm_acl[$title]
    }
  }

  $views.each |String $title, Hash $attributes| {
    if $attributes['include'] and $attributes['include'] != 'absent' {
      $attributes['include'].each |String $rule| {
        $parts = $rule.split('=')
        if $parts[0] == 'remote' and $parts[1] in $remotes {
          Pdm_remote[$parts[1]] -> Pdm_view[$title]
        }
      }
    }
    if $attributes['exclude'] and $attributes['exclude'] != 'absent' {
      $attributes['exclude'].each |String $rule| {
        $parts = $rule.split('=')
        if $parts[0] == 'remote' and $parts[1] in $remotes {
          Pdm_remote[$parts[1]] -> Pdm_view[$title]
        }
      }
    }
  }
}
