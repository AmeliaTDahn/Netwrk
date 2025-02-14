-- Drop existing policies that might conflict
DROP POLICY IF EXISTS "Businesses can view their own listings" ON public.job_listings;
DROP POLICY IF EXISTS "Anyone can view active listings" ON public.job_listings;
DROP POLICY IF EXISTS "Users can view shared listings" ON public.job_listings;

-- Create a comprehensive policy for business users
CREATE POLICY "Business users can view listings"
    ON public.job_listings
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM profiles 
            WHERE id = auth.uid() 
            AND account_type = 'business'
        ) AND (
            business_id = auth.uid() OR  -- Their own listings
            EXISTS (                     -- Shared listings
                SELECT 1 FROM shared_listings
                WHERE listing_id = job_listings.id
                AND shared_with = auth.uid()
            )
        )
    );

-- Create a policy for non-business users to view active listings
CREATE POLICY "Non-business users can view active listings"
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