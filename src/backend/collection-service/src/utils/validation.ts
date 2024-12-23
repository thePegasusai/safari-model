// External dependencies
import * as z from 'zod'; // v3.22.2
import { validate as validateUUIDFormat } from 'uuid'; // v9.0.0

// Internal dependencies
import { ICollection } from '../models/collection.model';
import { IDiscovery } from '../models/discovery.model';

/**
 * Enhanced location validation schema with precise coordinate checks
 */
export const LocationValidationSchema = z.object({
  latitude: z.number()
    .min(-90, 'Latitude must be between -90 and 90 degrees')
    .max(90, 'Latitude must be between -90 and 90 degrees')
    .transform(val => Number(val.toFixed(6))), // Limit to 6 decimal places
  longitude: z.number()
    .min(-180, 'Longitude must be between -180 and 180 degrees')
    .max(180, 'Longitude must be between -180 and 180 degrees')
    .transform(val => Number(val.toFixed(6))),
  altitude: z.number()
    .optional()
    .transform(val => val ? Number(val.toFixed(2)) : undefined)
});

/**
 * Enhanced collection validation schema with strict security rules
 */
export const CollectionValidationSchema = z.object({
  collection_id: z.string()
    .uuid('Invalid collection ID format')
    .refine(val => validateUUIDFormat(val), 'Invalid UUID v4 format'),
  user_id: z.string()
    .uuid('Invalid user ID format')
    .refine(val => validateUUIDFormat(val), 'Invalid UUID v4 format'),
  name: z.string()
    .min(3, 'Collection name must be at least 3 characters')
    .max(100, 'Collection name cannot exceed 100 characters')
    .regex(/^[\w\s-]+$/, 'Collection name can only contain letters, numbers, spaces, and hyphens')
    .transform(val => val.trim()),
  description: z.string()
    .max(1000, 'Description cannot exceed 1000 characters')
    .regex(/^[\w\s.,!?-]*$/, 'Description contains invalid characters')
    .optional()
    .transform(val => val?.trim()),
  metadata: z.object({
    tags: z.array(z.string().max(30)).max(10, 'Maximum 10 tags allowed'),
    category: z.enum(['wildlife', 'fossil', 'mixed']).optional(),
    visibility: z.enum(['private', 'public', 'shared']).default('private'),
    shared_with: z.array(z.string().uuid()).max(100, 'Cannot share with more than 100 users').optional(),
    last_sync: z.date().optional(),
    stats: z.object({
      total_discoveries: z.number().min(0).optional(),
      unique_species: z.number().min(0).optional(),
      rare_findings: z.number().min(0).optional()
    }).optional()
  }).strict(),
  created_at: z.date(),
  updated_at: z.date(),
  deleted_at: z.date().nullable().optional()
});

/**
 * Enhanced discovery validation schema with precise validation rules
 */
export const DiscoveryValidationSchema = z.object({
  discovery_id: z.string()
    .uuid('Invalid discovery ID format')
    .refine(val => validateUUIDFormat(val), 'Invalid UUID v4 format'),
  collection_id: z.string()
    .uuid('Invalid collection ID format')
    .refine(val => validateUUIDFormat(val), 'Invalid UUID v4 format'),
  species_id: z.string()
    .uuid('Invalid species ID format')
    .refine(val => validateUUIDFormat(val), 'Invalid UUID v4 format'),
  location: LocationValidationSchema,
  confidence: z.number()
    .min(0, 'Confidence score must be between 0 and 1')
    .max(1, 'Confidence score must be between 0 and 1')
    .transform(val => Number(val.toFixed(4))), // Limit to 4 decimal places
  media_urls: z.array(z.string()
    .url('Invalid media URL format')
    .regex(/^https:\/\//, 'Only HTTPS URLs are allowed')
    .regex(/^https:\/\/[^/]+\.(wildlife-safari\.com|amazonaws\.com)\//, 'Invalid media domain'))
    .min(1, 'At least one media URL is required')
    .max(10, 'Maximum of 10 media items allowed'),
  metadata: z.object({
    weather: z.object({
      temperature: z.number().optional(),
      humidity: z.number().min(0).max(100).optional(),
      conditions: z.string().max(50).optional()
    }).optional(),
    habitat: z.string().max(100).optional(),
    notes: z.string().max(1000).optional()
  }).strict()
});

/**
 * Validates UUID format with enhanced version 4 specific checks
 * @param id - UUID string to validate
 * @returns boolean indicating if UUID is valid
 */
export function validateUUID(id: string): boolean {
  if (!id || typeof id !== 'string') return false;
  return validateUUIDFormat(id);
}

/**
 * Validates collection data with enhanced security checks
 * @param data - Collection data to validate
 * @returns Promise resolving to validation result
 */
export async function validateCollection(data: Partial<ICollection>): Promise<boolean> {
  try {
    // Sanitize and validate collection data
    const validatedData = await CollectionValidationSchema.parseAsync({
      ...data,
      created_at: data.created_at || new Date(),
      updated_at: data.updated_at || new Date()
    });

    // Additional security checks
    if (validatedData.metadata?.shared_with?.includes(validatedData.user_id)) {
      throw new Error('Collection cannot be shared with its owner');
    }

    // Validate timestamp sequence
    if (validatedData.updated_at < validatedData.created_at) {
      throw new Error('Updated timestamp cannot be earlier than created timestamp');
    }

    if (validatedData.deleted_at && validatedData.deleted_at < validatedData.created_at) {
      throw new Error('Deleted timestamp cannot be earlier than created timestamp');
    }

    return true;
  } catch (error) {
    console.error('Collection validation failed:', error);
    return false;
  }
}

/**
 * Validates discovery data with enhanced precision checks
 * @param data - Discovery data to validate
 * @returns Promise resolving to validation result
 */
export async function validateDiscovery(data: Partial<IDiscovery>): Promise<boolean> {
  try {
    // Sanitize and validate discovery data
    const validatedData = await DiscoveryValidationSchema.parseAsync({
      ...data,
      created_at: data.created_at || new Date(),
      updated_at: data.updated_at || new Date()
    });

    // Validate timestamp sequence
    if (validatedData.updated_at < validatedData.created_at) {
      throw new Error('Updated timestamp cannot be earlier than created timestamp');
    }

    // Additional coordinate precision checks
    const { latitude, longitude } = validatedData.location;
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
      throw new Error('Invalid coordinate values');
    }

    return true;
  } catch (error) {
    console.error('Discovery validation failed:', error);
    return false;
  }
}