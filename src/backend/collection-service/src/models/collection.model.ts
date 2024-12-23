// External dependencies
import { v4 as uuidv4 } from 'uuid'; // v9.0.0
import * as z from 'zod'; // v3.22.2

// Internal dependencies
import { pool } from '../config/database';
import { IDiscovery } from './discovery.model';

// Type definitions for collection metadata
interface CollectionMetadata {
  tags: string[];
  category?: 'wildlife' | 'fossil' | 'mixed';
  visibility: 'private' | 'public' | 'shared';
  shared_with?: string[]; // Array of user IDs
  last_sync?: Date;
  stats?: {
    total_discoveries: number;
    unique_species: number;
    rare_findings: number;
  };
}

// Interface for pagination options
interface PaginationOptions {
  limit?: number;
  offset?: number;
  sort_by?: 'created_at' | 'updated_at' | 'name';
  sort_order?: 'asc' | 'desc';
}

// Interface for paginated results
interface PaginatedCollections {
  items: ICollection[];
  total: number;
  page_size: number;
  offset: number;
}

// Main collection interface
export interface ICollection {
  collection_id: string;
  user_id: string;
  name: string;
  description: string;
  metadata: CollectionMetadata;
  created_at: Date;
  updated_at: Date;
  deleted_at: Date | null;
}

// Enhanced Zod schema for collection validation
export const CollectionSchema = z.object({
  collection_id: z.string().uuid().optional(),
  user_id: z.string().uuid(),
  name: z.string()
    .min(1, 'Collection name is required')
    .max(100, 'Collection name cannot exceed 100 characters')
    .regex(/^[\w\s-]+$/, 'Collection name can only contain letters, numbers, spaces, and hyphens'),
  description: z.string()
    .max(1000, 'Description cannot exceed 1000 characters')
    .optional()
    .default(''),
  metadata: z.object({
    tags: z.array(z.string().max(30)).max(10, 'Maximum 10 tags allowed'),
    category: z.enum(['wildlife', 'fossil', 'mixed']).optional(),
    visibility: z.enum(['private', 'public', 'shared']).default('private'),
    shared_with: z.array(z.string().uuid()).optional(),
    last_sync: z.date().optional(),
    stats: z.object({
      total_discoveries: z.number().min(0).optional(),
      unique_species: z.number().min(0).optional(),
      rare_findings: z.number().min(0).optional()
    }).optional()
  }),
  created_at: z.date().optional(),
  updated_at: z.date().optional(),
  deleted_at: z.date().nullable().optional()
});

export class Collection implements ICollection {
  public collection_id: string;
  public user_id: string;
  public name: string;
  public description: string;
  public metadata: CollectionMetadata;
  public created_at: Date;
  public updated_at: Date;
  public deleted_at: Date | null;

  constructor(data: Partial<ICollection>) {
    // Validate and sanitize input data
    const validatedData = CollectionSchema.parse({
      ...data,
      collection_id: data.collection_id || uuidv4(),
      created_at: data.created_at || new Date(),
      updated_at: data.updated_at || new Date(),
      deleted_at: data.deleted_at || null,
      metadata: {
        ...data.metadata,
        tags: data.metadata?.tags || [],
        visibility: data.metadata?.visibility || 'private'
      }
    });

    // Assign validated data to instance
    Object.assign(this, validatedData);
  }

  /**
   * Saves or updates the collection with transaction support
   * @returns Promise<ICollection>
   */
  async save(): Promise<ICollection> {
    const client = await pool.connect();
    
    try {
      await client.query('BEGIN');

      const query = `
        INSERT INTO collections (
          collection_id, user_id, name, description, metadata,
          created_at, updated_at, deleted_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        ON CONFLICT (collection_id) DO UPDATE SET
          name = EXCLUDED.name,
          description = EXCLUDED.description,
          metadata = collections.metadata || EXCLUDED.metadata,
          updated_at = EXCLUDED.updated_at
        RETURNING *;
      `;

      const values = [
        this.collection_id,
        this.user_id,
        this.name,
        this.description,
        this.metadata,
        this.created_at,
        new Date(), // Always update the updated_at timestamp
        this.deleted_at
      ];

      const result = await client.query(query, values);
      await client.query('COMMIT');
      
      return result.rows[0] as ICollection;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Retrieves a non-deleted collection by ID
   * @param collection_id UUID of the collection
   * @returns Promise<ICollection | null>
   */
  static async findById(collection_id: string): Promise<ICollection | null> {
    const query = `
      SELECT * FROM collections 
      WHERE collection_id = $1 
      AND deleted_at IS NULL;
    `;

    const result = await pool.query(query, [collection_id]);
    return result.rows[0] || null;
  }

  /**
   * Retrieves all non-deleted collections for a user with pagination
   * @param user_id UUID of the user
   * @param options Pagination options
   * @returns Promise<PaginatedCollections>
   */
  static async findByUserId(
    user_id: string,
    options: PaginationOptions = {}
  ): Promise<PaginatedCollections> {
    const {
      limit = 50,
      offset = 0,
      sort_by = 'updated_at',
      sort_order = 'desc'
    } = options;

    const queryParams = [user_id, limit, offset];

    // Get total count
    const countQuery = `
      SELECT COUNT(*) as total 
      FROM collections 
      WHERE user_id = $1 
      AND deleted_at IS NULL;
    `;
    const countResult = await pool.query(countQuery, [user_id]);
    const total = parseInt(countResult.rows[0].total);

    // Get paginated results
    const query = `
      SELECT * FROM collections 
      WHERE user_id = $1 
      AND deleted_at IS NULL 
      ORDER BY ${sort_by} ${sort_order} 
      LIMIT $2 OFFSET $3;
    `;

    const result = await pool.query(query, queryParams);

    return {
      items: result.rows,
      total,
      page_size: limit,
      offset
    };
  }

  /**
   * Soft deletes a collection by setting deleted_at timestamp
   * @returns Promise<void>
   */
  async softDelete(): Promise<void> {
    const client = await pool.connect();
    
    try {
      await client.query('BEGIN');

      const query = `
        UPDATE collections 
        SET deleted_at = $1, 
            updated_at = $1 
        WHERE collection_id = $2 
        AND deleted_at IS NULL;
      `;

      await client.query(query, [new Date(), this.collection_id]);
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Updates collection statistics based on discoveries
   * @returns Promise<void>
   */
  async updateStats(): Promise<void> {
    const client = await pool.connect();
    
    try {
      await client.query('BEGIN');

      // Get collection statistics
      const statsQuery = `
        SELECT 
          COUNT(*) as total_discoveries,
          COUNT(DISTINCT species_id) as unique_species,
          COUNT(*) FILTER (WHERE confidence > 0.95) as rare_findings
        FROM discoveries 
        WHERE collection_id = $1;
      `;

      const statsResult = await client.query(statsQuery, [this.collection_id]);
      const stats = statsResult.rows[0];

      // Update collection metadata with new stats
      this.metadata.stats = {
        total_discoveries: parseInt(stats.total_discoveries),
        unique_species: parseInt(stats.unique_species),
        rare_findings: parseInt(stats.rare_findings)
      };

      await this.save();
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }
}