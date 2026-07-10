export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

export type Database = {
  public: {
    Tables: {
      actions: {
        Row: {
          bot_id: string | null;
          created_at: string;
          data: Json;
          game_id: string;
          id: string;
          kind: Database["public"]["Enums"]["action_kind"];
          player_index: number | null;
          type: Database["public"]["Enums"]["action_type"];
          user_id: string | null;
          version_after: number;
        };
        Insert: {
          bot_id?: string | null;
          created_at?: string;
          data: Json;
          game_id: string;
          id?: string;
          kind: Database["public"]["Enums"]["action_kind"];
          player_index?: number | null;
          type?: Database["public"]["Enums"]["action_type"];
          user_id?: string | null;
          version_after: number;
        };
        Update: {
          bot_id?: string | null;
          created_at?: string;
          data?: Json;
          game_id?: string;
          id?: string;
          kind?: Database["public"]["Enums"]["action_kind"];
          player_index?: number | null;
          type?: Database["public"]["Enums"]["action_type"];
          user_id?: string | null;
          version_after?: number;
        };
        Relationships: [
          {
            foreignKeyName: "actions_bot_id_fkey";
            columns: ["bot_id"];
            isOneToOne: false;
            referencedRelation: "bots";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "actions_game_id_fkey";
            columns: ["game_id"];
            isOneToOne: false;
            referencedRelation: "games";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "actions_state_fk";
            columns: ["game_id", "version_after"];
            isOneToOne: true;
            referencedRelation: "game_states";
            referencedColumns: ["game_id", "version"];
          },
          {
            foreignKeyName: "actions_user_id_fkey";
            columns: ["user_id"];
            isOneToOne: false;
            referencedRelation: "users";
            referencedColumns: ["id"];
          },
        ];
      };
      bots: {
        Row: {
          avatar_url: string | null;
          config: Json;
          created_at: string;
          display_name: string;
          id: string;
          is_local: boolean;
          rated_eligible: boolean;
          schema_version: number;
          username: string;
          webhook_url: string | null;
        };
        Insert: {
          avatar_url?: string | null;
          config?: Json;
          created_at?: string;
          display_name: string;
          id?: string;
          is_local: boolean;
          rated_eligible?: boolean;
          schema_version: number;
          username: string;
          webhook_url?: string | null;
        };
        Update: {
          avatar_url?: string | null;
          config?: Json;
          created_at?: string;
          display_name?: string;
          id?: string;
          is_local?: boolean;
          rated_eligible?: boolean;
          schema_version?: number;
          username?: string;
          webhook_url?: string | null;
        };
        Relationships: [];
      };
      device_installations: {
        Row: {
          fid: string;
          platform: string;
          updated_at: string;
          user_id: string;
        };
        Insert: {
          fid: string;
          platform: string;
          updated_at?: string;
          user_id: string;
        };
        Update: {
          fid?: string;
          platform?: string;
          updated_at?: string;
          user_id?: string;
        };
        Relationships: [];
      };
      game_outcomes: {
        Row: {
          bot_id: string | null;
          game_id: string;
          placement: number;
          player_index: number;
          result: Database["public"]["Enums"]["game_result"];
          score: number | null;
          team_index: number;
          user_id: string | null;
        };
        Insert: {
          bot_id?: string | null;
          game_id: string;
          placement: number;
          player_index: number;
          result: Database["public"]["Enums"]["game_result"];
          score?: number | null;
          team_index: number;
          user_id?: string | null;
        };
        Update: {
          bot_id?: string | null;
          game_id?: string;
          placement?: number;
          player_index?: number;
          result?: Database["public"]["Enums"]["game_result"];
          score?: number | null;
          team_index?: number;
          user_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "game_outcomes_bot_id_fkey";
            columns: ["bot_id"];
            isOneToOne: false;
            referencedRelation: "bots";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "game_outcomes_game_id_fkey";
            columns: ["game_id"];
            isOneToOne: false;
            referencedRelation: "games";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "game_outcomes_user_id_fkey";
            columns: ["user_id"];
            isOneToOne: false;
            referencedRelation: "users";
            referencedColumns: ["id"];
          },
        ];
      };
      game_states: {
        Row: {
          created_at: string;
          game_id: string;
          pending_players: number[];
          player_times: number[] | null;
          rng_seed: string;
          state: Json;
          turn_deadline: string | null;
          turn_started_at: string | null;
          version: number;
        };
        Insert: {
          created_at?: string;
          game_id: string;
          pending_players: number[];
          player_times?: number[] | null;
          rng_seed: string;
          state: Json;
          turn_deadline?: string | null;
          turn_started_at?: string | null;
          version: number;
        };
        Update: {
          created_at?: string;
          game_id?: string;
          pending_players?: number[];
          player_times?: number[] | null;
          rng_seed?: string;
          state?: Json;
          turn_deadline?: string | null;
          turn_started_at?: string | null;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "game_states_game_id_fkey";
            columns: ["game_id"];
            isOneToOne: false;
            referencedRelation: "games";
            referencedColumns: ["id"];
          },
        ];
      };
      games: {
        Row: {
          access: Database["public"]["Enums"]["game_access"];
          budget_seconds: number | null;
          config: Json;
          created_at: string;
          created_by: string | null;
          finished_at: string | null;
          id: string;
          increment_seconds: number | null;
          max_players: number;
          min_players: number;
          rated: boolean;
          rating_pool: string | null;
          schema_version: number;
          short_code: string;
          status: Database["public"]["Enums"]["game_status"];
          turn_seconds: number | null;
          updated_at: string;
        };
        Insert: {
          access?: Database["public"]["Enums"]["game_access"];
          budget_seconds?: number | null;
          config?: Json;
          created_at?: string;
          created_by?: string | null;
          finished_at?: string | null;
          id?: string;
          increment_seconds?: number | null;
          max_players: number;
          min_players: number;
          rated?: boolean;
          rating_pool?: string | null;
          schema_version: number;
          short_code: string;
          status?: Database["public"]["Enums"]["game_status"];
          turn_seconds?: number | null;
          updated_at?: string;
        };
        Update: {
          access?: Database["public"]["Enums"]["game_access"];
          budget_seconds?: number | null;
          config?: Json;
          created_at?: string;
          created_by?: string | null;
          finished_at?: string | null;
          id?: string;
          increment_seconds?: number | null;
          max_players?: number;
          min_players?: number;
          rated?: boolean;
          rating_pool?: string | null;
          schema_version?: number;
          short_code?: string;
          status?: Database["public"]["Enums"]["game_status"];
          turn_seconds?: number | null;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "games_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "users";
            referencedColumns: ["id"];
          },
        ];
      };
      observations: {
        Row: {
          bot_id: string | null;
          created_at: string;
          data: Json;
          game_id: string;
          pending_players: number[];
          player_index: number;
          player_times: number[] | null;
          turn_deadline: string | null;
          turn_started_at: string | null;
          user_id: string | null;
          version: number;
        };
        Insert: {
          bot_id?: string | null;
          created_at?: string;
          data: Json;
          game_id: string;
          pending_players: number[];
          player_index: number;
          player_times?: number[] | null;
          turn_deadline?: string | null;
          turn_started_at?: string | null;
          user_id?: string | null;
          version: number;
        };
        Update: {
          bot_id?: string | null;
          created_at?: string;
          data?: Json;
          game_id?: string;
          pending_players?: number[];
          player_index?: number;
          player_times?: number[] | null;
          turn_deadline?: string | null;
          turn_started_at?: string | null;
          user_id?: string | null;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "observations_bot_id_fkey";
            columns: ["bot_id"];
            isOneToOne: false;
            referencedRelation: "bots";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "observations_game_id_fkey";
            columns: ["game_id"];
            isOneToOne: false;
            referencedRelation: "games";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "observations_user_id_fkey";
            columns: ["user_id"];
            isOneToOne: false;
            referencedRelation: "users";
            referencedColumns: ["id"];
          },
        ];
      };
      participants: {
        Row: {
          bot_id: string | null;
          created_at: string;
          game_id: string;
          id: string;
          player_index: number;
          type: Database["public"]["Enums"]["participant_type"];
          user_id: string | null;
        };
        Insert: {
          bot_id?: string | null;
          created_at?: string;
          game_id: string;
          id?: string;
          player_index: number;
          type?: Database["public"]["Enums"]["participant_type"];
          user_id?: string | null;
        };
        Update: {
          bot_id?: string | null;
          created_at?: string;
          game_id?: string;
          id?: string;
          player_index?: number;
          type?: Database["public"]["Enums"]["participant_type"];
          user_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "participants_bot_id_fkey";
            columns: ["bot_id"];
            isOneToOne: false;
            referencedRelation: "bots";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "participants_game_id_fkey";
            columns: ["game_id"];
            isOneToOne: false;
            referencedRelation: "games";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "participants_user_id_fkey";
            columns: ["user_id"];
            isOneToOne: false;
            referencedRelation: "users";
            referencedColumns: ["id"];
          },
        ];
      };
      player_ratings: {
        Row: {
          bot_id: string | null;
          created_at: string;
          display_rating: number;
          id: string;
          mu: number;
          pool: string;
          revision: number;
          sigma: number;
          updated_at: string;
          user_id: string | null;
        };
        Insert: {
          bot_id?: string | null;
          created_at?: string;
          display_rating?: number;
          id?: string;
          mu?: number;
          pool: string;
          revision: number;
          sigma?: number;
          updated_at?: string;
          user_id?: string | null;
        };
        Update: {
          bot_id?: string | null;
          created_at?: string;
          display_rating?: number;
          id?: string;
          mu?: number;
          pool?: string;
          revision?: number;
          sigma?: number;
          updated_at?: string;
          user_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "player_ratings_bot_id_fkey";
            columns: ["bot_id"];
            isOneToOne: false;
            referencedRelation: "bots";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "player_ratings_user_id_fkey";
            columns: ["user_id"];
            isOneToOne: false;
            referencedRelation: "users";
            referencedColumns: ["id"];
          },
        ];
      };
      rating_history: {
        Row: {
          bot_id: string | null;
          created_at: string;
          display_after: number;
          display_before: number;
          display_change: number;
          game_id: string;
          id: string;
          mu_after: number;
          mu_before: number;
          pool: string;
          sigma_after: number;
          sigma_before: number;
          user_id: string | null;
        };
        Insert: {
          bot_id?: string | null;
          created_at?: string;
          display_after: number;
          display_before: number;
          display_change: number;
          game_id: string;
          id?: string;
          mu_after: number;
          mu_before: number;
          pool: string;
          sigma_after: number;
          sigma_before: number;
          user_id?: string | null;
        };
        Update: {
          bot_id?: string | null;
          created_at?: string;
          display_after?: number;
          display_before?: number;
          display_change?: number;
          game_id?: string;
          id?: string;
          mu_after?: number;
          mu_before?: number;
          pool?: string;
          sigma_after?: number;
          sigma_before?: number;
          user_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "rating_history_bot_id_fkey";
            columns: ["bot_id"];
            isOneToOne: false;
            referencedRelation: "bots";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "rating_history_game_id_fkey";
            columns: ["game_id"];
            isOneToOne: false;
            referencedRelation: "games";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "rating_history_user_id_fkey";
            columns: ["user_id"];
            isOneToOne: false;
            referencedRelation: "users";
            referencedColumns: ["id"];
          },
        ];
      };
      relationships: {
        Row: {
          created_at: string;
          id: string;
          initiated_by: string;
          status: Database["public"]["Enums"]["relationship_status"];
          updated_at: string;
          user_id_1: string;
          user_id_2: string;
        };
        Insert: {
          created_at?: string;
          id?: string;
          initiated_by: string;
          status?: Database["public"]["Enums"]["relationship_status"];
          updated_at?: string;
          user_id_1: string;
          user_id_2: string;
        };
        Update: {
          created_at?: string;
          id?: string;
          initiated_by?: string;
          status?: Database["public"]["Enums"]["relationship_status"];
          updated_at?: string;
          user_id_1?: string;
          user_id_2?: string;
        };
        Relationships: [
          {
            foreignKeyName: "relationships_initiated_by_fkey";
            columns: ["initiated_by"];
            isOneToOne: false;
            referencedRelation: "users";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "relationships_user_id_1_fkey";
            columns: ["user_id_1"];
            isOneToOne: false;
            referencedRelation: "users";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "relationships_user_id_2_fkey";
            columns: ["user_id_2"];
            isOneToOne: false;
            referencedRelation: "users";
            referencedColumns: ["id"];
          },
        ];
      };
      user_profiles: {
        Row: {
          avatar_url: string | null;
          created_at: string;
          display_name: string;
          id: string;
          updated_at: string;
        };
        Insert: {
          avatar_url?: string | null;
          created_at?: string;
          display_name: string;
          id: string;
          updated_at?: string;
        };
        Update: {
          avatar_url?: string | null;
          created_at?: string;
          display_name?: string;
          id?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "user_profiles_id_fkey";
            columns: ["id"];
            isOneToOne: true;
            referencedRelation: "users";
            referencedColumns: ["id"];
          },
        ];
      };
      users: {
        Row: {
          created_at: string;
          email: string | null;
          id: string;
          payment_tier: string;
          updated_at: string;
          username: string;
        };
        Insert: {
          created_at?: string;
          email?: string | null;
          id: string;
          payment_tier?: string;
          updated_at?: string;
          username: string;
        };
        Update: {
          created_at?: string;
          email?: string | null;
          id?: string;
          payment_tier?: string;
          updated_at?: string;
          username?: string;
        };
        Relationships: [];
      };
    };
    Views: {
      friends_view: {
        Row: {
          created_at: string | null;
          friend_id: string | null;
          initiated_by: string | null;
          status: Database["public"]["Enums"]["relationship_status"] | null;
          updated_at: string | null;
          user_id: string | null;
        };
        Relationships: [];
      };
    };
    Functions: {
      app_bots: {
        Args: never;
        Returns: {
          avatar_url: string;
          config: Json;
          display_name: string;
          id: string;
          is_local: boolean;
          rated_eligible: boolean;
          schema_version: number;
          username: string;
        }[];
      };
      app_cancel_game: { Args: { p_game_id: string }; Returns: undefined };
      app_delete_device_installation: {
        Args: { p_fid: string };
        Returns: undefined;
      };
      app_friends_games: {
        Args: { p_cursor?: string; p_limit?: number };
        Returns: unknown[];
        SetofOptions: {
          from: "*";
          to: "open_games_with_participants";
          isOneToOne: false;
          isSetofReturn: true;
        };
      };
      app_join_game: {
        Args: { p_client_schema_version: number; p_game_id: string };
        Returns: string;
      };
      app_join_game_by_code: {
        Args: { p_client_schema_version: number; p_code: string };
        Returns: string;
      };
      app_leave_game: { Args: { p_game_id: string }; Returns: undefined };
      app_lobby_games: {
        Args: { p_cursor?: string; p_limit?: number };
        Returns: unknown[];
        SetofOptions: {
          from: "*";
          to: "open_games_with_participants";
          isOneToOne: false;
          isSetofReturn: true;
        };
      };
      app_local_bot_observation: {
        Args: { p_game_id: string; p_player_index: number };
        Returns: {
          bot_id: string | null;
          created_at: string;
          data: Json;
          game_id: string;
          pending_players: number[];
          player_index: number;
          player_times: number[] | null;
          turn_deadline: string | null;
          turn_started_at: string | null;
          user_id: string | null;
          version: number;
        }[];
        SetofOptions: {
          from: "*";
          to: "observations";
          isOneToOne: false;
          isSetofReturn: true;
        };
      };
      app_players: {
        Args: { p_ids: string[] };
        Returns: {
          avatar_url: string;
          display_name: string;
          id: string;
          is_guest: boolean;
          username: string;
        }[];
      };
      app_search_users: {
        Args: { p_query: string };
        Returns: {
          avatar_url: string;
          display_name: string;
          id: string;
          username: string;
        }[];
      };
      app_update_username: { Args: { new_username: string }; Returns: string };
      app_upsert_device_installation: {
        Args: { p_fid: string; p_platform: string };
        Returns: undefined;
      };
      engine_accept_friend_request: {
        Args: { p_caller_id: string; p_target_user_id: string };
        Returns: {
          accepted: boolean;
          accepter_display_name: string;
          requester_id: string;
        }[];
      };
      engine_add_bot_to_game: {
        Args: { p_bot_id: string; p_caller_id: string; p_game_id: string };
        Returns: undefined;
      };
      engine_commit_action: {
        Args: {
          p_acting_bot_id: string;
          p_caller_id: string;
          p_expected_version: number;
          p_game_id: string;
          p_mode: string;
          p_transitions: Json;
        };
        Returns: Json;
      };
      engine_commit_start: {
        Args: {
          p_caller_id: string;
          p_game_id: string;
          p_initial_state: Json;
          p_observations: Json;
          p_pending: Json;
          p_seed: string;
          p_turn_seconds: number;
        };
        Returns: undefined;
      };
      engine_create_game: {
        Args: {
          p_access: Database["public"]["Enums"]["game_access"];
          p_budget_seconds: number;
          p_caller_id: string;
          p_config: Json;
          p_increment_seconds: number;
          p_max_players: number;
          p_min_players: number;
          p_pool: string;
          p_rated: boolean;
          p_schema_version: number;
          p_turn_seconds: number;
        };
        Returns: string;
      };
      engine_create_solo_game: {
        Args: {
          p_bot_ids: string[];
          p_budget_seconds?: number;
          p_caller_id: string;
          p_config?: Json;
          p_increment_seconds?: number;
          p_schema_version: number;
          p_turn_seconds?: number;
        };
        Returns: string;
      };
      engine_purge_user: { Args: { p_user_id: string }; Returns: undefined };
      engine_remove_friend: {
        Args: { p_caller_id: string; p_target_user_id: string };
        Returns: undefined;
      };
      engine_send_friend_request: {
        Args: { p_caller_id: string; p_target_user_id: string };
        Returns: {
          actor_display_name: string;
          auto_accepted: boolean;
          created_pending: boolean;
          notify_user_id: string;
        }[];
      };
    };
    Enums: {
      action_kind: "game" | "lifecycle";
      action_type: "user" | "bot" | "system";
      game_access: "public" | "private" | "friends";
      game_result: "win" | "loss" | "draw" | "eliminated";
      game_status: "waiting" | "ready" | "active" | "finished" | "aborted";
      lifecycle_type: "timeout" | "forfeit" | "auto_forfeit";
      participant_type: "human" | "bot";
      relationship_status: "pending" | "accepted" | "blocked";
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
};

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">;

