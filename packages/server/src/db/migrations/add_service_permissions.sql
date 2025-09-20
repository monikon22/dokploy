-- Add new permissions for service environments and terminal access
ALTER TABLE member 
ADD COLUMN IF NOT EXISTS "canAccessToServiceEnvironments" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS "canAccessToServiceTerminal" BOOLEAN NOT NULL DEFAULT false;