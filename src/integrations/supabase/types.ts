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
    PostgrestVersion: "14.18"
  }
  public: {
    Tables: {
      absence_justifications: {
        Row: {
          absence_date: string | null
          created_at: string
          id: string
          reason: string
          record_id: string | null
          review_note: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          student_id: string
          updated_at: string
        }
        Insert: {
          absence_date?: string | null
          created_at?: string
          id?: string
          reason: string
          record_id?: string | null
          review_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          student_id: string
          updated_at?: string
        }
        Update: {
          absence_date?: string | null
          created_at?: string
          id?: string
          reason?: string
          record_id?: string | null
          review_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          student_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "absence_justifications_record_id_fkey"
            columns: ["record_id"]
            isOneToOne: false
            referencedRelation: "attendance_records"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "absence_justifications_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      access_settings: {
        Row: {
          key: string
          updated_at: string
          updated_by: string | null
          value: number
        }
        Insert: {
          key: string
          updated_at?: string
          updated_by?: string | null
          value: number
        }
        Update: {
          key?: string
          updated_at?: string
          updated_by?: string | null
          value?: number
        }
        Relationships: []
      }
      account_claim_tokens: {
        Row: {
          claimed_by: string | null
          code: string
          created_at: string
          expires_at: string
          id: string
          issued_by: string | null
          kind: string
          status: string
          student_id: string | null
          teacher_code: string | null
          used_at: string | null
        }
        Insert: {
          claimed_by?: string | null
          code: string
          created_at?: string
          expires_at?: string
          id?: string
          issued_by?: string | null
          kind: string
          status?: string
          student_id?: string | null
          teacher_code?: string | null
          used_at?: string | null
        }
        Update: {
          claimed_by?: string | null
          code?: string
          created_at?: string
          expires_at?: string
          id?: string
          issued_by?: string | null
          kind?: string
          status?: string
          student_id?: string | null
          teacher_code?: string | null
          used_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "account_claim_tokens_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "account_claim_tokens_teacher_code_fkey"
            columns: ["teacher_code"]
            isOneToOne: false
            referencedRelation: "teacher_directory"
            referencedColumns: ["code"]
          },
        ]
      }
      account_login_codes: {
        Row: {
          code: string
          created_at: string
          user_id: string
        }
        Insert: {
          code: string
          created_at?: string
          user_id: string
        }
        Update: {
          code?: string
          created_at?: string
          user_id?: string
        }
        Relationships: []
      }
      appearance_settings: {
        Row: {
          created_at: string
          id: string
          is_global: boolean
          settings: Json
          updated_at: string
          user_id: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          is_global?: boolean
          settings?: Json
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          is_global?: boolean
          settings?: Json
          updated_at?: string
          user_id?: string | null
        }
        Relationships: []
      }
      attendance_records: {
        Row: {
          created_at: string
          id: string
          justification_note: string | null
          justified_at: string | null
          justified_by: string | null
          note: string | null
          session_id: string
          status: string
          student_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          justification_note?: string | null
          justified_at?: string | null
          justified_by?: string | null
          note?: string | null
          session_id: string
          status?: string
          student_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          justification_note?: string | null
          justified_at?: string | null
          justified_by?: string | null
          note?: string | null
          session_id?: string
          status?: string
          student_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "attendance_records_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "attendance_sessions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_records_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      attendance_sessions: {
        Row: {
          class_id: string
          created_at: string
          group_scope: string
          id: string
          note: string | null
          period: string | null
          session_date: string
          session_type: string
          slot_id: string | null
          subject: string | null
          teacher_edit_count: number
          teacher_id: string
          updated_at: string
        }
        Insert: {
          class_id: string
          created_at?: string
          group_scope?: string
          id?: string
          note?: string | null
          period?: string | null
          session_date?: string
          session_type?: string
          slot_id?: string | null
          subject?: string | null
          teacher_edit_count?: number
          teacher_id: string
          updated_at?: string
        }
        Update: {
          class_id?: string
          created_at?: string
          group_scope?: string
          id?: string
          note?: string | null
          period?: string | null
          session_date?: string
          session_type?: string
          slot_id?: string | null
          subject?: string | null
          teacher_edit_count?: number
          teacher_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "attendance_sessions_class_id_fkey"
            columns: ["class_id"]
            isOneToOne: false
            referencedRelation: "classes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_sessions_slot_id_fkey"
            columns: ["slot_id"]
            isOneToOne: false
            referencedRelation: "schedule_slots"
            referencedColumns: ["id"]
          },
        ]
      }
      behavior_records: {
        Row: {
          created_at: string
          id: string
          note: string | null
          points: number
          record_type: string
          recorded_at: string
          recorded_by: string | null
          student_id: string | null
          title: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          note?: string | null
          points?: number
          record_type?: string
          recorded_at?: string
          recorded_by?: string | null
          student_id?: string | null
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          note?: string | null
          points?: number
          record_type?: string
          recorded_at?: string
          recorded_by?: string | null
          student_id?: string | null
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "behavior_records_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      card_scans: {
        Row: {
          card_uid: string
          direction: string
          gate_id: string | null
          id: string
          mode: string
          note: string | null
          scanned_at: string
          scanned_by: string | null
          student_id: string | null
          visitor_name: string | null
        }
        Insert: {
          card_uid: string
          direction?: string
          gate_id?: string | null
          id?: string
          mode?: string
          note?: string | null
          scanned_at?: string
          scanned_by?: string | null
          student_id?: string | null
          visitor_name?: string | null
        }
        Update: {
          card_uid?: string
          direction?: string
          gate_id?: string | null
          id?: string
          mode?: string
          note?: string | null
          scanned_at?: string
          scanned_by?: string | null
          student_id?: string | null
          visitor_name?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "card_scans_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      claim_attempts: {
        Row: {
          failed_count: number
          locked_until: string | null
          user_id: string
        }
        Insert: {
          failed_count?: number
          locked_until?: string | null
          user_id: string
        }
        Update: {
          failed_count?: number
          locked_until?: string | null
          user_id?: string
        }
        Relationships: []
      }
      class_representatives: {
        Row: {
          assigned_by: string | null
          class_id: string
          created_at: string
          id: string
          kind: string
          student_id: string
          user_id: string
        }
        Insert: {
          assigned_by?: string | null
          class_id: string
          created_at?: string
          id?: string
          kind: string
          student_id: string
          user_id: string
        }
        Update: {
          assigned_by?: string | null
          class_id?: string
          created_at?: string
          id?: string
          kind?: string
          student_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "class_representatives_class_id_fkey"
            columns: ["class_id"]
            isOneToOne: false
            referencedRelation: "classes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "class_representatives_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      class_teachers: {
        Row: {
          class_id: string
          created_at: string
          id: string
          subject: string | null
          teacher_id: string
          updated_at: string
        }
        Insert: {
          class_id: string
          created_at?: string
          id?: string
          subject?: string | null
          teacher_id: string
          updated_at?: string
        }
        Update: {
          class_id?: string
          created_at?: string
          id?: string
          subject?: string | null
          teacher_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "class_teachers_class_id_fkey"
            columns: ["class_id"]
            isOneToOne: false
            referencedRelation: "classes"
            referencedColumns: ["id"]
          },
        ]
      }
      classes: {
        Row: {
          branch: string | null
          created_at: string
          head_teacher_id: string | null
          id: string
          level: string | null
          name: string
        }
        Insert: {
          branch?: string | null
          created_at?: string
          head_teacher_id?: string | null
          id?: string
          level?: string | null
          name: string
        }
        Update: {
          branch?: string | null
          created_at?: string
          head_teacher_id?: string | null
          id?: string
          level?: string | null
          name?: string
        }
        Relationships: []
      }
      custom_role_permissions: {
        Row: {
          allowed: boolean
          permission: string
          role_key: string
        }
        Insert: {
          allowed?: boolean
          permission: string
          role_key: string
        }
        Update: {
          allowed?: boolean
          permission?: string
          role_key?: string
        }
        Relationships: [
          {
            foreignKeyName: "custom_role_permissions_role_key_fkey"
            columns: ["role_key"]
            isOneToOne: false
            referencedRelation: "role_definitions"
            referencedColumns: ["key"]
          },
        ]
      }
      custom_user_roles: {
        Row: {
          role_key: string
          user_id: string
        }
        Insert: {
          role_key: string
          user_id: string
        }
        Update: {
          role_key?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "custom_user_roles_role_key_fkey"
            columns: ["role_key"]
            isOneToOne: false
            referencedRelation: "role_definitions"
            referencedColumns: ["key"]
          },
          {
            foreignKeyName: "custom_user_roles_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      entry_permits: {
        Row: {
          created_at: string
          daily_no: number
          entry_time: string
          id: string
          issued_by: string | null
          justified: boolean
          kind: string
          period: string | null
          permit_date: string
          reason: string | null
          record_ids: string[]
          student_id: string
        }
        Insert: {
          created_at?: string
          daily_no?: number
          entry_time?: string
          id?: string
          issued_by?: string | null
          justified: boolean
          kind: string
          period?: string | null
          permit_date?: string
          reason?: string | null
          record_ids?: string[]
          student_id: string
        }
        Update: {
          created_at?: string
          daily_no?: number
          entry_time?: string
          id?: string
          issued_by?: string | null
          justified?: boolean
          kind?: string
          period?: string | null
          permit_date?: string
          reason?: string | null
          record_ids?: string[]
          student_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "entry_permits_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      exams: {
        Row: {
          class_id: string | null
          created_at: string
          created_by: string | null
          exam_date: string | null
          id: string
          note: string | null
          room: string | null
          status: string
          subject: string
          updated_at: string
        }
        Insert: {
          class_id?: string | null
          created_at?: string
          created_by?: string | null
          exam_date?: string | null
          id?: string
          note?: string | null
          room?: string | null
          status?: string
          subject: string
          updated_at?: string
        }
        Update: {
          class_id?: string | null
          created_at?: string
          created_by?: string | null
          exam_date?: string | null
          id?: string
          note?: string | null
          room?: string | null
          status?: string
          subject?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "exams_class_id_fkey"
            columns: ["class_id"]
            isOneToOne: false
            referencedRelation: "classes"
            referencedColumns: ["id"]
          },
        ]
      }
      free_period_decisions: {
        Row: {
          class_id: string
          created_at: string
          decided_by: string | null
          decision: string
          decision_date: string
          id: string
          note: string | null
          slot_id: string
          substitute_teacher_id: string | null
          updated_at: string
        }
        Insert: {
          class_id: string
          created_at?: string
          decided_by?: string | null
          decision: string
          decision_date: string
          id?: string
          note?: string | null
          slot_id: string
          substitute_teacher_id?: string | null
          updated_at?: string
        }
        Update: {
          class_id?: string
          created_at?: string
          decided_by?: string | null
          decision?: string
          decision_date?: string
          id?: string
          note?: string | null
          slot_id?: string
          substitute_teacher_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "free_period_decisions_class_id_fkey"
            columns: ["class_id"]
            isOneToOne: false
            referencedRelation: "classes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "free_period_decisions_slot_id_fkey"
            columns: ["slot_id"]
            isOneToOne: false
            referencedRelation: "schedule_slots"
            referencedColumns: ["id"]
          },
        ]
      }
      grades: {
        Row: {
          created_at: string
          entered_by: string | null
          exam_id: string
          id: string
          max_score: number
          remark: string | null
          score: number | null
          student_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          entered_by?: string | null
          exam_id: string
          id?: string
          max_score?: number
          remark?: string | null
          score?: number | null
          student_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          entered_by?: string | null
          exam_id?: string
          id?: string
          max_score?: number
          remark?: string | null
          score?: number | null
          student_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "grades_exam_id_fkey"
            columns: ["exam_id"]
            isOneToOne: false
            referencedRelation: "exams"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "grades_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      homework: {
        Row: {
          class_id: string
          created_at: string
          description: string | null
          due_date: string | null
          id: string
          subject: string
          teacher_id: string | null
          title: string
          updated_at: string
        }
        Insert: {
          class_id: string
          created_at?: string
          description?: string | null
          due_date?: string | null
          id?: string
          subject: string
          teacher_id?: string | null
          title: string
          updated_at?: string
        }
        Update: {
          class_id?: string
          created_at?: string
          description?: string | null
          due_date?: string | null
          id?: string
          subject?: string
          teacher_id?: string | null
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "homework_class_id_fkey"
            columns: ["class_id"]
            isOneToOne: false
            referencedRelation: "classes"
            referencedColumns: ["id"]
          },
        ]
      }
      institution_settings: {
        Row: {
          academic_year: string
          address: string
          deployment_id: string
          email: string
          id: boolean
          logo_data_url: string
          name: string
          phone: string
          published_origin: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          academic_year?: string
          address?: string
          deployment_id?: string
          email?: string
          id?: boolean
          logo_data_url?: string
          name?: string
          phone?: string
          published_origin?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          academic_year?: string
          address?: string
          deployment_id?: string
          email?: string
          id?: boolean
          logo_data_url?: string
          name?: string
          phone?: string
          published_origin?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      legal_notice_settings: {
        Row: {
          confirmed: boolean
          id: boolean
          notice1_days: number
          notice2_days: number
          notice3_days: number
          strike_off_days: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          confirmed?: boolean
          id?: boolean
          notice1_days?: number
          notice2_days?: number
          notice3_days?: number
          strike_off_days?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          confirmed?: boolean
          id?: boolean
          notice1_days?: number
          notice2_days?: number
          notice3_days?: number
          strike_off_days?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      legal_notices: {
        Row: {
          absence_dates: string[]
          delivery_method: string
          guardian_response_on: string | null
          id: string
          issued_at: string
          issued_by: string | null
          level: number
          note: string | null
          serial: number
          student_id: string
          unjustified_days: number
        }
        Insert: {
          absence_dates?: string[]
          delivery_method?: string
          guardian_response_on?: string | null
          id?: string
          issued_at?: string
          issued_by?: string | null
          level: number
          note?: string | null
          serial?: never
          student_id: string
          unjustified_days: number
        }
        Update: {
          absence_dates?: string[]
          delivery_method?: string
          guardian_response_on?: string | null
          id?: string
          issued_at?: string
          issued_by?: string | null
          level?: number
          note?: string | null
          serial?: never
          student_id?: string
          unjustified_days?: number
        }
        Relationships: [
          {
            foreignKeyName: "legal_notices_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      library_items: {
        Row: {
          author: string | null
          available_copies: number
          created_at: string
          id: string
          item_type: string
          title: string
          total_copies: number
          updated_at: string
        }
        Insert: {
          author?: string | null
          available_copies?: number
          created_at?: string
          id?: string
          item_type?: string
          title: string
          total_copies?: number
          updated_at?: string
        }
        Update: {
          author?: string | null
          available_copies?: number
          created_at?: string
          id?: string
          item_type?: string
          title?: string
          total_copies?: number
          updated_at?: string
        }
        Relationships: []
      }
      library_loans: {
        Row: {
          created_at: string
          created_by: string | null
          due_at: string | null
          id: string
          item_id: string
          loaned_at: string
          returned_at: string | null
          student_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          due_at?: string | null
          id?: string
          item_id: string
          loaned_at?: string
          returned_at?: string | null
          student_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          due_at?: string | null
          id?: string
          item_id?: string
          loaned_at?: string
          returned_at?: string | null
          student_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "library_loans_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "library_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "library_loans_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      meeting_requests: {
        Row: {
          created_at: string
          id: string
          message: string | null
          parent_user_id: string
          preferred_date: string | null
          preferred_slot: string | null
          review_note: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: string
          student_id: string
          target_kind: string
          target_teacher_id: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          message?: string | null
          parent_user_id: string
          preferred_date?: string | null
          preferred_slot?: string | null
          review_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          student_id: string
          target_kind?: string
          target_teacher_id?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          message?: string | null
          parent_user_id?: string
          preferred_date?: string | null
          preferred_slot?: string | null
          review_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: string
          student_id?: string
          target_kind?: string
          target_teacher_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "meeting_requests_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      notifications: {
        Row: {
          body: string | null
          channel: string
          created_at: string
          created_by: string | null
          id: string
          read_at: string | null
          recipient_id: string | null
          recipient_label: string | null
          related_student_id: string | null
          status: string
          title: string
        }
        Insert: {
          body?: string | null
          channel?: string
          created_at?: string
          created_by?: string | null
          id?: string
          read_at?: string | null
          recipient_id?: string | null
          recipient_label?: string | null
          related_student_id?: string | null
          status?: string
          title: string
        }
        Update: {
          body?: string | null
          channel?: string
          created_at?: string
          created_by?: string | null
          id?: string
          read_at?: string | null
          recipient_id?: string | null
          recipient_label?: string | null
          related_student_id?: string | null
          status?: string
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "notifications_related_student_id_fkey"
            columns: ["related_student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      page_visibility_rules: {
        Row: {
          hidden: boolean
          id: string
          page: string
          target: string
          target_type: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          hidden?: boolean
          id?: string
          page: string
          target?: string
          target_type: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          hidden?: boolean
          id?: string
          page?: string
          target?: string
          target_type?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      parent_student: {
        Row: {
          created_at: string
          id: string
          parent_user_id: string
          relation: string | null
          student_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          parent_user_id: string
          relation?: string | null
          student_id: string
        }
        Update: {
          created_at?: string
          id?: string
          parent_user_id?: string
          relation?: string | null
          student_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "parent_student_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_audit_log: {
        Row: {
          action: string
          created_at: string
          details: Json | null
          id: string
          ip: string | null
          user_agent: string | null
          user_id: string
        }
        Insert: {
          action: string
          created_at?: string
          details?: Json | null
          id?: string
          ip?: string | null
          user_agent?: string | null
          user_id: string
        }
        Update: {
          action?: string
          created_at?: string
          details?: Json | null
          id?: string
          ip?: string | null
          user_agent?: string | null
          user_id?: string
        }
        Relationships: []
      }
      profiles: {
        Row: {
          avatar_url: string | null
          created_at: string
          full_name: string | null
          id: string
          phone: string | null
          preferred_language: string | null
          updated_at: string
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string
          full_name?: string | null
          id: string
          phone?: string | null
          preferred_language?: string | null
          updated_at?: string
        }
        Update: {
          avatar_url?: string | null
          created_at?: string
          full_name?: string | null
          id?: string
          phone?: string | null
          preferred_language?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      rfid_cards: {
        Row: {
          assigned_at: string | null
          card_uid: string
          created_at: string
          id: string
          last_seen_at: string | null
          note: string | null
          status: string
          student_id: string | null
          updated_at: string
        }
        Insert: {
          assigned_at?: string | null
          card_uid: string
          created_at?: string
          id?: string
          last_seen_at?: string | null
          note?: string | null
          status?: string
          student_id?: string | null
          updated_at?: string
        }
        Update: {
          assigned_at?: string | null
          card_uid?: string
          created_at?: string
          id?: string
          last_seen_at?: string | null
          note?: string | null
          status?: string
          student_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "rfid_cards_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      role_definitions: {
        Row: {
          builtin: boolean
          created_at: string
          description: string
          key: string
          label: string
        }
        Insert: {
          builtin?: boolean
          created_at?: string
          description?: string
          key: string
          label: string
        }
        Update: {
          builtin?: boolean
          created_at?: string
          description?: string
          key?: string
          label?: string
        }
        Relationships: []
      }
      role_permissions: {
        Row: {
          allowed: boolean
          permission: string
          role: Database["public"]["Enums"]["app_role"]
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          allowed?: boolean
          permission: string
          role: Database["public"]["Enums"]["app_role"]
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          allowed?: boolean
          permission?: string
          role?: Database["public"]["Enums"]["app_role"]
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      schedule_slots: {
        Row: {
          class_id: string
          created_at: string
          end_time: string
          group_label: string
          id: string
          is_active: boolean
          note: string | null
          period_no: number | null
          room: string | null
          start_time: string
          subject: string
          teacher_id: string | null
          updated_at: string
          weekday: number
        }
        Insert: {
          class_id: string
          created_at?: string
          end_time: string
          group_label?: string
          id?: string
          is_active?: boolean
          note?: string | null
          period_no?: number | null
          room?: string | null
          start_time: string
          subject: string
          teacher_id?: string | null
          updated_at?: string
          weekday: number
        }
        Update: {
          class_id?: string
          created_at?: string
          end_time?: string
          group_label?: string
          id?: string
          is_active?: boolean
          note?: string | null
          period_no?: number | null
          room?: string | null
          start_time?: string
          subject?: string
          teacher_id?: string | null
          updated_at?: string
          weekday?: number
        }
        Relationships: [
          {
            foreignKeyName: "schedule_slots_class_id_fkey"
            columns: ["class_id"]
            isOneToOne: false
            referencedRelation: "classes"
            referencedColumns: ["id"]
          },
        ]
      }
      school_decisions: {
        Row: {
          body: string | null
          created_at: string
          created_by: string | null
          decision_type: string
          ends_at: string | null
          id: string
          starts_at: string | null
          status: string
          title: string
          updated_at: string
        }
        Insert: {
          body?: string | null
          created_at?: string
          created_by?: string | null
          decision_type?: string
          ends_at?: string | null
          id?: string
          starts_at?: string | null
          status?: string
          title: string
          updated_at?: string
        }
        Update: {
          body?: string | null
          created_at?: string
          created_by?: string | null
          decision_type?: string
          ends_at?: string | null
          id?: string
          starts_at?: string | null
          status?: string
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      school_events: {
        Row: {
          audience: string
          created_at: string
          created_by: string | null
          description: string | null
          ends_on: string | null
          event_type: string
          id: string
          starts_on: string
          title: string
          updated_at: string
        }
        Insert: {
          audience?: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          ends_on?: string | null
          event_type?: string
          id?: string
          starts_on: string
          title: string
          updated_at?: string
        }
        Update: {
          audience?: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          ends_on?: string | null
          event_type?: string
          id?: string
          starts_on?: string
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      school_trips: {
        Row: {
          created_at: string
          created_by: string | null
          destination: string | null
          id: string
          note: string | null
          status: string
          title: string
          trip_date: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          destination?: string | null
          id?: string
          note?: string | null
          status?: string
          title: string
          trip_date?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          destination?: string | null
          id?: string
          note?: string | null
          status?: string
          title?: string
          trip_date?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      site_maintenance: {
        Row: {
          enabled: boolean
          id: boolean
          message: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          enabled?: boolean
          id?: boolean
          message?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          enabled?: boolean
          id?: boolean
          message?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      staff_whitelist: {
        Row: {
          created_at: string
          email: string | null
          full_name: string
          id: string
          note: string | null
          role: Database["public"]["Enums"]["app_role"]
        }
        Insert: {
          created_at?: string
          email?: string | null
          full_name: string
          id?: string
          note?: string | null
          role: Database["public"]["Enums"]["app_role"]
        }
        Update: {
          created_at?: string
          email?: string | null
          full_name?: string
          id?: string
          note?: string | null
          role?: Database["public"]["Enums"]["app_role"]
        }
        Relationships: []
      }
      student_goals: {
        Row: {
          created_at: string
          description: string | null
          done: boolean
          id: string
          progress: number
          student_id: string
          target_date: string | null
          title: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          done?: boolean
          id?: string
          progress?: number
          student_id: string
          target_date?: string | null
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          description?: string | null
          done?: boolean
          id?: string
          progress?: number
          student_id?: string
          target_date?: string | null
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "student_goals_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      students: {
        Row: {
          class_id: string | null
          created_at: string
          date_of_birth: string | null
          enrollment_data: Json | null
          enrollment_status: string
          extra_fields: Json
          fake_email: string | null
          fake_phone: string | null
          father_phone: string | null
          full_name: string
          gender: string | null
          guardian_name: string | null
          guardian_phone: string | null
          id: string
          mother_phone: string | null
          national_student_id: string | null
          struck_off_at: string | null
          struck_off_by: string | null
          struck_off_reason: string | null
          subgroup: string | null
          updated_at: string
          user_id: string | null
        }
        Insert: {
          class_id?: string | null
          created_at?: string
          date_of_birth?: string | null
          enrollment_data?: Json | null
          enrollment_status?: string
          extra_fields?: Json
          fake_email?: string | null
          fake_phone?: string | null
          father_phone?: string | null
          full_name: string
          gender?: string | null
          guardian_name?: string | null
          guardian_phone?: string | null
          id?: string
          mother_phone?: string | null
          national_student_id?: string | null
          struck_off_at?: string | null
          struck_off_by?: string | null
          struck_off_reason?: string | null
          subgroup?: string | null
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          class_id?: string | null
          created_at?: string
          date_of_birth?: string | null
          enrollment_data?: Json | null
          enrollment_status?: string
          extra_fields?: Json
          fake_email?: string | null
          fake_phone?: string | null
          father_phone?: string | null
          full_name?: string
          gender?: string | null
          guardian_name?: string | null
          guardian_phone?: string | null
          id?: string
          mother_phone?: string | null
          national_student_id?: string | null
          struck_off_at?: string | null
          struck_off_by?: string | null
          struck_off_reason?: string | null
          subgroup?: string | null
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "students_class_id_fkey"
            columns: ["class_id"]
            isOneToOne: false
            referencedRelation: "classes"
            referencedColumns: ["id"]
          },
        ]
      }
      substitution_requests: {
        Row: {
          class_id: string | null
          created_at: string
          id: string
          reason: string
          request_date: string
          requester_id: string
          review_note: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          slot_id: string | null
          status: string
          substitute_teacher_id: string | null
          updated_at: string
        }
        Insert: {
          class_id?: string | null
          created_at?: string
          id?: string
          reason: string
          request_date: string
          requester_id?: string
          review_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          slot_id?: string | null
          status?: string
          substitute_teacher_id?: string | null
          updated_at?: string
        }
        Update: {
          class_id?: string | null
          created_at?: string
          id?: string
          reason?: string
          request_date?: string
          requester_id?: string
          review_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          slot_id?: string | null
          status?: string
          substitute_teacher_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "substitution_requests_class_id_fkey"
            columns: ["class_id"]
            isOneToOne: false
            referencedRelation: "classes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "substitution_requests_slot_id_fkey"
            columns: ["slot_id"]
            isOneToOne: false
            referencedRelation: "schedule_slots"
            referencedColumns: ["id"]
          },
        ]
      }
      teacher_absences: {
        Row: {
          absence_date: string
          created_at: string
          created_by: string | null
          id: string
          reason: string | null
          slot_ids: string[] | null
          teacher_id: string
        }
        Insert: {
          absence_date: string
          created_at?: string
          created_by?: string | null
          id?: string
          reason?: string | null
          slot_ids?: string[] | null
          teacher_id: string
        }
        Update: {
          absence_date?: string
          created_at?: string
          created_by?: string | null
          id?: string
          reason?: string | null
          slot_ids?: string[] | null
          teacher_id?: string
        }
        Relationships: []
      }
      teacher_attendance_pins: {
        Row: {
          failed_count: number
          locked_until: string | null
          pin_hash: string
          teacher_id: string
          updated_at: string
        }
        Insert: {
          failed_count?: number
          locked_until?: string | null
          pin_hash: string
          teacher_id: string
          updated_at?: string
        }
        Update: {
          failed_count?: number
          locked_until?: string | null
          pin_hash?: string
          teacher_id?: string
          updated_at?: string
        }
        Relationships: []
      }
      teacher_directory: {
        Row: {
          code: string
          full_name: string
          login_email: string | null
          needs_review: boolean
          subject: string
          updated_at: string
          user_id: string | null
        }
        Insert: {
          code: string
          full_name: string
          login_email?: string | null
          needs_review?: boolean
          subject: string
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          code?: string
          full_name?: string
          login_email?: string | null
          needs_review?: boolean
          subject?: string
          updated_at?: string
          user_id?: string | null
        }
        Relationships: []
      }
      teacher_posts: {
        Row: {
          attachments: Json
          body: string | null
          class_id: string | null
          created_at: string
          due_date: string | null
          id: string
          kind: string
          link_url: string | null
          teacher_id: string
          title: string
        }
        Insert: {
          attachments?: Json
          body?: string | null
          class_id?: string | null
          created_at?: string
          due_date?: string | null
          id?: string
          kind?: string
          link_url?: string | null
          teacher_id?: string
          title: string
        }
        Update: {
          attachments?: Json
          body?: string | null
          class_id?: string | null
          created_at?: string
          due_date?: string | null
          id?: string
          kind?: string
          link_url?: string | null
          teacher_id?: string
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "teacher_posts_class_id_fkey"
            columns: ["class_id"]
            isOneToOne: false
            referencedRelation: "classes"
            referencedColumns: ["id"]
          },
        ]
      }
      teacher_reception_hours: {
        Row: {
          created_at: string
          end_time: string
          id: string
          note: string | null
          place: string | null
          start_time: string
          teacher_id: string
          weekday: number
        }
        Insert: {
          created_at?: string
          end_time: string
          id?: string
          note?: string | null
          place?: string | null
          start_time: string
          teacher_id: string
          weekday: number
        }
        Update: {
          created_at?: string
          end_time?: string
          id?: string
          note?: string | null
          place?: string | null
          start_time?: string
          teacher_id?: string
          weekday?: number
        }
        Relationships: []
      }
      telegram_alerts: {
        Row: {
          class_name: string
          created_at: string
          decided_at: string | null
          decided_by: string | null
          decision: string
          details: string
          event_at: string
          event_type: string
          guardian_name: string
          guardian_phone: string | null
          id: string
          is_test: boolean
          source_key: string
          student_id: string | null
          student_name: string
          telegram_error: string | null
          telegram_message_id: number | null
          telegram_status: string
        }
        Insert: {
          class_name?: string
          created_at?: string
          decided_at?: string | null
          decided_by?: string | null
          decision?: string
          details?: string
          event_at?: string
          event_type: string
          guardian_name?: string
          guardian_phone?: string | null
          id?: string
          is_test?: boolean
          source_key: string
          student_id?: string | null
          student_name: string
          telegram_error?: string | null
          telegram_message_id?: number | null
          telegram_status?: string
        }
        Update: {
          class_name?: string
          created_at?: string
          decided_at?: string | null
          decided_by?: string | null
          decision?: string
          details?: string
          event_at?: string
          event_type?: string
          guardian_name?: string
          guardian_phone?: string | null
          id?: string
          is_test?: boolean
          source_key?: string
          student_id?: string | null
          student_name?: string
          telegram_error?: string | null
          telegram_message_id?: number | null
          telegram_status?: string
        }
        Relationships: [
          {
            foreignKeyName: "telegram_alerts_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      telegram_settings: {
        Row: {
          chat_id: string
          enabled: boolean
          id: boolean
        }
        Insert: {
          chat_id: string
          enabled?: boolean
          id?: boolean
        }
        Update: {
          chat_id?: string
          enabled?: boolean
          id?: boolean
        }
        Relationships: []
      }
      trip_participants: {
        Row: {
          attended: boolean
          consent_status: string
          created_at: string
          id: string
          student_id: string
          trip_id: string
        }
        Insert: {
          attended?: boolean
          consent_status?: string
          created_at?: string
          id?: string
          student_id: string
          trip_id: string
        }
        Update: {
          attended?: boolean
          consent_status?: string
          created_at?: string
          id?: string
          student_id?: string
          trip_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "trip_participants_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trip_participants_trip_id_fkey"
            columns: ["trip_id"]
            isOneToOne: false
            referencedRelation: "school_trips"
            referencedColumns: ["id"]
          },
        ]
      }
      user_permission_overrides: {
        Row: {
          allowed: boolean
          note: string | null
          permission: string
          updated_at: string
          updated_by: string | null
          user_id: string
        }
        Insert: {
          allowed: boolean
          note?: string | null
          permission: string
          updated_at?: string
          updated_by?: string | null
          user_id: string
        }
        Update: {
          allowed?: boolean
          note?: string | null
          permission?: string
          updated_at?: string
          updated_by?: string | null
          user_id?: string
        }
        Relationships: []
      }
      user_roles: {
        Row: {
          assigned_at: string
          id: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Insert: {
          assigned_at?: string
          id?: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Update: {
          assigned_at?: string
          id?: string
          role?: Database["public"]["Enums"]["app_role"]
          user_id?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      auto_split_class_subgroups: { Args: { _class: string }; Returns: number }
      claim_account: { Args: { _code: string }; Returns: Json }
      claim_lookup: {
        Args: { _code: string }
        Returns: {
          claimed_by: string | null
          code: string
          created_at: string
          expires_at: string
          id: string
          issued_by: string | null
          kind: string
          status: string
          student_id: string | null
          teacher_code: string | null
          used_at: string | null
        }
        SetofOptions: {
          from: "*"
          to: "account_claim_tokens"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      class_blocked_students: {
        Args: { _class: string }
        Returns: {
          absences: number
          since_date: string
          student_id: string
        }[]
      }
      gen_claim_code: { Args: never; Returns: string }
      get_overview_stats: { Args: never; Returns: Json }
      get_user_roles: {
        Args: { _user_id: string }
        Returns: Database["public"]["Enums"]["app_role"][]
      }
      has_my_attendance_pin: { Args: never; Returns: boolean }
      has_permission: {
        Args: { _perm: string; _user_id: string }
        Returns: boolean
      }
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: boolean
      }
      is_management: { Args: { _uid: string }; Returns: boolean }
      is_role_owner: { Args: never; Returns: boolean }
      issue_claim_tokens: {
        Args: { _class?: string; _kind: string }
        Returns: number
      }
      justify_absences: {
        Args: { _reason: string; _record_ids: string[] }
        Returns: number
      }
      kiosk_context: { Args: never; Returns: Json }
      kiosk_submit_attendance: {
        Args: {
          _absent: string[]
          _late: string[]
          _pin: string
          _scope?: string
          _slot_id: string
        }
        Returns: Json
      }
      list_teachers: {
        Args: never
        Returns: {
          full_name: string
          id: string
        }[]
      }
      my_cancelled_slots: {
        Args: { _from: string; _to: string }
        Returns: {
          class_id: string
          decision: string
          on_date: string
          reason: string
          slot_id: string
        }[]
      }
      my_children_teachers: {
        Args: never
        Returns: {
          class_name: string
          is_head: boolean
          reception: Json
          student_id: string
          student_name: string
          subject: string
          teacher_id: string
          teacher_name: string
        }[]
      }
      my_display_name: { Args: never; Returns: string }
      owner_set_account_roles: {
        Args: {
          _roles: Database["public"]["Enums"]["app_role"][]
          _user_id: string
        }
        Returns: undefined
      }
      preview_claim_token: { Args: { _code: string }; Returns: Json }
      reset_teacher_attendance_pin: {
        Args: { _teacher: string }
        Returns: undefined
      }
      revoke_claim_token: {
        Args: { _id: string; _reissue?: boolean }
        Returns: string
      }
      send_bulk_notification: {
        Args: {
          _body: string
          _class_id: string
          _target: string
          _title: string
        }
        Returns: number
      }
      set_class_head_teacher: {
        Args: { _class: string; _teacher: string }
        Returns: undefined
      }
      set_my_attendance_pin: { Args: { _pin: string }; Returns: undefined }
      set_slot_group: {
        Args: { _group: string; _slot: string }
        Returns: undefined
      }
      set_student_enrollment: {
        Args: { _reason: string; _status: string; _student: string }
        Returns: undefined
      }
      set_student_subgroup: {
        Args: { _group: string; _student: string }
        Returns: undefined
      }
      student_absence_standing: {
        Args: never
        Returns: {
          absence_dates: string[]
          class_name: string
          enrollment_status: string
          full_name: string
          guardian_name: string
          guardian_phone: string
          last_notice_level: number
          student_id: string
          unjustified_days: number
        }[]
      }
      student_entry_block: {
        Args: { _sid: string }
        Returns: {
          absences: number
          since_date: string
        }[]
      }
      teacher_edit_attendance: {
        Args: { _changes: Json; _session: string }
        Returns: number
      }
      teaches_class: {
        Args: { _class: string; _teacher: string }
        Returns: boolean
      }
    }
    Enums: {
      app_role:
        | "admin"
        | "director"
        | "supervisor"
        | "teacher"
        | "parent"
        | "student"
        | "gate_monitor"
        | "developer"
        | "class_rep"
        | "class_rep_deputy"
        | "digital_advisor"
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
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
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
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
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      app_role: [
        "admin",
        "director",
        "supervisor",
        "teacher",
        "parent",
        "student",
        "gate_monitor",
        "developer",
        "class_rep",
        "class_rep_deputy",
        "digital_advisor",
      ],
    },
  },
} as const
