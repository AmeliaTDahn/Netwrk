-- Add acceptance and rejection message template columns to job_listings table
ALTER TABLE job_listings
ADD COLUMN acceptance_message_template TEXT,
ADD COLUMN rejection_message_template TEXT;

-- Set default templates for existing listings
UPDATE job_listings
SET acceptance_message_template = 'Congratulations! We are pleased to inform you that we would like to offer you the position. We believe your skills and experience will be a great addition to our team.',
    rejection_message_template = 'Thank you for your interest in the position and for taking the time to go through our interview process. After careful consideration, we have decided to move forward with another candidate who more closely matches our current needs.';