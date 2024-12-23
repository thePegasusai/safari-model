// External dependencies
import { v4 as uuidv4 } from 'uuid'; // v9.0.0
import * as z from 'zod'; // v3.22.2
import { pool } from '../config/database';

// Type definitions for location data
interface ILocation {
  latitude: number;
  longitude: number;
  altitude?: number;
}

// Type definitions for metadata
interface IMetadata {
  weather?: {
    temperature?: number;
    humidity?: number;
    conditions?: string;
  };
  habitat?: string;
  notes?: string;
}

// Main discovery interface
export interface IDiscovery {
  discovery_id: string;
  collection_id: string;
  species_id: string;
  location: ILocation;
  confidence: number;
  media_urls: string[];
  metadata: IMetadata;
  created_at: Date;
  updated_at: Date;
}

// Zod schema for location validation
const LocationSchema = z.object({
  latitude: z.number()
    .min(-90, 'Latitude must be between -90 and 90 degrees')
    .max(90, 'Latitude must be between -90 and 90 degrees'),
  longitude: z.number()
    .min(-180, 'Longitude must be between -180 and 180 degrees')
    .max(180, 'Longitude must be between -180 and 180 degrees'),
  altitude: z.number().optional()
});

// Zod schema for metadata validation
const MetadataSchema = z.object({
  weather: z.object({
    temperature: z.number().optional(),
    humidity: z.number().min(0).max(100).optional(),
    conditions: z.string().optional()
  }).optional(),
  habitat: z.string().optional(),
  notes: z.string().max(1000, 'Notes cannot exceed 1000 characters').optional()
});

// Main discovery schema validation
export const DiscoverySchema = z.object({
  discovery_id: z.string().uuid().optional(),
  collection_id: z.string().uuid(),
  species_id: z.string().uuid(),
  location: LocationSchema,
  confidence: z.number()
    .min(0, 'Confidence score must be between 0 and 1')
    .max(1, 'Confidence score must be between 0 and 1'),
  media_urls: z.array(z.string().url('Invalid media URL format'))
    .min(1, 'At least one media URL is required')
    .max(10, 'Maximum of 10 media items allowed'),
  metadata: MetadataSchema,
  created_at: z.date().optional(),
  updated_at: z.date().optional()
});

export class Discovery implements IDiscovery {
  public discovery_id: string;
  public collection_id: string;
  public species_id: string;
  public location: ILocation;
  public confidence: number;
  public media_urls: string[];
  public metadata: IMetadata;
  public created_at: Date;
  public updated_at: Date;

  constructor(data: Partial<IDiscovery>) {
    // Validate input data
    const validatedData = DiscoverySchema.parse({
      ...data,
      discovery_id: data.discovery_id || uuidv4(),
      created_at: data.created_at || new Date(),
      updated_at: data.updated_at || new Date()
    });

    // Assign validated data to instance
    Object.assign(this, validatedData);
  }

  /**
   * Saves or updates the discovery with transaction support
   * @returns Promise<IDiscovery>
   */
  async save(): Promise<IDiscovery> {
    const client = await pool.connect();
    
    try {
      await client.query('BEGIN');

      const query = `
        INSERT INTO discoveries (
          discovery_id, collection_id, species_id, location, confidence,
          media_urls, metadata, created_at, updated_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        ON CONFLICT (discovery_id) DO UPDATE SET
          location = EXCLUDED.location,
          confidence = EXCLUDED.confidence,
          media_urls = EXCLUDED.media_urls,
          metadata = EXCLUDED.metadata,
          updated_at = EXCLUDED.updated_at
        RETURNING *;
      `;

      const values = [
        this.discovery_id,
        this.collection_id,
        this.species_id,
        this.location,
        this.confidence,
        this.media_urls,
        this.metadata,
        this.created_at,
        new Date() // Always update the updated_at timestamp
      ];

      const result = await client.query(query, values);
      await client.query('COMMIT');
      
      return result.rows[0] as IDiscovery;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Retrieves a discovery by ID
   * @param discovery_id UUID of the discovery
   * @returns Promise<IDiscovery | null>
   */
  static async findById(discovery_id: string): Promise<IDiscovery | null> {
    const query = `
      SELECT * FROM discoveries 
      WHERE discovery_id = $1;
    `;

    const result = await pool.query(query, [discovery_id]);
    return result.rows[0] || null;
  }

  /**
   * Retrieves all discoveries in a collection with pagination
   * @param collection_id UUID of the collection
   * @param options Pagination options
   * @returns Promise<IDiscovery[]>
   */
  static async findByCollectionId(
    collection_id: string,
    options: { limit?: number; offset?: number; } = {}
  ): Promise<IDiscovery[]> {
    const { limit = 50, offset = 0 } = options;
    
    const query = `
      SELECT * FROM discoveries 
      WHERE collection_id = $1 
      ORDER BY created_at DESC 
      LIMIT $2 OFFSET $3;
    `;

    const result = await pool.query(query, [collection_id, limit, offset]);
    return result.rows;
  }

  /**
   * Deletes a discovery and its associated media
   * @returns Promise<void>
   */
  async delete(): Promise<void> {
    const client = await pool.connect();
    
    try {
      await client.query('BEGIN');

      // Delete the discovery record
      const query = `
        DELETE FROM discoveries 
        WHERE discovery_id = $1 
        RETURNING media_urls;
      `;

      const result = await client.query(query, [this.discovery_id]);
      
      // If media cleanup is needed, handle it here
      if (result.rows[0]?.media_urls?.length > 0) {
        // Implement media cleanup logic here
        // This would typically involve calling a media service to remove files
      }

      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }
}