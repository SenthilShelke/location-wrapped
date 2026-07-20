/**
 * Visit_Processor (design.md component 2).
 *
 * Consumes RawVisitEvents from the Location_Module and maintains at most one
 * in-progress Visit at a time.
 *
 * TODO: Implement the pairing algorithm (see tasks.md task 7) - this file is
 * a structural stub only.
 */

import { RawVisitEvent } from '../../native';

export interface VisitProcessor {
  handleRawVisitEvent(event: RawVisitEvent): Promise<void>;
  recoverInProgressVisit(): Promise<void>; // called on app launch
}
