-- Drop all existing job_listings policies to start fresh
DROP POLICY IF EXISTS "Business users can view listings" ON public.job_listings;
DROP POLICY IF EXISTS "Non-business users can view active listings" ON public.job_listings;
DROP POLICY IF EXISTS "Anyone can view active listings" ON public.job_listings;
DROP POLICY IF EXISTS "Businesses can view their own listings" ON public.job_listings;
DROP POLICY IF EXISTS "Users can view shared listings" ON public.job_listings;
DROP POLICY IF EXISTS "Businesses can manage their own listings" ON public.job_listings;

-- Create a single comprehensive policy for business users
CREATE POLICY "business_user_access"
    ON public.job_listings
    FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM profiles 
            WHERE id = auth.uid() 
            AND account_type = 'business'
            AND (
                -- Business owns the listing
                business_id = auth.uid()
                OR
                -- Or listing is shared with them
                EXISTS (
                    SELECT 1 FROM shared_listings
                    WHERE listing_id = job_listings.id
                    AND shared_with = auth.uid()
                )
            )
        )
    );

-- Create policy for non-business users
CREATE POLICY "non_business_user_access"
    ON public.job_listings
    FOR SELECT
    USING (
        -- Must be active listing
        is_active = true
        AND
        -- User must not be a business
        NOT EXISTS (
            SELECT 1 FROM profiles 
            WHERE id = auth.uid() 
            AND account_type = 'business'
        )
    );