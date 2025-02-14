-- Add back the policy that allows users to view active listings
CREATE POLICY "Anyone can view active listings"
    ON public.job_listings
    FOR SELECT
    USING (is_active = true);

-- Drop and recreate the business view policy to include inactive listings
DROP POLICY IF EXISTS "Businesses can view their own listings" ON public.job_listings;

CREATE POLICY "Businesses can view their own listings"
    ON public.job_listings
    FOR SELECT
    USING (auth.uid() = business_id OR 
           EXISTS (
               SELECT 1 FROM shared_listings
               WHERE listing_id = id
               AND shared_with = auth.uid()
           )); 