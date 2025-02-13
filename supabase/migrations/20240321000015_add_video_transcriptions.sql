-- Create video_transcriptions table
CREATE TABLE IF NOT EXISTS public.video_transcriptions (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    application_id uuid REFERENCES public.job_applications(id) ON DELETE CASCADE NOT NULL,
    listing_id uuid REFERENCES public.job_listings(id) ON DELETE CASCADE NOT NULL,
    user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    transcription text NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Enable RLS
ALTER TABLE public.video_transcriptions ENABLE ROW LEVEL SECURITY;

-- Allow business users to view transcriptions for their listings
CREATE POLICY "Business users can view transcriptions for their listings"
    ON public.video_transcriptions FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM public.job_listings
        WHERE job_listings.id = video_transcriptions.listing_id
        AND job_listings.business_id = auth.uid()
    ));

-- Allow users to view their own transcriptions
CREATE POLICY "Users can view their own transcriptions"
    ON public.video_transcriptions FOR SELECT
    USING (user_id = auth.uid());

-- Allow users to create transcriptions for their own applications
CREATE POLICY "Users can create transcriptions for their own applications"
    ON public.video_transcriptions FOR INSERT
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.job_applications
        WHERE job_applications.id = application_id
        AND job_applications.applicant_id = auth.uid()
    ));

-- Create indexes for better query performance
CREATE INDEX video_transcriptions_application_id_idx ON public.video_transcriptions(application_id);
CREATE INDEX video_transcriptions_listing_id_idx ON public.video_transcriptions(listing_id);
CREATE INDEX video_transcriptions_user_id_idx ON public.video_transcriptions(user_id); 