-- Performance review of Part 1a's migration layer, 2026-08-18. Both indexes below were created by
-- 20260818100000 and are redundant: they add write cost on every booking and serve no query that an
-- existing index does not already serve.

-- assessment_assignees_pkey is (assessment_id, user_id) and already leads with assessment_id, so it
-- serves every lookup by assessment.
drop index public.assessment_assignees_assessment_idx;

-- assessments_request_unique is a UNIQUE index on request_id, so a lookup by request returns at most
-- one row without help. Organization-scoped scans are served by assessments_organization_updated_idx.
drop index public.assessments_organization_request_idx;
