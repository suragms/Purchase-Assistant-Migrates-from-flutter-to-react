-- Migration 046: server-persisted report saved views
CREATE TABLE IF NOT EXISTS report_saved_views (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name VARCHAR(120) NOT NULL,
  tab VARCHAR(32) NOT NULL,
  filters_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_default BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_report_saved_views_business_user
  ON report_saved_views (business_id, user_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_report_saved_views_default_per_tab
  ON report_saved_views (business_id, user_id, tab)
  WHERE is_default = true;
