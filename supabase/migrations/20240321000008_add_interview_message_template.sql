-- Add interview_message_template column to job_listings table
ALTER TABLE job_listings
ADD COLUMN interview_message_template TEXT;

-- Set default template for existing listings
UPDATE job_listings
SET interview_message_template = 'Hi! Thanks for applying. We would like to schedule an interview with you. Please let me know your availability for this week.';

-- Drop column from profiles if it exists
ALTER TABLE profiles
DROP COLUMN IF EXISTS interview_message_template; 