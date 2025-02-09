-- Create video_saves table to track saved videos
CREATE TABLE IF NOT EXISTS video_saves (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  video_id UUID NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  UNIQUE(user_id, video_id)
);

-- Add RLS policies
ALTER TABLE video_saves ENABLE ROW LEVEL SECURITY;

-- Users can view their own saves
CREATE POLICY "Users can view their own saves"
ON video_saves FOR SELECT
USING (auth.uid() = user_id);

-- Users can save videos
CREATE POLICY "Users can save videos"
ON video_saves FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Users can unsave videos
CREATE POLICY "Users can delete their own saves"
ON video_saves FOR DELETE
USING (auth.uid() = user_id); 