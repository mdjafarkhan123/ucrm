export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type Database = {
	// Allows to automatically instantiate createClient with right options
	// instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
	__InternalSupabase: {
		PostgrestVersion: '14.15';
	};
	public: {
		Tables: {
			access_audit_events: {
				Row: {
					actor_kind: string;
					actor_owner_email: string | null;
					actor_user_id: string | null;
					after_state: Json | null;
					before_state: Json | null;
					created_at: string;
					event_type: string;
					id: string;
					organization_id: string;
					target_key: string | null;
					target_type: string;
				};
				Insert: {
					actor_kind: string;
					actor_owner_email?: string | null;
					actor_user_id?: string | null;
					after_state?: Json | null;
					before_state?: Json | null;
					created_at?: string;
					event_type: string;
					id?: string;
					organization_id: string;
					target_key?: string | null;
					target_type: string;
				};
				Update: {
					actor_kind?: string;
					actor_owner_email?: string | null;
					actor_user_id?: string | null;
					after_state?: Json | null;
					before_state?: Json | null;
					created_at?: string;
					event_type?: string;
					id?: string;
					organization_id?: string;
					target_key?: string | null;
					target_type?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'access_audit_events_organization_id_fkey';
						columns: ['organization_id'];
						isOneToOne: false;
						referencedRelation: 'organizations';
						referencedColumns: ['id'];
					}
				];
			};
			contacts: {
				Row: {
					company_name: string | null;
					created_at: string;
					display_name: string;
					email: string | null;
					first_name: string | null;
					id: string;
					last_name: string | null;
					lifecycle_status: string;
					notes: string | null;
					organization_id: string;
					phone: string | null;
					source: string | null;
					updated_at: string;
				};
				Insert: {
					company_name?: string | null;
					created_at?: string;
					display_name: string;
					email?: string | null;
					first_name?: string | null;
					id?: string;
					last_name?: string | null;
					lifecycle_status?: string;
					notes?: string | null;
					organization_id: string;
					phone?: string | null;
					source?: string | null;
					updated_at?: string;
				};
				Update: {
					company_name?: string | null;
					created_at?: string;
					display_name?: string;
					email?: string | null;
					first_name?: string | null;
					id?: string;
					last_name?: string | null;
					lifecycle_status?: string;
					notes?: string | null;
					organization_id?: string;
					phone?: string | null;
					source?: string | null;
					updated_at?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'contacts_organization_id_fkey';
						columns: ['organization_id'];
						isOneToOne: false;
						referencedRelation: 'organizations';
						referencedColumns: ['id'];
					}
				];
			};
			features: {
				Row: {
					created_at: string;
					description: string;
					feature_key: string;
				};
				Insert: {
					created_at?: string;
					description: string;
					feature_key: string;
				};
				Update: {
					created_at?: string;
					description?: string;
					feature_key?: string;
				};
				Relationships: [];
			};
			organization_billing_accounts: {
				Row: {
					created_at: string;
					organization_id: string;
					paid_through_date: string | null;
					paid_through_source: string | null;
					updated_at: string;
				};
				Insert: {
					created_at?: string;
					organization_id: string;
					paid_through_date?: string | null;
					paid_through_source?: string | null;
					updated_at?: string;
				};
				Update: {
					created_at?: string;
					organization_id?: string;
					paid_through_date?: string | null;
					paid_through_source?: string | null;
					updated_at?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'organization_billing_accounts_organization_id_fkey';
						columns: ['organization_id'];
						isOneToOne: true;
						referencedRelation: 'organizations';
						referencedColumns: ['id'];
					}
				];
			};
			organization_closure_notices: {
				Row: {
					closure_record_id: string;
					created_at: string;
					id: string;
					notice_kind: string;
					outbox_delivery_id: string | null;
					sent_at: string;
				};
				Insert: {
					closure_record_id: string;
					created_at?: string;
					id?: string;
					notice_kind: string;
					outbox_delivery_id?: string | null;
					sent_at?: string;
				};
				Update: {
					closure_record_id?: string;
					created_at?: string;
					id?: string;
					notice_kind?: string;
					outbox_delivery_id?: string | null;
					sent_at?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'organization_closure_notices_closure_record_id_fkey';
						columns: ['closure_record_id'];
						isOneToOne: false;
						referencedRelation: 'organization_closure_records';
						referencedColumns: ['id'];
					},
					{
						foreignKeyName: 'organization_closure_notices_outbox_delivery_id_fkey';
						columns: ['outbox_delivery_id'];
						isOneToOne: false;
						referencedRelation: 'platform_outbox_deliveries';
						referencedColumns: ['id'];
					}
				];
			};
			organization_closure_records: {
				Row: {
					created_at: string;
					deadline_at: string;
					id: string;
					organization_id: string;
					prior_lifecycle_status: string;
					purge_operation_id: string | null;
					purge_started_at: string | null;
					reason: string;
					restoration_evidence_note: string | null;
					restored_at: string | null;
					restored_by_owner_email: string | null;
					started_at: string;
					started_by_owner_email: string;
					status: string;
				};
				Insert: {
					created_at?: string;
					deadline_at: string;
					id?: string;
					organization_id: string;
					prior_lifecycle_status: string;
					purge_operation_id?: string | null;
					purge_started_at?: string | null;
					reason: string;
					restoration_evidence_note?: string | null;
					restored_at?: string | null;
					restored_by_owner_email?: string | null;
					started_at?: string;
					started_by_owner_email: string;
					status?: string;
				};
				Update: {
					created_at?: string;
					deadline_at?: string;
					id?: string;
					organization_id?: string;
					prior_lifecycle_status?: string;
					purge_operation_id?: string | null;
					purge_started_at?: string | null;
					reason?: string;
					restoration_evidence_note?: string | null;
					restored_at?: string | null;
					restored_by_owner_email?: string | null;
					started_at?: string;
					started_by_owner_email?: string;
					status?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'organization_closure_records_organization_id_fkey';
						columns: ['organization_id'];
						isOneToOne: false;
						referencedRelation: 'organizations';
						referencedColumns: ['id'];
					},
					{
						foreignKeyName: 'organization_closure_records_purge_operation_id_fkey';
						columns: ['purge_operation_id'];
						isOneToOne: false;
						referencedRelation: 'organization_deletion_receipts';
						referencedColumns: ['operation_id'];
					}
				];
			};
			organization_commercial_events: {
				Row: {
					actor_kind: string;
					actor_owner_email: string | null;
					amount_usd_cents: number | null;
					change_after: Json | null;
					change_before: Json | null;
					commercial_timezone_after: string | null;
					commercial_timezone_before: string | null;
					created_at: string;
					deadline_recalculated: boolean;
					event_kind: string;
					grace_ends_at_after: string | null;
					id: string;
					idempotency_key: string;
					is_legacy_import: boolean;
					occurred_at: string;
					organization_id: string;
					original_confirmation_id: string | null;
					paid_through_after: string | null;
					paid_through_before: string | null;
					paid_through_effect: string;
					private_reason: string | null;
					private_reference: string | null;
					source_event_id: string | null;
					summary: string;
					suspension_category: string | null;
				};
				Insert: {
					actor_kind?: string;
					actor_owner_email?: string | null;
					amount_usd_cents?: number | null;
					change_after?: Json | null;
					change_before?: Json | null;
					commercial_timezone_after?: string | null;
					commercial_timezone_before?: string | null;
					created_at?: string;
					deadline_recalculated?: boolean;
					event_kind: string;
					grace_ends_at_after?: string | null;
					id?: string;
					idempotency_key: string;
					is_legacy_import?: boolean;
					occurred_at?: string;
					organization_id: string;
					original_confirmation_id?: string | null;
					paid_through_after?: string | null;
					paid_through_before?: string | null;
					paid_through_effect: string;
					private_reason?: string | null;
					private_reference?: string | null;
					source_event_id?: string | null;
					summary: string;
					suspension_category?: string | null;
				};
				Update: {
					actor_kind?: string;
					actor_owner_email?: string | null;
					amount_usd_cents?: number | null;
					change_after?: Json | null;
					change_before?: Json | null;
					commercial_timezone_after?: string | null;
					commercial_timezone_before?: string | null;
					created_at?: string;
					deadline_recalculated?: boolean;
					event_kind?: string;
					grace_ends_at_after?: string | null;
					id?: string;
					idempotency_key?: string;
					is_legacy_import?: boolean;
					occurred_at?: string;
					organization_id?: string;
					original_confirmation_id?: string | null;
					paid_through_after?: string | null;
					paid_through_before?: string | null;
					paid_through_effect?: string;
					private_reason?: string | null;
					private_reference?: string | null;
					source_event_id?: string | null;
					summary?: string;
					suspension_category?: string | null;
				};
				Relationships: [
					{
						foreignKeyName: 'organization_commercial_events_organization_id_fkey';
						columns: ['organization_id'];
						isOneToOne: false;
						referencedRelation: 'organizations';
						referencedColumns: ['id'];
					},
					{
						foreignKeyName: 'organization_commercial_events_original_confirmation_id_fkey';
						columns: ['original_confirmation_id'];
						isOneToOne: false;
						referencedRelation: 'organization_commercial_events';
						referencedColumns: ['id'];
					},
					{
						foreignKeyName: 'organization_commercial_events_source_event_id_fkey';
						columns: ['source_event_id'];
						isOneToOne: false;
						referencedRelation: 'organization_commercial_events';
						referencedColumns: ['id'];
					}
				];
			};
			organization_commercial_settings: {
				Row: {
					commercial_timezone: string;
					created_at: string;
					imported_at: string | null;
					imported_operational_timezone: string | null;
					organization_id: string;
					timezone_source: string;
					updated_at: string;
				};
				Insert: {
					commercial_timezone: string;
					created_at?: string;
					imported_at?: string | null;
					imported_operational_timezone?: string | null;
					organization_id: string;
					timezone_source?: string;
					updated_at?: string;
				};
				Update: {
					commercial_timezone?: string;
					created_at?: string;
					imported_at?: string | null;
					imported_operational_timezone?: string | null;
					organization_id?: string;
					timezone_source?: string;
					updated_at?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'organization_commercial_settings_organization_id_fkey';
						columns: ['organization_id'];
						isOneToOne: true;
						referencedRelation: 'organizations';
						referencedColumns: ['id'];
					}
				];
			};
			organization_commercial_state: {
				Row: {
					created_at: string;
					grace_basis_timezone: string | null;
					grace_ends_at: string | null;
					last_event_id: string | null;
					organization_id: string;
					paid_through_date: string | null;
					paid_through_source: string | null;
					state_version: number;
					updated_at: string;
				};
				Insert: {
					created_at?: string;
					grace_basis_timezone?: string | null;
					grace_ends_at?: string | null;
					last_event_id?: string | null;
					organization_id: string;
					paid_through_date?: string | null;
					paid_through_source?: string | null;
					state_version?: number;
					updated_at?: string;
				};
				Update: {
					created_at?: string;
					grace_basis_timezone?: string | null;
					grace_ends_at?: string | null;
					last_event_id?: string | null;
					organization_id?: string;
					paid_through_date?: string | null;
					paid_through_source?: string | null;
					state_version?: number;
					updated_at?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'organization_commercial_state_last_event_id_fkey';
						columns: ['last_event_id'];
						isOneToOne: false;
						referencedRelation: 'organization_commercial_events';
						referencedColumns: ['id'];
					},
					{
						foreignKeyName: 'organization_commercial_state_organization_id_fkey';
						columns: ['organization_id'];
						isOneToOne: true;
						referencedRelation: 'organizations';
						referencedColumns: ['id'];
					}
				];
			};
			organization_deletion_receipts: {
				Row: {
					completed_at: string | null;
					component_results: Json;
					created_at: string;
					initiated_at: string;
					operation_id: string;
					pending_auth_user_ids: string[] | null;
					retry_count: number;
					status: string;
					trigger_kind: string;
				};
				Insert: {
					completed_at?: string | null;
					component_results?: Json;
					created_at?: string;
					initiated_at?: string;
					operation_id?: string;
					pending_auth_user_ids?: string[] | null;
					retry_count?: number;
					status?: string;
					trigger_kind: string;
				};
				Update: {
					completed_at?: string | null;
					component_results?: Json;
					created_at?: string;
					initiated_at?: string;
					operation_id?: string;
					pending_auth_user_ids?: string[] | null;
					retry_count?: number;
					status?: string;
					trigger_kind?: string;
				};
				Relationships: [];
			};
			organization_feature_overrides: {
				Row: {
					actor_owner_email: string | null;
					created_at: string;
					expires_at: string | null;
					feature_key: string;
					is_legacy_import: boolean;
					organization_id: string;
					override_state: string;
					reason: string | null;
					starts_at: string;
					updated_at: string;
				};
				Insert: {
					actor_owner_email?: string | null;
					created_at?: string;
					expires_at?: string | null;
					feature_key: string;
					is_legacy_import?: boolean;
					organization_id: string;
					override_state: string;
					reason?: string | null;
					starts_at?: string;
					updated_at?: string;
				};
				Update: {
					actor_owner_email?: string | null;
					created_at?: string;
					expires_at?: string | null;
					feature_key?: string;
					is_legacy_import?: boolean;
					organization_id?: string;
					override_state?: string;
					reason?: string | null;
					starts_at?: string;
					updated_at?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'organization_feature_overrides_feature_key_fkey';
						columns: ['feature_key'];
						isOneToOne: false;
						referencedRelation: 'features';
						referencedColumns: ['feature_key'];
					},
					{
						foreignKeyName: 'organization_feature_overrides_organization_id_fkey';
						columns: ['organization_id'];
						isOneToOne: false;
						referencedRelation: 'organizations';
						referencedColumns: ['id'];
					}
				];
			};
			organization_free_access_events: {
				Row: {
					access_until_date: string | null;
					action: string;
					actor_kind: string;
					actor_owner_email: string | null;
					created_at: string;
					id: string;
					occurred_at: string;
					organization_id: string;
					package_version_id: string;
					reason: string;
					starts_at: string;
					target_grant_id: string | null;
				};
				Insert: {
					access_until_date?: string | null;
					action: string;
					actor_kind?: string;
					actor_owner_email?: string | null;
					created_at?: string;
					id?: string;
					occurred_at?: string;
					organization_id: string;
					package_version_id: string;
					reason: string;
					starts_at: string;
					target_grant_id?: string | null;
				};
				Update: {
					access_until_date?: string | null;
					action?: string;
					actor_kind?: string;
					actor_owner_email?: string | null;
					created_at?: string;
					id?: string;
					occurred_at?: string;
					organization_id?: string;
					package_version_id?: string;
					reason?: string;
					starts_at?: string;
					target_grant_id?: string | null;
				};
				Relationships: [
					{
						foreignKeyName: 'organization_free_access_events_organization_id_fkey';
						columns: ['organization_id'];
						isOneToOne: false;
						referencedRelation: 'organizations';
						referencedColumns: ['id'];
					},
					{
						foreignKeyName: 'organization_free_access_events_package_version_id_fkey';
						columns: ['package_version_id'];
						isOneToOne: false;
						referencedRelation: 'platform_package_versions';
						referencedColumns: ['id'];
					},
					{
						foreignKeyName: 'organization_free_access_events_target_grant_id_fkey';
						columns: ['target_grant_id'];
						isOneToOne: false;
						referencedRelation: 'organization_free_access_events';
						referencedColumns: ['id'];
					}
				];
			};
			organization_limit_overrides: {
				Row: {
					actor_owner_email: string | null;
					created_at: string;
					expires_at: string | null;
					is_legacy_import: boolean;
					is_unlimited: boolean;
					limit_key: string;
					limit_state: string;
					limit_value: number | null;
					organization_id: string;
					reason: string | null;
					starts_at: string;
					updated_at: string;
				};
				Insert: {
					actor_owner_email?: string | null;
					created_at?: string;
					expires_at?: string | null;
					is_legacy_import?: boolean;
					is_unlimited?: boolean;
					limit_key: string;
					limit_state?: string;
					limit_value?: number | null;
					organization_id: string;
					reason?: string | null;
					starts_at?: string;
					updated_at?: string;
				};
				Update: {
					actor_owner_email?: string | null;
					created_at?: string;
					expires_at?: string | null;
					is_legacy_import?: boolean;
					is_unlimited?: boolean;
					limit_key?: string;
					limit_state?: string;
					limit_value?: number | null;
					organization_id?: string;
					reason?: string | null;
					starts_at?: string;
					updated_at?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'organization_limit_overrides_organization_id_fkey';
						columns: ['organization_id'];
						isOneToOne: false;
						referencedRelation: 'organizations';
						referencedColumns: ['id'];
					}
				];
			};
			organization_member_permission_overrides: {
				Row: {
					created_at: string;
					organization_id: string;
					override_state: string;
					permission_key: string;
					updated_at: string;
					user_id: string;
				};
				Insert: {
					created_at?: string;
					organization_id: string;
					override_state: string;
					permission_key: string;
					updated_at?: string;
					user_id: string;
				};
				Update: {
					created_at?: string;
					organization_id?: string;
					override_state?: string;
					permission_key?: string;
					updated_at?: string;
					user_id?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'organization_member_permission_overrides_member_fk';
						columns: ['organization_id', 'user_id'];
						isOneToOne: false;
						referencedRelation: 'organization_members';
						referencedColumns: ['organization_id', 'user_id'];
					},
					{
						foreignKeyName: 'organization_member_permission_overrides_permission_key_fkey';
						columns: ['permission_key'];
						isOneToOne: false;
						referencedRelation: 'permissions';
						referencedColumns: ['key'];
					}
				];
			};
			organization_members: {
				Row: {
					created_at: string;
					organization_id: string;
					role: string;
					user_id: string;
				};
				Insert: {
					created_at?: string;
					organization_id: string;
					role?: string;
					user_id: string;
				};
				Update: {
					created_at?: string;
					organization_id?: string;
					role?: string;
					user_id?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'organization_members_organization_id_fkey';
						columns: ['organization_id'];
						isOneToOne: false;
						referencedRelation: 'organizations';
						referencedColumns: ['id'];
					}
				];
			};
			organization_package_assignments: {
				Row: {
					assignment_source: string;
					created_at: string;
					effective_at: string;
					id: string;
					organization_id: string;
					package_version_id: string;
					reason: string;
				};
				Insert: {
					assignment_source: string;
					created_at?: string;
					effective_at?: string;
					id?: string;
					organization_id: string;
					package_version_id: string;
					reason: string;
				};
				Update: {
					assignment_source?: string;
					created_at?: string;
					effective_at?: string;
					id?: string;
					organization_id?: string;
					package_version_id?: string;
					reason?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'organization_package_assignments_organization_id_fkey';
						columns: ['organization_id'];
						isOneToOne: false;
						referencedRelation: 'organizations';
						referencedColumns: ['id'];
					},
					{
						foreignKeyName: 'organization_package_assignments_package_version_id_fkey';
						columns: ['package_version_id'];
						isOneToOne: false;
						referencedRelation: 'platform_package_versions';
						referencedColumns: ['id'];
					}
				];
			};
			organization_payment_confirmations: {
				Row: {
					amount_usd_cents: number;
					confirmed_at: string;
					created_at: string;
					currency: string;
					id: string;
					mismatch_reason: string | null;
					organization_id: string;
					paid_through_date: string;
					payment_kind: string;
					private_reference: string;
				};
				Insert: {
					amount_usd_cents: number;
					confirmed_at?: string;
					created_at?: string;
					currency?: string;
					id?: string;
					mismatch_reason?: string | null;
					organization_id: string;
					paid_through_date: string;
					payment_kind: string;
					private_reference: string;
				};
				Update: {
					amount_usd_cents?: number;
					confirmed_at?: string;
					created_at?: string;
					currency?: string;
					id?: string;
					mismatch_reason?: string | null;
					organization_id?: string;
					paid_through_date?: string;
					payment_kind?: string;
					private_reference?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'organization_payment_confirmations_organization_id_fkey';
						columns: ['organization_id'];
						isOneToOne: false;
						referencedRelation: 'organizations';
						referencedColumns: ['id'];
					}
				];
			};
			organization_safe_events: {
				Row: {
					commercial_event_id: string;
					created_at: string;
					id: string;
					occurred_at: string;
					organization_id: string;
					safe_kind: string;
					safe_payload: Json;
				};
				Insert: {
					commercial_event_id: string;
					created_at?: string;
					id?: string;
					occurred_at?: string;
					organization_id: string;
					safe_kind: string;
					safe_payload?: Json;
				};
				Update: {
					commercial_event_id?: string;
					created_at?: string;
					id?: string;
					occurred_at?: string;
					organization_id?: string;
					safe_kind?: string;
					safe_payload?: Json;
				};
				Relationships: [
					{
						foreignKeyName: 'organization_safe_events_commercial_event_id_fkey';
						columns: ['commercial_event_id'];
						isOneToOne: true;
						referencedRelation: 'organization_commercial_events';
						referencedColumns: ['id'];
					},
					{
						foreignKeyName: 'organization_safe_events_organization_id_fkey';
						columns: ['organization_id'];
						isOneToOne: false;
						referencedRelation: 'organizations';
						referencedColumns: ['id'];
					}
				];
			};
			organization_settings: {
				Row: {
					created_at: string;
					currency_code: string;
					locale: string;
					organization_id: string;
					timezone: string;
					updated_at: string;
				};
				Insert: {
					created_at?: string;
					currency_code?: string;
					locale?: string;
					organization_id: string;
					timezone?: string;
					updated_at?: string;
				};
				Update: {
					created_at?: string;
					currency_code?: string;
					locale?: string;
					organization_id?: string;
					timezone?: string;
					updated_at?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'organization_settings_organization_id_fkey';
						columns: ['organization_id'];
						isOneToOne: true;
						referencedRelation: 'organizations';
						referencedColumns: ['id'];
					}
				];
			};
			organizations: {
				Row: {
					created_at: string;
					id: string;
					lifecycle_status: string;
					name: string;
					package_key: string;
					scheduled_package_effective_at: string | null;
					scheduled_package_key: string | null;
					slug: string;
					updated_at: string;
				};
				Insert: {
					created_at?: string;
					id?: string;
					lifecycle_status?: string;
					name: string;
					package_key?: string;
					scheduled_package_effective_at?: string | null;
					scheduled_package_key?: string | null;
					slug: string;
					updated_at?: string;
				};
				Update: {
					created_at?: string;
					id?: string;
					lifecycle_status?: string;
					name?: string;
					package_key?: string;
					scheduled_package_effective_at?: string | null;
					scheduled_package_key?: string | null;
					slug?: string;
					updated_at?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'organizations_package_key_fkey';
						columns: ['package_key'];
						isOneToOne: false;
						referencedRelation: 'platform_packages';
						referencedColumns: ['package_key'];
					},
					{
						foreignKeyName: 'organizations_scheduled_package_key_fkey';
						columns: ['scheduled_package_key'];
						isOneToOne: false;
						referencedRelation: 'platform_packages';
						referencedColumns: ['package_key'];
					}
				];
			};
			package_features: {
				Row: {
					created_at: string;
					feature_key: string;
					package_key: string;
				};
				Insert: {
					created_at?: string;
					feature_key: string;
					package_key: string;
				};
				Update: {
					created_at?: string;
					feature_key?: string;
					package_key?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'package_features_feature_key_fkey';
						columns: ['feature_key'];
						isOneToOne: false;
						referencedRelation: 'features';
						referencedColumns: ['feature_key'];
					},
					{
						foreignKeyName: 'package_features_package_key_fkey';
						columns: ['package_key'];
						isOneToOne: false;
						referencedRelation: 'platform_packages';
						referencedColumns: ['package_key'];
					}
				];
			};
			package_limits: {
				Row: {
					created_at: string;
					is_unlimited: boolean;
					limit_key: string;
					limit_value: number | null;
					package_key: string;
				};
				Insert: {
					created_at?: string;
					is_unlimited?: boolean;
					limit_key: string;
					limit_value?: number | null;
					package_key: string;
				};
				Update: {
					created_at?: string;
					is_unlimited?: boolean;
					limit_key?: string;
					limit_value?: number | null;
					package_key?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'package_limits_package_key_fkey';
						columns: ['package_key'];
						isOneToOne: false;
						referencedRelation: 'platform_packages';
						referencedColumns: ['package_key'];
					}
				];
			};
			permissions: {
				Row: {
					created_at: string;
					description: string;
					key: string;
				};
				Insert: {
					created_at?: string;
					description: string;
					key: string;
				};
				Update: {
					created_at?: string;
					description?: string;
					key?: string;
				};
				Relationships: [];
			};
			platform_message_template_versions: {
				Row: {
					body: string;
					id: string;
					published_at: string;
					published_by_owner_email: string;
					subject: string | null;
					template_key: string;
					version: number;
				};
				Insert: {
					body: string;
					id?: string;
					published_at?: string;
					published_by_owner_email: string;
					subject?: string | null;
					template_key: string;
					version: number;
				};
				Update: {
					body?: string;
					id?: string;
					published_at?: string;
					published_by_owner_email?: string;
					subject?: string | null;
					template_key?: string;
					version?: number;
				};
				Relationships: [
					{
						foreignKeyName: 'platform_message_template_versions_template_key_fkey';
						columns: ['template_key'];
						isOneToOne: false;
						referencedRelation: 'platform_message_templates';
						referencedColumns: ['template_key'];
					}
				];
			};
			platform_message_templates: {
				Row: {
					body_draft: string;
					body_published: string | null;
					created_at: string;
					published_at: string | null;
					published_by_owner_email: string | null;
					published_version: number;
					subject_draft: string | null;
					subject_published: string | null;
					template_key: string;
					updated_at: string;
				};
				Insert: {
					body_draft?: string;
					body_published?: string | null;
					created_at?: string;
					published_at?: string | null;
					published_by_owner_email?: string | null;
					published_version?: number;
					subject_draft?: string | null;
					subject_published?: string | null;
					template_key: string;
					updated_at?: string;
				};
				Update: {
					body_draft?: string;
					body_published?: string | null;
					created_at?: string;
					published_at?: string | null;
					published_by_owner_email?: string | null;
					published_version?: number;
					subject_draft?: string | null;
					subject_published?: string | null;
					template_key?: string;
					updated_at?: string;
				};
				Relationships: [];
			};
			platform_onboarding_application_corrections: {
				Row: {
					actor_owner_email: string;
					after_state: Json;
					application_id: string;
					before_state: Json;
					created_at: string;
					id: string;
					reason: string;
				};
				Insert: {
					actor_owner_email: string;
					after_state: Json;
					application_id: string;
					before_state: Json;
					created_at?: string;
					id?: string;
					reason: string;
				};
				Update: {
					actor_owner_email?: string;
					after_state?: Json;
					application_id?: string;
					before_state?: Json;
					created_at?: string;
					id?: string;
					reason?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'platform_onboarding_application_corrections_application_id_fkey';
						columns: ['application_id'];
						isOneToOne: false;
						referencedRelation: 'platform_onboarding_applications';
						referencedColumns: ['id'];
					}
				];
			};
			platform_onboarding_application_payment_confirmations: {
				Row: {
					actor_owner_email: string;
					amount_usd_cents: number;
					application_id: string;
					confirmed_at: string;
					created_at: string;
					currency: string;
					id: string;
					mismatch_reason: string | null;
					package_version_id: string;
					private_reference: string;
				};
				Insert: {
					actor_owner_email: string;
					amount_usd_cents: number;
					application_id: string;
					confirmed_at?: string;
					created_at?: string;
					currency?: string;
					id?: string;
					mismatch_reason?: string | null;
					package_version_id: string;
					private_reference: string;
				};
				Update: {
					actor_owner_email?: string;
					amount_usd_cents?: number;
					application_id?: string;
					confirmed_at?: string;
					created_at?: string;
					currency?: string;
					id?: string;
					mismatch_reason?: string | null;
					package_version_id?: string;
					private_reference?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'platform_onboarding_application_payment_con_application_id_fkey';
						columns: ['application_id'];
						isOneToOne: false;
						referencedRelation: 'platform_onboarding_applications';
						referencedColumns: ['id'];
					},
					{
						foreignKeyName: 'platform_onboarding_application_payment_package_version_id_fkey';
						columns: ['package_version_id'];
						isOneToOne: false;
						referencedRelation: 'platform_package_versions';
						referencedColumns: ['id'];
					}
				];
			};
			platform_onboarding_application_payment_reversals: {
				Row: {
					actor_owner_email: string;
					application_id: string;
					confirmation_id: string;
					created_at: string;
					id: string;
					reason: string;
					reversed_amount_usd_cents: number;
					reversed_at: string;
				};
				Insert: {
					actor_owner_email: string;
					application_id: string;
					confirmation_id: string;
					created_at?: string;
					id?: string;
					reason: string;
					reversed_amount_usd_cents: number;
					reversed_at?: string;
				};
				Update: {
					actor_owner_email?: string;
					application_id?: string;
					confirmation_id?: string;
					created_at?: string;
					id?: string;
					reason?: string;
					reversed_amount_usd_cents?: number;
					reversed_at?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'platform_onboarding_application_payment_re_confirmation_id_fkey';
						columns: ['confirmation_id'];
						isOneToOne: false;
						referencedRelation: 'platform_onboarding_application_payment_confirmations';
						referencedColumns: ['id'];
					},
					{
						foreignKeyName: 'platform_onboarding_application_payment_rev_application_id_fkey';
						columns: ['application_id'];
						isOneToOne: false;
						referencedRelation: 'platform_onboarding_applications';
						referencedColumns: ['id'];
					}
				];
			};
			platform_onboarding_application_provisions: {
				Row: {
					administrator_user_id: string | null;
					application_id: string;
					attempt_count: number;
					created_at: string;
					last_error: string | null;
					organization_id: string | null;
					status: string;
					updated_at: string;
				};
				Insert: {
					administrator_user_id?: string | null;
					application_id: string;
					attempt_count?: number;
					created_at?: string;
					last_error?: string | null;
					organization_id?: string | null;
					status?: string;
					updated_at?: string;
				};
				Update: {
					administrator_user_id?: string | null;
					application_id?: string;
					attempt_count?: number;
					created_at?: string;
					last_error?: string | null;
					organization_id?: string | null;
					status?: string;
					updated_at?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'platform_onboarding_application_provisions_application_id_fkey';
						columns: ['application_id'];
						isOneToOne: true;
						referencedRelation: 'platform_onboarding_applications';
						referencedColumns: ['id'];
					},
					{
						foreignKeyName: 'platform_onboarding_application_provisions_organization_id_fkey';
						columns: ['organization_id'];
						isOneToOne: false;
						referencedRelation: 'organizations';
						referencedColumns: ['id'];
					}
				];
			};
			platform_onboarding_application_setup_links: {
				Row: {
					administrator_user_id: string;
					application_id: string;
					consumed_at: string | null;
					created_at: string;
					expires_at: string;
					intended_email: string;
					last_error: string | null;
					last_sent_at: string;
					rendered_body: string | null;
					rendered_subject: string | null;
					token_hash: string;
					updated_at: string;
				};
				Insert: {
					administrator_user_id: string;
					application_id: string;
					consumed_at?: string | null;
					created_at?: string;
					expires_at: string;
					intended_email: string;
					last_error?: string | null;
					last_sent_at?: string;
					rendered_body?: string | null;
					rendered_subject?: string | null;
					token_hash: string;
					updated_at?: string;
				};
				Update: {
					administrator_user_id?: string;
					application_id?: string;
					consumed_at?: string | null;
					created_at?: string;
					expires_at?: string;
					intended_email?: string;
					last_error?: string | null;
					last_sent_at?: string;
					rendered_body?: string | null;
					rendered_subject?: string | null;
					token_hash?: string;
					updated_at?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'platform_onboarding_application_setup_links_application_id_fkey';
						columns: ['application_id'];
						isOneToOne: true;
						referencedRelation: 'platform_onboarding_applications';
						referencedColumns: ['id'];
					}
				];
			};
			platform_onboarding_application_submissions: {
				Row: {
					agreement_accepted_at: string;
					application_id: string;
					id: string;
					package_snapshot: Json;
					privacy_policy_version: string;
					submitted_at: string;
					submitted_data: Json;
				};
				Insert: {
					agreement_accepted_at: string;
					application_id: string;
					id?: string;
					package_snapshot: Json;
					privacy_policy_version: string;
					submitted_at?: string;
					submitted_data: Json;
				};
				Update: {
					agreement_accepted_at?: string;
					application_id?: string;
					id?: string;
					package_snapshot?: Json;
					privacy_policy_version?: string;
					submitted_at?: string;
					submitted_data?: Json;
				};
				Relationships: [
					{
						foreignKeyName: 'platform_onboarding_application_submissions_application_id_fkey';
						columns: ['application_id'];
						isOneToOne: true;
						referencedRelation: 'platform_onboarding_applications';
						referencedColumns: ['id'];
					}
				];
			};
			platform_onboarding_applications: {
				Row: {
					business_name: string;
					city_country: string;
					duplicate_acknowledged_at: string | null;
					duplicate_acknowledged_by_owner_email: string | null;
					id: string;
					initial_administrator_email: string | null;
					initial_administrator_name: string | null;
					main_contact_email: string;
					main_contact_name: string;
					main_contact_phone: string;
					not_proceeding_at: string | null;
					note: string | null;
					package_snapshot: Json;
					package_version_id: string;
					payment_reversed_at: string | null;
					personal_data_purge_after: string;
					possible_duplicate: boolean;
					stage: string;
					submitted_at: string;
					time_zone: string;
					trade: string;
					updated_at: string;
				};
				Insert: {
					business_name: string;
					city_country: string;
					duplicate_acknowledged_at?: string | null;
					duplicate_acknowledged_by_owner_email?: string | null;
					id?: string;
					initial_administrator_email?: string | null;
					initial_administrator_name?: string | null;
					main_contact_email: string;
					main_contact_name: string;
					main_contact_phone: string;
					not_proceeding_at?: string | null;
					note?: string | null;
					package_snapshot: Json;
					package_version_id: string;
					payment_reversed_at?: string | null;
					personal_data_purge_after?: string;
					possible_duplicate?: boolean;
					stage?: string;
					submitted_at?: string;
					time_zone: string;
					trade: string;
					updated_at?: string;
				};
				Update: {
					business_name?: string;
					city_country?: string;
					duplicate_acknowledged_at?: string | null;
					duplicate_acknowledged_by_owner_email?: string | null;
					id?: string;
					initial_administrator_email?: string | null;
					initial_administrator_name?: string | null;
					main_contact_email?: string;
					main_contact_name?: string;
					main_contact_phone?: string;
					not_proceeding_at?: string | null;
					note?: string | null;
					package_snapshot?: Json;
					package_version_id?: string;
					payment_reversed_at?: string | null;
					personal_data_purge_after?: string;
					possible_duplicate?: boolean;
					stage?: string;
					submitted_at?: string;
					time_zone?: string;
					trade?: string;
					updated_at?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'platform_onboarding_applications_package_version_id_fkey';
						columns: ['package_version_id'];
						isOneToOne: false;
						referencedRelation: 'platform_package_versions';
						referencedColumns: ['id'];
					}
				];
			};
			platform_operation_attempts: {
				Row: {
					acknowledged_at: string | null;
					acknowledged_by_owner_email: string | null;
					attempt_count: number;
					correlation_id: string;
					created_at: string;
					id: string;
					idempotency_key: string;
					last_error: string | null;
					next_retry_at: string | null;
					operation_type: string;
					resolution_note: string | null;
					resolved_at: string | null;
					resolved_by_owner_email: string | null;
					status: string;
					target_id: string | null;
					target_kind: string;
					updated_at: string;
				};
				Insert: {
					acknowledged_at?: string | null;
					acknowledged_by_owner_email?: string | null;
					attempt_count?: number;
					correlation_id?: string;
					created_at?: string;
					id?: string;
					idempotency_key: string;
					last_error?: string | null;
					next_retry_at?: string | null;
					operation_type: string;
					resolution_note?: string | null;
					resolved_at?: string | null;
					resolved_by_owner_email?: string | null;
					status?: string;
					target_id?: string | null;
					target_kind: string;
					updated_at?: string;
				};
				Update: {
					acknowledged_at?: string | null;
					acknowledged_by_owner_email?: string | null;
					attempt_count?: number;
					correlation_id?: string;
					created_at?: string;
					id?: string;
					idempotency_key?: string;
					last_error?: string | null;
					next_retry_at?: string | null;
					operation_type?: string;
					resolution_note?: string | null;
					resolved_at?: string | null;
					resolved_by_owner_email?: string | null;
					status?: string;
					target_id?: string | null;
					target_kind?: string;
					updated_at?: string;
				};
				Relationships: [];
			};
			platform_outbox_deliveries: {
				Row: {
					attempt_count: number;
					channel: string;
					correlation_id: string;
					created_at: string;
					id: string;
					idempotency_key: string;
					last_error: string | null;
					next_attempt_at: string;
					payload: Json;
					recipient_email: string;
					sent_at: string | null;
					status: string;
					target_id: string | null;
					target_kind: string;
					template_key: string;
					updated_at: string;
				};
				Insert: {
					attempt_count?: number;
					channel?: string;
					correlation_id?: string;
					created_at?: string;
					id?: string;
					idempotency_key: string;
					last_error?: string | null;
					next_attempt_at?: string;
					payload?: Json;
					recipient_email: string;
					sent_at?: string | null;
					status?: string;
					target_id?: string | null;
					target_kind: string;
					template_key: string;
					updated_at?: string;
				};
				Update: {
					attempt_count?: number;
					channel?: string;
					correlation_id?: string;
					created_at?: string;
					id?: string;
					idempotency_key?: string;
					last_error?: string | null;
					next_attempt_at?: string;
					payload?: Json;
					recipient_email?: string;
					sent_at?: string | null;
					status?: string;
					target_id?: string | null;
					target_kind?: string;
					template_key?: string;
					updated_at?: string;
				};
				Relationships: [];
			};
			platform_owner_audit_events: {
				Row: {
					actor_owner_email: string;
					after_state: Json | null;
					before_state: Json | null;
					correlation_id: string;
					created_at: string;
					event_type: string;
					id: string;
					target_key: string | null;
					target_type: string;
				};
				Insert: {
					actor_owner_email: string;
					after_state?: Json | null;
					before_state?: Json | null;
					correlation_id?: string;
					created_at?: string;
					event_type: string;
					id?: string;
					target_key?: string | null;
					target_type: string;
				};
				Update: {
					actor_owner_email?: string;
					after_state?: Json | null;
					before_state?: Json | null;
					correlation_id?: string;
					created_at?: string;
					event_type?: string;
					id?: string;
					target_key?: string | null;
					target_type?: string;
				};
				Relationships: [];
			};
			platform_owner_login_attempts: {
				Row: {
					correlation_id: string;
					created_at: string;
					id: string;
					outcome: string;
				};
				Insert: {
					correlation_id?: string;
					created_at?: string;
					id?: string;
					outcome: string;
				};
				Update: {
					correlation_id?: string;
					created_at?: string;
					id?: string;
					outcome?: string;
				};
				Relationships: [];
			};
			platform_owner_notifications: {
				Row: {
					body: string | null;
					correlation_id: string | null;
					created_at: string;
					id: string;
					kind: string;
					read_at: string | null;
					severity: string;
					target_id: string | null;
					target_kind: string;
					title: string;
				};
				Insert: {
					body?: string | null;
					correlation_id?: string | null;
					created_at?: string;
					id?: string;
					kind: string;
					read_at?: string | null;
					severity?: string;
					target_id?: string | null;
					target_kind: string;
					title: string;
				};
				Update: {
					body?: string | null;
					correlation_id?: string | null;
					created_at?: string;
					id?: string;
					kind?: string;
					read_at?: string | null;
					severity?: string;
					target_id?: string | null;
					target_kind?: string;
					title?: string;
				};
				Relationships: [];
			};
			platform_owner_sessions: {
				Row: {
					correlation_id: string;
					created_at: string;
					expires_at: string;
					id: string;
					owner_email: string;
					revoked_at: string | null;
					revoked_reason: string | null;
				};
				Insert: {
					correlation_id?: string;
					created_at?: string;
					expires_at: string;
					id?: string;
					owner_email: string;
					revoked_at?: string | null;
					revoked_reason?: string | null;
				};
				Update: {
					correlation_id?: string;
					created_at?: string;
					expires_at?: string;
					id?: string;
					owner_email?: string;
					revoked_at?: string | null;
					revoked_reason?: string | null;
				};
				Relationships: [];
			};
			platform_owner_settings: {
				Row: {
					alert_recipient_emails: string[];
					created_at: string;
					id: boolean;
					payment_instructions: string;
					privacy_policy_url: string;
					privacy_policy_version: string;
					reply_to_address: string;
					sender_display_name: string;
					updated_at: string;
				};
				Insert: {
					alert_recipient_emails?: string[];
					created_at?: string;
					id?: boolean;
					payment_instructions?: string;
					privacy_policy_url?: string;
					privacy_policy_version?: string;
					reply_to_address?: string;
					sender_display_name?: string;
					updated_at?: string;
				};
				Update: {
					alert_recipient_emails?: string[];
					created_at?: string;
					id?: boolean;
					payment_instructions?: string;
					privacy_policy_url?: string;
					privacy_policy_version?: string;
					reply_to_address?: string;
					sender_display_name?: string;
					updated_at?: string;
				};
				Relationships: [];
			};
			platform_package_version_features: {
				Row: {
					created_at: string;
					feature_key: string;
					package_version_id: string;
				};
				Insert: {
					created_at?: string;
					feature_key: string;
					package_version_id: string;
				};
				Update: {
					created_at?: string;
					feature_key?: string;
					package_version_id?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'platform_package_version_features_feature_key_fkey';
						columns: ['feature_key'];
						isOneToOne: false;
						referencedRelation: 'features';
						referencedColumns: ['feature_key'];
					},
					{
						foreignKeyName: 'platform_package_version_features_package_version_id_fkey';
						columns: ['package_version_id'];
						isOneToOne: false;
						referencedRelation: 'platform_package_versions';
						referencedColumns: ['id'];
					}
				];
			};
			platform_package_version_limits: {
				Row: {
					created_at: string;
					limit_key: string;
					limit_state: string;
					limit_value: number | null;
					package_version_id: string;
				};
				Insert: {
					created_at?: string;
					limit_key: string;
					limit_state: string;
					limit_value?: number | null;
					package_version_id: string;
				};
				Update: {
					created_at?: string;
					limit_key?: string;
					limit_state?: string;
					limit_value?: number | null;
					package_version_id?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'platform_package_version_limits_package_version_id_fkey';
						columns: ['package_version_id'];
						isOneToOne: false;
						referencedRelation: 'platform_package_versions';
						referencedColumns: ['id'];
					}
				];
			};
			platform_package_versions: {
				Row: {
					billing_period: string;
					created_at: string;
					currency: string;
					display_name: string;
					id: string;
					package_id: string;
					price_usd_cents: number | null;
					public_description: string | null;
					published_at: string | null;
					retired_at: string | null;
					status: string;
					value_explanation: string | null;
					version_number: number;
				};
				Insert: {
					billing_period?: string;
					created_at?: string;
					currency?: string;
					display_name: string;
					id?: string;
					package_id: string;
					price_usd_cents?: number | null;
					public_description?: string | null;
					published_at?: string | null;
					retired_at?: string | null;
					status?: string;
					value_explanation?: string | null;
					version_number: number;
				};
				Update: {
					billing_period?: string;
					created_at?: string;
					currency?: string;
					display_name?: string;
					id?: string;
					package_id?: string;
					price_usd_cents?: number | null;
					public_description?: string | null;
					published_at?: string | null;
					retired_at?: string | null;
					status?: string;
					value_explanation?: string | null;
					version_number?: number;
				};
				Relationships: [
					{
						foreignKeyName: 'platform_package_versions_package_id_fkey';
						columns: ['package_id'];
						isOneToOne: false;
						referencedRelation: 'platform_packages';
						referencedColumns: ['package_id'];
					}
				];
			};
			platform_packages: {
				Row: {
					billing_period: string;
					created_at: string;
					currency: string;
					display_name: string;
					package_id: string;
					package_key: string;
					price_usd_cents: number | null;
					public_description: string | null;
					sort_order: number;
					status: string;
				};
				Insert: {
					billing_period?: string;
					created_at?: string;
					currency?: string;
					display_name: string;
					package_id?: string;
					package_key: string;
					price_usd_cents?: number | null;
					public_description?: string | null;
					sort_order: number;
					status?: string;
				};
				Update: {
					billing_period?: string;
					created_at?: string;
					currency?: string;
					display_name?: string;
					package_id?: string;
					package_key?: string;
					price_usd_cents?: number | null;
					public_description?: string | null;
					sort_order?: number;
					status?: string;
				};
				Relationships: [];
			};
			platform_rate_limit_buckets: {
				Row: {
					attempt_count: number;
					bucket_key: string;
					window_start: string;
				};
				Insert: {
					attempt_count?: number;
					bucket_key: string;
					window_start: string;
				};
				Update: {
					attempt_count?: number;
					bucket_key?: string;
					window_start?: string;
				};
				Relationships: [];
			};
			profiles: {
				Row: {
					avatar_url: string | null;
					created_at: string;
					full_name: string | null;
					id: string;
					updated_at: string;
				};
				Insert: {
					avatar_url?: string | null;
					created_at?: string;
					full_name?: string | null;
					id: string;
					updated_at?: string;
				};
				Update: {
					avatar_url?: string | null;
					created_at?: string;
					full_name?: string | null;
					id?: string;
					updated_at?: string;
				};
				Relationships: [];
			};
			properties: {
				Row: {
					access_notes: string | null;
					address_line1: string;
					address_line2: string | null;
					city: string;
					contact_id: string;
					country: string;
					created_at: string;
					id: string;
					label: string;
					organization_id: string;
					postal_code: string | null;
					state_region: string | null;
					updated_at: string;
				};
				Insert: {
					access_notes?: string | null;
					address_line1: string;
					address_line2?: string | null;
					city: string;
					contact_id: string;
					country?: string;
					created_at?: string;
					id?: string;
					label?: string;
					organization_id: string;
					postal_code?: string | null;
					state_region?: string | null;
					updated_at?: string;
				};
				Update: {
					access_notes?: string | null;
					address_line1?: string;
					address_line2?: string | null;
					city?: string;
					contact_id?: string;
					country?: string;
					created_at?: string;
					id?: string;
					label?: string;
					organization_id?: string;
					postal_code?: string | null;
					state_region?: string | null;
					updated_at?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'properties_contact_id_fkey';
						columns: ['contact_id'];
						isOneToOne: false;
						referencedRelation: 'contacts';
						referencedColumns: ['id'];
					},
					{
						foreignKeyName: 'properties_contact_organization_fk';
						columns: ['organization_id', 'contact_id'];
						isOneToOne: false;
						referencedRelation: 'contacts';
						referencedColumns: ['organization_id', 'id'];
					},
					{
						foreignKeyName: 'properties_organization_id_fkey';
						columns: ['organization_id'];
						isOneToOne: false;
						referencedRelation: 'organizations';
						referencedColumns: ['id'];
					}
				];
			};
			requests: {
				Row: {
					contact_id: string;
					created_at: string;
					description: string | null;
					id: string;
					organization_id: string;
					preferred_time: string | null;
					property_id: string;
					service_type: string | null;
					source: string;
					status: string;
					title: string;
					updated_at: string;
				};
				Insert: {
					contact_id: string;
					created_at?: string;
					description?: string | null;
					id?: string;
					organization_id: string;
					preferred_time?: string | null;
					property_id: string;
					service_type?: string | null;
					source?: string;
					status?: string;
					title: string;
					updated_at?: string;
				};
				Update: {
					contact_id?: string;
					created_at?: string;
					description?: string | null;
					id?: string;
					organization_id?: string;
					preferred_time?: string | null;
					property_id?: string;
					service_type?: string | null;
					source?: string;
					status?: string;
					title?: string;
					updated_at?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'requests_contact_organization_fk';
						columns: ['organization_id', 'contact_id'];
						isOneToOne: false;
						referencedRelation: 'contacts';
						referencedColumns: ['organization_id', 'id'];
					},
					{
						foreignKeyName: 'requests_organization_id_fkey';
						columns: ['organization_id'];
						isOneToOne: false;
						referencedRelation: 'organizations';
						referencedColumns: ['id'];
					},
					{
						foreignKeyName: 'requests_property_organization_fk';
						columns: ['organization_id', 'property_id'];
						isOneToOne: false;
						referencedRelation: 'properties';
						referencedColumns: ['organization_id', 'id'];
					}
				];
			};
			role_permissions: {
				Row: {
					created_at: string;
					permission_key: string;
					role: string;
				};
				Insert: {
					created_at?: string;
					permission_key: string;
					role: string;
				};
				Update: {
					created_at?: string;
					permission_key?: string;
					role?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'role_permissions_permission_key_fkey';
						columns: ['permission_key'];
						isOneToOne: false;
						referencedRelation: 'permissions';
						referencedColumns: ['key'];
					}
				];
			};
		};
		Views: {
			[_ in never]: never;
		};
		Functions: {
			acknowledge_onboarding_application_duplicate: {
				Args: { actor_email: string; target_application_id: string };
				Returns: undefined;
			};
			apply_organization_administrator_email_recovery: {
				Args: {
					actor_owner_email: string;
					evidence_summary: string;
					new_email: string;
					occurred_at?: string;
					old_email: string;
					private_reason: string;
					target_organization_id: string;
					target_user_id: string;
				};
				Returns: Json;
			};
			apply_organization_closure_restore: {
				Args: {
					actor_owner_email: string;
					idempotency_key: string;
					occurred_at?: string;
					restoration_evidence_note: string;
					target_organization_id: string;
				};
				Returns: Json;
			};
			apply_organization_closure_start: {
				Args: {
					actor_owner_email: string;
					idempotency_key: string;
					occurred_at?: string;
					private_reason: string;
					target_organization_id: string;
				};
				Returns: Json;
			};
			apply_organization_commercial_command: {
				Args: {
					actor_owner_email?: string;
					amount_usd_cents?: number;
					commercial_timezone?: string;
					event_kind: string;
					idempotency_key: string;
					is_legacy_import?: boolean;
					occurred_at?: string;
					original_confirmation_id?: string;
					paid_through_date?: string;
					paid_through_effect: string;
					private_reason?: string;
					private_reference?: string;
					recalculate_deadline?: boolean;
					safe_kind?: string;
					safe_payload?: Json;
					source_event_id?: string;
					summary: string;
					suspension_category?: string;
					target_organization_id: string;
				};
				Returns: Json;
			};
			apply_organization_feature_exception: {
				Args: {
					actor_owner_email: string;
					idempotency_key: string;
					occurred_at?: string;
					private_reason: string;
					target_expires_at: string;
					target_feature_key: string;
					target_organization_id: string;
					target_override_state: string;
					target_starts_at: string;
				};
				Returns: Json;
			};
			apply_organization_free_access_change: {
				Args: {
					actor_owner_email: string;
					idempotency_key: string;
					occurred_at?: string;
					private_reason: string;
					target_access_until_date: string;
					target_action: string;
					target_grant_id: string;
					target_organization_id: string;
					target_starts_at: string;
				};
				Returns: Json;
			};
			apply_organization_late_renewal_reactivation: {
				Args: {
					actor_owner_email?: string;
					amount_usd_cents?: number;
					idempotency_key: string;
					occurred_at?: string;
					original_confirmation_id?: string;
					paid_through_date?: string;
					paid_through_effect: string;
					private_reason?: string;
					private_reference?: string;
					reactivate?: boolean;
					safe_kind?: string;
					safe_payload?: Json;
					summary: string;
					target_organization_id: string;
				};
				Returns: Json;
			};
			apply_organization_lifecycle_change: {
				Args: {
					actor_owner_email: string;
					idempotency_key: string;
					occurred_at?: string;
					private_reason: string;
					target_organization_id: string;
					target_status: string;
					target_suspension_category: string;
				};
				Returns: Json;
			};
			apply_organization_limit_exception: {
				Args: {
					actor_owner_email: string;
					idempotency_key: string;
					occurred_at?: string;
					private_reason: string;
					target_expires_at: string;
					target_limit_key: string;
					target_limit_state: string;
					target_limit_value: number;
					target_organization_id: string;
					target_starts_at: string;
				};
				Returns: Json;
			};
			apply_organization_member_profile_correction: {
				Args: {
					actor_owner_email: string;
					email_changed: boolean;
					new_email: string;
					new_full_name: string;
					occurred_at?: string;
					old_email: string;
					private_reason: string;
					target_organization_id: string;
					target_user_id: string;
				};
				Returns: Json;
			};
			apply_organization_package_change: {
				Args: {
					actor_owner_email: string;
					idempotency_key: string;
					occurred_at?: string;
					private_reason: string;
					target_organization_id: string;
					target_package_version_id: string;
				};
				Returns: Json;
			};
			apply_organization_pending_setup_reconciliation: {
				Args: {
					actor_owner_email: string;
					idempotency_key: string;
					occurred_at?: string;
					private_reason: string;
					target_organization_id: string;
					target_status: string;
					target_suspension_category: string;
				};
				Returns: Json;
			};
			apply_organization_purge: {
				Args: {
					actor_owner_email?: string;
					purge_trigger_kind: string;
					target_organization_id: string;
				};
				Returns: Json;
			};
			check_rate_limit: {
				Args: {
					target_bucket_key: string;
					target_max_attempts: number;
					target_window_seconds: number;
				};
				Returns: {
					allowed: boolean;
					retry_after_seconds: number;
				}[];
			};
			claim_onboarding_application_provision: {
				Args: { stale_after?: string; target_application_id: string };
				Returns: {
					administrator_user_id: string;
					attempt_count: number;
					claim_status: string;
					organization_id: string;
				}[];
			};
			confirm_onboarding_application_payment: {
				Args: {
					actor_email: string;
					amount_usd_cents: number;
					mismatch_reason: string;
					private_reference: string;
					target_application_id: string;
				};
				Returns: undefined;
			};
			consume_onboarding_application_setup_link: {
				Args: { target_email: string; target_token_hash: string };
				Returns: {
					administrator_user_id: string;
					application_id: string;
					consumed: boolean;
				}[];
			};
			correct_onboarding_application: {
				Args: {
					actor_email: string;
					correction_reason: string;
					new_business_name: string;
					new_city_country: string;
					new_initial_administrator_email: string;
					new_initial_administrator_name: string;
					new_main_contact_email: string;
					new_main_contact_name: string;
					new_main_contact_phone: string;
					new_note: string;
					new_time_zone: string;
					new_trade: string;
					target_application_id: string;
				};
				Returns: undefined;
			};
			correct_onboarding_application_package: {
				Args: {
					actor_email: string;
					correction_reason: string;
					new_package_version_id: string;
					target_application_id: string;
				};
				Returns: undefined;
			};
			manage_platform_package_version: {
				Args: {
					actor_email?: string;
					operation: string;
					target_display_name?: string;
					target_feature_keys?: string[];
					target_limit_state?: string;
					target_limit_value?: number;
					target_package_key: string;
					target_price_usd_cents?: number;
					target_public_description?: string;
					target_value_explanation?: string;
					target_version_id?: string;
				};
				Returns: string;
			};
			mark_onboarding_application_not_proceeding: {
				Args: {
					actor_email: string;
					reason?: string;
					target_application_id: string;
				};
				Returns: undefined;
			};
			mark_onboarding_application_reviewed: {
				Args: { actor_email: string; target_application_id: string };
				Returns: undefined;
			};
			organization_legacy_readiness: {
				Args: { target_organization_id: string };
				Returns: Json;
			};
			owner_email_is_available: {
				Args: { candidate_email: string };
				Returns: boolean;
			};
			owner_organization_directory: {
				Args: {
					attention_reason?: string;
					cursor_created_at?: string;
					cursor_id?: string;
					page_size?: number;
					search_term?: string;
				};
				Returns: Json;
			};
			provision_organization_from_application: {
				Args: {
					target_actor_owner_email?: string;
					target_administrator_role?: string;
					target_administrator_user_id: string;
					target_application_id: string;
					target_organization_id: string;
					target_organization_name: string;
					target_slug: string;
				};
				Returns: string;
			};
			publish_message_template: {
				Args: { actor_email: string; target_template_key: string };
				Returns: {
					body_draft: string;
					body_published: string | null;
					created_at: string;
					published_at: string | null;
					published_by_owner_email: string | null;
					published_version: number;
					subject_draft: string | null;
					subject_published: string | null;
					template_key: string;
					updated_at: string;
				};
				SetofOptions: {
					from: '*';
					to: 'platform_message_templates';
					isOneToOne: true;
					isSetofReturn: false;
				};
			};
			record_legacy_organization_package: {
				Args: {
					target_organization_id: string;
					target_package_version_id: string;
					target_paid_through_date: string;
					target_reason: string;
				};
				Returns: undefined;
			};
			reverse_onboarding_application_payment: {
				Args: {
					actor_email: string;
					reason: string;
					target_application_id: string;
				};
				Returns: undefined;
			};
			submit_onboarding_application: {
				Args: {
					target_business_name: string;
					target_city_country: string;
					target_initial_administrator_email: string;
					target_initial_administrator_name: string;
					target_main_contact_email: string;
					target_main_contact_name: string;
					target_main_contact_phone: string;
					target_note: string;
					target_package_version_id: string;
					target_privacy_policy_version: string;
					target_submitted_data: Json;
					target_time_zone: string;
					target_trade: string;
				};
				Returns: string;
			};
			update_owner_settings: {
				Args: {
					actor_email: string;
					new_alert_recipient_emails: string[];
					new_payment_instructions: string;
					new_privacy_policy_url: string;
					new_privacy_policy_version: string;
					new_reply_to_address: string;
					new_sender_display_name: string;
				};
				Returns: {
					alert_recipient_emails: string[];
					created_at: string;
					id: boolean;
					payment_instructions: string;
					privacy_policy_url: string;
					privacy_policy_version: string;
					reply_to_address: string;
					sender_display_name: string;
					updated_at: string;
				};
				SetofOptions: {
					from: '*';
					to: 'platform_owner_settings';
					isOneToOne: true;
					isSetofReturn: false;
				};
			};
		};
		Enums: {
			[_ in never]: never;
		};
		CompositeTypes: {
			[_ in never]: never;
		};
	};
};

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>;

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, 'public'>];

