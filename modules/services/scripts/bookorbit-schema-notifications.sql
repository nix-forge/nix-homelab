CREATE OR REPLACE FUNCTION public.homelab_bookorbit_schema_changed () RETURNS event_trigger LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_notify('homelab_bookorbit_schema', 'changed');
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_event_trigger WHERE evtname = 'homelab_bookorbit_schema_changed') THEN
    CREATE EVENT TRIGGER homelab_bookorbit_schema_changed
      ON ddl_command_end WHEN TAG IN ('CREATE TABLE', 'ALTER TABLE')
      EXECUTE FUNCTION public.homelab_bookorbit_schema_changed();
  END IF;
END;
$$;
