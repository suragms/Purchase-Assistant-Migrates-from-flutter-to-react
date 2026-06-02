BEGIN;

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT n.nspname AS schemaname, c.relname AS tablename
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid
    WHERE c.relkind = 'r'
      AND n.nspname = 'public'
      AND a.attname = 'business_id'
      AND a.attnum > 0
      AND NOT a.attisdropped
  LOOP
    EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', r.schemaname, r.tablename);
    IF NOT EXISTS (
      SELECT 1
      FROM pg_policies
      WHERE schemaname = r.schemaname
        AND tablename = r.tablename
        AND policyname = 'p_business_isolation'
    ) THEN
      EXECUTE format(
        'CREATE POLICY p_business_isolation ON %I.%I
         USING (business_id = NULLIF(current_setting(''app.current_business_id'', true), '''')::uuid)
         WITH CHECK (business_id = NULLIF(current_setting(''app.current_business_id'', true), '''')::uuid)',
        r.schemaname,
        r.tablename
      );
    END IF;
  END LOOP;
END $$;

COMMIT;
