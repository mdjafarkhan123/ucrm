-- The M1 baseline granted "public"."effective_marketing_email_limit" to service_role only, unlike its two
-- sibling limit functions (effective_employee_seat_limit, effective_website_chat_widgets_limit), which are
-- also granted to authenticated. resolveOrganizationAccess() now reads all three limits for a signed-in
-- member's own effective access, so the missing grant surfaced as "permission denied for function
-- effective_marketing_email_limit" the first time a member session (not the service role) called it.

GRANT ALL ON FUNCTION "public"."effective_marketing_email_limit"("target_organization_id" "uuid", "at" timestamp with time zone) TO "authenticated";
