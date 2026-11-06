# frozen_string_literal: true

require_relative '../pdm_base_provider'

# @api private
module Puppet::Provider::PdmAcl; end

# Provider for PDM ACL entries.
class Puppet::Provider::PdmAcl::ProxmoxDatacenterManager < Puppet::Provider::PdmBaseProvider
  def self.attribute_map
    {
      'path' => :acl_path,
      'ugid' => :ugid,
      'ugid_type' => :ugid_type,
      # Both keys map to :role for forward compatibility; 'roleid' is listed last so the
      # authoritative role ID wins if a response ever contains both.
      'role' => :role,
      'roleid' => :role,
      'propagate' => :propagate,
    }
  end

  def self.boolean_attributes
    [:propagate]
  end

  def get(context)
    @ugid_types = {}
    (transport_get(context, '/access/acl') || []).map do |entry|
      result = pdm_to_puppet(entry).merge(ensure: 'present')
      key = acl_key(result)
      result[:title] = key
      ugid_types[key] = result[:ugid_type]
      result
    end
  end

  def create(context, name, should)
    context.notice("Creating PDM ACL '#{name}'")
    pdm_transport(context).put(context, '/access/acl', acl_body(should))
  end

  def update(context, name, should)
    create(context, name, should)
  end

  def delete(context, name)
    context.notice("Deleting PDM ACL '#{name}'")
    attributes = name.merge(ugid_type: ugid_types[acl_key(name)])
    pdm_transport(context).put(context, '/access/acl', acl_body(attributes).merge('delete' => true))
  end

  private

  def acl_body(attributes)
    subject_key = (acl_subject_type(attributes) == 'group') ? 'group' : 'auth-id'
    body = { 'path' => attributes[:acl_path], subject_key => attributes[:ugid], 'role' => attributes[:role] }
    body['propagate'] = to_bool(attributes[:propagate]) if attributes.key?(:propagate)
    body
  end

  def acl_subject_type(attributes)
    attributes[:ugid_type] || (attributes[:ugid].include?('@') ? 'user' : 'group')
  end

  def acl_key(attributes)
    [attributes[:acl_path], attributes[:ugid], attributes[:role]].join('|')
  end

  def ugid_types
    @ugid_types ||= {}
  end
end
