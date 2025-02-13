-- Create profile_experience table
CREATE TABLE IF NOT EXISTS "public"."profile_experience" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "profile_id" uuid NOT NULL REFERENCES "public"."profiles"("id") ON DELETE CASCADE,
    "company" text NOT NULL,
    "role" text NOT NULL,
    "description" text,
    "start_date" date NOT NULL,
    "end_date" date,
    "is_current" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    PRIMARY KEY ("id")
);

-- Add RLS policies
ALTER TABLE "public"."profile_experience" ENABLE ROW LEVEL SECURITY;

-- Allow users to view their own experience and experience of others
CREATE POLICY "View own and others experience" ON "public"."profile_experience"
    FOR SELECT USING (true);

-- Allow users to manage their own experience
CREATE POLICY "Users can manage own experience" ON "public"."profile_experience"
    FOR ALL USING (auth.uid() = profile_id);

-- Add updated_at trigger
CREATE TRIGGER "handle_profile_experience_updated_at" BEFORE UPDATE ON "public"."profile_experience"
    FOR EACH ROW EXECUTE FUNCTION "public"."handle_updated_at"();

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS "profile_experience_profile_id_idx" ON "public"."profile_experience" ("profile_id");
CREATE INDEX IF NOT EXISTS "profile_experience_company_idx" ON "public"."profile_experience" ("company");

-- Add comment
COMMENT ON TABLE "public"."profile_experience" IS 'Stores user work experience history'; 