type DefaultSchema =
  DatabaseWithoutInternals[Extract<keyof Database, "public">];

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  } ? keyof (
      & DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]][
        "Tables"
      ]
      & DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]][
        "Views"
      ]
    )
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
} ? (
    & DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]][
      "Tables"
    ]
    & DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]][
      "Views"
    ]
  )[TableName] extends {
    Row: infer R;
  } ? R
  : never
  : DefaultSchemaTableNameOrOptions extends keyof (
    & DefaultSchema["Tables"]
    & DefaultSchema["Views"]
  ) ? (
      & DefaultSchema["Tables"]
      & DefaultSchema["Views"]
    )[DefaultSchemaTableNameOrOptions] extends {
      Row: infer R;
    } ? R
    : never
  : never;

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  } ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]][
      "Tables"
    ]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
} ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]][
    "Tables"
  ][TableName] extends {
    Insert: infer I;
  } ? I
  : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Insert: infer I;
    } ? I
    : never
  : never;

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  } ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]][
      "Tables"
    ]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
} ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]][
    "Tables"
  ][TableName] extends {
    Update: infer U;
  } ? U
  : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Update: infer U;
    } ? U
    : never
  : never;

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  } ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]][
      "Enums"
    ]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
} ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][
    EnumName
  ]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
  : never;

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  } ? keyof DatabaseWithoutInternals[
      PublicCompositeTypeNameOrOptions["schema"]
    ]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
} ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]][
    "CompositeTypes"
  ][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends
    keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
  : never;

export const Constants = {
  public: {
    Enums: {
      action_kind: ["game", "lifecycle"],
      action_type: ["user", "bot", "system"],
      game_access: ["public", "private", "friends"],
      game_result: ["win", "loss", "draw", "eliminated"],
      game_status: ["waiting", "ready", "active", "finished", "aborted"],
      lifecycle_type: ["timeout", "forfeit", "auto_forfeit"],
      participant_type: ["human", "bot"],
      relationship_status: ["pending", "accepted", "blocked"],
    },
  },
} as const;
