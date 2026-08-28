export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.17"
  }
  public: {
    Tables: {
      access_audit_events: {
        Row: {
          actor_kind: string
          actor_owner_email: string | null
          actor_user_id: string | null
          after_state: Json | null
          before_state: Json | null
          created_at: string
          event_type: string
          id: string
          organization_id: string
          target_key: string | null
          target_type: string
        }
        Insert: {
          actor_kind: string
          actor_owner_email?: string | null
          actor_user_id?: string | null
          after_state?: Json | null
          before_state?: Json | null
          created_at?: string
          event_type: string
          id?: string
          organization_id: string
          target_key?: string | null
          target_type: string
        }
        Update: {
          actor_kind?: string
          actor_owner_email?: string | null
          actor_user_id?: string | null
          after_state?: Json | null
          before_state?: Json | null
          created_at?: string
          event_type?: string
          id?: string
          organization_id?: string
          target_key?: string | null
          target_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "access_audit_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      activity_events: {
        Row: {
          actor_user_id: string | null
          created_at: string
          entity_id: string
          entity_type: string
          event_type: string
          id: string
          metadata: Json
          organization_id: string
          summary: string
        }
        Insert: {
          actor_user_id?: string | null
          created_at?: string
          entity_id: string
          entity_type: string
          event_type: string
          id?: string
          metadata?: Json
          organization_id: string
          summary: string
        }
        Update: {
          actor_user_id?: string | null
          created_at?: string
          entity_id?: string
          entity_type?: string
          event_type?: string
          id?: string
          metadata?: Json
          organization_id?: string
          summary?: string
        }
        Relationships: [
          {
            foreignKeyName: "activity_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      assessment_assignees: {
        Row: {
          assessment_id: string
          created_at: string
          organization_id: string
          user_id: string
        }
        Insert: {
          assessment_id: string
          created_at?: string
          organization_id: string
          user_id: string
        }
        Update: {
          assessment_id?: string
          created_at?: string
          organization_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "assessment_assignees_assessment_id_fkey"
            columns: ["assessment_id"]
            isOneToOne: false
            referencedRelation: "assessments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assessment_assignees_member_fk"
            columns: ["organization_id", "user_id"]
            isOneToOne: false
            referencedRelation: "organization_members"
            referencedColumns: ["organization_id", "user_id"]
          },
          {
            foreignKeyName: "assessment_assignees_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      assessments: {
        Row: {
          all_day: boolean
          completed_at: string | null
          created_at: string
          ends_at: string | null
          id: string
          instructions: string | null
          organization_id: string
          request_id: string
          starts_at: string | null
          updated_at: string
        }
        Insert: {
          all_day?: boolean
          completed_at?: string | null
          created_at?: string
          ends_at?: string | null
          id?: string
          instructions?: string | null
          organization_id: string
          request_id: string
          starts_at?: string | null
          updated_at?: string
        }
        Update: {
          all_day?: boolean
          completed_at?: string | null
          created_at?: string
          ends_at?: string | null
          id?: string
          instructions?: string | null
          organization_id?: string
          request_id?: string
          starts_at?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "assessments_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assessments_request_organization_fk"
            columns: ["organization_id", "request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      attachments: {
        Row: {
          created_at: string
          entity_id: string
          entity_type: string
          file_name: string
          id: string
          mime_type: string
          note_id: string | null
          object_key: string
          organization_id: string
          size_bytes: number
          thumbnail_object_key: string | null
          uploaded_by: string | null
        }
        Insert: {
          created_at?: string
          entity_id: string
          entity_type: string
          file_name: string
          id?: string
          mime_type: string
          note_id?: string | null
          object_key: string
          organization_id: string
          size_bytes: number
          thumbnail_object_key?: string | null
          uploaded_by?: string | null
        }
        Update: {
          created_at?: string
          entity_id?: string
          entity_type?: string
          file_name?: string
          id?: string
          mime_type?: string
          note_id?: string | null
          object_key?: string
          organization_id?: string
          size_bytes?: number
          thumbnail_object_key?: string | null
          uploaded_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "attachments_note_id_fkey"
            columns: ["note_id"]
            isOneToOne: false
            referencedRelation: "notes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attachments_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      catalog_items: {
        Row: {
          archived_at: string | null
          category: string
          created_at: string
          created_by: string | null
          description: string | null
          id: string
          is_labor: boolean
          is_taxable: boolean
          name: string
          organization_id: string
          revision: number
          unit_cost_minor: number
          unit_label: string | null
          unit_price_minor: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          archived_at?: string | null
          category: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          is_labor?: boolean
          is_taxable?: boolean
          name: string
          organization_id: string
          revision?: number
          unit_cost_minor?: number
          unit_label?: string | null
          unit_price_minor?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          archived_at?: string | null
          category?: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          is_labor?: boolean
          is_taxable?: boolean
          name?: string
          organization_id?: string
          revision?: number
          unit_cost_minor?: number
          unit_label?: string | null
          unit_price_minor?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "catalog_items_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      client_communication_preferences: {
        Row: {
          appointment_reminders: boolean
          client_id: string
          contact_policy: string
          created_at: string
          invoice_reminders: boolean
          job_follow_ups: boolean
          marketing: boolean
          opt_out_source: string | null
          organization_id: string
          quote_follow_ups: boolean
          review_requests: boolean
          sms_opt_in_at: string | null
          sms_opt_out_at: string | null
          updated_at: string
        }
        Insert: {
          appointment_reminders?: boolean
          client_id: string
          contact_policy?: string
          created_at?: string
          invoice_reminders?: boolean
          job_follow_ups?: boolean
          marketing?: boolean
          opt_out_source?: string | null
          organization_id: string
          quote_follow_ups?: boolean
          review_requests?: boolean
          sms_opt_in_at?: string | null
          sms_opt_out_at?: string | null
          updated_at?: string
        }
        Update: {
          appointment_reminders?: boolean
          client_id?: string
          contact_policy?: string
          created_at?: string
          invoice_reminders?: boolean
          job_follow_ups?: boolean
          marketing?: boolean
          opt_out_source?: string | null
          organization_id?: string
          quote_follow_ups?: boolean
          review_requests?: boolean
          sms_opt_in_at?: string | null
          sms_opt_out_at?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "client_communication_preferences_client_organization_fk"
            columns: ["organization_id", "client_id"]
            isOneToOne: true
            referencedRelation: "clients"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "client_communication_preferences_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      client_contact_methods: {
        Row: {
          client_contact_id: string | null
          client_id: string
          created_at: string
          id: string
          is_primary: boolean
          kind: string
          label: string | null
          normalized_value: string
          organization_id: string
          updated_at: string
          value: string
        }
        Insert: {
          client_contact_id?: string | null
          client_id: string
          created_at?: string
          id?: string
          is_primary?: boolean
          kind: string
          label?: string | null
          normalized_value?: string
          organization_id: string
          updated_at?: string
          value: string
        }
        Update: {
          client_contact_id?: string | null
          client_id?: string
          created_at?: string
          id?: string
          is_primary?: boolean
          kind?: string
          label?: string | null
          normalized_value?: string
          organization_id?: string
          updated_at?: string
          value?: string
        }
        Relationships: [
          {
            foreignKeyName: "client_contact_methods_client_organization_fk"
            columns: ["organization_id", "client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "client_contact_methods_contact_organization_fk"
            columns: ["organization_id", "client_contact_id"]
            isOneToOne: false
            referencedRelation: "client_contacts"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "client_contact_methods_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      client_contacts: {
        Row: {
          client_id: string
          created_at: string
          first_name: string | null
          id: string
          is_primary: boolean
          last_name: string | null
          organization_id: string
          role_label: string | null
          updated_at: string
        }
        Insert: {
          client_id: string
          created_at?: string
          first_name?: string | null
          id?: string
          is_primary?: boolean
          last_name?: string | null
          organization_id: string
          role_label?: string | null
          updated_at?: string
        }
        Update: {
          client_id?: string
          created_at?: string
          first_name?: string | null
          id?: string
          is_primary?: boolean
          last_name?: string | null
          organization_id?: string
          role_label?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "client_contacts_client_organization_fk"
            columns: ["organization_id", "client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "client_contacts_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      clients: {
        Row: {
          archived_at: string | null
          client_type: string
          company_name: string | null
          converted_to_customer_at: string | null
          created_at: string
          deleted_at: string | null
          display_name: string
          first_name: string | null
          id: string
          last_name: string | null
          lead_source: string | null
          lead_temperature: string | null
          lifecycle_status: string
          next_follow_up_at: string | null
          organization_id: string
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          client_type?: string
          company_name?: string | null
          converted_to_customer_at?: string | null
          created_at?: string
          deleted_at?: string | null
          display_name: string
          first_name?: string | null
          id?: string
          last_name?: string | null
          lead_source?: string | null
          lead_temperature?: string | null
          lifecycle_status?: string
          next_follow_up_at?: string | null
          organization_id: string
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          client_type?: string
          company_name?: string | null
          converted_to_customer_at?: string | null
          created_at?: string
          deleted_at?: string | null
          display_name?: string
          first_name?: string | null
          id?: string
          last_name?: string | null
          lead_source?: string | null
          lead_temperature?: string | null
          lifecycle_status?: string
          next_follow_up_at?: string | null
          organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "clients_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      communication_conversation_assignments: {
        Row: {
          assigned_at: string
          assigned_by: string | null
          assigned_to: string
          client_id: string
          organization_id: string
          updated_at: string
        }
        Insert: {
          assigned_at?: string
          assigned_by?: string | null
          assigned_to: string
          client_id: string
          organization_id: string
          updated_at?: string
        }
        Update: {
          assigned_at?: string
          assigned_by?: string | null
          assigned_to?: string
          client_id?: string
          organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "communication_conversation_assignments_client_fk"
            columns: ["organization_id", "client_id"]
            isOneToOne: true
            referencedRelation: "clients"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "communication_conversation_assignments_member_fk"
            columns: ["organization_id", "assigned_to"]
            isOneToOne: false
            referencedRelation: "organization_members"
            referencedColumns: ["organization_id", "user_id"]
          },
          {
            foreignKeyName: "communication_conversation_assignments_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      communication_conversation_followers: {
        Row: {
          client_id: string
          followed_at: string
          organization_id: string
          user_id: string
        }
        Insert: {
          client_id: string
          followed_at?: string
          organization_id: string
          user_id: string
        }
        Update: {
          client_id?: string
          followed_at?: string
          organization_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "communication_conversation_followers_client_fk"
            columns: ["organization_id", "client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "communication_conversation_followers_member_fk"
            columns: ["organization_id", "user_id"]
            isOneToOne: false
            referencedRelation: "organization_members"
            referencedColumns: ["organization_id", "user_id"]
          },
          {
            foreignKeyName: "communication_conversation_followers_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      communication_conversation_read_marks: {
        Row: {
          client_id: string
          created_at: string
          last_read_at: string
          organization_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          client_id: string
          created_at?: string
          last_read_at: string
          organization_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          client_id?: string
          created_at?: string
          last_read_at?: string
          organization_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "communication_conversation_read_marks_client_fk"
            columns: ["organization_id", "client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "communication_conversation_read_marks_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      communication_delivery_intents: {
        Row: {
          accepted_at: string | null
          allowance_class: string
          channel: string
          client_contact_method_id: string
          client_id: string
          created_at: string
          created_by: string | null
          delivery_outcome: string | null
          delivery_outcome_at: string | null
          delivery_outcome_detail: string | null
          direction: string
          expires_at: string
          failure_code: string | null
          failure_message: string | null
          html_content: string
          id: string
          logical_send_key: string
          organization_id: string
          provider_message_id: string | null
          quote_id: string | null
          recipient_email: string
          reply_alias_id: string | null
          resent_from_intent_id: string | null
          retry_class: string
          retry_window_ends_at: string | null
          send_kind: string
          sender_id: string | null
          status: string
          subject: string
          text_content: string
          updated_at: string
        }
        Insert: {
          accepted_at?: string | null
          allowance_class?: string
          channel?: string
          client_contact_method_id: string
          client_id: string
          created_at?: string
          created_by?: string | null
          delivery_outcome?: string | null
          delivery_outcome_at?: string | null
          delivery_outcome_detail?: string | null
          direction?: string
          expires_at?: string
          failure_code?: string | null
          failure_message?: string | null
          html_content: string
          id?: string
          logical_send_key: string
          organization_id: string
          provider_message_id?: string | null
          quote_id?: string | null
          recipient_email: string
          reply_alias_id?: string | null
          resent_from_intent_id?: string | null
          retry_class?: string
          retry_window_ends_at?: string | null
          send_kind?: string
          sender_id?: string | null
          status?: string
          subject: string
          text_content: string
          updated_at?: string
        }
        Update: {
          accepted_at?: string | null
          allowance_class?: string
          channel?: string
          client_contact_method_id?: string
          client_id?: string
          created_at?: string
          created_by?: string | null
          delivery_outcome?: string | null
          delivery_outcome_at?: string | null
          delivery_outcome_detail?: string | null
          direction?: string
          expires_at?: string
          failure_code?: string | null
          failure_message?: string | null
          html_content?: string
          id?: string
          logical_send_key?: string
          organization_id?: string
          provider_message_id?: string | null
          quote_id?: string | null
          recipient_email?: string
          reply_alias_id?: string | null
          resent_from_intent_id?: string | null
          retry_class?: string
          retry_window_ends_at?: string | null
          send_kind?: string
          sender_id?: string | null
          status?: string
          subject?: string
          text_content?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "communication_delivery_intents_client_fk"
            columns: ["organization_id", "client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "communication_delivery_intents_contact_method_fk"
            columns: ["organization_id", "client_contact_method_id"]
            isOneToOne: false
            referencedRelation: "client_contact_methods"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "communication_delivery_intents_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communication_delivery_intents_quote_fk"
            columns: ["organization_id", "quote_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "communication_delivery_intents_reply_alias_id_fkey"
            columns: ["reply_alias_id"]
            isOneToOne: false
            referencedRelation: "communication_reply_aliases"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communication_delivery_intents_resent_from_fk"
            columns: ["resent_from_intent_id"]
            isOneToOne: false
            referencedRelation: "communication_delivery_intents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communication_delivery_intents_sender_fk"
            columns: ["organization_id", "sender_id"]
            isOneToOne: false
            referencedRelation: "communication_email_senders"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      communication_email_allowance_alerts: {
        Row: {
          alert_kind: string
          allowance_period_id: string
          first_detected_at: string
          id: string
          organization_id: string
        }
        Insert: {
          alert_kind: string
          allowance_period_id: string
          first_detected_at?: string
          id?: string
          organization_id: string
        }
        Update: {
          alert_kind?: string
          allowance_period_id?: string
          first_detected_at?: string
          id?: string
          organization_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "communication_email_allowance_alerts_allowance_period_id_fkey"
            columns: ["allowance_period_id"]
            isOneToOne: false
            referencedRelation: "communication_email_allowance_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communication_email_allowance_alerts_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      communication_email_allowance_periods: {
        Row: {
          created_at: string
          ends_at: string
          id: string
          opened_by_commercial_event_id: string | null
          organization_id: string
          starts_at: string
        }
        Insert: {
          created_at?: string
          ends_at: string
          id?: string
          opened_by_commercial_event_id?: string | null
          organization_id: string
          starts_at: string
        }
        Update: {
          created_at?: string
          ends_at?: string
          id?: string
          opened_by_commercial_event_id?: string | null
          organization_id?: string
          starts_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "communication_email_allowance_opened_by_commercial_event_i_fkey"
            columns: ["opened_by_commercial_event_id"]
            isOneToOne: false
            referencedRelation: "organization_commercial_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communication_email_allowance_periods_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      communication_email_authority_events: {
        Row: {
          actor_kind: string
          actor_owner_email: string | null
          actor_user_id: string | null
          after_state: Json | null
          before_state: Json | null
          created_at: string
          event_type: string
          id: string
          idempotency_key: string
          occurred_at: string
          organization_id: string
          reason: string | null
          target_id: string
          target_type: string
        }
        Insert: {
          actor_kind: string
          actor_owner_email?: string | null
          actor_user_id?: string | null
          after_state?: Json | null
          before_state?: Json | null
          created_at?: string
          event_type: string
          id?: string
          idempotency_key: string
          occurred_at?: string
          organization_id: string
          reason?: string | null
          target_id: string
          target_type: string
        }
        Update: {
          actor_kind?: string
          actor_owner_email?: string | null
          actor_user_id?: string | null
          after_state?: Json | null
          before_state?: Json | null
          created_at?: string
          event_type?: string
          id?: string
          idempotency_key?: string
          occurred_at?: string
          organization_id?: string
          reason?: string | null
          target_id?: string
          target_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "communication_email_authority_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      communication_email_capacity_buckets: {
        Row: {
          allowance_class: string
          allowance_period_id: string
          created_at: string
          organization_id: string
        }
        Insert: {
          allowance_class: string
          allowance_period_id: string
          created_at?: string
          organization_id: string
        }
        Update: {
          allowance_class?: string
          allowance_period_id?: string
          created_at?: string
          organization_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "communication_email_capacity_buckets_allowance_period_id_fkey"
            columns: ["allowance_period_id"]
            isOneToOne: false
            referencedRelation: "communication_email_allowance_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communication_email_capacity_buckets_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      communication_email_capacity_reservations: {
        Row: {
          allowance_class: string
          allowance_period_id: string
          created_at: string
          delivery_intent_id: string
          id: string
          organization_id: string
          recipient_count: number
          reservation_state: string
          reserved_at: string
          settled_at: string | null
          updated_at: string
        }
        Insert: {
          allowance_class: string
          allowance_period_id: string
          created_at?: string
          delivery_intent_id: string
          id?: string
          organization_id: string
          recipient_count?: number
          reservation_state?: string
          reserved_at?: string
          settled_at?: string | null
          updated_at?: string
        }
        Update: {
          allowance_class?: string
          allowance_period_id?: string
          created_at?: string
          delivery_intent_id?: string
          id?: string
          organization_id?: string
          recipient_count?: number
          reservation_state?: string
          reserved_at?: string
          settled_at?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "communication_email_capacity_reservati_allowance_period_id_fkey"
            columns: ["allowance_period_id"]
            isOneToOne: false
            referencedRelation: "communication_email_allowance_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communication_email_capacity_reservatio_delivery_intent_id_fkey"
            columns: ["delivery_intent_id"]
            isOneToOne: true
            referencedRelation: "communication_delivery_intents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communication_email_capacity_reservations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      communication_email_domains: {
        Row: {
          created_at: string
          created_by: string | null
          dkim_status: string
          dmarc_status: string
          dns_records: Json
          dns_zone: string | null
          domain_name: string
          id: string
          inbound_mx_status: string
          last_checked_at: string | null
          lifecycle_state: string
          organization_id: string
          ownership_status: string
          provider: string
          provider_authenticated: boolean
          provider_cleanup_error: string | null
          provider_domain_id: string | null
          provider_verified: boolean
          purpose: string
          replacement_of_domain_id: string | null
          spf_status: string
          transition_until: string | null
          updated_at: string
          verified_at: string | null
          warmup_started_at: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          dkim_status?: string
          dmarc_status?: string
          dns_records?: Json
          dns_zone?: string | null
          domain_name: string
          id?: string
          inbound_mx_status?: string
          last_checked_at?: string | null
          lifecycle_state?: string
          organization_id: string
          ownership_status?: string
          provider?: string
          provider_authenticated?: boolean
          provider_cleanup_error?: string | null
          provider_domain_id?: string | null
          provider_verified?: boolean
          purpose: string
          replacement_of_domain_id?: string | null
          spf_status?: string
          transition_until?: string | null
          updated_at?: string
          verified_at?: string | null
          warmup_started_at?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          dkim_status?: string
          dmarc_status?: string
          dns_records?: Json
          dns_zone?: string | null
          domain_name?: string
          id?: string
          inbound_mx_status?: string
          last_checked_at?: string | null
          lifecycle_state?: string
          organization_id?: string
          ownership_status?: string
          provider?: string
          provider_authenticated?: boolean
          provider_cleanup_error?: string | null
          provider_domain_id?: string | null
          provider_verified?: boolean
          purpose?: string
          replacement_of_domain_id?: string | null
          spf_status?: string
          transition_until?: string | null
          updated_at?: string
          verified_at?: string | null
          warmup_started_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "communication_email_domains_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communication_email_domains_replacement_fk"
            columns: ["organization_id", "replacement_of_domain_id"]
            isOneToOne: false
            referencedRelation: "communication_email_domains"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      communication_email_platform_period_usage: {
        Row: {
          accepted_recipients: number
          period_end: string
          period_start: string
          updated_at: string
        }
        Insert: {
          accepted_recipients?: number
          period_end: string
          period_start: string
          updated_at?: string
        }
        Update: {
          accepted_recipients?: number
          period_end?: string
          period_start?: string
          updated_at?: string
        }
        Relationships: []
      }
      communication_email_platform_sending_settings: {
        Row: {
          actor_owner_email: string
          created_at: string
          effective_from: string
          effective_to: string | null
          id: string
          provider_period_capacity: number | null
          reason: string
          reserve_percent: number
          short_term_max_recipients: number
          short_term_window_minutes: number
          singleton_key: boolean
        }
        Insert: {
          actor_owner_email: string
          created_at?: string
          effective_from?: string
          effective_to?: string | null
          id?: string
          provider_period_capacity?: number | null
          reason: string
          reserve_percent?: number
          short_term_max_recipients: number
          short_term_window_minutes: number
          singleton_key?: boolean
        }
        Update: {
          actor_owner_email?: string
          created_at?: string
          effective_from?: string
          effective_to?: string | null
          id?: string
          provider_period_capacity?: number | null
          reason?: string
          reserve_percent?: number
          short_term_max_recipients?: number
          short_term_window_minutes?: number
          singleton_key?: boolean
        }
        Relationships: []
      }
      communication_email_reputation_state: {
        Row: {
          evaluated_at: string
          evaluation_requested_at: string | null
          last_breach_at: string | null
          metrics: Json
          organization_id: string
          updated_at: string
          worst_status: string
        }
        Insert: {
          evaluated_at?: string
          evaluation_requested_at?: string | null
          last_breach_at?: string | null
          metrics?: Json
          organization_id: string
          updated_at?: string
          worst_status?: string
        }
        Update: {
          evaluated_at?: string
          evaluation_requested_at?: string | null
          last_breach_at?: string | null
          metrics?: Json
          organization_id?: string
          updated_at?: string
          worst_status?: string
        }
        Relationships: [
          {
            foreignKeyName: "communication_email_reputation_state_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: true
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      communication_email_reputation_thresholds: {
        Row: {
          actor_owner_email: string
          created_at: string
          effective_from: string
          effective_to: string | null
          id: string
          min_event_count: number | null
          min_sample_recipients: number | null
          organization_id: string | null
          pause_rate: number | null
          reason: string
          scope: string
          signal: string
          warn_rate: number | null
          window_hours: number | null
          window_key: string
        }
        Insert: {
          actor_owner_email: string
          created_at?: string
          effective_from?: string
          effective_to?: string | null
          id?: string
          min_event_count?: number | null
          min_sample_recipients?: number | null
          organization_id?: string | null
          pause_rate?: number | null
          reason: string
          scope: string
          signal: string
          warn_rate?: number | null
          window_hours?: number | null
          window_key: string
        }
        Update: {
          actor_owner_email?: string
          created_at?: string
          effective_from?: string
          effective_to?: string | null
          id?: string
          min_event_count?: number | null
          min_sample_recipients?: number | null
          organization_id?: string | null
          pause_rate?: number | null
          reason?: string
          scope?: string
          signal?: string
          warn_rate?: number | null
          window_hours?: number | null
          window_key?: string
        }
        Relationships: [
          {
            foreignKeyName: "communication_email_reputation_thresholds_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      communication_email_senders: {
        Row: {
          allows_automated: boolean
          allows_manual: boolean
          assigned_user_id: string | null
          created_at: string
          created_by: string | null
          display_name: string
          domain_id: string
          email_address: string
          id: string
          is_organization_default: boolean
          lifecycle_state: string
          organization_id: string
          provider: string
          provider_cleanup_error: string | null
          provider_sender_id: number | null
          restriction_reason: string | null
          updated_at: string
        }
        Insert: {
          allows_automated?: boolean
          allows_manual?: boolean
          assigned_user_id?: string | null
          created_at?: string
          created_by?: string | null
          display_name: string
          domain_id: string
          email_address: string
          id?: string
          is_organization_default?: boolean
          lifecycle_state?: string
          organization_id: string
          provider?: string
          provider_cleanup_error?: string | null
          provider_sender_id?: number | null
          restriction_reason?: string | null
          updated_at?: string
        }
        Update: {
          allows_automated?: boolean
          allows_manual?: boolean
          assigned_user_id?: string | null
          created_at?: string
          created_by?: string | null
          display_name?: string
          domain_id?: string
          email_address?: string
          id?: string
          is_organization_default?: boolean
          lifecycle_state?: string
          organization_id?: string
          provider?: string
          provider_cleanup_error?: string | null
          provider_sender_id?: number | null
          restriction_reason?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "communication_email_senders_domain_fk"
            columns: ["organization_id", "domain_id"]
            isOneToOne: false
            referencedRelation: "communication_email_domains"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "communication_email_senders_member_fk"
            columns: ["organization_id", "assigned_user_id"]
            isOneToOne: false
            referencedRelation: "organization_members"
            referencedColumns: ["organization_id", "user_id"]
          },
          {
            foreignKeyName: "communication_email_senders_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      communication_email_sending_pauses: {
        Row: {
          applies_to: string
          engaged_at: string
          engaged_by_owner_email: string
          evidence: Json
          id: string
          organization_id: string | null
          reason: string
          released_at: string | null
          released_by_owner_email: string | null
          released_reason: string | null
          scope: string
          source: string
        }
        Insert: {
          applies_to?: string
          engaged_at?: string
          engaged_by_owner_email: string
          evidence?: Json
          id?: string
          organization_id?: string | null
          reason: string
          released_at?: string | null
          released_by_owner_email?: string | null
          released_reason?: string | null
          scope: string
          source?: string
        }
        Update: {
          applies_to?: string
          engaged_at?: string
          engaged_by_owner_email?: string
          evidence?: Json
          id?: string
          organization_id?: string | null
          reason?: string
          released_at?: string | null
          released_by_owner_email?: string | null
          released_reason?: string | null
          scope?: string
          source?: string
        }
        Relationships: [
          {
            foreignKeyName: "communication_email_sending_pauses_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      communication_email_suppression_removal_requests: {
        Row: {
          consent_confirmed: boolean
          created_at: string
          decided_at: string | null
          decided_by_email: string | null
          decided_by_kind: string | null
          decided_by_user_id: string | null
          decision_note: string | null
          id: string
          organization_id: string
          recipient_email: string
          request_evidence: string
          request_reason: string
          requested_by_email: string
          requested_by_user_id: string | null
          status: string
          suppression_id: string
          suppression_reason: string
        }
        Insert: {
          consent_confirmed: boolean
          created_at?: string
          decided_at?: string | null
          decided_by_email?: string | null
          decided_by_kind?: string | null
          decided_by_user_id?: string | null
          decision_note?: string | null
          id?: string
          organization_id: string
          recipient_email: string
          request_evidence: string
          request_reason: string
          requested_by_email: string
          requested_by_user_id?: string | null
          status?: string
          suppression_id: string
          suppression_reason: string
        }
        Update: {
          consent_confirmed?: boolean
          created_at?: string
          decided_at?: string | null
          decided_by_email?: string | null
          decided_by_kind?: string | null
          decided_by_user_id?: string | null
          decision_note?: string | null
          id?: string
          organization_id?: string
          recipient_email?: string
          request_evidence?: string
          request_reason?: string
          requested_by_email?: string
          requested_by_user_id?: string | null
          status?: string
          suppression_id?: string
          suppression_reason?: string
        }
        Relationships: [
          {
            foreignKeyName: "communication_email_suppression_removal_re_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communication_email_suppression_removal_req_suppression_id_fkey"
            columns: ["suppression_id"]
            isOneToOne: false
            referencedRelation: "communication_email_suppressions"
            referencedColumns: ["id"]
          },
        ]
      }
      communication_email_suppressions: {
        Row: {
          created_at: string
          created_by_owner_email: string | null
          evidence: Json
          first_delivery_intent_id: string | null
          id: string
          organization_id: string
          reason: string
          recipient_email: string
          released_at: string | null
          released_by_kind: string | null
          released_by_owner_email: string | null
          released_by_user_id: string | null
          released_reason: string | null
          source: string
          source_callback_event_id: string | null
        }
        Insert: {
          created_at?: string
          created_by_owner_email?: string | null
          evidence?: Json
          first_delivery_intent_id?: string | null
          id?: string
          organization_id: string
          reason: string
          recipient_email: string
          released_at?: string | null
          released_by_kind?: string | null
          released_by_owner_email?: string | null
          released_by_user_id?: string | null
          released_reason?: string | null
          source?: string
          source_callback_event_id?: string | null
        }
        Update: {
          created_at?: string
          created_by_owner_email?: string | null
          evidence?: Json
          first_delivery_intent_id?: string | null
          id?: string
          organization_id?: string
          reason?: string
          recipient_email?: string
          released_at?: string | null
          released_by_kind?: string | null
          released_by_owner_email?: string | null
          released_by_user_id?: string | null
          released_reason?: string | null
          source?: string
          source_callback_event_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "communication_email_suppressions_first_delivery_intent_id_fkey"
            columns: ["first_delivery_intent_id"]
            isOneToOne: false
            referencedRelation: "communication_delivery_intents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communication_email_suppressions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communication_email_suppressions_source_callback_event_id_fkey"
            columns: ["source_callback_event_id"]
            isOneToOne: false
            referencedRelation: "communication_provider_callback_events"
            referencedColumns: ["id"]
          },
        ]
      }
      communication_email_usage_events: {
        Row: {
          allowance_class: string | null
          allowance_period_id: string | null
          delivery_intent_id: string
          event_kind: string
          id: string
          occurred_at: string
          organization_id: string
          recipient_count: number
        }
        Insert: {
          allowance_class?: string | null
          allowance_period_id?: string | null
          delivery_intent_id: string
          event_kind?: string
          id?: string
          occurred_at?: string
          organization_id: string
          recipient_count?: number
        }
        Update: {
          allowance_class?: string | null
          allowance_period_id?: string | null
          delivery_intent_id?: string
          event_kind?: string
          id?: string
          occurred_at?: string
          organization_id?: string
          recipient_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "communication_email_usage_events_allowance_period_id_fkey"
            columns: ["allowance_period_id"]
            isOneToOne: false
            referencedRelation: "communication_email_allowance_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communication_email_usage_events_delivery_intent_id_fkey"
            columns: ["delivery_intent_id"]
            isOneToOne: true
            referencedRelation: "communication_delivery_intents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communication_email_usage_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      communication_email_warmup_stages: {
        Row: {
          actor_owner_email: string
          created_at: string
          daily_ceiling: number
          effective_from: string
          effective_to: string | null
          id: string
          organization_id: string | null
          reason: string
          scope: string
          stage_key: string
        }
        Insert: {
          actor_owner_email: string
          created_at?: string
          daily_ceiling: number
          effective_from?: string
          effective_to?: string | null
          id?: string
          organization_id?: string | null
          reason: string
          scope: string
          stage_key: string
        }
        Update: {
          actor_owner_email?: string
          created_at?: string
          daily_ceiling?: number
          effective_from?: string
          effective_to?: string | null
          id?: string
          organization_id?: string | null
          reason?: string
          scope?: string
          stage_key?: string
        }
        Relationships: [
          {
            foreignKeyName: "communication_email_warmup_stages_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      communication_forward_attachments: {
        Row: {
          created_at: string
          forward_event_id: string
          id: string
          inbound_attachment_id: string
          organization_id: string
        }
        Insert: {
          created_at?: string
          forward_event_id: string
          id?: string
          inbound_attachment_id: string
          organization_id: string
        }
        Update: {
          created_at?: string
          forward_event_id?: string
          id?: string
          inbound_attachment_id?: string
          organization_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "communication_forward_attachments_event_fk"
            columns: ["organization_id", "forward_event_id"]
            isOneToOne: false
            referencedRelation: "communication_forward_events"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "communication_forward_attachments_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communication_forward_attachments_source_fk"
            columns: ["organization_id", "inbound_attachment_id"]
            isOneToOne: false
            referencedRelation: "communication_inbound_attachments"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      communication_forward_events: {
        Row: {
          accepted_at: string | null
          attempt_count: number
          available_at: string
          claim_token: string | null
          claimed_at: string | null
          client_id: string
          created_at: string
          created_by: string | null
          failure_code: string | null
          failure_message: string | null
          finalized_claim_token: string | null
          html_content: string
          id: string
          last_error: string | null
          logical_send_key: string
          organization_id: string
          provider_message_id: string | null
          recipient_emails: string[]
          sender_id: string
          source_inbound_message_id: string
          status: string
          subject: string
          text_content: string
          updated_at: string
        }
        Insert: {
          accepted_at?: string | null
          attempt_count?: number
          available_at?: string
          claim_token?: string | null
          claimed_at?: string | null
          client_id: string
          created_at?: string
          created_by?: string | null
          failure_code?: string | null
          failure_message?: string | null
          finalized_claim_token?: string | null
          html_content: string
          id?: string
          last_error?: string | null
          logical_send_key: string
          organization_id: string
          provider_message_id?: string | null
          recipient_emails: string[]
          sender_id: string
          source_inbound_message_id: string
          status?: string
          subject: string
          text_content: string
          updated_at?: string
        }
        Update: {
          accepted_at?: string | null
          attempt_count?: number
          available_at?: string
          claim_token?: string | null
          claimed_at?: string | null
          client_id?: string
          created_at?: string
          created_by?: string | null
          failure_code?: string | null
          failure_message?: string | null
          finalized_claim_token?: string | null
          html_content?: string
          id?: string
          last_error?: string | null
          logical_send_key?: string
          organization_id?: string
          provider_message_id?: string | null
          recipient_emails?: string[]
          sender_id?: string
          source_inbound_message_id?: string
          status?: string
          subject?: string
          text_content?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "communication_forward_events_client_fk"
            columns: ["organization_id", "client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "communication_forward_events_message_fk"
            columns: ["organization_id", "source_inbound_message_id"]
            isOneToOne: false
            referencedRelation: "communication_inbound_messages"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "communication_forward_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communication_forward_events_sender_fk"
            columns: ["organization_id", "sender_id"]
            isOneToOne: false
            referencedRelation: "communication_email_senders"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      communication_inbound_attachments: {
        Row: {
          byte_size: number
          claim_token: string | null
          claimed_at: string | null
          created_at: string
          failure_reason: string | null
          file_name: string
          id: string
          inbound_message_id: string
          mime_type: string
          object_key: string | null
          organization_id: string
          provider_download_token: string | null
          status: string
          updated_at: string
        }
        Insert: {
          byte_size: number
          claim_token?: string | null
          claimed_at?: string | null
          created_at?: string
          failure_reason?: string | null
          file_name: string
          id?: string
          inbound_message_id: string
          mime_type: string
          object_key?: string | null
          organization_id: string
          provider_download_token?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          byte_size?: number
          claim_token?: string | null
          claimed_at?: string | null
          created_at?: string
          failure_reason?: string | null
          file_name?: string
          id?: string
          inbound_message_id?: string
          mime_type?: string
          object_key?: string | null
          organization_id?: string
          provider_download_token?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "communication_inbound_attachments_message_fk"
            columns: ["organization_id", "inbound_message_id"]
            isOneToOne: false
            referencedRelation: "communication_inbound_messages"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "communication_inbound_attachments_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      communication_inbound_messages: {
        Row: {
          attachment_count: number
          automation_suppressed: boolean
          cc_recipients: Json
          client_contact_method_id: string | null
          client_id: string | null
          created_at: string
          direction: string
          html_content: string | null
          id: string
          in_reply_to_intent_id: string | null
          in_reply_to_provider_message_id: string | null
          loop_detected_at: string | null
          message_kind: string
          organization_id: string
          owner_user_id: string | null
          provider: string
          provider_callback_event_id: string | null
          provider_message_id: string | null
          reply_alias_id: string | null
          review_reason: string | null
          review_resolved_at: string | null
          review_resolved_by: string | null
          review_status: string
          sender_email: string
          sender_id: string | null
          sender_name: string | null
          subject: string
          text_content: string
          to_recipients: Json
          updated_at: string
        }
        Insert: {
          attachment_count?: number
          automation_suppressed?: boolean
          cc_recipients?: Json
          client_contact_method_id?: string | null
          client_id?: string | null
          created_at?: string
          direction?: string
          html_content?: string | null
          id?: string
          in_reply_to_intent_id?: string | null
          in_reply_to_provider_message_id?: string | null
          loop_detected_at?: string | null
          message_kind?: string
          organization_id: string
          owner_user_id?: string | null
          provider?: string
          provider_callback_event_id?: string | null
          provider_message_id?: string | null
          reply_alias_id?: string | null
          review_reason?: string | null
          review_resolved_at?: string | null
          review_resolved_by?: string | null
          review_status?: string
          sender_email: string
          sender_id?: string | null
          sender_name?: string | null
          subject: string
          text_content: string
          to_recipients?: Json
          updated_at?: string
        }
        Update: {
          attachment_count?: number
          automation_suppressed?: boolean
          cc_recipients?: Json
          client_contact_method_id?: string | null
          client_id?: string | null
          created_at?: string
          direction?: string
          html_content?: string | null
          id?: string
          in_reply_to_intent_id?: string | null
          in_reply_to_provider_message_id?: string | null
          loop_detected_at?: string | null
          message_kind?: string
          organization_id?: string
          owner_user_id?: string | null
          provider?: string
          provider_callback_event_id?: string | null
          provider_message_id?: string | null
          reply_alias_id?: string | null
          review_reason?: string | null
          review_resolved_at?: string | null
          review_resolved_by?: string | null
          review_status?: string
          sender_email?: string
          sender_id?: string | null
          sender_name?: string | null
          subject?: string
          text_content?: string
          to_recipients?: Json
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "communication_inbound_messages_client_fk"
            columns: ["organization_id", "client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "communication_inbound_messages_contact_method_fk"
            columns: ["organization_id", "client_contact_method_id"]
            isOneToOne: false
            referencedRelation: "client_contact_methods"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "communication_inbound_messages_in_reply_to_intent_id_fkey"
            columns: ["in_reply_to_intent_id"]
            isOneToOne: false
            referencedRelation: "communication_delivery_intents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communication_inbound_messages_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communication_inbound_messages_provider_callback_event_id_fkey"
            columns: ["provider_callback_event_id"]
            isOneToOne: false
            referencedRelation: "communication_provider_callback_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communication_inbound_messages_reply_alias_id_fkey"
            columns: ["reply_alias_id"]
            isOneToOne: false
            referencedRelation: "communication_reply_aliases"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communication_inbound_messages_sender_fk"
            columns: ["organization_id", "sender_id"]
            isOneToOne: false
            referencedRelation: "communication_email_senders"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      communication_message_events: {
        Row: {
          actor_email: string | null
          actor_kind: string
          actor_user_id: string | null
          attempt_number: number | null
          delivery_intent_id: string
          event_kind: string
          id: string
          last_occurred_at: string
          occurred_at: string
          organization_id: string
          reason_code: string | null
          reason_message: string | null
          related_inbound_message_id: string | null
          related_intent_id: string | null
          repeat_count: number
          retry_at: string | null
          seq: number
        }
        Insert: {
          actor_email?: string | null
          actor_kind?: string
          actor_user_id?: string | null
          attempt_number?: number | null
          delivery_intent_id: string
          event_kind: string
          id?: string
          last_occurred_at?: string
          occurred_at?: string
          organization_id: string
          reason_code?: string | null
          reason_message?: string | null
          related_inbound_message_id?: string | null
          related_intent_id?: string | null
          repeat_count?: number
          retry_at?: string | null
          seq?: never
        }
        Update: {
          actor_email?: string | null
          actor_kind?: string
          actor_user_id?: string | null
          attempt_number?: number | null
          delivery_intent_id?: string
          event_kind?: string
          id?: string
          last_occurred_at?: string
          occurred_at?: string
          organization_id?: string
          reason_code?: string | null
          reason_message?: string | null
          related_inbound_message_id?: string | null
          related_intent_id?: string | null
          repeat_count?: number
          retry_at?: string | null
          seq?: never
        }
        Relationships: [
          {
            foreignKeyName: "communication_message_events_delivery_intent_id_fkey"
            columns: ["delivery_intent_id"]
            isOneToOne: false
            referencedRelation: "communication_delivery_intents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communication_message_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communication_message_events_related_inbound_message_id_fkey"
            columns: ["related_inbound_message_id"]
            isOneToOne: false
            referencedRelation: "communication_inbound_messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communication_message_events_related_intent_id_fkey"
            columns: ["related_intent_id"]
            isOneToOne: false
            referencedRelation: "communication_delivery_intents"
            referencedColumns: ["id"]
          },
        ]
      }
      communication_outbound_attachments: {
        Row: {
          byte_size: number
          created_at: string
          delivery_intent_id: string
          file_name: string
          id: string
          mime_type: string
          object_key: string
          organization_id: string
          updated_at: string
        }
        Insert: {
          byte_size: number
          created_at?: string
          delivery_intent_id: string
          file_name: string
          id?: string
          mime_type: string
          object_key: string
          organization_id: string
          updated_at?: string
        }
        Update: {
          byte_size?: number
          created_at?: string
          delivery_intent_id?: string
          file_name?: string
          id?: string
          mime_type?: string
          object_key?: string
          organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "communication_outbound_attachments_intent_fk"
            columns: ["organization_id", "delivery_intent_id"]
            isOneToOne: false
            referencedRelation: "communication_delivery_intents"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "communication_outbound_attachments_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      communication_outbox_events: {
        Row: {
          attempt_count: number
          available_at: string
          claim_token: string | null
          claimed_at: string | null
          created_at: string
          delivery_intent_id: string
          finalized_claim_token: string | null
          id: string
          last_error: string | null
          organization_id: string
          status: string
          updated_at: string
        }
        Insert: {
          attempt_count?: number
          available_at?: string
          claim_token?: string | null
          claimed_at?: string | null
          created_at?: string
          delivery_intent_id: string
          finalized_claim_token?: string | null
          id?: string
          last_error?: string | null
          organization_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          attempt_count?: number
          available_at?: string
          claim_token?: string | null
          claimed_at?: string | null
          created_at?: string
          delivery_intent_id?: string
          finalized_claim_token?: string | null
          id?: string
          last_error?: string | null
          organization_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "communication_outbox_events_delivery_intent_id_fkey"
            columns: ["delivery_intent_id"]
            isOneToOne: true
            referencedRelation: "communication_delivery_intents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communication_outbox_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      communication_provider_callback_events: {
        Row: {
          delivery_intent_id: string | null
          event_at: string | null
          event_kind: string
          id: string
          normalized_kind: string | null
          occurred_at: string | null
          organization_id: string | null
          payload: Json
          processed_at: string | null
          provider: string
          provider_event_key: string
          received_at: string
        }
        Insert: {
          delivery_intent_id?: string | null
          event_at?: string | null
          event_kind: string
          id?: string
          normalized_kind?: string | null
          occurred_at?: string | null
          organization_id?: string | null
          payload: Json
          processed_at?: string | null
          provider?: string
          provider_event_key: string
          received_at?: string
        }
        Update: {
          delivery_intent_id?: string | null
          event_at?: string | null
          event_kind?: string
          id?: string
          normalized_kind?: string | null
          occurred_at?: string | null
          organization_id?: string | null
          payload?: Json
          processed_at?: string | null
          provider?: string
          provider_event_key?: string
          received_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "communication_provider_callback_events_delivery_intent_id_fkey"
            columns: ["delivery_intent_id"]
            isOneToOne: false
            referencedRelation: "communication_delivery_intents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communication_provider_callback_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      communication_reply_aliases: {
        Row: {
          alias_local_part: string
          client_contact_method_id: string
          client_id: string
          created_at: string
          expires_at: string
          id: string
          last_activity_at: string
          organization_id: string
          receiving_domain_id: string
          sender_id: string
          updated_at: string
        }
        Insert: {
          alias_local_part: string
          client_contact_method_id: string
          client_id: string
          created_at?: string
          expires_at?: string
          id?: string
          last_activity_at?: string
          organization_id: string
          receiving_domain_id: string
          sender_id: string
          updated_at?: string
        }
        Update: {
          alias_local_part?: string
          client_contact_method_id?: string
          client_id?: string
          created_at?: string
          expires_at?: string
          id?: string
          last_activity_at?: string
          organization_id?: string
          receiving_domain_id?: string
          sender_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "communication_reply_aliases_client_fk"
            columns: ["organization_id", "client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "communication_reply_aliases_contact_method_fk"
            columns: ["organization_id", "client_contact_method_id"]
            isOneToOne: false
            referencedRelation: "client_contact_methods"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "communication_reply_aliases_domain_fk"
            columns: ["organization_id", "receiving_domain_id"]
            isOneToOne: false
            referencedRelation: "communication_email_domains"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "communication_reply_aliases_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communication_reply_aliases_sender_fk"
            columns: ["organization_id", "sender_id"]
            isOneToOne: false
            referencedRelation: "communication_email_senders"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      communications_email_templates: {
        Row: {
          body: string
          created_at: string
          created_by: string | null
          folder: string | null
          id: string
          name: string
          organization_id: string
          source_template_id: string | null
          source_version_copied_at: number | null
          subject: string
          updated_at: string
        }
        Insert: {
          body: string
          created_at?: string
          created_by?: string | null
          folder?: string | null
          id?: string
          name: string
          organization_id: string
          source_template_id?: string | null
          source_version_copied_at?: number | null
          subject: string
          updated_at?: string
        }
        Update: {
          body?: string
          created_at?: string
          created_by?: string | null
          folder?: string | null
          id?: string
          name?: string
          organization_id?: string
          source_template_id?: string | null
          source_version_copied_at?: number | null
          subject?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "communications_email_templates_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communications_email_templates_source_template_id_fkey"
            columns: ["source_template_id"]
            isOneToOne: false
            referencedRelation: "platform_email_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      communications_snippets: {
        Row: {
          body: string
          created_at: string
          created_by: string | null
          folder: string | null
          id: string
          organization_id: string
          title: string
          updated_at: string
        }
        Insert: {
          body: string
          created_at?: string
          created_by?: string | null
          folder?: string | null
          id?: string
          organization_id: string
          title: string
          updated_at?: string
        }
        Update: {
          body?: string
          created_at?: string
          created_by?: string | null
          folder?: string | null
          id?: string
          organization_id?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "communications_snippets_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      features: {
        Row: {
          created_at: string
          description: string
          feature_key: string
        }
        Insert: {
          created_at?: string
          description: string
          feature_key: string
        }
        Update: {
          created_at?: string
          description?: string
          feature_key?: string
        }
        Relationships: []
      }
      member_access_event_shapes: {
        Row: {
          event_type: string
          required_summary_keys: string[]
          subject_kind: string
          summary_keys: Json
        }
        Insert: {
          event_type: string
          required_summary_keys?: string[]
          subject_kind: string
          summary_keys?: Json
        }
        Update: {
          event_type?: string
          required_summary_keys?: string[]
          subject_kind?: string
          summary_keys?: Json
        }
        Relationships: []
      }
      note_links: {
        Row: {
          created_at: string
          entity_id: string
          entity_type: string
          id: string
          note_id: string
          organization_id: string
        }
        Insert: {
          created_at?: string
          entity_id: string
          entity_type: string
          id?: string
          note_id: string
          organization_id: string
        }
        Update: {
          created_at?: string
          entity_id?: string
          entity_type?: string
          id?: string
          note_id?: string
          organization_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "note_links_note_organization_fk"
            columns: ["organization_id", "note_id"]
            isOneToOne: false
            referencedRelation: "notes"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "note_links_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      notes: {
        Row: {
          body: string
          created_at: string
          created_by: string | null
          edited_at: string | null
          edited_by: string | null
          id: string
          organization_id: string
          pinned: boolean
          updated_at: string
        }
        Insert: {
          body: string
          created_at?: string
          created_by?: string | null
          edited_at?: string | null
          edited_by?: string | null
          id?: string
          organization_id: string
          pinned?: boolean
          updated_at?: string
        }
        Update: {
          body?: string
          created_at?: string
          created_by?: string | null
          edited_at?: string | null
          edited_by?: string | null
          id?: string
          organization_id?: string
          pinned?: boolean
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "notes_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      opportunities: {
        Row: {
          client_id: string
          created_at: string
          current_outcome_event_id: string | null
          estimated_value: number | null
          expected_close_on: string | null
          id: string
          next_follow_up_on: string | null
          organization_id: string
          outcome: string
          outcome_at: string | null
          owner_user_id: string | null
          property_id: string | null
          quote_id: string | null
          request_id: string | null
          stage: string
          stage_entered_at: string
          title: string
          updated_at: string
        }
        Insert: {
          client_id: string
          created_at?: string
          current_outcome_event_id?: string | null
          estimated_value?: number | null
          expected_close_on?: string | null
          id?: string
          next_follow_up_on?: string | null
          organization_id: string
          outcome?: string
          outcome_at?: string | null
          owner_user_id?: string | null
          property_id?: string | null
          quote_id?: string | null
          request_id?: string | null
          stage?: string
          stage_entered_at?: string
          title: string
          updated_at?: string
        }
        Update: {
          client_id?: string
          created_at?: string
          current_outcome_event_id?: string | null
          estimated_value?: number | null
          expected_close_on?: string | null
          id?: string
          next_follow_up_on?: string | null
          organization_id?: string
          outcome?: string
          outcome_at?: string | null
          owner_user_id?: string | null
          property_id?: string | null
          quote_id?: string | null
          request_id?: string | null
          stage?: string
          stage_entered_at?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "opportunities_client_organization_fk"
            columns: ["organization_id", "client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "opportunities_current_outcome_event_fk"
            columns: ["organization_id", "current_outcome_event_id"]
            isOneToOne: false
            referencedRelation: "opportunity_outcome_events"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "opportunities_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opportunities_property_organization_fk"
            columns: ["organization_id", "property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "opportunities_quote_organization_fk"
            columns: ["organization_id", "quote_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "opportunities_request_organization_fk"
            columns: ["organization_id", "request_id"]
            isOneToOne: true
            referencedRelation: "requests"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      opportunity_outcome_events: {
        Row: {
          actor_user_id: string | null
          created_at: string
          event_type: string
          id: string
          idempotency_key: string
          note: string | null
          occurred_at: string
          opportunity_id: string
          organization_id: string
          prior_quote_status: string | null
          prior_request_status: string | null
          reason: string | null
          reopen_explanation: string | null
          restores_event_id: string | null
        }
        Insert: {
          actor_user_id?: string | null
          created_at?: string
          event_type: string
          id?: string
          idempotency_key: string
          note?: string | null
          occurred_at?: string
          opportunity_id: string
          organization_id: string
          prior_quote_status?: string | null
          prior_request_status?: string | null
          reason?: string | null
          reopen_explanation?: string | null
          restores_event_id?: string | null
        }
        Update: {
          actor_user_id?: string | null
          created_at?: string
          event_type?: string
          id?: string
          idempotency_key?: string
          note?: string | null
          occurred_at?: string
          opportunity_id?: string
          organization_id?: string
          prior_quote_status?: string | null
          prior_request_status?: string | null
          reason?: string | null
          reopen_explanation?: string | null
          restores_event_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "opportunity_outcome_events_opportunity_fk"
            columns: ["organization_id", "opportunity_id"]
            isOneToOne: false
            referencedRelation: "opportunities"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "opportunity_outcome_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "opportunity_outcome_events_restores_fk"
            columns: ["organization_id", "restores_event_id"]
            isOneToOne: false
            referencedRelation: "opportunity_outcome_events"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      opportunity_stage_events: {
        Row: {
          actor_user_id: string | null
          from_stage: string | null
          id: string
          occurred_at: string
          opportunity_id: string
          organization_id: string
          to_stage: string
        }
        Insert: {
          actor_user_id?: string | null
          from_stage?: string | null
          id?: string
          occurred_at?: string
          opportunity_id: string
          organization_id: string
          to_stage: string
        }
        Update: {
          actor_user_id?: string | null
          from_stage?: string | null
          id?: string
          occurred_at?: string
          opportunity_id?: string
          organization_id?: string
          to_stage?: string
        }
        Relationships: [
          {
            foreignKeyName: "opportunity_stage_events_opportunity_fk"
            columns: ["organization_id", "opportunity_id"]
            isOneToOne: false
            referencedRelation: "opportunities"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "opportunity_stage_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_billing_accounts: {
        Row: {
          created_at: string
          organization_id: string
          paid_through_date: string | null
          paid_through_source: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          organization_id: string
          paid_through_date?: string | null
          paid_through_source?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          organization_id?: string
          paid_through_date?: string | null
          paid_through_source?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_billing_accounts_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: true
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_business_hours: {
        Row: {
          closes_at: string | null
          created_at: string
          is_open: boolean
          is_open_24h: boolean
          opens_at: string | null
          organization_id: string
          period_index: number
          updated_at: string
          weekday: number
        }
        Insert: {
          closes_at?: string | null
          created_at?: string
          is_open?: boolean
          is_open_24h?: boolean
          opens_at?: string | null
          organization_id: string
          period_index?: number
          updated_at?: string
          weekday: number
        }
        Update: {
          closes_at?: string | null
          created_at?: string
          is_open?: boolean
          is_open_24h?: boolean
          opens_at?: string | null
          organization_id?: string
          period_index?: number
          updated_at?: string
          weekday?: number
        }
        Relationships: [
          {
            foreignKeyName: "organization_business_hours_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_closure_notices: {
        Row: {
          closure_record_id: string
          created_at: string
          id: string
          notice_kind: string
          outbox_delivery_id: string | null
          sent_at: string
        }
        Insert: {
          closure_record_id: string
          created_at?: string
          id?: string
          notice_kind: string
          outbox_delivery_id?: string | null
          sent_at?: string
        }
        Update: {
          closure_record_id?: string
          created_at?: string
          id?: string
          notice_kind?: string
          outbox_delivery_id?: string | null
          sent_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_closure_notices_closure_record_id_fkey"
            columns: ["closure_record_id"]
            isOneToOne: false
            referencedRelation: "organization_closure_records"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_closure_notices_outbox_delivery_id_fkey"
            columns: ["outbox_delivery_id"]
            isOneToOne: false
            referencedRelation: "platform_outbox_deliveries"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_closure_records: {
        Row: {
          created_at: string
          deadline_at: string
          id: string
          organization_id: string
          prior_lifecycle_status: string
          purge_operation_id: string | null
          purge_started_at: string | null
          reason: string
          restoration_evidence_note: string | null
          restored_at: string | null
          restored_by_owner_email: string | null
          started_at: string
          started_by_owner_email: string
          status: string
        }
        Insert: {
          created_at?: string
          deadline_at: string
          id?: string
          organization_id: string
          prior_lifecycle_status: string
          purge_operation_id?: string | null
          purge_started_at?: string | null
          reason: string
          restoration_evidence_note?: string | null
          restored_at?: string | null
          restored_by_owner_email?: string | null
          started_at?: string
          started_by_owner_email: string
          status?: string
        }
        Update: {
          created_at?: string
          deadline_at?: string
          id?: string
          organization_id?: string
          prior_lifecycle_status?: string
          purge_operation_id?: string | null
          purge_started_at?: string | null
          reason?: string
          restoration_evidence_note?: string | null
          restored_at?: string | null
          restored_by_owner_email?: string | null
          started_at?: string
          started_by_owner_email?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_closure_records_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_closure_records_purge_operation_id_fkey"
            columns: ["purge_operation_id"]
            isOneToOne: false
            referencedRelation: "organization_deletion_receipts"
            referencedColumns: ["operation_id"]
          },
        ]
      }
      organization_commercial_events: {
        Row: {
          actor_kind: string
          actor_owner_email: string | null
          amount_usd_cents: number | null
          change_after: Json | null
          change_before: Json | null
          commercial_timezone_after: string | null
          commercial_timezone_before: string | null
          created_at: string
          deadline_recalculated: boolean
          event_kind: string
          grace_ends_at_after: string | null
          id: string
          idempotency_key: string
          is_legacy_import: boolean
          occurred_at: string
          organization_id: string
          original_confirmation_id: string | null
          paid_through_after: string | null
          paid_through_before: string | null
          paid_through_effect: string
          private_reason: string | null
          private_reference: string | null
          source_event_id: string | null
          summary: string
          suspension_category: string | null
        }
        Insert: {
          actor_kind?: string
          actor_owner_email?: string | null
          amount_usd_cents?: number | null
          change_after?: Json | null
          change_before?: Json | null
          commercial_timezone_after?: string | null
          commercial_timezone_before?: string | null
          created_at?: string
          deadline_recalculated?: boolean
          event_kind: string
          grace_ends_at_after?: string | null
          id?: string
          idempotency_key: string
          is_legacy_import?: boolean
          occurred_at?: string
          organization_id: string
          original_confirmation_id?: string | null
          paid_through_after?: string | null
          paid_through_before?: string | null
          paid_through_effect: string
          private_reason?: string | null
          private_reference?: string | null
          source_event_id?: string | null
          summary: string
          suspension_category?: string | null
        }
        Update: {
          actor_kind?: string
          actor_owner_email?: string | null
          amount_usd_cents?: number | null
          change_after?: Json | null
          change_before?: Json | null
          commercial_timezone_after?: string | null
          commercial_timezone_before?: string | null
          created_at?: string
          deadline_recalculated?: boolean
          event_kind?: string
          grace_ends_at_after?: string | null
          id?: string
          idempotency_key?: string
          is_legacy_import?: boolean
          occurred_at?: string
          organization_id?: string
          original_confirmation_id?: string | null
          paid_through_after?: string | null
          paid_through_before?: string | null
          paid_through_effect?: string
          private_reason?: string | null
          private_reference?: string | null
          source_event_id?: string | null
          summary?: string
          suspension_category?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "organization_commercial_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_commercial_events_original_confirmation_id_fkey"
            columns: ["original_confirmation_id"]
            isOneToOne: false
            referencedRelation: "organization_commercial_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_commercial_events_source_event_id_fkey"
            columns: ["source_event_id"]
            isOneToOne: false
            referencedRelation: "organization_commercial_events"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_commercial_settings: {
        Row: {
          commercial_timezone: string
          created_at: string
          imported_at: string | null
          imported_operational_timezone: string | null
          organization_id: string
          timezone_source: string
          updated_at: string
        }
        Insert: {
          commercial_timezone: string
          created_at?: string
          imported_at?: string | null
          imported_operational_timezone?: string | null
          organization_id: string
          timezone_source?: string
          updated_at?: string
        }
        Update: {
          commercial_timezone?: string
          created_at?: string
          imported_at?: string | null
          imported_operational_timezone?: string | null
          organization_id?: string
          timezone_source?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_commercial_settings_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: true
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_commercial_state: {
        Row: {
          created_at: string
          grace_basis_timezone: string | null
          grace_ends_at: string | null
          last_event_id: string | null
          organization_id: string
          paid_through_date: string | null
          paid_through_source: string | null
          state_version: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          grace_basis_timezone?: string | null
          grace_ends_at?: string | null
          last_event_id?: string | null
          organization_id: string
          paid_through_date?: string | null
          paid_through_source?: string | null
          state_version?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          grace_basis_timezone?: string | null
          grace_ends_at?: string | null
          last_event_id?: string | null
          organization_id?: string
          paid_through_date?: string | null
          paid_through_source?: string | null
          state_version?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_commercial_state_last_event_id_fkey"
            columns: ["last_event_id"]
            isOneToOne: false
            referencedRelation: "organization_commercial_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_commercial_state_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: true
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_deletion_receipts: {
        Row: {
          completed_at: string | null
          component_results: Json
          created_at: string
          initiated_at: string
          operation_id: string
          pending_auth_user_ids: string[] | null
          pending_provider_resources: Json | null
          retry_count: number
          status: string
          trigger_kind: string
        }
        Insert: {
          completed_at?: string | null
          component_results?: Json
          created_at?: string
          initiated_at?: string
          operation_id?: string
          pending_auth_user_ids?: string[] | null
          pending_provider_resources?: Json | null
          retry_count?: number
          status?: string
          trigger_kind: string
        }
        Update: {
          completed_at?: string | null
          component_results?: Json
          created_at?: string
          initiated_at?: string
          operation_id?: string
          pending_auth_user_ids?: string[] | null
          pending_provider_resources?: Json | null
          retry_count?: number
          status?: string
          trigger_kind?: string
        }
        Relationships: []
      }
      organization_feature_overrides: {
        Row: {
          actor_owner_email: string | null
          created_at: string
          expires_at: string | null
          feature_key: string
          is_legacy_import: boolean
          organization_id: string
          override_state: string
          reason: string | null
          starts_at: string
          updated_at: string
        }
        Insert: {
          actor_owner_email?: string | null
          created_at?: string
          expires_at?: string | null
          feature_key: string
          is_legacy_import?: boolean
          organization_id: string
          override_state: string
          reason?: string | null
          starts_at?: string
          updated_at?: string
        }
        Update: {
          actor_owner_email?: string | null
          created_at?: string
          expires_at?: string | null
          feature_key?: string
          is_legacy_import?: boolean
          organization_id?: string
          override_state?: string
          reason?: string | null
          starts_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_feature_overrides_feature_key_fkey"
            columns: ["feature_key"]
            isOneToOne: false
            referencedRelation: "features"
            referencedColumns: ["feature_key"]
          },
          {
            foreignKeyName: "organization_feature_overrides_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_free_access_events: {
        Row: {
          access_until_date: string | null
          action: string
          actor_kind: string
          actor_owner_email: string | null
          created_at: string
          id: string
          occurred_at: string
          organization_id: string
          package_version_id: string
          reason: string
          starts_at: string
          target_grant_id: string | null
        }
        Insert: {
          access_until_date?: string | null
          action: string
          actor_kind?: string
          actor_owner_email?: string | null
          created_at?: string
          id?: string
          occurred_at?: string
          organization_id: string
          package_version_id: string
          reason: string
          starts_at: string
          target_grant_id?: string | null
        }
        Update: {
          access_until_date?: string | null
          action?: string
          actor_kind?: string
          actor_owner_email?: string | null
          created_at?: string
          id?: string
          occurred_at?: string
          organization_id?: string
          package_version_id?: string
          reason?: string
          starts_at?: string
          target_grant_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "organization_free_access_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_free_access_events_package_version_id_fkey"
            columns: ["package_version_id"]
            isOneToOne: false
            referencedRelation: "platform_package_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_free_access_events_target_grant_id_fkey"
            columns: ["target_grant_id"]
            isOneToOne: false
            referencedRelation: "organization_free_access_events"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_limit_overrides: {
        Row: {
          actor_owner_email: string | null
          created_at: string
          expires_at: string | null
          is_legacy_import: boolean
          is_unlimited: boolean
          limit_key: string
          limit_state: string
          limit_value: number | null
          organization_id: string
          reason: string | null
          starts_at: string
          updated_at: string
        }
        Insert: {
          actor_owner_email?: string | null
          created_at?: string
          expires_at?: string | null
          is_legacy_import?: boolean
          is_unlimited?: boolean
          limit_key: string
          limit_state?: string
          limit_value?: number | null
          organization_id: string
          reason?: string | null
          starts_at?: string
          updated_at?: string
        }
        Update: {
          actor_owner_email?: string | null
          created_at?: string
          expires_at?: string | null
          is_legacy_import?: boolean
          is_unlimited?: boolean
          limit_key?: string
          limit_state?: string
          limit_value?: number | null
          organization_id?: string
          reason?: string | null
          starts_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_limit_overrides_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_member_access_events: {
        Row: {
          actor_kind: string
          actor_user_id: string | null
          created_at: string
          event_type: string
          id: string
          organization_id: string
          subject_invitation_id: string | null
          subject_user_id: string | null
          summary: Json
        }
        Insert: {
          actor_kind: string
          actor_user_id?: string | null
          created_at?: string
          event_type: string
          id?: string
          organization_id: string
          subject_invitation_id?: string | null
          subject_user_id?: string | null
          summary?: Json
        }
        Update: {
          actor_kind?: string
          actor_user_id?: string | null
          created_at?: string
          event_type?: string
          id?: string
          organization_id?: string
          subject_invitation_id?: string | null
          subject_user_id?: string | null
          summary?: Json
        }
        Relationships: [
          {
            foreignKeyName: "organization_member_access_events_event_type_fkey"
            columns: ["event_type"]
            isOneToOne: false
            referencedRelation: "member_access_event_shapes"
            referencedColumns: ["event_type"]
          },
          {
            foreignKeyName: "organization_member_access_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_member_access_events_subject_invitation_id_fkey"
            columns: ["subject_invitation_id"]
            isOneToOne: false
            referencedRelation: "organization_member_invitations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_member_invitations: {
        Row: {
          accepted_at: string | null
          auth_attempt_nonce: string | null
          auth_attempt_started_at: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          expires_at: string | null
          id: string
          identity_cleanup_error: string | null
          identity_cleanup_state: string
          invited_by: string | null
          invited_email: string
          invited_user_id: string | null
          last_delivery_error: string | null
          last_sent_at: string | null
          lease_expires_at: string | null
          lease_nonce: string | null
          organization_id: string
          password_set_at: string | null
          reconciliation_lease_expires_at: string | null
          reconciliation_nonce: string | null
          requested_permission_overrides: Json
          role: string
          state: string
          token_hash: string | null
        }
        Insert: {
          accepted_at?: string | null
          auth_attempt_nonce?: string | null
          auth_attempt_started_at?: string | null
          cancelled_at?: string | null
          cancelled_by?: string | null
          created_at?: string
          expires_at?: string | null
          id?: string
          identity_cleanup_error?: string | null
          identity_cleanup_state?: string
          invited_by?: string | null
          invited_email: string
          invited_user_id?: string | null
          last_delivery_error?: string | null
          last_sent_at?: string | null
          lease_expires_at?: string | null
          lease_nonce?: string | null
          organization_id: string
          password_set_at?: string | null
          reconciliation_lease_expires_at?: string | null
          reconciliation_nonce?: string | null
          requested_permission_overrides?: Json
          role: string
          state?: string
          token_hash?: string | null
        }
        Update: {
          accepted_at?: string | null
          auth_attempt_nonce?: string | null
          auth_attempt_started_at?: string | null
          cancelled_at?: string | null
          cancelled_by?: string | null
          created_at?: string
          expires_at?: string | null
          id?: string
          identity_cleanup_error?: string | null
          identity_cleanup_state?: string
          invited_by?: string | null
          invited_email?: string
          invited_user_id?: string | null
          last_delivery_error?: string | null
          last_sent_at?: string | null
          lease_expires_at?: string | null
          lease_nonce?: string | null
          organization_id?: string
          password_set_at?: string | null
          reconciliation_lease_expires_at?: string | null
          reconciliation_nonce?: string | null
          requested_permission_overrides?: Json
          role?: string
          state?: string
          token_hash?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "organization_member_invitations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_member_permission_overrides: {
        Row: {
          access_scope: string
          created_at: string
          organization_id: string
          override_state: string
          permission_key: string
          updated_at: string
          user_id: string
        }
        Insert: {
          access_scope?: string
          created_at?: string
          organization_id: string
          override_state: string
          permission_key: string
          updated_at?: string
          user_id: string
        }
        Update: {
          access_scope?: string
          created_at?: string
          organization_id?: string
          override_state?: string
          permission_key?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_member_permission_overrides_member_fk"
            columns: ["organization_id", "user_id"]
            isOneToOne: false
            referencedRelation: "organization_members"
            referencedColumns: ["organization_id", "user_id"]
          },
          {
            foreignKeyName: "organization_member_permission_overrides_permission_key_fkey"
            columns: ["permission_key"]
            isOneToOne: false
            referencedRelation: "permissions"
            referencedColumns: ["key"]
          },
        ]
      }
      organization_members: {
        Row: {
          access_revision: number
          created_at: string
          deactivated_at: string | null
          display_name_at_removal: string | null
          identity_cleanup_error: string | null
          identity_cleanup_state: string
          job_title: string | null
          organization_id: string
          profile_revision: number
          removed_at: string | null
          role: string
          schedule_color: string | null
          status: string
          status_changed_at: string | null
          status_changed_by: string | null
          user_id: string
          work_phone: string | null
        }
        Insert: {
          access_revision?: number
          created_at?: string
          deactivated_at?: string | null
          display_name_at_removal?: string | null
          identity_cleanup_error?: string | null
          identity_cleanup_state?: string
          job_title?: string | null
          organization_id: string
          profile_revision?: number
          removed_at?: string | null
          role?: string
          schedule_color?: string | null
          status?: string
          status_changed_at?: string | null
          status_changed_by?: string | null
          user_id: string
          work_phone?: string | null
        }
        Update: {
          access_revision?: number
          created_at?: string
          deactivated_at?: string | null
          display_name_at_removal?: string | null
          identity_cleanup_error?: string | null
          identity_cleanup_state?: string
          job_title?: string | null
          organization_id?: string
          profile_revision?: number
          removed_at?: string | null
          role?: string
          schedule_color?: string | null
          status?: string
          status_changed_at?: string | null
          status_changed_by?: string | null
          user_id?: string
          work_phone?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "organization_members_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_ownership_transfers: {
        Row: {
          from_user_id: string
          id: string
          organization_id: string
          requested_at: string
          resolved_at: string | null
          resolved_by: string | null
          state: string
          to_user_id: string
        }
        Insert: {
          from_user_id: string
          id?: string
          organization_id: string
          requested_at?: string
          resolved_at?: string | null
          resolved_by?: string | null
          state?: string
          to_user_id: string
        }
        Update: {
          from_user_id?: string
          id?: string
          organization_id?: string
          requested_at?: string
          resolved_at?: string | null
          resolved_by?: string | null
          state?: string
          to_user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_ownership_transfers_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_package_assignments: {
        Row: {
          assignment_source: string
          created_at: string
          effective_at: string
          id: string
          organization_id: string
          package_version_id: string
          reason: string
        }
        Insert: {
          assignment_source: string
          created_at?: string
          effective_at?: string
          id?: string
          organization_id: string
          package_version_id: string
          reason: string
        }
        Update: {
          assignment_source?: string
          created_at?: string
          effective_at?: string
          id?: string
          organization_id?: string
          package_version_id?: string
          reason?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_package_assignments_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_package_assignments_package_version_id_fkey"
            columns: ["package_version_id"]
            isOneToOne: false
            referencedRelation: "platform_package_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_payment_confirmations: {
        Row: {
          amount_usd_cents: number
          confirmed_at: string
          created_at: string
          currency: string
          id: string
          mismatch_reason: string | null
          organization_id: string
          paid_through_date: string
          payment_kind: string
          private_reference: string
        }
        Insert: {
          amount_usd_cents: number
          confirmed_at?: string
          created_at?: string
          currency?: string
          id?: string
          mismatch_reason?: string | null
          organization_id: string
          paid_through_date: string
          payment_kind: string
          private_reference: string
        }
        Update: {
          amount_usd_cents?: number
          confirmed_at?: string
          created_at?: string
          currency?: string
          id?: string
          mismatch_reason?: string | null
          organization_id?: string
          paid_through_date?: string
          payment_kind?: string
          private_reference?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_payment_confirmations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_quote_counters: {
        Row: {
          next_quote_number: number
          organization_id: string
          updated_at: string
        }
        Insert: {
          next_quote_number?: number
          organization_id: string
          updated_at?: string
        }
        Update: {
          next_quote_number?: number
          organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_quote_counters_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: true
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_quote_target_margin: {
        Row: {
          created_at: string
          organization_id: string
          revision: number
          target_margin_basis_points: number | null
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          organization_id: string
          revision?: number
          target_margin_basis_points?: number | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          organization_id?: string
          revision?: number
          target_margin_basis_points?: number | null
          updated_at?: string | null
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "organization_quote_target_margin_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: true
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_safe_events: {
        Row: {
          commercial_event_id: string
          created_at: string
          id: string
          occurred_at: string
          organization_id: string
          safe_kind: string
          safe_payload: Json
        }
        Insert: {
          commercial_event_id: string
          created_at?: string
          id?: string
          occurred_at?: string
          organization_id: string
          safe_kind: string
          safe_payload?: Json
        }
        Update: {
          commercial_event_id?: string
          created_at?: string
          id?: string
          occurred_at?: string
          organization_id?: string
          safe_kind?: string
          safe_payload?: Json
        }
        Relationships: [
          {
            foreignKeyName: "organization_safe_events_commercial_event_id_fkey"
            columns: ["commercial_event_id"]
            isOneToOne: true
            referencedRelation: "organization_commercial_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_safe_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_settings: {
        Row: {
          address_is_public: boolean
          address_line1: string | null
          address_line2: string | null
          brand_color: string | null
          branding_revision: number
          branding_updated_at: string | null
          branding_updated_by: string | null
          city: string | null
          country_code: string | null
          created_at: string
          currency_code: string
          currency_confirmed_at: string | null
          description: string | null
          hours_mode: string
          hours_revision: number
          hours_updated_at: string | null
          hours_updated_by: string | null
          locale: string
          logo_object_key: string | null
          organization_id: string
          phone: string | null
          pipeline_detailed_assessment_stages: boolean
          pipeline_revision: number
          pipeline_updated_at: string | null
          pipeline_updated_by: string | null
          postal_code: string | null
          profile_revision: number
          profile_updated_at: string | null
          profile_updated_by: string | null
          quote_representative_enabled: boolean
          quote_representative_name: string | null
          quote_representative_revision: number
          quote_representative_signature_object_key: string | null
          quote_representative_title: string | null
          quote_representative_updated_at: string | null
          quote_representative_updated_by: string | null
          quote_require_customer_signature: boolean
          quote_signature_policy_revision: number
          quote_signature_policy_updated_at: string | null
          quote_signature_policy_updated_by: string | null
          quote_terms: string | null
          quote_terms_revision: number
          quote_terms_updated_at: string | null
          quote_terms_updated_by: string | null
          region: string | null
          tax_default_rate_id: string | null
          tax_default_source: string
          tax_revision: number
          tax_updated_at: string | null
          tax_updated_by: string | null
          timezone: string
          timezone_confirmed_at: string | null
          trade: string | null
          updated_at: string
          website: string | null
        }
        Insert: {
          address_is_public?: boolean
          address_line1?: string | null
          address_line2?: string | null
          brand_color?: string | null
          branding_revision?: number
          branding_updated_at?: string | null
          branding_updated_by?: string | null
          city?: string | null
          country_code?: string | null
          created_at?: string
          currency_code?: string
          currency_confirmed_at?: string | null
          description?: string | null
          hours_mode?: string
          hours_revision?: number
          hours_updated_at?: string | null
          hours_updated_by?: string | null
          locale?: string
          logo_object_key?: string | null
          organization_id: string
          phone?: string | null
          pipeline_detailed_assessment_stages?: boolean
          pipeline_revision?: number
          pipeline_updated_at?: string | null
          pipeline_updated_by?: string | null
          postal_code?: string | null
          profile_revision?: number
          profile_updated_at?: string | null
          profile_updated_by?: string | null
          quote_representative_enabled?: boolean
          quote_representative_name?: string | null
          quote_representative_revision?: number
          quote_representative_signature_object_key?: string | null
          quote_representative_title?: string | null
          quote_representative_updated_at?: string | null
          quote_representative_updated_by?: string | null
          quote_require_customer_signature?: boolean
          quote_signature_policy_revision?: number
          quote_signature_policy_updated_at?: string | null
          quote_signature_policy_updated_by?: string | null
          quote_terms?: string | null
          quote_terms_revision?: number
          quote_terms_updated_at?: string | null
          quote_terms_updated_by?: string | null
          region?: string | null
          tax_default_rate_id?: string | null
          tax_default_source?: string
          tax_revision?: number
          tax_updated_at?: string | null
          tax_updated_by?: string | null
          timezone?: string
          timezone_confirmed_at?: string | null
          trade?: string | null
          updated_at?: string
          website?: string | null
        }
        Update: {
          address_is_public?: boolean
          address_line1?: string | null
          address_line2?: string | null
          brand_color?: string | null
          branding_revision?: number
          branding_updated_at?: string | null
          branding_updated_by?: string | null
          city?: string | null
          country_code?: string | null
          created_at?: string
          currency_code?: string
          currency_confirmed_at?: string | null
          description?: string | null
          hours_mode?: string
          hours_revision?: number
          hours_updated_at?: string | null
          hours_updated_by?: string | null
          locale?: string
          logo_object_key?: string | null
          organization_id?: string
          phone?: string | null
          pipeline_detailed_assessment_stages?: boolean
          pipeline_revision?: number
          pipeline_updated_at?: string | null
          pipeline_updated_by?: string | null
          postal_code?: string | null
          profile_revision?: number
          profile_updated_at?: string | null
          profile_updated_by?: string | null
          quote_representative_enabled?: boolean
          quote_representative_name?: string | null
          quote_representative_revision?: number
          quote_representative_signature_object_key?: string | null
          quote_representative_title?: string | null
          quote_representative_updated_at?: string | null
          quote_representative_updated_by?: string | null
          quote_require_customer_signature?: boolean
          quote_signature_policy_revision?: number
          quote_signature_policy_updated_at?: string | null
          quote_signature_policy_updated_by?: string | null
          quote_terms?: string | null
          quote_terms_revision?: number
          quote_terms_updated_at?: string | null
          quote_terms_updated_by?: string | null
          region?: string | null
          tax_default_rate_id?: string | null
          tax_default_source?: string
          tax_revision?: number
          tax_updated_at?: string | null
          tax_updated_by?: string | null
          timezone?: string
          timezone_confirmed_at?: string | null
          trade?: string | null
          updated_at?: string
          website?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "organization_settings_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: true
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_settings_tax_default_rate_id_fkey"
            columns: ["tax_default_rate_id"]
            isOneToOne: false
            referencedRelation: "organization_tax_rates"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_settings_audit: {
        Row: {
          actor_user_id: string | null
          changed_fields: string[]
          created_at: string
          id: string
          organization_id: string
          section: string
        }
        Insert: {
          actor_user_id?: string | null
          changed_fields: string[]
          created_at?: string
          id?: string
          organization_id: string
          section: string
        }
        Update: {
          actor_user_id?: string | null
          changed_fields?: string[]
          created_at?: string
          id?: string
          organization_id?: string
          section?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_settings_audit_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organization_tax_rates: {
        Row: {
          created_at: string
          created_by: string | null
          id: string
          is_active: boolean
          name: string
          organization_id: string
          rate_basis_points: number
          revision: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id?: string
          is_active?: boolean
          name: string
          organization_id: string
          rate_basis_points: number
          revision?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: string
          is_active?: boolean
          name?: string
          organization_id?: string
          rate_basis_points?: number
          revision?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "organization_tax_rates_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organizations: {
        Row: {
          created_at: string
          id: string
          lifecycle_status: string
          name: string
          package_key: string
          scheduled_package_effective_at: string | null
          scheduled_package_key: string | null
          slug: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          lifecycle_status?: string
          name: string
          package_key?: string
          scheduled_package_effective_at?: string | null
          scheduled_package_key?: string | null
          slug: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          lifecycle_status?: string
          name?: string
          package_key?: string
          scheduled_package_effective_at?: string | null
          scheduled_package_key?: string | null
          slug?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organizations_package_key_fkey"
            columns: ["package_key"]
            isOneToOne: false
            referencedRelation: "platform_packages"
            referencedColumns: ["package_key"]
          },
          {
            foreignKeyName: "organizations_scheduled_package_key_fkey"
            columns: ["scheduled_package_key"]
            isOneToOne: false
            referencedRelation: "platform_packages"
            referencedColumns: ["package_key"]
          },
        ]
      }
      package_features: {
        Row: {
          created_at: string
          feature_key: string
          package_key: string
        }
        Insert: {
          created_at?: string
          feature_key: string
          package_key: string
        }
        Update: {
          created_at?: string
          feature_key?: string
          package_key?: string
        }
        Relationships: [
          {
            foreignKeyName: "package_features_feature_key_fkey"
            columns: ["feature_key"]
            isOneToOne: false
            referencedRelation: "features"
            referencedColumns: ["feature_key"]
          },
          {
            foreignKeyName: "package_features_package_key_fkey"
            columns: ["package_key"]
            isOneToOne: false
            referencedRelation: "platform_packages"
            referencedColumns: ["package_key"]
          },
        ]
      }
      package_limits: {
        Row: {
          created_at: string
          is_unlimited: boolean
          limit_key: string
          limit_value: number | null
          package_key: string
        }
        Insert: {
          created_at?: string
          is_unlimited?: boolean
          limit_key: string
          limit_value?: number | null
          package_key: string
        }
        Update: {
          created_at?: string
          is_unlimited?: boolean
          limit_key?: string
          limit_value?: number | null
          package_key?: string
        }
        Relationships: [
          {
            foreignKeyName: "package_limits_package_key_fkey"
            columns: ["package_key"]
            isOneToOne: false
            referencedRelation: "platform_packages"
            referencedColumns: ["package_key"]
          },
        ]
      }
      permissions: {
        Row: {
          created_at: string
          description: string
          key: string
          scope_model: string
        }
        Insert: {
          created_at?: string
          description: string
          key: string
          scope_model?: string
        }
        Update: {
          created_at?: string
          description?: string
          key?: string
          scope_model?: string
        }
        Relationships: []
      }
      platform_email_template_packages: {
        Row: {
          created_at: string
          package_key: string
          template_id: string
        }
        Insert: {
          created_at?: string
          package_key: string
          template_id: string
        }
        Update: {
          created_at?: string
          package_key?: string
          template_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "platform_email_template_packages_package_key_fkey"
            columns: ["package_key"]
            isOneToOne: false
            referencedRelation: "platform_packages"
            referencedColumns: ["package_key"]
          },
          {
            foreignKeyName: "platform_email_template_packages_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "platform_email_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      platform_email_templates: {
        Row: {
          body: string
          created_at: string
          folder: string | null
          id: string
          name: string
          subject: string
          updated_at: string
          version: number
        }
        Insert: {
          body: string
          created_at?: string
          folder?: string | null
          id?: string
          name: string
          subject: string
          updated_at?: string
          version?: number
        }
        Update: {
          body?: string
          created_at?: string
          folder?: string | null
          id?: string
          name?: string
          subject?: string
          updated_at?: string
          version?: number
        }
        Relationships: []
      }
      platform_message_template_versions: {
        Row: {
          body: string
          id: string
          published_at: string
          published_by_owner_email: string
          subject: string | null
          template_key: string
          version: number
        }
        Insert: {
          body: string
          id?: string
          published_at?: string
          published_by_owner_email: string
          subject?: string | null
          template_key: string
          version: number
        }
        Update: {
          body?: string
          id?: string
          published_at?: string
          published_by_owner_email?: string
          subject?: string | null
          template_key?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "platform_message_template_versions_template_key_fkey"
            columns: ["template_key"]
            isOneToOne: false
            referencedRelation: "platform_message_templates"
            referencedColumns: ["template_key"]
          },
        ]
      }
      platform_message_templates: {
        Row: {
          body_draft: string
          body_published: string | null
          created_at: string
          published_at: string | null
          published_by_owner_email: string | null
          published_version: number
          subject_draft: string | null
          subject_published: string | null
          template_key: string
          updated_at: string
        }
        Insert: {
          body_draft?: string
          body_published?: string | null
          created_at?: string
          published_at?: string | null
          published_by_owner_email?: string | null
          published_version?: number
          subject_draft?: string | null
          subject_published?: string | null
          template_key: string
          updated_at?: string
        }
        Update: {
          body_draft?: string
          body_published?: string | null
          created_at?: string
          published_at?: string | null
          published_by_owner_email?: string | null
          published_version?: number
          subject_draft?: string | null
          subject_published?: string | null
          template_key?: string
          updated_at?: string
        }
        Relationships: []
      }
      platform_onboarding_application_corrections: {
        Row: {
          actor_owner_email: string
          after_state: Json
          application_id: string
          before_state: Json
          created_at: string
          id: string
          reason: string
        }
        Insert: {
          actor_owner_email: string
          after_state: Json
          application_id: string
          before_state: Json
          created_at?: string
          id?: string
          reason: string
        }
        Update: {
          actor_owner_email?: string
          after_state?: Json
          application_id?: string
          before_state?: Json
          created_at?: string
          id?: string
          reason?: string
        }
        Relationships: [
          {
            foreignKeyName: "platform_onboarding_application_corrections_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "platform_onboarding_applications"
            referencedColumns: ["id"]
          },
        ]
      }
      platform_onboarding_application_payment_confirmations: {
        Row: {
          actor_owner_email: string
          amount_usd_cents: number
          application_id: string
          confirmed_at: string
          created_at: string
          currency: string
          id: string
          mismatch_reason: string | null
          package_version_id: string
          private_reference: string
        }
        Insert: {
          actor_owner_email: string
          amount_usd_cents: number
          application_id: string
          confirmed_at?: string
          created_at?: string
          currency?: string
          id?: string
          mismatch_reason?: string | null
          package_version_id: string
          private_reference: string
        }
        Update: {
          actor_owner_email?: string
          amount_usd_cents?: number
          application_id?: string
          confirmed_at?: string
          created_at?: string
          currency?: string
          id?: string
          mismatch_reason?: string | null
          package_version_id?: string
          private_reference?: string
        }
        Relationships: [
          {
            foreignKeyName: "platform_onboarding_application_payment_con_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "platform_onboarding_applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "platform_onboarding_application_payment_package_version_id_fkey"
            columns: ["package_version_id"]
            isOneToOne: false
            referencedRelation: "platform_package_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      platform_onboarding_application_payment_reversals: {
        Row: {
          actor_owner_email: string
          application_id: string
          confirmation_id: string
          created_at: string
          id: string
          reason: string
          reversed_amount_usd_cents: number
          reversed_at: string
        }
        Insert: {
          actor_owner_email: string
          application_id: string
          confirmation_id: string
          created_at?: string
          id?: string
          reason: string
          reversed_amount_usd_cents: number
          reversed_at?: string
        }
        Update: {
          actor_owner_email?: string
          application_id?: string
          confirmation_id?: string
          created_at?: string
          id?: string
          reason?: string
          reversed_amount_usd_cents?: number
          reversed_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "platform_onboarding_application_payment_re_confirmation_id_fkey"
            columns: ["confirmation_id"]
            isOneToOne: false
            referencedRelation: "platform_onboarding_application_payment_confirmations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "platform_onboarding_application_payment_rev_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "platform_onboarding_applications"
            referencedColumns: ["id"]
          },
        ]
      }
      platform_onboarding_application_provisions: {
        Row: {
          administrator_user_id: string | null
          application_id: string
          attempt_count: number
          created_at: string
          last_error: string | null
          organization_id: string | null
          status: string
          updated_at: string
        }
        Insert: {
          administrator_user_id?: string | null
          application_id: string
          attempt_count?: number
          created_at?: string
          last_error?: string | null
          organization_id?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          administrator_user_id?: string | null
          application_id?: string
          attempt_count?: number
          created_at?: string
          last_error?: string | null
          organization_id?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "platform_onboarding_application_provisions_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: true
            referencedRelation: "platform_onboarding_applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "platform_onboarding_application_provisions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      platform_onboarding_application_setup_links: {
        Row: {
          administrator_user_id: string
          application_id: string
          consumed_at: string | null
          created_at: string
          expires_at: string
          intended_email: string
          last_error: string | null
          last_sent_at: string
          rendered_body: string | null
          rendered_subject: string | null
          token_hash: string
          updated_at: string
        }
        Insert: {
          administrator_user_id: string
          application_id: string
          consumed_at?: string | null
          created_at?: string
          expires_at: string
          intended_email: string
          last_error?: string | null
          last_sent_at?: string
          rendered_body?: string | null
          rendered_subject?: string | null
          token_hash: string
          updated_at?: string
        }
        Update: {
          administrator_user_id?: string
          application_id?: string
          consumed_at?: string | null
          created_at?: string
          expires_at?: string
          intended_email?: string
          last_error?: string | null
          last_sent_at?: string
          rendered_body?: string | null
          rendered_subject?: string | null
          token_hash?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "platform_onboarding_application_setup_links_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: true
            referencedRelation: "platform_onboarding_applications"
            referencedColumns: ["id"]
          },
        ]
      }
      platform_onboarding_application_submissions: {
        Row: {
          agreement_accepted_at: string
          application_id: string
          id: string
          package_snapshot: Json
          privacy_policy_version: string
          submitted_at: string
          submitted_data: Json
        }
        Insert: {
          agreement_accepted_at: string
          application_id: string
          id?: string
          package_snapshot: Json
          privacy_policy_version: string
          submitted_at?: string
          submitted_data: Json
        }
        Update: {
          agreement_accepted_at?: string
          application_id?: string
          id?: string
          package_snapshot?: Json
          privacy_policy_version?: string
          submitted_at?: string
          submitted_data?: Json
        }
        Relationships: [
          {
            foreignKeyName: "platform_onboarding_application_submissions_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: true
            referencedRelation: "platform_onboarding_applications"
            referencedColumns: ["id"]
          },
        ]
      }
      platform_onboarding_applications: {
        Row: {
          business_name: string
          city_country: string
          duplicate_acknowledged_at: string | null
          duplicate_acknowledged_by_owner_email: string | null
          id: string
          initial_administrator_email: string | null
          initial_administrator_name: string | null
          main_contact_email: string
          main_contact_name: string
          main_contact_phone: string
          not_proceeding_at: string | null
          note: string | null
          package_snapshot: Json
          package_version_id: string
          payment_reversed_at: string | null
          personal_data_purge_after: string
          possible_duplicate: boolean
          stage: string
          submitted_at: string
          time_zone: string
          trade: string
          updated_at: string
        }
        Insert: {
          business_name: string
          city_country: string
          duplicate_acknowledged_at?: string | null
          duplicate_acknowledged_by_owner_email?: string | null
          id?: string
          initial_administrator_email?: string | null
          initial_administrator_name?: string | null
          main_contact_email: string
          main_contact_name: string
          main_contact_phone: string
          not_proceeding_at?: string | null
          note?: string | null
          package_snapshot: Json
          package_version_id: string
          payment_reversed_at?: string | null
          personal_data_purge_after?: string
          possible_duplicate?: boolean
          stage?: string
          submitted_at?: string
          time_zone: string
          trade: string
          updated_at?: string
        }
        Update: {
          business_name?: string
          city_country?: string
          duplicate_acknowledged_at?: string | null
          duplicate_acknowledged_by_owner_email?: string | null
          id?: string
          initial_administrator_email?: string | null
          initial_administrator_name?: string | null
          main_contact_email?: string
          main_contact_name?: string
          main_contact_phone?: string
          not_proceeding_at?: string | null
          note?: string | null
          package_snapshot?: Json
          package_version_id?: string
          payment_reversed_at?: string | null
          personal_data_purge_after?: string
          possible_duplicate?: boolean
          stage?: string
          submitted_at?: string
          time_zone?: string
          trade?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "platform_onboarding_applications_package_version_id_fkey"
            columns: ["package_version_id"]
            isOneToOne: false
            referencedRelation: "platform_package_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      platform_operation_attempts: {
        Row: {
          acknowledged_at: string | null
          acknowledged_by_owner_email: string | null
          attempt_count: number
          correlation_id: string
          created_at: string
          id: string
          idempotency_key: string
          last_error: string | null
          next_retry_at: string | null
          operation_type: string
          resolution_note: string | null
          resolved_at: string | null
          resolved_by_owner_email: string | null
          status: string
          target_id: string | null
          target_kind: string
          updated_at: string
        }
        Insert: {
          acknowledged_at?: string | null
          acknowledged_by_owner_email?: string | null
          attempt_count?: number
          correlation_id?: string
          created_at?: string
          id?: string
          idempotency_key: string
          last_error?: string | null
          next_retry_at?: string | null
          operation_type: string
          resolution_note?: string | null
          resolved_at?: string | null
          resolved_by_owner_email?: string | null
          status?: string
          target_id?: string | null
          target_kind: string
          updated_at?: string
        }
        Update: {
          acknowledged_at?: string | null
          acknowledged_by_owner_email?: string | null
          attempt_count?: number
          correlation_id?: string
          created_at?: string
          id?: string
          idempotency_key?: string
          last_error?: string | null
          next_retry_at?: string | null
          operation_type?: string
          resolution_note?: string | null
          resolved_at?: string | null
          resolved_by_owner_email?: string | null
          status?: string
          target_id?: string | null
          target_kind?: string
          updated_at?: string
        }
        Relationships: []
      }
      platform_outbox_deliveries: {
        Row: {
          attempt_count: number
          channel: string
          correlation_id: string
          created_at: string
          id: string
          idempotency_key: string
          last_error: string | null
          next_attempt_at: string
          payload: Json
          recipient_email: string
          sent_at: string | null
          status: string
          target_id: string | null
          target_kind: string
          template_key: string
          updated_at: string
        }
        Insert: {
          attempt_count?: number
          channel?: string
          correlation_id?: string
          created_at?: string
          id?: string
          idempotency_key: string
          last_error?: string | null
          next_attempt_at?: string
          payload?: Json
          recipient_email: string
          sent_at?: string | null
          status?: string
          target_id?: string | null
          target_kind: string
          template_key: string
          updated_at?: string
        }
        Update: {
          attempt_count?: number
          channel?: string
          correlation_id?: string
          created_at?: string
          id?: string
          idempotency_key?: string
          last_error?: string | null
          next_attempt_at?: string
          payload?: Json
          recipient_email?: string
          sent_at?: string | null
          status?: string
          target_id?: string | null
          target_kind?: string
          template_key?: string
          updated_at?: string
        }
        Relationships: []
      }
      platform_owner_audit_events: {
        Row: {
          actor_owner_email: string
          after_state: Json | null
          before_state: Json | null
          correlation_id: string
          created_at: string
          event_type: string
          id: string
          target_key: string | null
          target_type: string
        }
        Insert: {
          actor_owner_email: string
          after_state?: Json | null
          before_state?: Json | null
          correlation_id?: string
          created_at?: string
          event_type: string
          id?: string
          target_key?: string | null
          target_type: string
        }
        Update: {
          actor_owner_email?: string
          after_state?: Json | null
          before_state?: Json | null
          correlation_id?: string
          created_at?: string
          event_type?: string
          id?: string
          target_key?: string | null
          target_type?: string
        }
        Relationships: []
      }
      platform_owner_login_attempts: {
        Row: {
          correlation_id: string
          created_at: string
          id: string
          outcome: string
        }
        Insert: {
          correlation_id?: string
          created_at?: string
          id?: string
          outcome: string
        }
        Update: {
          correlation_id?: string
          created_at?: string
          id?: string
          outcome?: string
        }
        Relationships: []
      }
      platform_owner_notifications: {
        Row: {
          body: string | null
          correlation_id: string | null
          created_at: string
          id: string
          kind: string
          read_at: string | null
          severity: string
          target_id: string | null
          target_kind: string
          title: string
        }
        Insert: {
          body?: string | null
          correlation_id?: string | null
          created_at?: string
          id?: string
          kind: string
          read_at?: string | null
          severity?: string
          target_id?: string | null
          target_kind: string
          title: string
        }
        Update: {
          body?: string | null
          correlation_id?: string | null
          created_at?: string
          id?: string
          kind?: string
          read_at?: string | null
          severity?: string
          target_id?: string | null
          target_kind?: string
          title?: string
        }
        Relationships: []
      }
      platform_owner_sessions: {
        Row: {
          correlation_id: string
          created_at: string
          expires_at: string
          id: string
          owner_email: string
          revoked_at: string | null
          revoked_reason: string | null
        }
        Insert: {
          correlation_id?: string
          created_at?: string
          expires_at: string
          id?: string
          owner_email: string
          revoked_at?: string | null
          revoked_reason?: string | null
        }
        Update: {
          correlation_id?: string
          created_at?: string
          expires_at?: string
          id?: string
          owner_email?: string
          revoked_at?: string | null
          revoked_reason?: string | null
        }
        Relationships: []
      }
      platform_owner_settings: {
        Row: {
          alert_recipient_emails: string[]
          created_at: string
          id: boolean
          payment_instructions: string
          privacy_policy_url: string
          privacy_policy_version: string
          reply_to_address: string
          sender_display_name: string
          updated_at: string
        }
        Insert: {
          alert_recipient_emails?: string[]
          created_at?: string
          id?: boolean
          payment_instructions?: string
          privacy_policy_url?: string
          privacy_policy_version?: string
          reply_to_address?: string
          sender_display_name?: string
          updated_at?: string
        }
        Update: {
          alert_recipient_emails?: string[]
          created_at?: string
          id?: boolean
          payment_instructions?: string
          privacy_policy_url?: string
          privacy_policy_version?: string
          reply_to_address?: string
          sender_display_name?: string
          updated_at?: string
        }
        Relationships: []
      }
      platform_package_version_features: {
        Row: {
          created_at: string
          feature_key: string
          package_version_id: string
        }
        Insert: {
          created_at?: string
          feature_key: string
          package_version_id: string
        }
        Update: {
          created_at?: string
          feature_key?: string
          package_version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "platform_package_version_features_feature_key_fkey"
            columns: ["feature_key"]
            isOneToOne: false
            referencedRelation: "features"
            referencedColumns: ["feature_key"]
          },
          {
            foreignKeyName: "platform_package_version_features_package_version_id_fkey"
            columns: ["package_version_id"]
            isOneToOne: false
            referencedRelation: "platform_package_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      platform_package_version_limits: {
        Row: {
          created_at: string
          limit_key: string
          limit_state: string
          limit_value: number | null
          package_version_id: string
        }
        Insert: {
          created_at?: string
          limit_key: string
          limit_state: string
          limit_value?: number | null
          package_version_id: string
        }
        Update: {
          created_at?: string
          limit_key?: string
          limit_state?: string
          limit_value?: number | null
          package_version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "platform_package_version_limits_package_version_id_fkey"
            columns: ["package_version_id"]
            isOneToOne: false
            referencedRelation: "platform_package_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      platform_package_versions: {
        Row: {
          billing_period: string
          created_at: string
          currency: string
          display_name: string
          id: string
          package_id: string
          price_usd_cents: number | null
          public_description: string | null
          published_at: string | null
          retired_at: string | null
          status: string
          value_explanation: string | null
          version_number: number
        }
        Insert: {
          billing_period?: string
          created_at?: string
          currency?: string
          display_name: string
          id?: string
          package_id: string
          price_usd_cents?: number | null
          public_description?: string | null
          published_at?: string | null
          retired_at?: string | null
          status?: string
          value_explanation?: string | null
          version_number: number
        }
        Update: {
          billing_period?: string
          created_at?: string
          currency?: string
          display_name?: string
          id?: string
          package_id?: string
          price_usd_cents?: number | null
          public_description?: string | null
          published_at?: string | null
          retired_at?: string | null
          status?: string
          value_explanation?: string | null
          version_number?: number
        }
        Relationships: [
          {
            foreignKeyName: "platform_package_versions_package_id_fkey"
            columns: ["package_id"]
            isOneToOne: false
            referencedRelation: "platform_packages"
            referencedColumns: ["package_id"]
          },
        ]
      }
      platform_packages: {
        Row: {
          billing_period: string
          created_at: string
          currency: string
          display_name: string
          package_id: string
          package_key: string
          price_usd_cents: number | null
          public_description: string | null
          sort_order: number
          status: string
        }
        Insert: {
          billing_period?: string
          created_at?: string
          currency?: string
          display_name: string
          package_id?: string
          package_key: string
          price_usd_cents?: number | null
          public_description?: string | null
          sort_order: number
          status?: string
        }
        Update: {
          billing_period?: string
          created_at?: string
          currency?: string
          display_name?: string
          package_id?: string
          package_key?: string
          price_usd_cents?: number | null
          public_description?: string | null
          sort_order?: number
          status?: string
        }
        Relationships: []
      }
      platform_rate_limit_buckets: {
        Row: {
          attempt_count: number
          bucket_key: string
          window_start: string
        }
        Insert: {
          attempt_count?: number
          bucket_key: string
          window_start: string
        }
        Update: {
          attempt_count?: number
          bucket_key?: string
          window_start?: string
        }
        Relationships: []
      }
      profiles: {
        Row: {
          avatar_url: string | null
          created_at: string
          full_name: string | null
          id: string
          updated_at: string
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string
          full_name?: string | null
          id: string
          updated_at?: string
        }
        Update: {
          avatar_url?: string | null
          created_at?: string
          full_name?: string | null
          id?: string
          updated_at?: string
        }
        Relationships: []
      }
      properties: {
        Row: {
          access_notes: string | null
          address_line1: string
          address_line2: string | null
          archived_at: string | null
          city: string
          client_id: string
          country: string
          created_at: string
          deleted_at: string | null
          id: string
          is_billing_address: boolean
          is_primary: boolean
          label: string
          latitude: number | null
          longitude: number | null
          organization_id: string
          postal_code: string | null
          state_region: string | null
          tax_rate_id: string | null
          updated_at: string
        }
        Insert: {
          access_notes?: string | null
          address_line1: string
          address_line2?: string | null
          archived_at?: string | null
          city: string
          client_id: string
          country?: string
          created_at?: string
          deleted_at?: string | null
          id?: string
          is_billing_address?: boolean
          is_primary?: boolean
          label?: string
          latitude?: number | null
          longitude?: number | null
          organization_id: string
          postal_code?: string | null
          state_region?: string | null
          tax_rate_id?: string | null
          updated_at?: string
        }
        Update: {
          access_notes?: string | null
          address_line1?: string
          address_line2?: string | null
          archived_at?: string | null
          city?: string
          client_id?: string
          country?: string
          created_at?: string
          deleted_at?: string | null
          id?: string
          is_billing_address?: boolean
          is_primary?: boolean
          label?: string
          latitude?: number | null
          longitude?: number | null
          organization_id?: string
          postal_code?: string | null
          state_region?: string | null
          tax_rate_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "properties_client_id_fkey"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "properties_client_organization_fk"
            columns: ["organization_id", "client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "properties_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "properties_tax_rate_organization_fk"
            columns: ["organization_id", "tax_rate_id"]
            isOneToOne: false
            referencedRelation: "organization_tax_rates"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      property_contact_methods: {
        Row: {
          created_at: string
          id: string
          is_primary: boolean
          kind: string
          label: string | null
          normalized_value: string
          organization_id: string
          property_contact_id: string | null
          property_id: string
          updated_at: string
          value: string
        }
        Insert: {
          created_at?: string
          id?: string
          is_primary?: boolean
          kind: string
          label?: string | null
          normalized_value?: string
          organization_id: string
          property_contact_id?: string | null
          property_id: string
          updated_at?: string
          value: string
        }
        Update: {
          created_at?: string
          id?: string
          is_primary?: boolean
          kind?: string
          label?: string | null
          normalized_value?: string
          organization_id?: string
          property_contact_id?: string | null
          property_id?: string
          updated_at?: string
          value?: string
        }
        Relationships: [
          {
            foreignKeyName: "property_contact_methods_contact_organization_fk"
            columns: ["organization_id", "property_contact_id"]
            isOneToOne: false
            referencedRelation: "property_contacts"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "property_contact_methods_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "property_contact_methods_property_organization_fk"
            columns: ["organization_id", "property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      property_contacts: {
        Row: {
          created_at: string
          first_name: string | null
          id: string
          is_primary: boolean
          last_name: string | null
          organization_id: string
          property_id: string
          role_label: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          first_name?: string | null
          id?: string
          is_primary?: boolean
          last_name?: string | null
          organization_id: string
          property_id: string
          role_label?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          first_name?: string | null
          id?: string
          is_primary?: boolean
          last_name?: string | null
          organization_id?: string
          property_id?: string
          role_label?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "property_contacts_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "property_contacts_property_organization_fk"
            columns: ["organization_id", "property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      quote_access_links: {
        Row: {
          expires_at: string | null
          first_viewed_at: string | null
          id: string
          issued_at: string
          issued_by: string | null
          last_viewed_at: string | null
          organization_id: string
          quote_id: string
          quote_version_id: string
          recipient_id: string
          revoked_at: string | null
          revoked_reason: string | null
          token_hash: string
          view_count: number
        }
        Insert: {
          expires_at?: string | null
          first_viewed_at?: string | null
          id?: string
          issued_at?: string
          issued_by?: string | null
          last_viewed_at?: string | null
          organization_id: string
          quote_id: string
          quote_version_id: string
          recipient_id: string
          revoked_at?: string | null
          revoked_reason?: string | null
          token_hash: string
          view_count?: number
        }
        Update: {
          expires_at?: string | null
          first_viewed_at?: string | null
          id?: string
          issued_at?: string
          issued_by?: string | null
          last_viewed_at?: string | null
          organization_id?: string
          quote_id?: string
          quote_version_id?: string
          recipient_id?: string
          revoked_at?: string | null
          revoked_reason?: string | null
          token_hash?: string
          view_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "quote_access_links_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_access_links_recipient_fk"
            columns: ["organization_id", "quote_id", "recipient_id"]
            isOneToOne: false
            referencedRelation: "quote_recipients"
            referencedColumns: ["organization_id", "quote_id", "id"]
          },
          {
            foreignKeyName: "quote_access_links_version_fk"
            columns: ["organization_id", "quote_id", "quote_version_id"]
            isOneToOne: false
            referencedRelation: "quote_versions"
            referencedColumns: ["organization_id", "quote_id", "id"]
          },
        ]
      }
      quote_decisions: {
        Row: {
          actor_kind: string
          actor_user_id: string | null
          decided_at: string
          evidence: Json
          id: string
          is_current: boolean
          method: string
          note: string | null
          organization_id: string
          outcome: string
          quote_access_link_id: string | null
          quote_id: string
          quote_version_id: string
        }
        Insert: {
          actor_kind: string
          actor_user_id?: string | null
          decided_at?: string
          evidence?: Json
          id?: string
          is_current?: boolean
          method: string
          note?: string | null
          organization_id: string
          outcome: string
          quote_access_link_id?: string | null
          quote_id: string
          quote_version_id: string
        }
        Update: {
          actor_kind?: string
          actor_user_id?: string | null
          decided_at?: string
          evidence?: Json
          id?: string
          is_current?: boolean
          method?: string
          note?: string | null
          organization_id?: string
          outcome?: string
          quote_access_link_id?: string | null
          quote_id?: string
          quote_version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "quote_decisions_link_fk"
            columns: ["organization_id", "quote_access_link_id"]
            isOneToOne: false
            referencedRelation: "quote_access_links"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "quote_decisions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_decisions_quote_fk"
            columns: ["organization_id", "quote_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "quote_decisions_version_fk"
            columns: ["organization_id", "quote_id", "quote_version_id"]
            isOneToOne: false
            referencedRelation: "quote_versions"
            referencedColumns: ["organization_id", "quote_id", "id"]
          },
        ]
      }
      quote_deposit_events: {
        Row: {
          actor_user_id: string | null
          amount_minor: number
          created_at: string
          event_type: string
          id: string
          idempotency_key: string
          method: string
          note: string | null
          organization_id: string
          quote_id: string
          quote_version_id: string
          reference: string | null
          reversed_event_id: string | null
        }
        Insert: {
          actor_user_id?: string | null
          amount_minor: number
          created_at?: string
          event_type: string
          id?: string
          idempotency_key: string
          method: string
          note?: string | null
          organization_id: string
          quote_id: string
          quote_version_id: string
          reference?: string | null
          reversed_event_id?: string | null
        }
        Update: {
          actor_user_id?: string | null
          amount_minor?: number
          created_at?: string
          event_type?: string
          id?: string
          idempotency_key?: string
          method?: string
          note?: string | null
          organization_id?: string
          quote_id?: string
          quote_version_id?: string
          reference?: string | null
          reversed_event_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "quote_deposit_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_deposit_events_quote_fk"
            columns: ["organization_id", "quote_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "quote_deposit_events_reversed_fk"
            columns: ["organization_id", "reversed_event_id"]
            isOneToOne: false
            referencedRelation: "quote_deposit_events"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "quote_deposit_events_version_fk"
            columns: ["organization_id", "quote_id", "quote_version_id"]
            isOneToOne: false
            referencedRelation: "quote_versions"
            referencedColumns: ["organization_id", "quote_id", "id"]
          },
        ]
      }
      quote_recipients: {
        Row: {
          created_at: string
          created_by: string | null
          display_name: string
          email: string
          id: string
          organization_id: string
          quote_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          display_name: string
          email: string
          id?: string
          organization_id: string
          quote_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          display_name?: string
          email?: string
          id?: string
          organization_id?: string
          quote_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "quote_recipients_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_recipients_quote_organization_fk"
            columns: ["organization_id", "quote_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      quote_signatures: {
        Row: {
          document_hash: string
          evidence: Json
          id: string
          image_byte_size: number | null
          image_object_key: string | null
          method: string
          organization_id: string
          quote_decision_id: string
          quote_id: string
          quote_version_id: string
          signed_at: string
          signer_name: string
        }
        Insert: {
          document_hash: string
          evidence?: Json
          id?: string
          image_byte_size?: number | null
          image_object_key?: string | null
          method: string
          organization_id: string
          quote_decision_id: string
          quote_id: string
          quote_version_id: string
          signed_at?: string
          signer_name: string
        }
        Update: {
          document_hash?: string
          evidence?: Json
          id?: string
          image_byte_size?: number | null
          image_object_key?: string | null
          method?: string
          organization_id?: string
          quote_decision_id?: string
          quote_id?: string
          quote_version_id?: string
          signed_at?: string
          signer_name?: string
        }
        Relationships: [
          {
            foreignKeyName: "quote_signatures_decision_fk"
            columns: ["organization_id", "quote_decision_id"]
            isOneToOne: true
            referencedRelation: "quote_decisions"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "quote_signatures_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_signatures_quote_fk"
            columns: ["organization_id", "quote_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "quote_signatures_version_fk"
            columns: ["organization_id", "quote_id", "quote_version_id"]
            isOneToOne: false
            referencedRelation: "quote_versions"
            referencedColumns: ["organization_id", "quote_id", "id"]
          },
        ]
      }
      quote_version_attachments: {
        Row: {
          attachment_id: string
          created_at: string
          customer_visible: boolean
          display_name: string
          id: string
          organization_id: string
          position: number
          quote_id: string
          quote_version_id: string
        }
        Insert: {
          attachment_id: string
          created_at?: string
          customer_visible?: boolean
          display_name: string
          id?: string
          organization_id: string
          position: number
          quote_id: string
          quote_version_id: string
        }
        Update: {
          attachment_id?: string
          created_at?: string
          customer_visible?: boolean
          display_name?: string
          id?: string
          organization_id?: string
          position?: number
          quote_id?: string
          quote_version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "quote_version_attachments_attachment_fk"
            columns: ["organization_id", "attachment_id"]
            isOneToOne: false
            referencedRelation: "attachments"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "quote_version_attachments_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_version_attachments_version_fk"
            columns: ["organization_id", "quote_id", "quote_version_id"]
            isOneToOne: false
            referencedRelation: "quote_versions"
            referencedColumns: ["organization_id", "quote_id", "id"]
          },
        ]
      }
      quote_version_lines: {
        Row: {
          category: string | null
          created_at: string
          description: string | null
          id: string
          image_attachment_id: string | null
          is_labor: boolean
          is_recommended: boolean
          is_taxable: boolean
          line_cost_total_minor: number | null
          line_kind: string
          line_total_minor: number | null
          name: string
          organization_id: string
          position: number
          quantity: number | null
          quote_id: string
          quote_version_id: string
          selection_kind: string
          source_catalog_item_id: string | null
          unit_cost_minor: number | null
          unit_label: string | null
          unit_price_minor: number | null
          updated_at: string
        }
        Insert: {
          category?: string | null
          created_at?: string
          description?: string | null
          id?: string
          image_attachment_id?: string | null
          is_labor?: boolean
          is_recommended?: boolean
          is_taxable?: boolean
          line_cost_total_minor?: number | null
          line_kind?: string
          line_total_minor?: number | null
          name: string
          organization_id: string
          position: number
          quantity?: number | null
          quote_id: string
          quote_version_id: string
          selection_kind?: string
          source_catalog_item_id?: string | null
          unit_cost_minor?: number | null
          unit_label?: string | null
          unit_price_minor?: number | null
          updated_at?: string
        }
        Update: {
          category?: string | null
          created_at?: string
          description?: string | null
          id?: string
          image_attachment_id?: string | null
          is_labor?: boolean
          is_recommended?: boolean
          is_taxable?: boolean
          line_cost_total_minor?: number | null
          line_kind?: string
          line_total_minor?: number | null
          name?: string
          organization_id?: string
          position?: number
          quantity?: number | null
          quote_id?: string
          quote_version_id?: string
          selection_kind?: string
          source_catalog_item_id?: string | null
          unit_cost_minor?: number | null
          unit_label?: string | null
          unit_price_minor?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "quote_version_lines_image_fk"
            columns: ["organization_id", "image_attachment_id"]
            isOneToOne: false
            referencedRelation: "attachments"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "quote_version_lines_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_version_lines_version_organization_fk"
            columns: ["organization_id", "quote_id", "quote_version_id"]
            isOneToOne: false
            referencedRelation: "quote_versions"
            referencedColumns: ["organization_id", "quote_id", "id"]
          },
        ]
      }
      quote_version_schedule_items: {
        Row: {
          created_at: string
          description: string
          id: string
          is_deposit: boolean
          organization_id: string
          position: number
          quote_id: string
          quote_version_id: string
          updated_at: string
          value: number
          value_type: string
        }
        Insert: {
          created_at?: string
          description: string
          id?: string
          is_deposit?: boolean
          organization_id: string
          position: number
          quote_id: string
          quote_version_id: string
          updated_at?: string
          value: number
          value_type: string
        }
        Update: {
          created_at?: string
          description?: string
          id?: string
          is_deposit?: boolean
          organization_id?: string
          position?: number
          quote_id?: string
          quote_version_id?: string
          updated_at?: string
          value?: number
          value_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "quote_version_schedule_items_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_version_schedule_items_version_fk"
            columns: ["organization_id", "quote_id", "quote_version_id"]
            isOneToOne: false
            referencedRelation: "quote_versions"
            referencedColumns: ["organization_id", "quote_id", "id"]
          },
        ]
      }
      quote_versions: {
        Row: {
          calculation: Json
          client_display_name: string
          client_message: string | null
          contract_disclaimer: string | null
          cost_minor: number
          created_at: string
          created_by: string | null
          currency_code: string
          deposit_required_minor: number
          deposit_type: string | null
          discount_minor: number
          discount_name: string | null
          discount_type: string | null
          discount_value: number | null
          document_hash: string | null
          id: string
          introduction: string | null
          margin_basis_points: number | null
          organization_id: string
          organization_name: string
          profit_minor: number
          published_at: string | null
          quote_id: string
          representative_enabled: boolean
          representative_name: string | null
          representative_signature_object_key: string | null
          representative_title: string | null
          require_customer_signature: boolean
          revision: number
          service_address_line1: string | null
          service_address_line2: string | null
          service_city: string | null
          service_country: string | null
          service_postal_code: string | null
          service_state_region: string | null
          show_line_totals: boolean
          show_quantities: boolean
          show_totals: boolean
          show_unit_prices: boolean
          status: string
          subtotal_minor: number
          tax_minor: number
          tax_name: string | null
          tax_rate_basis_points: number
          tax_rate_id: string | null
          tax_source: string
          total_minor: number
          updated_at: string
          version_number: number
        }
        Insert: {
          calculation?: Json
          client_display_name: string
          client_message?: string | null
          contract_disclaimer?: string | null
          cost_minor?: number
          created_at?: string
          created_by?: string | null
          currency_code: string
          deposit_required_minor?: number
          deposit_type?: string | null
          discount_minor?: number
          discount_name?: string | null
          discount_type?: string | null
          discount_value?: number | null
          document_hash?: string | null
          id?: string
          introduction?: string | null
          margin_basis_points?: number | null
          organization_id: string
          organization_name: string
          profit_minor?: number
          published_at?: string | null
          quote_id: string
          representative_enabled?: boolean
          representative_name?: string | null
          representative_signature_object_key?: string | null
          representative_title?: string | null
          require_customer_signature?: boolean
          revision?: number
          service_address_line1?: string | null
          service_address_line2?: string | null
          service_city?: string | null
          service_country?: string | null
          service_postal_code?: string | null
          service_state_region?: string | null
          show_line_totals?: boolean
          show_quantities?: boolean
          show_totals?: boolean
          show_unit_prices?: boolean
          status?: string
          subtotal_minor?: number
          tax_minor?: number
          tax_name?: string | null
          tax_rate_basis_points?: number
          tax_rate_id?: string | null
          tax_source?: string
          total_minor?: number
          updated_at?: string
          version_number: number
        }
        Update: {
          calculation?: Json
          client_display_name?: string
          client_message?: string | null
          contract_disclaimer?: string | null
          cost_minor?: number
          created_at?: string
          created_by?: string | null
          currency_code?: string
          deposit_required_minor?: number
          deposit_type?: string | null
          discount_minor?: number
          discount_name?: string | null
          discount_type?: string | null
          discount_value?: number | null
          document_hash?: string | null
          id?: string
          introduction?: string | null
          margin_basis_points?: number | null
          organization_id?: string
          organization_name?: string
          profit_minor?: number
          published_at?: string | null
          quote_id?: string
          representative_enabled?: boolean
          representative_name?: string | null
          representative_signature_object_key?: string | null
          representative_title?: string | null
          require_customer_signature?: boolean
          revision?: number
          service_address_line1?: string | null
          service_address_line2?: string | null
          service_city?: string | null
          service_country?: string | null
          service_postal_code?: string | null
          service_state_region?: string | null
          show_line_totals?: boolean
          show_quantities?: boolean
          show_totals?: boolean
          show_unit_prices?: boolean
          status?: string
          subtotal_minor?: number
          tax_minor?: number
          tax_name?: string | null
          tax_rate_basis_points?: number
          tax_rate_id?: string | null
          tax_source?: string
          total_minor?: number
          updated_at?: string
          version_number?: number
        }
        Relationships: [
          {
            foreignKeyName: "quote_versions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_versions_quote_organization_fk"
            columns: ["organization_id", "quote_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "quote_versions_tax_rate_organization_fk"
            columns: ["organization_id", "tax_rate_id"]
            isOneToOne: false
            referencedRelation: "organization_tax_rates"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      quotes: {
        Row: {
          archive_reason: string | null
          archived_at: string | null
          client_id: string
          conversion_idempotency_key: string | null
          conversion_request_hash: string | null
          created_at: string
          created_by: string | null
          currency_code: string
          current_published_version_id: string | null
          decided_at: string | null
          decided_by: string | null
          decision: string | null
          decision_method: string | null
          decision_note: string | null
          draft_version_id: string | null
          id: string
          organization_id: string
          previous_status: string | null
          property_id: string
          quote_number: number
          request_id: string | null
          sent_at: string | null
          status: string
          title: string
          updated_at: string
        }
        Insert: {
          archive_reason?: string | null
          archived_at?: string | null
          client_id: string
          conversion_idempotency_key?: string | null
          conversion_request_hash?: string | null
          created_at?: string
          created_by?: string | null
          currency_code: string
          current_published_version_id?: string | null
          decided_at?: string | null
          decided_by?: string | null
          decision?: string | null
          decision_method?: string | null
          decision_note?: string | null
          draft_version_id?: string | null
          id?: string
          organization_id: string
          previous_status?: string | null
          property_id: string
          quote_number: number
          request_id?: string | null
          sent_at?: string | null
          status?: string
          title: string
          updated_at?: string
        }
        Update: {
          archive_reason?: string | null
          archived_at?: string | null
          client_id?: string
          conversion_idempotency_key?: string | null
          conversion_request_hash?: string | null
          created_at?: string
          created_by?: string | null
          currency_code?: string
          current_published_version_id?: string | null
          decided_at?: string | null
          decided_by?: string | null
          decision?: string | null
          decision_method?: string | null
          decision_note?: string | null
          draft_version_id?: string | null
          id?: string
          organization_id?: string
          previous_status?: string | null
          property_id?: string
          quote_number?: number
          request_id?: string | null
          sent_at?: string | null
          status?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "quotes_client_organization_fk"
            columns: ["organization_id", "client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "quotes_current_published_version_fk"
            columns: ["organization_id", "id", "current_published_version_id"]
            isOneToOne: false
            referencedRelation: "quote_versions"
            referencedColumns: ["organization_id", "quote_id", "id"]
          },
          {
            foreignKeyName: "quotes_draft_version_organization_fk"
            columns: ["organization_id", "draft_version_id"]
            isOneToOne: false
            referencedRelation: "quote_versions"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "quotes_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotes_property_organization_fk"
            columns: ["organization_id", "property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "quotes_request_organization_fk"
            columns: ["organization_id", "request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      request_pricing_lines: {
        Row: {
          catalog_item_id: string | null
          category: string
          created_at: string
          description: string | null
          id: string
          image_attachment_id: string | null
          is_labor: boolean
          is_taxable: boolean
          line_cost_total_minor: number
          line_total_minor: number
          name: string
          organization_id: string
          position: number
          quantity: number
          request_id: string
          unit_cost_minor: number
          unit_label: string | null
          unit_price_minor: number
          updated_at: string
        }
        Insert: {
          catalog_item_id?: string | null
          category: string
          created_at?: string
          description?: string | null
          id?: string
          image_attachment_id?: string | null
          is_labor?: boolean
          is_taxable?: boolean
          line_cost_total_minor?: number
          line_total_minor?: number
          name: string
          organization_id: string
          position: number
          quantity: number
          request_id: string
          unit_cost_minor?: number
          unit_label?: string | null
          unit_price_minor?: number
          updated_at?: string
        }
        Update: {
          catalog_item_id?: string | null
          category?: string
          created_at?: string
          description?: string | null
          id?: string
          image_attachment_id?: string | null
          is_labor?: boolean
          is_taxable?: boolean
          line_cost_total_minor?: number
          line_total_minor?: number
          name?: string
          organization_id?: string
          position?: number
          quantity?: number
          request_id?: string
          unit_cost_minor?: number
          unit_label?: string | null
          unit_price_minor?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "request_pricing_lines_catalog_organization_fk"
            columns: ["organization_id", "catalog_item_id"]
            isOneToOne: false
            referencedRelation: "catalog_items"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "request_pricing_lines_image_organization_fk"
            columns: ["organization_id", "image_attachment_id"]
            isOneToOne: false
            referencedRelation: "attachments"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "request_pricing_lines_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "request_pricing_lines_request_organization_fk"
            columns: ["organization_id", "request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      requests: {
        Row: {
          client_id: string
          created_at: string
          description: string | null
          id: string
          organization_id: string
          preferred_time: string | null
          pricing_revision: number
          pricing_subtotal_minor: number
          property_id: string
          service_type: string | null
          source: string
          status: string
          title: string
          updated_at: string
        }
        Insert: {
          client_id: string
          created_at?: string
          description?: string | null
          id?: string
          organization_id: string
          preferred_time?: string | null
          pricing_revision?: number
          pricing_subtotal_minor?: number
          property_id: string
          service_type?: string | null
          source?: string
          status?: string
          title: string
          updated_at?: string
        }
        Update: {
          client_id?: string
          created_at?: string
          description?: string | null
          id?: string
          organization_id?: string
          preferred_time?: string | null
          pricing_revision?: number
          pricing_subtotal_minor?: number
          property_id?: string
          service_type?: string | null
          source?: string
          status?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "requests_client_organization_fk"
            columns: ["organization_id", "client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "requests_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "requests_property_organization_fk"
            columns: ["organization_id", "property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      role_permissions: {
        Row: {
          access_scope: string
          created_at: string
          permission_key: string
          role: string
        }
        Insert: {
          access_scope?: string
          created_at?: string
          permission_key: string
          role: string
        }
        Update: {
          access_scope?: string
          created_at?: string
          permission_key?: string
          role?: string
        }
        Relationships: [
          {
            foreignKeyName: "role_permissions_permission_key_fkey"
            columns: ["permission_key"]
            isOneToOne: false
            referencedRelation: "permissions"
            referencedColumns: ["key"]
          },
        ]
      }
      tag_assignments: {
        Row: {
          created_at: string
          created_by: string | null
          entity_id: string
          entity_type: string
          id: string
          organization_id: string
          tag_id: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          entity_id: string
          entity_type: string
          id?: string
          organization_id: string
          tag_id: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          entity_id?: string
          entity_type?: string
          id?: string
          organization_id?: string
          tag_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "tag_assignments_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tag_assignments_tag_organization_fk"
            columns: ["organization_id", "tag_id"]
            isOneToOne: false
            referencedRelation: "tags"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      tags: {
        Row: {
          color: string | null
          created_at: string
          id: string
          name: string
          normalized_name: string
          organization_id: string
        }
        Insert: {
          color?: string | null
          created_at?: string
          id?: string
          name: string
          normalized_name?: string
          organization_id: string
        }
        Update: {
          color?: string | null
          created_at?: string
          id?: string
          name?: string
          normalized_name?: string
          organization_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "tags_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      tasks: {
        Row: {
          assignee_user_id: string | null
          completed_at: string | null
          completed_by: string | null
          completed_by_outcome_event_id: string | null
          created_at: string
          created_by: string | null
          due_on: string | null
          id: string
          instructions: string | null
          opportunity_id: string
          organization_id: string
          status: string
          title: string
          updated_at: string
        }
        Insert: {
          assignee_user_id?: string | null
          completed_at?: string | null
          completed_by?: string | null
          completed_by_outcome_event_id?: string | null
          created_at?: string
          created_by?: string | null
          due_on?: string | null
          id?: string
          instructions?: string | null
          opportunity_id: string
          organization_id: string
          status?: string
          title: string
          updated_at?: string
        }
        Update: {
          assignee_user_id?: string | null
          completed_at?: string | null
          completed_by?: string | null
          completed_by_outcome_event_id?: string | null
          created_at?: string
          created_by?: string | null
          due_on?: string | null
          id?: string
          instructions?: string | null
          opportunity_id?: string
          organization_id?: string
          status?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tasks_opportunity_organization_fk"
            columns: ["organization_id", "opportunity_id"]
            isOneToOne: false
            referencedRelation: "opportunities"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "tasks_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tasks_outcome_event_organization_fk"
            columns: ["organization_id", "completed_by_outcome_event_id"]
            isOneToOne: false
            referencedRelation: "opportunity_outcome_events"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      website_chat_allowance_periods: {
        Row: {
          created_at: string
          ends_at: string
          id: string
          opened_by_commercial_event_id: string | null
          organization_id: string
          starts_at: string
        }
        Insert: {
          created_at?: string
          ends_at: string
          id?: string
          opened_by_commercial_event_id?: string | null
          organization_id: string
          starts_at: string
        }
        Update: {
          created_at?: string
          ends_at?: string
          id?: string
          opened_by_commercial_event_id?: string | null
          organization_id?: string
          starts_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "website_chat_allowance_period_opened_by_commercial_event_i_fkey"
            columns: ["opened_by_commercial_event_id"]
            isOneToOne: false
            referencedRelation: "organization_commercial_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "website_chat_allowance_periods_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      website_chat_capacity_buckets: {
        Row: {
          accepted_count: number
          allowance_period_id: string
          created_at: string
          organization_id: string
          updated_at: string
        }
        Insert: {
          accepted_count?: number
          allowance_period_id: string
          created_at?: string
          organization_id: string
          updated_at?: string
        }
        Update: {
          accepted_count?: number
          allowance_period_id?: string
          created_at?: string
          organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "website_chat_capacity_buckets_allowance_period_id_fkey"
            columns: ["allowance_period_id"]
            isOneToOne: false
            referencedRelation: "website_chat_allowance_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "website_chat_capacity_buckets_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      website_chat_capacity_reservations: {
        Row: {
          accepted_at: string
          allowance_period_id: string
          created_at: string
          id: string
          organization_id: string
          released_at: string | null
          reservation_state: string
          session_id: string
        }
        Insert: {
          accepted_at?: string
          allowance_period_id: string
          created_at?: string
          id?: string
          organization_id: string
          released_at?: string | null
          reservation_state?: string
          session_id: string
        }
        Update: {
          accepted_at?: string
          allowance_period_id?: string
          created_at?: string
          id?: string
          organization_id?: string
          released_at?: string | null
          reservation_state?: string
          session_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "website_chat_capacity_reservations_bucket_fk"
            columns: ["organization_id", "allowance_period_id"]
            isOneToOne: false
            referencedRelation: "website_chat_capacity_buckets"
            referencedColumns: ["organization_id", "allowance_period_id"]
          },
          {
            foreignKeyName: "website_chat_capacity_reservations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      website_chat_messages: {
        Row: {
          body: string
          client_id: string | null
          created_at: string
          delivery_state: string
          direction: string
          id: string
          idempotency_key: string | null
          organization_id: string
          sender_type: string
          sender_user_id: string | null
          session_id: string
        }
        Insert: {
          body: string
          client_id?: string | null
          created_at?: string
          delivery_state?: string
          direction: string
          id?: string
          idempotency_key?: string | null
          organization_id: string
          sender_type: string
          sender_user_id?: string | null
          session_id: string
        }
        Update: {
          body?: string
          client_id?: string | null
          created_at?: string
          delivery_state?: string
          direction?: string
          id?: string
          idempotency_key?: string | null
          organization_id?: string
          sender_type?: string
          sender_user_id?: string | null
          session_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "website_chat_messages_client_fk"
            columns: ["organization_id", "client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "website_chat_messages_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "website_chat_messages_session_fk"
            columns: ["organization_id", "session_id"]
            isOneToOne: false
            referencedRelation: "website_chat_sessions"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      website_chat_realtime_grants: {
        Row: {
          channel_topic: string
          created_at: string
          expires_at: string
          organization_id: string
          session_id: string
          updated_at: string
        }
        Insert: {
          channel_topic: string
          created_at?: string
          expires_at: string
          organization_id: string
          session_id: string
          updated_at?: string
        }
        Update: {
          channel_topic?: string
          created_at?: string
          expires_at?: string
          organization_id?: string
          session_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "website_chat_realtime_grants_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "website_chat_realtime_grants_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: true
            referencedRelation: "website_chat_sessions"
            referencedColumns: ["id"]
          },
        ]
      }
      website_chat_sessions: {
        Row: {
          attribution: Json
          candidate_client_id_by_email: string | null
          candidate_client_id_by_phone: string | null
          client_id: string | null
          closed_at: string | null
          closed_by: string | null
          closed_reason: string | null
          consent_transactional_sms: boolean
          created_at: string
          id: string
          idempotency_key: string
          ip_hash: string | null
          last_activity_at: string
          match_status: string
          normalized_email: string | null
          normalized_phone: string | null
          organization_id: string
          session_token_hash: string
          started_at: string
          submitted_email: string | null
          submitted_phone_e164: string | null
          visitor_name: string
          widget_id: string
        }
        Insert: {
          attribution?: Json
          candidate_client_id_by_email?: string | null
          candidate_client_id_by_phone?: string | null
          client_id?: string | null
          closed_at?: string | null
          closed_by?: string | null
          closed_reason?: string | null
          consent_transactional_sms?: boolean
          created_at?: string
          id?: string
          idempotency_key: string
          ip_hash?: string | null
          last_activity_at?: string
          match_status?: string
          normalized_email?: string | null
          normalized_phone?: string | null
          organization_id: string
          session_token_hash: string
          started_at?: string
          submitted_email?: string | null
          submitted_phone_e164?: string | null
          visitor_name: string
          widget_id: string
        }
        Update: {
          attribution?: Json
          candidate_client_id_by_email?: string | null
          candidate_client_id_by_phone?: string | null
          client_id?: string | null
          closed_at?: string | null
          closed_by?: string | null
          closed_reason?: string | null
          consent_transactional_sms?: boolean
          created_at?: string
          id?: string
          idempotency_key?: string
          ip_hash?: string | null
          last_activity_at?: string
          match_status?: string
          normalized_email?: string | null
          normalized_phone?: string | null
          organization_id?: string
          session_token_hash?: string
          started_at?: string
          submitted_email?: string | null
          submitted_phone_e164?: string | null
          visitor_name?: string
          widget_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "website_chat_sessions_client_fk"
            columns: ["organization_id", "client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["organization_id", "id"]
          },
          {
            foreignKeyName: "website_chat_sessions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "website_chat_sessions_widget_fk"
            columns: ["organization_id", "widget_id"]
            isOneToOne: false
            referencedRelation: "website_chat_widgets"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      website_chat_widget_origins: {
        Row: {
          created_at: string
          created_by: string | null
          id: string
          organization_id: string
          origin: string
          widget_id: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id?: string
          organization_id: string
          origin: string
          widget_id: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: string
          organization_id?: string
          origin?: string
          widget_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "website_chat_widget_origins_widget_fk"
            columns: ["organization_id", "widget_id"]
            isOneToOne: false
            referencedRelation: "website_chat_widgets"
            referencedColumns: ["organization_id", "id"]
          },
        ]
      }
      website_chat_widgets: {
        Row: {
          availability_visibility_mode: string
          channel_options: Json
          contact_requirement: string
          created_at: string
          created_by: string | null
          disabled_at: string | null
          greeting_text: string | null
          id: string
          launcher_position: string
          name: string
          organization_id: string
          privacy_policy_url: string | null
          public_token: string
          published: boolean
          revision: number
          source_label: string | null
          suspended_at: string | null
          teaser_text: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          availability_visibility_mode?: string
          channel_options?: Json
          contact_requirement?: string
          created_at?: string
          created_by?: string | null
          disabled_at?: string | null
          greeting_text?: string | null
          id?: string
          launcher_position?: string
          name: string
          organization_id: string
          privacy_policy_url?: string | null
          public_token?: string
          published?: boolean
          revision?: number
          source_label?: string | null
          suspended_at?: string | null
          teaser_text?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          availability_visibility_mode?: string
          channel_options?: Json
          contact_requirement?: string
          created_at?: string
          created_by?: string | null
          disabled_at?: string | null
          greeting_text?: string | null
          id?: string
          launcher_position?: string
          name?: string
          organization_id?: string
          privacy_policy_url?: string | null
          public_token?: string
          published?: boolean
          revision?: number
          source_label?: string | null
          suspended_at?: string | null
          teaser_text?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "website_chat_widgets_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      accept_ownership_transfer: {
        Args: { accepting_user_id: string; target_transfer_id: string }
        Returns: {
          from_user_id: string
          id: string
          organization_id: string
          requested_at: string
          resolved_at: string | null
          resolved_by: string | null
          state: string
          to_user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "organization_ownership_transfers"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      accept_website_chat_first_message: {
        Args: {
          consent_transactional_sms?: boolean
          message_body: string
          new_attribution?: Json
          new_idempotency_key: string
          new_session_token_hash: string
          requesting_origin: string
          visitor_email: string
          visitor_ip_hash?: string
          visitor_name: string
          visitor_phone_e164: string
          widget_public_token: string
        }
        Returns: Json
      }
      acknowledge_onboarding_application_duplicate: {
        Args: { actor_email: string; target_application_id: string }
        Returns: undefined
      }
      add_website_chat_widget_origin: {
        Args: {
          new_origin: string
          target_organization_id: string
          target_widget_id: string
        }
        Returns: Json
      }
      apply_organization_administrator_email_recovery: {
        Args: {
          actor_owner_email: string
          evidence_summary: string
          new_email: string
          occurred_at?: string
          old_email: string
          private_reason: string
          target_organization_id: string
          target_user_id: string
        }
        Returns: Json
      }
      apply_organization_closure_restore: {
        Args: {
          actor_owner_email: string
          idempotency_key: string
          occurred_at?: string
          restoration_evidence_note: string
          target_organization_id: string
        }
        Returns: Json
      }
      apply_organization_closure_start: {
        Args: {
          actor_owner_email: string
          idempotency_key: string
          occurred_at?: string
          private_reason: string
          target_organization_id: string
        }
        Returns: Json
      }
      apply_organization_commercial_command: {
        Args: {
          actor_owner_email?: string
          amount_usd_cents?: number
          commercial_timezone?: string
          event_kind: string
          idempotency_key: string
          is_legacy_import?: boolean
          occurred_at?: string
          original_confirmation_id?: string
          paid_through_date?: string
          paid_through_effect: string
          private_reason?: string
          private_reference?: string
          recalculate_deadline?: boolean
          safe_kind?: string
          safe_payload?: Json
          source_event_id?: string
          summary: string
          suspension_category?: string
          target_organization_id: string
        }
        Returns: Json
      }
      apply_organization_feature_exception: {
        Args: {
          actor_owner_email: string
          idempotency_key: string
          occurred_at?: string
          private_reason: string
          target_expires_at: string
          target_feature_key: string
          target_organization_id: string
          target_override_state: string
          target_starts_at: string
        }
        Returns: Json
      }
      apply_organization_free_access_change: {
        Args: {
          actor_owner_email: string
          idempotency_key: string
          occurred_at?: string
          private_reason: string
          target_access_until_date: string
          target_action: string
          target_grant_id: string
          target_organization_id: string
          target_starts_at: string
        }
        Returns: Json
      }
      apply_organization_late_renewal_reactivation: {
        Args: {
          actor_owner_email?: string
          amount_usd_cents?: number
          idempotency_key: string
          occurred_at?: string
          original_confirmation_id?: string
          paid_through_date?: string
          paid_through_effect: string
          private_reason?: string
          private_reference?: string
          reactivate?: boolean
          safe_kind?: string
          safe_payload?: Json
          summary: string
          target_organization_id: string
        }
        Returns: Json
      }
      apply_organization_lifecycle_change: {
        Args: {
          actor_owner_email: string
          idempotency_key: string
          occurred_at?: string
          private_reason: string
          target_organization_id: string
          target_status: string
          target_suspension_category: string
        }
        Returns: Json
      }
      apply_organization_limit_exception: {
        Args: {
          actor_owner_email: string
          idempotency_key: string
          occurred_at?: string
          private_reason: string
          target_expires_at: string
          target_limit_key: string
          target_limit_state: string
          target_limit_value: number
          target_organization_id: string
          target_starts_at: string
        }
        Returns: Json
      }
      apply_organization_member_profile_correction: {
        Args: {
          actor_owner_email: string
          email_changed: boolean
          new_email: string
          new_full_name: string
          occurred_at?: string
          old_email: string
          private_reason: string
          target_organization_id: string
          target_user_id: string
        }
        Returns: Json
      }
      apply_organization_package_change: {
        Args: {
          actor_owner_email: string
          idempotency_key: string
          occurred_at?: string
          private_reason: string
          target_organization_id: string
          target_package_version_id: string
        }
        Returns: Json
      }
      apply_organization_pending_setup_reconciliation: {
        Args: {
          actor_owner_email: string
          idempotency_key: string
          occurred_at?: string
          private_reason: string
          target_organization_id: string
          target_status: string
          target_suspension_category: string
        }
        Returns: Json
      }
      apply_organization_purge: {
        Args: {
          actor_owner_email?: string
          purge_trigger_kind: string
          target_organization_id: string
        }
        Returns: Json
      }
      archive_quote: {
        Args: { reason?: string; target_quote_id: string }
        Returns: Json
      }
      attach_team_invitation_identity: {
        Args: {
          target_attempt_nonce: string
          target_expires_at: string
          target_invitation_id: string
          target_invited_user_id: string
          target_token_hash: string
        }
        Returns: {
          accepted_at: string | null
          auth_attempt_nonce: string | null
          auth_attempt_started_at: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          expires_at: string | null
          id: string
          identity_cleanup_error: string | null
          identity_cleanup_state: string
          invited_by: string | null
          invited_email: string
          invited_user_id: string | null
          last_delivery_error: string | null
          last_sent_at: string | null
          lease_expires_at: string | null
          lease_nonce: string | null
          organization_id: string
          password_set_at: string | null
          reconciliation_lease_expires_at: string | null
          reconciliation_nonce: string | null
          requested_permission_overrides: Json
          role: string
          state: string
          token_hash: string | null
        }
        SetofOptions: {
          from: "*"
          to: "organization_member_invitations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      begin_communication_email_domain_removal: {
        Args: {
          expected_live_replacement_count: number
          expected_live_sender_count: number
          target_domain_id: string
          target_organization_id: string
        }
        Returns: Json
      }
      begin_communication_email_sender_create: {
        Args: {
          actor_user_id: string
          command_idempotency_key: string
          target_allows_automated: boolean
          target_allows_manual: boolean
          target_assigned_user_id: string
          target_display_name: string
          target_domain_id: string
          target_email_address: string
          target_is_organization_default: boolean
          target_organization_id: string
        }
        Returns: Json
      }
      begin_communication_email_sender_update: {
        Args: {
          actor_user_id: string
          command_idempotency_key: string
          target_allows_automated: boolean
          target_allows_manual: boolean
          target_assigned_user_id: string
          target_display_name: string
          target_enabled: boolean
          target_is_organization_default: boolean
          target_organization_id: string
          target_sender_id: string
        }
        Returns: Json
      }
      begin_team_invitation: {
        Args: {
          target_invited_by: string
          target_invited_email: string
          target_organization_id: string
          target_permission_overrides: Json
          target_role: string
        }
        Returns: {
          accepted_at: string | null
          auth_attempt_nonce: string | null
          auth_attempt_started_at: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          expires_at: string | null
          id: string
          identity_cleanup_error: string | null
          identity_cleanup_state: string
          invited_by: string | null
          invited_email: string
          invited_user_id: string | null
          last_delivery_error: string | null
          last_sent_at: string | null
          lease_expires_at: string | null
          lease_nonce: string | null
          organization_id: string
          password_set_at: string | null
          reconciliation_lease_expires_at: string | null
          reconciliation_nonce: string | null
          requested_permission_overrides: Json
          role: string
          state: string
          token_hash: string | null
        }
        SetofOptions: {
          from: "*"
          to: "organization_member_invitations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      cancel_communication_message: {
        Args: {
          p_actor_email: string
          p_delivery_intent_id: string
          p_reason: string
        }
        Returns: Json
      }
      cancel_team_invitation: {
        Args: { target_cancelled_by: string; target_invitation_id: string }
        Returns: {
          accepted_at: string | null
          auth_attempt_nonce: string | null
          auth_attempt_started_at: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          expires_at: string | null
          id: string
          identity_cleanup_error: string | null
          identity_cleanup_state: string
          invited_by: string | null
          invited_email: string
          invited_user_id: string | null
          last_delivery_error: string | null
          last_sent_at: string | null
          lease_expires_at: string | null
          lease_nonce: string | null
          organization_id: string
          password_set_at: string | null
          reconciliation_lease_expires_at: string | null
          reconciliation_nonce: string | null
          requested_permission_overrides: Json
          role: string
          state: string
          token_hash: string | null
        }
        SetofOptions: {
          from: "*"
          to: "organization_member_invitations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      change_team_member_role: {
        Args: {
          actor_user_id: string
          expected_access_revision: number
          keep_adjustments: boolean
          new_role: string
          target_organization_id: string
          target_user_id: string
        }
        Returns: {
          access_revision: number
          created_at: string
          deactivated_at: string | null
          display_name_at_removal: string | null
          identity_cleanup_error: string | null
          identity_cleanup_state: string
          job_title: string | null
          organization_id: string
          profile_revision: number
          removed_at: string | null
          role: string
          schedule_color: string | null
          status: string
          status_changed_at: string | null
          status_changed_by: string | null
          user_id: string
          work_phone: string | null
        }
        SetofOptions: {
          from: "*"
          to: "organization_members"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      check_rate_limit: {
        Args: {
          target_bucket_key: string
          target_max_attempts: number
          target_window_seconds: number
        }
        Returns: {
          allowed: boolean
          retry_after_seconds: number
        }[]
      }
      claim_cancelled_team_invitation_cleanup: {
        Args: {
          target_invitation_id: string
          target_lease_nonce: string
          target_lease_seconds?: number
          target_organization_id: string
        }
        Returns: {
          accepted_at: string | null
          auth_attempt_nonce: string | null
          auth_attempt_started_at: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          expires_at: string | null
          id: string
          identity_cleanup_error: string | null
          identity_cleanup_state: string
          invited_by: string | null
          invited_email: string
          invited_user_id: string | null
          last_delivery_error: string | null
          last_sent_at: string | null
          lease_expires_at: string | null
          lease_nonce: string | null
          organization_id: string
          password_set_at: string | null
          reconciliation_lease_expires_at: string | null
          reconciliation_nonce: string | null
          requested_permission_overrides: Json
          role: string
          state: string
          token_hash: string | null
        }
        SetofOptions: {
          from: "*"
          to: "organization_member_invitations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      claim_communication_forward_event: {
        Args: never
        Returns: {
          claim_token: string
          forward_event_id: string
          html_content: string
          recipient_emails: string[]
          sender_email: string
          sender_id: string
          sender_name: string
          subject: string
          text_content: string
        }[]
      }
      claim_communication_inbound_attachment_imports: {
        Args: { batch_size?: number }
        Returns: {
          byte_size: number
          claim_token: string | null
          claimed_at: string | null
          created_at: string
          failure_reason: string | null
          file_name: string
          id: string
          inbound_message_id: string
          mime_type: string
          object_key: string | null
          organization_id: string
          provider_download_token: string | null
          status: string
          updated_at: string
        }[]
        SetofOptions: {
          from: "*"
          to: "communication_inbound_attachments"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      claim_communication_outbox_event: {
        Args: never
        Returns: {
          claim_token: string
          delivery_intent_id: string
          html_content: string
          logical_send_key: string
          outbox_event_id: string
          recipient_email: string
          reply_to_email: string
          reply_to_name: string
          sender_email: string
          sender_id: string
          sender_name: string
          subject: string
          text_content: string
        }[]
      }
      claim_onboarding_application_provision: {
        Args: { stale_after?: string; target_application_id: string }
        Returns: {
          administrator_user_id: string
          attempt_count: number
          claim_status: string
          organization_id: string
        }[]
      }
      claim_team_invitation: {
        Args: {
          target_email: string
          target_lease_nonce: string
          target_lease_seconds?: number
          target_token_hash: string
        }
        Returns: {
          claimed: boolean
          invitation_id: string
          invited_user_id: string
          organization_id: string
          role: string
        }[]
      }
      claim_team_invitation_reconciliation: {
        Args: {
          target_batch_size?: number
          target_lease_nonce: string
          target_lease_seconds?: number
        }
        Returns: {
          accepted_at: string | null
          auth_attempt_nonce: string | null
          auth_attempt_started_at: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          expires_at: string | null
          id: string
          identity_cleanup_error: string | null
          identity_cleanup_state: string
          invited_by: string | null
          invited_email: string
          invited_user_id: string | null
          last_delivery_error: string | null
          last_sent_at: string | null
          lease_expires_at: string | null
          lease_nonce: string | null
          organization_id: string
          password_set_at: string | null
          reconciliation_lease_expires_at: string | null
          reconciliation_nonce: string | null
          requested_permission_overrides: Json
          role: string
          state: string
          token_hash: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "organization_member_invitations"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      clone_quote_version_to_draft: {
        Args: { target_quote_id: string }
        Returns: Json
      }
      close_ownership_transfer: {
        Args: { actor_user_id: string; target_transfer_id: string }
        Returns: {
          from_user_id: string
          id: string
          organization_id: string
          requested_at: string
          resolved_at: string | null
          resolved_by: string | null
          state: string
          to_user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "organization_ownership_transfers"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      communication_email_suppression_removal_request_json: {
        Args: { p_request_id: string }
        Returns: Json
      }
      confirm_onboarding_application_payment: {
        Args: {
          actor_email: string
          amount_usd_cents: number
          mismatch_reason: string
          private_reference: string
          target_application_id: string
        }
        Returns: undefined
      }
      consume_onboarding_application_setup_link: {
        Args: { target_email: string; target_token_hash: string }
        Returns: {
          administrator_user_id: string
          application_id: string
          consumed: boolean
        }[]
      }
      convert_request_to_quote: {
        Args: {
          idempotency_key: string
          request_hash: string
          target_request_id: string
        }
        Returns: Json
      }
      correct_onboarding_application: {
        Args: {
          actor_email: string
          correction_reason: string
          new_business_name: string
          new_city_country: string
          new_initial_administrator_email: string
          new_initial_administrator_name: string
          new_main_contact_email: string
          new_main_contact_name: string
          new_main_contact_phone: string
          new_note: string
          new_time_zone: string
          new_trade: string
          target_application_id: string
        }
        Returns: undefined
      }
      correct_onboarding_application_package: {
        Args: {
          actor_email: string
          correction_reason: string
          new_package_version_id: string
          target_application_id: string
        }
        Returns: undefined
      }
      create_catalog_item: {
        Args: {
          new_category: string
          new_description: string
          new_is_labor: boolean
          new_is_taxable: boolean
          new_name: string
          new_unit_cost_minor: number
          new_unit_label: string
          new_unit_price_minor: number
          target_organization_id: string
        }
        Returns: Json
      }
      create_client: {
        Args: { payload: Json }
        Returns: {
          archived_at: string | null
          client_type: string
          company_name: string | null
          converted_to_customer_at: string | null
          created_at: string
          deleted_at: string | null
          display_name: string
          first_name: string | null
          id: string
          last_name: string | null
          lead_source: string | null
          lead_temperature: string | null
          lifecycle_status: string
          next_follow_up_at: string | null
          organization_id: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "clients"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_note: {
        Args: {
          new_body: string
          new_pinned?: boolean
          target_entity_id: string
          target_entity_type: string
          target_organization_id: string
        }
        Returns: {
          body: string
          created_at: string
          created_by: string
          edited_at: string
          edited_by: string
          entity_id: string
          entity_type: string
          id: string
          link_created_at: string
          link_id: string
          organization_id: string
          pinned: boolean
          updated_at: string
        }[]
      }
      create_organization_tax_rate: {
        Args: {
          new_name: string
          new_rate_basis_points: number
          target_organization_id: string
        }
        Returns: Json
      }
      create_quote: {
        Args: {
          disclaimer?: string
          quote_title: string
          target_client_id: string
          target_property_id: string
        }
        Returns: Json
      }
      create_similar_quote: { Args: { target_quote_id: string }; Returns: Json }
      create_website_chat_widget: {
        Args: {
          new_availability_visibility_mode: string
          new_channel_options: Json
          new_contact_requirement: string
          new_greeting_text: string
          new_launcher_position: string
          new_name: string
          new_privacy_policy_url: string
          new_source_label: string
          new_teaser_text: string
          target_organization_id: string
        }
        Returns: Json
      }
      deactivate_team_member: {
        Args: {
          actor_user_id: string
          target_organization_id: string
          target_user_id: string
        }
        Returns: {
          access_revision: number
          created_at: string
          deactivated_at: string | null
          display_name_at_removal: string | null
          identity_cleanup_error: string | null
          identity_cleanup_state: string
          job_title: string | null
          organization_id: string
          profile_revision: number
          removed_at: string | null
          role: string
          schedule_color: string | null
          status: string
          status_changed_at: string | null
          status_changed_by: string | null
          user_id: string
          work_phone: string | null
        }
        SetofOptions: {
          from: "*"
          to: "organization_members"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      decide_communication_email_suppression_removal: {
        Args: {
          p_actor_email: string
          p_decision: string
          p_note: string
          p_request_id: string
        }
        Returns: Json
      }
      delete_catalog_item: {
        Args: {
          expected_revision: number
          target_item_id: string
          target_organization_id: string
        }
        Returns: Json
      }
      delete_organization_tax_rate: {
        Args: {
          expected_revision: number
          target_organization_id: string
          target_rate_id: string
        }
        Returns: Json
      }
      delete_property: { Args: { p_property_id: string }; Returns: undefined }
      delete_quote: { Args: { target_quote_id: string }; Returns: Json }
      effective_employee_seat_limit: {
        Args: { at?: string; target_organization_id: string }
        Returns: {
          is_unlimited: boolean
          source: string
          state: string
          value: number
        }[]
      }
      effective_website_chat_widgets_limit: {
        Args: { at?: string; target_organization_id: string }
        Returns: {
          is_unlimited: boolean
          source: string
          state: string
          value: number
        }[]
      }
      end_website_chat_session: {
        Args: {
          target_actor_user_id: string
          target_organization_id: string
          target_session_id: string
        }
        Returns: Json
      }
      enqueue_communication_email: {
        Args: {
          target_client_id: string
          target_contact_method_id: string
          target_html_content: string
          target_logical_send_key: string
          target_organization_id: string
          target_recipient_email: string
          target_subject: string
          target_text_content: string
        }
        Returns: {
          accepted_at: string | null
          allowance_class: string
          channel: string
          client_contact_method_id: string
          client_id: string
          created_at: string
          created_by: string | null
          delivery_outcome: string | null
          delivery_outcome_at: string | null
          delivery_outcome_detail: string | null
          direction: string
          expires_at: string
          failure_code: string | null
          failure_message: string | null
          html_content: string
          id: string
          logical_send_key: string
          organization_id: string
          provider_message_id: string | null
          quote_id: string | null
          recipient_email: string
          reply_alias_id: string | null
          resent_from_intent_id: string | null
          retry_class: string
          retry_window_ends_at: string | null
          send_kind: string
          sender_id: string | null
          status: string
          subject: string
          text_content: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "communication_delivery_intents"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      enqueue_conversation_reply_email: {
        Args: {
          target_actor_user_id: string
          target_attachments?: Json
          target_client_id: string
          target_html_content: string
          target_logical_send_key: string
          target_organization_id: string
          target_subject: string
          target_text_content: string
        }
        Returns: {
          accepted_at: string | null
          allowance_class: string
          channel: string
          client_contact_method_id: string
          client_id: string
          created_at: string
          created_by: string | null
          delivery_outcome: string | null
          delivery_outcome_at: string | null
          delivery_outcome_detail: string | null
          direction: string
          expires_at: string
          failure_code: string | null
          failure_message: string | null
          html_content: string
          id: string
          logical_send_key: string
          organization_id: string
          provider_message_id: string | null
          quote_id: string | null
          recipient_email: string
          reply_alias_id: string | null
          resent_from_intent_id: string | null
          retry_class: string
          retry_window_ends_at: string | null
          send_kind: string
          sender_id: string | null
          status: string
          subject: string
          text_content: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "communication_delivery_intents"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      enqueue_inbound_message_forward: {
        Args: {
          target_actor_user_id: string
          target_attachment_ids?: string[]
          target_html_content: string
          target_logical_send_key: string
          target_organization_id: string
          target_recipient_emails: string[]
          target_source_inbound_message_id: string
          target_subject: string
          target_text_content: string
        }
        Returns: {
          accepted_at: string | null
          attempt_count: number
          available_at: string
          claim_token: string | null
          claimed_at: string | null
          client_id: string
          created_at: string
          created_by: string | null
          failure_code: string | null
          failure_message: string | null
          finalized_claim_token: string | null
          html_content: string
          id: string
          last_error: string | null
          logical_send_key: string
          organization_id: string
          provider_message_id: string | null
          recipient_emails: string[]
          sender_id: string
          source_inbound_message_id: string
          status: string
          subject: string
          text_content: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "communication_forward_events"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      enqueue_manual_communication_email: {
        Args: {
          target_actor_user_id: string
          target_attachments?: Json
          target_client_id: string
          target_contact_method_id: string
          target_html_content: string
          target_logical_send_key: string
          target_organization_id: string
          target_subject: string
          target_text_content: string
        }
        Returns: {
          accepted_at: string | null
          allowance_class: string
          channel: string
          client_contact_method_id: string
          client_id: string
          created_at: string
          created_by: string | null
          delivery_outcome: string | null
          delivery_outcome_at: string | null
          delivery_outcome_detail: string | null
          direction: string
          expires_at: string
          failure_code: string | null
          failure_message: string | null
          html_content: string
          id: string
          logical_send_key: string
          organization_id: string
          provider_message_id: string | null
          quote_id: string | null
          recipient_email: string
          reply_alias_id: string | null
          resent_from_intent_id: string | null
          retry_class: string
          retry_window_ends_at: string | null
          send_kind: string
          sender_id: string | null
          status: string
          subject: string
          text_content: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "communication_delivery_intents"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      enqueue_quote_communication_email: {
        Args: {
          target_actor_user_id: string
          target_logical_send_key: string
          target_organization_id: string
          target_quote_id: string
          target_quote_token_hash: string
          target_quote_url: string
        }
        Returns: {
          accepted_at: string | null
          allowance_class: string
          channel: string
          client_contact_method_id: string
          client_id: string
          created_at: string
          created_by: string | null
          delivery_outcome: string | null
          delivery_outcome_at: string | null
          delivery_outcome_detail: string | null
          direction: string
          expires_at: string
          failure_code: string | null
          failure_message: string | null
          html_content: string
          id: string
          logical_send_key: string
          organization_id: string
          provider_message_id: string | null
          quote_id: string | null
          recipient_email: string
          reply_alias_id: string | null
          resent_from_intent_id: string | null
          retry_class: string
          retry_window_ends_at: string | null
          send_kind: string
          sender_id: string | null
          status: string
          subject: string
          text_content: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "communication_delivery_intents"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      ensure_communication_reply_alias: {
        Args: {
          target_client_id: string
          target_contact_method_id: string
          target_organization_id: string
          target_sender_id: string
        }
        Returns: {
          alias_local_part: string
          client_contact_method_id: string
          client_id: string
          created_at: string
          expires_at: string
          id: string
          last_activity_at: string
          organization_id: string
          receiving_domain_id: string
          sender_id: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "communication_reply_aliases"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      evaluate_communication_email_reputation: {
        Args: { p_at?: string; p_organization_id: string }
        Returns: Json
      }
      expire_team_invitations: {
        Args: never
        Returns: {
          accepted_at: string | null
          auth_attempt_nonce: string | null
          auth_attempt_started_at: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          expires_at: string | null
          id: string
          identity_cleanup_error: string | null
          identity_cleanup_state: string
          invited_by: string | null
          invited_email: string
          invited_user_id: string | null
          last_delivery_error: string | null
          last_sent_at: string | null
          lease_expires_at: string | null
          lease_nonce: string | null
          organization_id: string
          password_set_at: string | null
          reconciliation_lease_expires_at: string | null
          reconciliation_nonce: string | null
          requested_permission_overrides: Json
          role: string
          state: string
          token_hash: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "organization_member_invitations"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      expire_team_invitations_bounded: {
        Args: { target_batch_size?: number }
        Returns: {
          accepted_at: string | null
          auth_attempt_nonce: string | null
          auth_attempt_started_at: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          expires_at: string | null
          id: string
          identity_cleanup_error: string | null
          identity_cleanup_state: string
          invited_by: string | null
          invited_email: string
          invited_user_id: string | null
          last_delivery_error: string | null
          last_sent_at: string | null
          lease_expires_at: string | null
          lease_nonce: string | null
          organization_id: string
          password_set_at: string | null
          reconciliation_lease_expires_at: string | null
          reconciliation_nonce: string | null
          requested_permission_overrides: Json
          role: string
          state: string
          token_hash: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "organization_member_invitations"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      finalize_communication_email_domain_removal: {
        Args: {
          actor_owner_email: string
          command_idempotency_key: string
          removal_reason: string
          target_domain_id: string
          target_organization_id: string
        }
        Returns: Json
      }
      finalize_communication_email_sender_create: {
        Args: {
          actor_user_id: string
          command_idempotency_key: string
          provider_sender_id: number
          target_organization_id: string
          target_sender_id: string
        }
        Returns: {
          allows_automated: boolean
          allows_manual: boolean
          assigned_user_id: string | null
          created_at: string
          created_by: string | null
          display_name: string
          domain_id: string
          email_address: string
          id: string
          is_organization_default: boolean
          lifecycle_state: string
          organization_id: string
          provider: string
          provider_cleanup_error: string | null
          provider_sender_id: number | null
          restriction_reason: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "communication_email_senders"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      finalize_communication_email_sender_update: {
        Args: {
          actor_user_id: string
          command_idempotency_key: string
          target_organization_id: string
          target_sender_id: string
        }
        Returns: {
          allows_automated: boolean
          allows_manual: boolean
          assigned_user_id: string | null
          created_at: string
          created_by: string | null
          display_name: string
          domain_id: string
          email_address: string
          id: string
          is_organization_default: boolean
          lifecycle_state: string
          organization_id: string
          provider: string
          provider_cleanup_error: string | null
          provider_sender_id: number | null
          restriction_reason: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "communication_email_senders"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      finalize_communication_forward_event: {
        Args: {
          target_claim_token: string
          target_failure_code?: string
          target_failure_message?: string
          target_forward_event_id: string
          target_outcome: string
          target_provider_message_id?: string
        }
        Returns: {
          accepted_at: string | null
          attempt_count: number
          available_at: string
          claim_token: string | null
          claimed_at: string | null
          client_id: string
          created_at: string
          created_by: string | null
          failure_code: string | null
          failure_message: string | null
          finalized_claim_token: string | null
          html_content: string
          id: string
          last_error: string | null
          logical_send_key: string
          organization_id: string
          provider_message_id: string | null
          recipient_emails: string[]
          sender_id: string
          source_inbound_message_id: string
          status: string
          subject: string
          text_content: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "communication_forward_events"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      finalize_communication_inbound_attachment_import: {
        Args: {
          target_attachment_id: string
          target_claim_token: string
          target_failure_reason?: string
          target_object_key?: string
          target_status: string
        }
        Returns: {
          byte_size: number
          claim_token: string | null
          claimed_at: string | null
          created_at: string
          failure_reason: string | null
          file_name: string
          id: string
          inbound_message_id: string
          mime_type: string
          object_key: string | null
          organization_id: string
          provider_download_token: string | null
          status: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "communication_inbound_attachments"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      finalize_communication_outbox_event: {
        Args: {
          target_claim_token: string
          target_failure_code?: string
          target_failure_message?: string
          target_outbox_event_id: string
          target_outcome: string
          target_provider_message_id?: string
        }
        Returns: {
          attempt_count: number
          available_at: string
          intent_status: string
          outbox_status: string
          usage_recorded: boolean
        }[]
      }
      finalize_reconciled_team_invitation: {
        Args: { target_invitation_id: string; target_lease_nonce: string }
        Returns: {
          accepted_at: string | null
          auth_attempt_nonce: string | null
          auth_attempt_started_at: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          expires_at: string | null
          id: string
          identity_cleanup_error: string | null
          identity_cleanup_state: string
          invited_by: string | null
          invited_email: string
          invited_user_id: string | null
          last_delivery_error: string | null
          last_sent_at: string | null
          lease_expires_at: string | null
          lease_nonce: string | null
          organization_id: string
          password_set_at: string | null
          reconciliation_lease_expires_at: string | null
          reconciliation_nonce: string | null
          requested_permission_overrides: Json
          role: string
          state: string
          token_hash: string | null
        }
        SetofOptions: {
          from: "*"
          to: "organization_member_invitations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      finalize_team_invitation: {
        Args: { target_invitation_id: string }
        Returns: {
          accepted_at: string | null
          auth_attempt_nonce: string | null
          auth_attempt_started_at: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          expires_at: string | null
          id: string
          identity_cleanup_error: string | null
          identity_cleanup_state: string
          invited_by: string | null
          invited_email: string
          invited_user_id: string | null
          last_delivery_error: string | null
          last_sent_at: string | null
          lease_expires_at: string | null
          lease_nonce: string | null
          organization_id: string
          password_set_at: string | null
          reconciliation_lease_expires_at: string | null
          reconciliation_nonce: string | null
          requested_permission_overrides: Json
          role: string
          state: string
          token_hash: string | null
        }
        SetofOptions: {
          from: "*"
          to: "organization_member_invitations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      find_team_invitation_auth_receipt: {
        Args: { target_invitation_id: string }
        Returns: {
          identity_invitation_id: string
          password_set_invitation_id: string
          user_id: string
        }[]
      }
      freeze_quote_version: {
        Args: { expected_revision: number; target_quote_id: string }
        Returns: Json
      }
      get_communication_email_blocked_addresses: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      get_communication_email_reputation: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      get_communication_email_reputation_overview: {
        Args: never
        Returns: Json
      }
      get_communication_email_sending_capacity_overview: {
        Args: never
        Returns: Json
      }
      get_communication_email_sending_health: { Args: never; Returns: Json }
      get_communication_email_suppression_removal_queue: {
        Args: never
        Returns: Json
      }
      get_communication_message_history: {
        Args: { p_delivery_intent_id: string; p_organization_id: string }
        Returns: Json
      }
      get_communication_message_recovery_queue: { Args: never; Returns: Json }
      get_organization_communication_email_allowances: {
        Args: { at?: string; target_organization_id: string }
        Returns: {
          effective_source: string
          effective_state: string
          effective_value: number
          fallback_state: string
          fallback_value: number
          limit_key: string
          override_author_email: string
          override_expires_at: string
          override_reason: string
          override_starts_at: string
          override_state: string
          override_value: number
          period_ends_at: string
          period_id: string
          period_starts_at: string
        }[]
      }
      get_organization_communication_email_usage: {
        Args: { p_organization_id: string }
        Returns: {
          essential_limit_state: string
          essential_limit_value: number
          essential_reserve_exhausted: boolean
          essential_reserve_exhausted_at: string
          essential_used: number
          optional_limit_state: string
          optional_limit_value: number
          optional_used: number
          organization_timezone: string
          period_ends_at: string
          period_id: string
          period_starts_at: string
        }[]
      }
      get_organization_communication_website_chat_allowance: {
        Args: { at?: string; target_organization_id: string }
        Returns: {
          effective_source: string
          effective_state: string
          effective_value: number
          fallback_state: string
          fallback_value: number
          limit_key: string
          override_author_email: string
          override_expires_at: string
          override_reason: string
          override_starts_at: string
          override_state: string
          override_value: number
          period_ends_at: string
          period_id: string
          period_starts_at: string
        }[]
      }
      get_organization_website_chat_authority: {
        Args: { p_organization_id: string }
        Returns: Json
      }
      get_team_member_detail: {
        Args: { target_organization_id: string; target_user_id: string }
        Returns: Json
      }
      get_website_chat_session_messages: {
        Args: {
          before_created_at?: string
          before_id?: string
          page_size?: number
          requesting_origin: string
          session_token_hash: string
        }
        Returns: Json
      }
      get_website_chat_widget_public_config: {
        Args: { requesting_origin: string; widget_public_token: string }
        Returns: {
          brand_color: string
          business_name: string
          contact_requirement: string
          greeting_text: string
          launcher_position: string
          organization_id: string
          privacy_policy_url: string
          status: string
          teaser_text: string
          widget_id: string
        }[]
      }
      issue_quote_access_link: {
        Args: { supplied_token_hash: string; target_quote_id: string }
        Returns: Json
      }
      list_communication_outbound_attachments: {
        Args: { target_delivery_intent_id: string }
        Returns: {
          byte_size: number
          file_name: string
          mime_type: string
          object_key: string
        }[]
      }
      list_team_directory: {
        Args: {
          cursor_created_at?: string
          cursor_status_order?: number
          cursor_user_id?: string
          page_limit?: number
          requested_status?: string
          search_term?: string
          target_organization_id: string
        }
        Returns: Json
      }
      manage_platform_package_email_allowances: {
        Args: {
          actor_email: string
          target_essential_state: string
          target_essential_value: number
          target_operational_state: string
          target_operational_value: number
          target_version_id: string
        }
        Returns: string
      }
      manage_platform_package_version: {
        Args: {
          actor_email?: string
          operation: string
          target_display_name?: string
          target_feature_keys?: string[]
          target_limit_state?: string
          target_limit_value?: number
          target_package_key: string
          target_price_usd_cents?: number
          target_public_description?: string
          target_value_explanation?: string
          target_version_id?: string
        }
        Returns: string
      }
      manage_platform_package_website_chat_limits: {
        Args: {
          actor_email: string
          target_accepted_conversations_state: string
          target_accepted_conversations_value: number
          target_version_id: string
          target_widgets_state: string
          target_widgets_value: number
        }
        Returns: string
      }
      mark_member_identity_revoked: {
        Args: {
          cleanup_error?: string
          new_cleanup_state: string
          target_organization_id: string
          target_user_id: string
        }
        Returns: {
          access_revision: number
          created_at: string
          deactivated_at: string | null
          display_name_at_removal: string | null
          identity_cleanup_error: string | null
          identity_cleanup_state: string
          job_title: string | null
          organization_id: string
          profile_revision: number
          removed_at: string | null
          role: string
          schedule_color: string | null
          status: string
          status_changed_at: string | null
          status_changed_by: string | null
          user_id: string
          work_phone: string | null
        }
        SetofOptions: {
          from: "*"
          to: "organization_members"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      mark_onboarding_application_not_proceeding: {
        Args: {
          actor_email: string
          reason?: string
          target_application_id: string
        }
        Returns: undefined
      }
      mark_onboarding_application_reviewed: {
        Args: { actor_email: string; target_application_id: string }
        Returns: undefined
      }
      mark_team_invitation_auth_attempt_started: {
        Args: { target_attempt_nonce: string; target_invitation_id: string }
        Returns: {
          accepted_at: string | null
          auth_attempt_nonce: string | null
          auth_attempt_started_at: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          expires_at: string | null
          id: string
          identity_cleanup_error: string | null
          identity_cleanup_state: string
          invited_by: string | null
          invited_email: string
          invited_user_id: string | null
          last_delivery_error: string | null
          last_sent_at: string | null
          lease_expires_at: string | null
          lease_nonce: string | null
          organization_id: string
          password_set_at: string | null
          reconciliation_lease_expires_at: string | null
          reconciliation_nonce: string | null
          requested_permission_overrides: Json
          role: string
          state: string
          token_hash: string | null
        }
        SetofOptions: {
          from: "*"
          to: "organization_member_invitations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      mint_website_chat_realtime_grant: {
        Args: {
          proposed_topic: string
          requesting_origin: string
          session_token_hash: string
          ttl_seconds?: number
        }
        Returns: Json
      }
      organization_currency_is_locked: {
        Args: { target_organization_id: string }
        Returns: boolean
      }
      organization_legacy_readiness: {
        Args: { target_organization_id: string }
        Returns: Json
      }
      organization_tax_default_property_count: {
        Args: { target_organization_id: string }
        Returns: number
      }
      organization_tax_picker: {
        Args: { target_organization_id: string; target_property_id?: string }
        Returns: {
          name: string
          rate_basis_points: number
          rate_id: string
          source: string
        }[]
      }
      organization_tax_rate_property_count: {
        Args: { target_organization_id: string; target_rate_id: string }
        Returns: number
      }
      owner_email_is_available: {
        Args: { candidate_email: string }
        Returns: boolean
      }
      owner_organization_directory: {
        Args: {
          attention_reason?: string
          cursor_created_at?: string
          cursor_id?: string
          page_size?: number
          search_term?: string
        }
        Returns: Json
      }
      pipeline_board_page: {
        Args: {
          created_from?: string
          created_to?: string
          cursor_id?: string
          cursor_phase?: number
          cursor_sort_key?: string
          cursor_timestamp?: string
          cursor_value?: number
          filter_owner_user_id?: string
          owner_filter?: string
          page_limit?: number
          sort_direction?: string
          sort_key?: string
          target_organization_id: string
          target_stage: string
        }
        Returns: {
          assessment_ends_at: string
          assessment_starts_at: string
          client_company_name: string
          client_display_name: string
          client_id: string
          created_at: string
          estimated_value: number
          expected_close_on: string
          id: string
          next_follow_up_on: string
          outcome: string
          owner_avatar_url: string
          owner_full_name: string
          owner_user_id: string
          property_address_line1: string
          property_city: string
          property_id: string
          property_label: string
          property_postal_code: string
          property_state_region: string
          quote_id: string
          quote_status: string
          request_id: string
          request_status: string
          stage: string
          stage_entered_at: string
          task_due_on: string
          task_id: string
          task_title: string
          title: string
        }[]
      }
      pipeline_create_opportunity_note: {
        Args: {
          new_body: string
          target_entity_type: string
          target_opportunity_id: string
        }
        Returns: {
          body: string
          created_at: string
          created_by: string
          edited_at: string
          edited_by: string
          entity_id: string
          entity_type: string
          id: string
          pinned: boolean
          updated_at: string
        }[]
      }
      pipeline_create_opportunity_task: {
        Args: {
          new_assignee_user_id?: string
          new_due_on?: string
          new_instructions?: string
          new_title: string
          target_opportunity_id: string
        }
        Returns: {
          assignee_user_id: string
          completed_at: string
          completed_by: string
          created_at: string
          created_by: string
          due_on: string
          id: string
          instructions: string
          opportunity_id: string
          status: string
          title: string
          updated_at: string
        }[]
      }
      pipeline_delete_opportunity_note: {
        Args: {
          target_entity_type: string
          target_note_id: string
          target_opportunity_id: string
        }
        Returns: {
          note_deleted: boolean
          unlinked: boolean
        }[]
      }
      pipeline_delete_task: {
        Args: { target_task_id: string }
        Returns: {
          id: string
          opportunity_id: string
        }[]
      }
      pipeline_drag_opportunity: {
        Args: { target_opportunity_id: string; to_stage: string }
        Returns: Json
      }
      pipeline_mark_opportunity_lost: {
        Args: {
          idempotency_key: string
          note?: string
          occurred_at?: string
          reason?: string
          target_opportunity_id: string
        }
        Returns: Json
      }
      pipeline_opportunity_notes: {
        Args: { target_opportunity_id: string }
        Returns: {
          body: string
          created_at: string
          created_by: string
          edited_at: string
          edited_by: string
          entity_id: string
          entity_type: string
          id: string
          pinned: boolean
          updated_at: string
        }[]
      }
      pipeline_outcome_page: {
        Args: {
          cursor_id?: string
          cursor_numeric?: number
          cursor_phase?: number
          cursor_sort_key?: string
          cursor_text?: string
          cursor_timestamp?: string
          outcome_from?: string
          outcome_to?: string
          outcome_type: string
          page_limit?: number
          sort_direction?: string
          sort_key?: string
          target_organization_id: string
        }
        Returns: {
          client_company_name: string
          client_display_name: string
          client_id: string
          created_at: string
          estimated_value: number
          id: string
          outcome: string
          outcome_at: string
          title: string
        }[]
      }
      pipeline_outcome_tiles: {
        Args: {
          target_organization_id: string
          tile_from: string
          tile_to: string
        }
        Returns: {
          closed_count: number
          outcome_key: string
          value_total: number
        }[]
      }
      pipeline_reopen_opportunity: {
        Args: {
          idempotency_key: string
          occurred_at?: string
          reopen_explanation: string
          target_opportunity_id: string
        }
        Returns: Json
      }
      pipeline_set_task_completed: {
        Args: { is_completed: boolean; target_task_id: string }
        Returns: {
          assignee_user_id: string
          completed_at: string
          completed_by: string
          created_at: string
          created_by: string
          due_on: string
          id: string
          instructions: string
          opportunity_id: string
          status: string
          title: string
          updated_at: string
        }[]
      }
      pipeline_stage_counts: {
        Args: {
          created_from?: string
          created_to?: string
          filter_owner_user_id?: string
          owner_filter?: string
          target_organization_id: string
        }
        Returns: {
          open_count: number
          stage_key: string
          value_total: number
        }[]
      }
      pipeline_update_opportunity_details: {
        Args: {
          new_estimated_value?: number
          new_expected_close_on?: string
          new_next_follow_up_on?: string
          new_owner_user_id?: string
          set_expected_close?: boolean
          set_next_follow_up?: boolean
          set_owner?: boolean
          set_value?: boolean
          target_opportunity_id: string
        }
        Returns: {
          estimated_value: number
          expected_close_on: string
          id: string
          next_follow_up_on: string
          owner_user_id: string
          updated_at: string
        }[]
      }
      pipeline_update_opportunity_note: {
        Args: {
          new_body: string
          target_note_id: string
          target_opportunity_id: string
        }
        Returns: {
          body: string
          created_at: string
          created_by: string
          edited_at: string
          edited_by: string
          entity_id: string
          entity_type: string
          id: string
          pinned: boolean
          updated_at: string
        }[]
      }
      pipeline_update_opportunity_task: {
        Args: {
          new_assignee_user_id?: string
          new_due_on?: string
          new_instructions?: string
          new_title: string
          target_task_id: string
        }
        Returns: {
          assignee_user_id: string
          completed_at: string
          completed_by: string
          created_at: string
          created_by: string
          due_on: string
          id: string
          instructions: string
          opportunity_id: string
          status: string
          title: string
          updated_at: string
        }[]
      }
      post_website_chat_message: {
        Args: {
          message_body: string
          new_idempotency_key?: string
          requesting_origin: string
          session_token_hash: string
        }
        Returns: Json
      }
      post_website_chat_staff_message: {
        Args: {
          message_body: string
          new_idempotency_key?: string
          target_actor_user_id: string
          target_organization_id: string
          target_session_id: string
        }
        Returns: Json
      }
      prepare_team_invitation_identity_cleanup: {
        Args: { target_invitation_id: string; target_lease_nonce: string }
        Returns: {
          accepted_at: string | null
          auth_attempt_nonce: string | null
          auth_attempt_started_at: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          expires_at: string | null
          id: string
          identity_cleanup_error: string | null
          identity_cleanup_state: string
          invited_by: string | null
          invited_email: string
          invited_user_id: string | null
          last_delivery_error: string | null
          last_sent_at: string | null
          lease_expires_at: string | null
          lease_nonce: string | null
          organization_id: string
          password_set_at: string | null
          reconciliation_lease_expires_at: string | null
          reconciliation_nonce: string | null
          requested_permission_overrides: Json
          role: string
          state: string
          token_hash: string | null
        }
        SetofOptions: {
          from: "*"
          to: "organization_member_invitations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      preview_organization_closure_impact: {
        Args: { target_organization_id: string }
        Returns: Json
      }
      preview_quote_version_totals: {
        Args: { selected_addon_ids?: string[]; target_quote_id: string }
        Returns: Json
      }
      pricing_line_total_minor: {
        Args: { quantity: number; unit_price_minor: number }
        Returns: number
      }
      process_communication_provider_callbacks: {
        Args: { batch_size?: number }
        Returns: number
      }
      provision_organization_from_application: {
        Args: {
          target_actor_owner_email?: string
          target_administrator_role?: string
          target_administrator_user_id: string
          target_application_id: string
          target_organization_id: string
          target_organization_name: string
          target_slug: string
        }
        Returns: string
      }
      publish_message_template: {
        Args: { actor_email: string; target_template_key: string }
        Returns: {
          body_draft: string
          body_published: string | null
          created_at: string
          published_at: string | null
          published_by_owner_email: string | null
          published_version: number
          subject_draft: string | null
          subject_published: string | null
          template_key: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "platform_message_templates"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      publish_quote: {
        Args: { expected_revision: number; target_quote_id: string }
        Returns: Json
      }
      quarantine_stale_communication_claims: {
        Args: { batch_size?: number; stale_after?: string }
        Returns: number
      }
      quarantine_stale_communication_forward_claims: {
        Args: { batch_size?: number; stale_after?: string }
        Returns: number
      }
      quote_access_link_state: {
        Args: { target_quote_id: string }
        Returns: Json
      }
      quote_current_signature: {
        Args: { target_quote_id: string }
        Returns: Json
      }
      quote_customer_preview: {
        Args: { target_quote_id: string }
        Returns: Json
      }
      quote_ready_for_job: {
        Args: { target_quote_id: string }
        Returns: boolean
      }
      quote_status_counts: {
        Args: { target_organization_id: string }
        Returns: {
          status: string
          total: number
        }[]
      }
      record_communication_inbound_message: {
        Args: {
          target_candidate_recipients?: Json
          target_cc_recipients?: Json
          target_html_content?: string
          target_in_reply_to_provider_message_id?: string
          target_message_kind?: string
          target_provider_callback_event_id?: string
          target_provider_message_id?: string
          target_sender_email?: string
          target_sender_name?: string
          target_subject?: string
          target_text_content?: string
          target_to_recipients?: Json
        }
        Returns: {
          attachment_count: number
          automation_suppressed: boolean
          cc_recipients: Json
          client_contact_method_id: string | null
          client_id: string | null
          created_at: string
          direction: string
          html_content: string | null
          id: string
          in_reply_to_intent_id: string | null
          in_reply_to_provider_message_id: string | null
          loop_detected_at: string | null
          message_kind: string
          organization_id: string
          owner_user_id: string | null
          provider: string
          provider_callback_event_id: string | null
          provider_message_id: string | null
          reply_alias_id: string | null
          review_reason: string | null
          review_resolved_at: string | null
          review_resolved_by: string | null
          review_status: string
          sender_email: string
          sender_id: string | null
          sender_name: string | null
          subject: string
          text_content: string
          to_recipients: Json
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "communication_inbound_messages"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      record_invitation_password_set: {
        Args: { target_invitation_id: string; target_lease_nonce: string }
        Returns: {
          accepted_at: string | null
          auth_attempt_nonce: string | null
          auth_attempt_started_at: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          expires_at: string | null
          id: string
          identity_cleanup_error: string | null
          identity_cleanup_state: string
          invited_by: string | null
          invited_email: string
          invited_user_id: string | null
          last_delivery_error: string | null
          last_sent_at: string | null
          lease_expires_at: string | null
          lease_nonce: string | null
          organization_id: string
          password_set_at: string | null
          reconciliation_lease_expires_at: string | null
          reconciliation_nonce: string | null
          requested_permission_overrides: Json
          role: string
          state: string
          token_hash: string | null
        }
        SetofOptions: {
          from: "*"
          to: "organization_member_invitations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      record_legacy_organization_package: {
        Args: {
          target_organization_id: string
          target_package_version_id: string
          target_paid_through_date: string
          target_reason: string
        }
        Returns: undefined
      }
      record_quote_decision: {
        Args: {
          decision_note?: string
          expected_revision?: number
          new_decision: string
          target_quote_id: string
        }
        Returns: Json
      }
      record_quote_deposit_event: {
        Args: {
          idempotency_key: string
          method: string
          note?: string
          reference?: string
          target_quote_id: string
        }
        Returns: Json
      }
      record_quote_in_person_signature: {
        Args: {
          decision_note?: string
          expected_revision?: number
          signature_byte_size?: number
          signature_method?: string
          signature_object_key?: string
          signer_name: string
          target_quote_id: string
        }
        Returns: Json
      }
      record_quote_link_view: {
        Args: { supplied_token_hash: string }
        Returns: Json
      }
      record_team_invitation_delivery: {
        Args: {
          target_error?: string
          target_invitation_id: string
          target_success: boolean
        }
        Returns: {
          accepted_at: string | null
          auth_attempt_nonce: string | null
          auth_attempt_started_at: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          expires_at: string | null
          id: string
          identity_cleanup_error: string | null
          identity_cleanup_state: string
          invited_by: string | null
          invited_email: string
          invited_user_id: string | null
          last_delivery_error: string | null
          last_sent_at: string | null
          lease_expires_at: string | null
          lease_nonce: string | null
          organization_id: string
          password_set_at: string | null
          reconciliation_lease_expires_at: string | null
          reconciliation_nonce: string | null
          requested_permission_overrides: Json
          role: string
          state: string
          token_hash: string | null
        }
        SetofOptions: {
          from: "*"
          to: "organization_member_invitations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      release_team_invitation_reconciliation: {
        Args: {
          target_invitation_id: string
          target_lease_nonce: string
          target_safe_error: string
        }
        Returns: {
          accepted_at: string | null
          auth_attempt_nonce: string | null
          auth_attempt_started_at: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          expires_at: string | null
          id: string
          identity_cleanup_error: string | null
          identity_cleanup_state: string
          invited_by: string | null
          invited_email: string
          invited_user_id: string | null
          last_delivery_error: string | null
          last_sent_at: string | null
          lease_expires_at: string | null
          lease_nonce: string | null
          organization_id: string
          password_set_at: string | null
          reconciliation_lease_expires_at: string | null
          reconciliation_nonce: string | null
          requested_permission_overrides: Json
          role: string
          state: string
          token_hash: string | null
        }
        SetofOptions: {
          from: "*"
          to: "organization_member_invitations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      remove_organization_logo: {
        Args: { target_organization_id: string }
        Returns: Json
      }
      remove_team_member: {
        Args: {
          actor_user_id: string
          target_organization_id: string
          target_user_id: string
        }
        Returns: {
          access_revision: number
          created_at: string
          deactivated_at: string | null
          display_name_at_removal: string | null
          identity_cleanup_error: string | null
          identity_cleanup_state: string
          job_title: string | null
          organization_id: string
          profile_revision: number
          removed_at: string | null
          role: string
          schedule_color: string | null
          status: string
          status_changed_at: string | null
          status_changed_by: string | null
          user_id: string
          work_phone: string | null
        }
        SetofOptions: {
          from: "*"
          to: "organization_members"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      remove_website_chat_widget_origin: {
        Args: {
          target_organization_id: string
          target_origin_id: string
          target_widget_id: string
        }
        Returns: Json
      }
      rotate_website_chat_widget_public_token: {
        Args: {
          p_actor_email: string
          p_expected_revision: number
          p_idempotency_key: string
          p_organization_id: string
          p_reason: string
          p_widget_id: string
        }
        Returns: Json
      }
      replace_quote_version_attachments: {
        Args: {
          expected_revision: number
          new_attachments: Json
          target_quote_id: string
        }
        Returns: Json
      }
      replace_quote_version_lines: {
        Args: {
          expected_revision: number
          new_lines: Json
          target_quote_id: string
        }
        Returns: Json
      }
      replace_request_pricing_lines: {
        Args: {
          expected_revision: number
          new_lines: Json
          target_request_id: string
        }
        Returns: Json
      }
      request_communication_email_suppression_removal: {
        Args: {
          p_actor_email: string
          p_actor_user_id: string
          p_consent_confirmed: boolean
          p_evidence: string
          p_organization_id: string
          p_reason: string
          p_suppression_id: string
        }
        Returns: Json
      }
      request_ownership_transfer: {
        Args: {
          requesting_user_id: string
          target_organization_id: string
          target_user_id: string
        }
        Returns: {
          from_user_id: string
          id: string
          organization_id: string
          requested_at: string
          resolved_at: string | null
          resolved_by: string | null
          state: string
          to_user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "organization_ownership_transfers"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_organization_website_chat_suspension: {
        Args: {
          p_actor_email: string
          p_engage: boolean
          p_idempotency_key: string
          p_organization_id: string
          p_reason: string
        }
        Returns: Json
      }
      request_status_counts: {
        Args: {
          day_end: string
          day_start: string
          target_organization_id: string
        }
        Returns: {
          display_status: string
          total: number
        }[]
      }
      resend_communication_email: {
        Args: {
          target_actor_user_id: string
          target_logical_send_key: string
          target_organization_id: string
          target_original_intent_id: string
          target_quote_token_hash?: string
          target_quote_url?: string
        }
        Returns: {
          accepted_at: string | null
          allowance_class: string
          channel: string
          client_contact_method_id: string
          client_id: string
          created_at: string
          created_by: string | null
          delivery_outcome: string | null
          delivery_outcome_at: string | null
          delivery_outcome_detail: string | null
          direction: string
          expires_at: string
          failure_code: string | null
          failure_message: string | null
          html_content: string
          id: string
          logical_send_key: string
          organization_id: string
          provider_message_id: string | null
          quote_id: string | null
          recipient_email: string
          reply_alias_id: string | null
          resent_from_intent_id: string | null
          retry_class: string
          retry_window_ends_at: string | null
          send_kind: string
          sender_id: string | null
          status: string
          subject: string
          text_content: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "communication_delivery_intents"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      resend_team_invitation: {
        Args: {
          target_expires_at: string
          target_invitation_id: string
          target_token_hash: string
        }
        Returns: {
          accepted_at: string | null
          auth_attempt_nonce: string | null
          auth_attempt_started_at: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          expires_at: string | null
          id: string
          identity_cleanup_error: string | null
          identity_cleanup_state: string
          invited_by: string | null
          invited_email: string
          invited_user_id: string | null
          last_delivery_error: string | null
          last_sent_at: string | null
          lease_expires_at: string | null
          lease_nonce: string | null
          organization_id: string
          password_set_at: string | null
          reconciliation_lease_expires_at: string | null
          reconciliation_nonce: string | null
          requested_permission_overrides: Json
          role: string
          state: string
          token_hash: string | null
        }
        SetofOptions: {
          from: "*"
          to: "organization_member_invitations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      resolve_inbound_message_review: {
        Args: {
          target_actor_user_id: string
          target_client_id?: string
          target_organization_id: string
          target_resolution: string
          target_sender_email: string
        }
        Returns: number
      }
      resolve_quote_access_link: {
        Args: { supplied_token_hash: string }
        Returns: Json
      }
      resolve_website_chat_session_identity: {
        Args: {
          target_actor_user_id: string
          target_client_id: string
          target_organization_id: string
          target_session_id: string
        }
        Returns: Json
      }
      restore_quote: { Args: { target_quote_id: string }; Returns: Json }
      restore_team_member: {
        Args: {
          actor_user_id: string
          target_organization_id: string
          target_user_id: string
        }
        Returns: {
          access_revision: number
          created_at: string
          deactivated_at: string | null
          display_name_at_removal: string | null
          identity_cleanup_error: string | null
          identity_cleanup_state: string
          job_title: string | null
          organization_id: string
          profile_revision: number
          removed_at: string | null
          role: string
          schedule_color: string | null
          status: string
          status_changed_at: string | null
          status_changed_by: string | null
          user_id: string
          work_phone: string | null
        }
        SetofOptions: {
          from: "*"
          to: "organization_members"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      resume_communication_email_reputation_pause: {
        Args: {
          p_actor_email: string
          p_confirm_remediation?: boolean
          p_organization_id: string
          p_reason: string
        }
        Returns: Json
      }
      retry_communication_message: {
        Args: {
          p_actor_email: string
          p_delivery_intent_id: string
          p_reason: string
        }
        Returns: Json
      }
      reverse_onboarding_application_payment: {
        Args: {
          actor_email: string
          reason: string
          target_application_id: string
        }
        Returns: undefined
      }
      reverse_quote_deposit_event: {
        Args: {
          idempotency_key: string
          reason: string
          target_event_id: string
          target_quote_id: string
        }
        Returns: Json
      }
      revise_quote: { Args: { target_quote_id: string }; Returns: Json }
      revoke_quote_access_link: {
        Args: { target_link_id: string }
        Returns: Json
      }
      save_organization_branding: {
        Args: {
          expected_revision: number
          new_brand_color: string
          target_organization_id: string
        }
        Returns: Json
      }
      save_organization_business_hours: {
        Args: {
          expected_revision: number
          new_hours: Json
          new_mode: string
          target_organization_id: string
        }
        Returns: Json
      }
      save_organization_business_profile: {
        Args: {
          confirm_currency: boolean
          confirm_timezone: boolean
          expected_revision: number
          new_address_is_public: boolean
          new_address_line1: string
          new_address_line2: string
          new_city: string
          new_country_code: string
          new_currency_code: string
          new_description: string
          new_name: string
          new_phone: string
          new_postal_code: string
          new_region: string
          new_timezone: string
          new_trade: string
          new_website: string
          target_organization_id: string
        }
        Returns: Json
      }
      save_pipeline_presentation: {
        Args: {
          expected_revision: number
          new_detailed_assessment_stages: boolean
          target_organization_id: string
        }
        Returns: Json
      }
      save_team_member_permissions: {
        Args: {
          actor_user_id: string
          desired_overrides: Json
          expected_access_revision: number
          target_organization_id: string
          target_user_id: string
        }
        Returns: {
          access_revision: number
          created_at: string
          deactivated_at: string | null
          display_name_at_removal: string | null
          identity_cleanup_error: string | null
          identity_cleanup_state: string
          job_title: string | null
          organization_id: string
          profile_revision: number
          removed_at: string | null
          role: string
          schedule_color: string | null
          status: string
          status_changed_at: string | null
          status_changed_by: string | null
          user_id: string
          work_phone: string | null
        }
        SetofOptions: {
          from: "*"
          to: "organization_members"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      set_communication_email_organization_pause: {
        Args: {
          p_actor_email: string
          p_engage: boolean
          p_organization_id: string
          p_reason: string
        }
        Returns: string
      }
      set_communication_email_platform_pause: {
        Args: { p_actor_email: string; p_engage: boolean; p_reason: string }
        Returns: string
      }
      set_communication_email_provider_capacity: {
        Args: {
          p_actor_email: string
          p_capacity: number
          p_confirm_platform_change?: boolean
          p_reason: string
          p_reserve_percent: number
        }
        Returns: Json
      }
      set_communication_email_reputation_threshold: {
        Args: {
          p_actor_email: string
          p_confirm_platform_change?: boolean
          p_min_event_count: number
          p_min_sample_recipients: number
          p_organization_id: string
          p_pause_rate: number
          p_reason: string
          p_scope: string
          p_signal: string
          p_warn_rate: number
          p_window_hours: number
          p_window_key: string
        }
        Returns: Json
      }
      set_communication_email_short_term_rate: {
        Args: {
          p_actor_email: string
          p_confirm_platform_change?: boolean
          p_max_recipients: number
          p_reason: string
          p_window_minutes: number
        }
        Returns: Json
      }
      set_communication_email_warmup_stage: {
        Args: {
          p_actor_email: string
          p_confirm_platform_change?: boolean
          p_daily_ceiling: number
          p_reason: string
          p_stage_key: string
        }
        Returns: Json
      }
      set_organization_logo: {
        Args: { new_object_key: string; target_organization_id: string }
        Returns: Json
      }
      set_organization_quote_representative: {
        Args: {
          expected_revision: number
          new_enabled: boolean
          new_name: string
          new_signature_object_key: string
          new_title: string
          target_organization_id: string
        }
        Returns: Json
      }
      set_organization_quote_signature_policy: {
        Args: {
          expected_revision: number
          new_require_signature: boolean
          target_organization_id: string
        }
        Returns: Json
      }
      set_organization_quote_target_margin: {
        Args: {
          expected_revision: number
          new_margin_basis_points: number
          target_organization_id: string
        }
        Returns: Json
      }
      set_organization_quote_terms: {
        Args: {
          expected_revision: number
          new_terms: string
          target_organization_id: string
        }
        Returns: Json
      }
      set_organization_tax_default: {
        Args: {
          expected_revision: number
          new_rate_id: string
          new_source: string
          target_organization_id: string
        }
        Returns: Json
      }
      set_organization_tax_rate_active: {
        Args: {
          expected_revision: number
          new_is_active: boolean
          target_organization_id: string
          target_rate_id: string
        }
        Returns: Json
      }
      set_quote_draft_copy: {
        Args: {
          expected_revision: number
          new_client_message: string
          new_introduction: string
          target_quote_id: string
        }
        Returns: Json
      }
      set_quote_draft_deposit: {
        Args: {
          expected_revision: number
          new_deposit_type: string
          new_items: Json
          target_quote_id: string
        }
        Returns: Json
      }
      set_quote_draft_discount: {
        Args: {
          expected_revision: number
          new_name: string
          new_type: string
          new_value: number
          target_quote_id: string
        }
        Returns: Json
      }
      set_quote_draft_tax: {
        Args: {
          expected_revision: number
          new_custom_name?: string
          new_custom_rate_basis_points?: number
          new_rate_id?: string
          new_source: string
          save_as_reusable?: boolean
          target_quote_id: string
        }
        Returns: Json
      }
      set_quote_draft_visibility: {
        Args: {
          expected_revision: number
          new_show_line_totals: boolean
          new_show_quantities: boolean
          new_show_totals: boolean
          new_show_unit_prices: boolean
          target_quote_id: string
        }
        Returns: Json
      }
      settle_team_invitation_identity_cleanup: {
        Args: { target_invitation_id: string; target_lease_nonce: string }
        Returns: {
          accepted_at: string | null
          auth_attempt_nonce: string | null
          auth_attempt_started_at: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          expires_at: string | null
          id: string
          identity_cleanup_error: string | null
          identity_cleanup_state: string
          invited_by: string | null
          invited_email: string
          invited_user_id: string | null
          last_delivery_error: string | null
          last_sent_at: string | null
          lease_expires_at: string | null
          lease_nonce: string | null
          organization_id: string
          password_set_at: string | null
          reconciliation_lease_expires_at: string | null
          reconciliation_nonce: string | null
          requested_permission_overrides: Json
          role: string
          state: string
          token_hash: string | null
        }
        SetofOptions: {
          from: "*"
          to: "organization_member_invitations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      submit_onboarding_application: {
        Args: {
          target_business_name: string
          target_city_country: string
          target_initial_administrator_email: string
          target_initial_administrator_name: string
          target_main_contact_email: string
          target_main_contact_name: string
          target_main_contact_phone: string
          target_note: string
          target_package_version_id: string
          target_privacy_policy_version: string
          target_submitted_data: Json
          target_time_zone: string
          target_trade: string
        }
        Returns: string
      }
      submit_quote_customer_decision: {
        Args: {
          customer_note?: string
          new_outcome: string
          signature_byte_size?: number
          signature_method?: string
          signature_name?: string
          signature_object_key?: string
          supplied_evidence?: Json
          supplied_token_hash: string
        }
        Returns: Json
      }
      sweep_communication_email_reputation: {
        Args: { batch_size?: number }
        Returns: number
      }
      sweep_team_invitation_reservations: {
        Args: { stale_after?: string }
        Returns: {
          accepted_at: string | null
          auth_attempt_nonce: string | null
          auth_attempt_started_at: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          expires_at: string | null
          id: string
          identity_cleanup_error: string | null
          identity_cleanup_state: string
          invited_by: string | null
          invited_email: string
          invited_user_id: string | null
          last_delivery_error: string | null
          last_sent_at: string | null
          lease_expires_at: string | null
          lease_nonce: string | null
          organization_id: string
          password_set_at: string | null
          reconciliation_lease_expires_at: string | null
          reconciliation_nonce: string | null
          requested_permission_overrides: Json
          role: string
          state: string
          token_hash: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "organization_member_invitations"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      sweep_team_invitation_reservations_bounded: {
        Args: { target_batch_size?: number; target_stale_after?: string }
        Returns: {
          accepted_at: string | null
          auth_attempt_nonce: string | null
          auth_attempt_started_at: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          expires_at: string | null
          id: string
          identity_cleanup_error: string | null
          identity_cleanup_state: string
          invited_by: string | null
          invited_email: string
          invited_user_id: string | null
          last_delivery_error: string | null
          last_sent_at: string | null
          lease_expires_at: string | null
          lease_nonce: string | null
          organization_id: string
          password_set_at: string | null
          reconciliation_lease_expires_at: string | null
          reconciliation_nonce: string | null
          requested_permission_overrides: Json
          role: string
          state: string
          token_hash: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "organization_member_invitations"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      update_catalog_item: {
        Args: {
          expected_revision: number
          new_category: string
          new_description: string
          new_is_labor: boolean
          new_is_taxable: boolean
          new_name: string
          new_unit_cost_minor: number
          new_unit_label: string
          new_unit_price_minor: number
          target_item_id: string
          target_organization_id: string
        }
        Returns: Json
      }
      update_client: {
        Args: { payload: Json }
        Returns: {
          archived_at: string | null
          client_type: string
          company_name: string | null
          converted_to_customer_at: string | null
          created_at: string
          deleted_at: string | null
          display_name: string
          first_name: string | null
          id: string
          last_name: string | null
          lead_source: string | null
          lead_temperature: string | null
          lifecycle_status: string
          next_follow_up_at: string | null
          organization_id: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "clients"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      update_organization_tax_rate: {
        Args: {
          expected_revision: number
          new_name: string
          new_rate_basis_points: number
          target_organization_id: string
          target_rate_id: string
        }
        Returns: Json
      }
      update_owner_settings: {
        Args: {
          actor_email: string
          new_alert_recipient_emails: string[]
          new_payment_instructions: string
          new_privacy_policy_url: string
          new_privacy_policy_version: string
          new_reply_to_address: string
          new_sender_display_name: string
        }
        Returns: {
          alert_recipient_emails: string[]
          created_at: string
          id: boolean
          payment_instructions: string
          privacy_policy_url: string
          privacy_policy_version: string
          reply_to_address: string
          sender_display_name: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "platform_owner_settings"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      update_quote_draft: {
        Args: {
          expected_revision: number
          new_disclaimer: string
          new_title: string
          target_quote_id: string
        }
        Returns: Json
      }
      update_team_member_profile: {
        Args: {
          actor_user_id: string
          expected_profile_revision: number
          new_full_name: string
          new_job_title: string
          new_schedule_color: string
          new_work_phone: string
          target_organization_id: string
          target_user_id: string
        }
        Returns: {
          access_revision: number
          created_at: string
          deactivated_at: string | null
          display_name_at_removal: string | null
          identity_cleanup_error: string | null
          identity_cleanup_state: string
          job_title: string | null
          organization_id: string
          profile_revision: number
          removed_at: string | null
          role: string
          schedule_color: string | null
          status: string
          status_changed_at: string | null
          status_changed_by: string | null
          user_id: string
          work_phone: string | null
        }
        SetofOptions: {
          from: "*"
          to: "organization_members"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      update_website_chat_widget: {
        Args: {
          expected_revision: number
          new_availability_visibility_mode: string
          new_channel_options: Json
          new_contact_requirement: string
          new_disabled: boolean
          new_greeting_text: string
          new_launcher_position: string
          new_name: string
          new_privacy_policy_url: string
          new_published: boolean
          new_source_label: string
          new_teaser_text: string
          target_organization_id: string
          target_widget_id: string
        }
        Returns: Json
      }
      withdraw_communication_email_suppression_removal: {
        Args: {
          p_actor_email: string
          p_actor_user_id: string
          p_organization_id: string
          p_suppression_id: string
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
