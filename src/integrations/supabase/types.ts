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
      allowed_user_roles: {
        Row: {
          allowed_user_id: string
          created_at: string
          id: string
          role: Database["public"]["Enums"]["app_role"]
          updated_at: string
        }
        Insert: {
          allowed_user_id: string
          created_at?: string
          id?: string
          role: Database["public"]["Enums"]["app_role"]
          updated_at?: string
        }
        Update: {
          allowed_user_id?: string
          created_at?: string
          id?: string
          role?: Database["public"]["Enums"]["app_role"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "allowed_user_roles_allowed_user_id_fkey"
            columns: ["allowed_user_id"]
            isOneToOne: true
            referencedRelation: "allowed_users"
            referencedColumns: ["id"]
          },
        ]
      }
      allowed_users: {
        Row: {
          created_at: string
          departure_date: string | null
          email: string
          first_name: string | null
          id: string
          last_name: string | null
          team: string | null
        }
        Insert: {
          created_at?: string
          departure_date?: string | null
          email: string
          first_name?: string | null
          id?: string
          last_name?: string | null
          team?: string | null
        }
        Update: {
          created_at?: string
          departure_date?: string | null
          email?: string
          first_name?: string | null
          id?: string
          last_name?: string | null
          team?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "allowed_users_team_fkey"
            columns: ["team"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["name"]
          },
        ]
      }
      attachment_deletion_queue: {
        Row: {
          delete_after: string
          id: string
          last_error: string | null
          path: string
          queued_at: string
        }
        Insert: {
          delete_after?: string
          id?: string
          last_error?: string | null
          path: string
          queued_at?: string
        }
        Update: {
          delete_after?: string
          id?: string
          last_error?: string | null
          path?: string
          queued_at?: string
        }
        Relationships: []
      }
      blocker_teams: {
        Row: {
          blocker_id: string
          team: string
        }
        Insert: {
          blocker_id: string
          team: string
        }
        Update: {
          blocker_id?: string
          team?: string
        }
        Relationships: [
          {
            foreignKeyName: "blocker_teams_blocker_id_fkey"
            columns: ["blocker_id"]
            isOneToOne: false
            referencedRelation: "blockers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "blocker_teams_team_fkey"
            columns: ["team"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["name"]
          },
        ]
      }
      blockers: {
        Row: {
          created_at: string
          department: string | null
          description: string | null
          id: string
          impact: string | null
          reminded_at: string | null
          reminded_by_name: string | null
          severity: Database["public"]["Enums"]["blocker_severity"]
          status: Database["public"]["Enums"]["blocker_status"]
          title: string
          updated_at: string
          updated_by: string | null
          updated_by_name: string | null
        }
        Insert: {
          created_at?: string
          department?: string | null
          description?: string | null
          id?: string
          impact?: string | null
          reminded_at?: string | null
          reminded_by_name?: string | null
          severity?: Database["public"]["Enums"]["blocker_severity"]
          status?: Database["public"]["Enums"]["blocker_status"]
          title: string
          updated_at?: string
          updated_by?: string | null
          updated_by_name?: string | null
        }
        Update: {
          created_at?: string
          department?: string | null
          description?: string | null
          id?: string
          impact?: string | null
          reminded_at?: string | null
          reminded_by_name?: string | null
          severity?: Database["public"]["Enums"]["blocker_severity"]
          status?: Database["public"]["Enums"]["blocker_status"]
          title?: string
          updated_at?: string
          updated_by?: string | null
          updated_by_name?: string | null
        }
        Relationships: []
      }
      departure_notices: {
        Row: {
          closed_at: string | null
          created_at: string
          departing_label: string
          departing_user_id: string | null
          departure_date: string
          documents: Json
          downloaded_at: string | null
          id: string
          kind: string
          recipient_email: string
          reminder_at: string | null
        }
        Insert: {
          closed_at?: string | null
          created_at?: string
          departing_label: string
          departing_user_id?: string | null
          departure_date: string
          documents?: Json
          downloaded_at?: string | null
          id?: string
          kind: string
          recipient_email: string
          reminder_at?: string | null
        }
        Update: {
          closed_at?: string | null
          created_at?: string
          departing_label?: string
          departing_user_id?: string | null
          departure_date?: string
          documents?: Json
          downloaded_at?: string | null
          id?: string
          kind?: string
          recipient_email?: string
          reminder_at?: string | null
        }
        Relationships: []
      }
      manager_teams: {
        Row: {
          allowed_user_id: string
          created_at: string
          id: string
          team: string
        }
        Insert: {
          allowed_user_id: string
          created_at?: string
          id?: string
          team: string
        }
        Update: {
          allowed_user_id?: string
          created_at?: string
          id?: string
          team?: string
        }
        Relationships: [
          {
            foreignKeyName: "manager_teams_allowed_user_id_fkey"
            columns: ["allowed_user_id"]
            isOneToOne: false
            referencedRelation: "allowed_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "manager_teams_team_fkey"
            columns: ["team"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["name"]
          },
        ]
      }
      metrics: {
        Row: {
          definition: string | null
          impact: string | null
          key: string
          label: string
          stale_after_days: number | null
          threshold_max: number | null
          threshold_min: number | null
          thresholds_updated_at: string | null
          unit: string | null
          updated_at: string
          updated_by: string | null
          updated_by_name: string | null
          value: number
          verified_at: string | null
        }
        Insert: {
          definition?: string | null
          impact?: string | null
          key: string
          label: string
          stale_after_days?: number | null
          threshold_max?: number | null
          threshold_min?: number | null
          thresholds_updated_at?: string | null
          unit?: string | null
          updated_at?: string
          updated_by?: string | null
          updated_by_name?: string | null
          value: number
          verified_at?: string | null
        }
        Update: {
          definition?: string | null
          impact?: string | null
          key?: string
          label?: string
          stale_after_days?: number | null
          threshold_max?: number | null
          threshold_min?: number | null
          thresholds_updated_at?: string | null
          unit?: string | null
          updated_at?: string
          updated_by?: string | null
          updated_by_name?: string | null
          value?: number
          verified_at?: string | null
        }
        Relationships: []
      }
      metrics_history: {
        Row: {
          id: string
          metric_key: string
          recorded_at: string
          value: number
        }
        Insert: {
          id?: string
          metric_key: string
          recorded_at?: string
          value: number
        }
        Update: {
          id?: string
          metric_key?: string
          recorded_at?: string
          value?: number
        }
        Relationships: []
      }
      news: {
        Row: {
          audience: Database["public"]["Enums"]["news_audience"] | null
          author: string
          author_email: string | null
          body: string | null
          created_at: string
          id: string
          image_path: string | null
          links: Json
          published_at: string | null
          status: Database["public"]["Enums"]["news_status"]
          title: string
          updated_at: string
        }
        Insert: {
          audience?: Database["public"]["Enums"]["news_audience"] | null
          author?: string
          author_email?: string | null
          body?: string | null
          created_at?: string
          id?: string
          image_path?: string | null
          links?: Json
          published_at?: string | null
          status?: Database["public"]["Enums"]["news_status"]
          title: string
          updated_at?: string
        }
        Update: {
          audience?: Database["public"]["Enums"]["news_audience"] | null
          author?: string
          author_email?: string | null
          body?: string | null
          created_at?: string
          id?: string
          image_path?: string | null
          links?: Json
          published_at?: string | null
          status?: Database["public"]["Enums"]["news_status"]
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      news_teams: {
        Row: {
          news_id: string
          team: string
        }
        Insert: {
          news_id: string
          team: string
        }
        Update: {
          news_id?: string
          team?: string
        }
        Relationships: [
          {
            foreignKeyName: "news_teams_news_id_fkey"
            columns: ["news_id"]
            isOneToOne: false
            referencedRelation: "news"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "news_teams_team_fkey"
            columns: ["team"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["name"]
          },
        ]
      }
      notification_preferences: {
        Row: {
          by_email: boolean
          in_app: boolean
          kind: Database["public"]["Enums"]["notification_kind"]
          recipient_email: string
          updated_at: string
        }
        Insert: {
          by_email?: boolean
          in_app?: boolean
          kind: Database["public"]["Enums"]["notification_kind"]
          recipient_email: string
          updated_at?: string
        }
        Update: {
          by_email?: boolean
          in_app?: boolean
          kind?: Database["public"]["Enums"]["notification_kind"]
          recipient_email?: string
          updated_at?: string
        }
        Relationships: []
      }
      notifications: {
        Row: {
          actor_email: string | null
          actor_name: string | null
          blocker_id: string | null
          created_at: string
          id: string
          kind: Database["public"]["Enums"]["notification_kind"]
          message: string
          read_at: string | null
          recipient_email: string
          submission_id: string | null
        }
        Insert: {
          actor_email?: string | null
          actor_name?: string | null
          blocker_id?: string | null
          created_at?: string
          id?: string
          kind: Database["public"]["Enums"]["notification_kind"]
          message: string
          read_at?: string | null
          recipient_email: string
          submission_id?: string | null
        }
        Update: {
          actor_email?: string | null
          actor_name?: string | null
          blocker_id?: string | null
          created_at?: string
          id?: string
          kind?: Database["public"]["Enums"]["notification_kind"]
          message?: string
          read_at?: string | null
          recipient_email?: string
          submission_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "notifications_blocker_id_fkey"
            columns: ["blocker_id"]
            isOneToOne: false
            referencedRelation: "blockers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_submission_id_fkey"
            columns: ["submission_id"]
            isOneToOne: false
            referencedRelation: "submissions"
            referencedColumns: ["id"]
          },
        ]
      }
      submission_followers: {
        Row: {
          created_at: string
          follower_email: string
          source: string
          submission_id: string
        }
        Insert: {
          created_at?: string
          follower_email: string
          source: string
          submission_id: string
        }
        Update: {
          created_at?: string
          follower_email?: string
          source?: string
          submission_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "submission_followers_submission_id_fkey"
            columns: ["submission_id"]
            isOneToOne: false
            referencedRelation: "submissions"
            referencedColumns: ["id"]
          },
        ]
      }
      submission_status_history: {
        Row: {
          changed_at: string
          changed_by_email: string | null
          changed_by_name: string | null
          id: string
          is_automatic: boolean
          new_status: Database["public"]["Enums"]["submission_status"]
          old_status: Database["public"]["Enums"]["submission_status"] | null
          rejection_category:
            | Database["public"]["Enums"]["rejection_category"]
            | null
          rejection_note: string | null
          submission_id: string
        }
        Insert: {
          changed_at?: string
          changed_by_email?: string | null
          changed_by_name?: string | null
          id?: string
          is_automatic?: boolean
          new_status: Database["public"]["Enums"]["submission_status"]
          old_status?: Database["public"]["Enums"]["submission_status"] | null
          rejection_category?:
            | Database["public"]["Enums"]["rejection_category"]
            | null
          rejection_note?: string | null
          submission_id: string
        }
        Update: {
          changed_at?: string
          changed_by_email?: string | null
          changed_by_name?: string | null
          id?: string
          is_automatic?: boolean
          new_status?: Database["public"]["Enums"]["submission_status"]
          old_status?: Database["public"]["Enums"]["submission_status"] | null
          rejection_category?:
            | Database["public"]["Enums"]["rejection_category"]
            | null
          rejection_note?: string | null
          submission_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "submission_status_history_submission_id_fkey"
            columns: ["submission_id"]
            isOneToOne: false
            referencedRelation: "submissions"
            referencedColumns: ["id"]
          },
        ]
      }
      submission_verifications: {
        Row: {
          id: string
          submission_id: string
          verified_at: string
          verified_by_email: string | null
          verified_by_name: string | null
        }
        Insert: {
          id?: string
          submission_id: string
          verified_at?: string
          verified_by_email?: string | null
          verified_by_name?: string | null
        }
        Update: {
          id?: string
          submission_id?: string
          verified_at?: string
          verified_by_email?: string | null
          verified_by_name?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "submission_verifications_submission_id_fkey"
            columns: ["submission_id"]
            isOneToOne: false
            referencedRelation: "submissions"
            referencedColumns: ["id"]
          },
        ]
      }
      submissions: {
        Row: {
          attachment_name: string | null
          attachment_path: string | null
          author_name: string
          content: string
          created_at: string
          id: string
          rejection_category:
            | Database["public"]["Enums"]["rejection_category"]
            | null
          rejection_note: string | null
          revalidate_at: string | null
          status: Database["public"]["Enums"]["submission_status"]
          submitted_by_email: string | null
          team: string
          verified_at: string | null
        }
        Insert: {
          attachment_name?: string | null
          attachment_path?: string | null
          author_name: string
          content: string
          created_at?: string
          id?: string
          rejection_category?:
            | Database["public"]["Enums"]["rejection_category"]
            | null
          rejection_note?: string | null
          revalidate_at?: string | null
          status?: Database["public"]["Enums"]["submission_status"]
          submitted_by_email?: string | null
          team: string
          verified_at?: string | null
        }
        Update: {
          attachment_name?: string | null
          attachment_path?: string | null
          author_name?: string
          content?: string
          created_at?: string
          id?: string
          rejection_category?:
            | Database["public"]["Enums"]["rejection_category"]
            | null
          rejection_note?: string | null
          revalidate_at?: string | null
          status?: Database["public"]["Enums"]["submission_status"]
          submitted_by_email?: string | null
          team?: string
          verified_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "submissions_team_fkey"
            columns: ["team"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["name"]
          },
        ]
      }
      teams: {
        Row: {
          created_at: string
          is_reserved: boolean
          name: string
        }
        Insert: {
          created_at?: string
          is_reserved?: boolean
          name: string
        }
        Update: {
          created_at?: string
          is_reserved?: boolean
          name?: string
        }
        Relationships: []
      }
    }
    Views: {
      metrics_with_trend: {
        Row: {
          definition: string | null
          delta: number | null
          impact: string | null
          key: string | null
          label: string | null
          out_of_range_since: string | null
          previous_value: number | null
          stale_after_days: number | null
          threshold_max: number | null
          threshold_min: number | null
          trend: string | null
          unit: string | null
          updated_at: string | null
          updated_by_name: string | null
          value: number | null
          verified_at: string | null
        }
        Relationships: []
      }
    }
    Functions: {
      choisir_mon_role: {
        Args: {
          _first_name: string
          _last_name: string
          _role: Database["public"]["Enums"]["app_role"]
          _team?: string | null
        }
        Returns: Database["public"]["Enums"]["app_role"]
      }
      bulk_import_allowed_users: {
        Args: { _dry_run?: boolean; _rows: Json }
        Returns: Json
      }
      mark_departure_notice_downloaded: {
        Args: { _id: string }
        Returns: undefined
      }
      save_blocker_teams: {
        Args: { _blocker_id: string; _teams?: string[] }
        Returns: undefined
      }
      save_news_audience: {
        Args: {
          _audience: Database["public"]["Enums"]["news_audience"] | null
          _news_id: string
          _teams?: string[]
        }
        Returns: undefined
      }
      confirm_submission_up_to_date: {
        Args: { _submission_id: string }
        Returns: undefined
      }
      remind_blocker_teams: {
        Args: { _blocker_id: string }
        Returns: number
      }
      set_blocker_status: {
        Args: {
          _blocker_id: string
          _status: Database["public"]["Enums"]["blocker_status"]
        }
        Returns: undefined
      }
      verify_metric: {
        Args: { _key: string }
        Returns: undefined
      }
      simuler_kpi_hors_plage: {
        Args: { _key: string }
        Returns: number
      }
      simuler_point_bloquant_a_revoir: {
        Args: { _blocker_id: string }
        Returns: number
      }
      save_published_news: {
        Args: {
          _audience: Database["public"]["Enums"]["news_audience"]
          _body: string
          _image_path: string | null
          _links: Json
          _news_id: string
          _teams?: string[]
          _title: string
        }
        Returns: undefined
      }
    }
    Enums: {
      app_role: "admin" | "manager" | "collaborateur"
      blocker_severity: "critical" | "warning" | "info"
      blocker_status: "OUVERT" | "EN COURS" | "SURVEILLANCE" | "RÉSOLU"
      news_audience: "équipe" | "entreprise"
      news_status: "brouillon" | "publiée"
      notification_kind:
        | "nouvelle_demande"
        | "changement_statut"
        | "resume_hebdo"
        | "changement_statut_suivi"
        | "point_bloquant_a_revoir"
        | "relance_point_bloquant"
      rejection_category:
        | "à clarifier"
        | "en désaccord avec les process"
        | "doublon"
        | "autre"
      submission_status: "en attente" | "validée" | "refusée" | "clôturée"
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
      app_role: ["admin", "manager", "collaborateur"],
      blocker_severity: ["critical", "warning", "info"],
      blocker_status: ["OUVERT", "EN COURS", "SURVEILLANCE", "RÉSOLU"],
      news_audience: ["équipe", "entreprise"],
      news_status: ["brouillon", "publiée"],
      notification_kind: [
        "nouvelle_demande",
        "changement_statut",
        "resume_hebdo",
        "changement_statut_suivi",
        "point_bloquant_a_revoir",
        "relance_point_bloquant",
      ],
      rejection_category: [
        "à clarifier",
        "en désaccord avec les process",
        "doublon",
        "autre",
      ],
      submission_status: ["en attente", "validée", "refusée", "clôturée"],
    },
  },
} as const
