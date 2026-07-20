/**
 * Storage_Service (design.md component 4).
 *
 * Thin repository layer over SQLite (schema in design.md's "Data Models"
 * section: places / visits / geocode_cache / app_settings).
 *
 * TODO: Implement the SQLite-backed repository methods (see tasks.md tasks
 * 2.3 and 6) - this file is a structural stub only.
 */

import { Cadence, Coordinates, PlaceRecord, TimeWindow, VisitRecord } from '../../types';

export interface StorageService {
  saveVisit(visit: VisitRecord): Promise<VisitRecord>;
  getInProgressVisit(): Promise<VisitRecord | null>;
  getVisitsInWindow(window: TimeWindow): Promise<VisitRecord[]>;
  getAllVisits(): Promise<VisitRecord[]>;
  findOrCreatePlace(coords: Coordinates, name: string): Promise<PlaceRecord>;
  deleteAllData(): Promise<void>;
  getNotificationSetting(cadence: Cadence): Promise<boolean>;
  setNotificationSetting(cadence: Cadence, enabled: boolean): Promise<void>;
}
