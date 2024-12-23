-- PostgreSQL initialization script for Wildlife Safari Pokédex database
-- Version: 1.0
-- Required PostgreSQL version: 13+

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";      -- UUID support
CREATE EXTENSION IF NOT EXISTS "postgis";        -- Spatial capabilities
CREATE EXTENSION IF NOT EXISTS "pgcrypto";       -- Encryption support
CREATE EXTENSION IF NOT EXISTS "btree_gist";     -- Combined B-tree and GiST indexes
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements"; -- Query performance monitoring

-- Create custom enumeration types
DO $$
BEGIN
    -- User roles enum
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE user_role AS ENUM (
            'BASIC_USER',
            'RESEARCHER',
            'MODERATOR',
            'ADMIN'
        );
    END IF;

    -- Conservation status enum
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'conservation_status') THEN
        CREATE TYPE conservation_status AS ENUM (
            'LEAST_CONCERN',
            'VULNERABLE',
            'ENDANGERED',
            'CRITICALLY_ENDANGERED'
        );
    END IF;

    -- Discovery type enum
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'discovery_type') THEN
        CREATE TYPE discovery_type AS ENUM (
            'WILDLIFE',
            'FOSSIL'
        );
    END IF;

    -- Verification status enum
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'verification_status') THEN
        CREATE TYPE verification_status AS ENUM (
            'PENDING',
            'VERIFIED',
            'REJECTED'
        );
    END IF;
END$$;

-- Create users table with enhanced security
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    name VARCHAR(100) NOT NULL,
    role user_role NOT NULL DEFAULT 'BASIC_USER',
    enabled BOOLEAN NOT NULL DEFAULT true,
    preferences JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_login_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT email_format CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

-- Create collections table
CREATE TABLE IF NOT EXISTS collections (
    collection_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT collection_name_length CHECK (char_length(name) >= 3)
);

-- Create species table
CREATE TABLE IF NOT EXISTS species (
    species_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scientific_name VARCHAR(255) NOT NULL UNIQUE,
    common_name VARCHAR(255) NOT NULL,
    taxonomy JSONB NOT NULL,
    conservation_status conservation_status NOT NULL,
    description TEXT,
    habitat TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT scientific_name_format CHECK (scientific_name ~ '^[A-Z][a-z]+ [a-z]+$')
);

-- Create discoveries table with partitioning
CREATE TABLE IF NOT EXISTS discoveries (
    discovery_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    collection_id UUID NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
    species_id UUID NOT NULL REFERENCES species(id),
    discovery_type discovery_type NOT NULL,
    verification_status verification_status NOT NULL DEFAULT 'PENDING',
    location GEOGRAPHY(POINT, 4326) NOT NULL,
    confidence NUMERIC(4,3) NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
) PARTITION BY RANGE (created_at);

-- Create partitions for discoveries (example for one year)
CREATE TABLE discoveries_2024_q1 PARTITION OF discoveries
    FOR VALUES FROM ('2024-01-01') TO ('2024-04-01');
CREATE TABLE discoveries_2024_q2 PARTITION OF discoveries
    FOR VALUES FROM ('2024-04-01') TO ('2024-07-01');
CREATE TABLE discoveries_2024_q3 PARTITION OF discoveries
    FOR VALUES FROM ('2024-07-01') TO ('2024-10-01');
CREATE TABLE discoveries_2024_q4 PARTITION OF discoveries
    FOR VALUES FROM ('2024-10-01') TO ('2025-01-01');

-- Create media_files table
CREATE TABLE IF NOT EXISTS media_files (
    media_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    discovery_id UUID NOT NULL REFERENCES discoveries(discovery_id) ON DELETE CASCADE,
    file_type VARCHAR(50) NOT NULL,
    file_path VARCHAR(255) NOT NULL,
    file_size BIGINT NOT NULL,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_file_size CHECK (file_size > 0)
);

-- Create audit_logs table
CREATE TABLE IF NOT EXISTS audit_logs (
    log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name VARCHAR(50) NOT NULL,
    record_id UUID NOT NULL,
    action VARCHAR(10) NOT NULL,
    old_data JSONB,
    new_data JSONB,
    user_id UUID REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create optimized indexes
CREATE INDEX IF NOT EXISTS idx_users_email ON users USING btree (email);
CREATE INDEX IF NOT EXISTS idx_users_role ON users USING btree (role);
CREATE INDEX IF NOT EXISTS idx_collections_user_time ON collections USING btree (user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_collections_metadata ON collections USING gin (metadata);
CREATE INDEX IF NOT EXISTS idx_discoveries_collection ON discoveries USING btree (collection_id);
CREATE INDEX IF NOT EXISTS idx_discoveries_spatial ON discoveries USING gist (location);
CREATE INDEX IF NOT EXISTS idx_discoveries_verification ON discoveries USING btree (verification_status) 
    WHERE verification_status = 'PENDING';
CREATE INDEX IF NOT EXISTS idx_discoveries_type_time ON discoveries USING btree (discovery_type, created_at);
CREATE INDEX IF NOT EXISTS idx_audit_logs_time ON audit_logs USING brin (created_at);

-- Create function for updating timestamps
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for timestamp updates
CREATE TRIGGER update_users_timestamp
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_collections_timestamp
    BEFORE UPDATE ON collections
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_discoveries_timestamp
    BEFORE UPDATE ON discoveries
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_species_timestamp
    BEFORE UPDATE ON species
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

-- Create audit trail function
CREATE OR REPLACE FUNCTION audit_trail()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_logs (
        table_name,
        record_id,
        action,
        old_data,
        new_data,
        user_id
    ) VALUES (
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        TG_OP,
        CASE WHEN TG_OP = 'DELETE' THEN row_to_json(OLD) ELSE NULL END,
        CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN row_to_json(NEW) ELSE NULL END,
        CURRENT_USER::uuid
    );
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create audit triggers for main tables
CREATE TRIGGER audit_users
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW EXECUTE FUNCTION audit_trail();

CREATE TRIGGER audit_collections
    AFTER INSERT OR UPDATE OR DELETE ON collections
    FOR EACH ROW EXECUTE FUNCTION audit_trail();

CREATE TRIGGER audit_discoveries
    AFTER INSERT OR UPDATE OR DELETE ON discoveries
    FOR EACH ROW EXECUTE FUNCTION audit_trail();

-- Grant minimal required permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO wildlife_app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO wildlife_app_user;