export type Tables<
	DefaultSchemaTableNameOrOptions extends
		| keyof (DefaultSchema['Tables'] & DefaultSchema['Views'])
		| { schema: keyof DatabaseWithoutInternals },
	TableName extends (DefaultSchemaTableNameOrOptions extends {
		schema: keyof DatabaseWithoutInternals;
	}
		? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'] &
				DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Views'])
		: never) = never
> = DefaultSchemaTableNameOrOptions extends {
	schema: keyof DatabaseWithoutInternals;
}
	? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'] &
			DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Views'])[TableName] extends {
			Row: infer R;
		}
		? R
		: never
	: DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema['Tables'] & DefaultSchema['Views'])
		? (DefaultSchema['Tables'] & DefaultSchema['Views'])[DefaultSchemaTableNameOrOptions] extends {
				Row: infer R;
			}
			? R
			: never
		: never;

export type TablesInsert<
	DefaultSchemaTableNameOrOptions extends
		keyof DefaultSchema['Tables'] | { schema: keyof DatabaseWithoutInternals },
	TableName extends (DefaultSchemaTableNameOrOptions extends {
		schema: keyof DatabaseWithoutInternals;
	}
		? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables']
		: never) = never
> = DefaultSchemaTableNameOrOptions extends {
	schema: keyof DatabaseWithoutInternals;
}
	? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'][TableName] extends {
			Insert: infer I;
		}
		? I
		: never
	: DefaultSchemaTableNameOrOptions extends keyof DefaultSchema['Tables']
		? DefaultSchema['Tables'][DefaultSchemaTableNameOrOptions] extends {
				Insert: infer I;
			}
			? I
			: never
		: never;

