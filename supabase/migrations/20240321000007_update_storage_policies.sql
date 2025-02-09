-- Update storage policies to allow shared users to access application files
CREATE POLICY "Shared users can access application files"
ON storage.objects FOR ALL
USING (
  bucket_id = 'applications'
  AND auth.role() = 'authenticated'
  AND EXISTS (
    SELECT 1
    FROM job_applications ja
    JOIN shared_listings sl ON sl.listing_id = ja.job_listing_id
    WHERE storage.foldername(name) = array[ja.applicant_id::text]
    AND sl.shared_with = auth.uid()
  )
);

-- Update existing policy for businesses to include shared listings
DROP POLICY IF EXISTS "Businesses can access application files for their listings" ON storage.objects;

CREATE POLICY "Businesses can access application files for their listings"
ON storage.objects FOR ALL
USING (
  bucket_id = 'applications'
  AND auth.role() = 'authenticated'
  AND (
    EXISTS (
      SELECT 1
      FROM job_applications ja
      JOIN job_listings jl ON jl.id = ja.job_listing_id
      WHERE storage.foldername(name) = array[ja.applicant_id::text]
      AND jl.business_id = auth.uid()
    )
    OR
    EXISTS (
      SELECT 1
      FROM job_applications ja
      JOIN shared_listings sl ON sl.listing_id = ja.job_listing_id
      WHERE storage.foldername(name) = array[ja.applicant_id::text]
      AND sl.shared_with = auth.uid()
    )
  )
);

-- Update job_listings policies to prevent shared users from modifying listings
DROP POLICY IF EXISTS "Users can view shared listings" ON job_listings;
DROP POLICY IF EXISTS "Businesses can manage their own listings" ON job_listings;

-- Separate policies for different operations
CREATE POLICY "Businesses can view their own listings"
ON job_listings
FOR SELECT
USING (auth.uid() = business_id);

CREATE POLICY "Businesses can insert their own listings"
ON job_listings
FOR INSERT
WITH CHECK (auth.uid() = business_id);

CREATE POLICY "Businesses can update their own listings"
ON job_listings
FOR UPDATE
USING (auth.uid() = business_id);

CREATE POLICY "Businesses can delete their own listings"
ON job_listings
FOR DELETE
USING (auth.uid() = business_id);

CREATE POLICY "Users can view shared listings"
ON job_listings
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM shared_listings
    WHERE listing_id = id
    AND shared_with = auth.uid()
  )
); 