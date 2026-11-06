# frozen_string_literal: true

require_relative '../pdm_base_provider'
require_relative '../../../puppet_x/proxmox_datacenter_manager/crypt' # see crypt.rb: a bare require breaks in puppetserver

# @api private
module Puppet::Provider::PdmUser; end

# Provider for PDM users.
class Puppet::Provider::PdmUser::ProxmoxDatacenterManager < Puppet::Provider::PdmBaseProvider
  def self.attribute_map
    {
      'userid' => :userid,
      'comment' => :comment,
      'email' => :email,
      'enable' => :enable,
      'expire' => :expire,
      'firstname' => :firstname,
      'lastname' => :lastname,
      'password' => :password,
      'delete' => :delete_properties,
    }
  end

  def self.boolean_attributes
    [:enable]
  end

  def self.secret_attributes
    [:password]
  end

  def get(context)
    (transport_get(context, '/access/users') || []).map { |user| map_user(user) }
  end

  def stored_secret(title, _attribute_name)
    PuppetX::ProxmoxDatacenterManager::SecretStore.user_password_hash(title)
  end

  # PDM stores a crypt(3) hash rather than the password, so the declared value
  # is verified against it instead of compared to it.
  def secret_matches?(stored, desired)
    PuppetX::ProxmoxDatacenterManager::Crypt.verify(desired, stored)
  end

  def create(context, name, should)
    context.notice("Creating PDM user '#{name}'")
    pdm_transport(context).post(context, '/access/users', create_request_body(should))
  end

  def update(context, name, should)
    context.notice("Updating PDM user '#{name}'")
    pdm_transport(context).put(context, pdm_path('/access/users/{userid}', userid: name), update_request_body(context, should))
  end

  def delete(context, name)
    context.notice("Deleting PDM user '#{name}'")
    pdm_transport(context).delete(context, pdm_path('/access/users/{userid}', userid: name))
  end

  private

  # The API never returns a password or a derivative of one, so the reported
  # value comes from shadow.json instead.
  def map_user(user)
    mapped = pdm_to_puppet(user).reject { |key, _| key == :password }
    { enable: true }.merge(mapped, ensure: 'present', **password_placeholder(user['userid']))
  end

  def password_placeholder(userid)
    placeholder = secret_placeholder(userid, :password)
    placeholder ? { password: placeholder } : {}
  end
end
