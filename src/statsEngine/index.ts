/**
 * Stats_Engine (design.md component 5).
 *
 * Pure function that computes WrappedStats for a given TimeWindow from the
 * full Visit history. No I/O - the caller is responsible for fetching
 * `allVisits` from Storage_Service.
 *
 * TODO: Implement the computation pipeline (see tasks.md task 12) - this
 * file is a structural stub only.
 */

import { TimeWindow, VisitRecord, WrappedStats } from '../types';

export function computeWrappedStats(
  _allVisits: VisitRecord[],
  _timeWindow: TimeWindow,
): WrappedStats {
  throw new Error('computeWrappedStats is not yet implemented (see tasks.md task 12)');
}
