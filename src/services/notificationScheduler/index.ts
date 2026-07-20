/**
 * Notification_Scheduler (design.md component 6).
 *
 * Built on top of Notifee to schedule/cancel per-cadence local recap
 * notifications.
 *
 * TODO: Implement Notifee wiring and Storage_Service-backed enabled/disabled
 * persistence (see tasks.md task 18) - this file is a structural stub only.
 */

import { Cadence } from '../../types';

export interface NotificationScheduler {
  scheduleForCadence(cadence: Cadence, windowEnd: Date): Promise<void>;
  cancelForCadence(cadence: Cadence): Promise<void>;
  isEnabled(cadence: Cadence): Promise<boolean>;
  setEnabled(cadence: Cadence, enabled: boolean): Promise<void>;
  rescheduleAll(): Promise<void>; // called on app launch / settings change
}
