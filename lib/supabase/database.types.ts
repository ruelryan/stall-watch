
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  
  "builder": {
          Tables: {
            "alerts": {
                  Row: {
                    "created_at": string,"id": string,"kind": string,"lock_version": number,"message": string,"org_id": string,"project_id": string,"read_at": string | null,"source_key": string,"updated_at": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"id"?: string,"kind": string,"lock_version"?: number,"message": string,"org_id": string,"project_id": string,"read_at"?: string | null,"source_key": string,"updated_at"?: string,"user_id": string
                  }
                  Update: {
                    "created_at"?: string,"id"?: string,"kind"?: string,"lock_version"?: number,"message"?: string,"org_id"?: string,"project_id"?: string,"read_at"?: string | null,"source_key"?: string,"updated_at"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "alerts_project_fk"
      columns: ["project_id","org_id"]
isOneToOne: false
      referencedRelation: "projects"
      referencedColumns: ["id","org_id"]
    },{
      foreignKeyName: "alerts_project_fk"
      columns: ["project_id","org_id"]
isOneToOne: false
      referencedRelation: "v_projects_overview"
      referencedColumns: ["id","org_id"]
    }
                  ]
                },"detector_runs": {
                  Row: {
                    "alerts_created": number,"created_at": string,"error_message": string | null,"finished_at": string | null,"id": string,"new_episodes": number,"projects_flagged": number,"started_at": string,"status": string,"trigger_kind": string,"triggered_by": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "alerts_created"?: number,"created_at"?: string,"error_message"?: string | null,"finished_at"?: string | null,"id"?: string,"new_episodes"?: number,"projects_flagged"?: number,"started_at"?: string,"status"?: string,"trigger_kind": string,"triggered_by"?: string | null
                  }
                  Update: {
                    "alerts_created"?: number,"created_at"?: string,"error_message"?: string | null,"finished_at"?: string | null,"id"?: string,"new_episodes"?: number,"projects_flagged"?: number,"started_at"?: string,"status"?: string,"trigger_kind"?: string,"triggered_by"?: string | null
                  }
                  Relationships: [
                    
                  ]
                },"project_slots": {
                  Row: {
                    "category": string,"created_at": string,"id": string,"lock_version": number,"org_id": string,"project_id": string,"room": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "category": string,"created_at"?: string,"id"?: string,"lock_version"?: number,"org_id": string,"project_id": string,"room": string,"updated_at"?: string
                  }
                  Update: {
                    "category"?: string,"created_at"?: string,"id"?: string,"lock_version"?: number,"org_id"?: string,"project_id"?: string,"room"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "project_slots_project_fk"
      columns: ["project_id","org_id"]
isOneToOne: false
      referencedRelation: "projects"
      referencedColumns: ["id","org_id"]
    },{
      foreignKeyName: "project_slots_project_fk"
      columns: ["project_id","org_id"]
isOneToOne: false
      referencedRelation: "v_projects_overview"
      referencedColumns: ["id","org_id"]
    }
                  ]
                },"projects": {
                  Row: {
                    "archived_at": string | null,"created_at": string,"id": string,"lock_version": number,"name": string,"org_id": string,"selection_due_date": string,"selection_phase_started_at": string | null,"status": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "archived_at"?: string | null,"created_at"?: string,"id"?: string,"lock_version"?: number,"name": string,"org_id": string,"selection_due_date": string,"selection_phase_started_at"?: string | null,"status"?: string,"updated_at"?: string
                  }
                  Update: {
                    "archived_at"?: string | null,"created_at"?: string,"id"?: string,"lock_version"?: number,"name"?: string,"org_id"?: string,"selection_due_date"?: string,"selection_phase_started_at"?: string | null,"status"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"selection_history": {
                  Row: {
                    "action": string,"actor_kind": string,"changed_at": string,"changed_by": string | null,"created_at": string,"id": string,"org_id": string,"product_name": string | null,"slot_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "action": string,"actor_kind": string,"changed_at"?: string,"changed_by"?: string | null,"created_at"?: string,"id"?: string,"org_id": string,"product_name"?: string | null,"slot_id": string
                  }
                  Update: {
                    "action"?: string,"actor_kind"?: string,"changed_at"?: string,"changed_by"?: string | null,"created_at"?: string,"id"?: string,"org_id"?: string,"product_name"?: string | null,"slot_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "selection_history_slot_fk"
      columns: ["slot_id","org_id"]
isOneToOne: false
      referencedRelation: "project_slots"
      referencedColumns: ["id","org_id"]
    }
                  ]
                },"selections": {
                  Row: {
                    "created_at": string,"id": string,"lock_version": number,"org_id": string,"product_name": string,"selected_by": string | null,"slot_id": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"id"?: string,"lock_version"?: number,"org_id": string,"product_name": string,"selected_by"?: string | null,"slot_id": string,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"id"?: string,"lock_version"?: number,"org_id"?: string,"product_name"?: string,"selected_by"?: string | null,"slot_id"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "selections_slot_fk"
      columns: ["slot_id","org_id"]
isOneToOne: false
      referencedRelation: "project_slots"
      referencedColumns: ["id","org_id"]
    }
                  ]
                },"stall_episodes": {
                  Row: {
                    "created_at": string,"detected_at": string,"detector_run_id": string,"id": string,"lock_version": number,"org_id": string,"project_id": string,"quiet_since": string,"resolved_at": string | null,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"detected_at"?: string,"detector_run_id": string,"id"?: string,"lock_version"?: number,"org_id": string,"project_id": string,"quiet_since": string,"resolved_at"?: string | null,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"detected_at"?: string,"detector_run_id"?: string,"id"?: string,"lock_version"?: number,"org_id"?: string,"project_id"?: string,"quiet_since"?: string,"resolved_at"?: string | null,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "stall_episodes_detector_run_id_fkey"
      columns: ["detector_run_id"]
isOneToOne: false
      referencedRelation: "detector_runs"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "stall_episodes_project_fk"
      columns: ["project_id","org_id"]
isOneToOne: false
      referencedRelation: "projects"
      referencedColumns: ["id","org_id"]
    },{
      foreignKeyName: "stall_episodes_project_fk"
      columns: ["project_id","org_id"]
isOneToOne: false
      referencedRelation: "v_projects_overview"
      referencedColumns: ["id","org_id"]
    }
                  ]
                }
          }
          Views: {
            "v_projects_overview": {
                  Row: {
                    "archived_at": string | null,"created_at": string | null,"empty_slots": number | null,"id": string | null,"is_stalled": boolean | null,"last_builder_activity_at": string | null,"lock_version": number | null,"name": string | null,"org_id": string | null,"org_name": string | null,"quiet_since": string | null,"selection_due_date": string | null,"selection_phase_started_at": string | null,"status": string | null,"total_slots": number | null,"updated_at": string | null
                  }
                  ComputedFields: never
                  Relationships: [
                    
                  ]
                }
          }
          Functions: {
            "run_stall_detector_now":
{ Args: Record<PropertyKey, never>; Returns: string
                           }
          }
          Enums: {
            [_ in never]: never
          }
          CompositeTypes: {
            [_ in never]: never
          }
        },"public": {
          Tables: {
            "memberships": {
                  Row: {
                    "created_at": string,"id": string,"lock_version": number,"org_id": string,"role": string,"updated_at": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"id"?: string,"lock_version"?: number,"org_id": string,"role": string,"updated_at"?: string,"user_id": string
                  }
                  Update: {
                    "created_at"?: string,"id"?: string,"lock_version"?: number,"org_id"?: string,"role"?: string,"updated_at"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "memberships_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "orgs"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "memberships_user_id_fkey"
      columns: ["user_id"]
isOneToOne: false
      referencedRelation: "users"
      referencedColumns: ["id"]
    }
                  ]
                },"orgs": {
                  Row: {
                    "created_at": string,"id": string,"lock_version": number,"name": string,"org_type": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"id"?: string,"lock_version"?: number,"name": string,"org_type": string,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"id"?: string,"lock_version"?: number,"name"?: string,"org_type"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"users": {
                  Row: {
                    "created_at": string,"display_name": string | null,"email": string,"id": string,"lock_version": number,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"display_name"?: string | null,"email": string,"id": string,"lock_version"?: number,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"display_name"?: string | null,"email"?: string,"id"?: string,"lock_version"?: number,"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                }
          }
          Views: {
            [_ in never]: never
          }
          Functions: {
            [_ in never]: never
          }
          Enums: {
            [_ in never]: never
          }
          CompositeTypes: {
            [_ in never]: never
          }
        }
}

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>

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
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
  ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
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
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
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
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
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
    : never = never
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
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
    : never = never
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
  ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
  : never

export const Constants = {
  "builder": {
          Enums: {
            
          }
        },"public": {
          Enums: {
            
          }
        }
} as const
