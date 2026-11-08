INSERT INTO
  app_settings (key, value)
VALUES
  (
    'metadata_provider_config',
    '@lib_replaceStrings_builtins_toJSON_cfg_metadataProviders@'
  )
ON CONFLICT (key) DO NOTHING;

INSERT INTO
  app_settings (key, value)
VALUES
  ('allow_registration', 'false')
ON CONFLICT (key) DO UPDATE
SET
  value = 'false';
