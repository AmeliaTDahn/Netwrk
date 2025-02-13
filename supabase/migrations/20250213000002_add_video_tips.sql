-- Add video_application_tips column to job_listings table
ALTER TABLE job_listings
ADD COLUMN IF NOT EXISTS video_application_tips text[];

-- Update existing listings with empty tips array
UPDATE job_listings
SET video_application_tips = ARRAY[]::text[]
WHERE video_application_tips IS NULL;

-- Add comment to explain the column
COMMENT ON COLUMN job_listings.video_application_tips IS 'Array of AI-generated tips for creating a good video application for this job'; 