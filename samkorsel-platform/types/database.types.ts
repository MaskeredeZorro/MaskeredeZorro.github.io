export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export interface Database {
  public: {
    Tables: {
      profiles: {
        Row: {
          id: string
          full_name: string | null
          avatar_url: string | null
          is_verified_mitid: boolean
          created_at: string
        }
        Insert: {
          id: string
          full_name?: string | null
          avatar_url?: string | null
        }
        Update: {
          full_name?: string | null
          avatar_url?: string | null
          is_verified_mitid?: boolean
        }
      }
      rides: {
        Row: {
          id: string
          driver_id: string
          origin_city: string
          destination_city: string
          departure_time: string
          price_dkk: number
          status: string
        }
        Insert: {
          driver_id: string
          origin_city: string
          destination_city: string
          departure_time: string
          price_dkk: number
        }
      }
    }
  }
}