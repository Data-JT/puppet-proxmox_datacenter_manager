# frozen_string_literal: true

require_relative '../pdm_base_provider'

# @api private
module Puppet::Provider::PdmApiToken; end

# Provider for PDM API token metadata.
class Puppet::Provider::PdmApiToken::ProxmoxDatacenterManager < Puppet::Provider::PdmBaseProvider
  def self.attribute_map
    {
      'tokenid' => :tokenid,
      'comment' => :comment,
      'enable' => :enable,
      'expire' => :expire,
      'delete' => :delete_properties,
    }
  end

  def self.boolean_attributes
    [:enable]
  end

  def get(context)
    (transport_get(context, '/access/users') || []).flat_map do |user|
      userid = user['userid']
      path = pdm_path('/access/users/{userid}/token', userid: userid)
      (transport_get(context, path) || []).map do |token|
        pdm_to_puppet(token).merge(ensure: 'present')
      end
    end
  end

  def create(context, name, should)
    userid, token_name = parse_tokenid(name)
    context.notice("Creating PDM API token '#{name}'")
    # The token ID travels in the path, so the body is built like an update's
    # (namevar dropped) but without the 'delete' a POST does not accept.
    result = pdm_transport(context).post(
      context,
      token_path(userid, token_name),
      update_request_body(context, should).except('delete'),
    )
    persist_secret(context, name, should[:secret_file], result)
  end

  def update(context, name, should)
    userid, token_name = parse_tokenid(name)
    context.notice("Updating PDM API token '#{name}'")
    pdm_transport(context).put(
      context,
      token_path(userid, token_name),
      update_request_body(context, should),
    )
  end

  def delete(context, name)
    userid, token_name = parse_tokenid(name)
    context.notice("Deleting PDM API token '#{name}'")
    pdm_transport(context).delete(context, token_path(userid, token_name))
  end

  private

  def persist_secret(context, tokenid, secret_file, result)
    secret = result['value'] if result.is_a?(Hash)
    return unless secret

    unless secret_file
      context.warning("PDM returned the one-time secret for '#{tokenid}', but secret_file is not configured; the secret was not retained")
      return
    end

    flags = File::WRONLY | File::CREAT | File::TRUNC | File::NOFOLLOW
    File.open(secret_file, flags, 0o600) do |file|
      file.chmod(0o600)
      file.write("#{secret}\n")
    end
    context.notice("Stored the one-time secret for PDM API token '#{tokenid}' in #{secret_file}")
  end

  def parse_tokenid(tokenid)
    userid, token_name, extra = tokenid.split('!', 3)
    return [userid, token_name] if extra.nil? && userid.include?('@') && !token_name.to_s.empty?

    raise Puppet::ResourceError, "tokenid must be in user@realm!tokenname format, got: #{tokenid.inspect}"
  end

  def token_path(userid, token_name)
    pdm_path('/access/users/{userid}/token/{token-name}', userid: userid, 'token-name': token_name)
  end
end