export type TablesUpdate<
	DefaultSchemaTableNameOrOptions extends
		keyof DefaultSchema['Tables'] | { schema: keyof DatabaseWithoutInternals },
	TableName extends (DefaultSchemaTableNameOrOptions extends {
		schema: keyof DatabaseWithoutInternals;
	}
		? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables']
		: never) = never
> = DefaultSchemaTableNameOrOptions extends {
	schema: keyof DatabaseWithoutInternals;
}
	? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'][TableName] extends {
			Update: infer U;
		}
		? U
		: never
	: DefaultSchemaTableNameOrOptions extends keyof DefaultSchema['Tables']
		? DefaultSchema['Tables'][DefaultSchemaTableNameOrOptions] extends {
				Update: infer U;
			}
			? U
			: never
		: never;

export type Enums<
	DefaultSchemaEnumNameOrOptions extends
		keyof DefaultSchema['Enums'] | { schema: keyof DatabaseWithoutInternals },
	EnumName extends (DefaultSchemaEnumNameOrOptions extends {
		schema: keyof DatabaseWithoutInternals;
	}
		? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions['schema']]['Enums']
		: never) = never
> = DefaultSchemaEnumNameOrOptions extends {
	schema: keyof DatabaseWithoutInternals;
}
	? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions['schema']]['Enums'][EnumName]
	: DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema['Enums']
		? DefaultSchema['Enums'][DefaultSchemaEnumNameOrOptions]
		: never;

export type CompositeTypes<
	PublicCompositeTypeNameOrOptions extends
		keyof DefaultSchema['CompositeTypes'] | { schema: keyof DatabaseWithoutInternals },
	CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
		schema: keyof DatabaseWithoutInternals;
	}
		? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions['schema']]['CompositeTypes']
		: never) = never
> = PublicCompositeTypeNameOrOptions extends {
	schema: keyof DatabaseWithoutInternals;
}
	? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions['schema']]['CompositeTypes'][CompositeTypeName]
	: PublicCompositeTypeNameOrOptions extends keyof DefaultSchema['CompositeTypes']
		? DefaultSchema['CompositeTypes'][PublicCompositeTypeNameOrOptions]
		: never;

export const Constants = {
	public: {
		Enums: {}
	}
} as const;
