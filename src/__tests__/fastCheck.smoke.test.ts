import fc from 'fast-check';

/**
 * TEMPORARY wiring-verification test.
 *
 * This test only proves that `fast-check` is correctly wired up with Jest
 * (task 1.2). It does not validate any product behavior and should be
 * removed/replaced once real property tests (see design.md's Correctness
 * Properties) are added in later tasks.
 */
describe('fast-check smoke test', () => {
  it('addition is commutative for any pair of integers', () => {
    fc.assert(
      fc.property(fc.integer(), fc.integer(), (a, b) => {
        return a + b === b + a;
      }),
      { numRuns: 100 },
    );
  });
});
