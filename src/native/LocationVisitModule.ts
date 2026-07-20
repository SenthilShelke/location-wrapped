/**
 * Thin JS-side wrapper (interface stubs only) around the native
 * `LocationVisitModule` Swift module described in design.md's
 * "Location_Module" component section.
 *
 * TODO: Implement the actual `NativeModules.LocationVisitModule` bridging
 * and `NativeEventEmitter` wiring in later tasks (see tasks.md task 2.2,
 * 3.2, 4.2).
 */

export type AuthorizationStatus =
  | 'notDetermined'
  | 'restricted'
  | 'denied'
  | 'authorizedWhenInUse'
  | 'authorizedAlways';

export interface RawVisitEvent {
  latitude: number;
  longitude: number;
  horizontalAccuracyMeters: number;
  // CLVisit.arrivalDate, converted to epoch ms. `null` when CLVisit reports
  // NSDate.distantPast (arrival time unknown).
  arrivalTimeMs: number | null;
  // CLVisit.departureDate, converted to epoch ms. `null` when CLVisit reports
  // NSDate.distantFuture (the user has not yet left - this is an
  // arrival-only report).
  departureTimeMs: number | null;
}

export type LocationModuleEvent = 'onVisit' | 'onAuthorizationStatusChange';

export interface LocationVisitModuleNative {
  requestWhenInUseAuthorization(): Promise<AuthorizationStatus>;
  requestAlwaysAuthorization(): Promise<AuthorizationStatus>;
  getAuthorizationStatus(): Promise<AuthorizationStatus>;
  startMonitoringVisits(): Promise<void>;
  stopMonitoringVisits(): Promise<void>;
}
