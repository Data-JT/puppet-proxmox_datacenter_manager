# Clearing optional properties

How to remove a value on the PDM side, since removing an attribute from a manifest does not.

Removing an attribute from a manifest only stops Puppet managing it; the value stays set on the
PDM side. To clear an optional property, list its PDM API name (the hyphenated name the API uses,
such as `web-url`, not the Puppet attribute name) in `delete_properties`:

```puppet
pdm_view { 'production':
  delete_properties => ['layout'],
}
```

The provider passes the list to the endpoint's `delete` parameter on update, and only while one of
the named properties is still set, so the resource converges instead of re-sending the deletion on
every run. A name the provider does not map is rejected, because its removal could never be
observed. Create requests never carry the parameter.

The following types support `delete_properties`: `pdm_api_token`, `pdm_node_config`, `pdm_realm`,
`pdm_remote`, `pdm_user` and `pdm_view`.
