/**
 * Shared TypeScript data models for Location Wrapped.
 *
 * These types are transcribed verbatim from design.md's "Data Models" section
 * and are intended to be imported by every other module (native wrapper,
 * services, stats engine, screens) rather than redefined locally.
 */

export interface Coordinates {
  latitude: number;
  longitude: number;
}

export interface PlaceRecord {
  id: string;
  latitude: number;
  longitude: number;
  name: string;
  createdAt: number; // epoch ms
}

export interface VisitRecord {
  id: string;
  placeId: string;
  latitude: number;
  longitude: number;
  arrivalTimeMs: number;
  departureTimeMs: number | null; // null = in progress
  createdAt: number;
  updatedAt: number;
}

export type Cadence = 'daily' | 'weekly' | 'monthly' | 'yearly';

export interface TimeWindow {
  cadence: Cadence;
  startMs: number; // inclusive
  endMs: number; // exclusive
}

export interface PlaceStat {
  placeId: string;
  placeName: string;
  totalTimeMs: number;
  percentageOfTrackedTime: number; // 0-100
}

export interface WrappedStats {
  timeWindow: TimeWindow;
  topPlaces: PlaceStat[];
  distinctPlaceCount: number;
  longestStreakDays: { placeId: string; placeName: string; days: number } | null;
  newPlacesExplored: PlaceStat[];
  superlatives: SuperlativeLabel[];
}

export interface SuperlativeLabel {
  label: string; // e.g. "Night Owl", "Homebody", "Explorer"
  description: string; // short human-readable rationale
}
