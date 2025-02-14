-- Drop existing policies that might conflict
DROP POLICY IF EXISTS "Anyone can view active listings" ON public.job_listings;
DROP POLICY IF EXISTS "Businesses can view their own listings" ON public.job_listings;

-- Create a new policy for viewing active listings (for non-business users)
CREATE POLICY "Anyone can view active listings"
    ON public.job_listings
    FOR SELECT
    USING (
        is_active = true AND 
        NOT EXISTS (
            SELECT 1 FROM profiles 
            WHERE id = auth.uid() 
            AND account_type = 'business'
        )
    );

-- Create a policy for businesses to view all their own listings (active and inactive)
CREATE POLICY "Businesses can view their own listings"
    ON public.job_listings
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM profiles 
            WHERE id = auth.uid() 
            AND account_type = 'business'
        ) AND (
            business_id = auth.uid() OR 
            EXISTS (
                SELECT 1 FROM shared_listings
                WHERE listing_id = job_listings.id
                AND shared_with = auth.uid()
            )
        )
    ); 