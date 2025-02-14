-- Create application_match_ratings table
CREATE TABLE IF NOT EXISTS public.application_match_ratings (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    application_id uuid REFERENCES public.job_applications(id) ON DELETE CASCADE NOT NULL,
    listing_id uuid REFERENCES public.job_listings(id) ON DELETE CASCADE NOT NULL,
    user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    match_rating numeric CHECK (match_rating >= 1 AND match_rating <= 10) NOT NULL,
    analysis_text text NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    UNIQUE(application_id)
);

-- Enable RLS
ALTER TABLE public.application_match_ratings ENABLE ROW LEVEL SECURITY;

-- Allow business users to view match ratings for their listings
CREATE POLICY "Business users can view match ratings for their listings"
    ON public.application_match_ratings FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM public.job_listings
        WHERE job_listings.id = application_match_ratings.listing_id
        AND job_listings.business_id = auth.uid()
    ));

-- Allow users to view their own match ratings
CREATE POLICY "Users can view their own match ratings"
    ON public.application_match_ratings FOR SELECT
    USING (user_id = auth.uid());

-- Create indexes for better query performance
CREATE INDEX application_match_ratings_application_id_idx ON public.application_match_ratings(application_id);
CREATE INDEX application_match_ratings_listing_id_idx ON public.application_match_ratings(listing_id);
CREATE INDEX application_match_ratings_user_id_idx ON public.application_match_ratings(user_id); 