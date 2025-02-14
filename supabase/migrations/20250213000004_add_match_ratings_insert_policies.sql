-- Add INSERT policies for application_match_ratings table

-- Allow users to create match ratings for their own applications
CREATE POLICY "Users can create match ratings for their own applications"
    ON public.application_match_ratings FOR INSERT
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.job_applications
        WHERE job_applications.id = application_id
        AND job_applications.applicant_id = auth.uid()
    ));

-- Allow business users to create match ratings for applications to their listings
CREATE POLICY "Business users can create match ratings for their listings"
    ON public.application_match_ratings FOR INSERT
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.job_listings
        WHERE job_listings.id = listing_id
        AND job_listings.business_id = auth.uid()
    ));

-- Allow system-level operations (for AI service)
CREATE POLICY "System can create match ratings"
    ON public.application_match_ratings FOR INSERT
    WITH CHECK (auth.role() = 'authenticated'); 