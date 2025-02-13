-- Remove rejection message template column from job_listings table
ALTER TABLE job_listings
DROP COLUMN IF EXISTS rejection_message_template; 