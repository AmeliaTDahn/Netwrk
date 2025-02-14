-- Drop existing policies that might conflict
DROP POLICY IF EXISTS "Business users can view listings" ON public.job_listings;
DROP POLICY IF EXISTS "Non-business users can view active listings" ON public.job_listings;
DROP POLICY IF EXISTS "Anyone can view active listings" ON public.job_listings;
DROP POLICY IF EXISTS "Businesses can view their own listings" ON public.job_listings;
DROP POLICY IF EXISTS "Users can view shared listings" ON public.job_listings;

-- Create a simple policy for business users
CREATE POLICY "Business users can view all listings"
    ON public.job_listings
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM profiles 
            WHERE id = auth.uid() 
            AND account_type = 'business'
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