/**
 * Sharing_Service (design.md component 7).
 *
 * Captures a card view as a static image and opens the iOS share sheet.
 *
 * TODO: Implement view-shot capture and share-sheet invocation (see
 * tasks.md task 20) - this file is a structural stub only.
 */

// Placeholder for a React ref to the native card view to be captured.
// TODO: Replace with the actual ref type once the share capture library is
// chosen and wired in task 20.
export type CardViewRef = unknown;

export interface SharingService {
  shareCard(cardRef: CardViewRef): Promise<void>;
}
