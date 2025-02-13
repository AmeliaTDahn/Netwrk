-- Create shared_listings table
CREATE TABLE IF NOT EXISTS shared_listings (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  listing_id UUID REFERENCES job_listings(id) ON DELETE CASCADE NOT NULL,
  shared_by UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  shared_with UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  shared_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  UNIQUE(listing_id, shared_with)
);

-- Enable RLS
ALTER TABLE shared_listings ENABLE ROW LEVEL SECURITY;

-- Users can view listings shared with them
CREATE POLICY "Users can view listings shared with them"
ON shared_listings FOR SELECT
USING (auth.uid() = shared_with);

-- Users can share listings
CREATE POLICY "Users can share listings"
ON shared_listings FOR INSERT
WITH CHECK (
  auth.uid() = shared_by AND
  EXISTS (
    SELECT 1 FROM job_listings
    WHERE id = listing_id
    AND business_id = auth.uid()
  )
);

-- Update job_listings policies to allow shared users to view
CREATE POLICY "Users can view shared listings"
ON job_listings FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM shared_listings
    WHERE listing_id = id
    AND shared_with = auth.uid()
  )
);

-- Update job_applications policies to allow shared users to view and update
CREATE POLICY "Shared users can view applications"
ON job_applications FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM shared_listings
    WHERE listing_id = job_listing_id
    AND shared_with = auth.uid()
  )
);

CREATE POLICY "Shared users can update application status"
ON job_applications FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM shared_listings
    WHERE listing_id = job_listing_id
    AND shared_with = auth.uid()
  )
); 