/**
 * Geocoding_Service (design.md component 3).
 *
 * Resolves coordinates to human-readable place names, backed by CLGeocoder
 * with a proximity cache.
 *
 * TODO: Implement cache lookup/population, throttling, and fallback naming
 * (see tasks.md task 9) - this file is a structural stub only.
 */

import { Coordinates } from '../../types';

export interface GeocodingService {
  resolvePlaceName(coords: Coordinates): Promise<string>;
}
