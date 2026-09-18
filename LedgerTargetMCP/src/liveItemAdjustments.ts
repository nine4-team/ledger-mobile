/** Exact vendor-order allocation. Fractions preserve inclusive edits and exact
 * balance; rounded shares never become subsequent calculation inputs. */
export type AdjustmentInput = Readonly<{ itemId: string; numerator: string | null; denominator: string | null; issue?: string | null }>;
type Fraction = readonly [bigint, bigint];
const gcd = (a: bigint, b: bigint): bigint => {
  a = a < 0n ? -a : a; b = b < 0n ? -b : b;
  while (b) [a, b] = [b, a % b];
  return a || 1n;
};
const fraction = (n: bigint, d: bigint): Fraction => {
  if (d === 0n) throw new Error("zero denominator");
  const divisor = gcd(n, d); n /= divisor; d /= divisor;
  if (d < 0n) { n = -n; d = -d; }
  if (n.toString().replace("-", "").length > 38 || d.toString().length > 38) throw new Error("arithmeticRange");
  return [n, d];
};
const checked = (value: bigint) => {
  if (value.toString().replace("-", "").length > 38) throw new Error("arithmeticRange");
  return value;
};
const multiply = (a: Fraction, b: Fraction): Fraction => {
  const x = gcd(a[0], b[1]), y = gcd(b[0], a[1]);
  return fraction(checked((a[0] / x) * (b[0] / y)), checked((a[1] / y) * (b[1] / x)));
};
const add = (a: Fraction, b: Fraction): Fraction => {
  const common = gcd(a[1], b[1]);
  return fraction(checked(checked(a[0] * (b[1] / common)) + checked(b[0] * (a[1] / common))),
    checked(a[1] * (b[1] / common)));
};
const round = ([n, d]: Fraction): bigint => {
  const sign = n < 0n ? -1n : 1n; n *= sign;
  const result = (n / d + (2n * (n % d) >= d ? 1n : 0n)) * sign;
  if (result < -9223372036854775808n || result > 9223372036854775807n) throw new Error("arithmeticRange");
  return result;
};

export function inclusiveItemPriceInput(requested: bigint, total: bigint, adjustments: bigint): Fraction | null {
  const base = total - adjustments;
  if (base <= 0n || (total === 0n && requested !== 0n)) return null;
  return multiply([requested, 1n], fraction(base, total === 0n ? 1n : total));
}

export function calculateItemAdjustments(total: bigint, adjustments: bigint, inputs: readonly AdjustmentInput[]) {
  if (new Set(inputs.map(input => input.itemId)).size !== inputs.length) throw new Error("duplicate Item");
  const base = total - adjustments;
  const values = inputs.map(input => input.numerator === null || input.denominator === null ? null
    : fraction(BigInt(input.numerator), BigInt(input.denominator)));
  function safe<T>(work: () => T): T | null { try { return work(); } catch { return null; } }
  let difference = values.every(value => value !== null)
    ? safe(() => values.reduce<Fraction>((sum, value) => add(sum, [-value![0], value![1]]), [base, 1n])) : null;
  const unadjusted = values.map(value => value === null ? null : safe(() => round(value)));
  const shares = values.map(value => base <= 0n || value === null ? null : safe(() => multiply(value, fraction(adjustments, base))));
  const finals = values.map(value => base <= 0n || value === null ? null : safe(() => multiply(value, fraction(total, base))));
  const issues = values.map((value, i) => value !== null && unadjusted[i] === null ? "arithmeticRange"
    : base <= 0n ? "nonpositiveBase" : value === null ? inputs[i].issue ?? "unknownInput"
    : shares[i] === null || finals[i] === null || safe(() => round(shares[i]!)) === null || safe(() => round(finals[i]!)) === null
      ? "arithmeticRange" : null);
  if (issues.includes("arithmeticRange")) difference = null;
  let balanced = difference?.[0] === 0n;
  function allocate(values: readonly (Fraction | null)[], target: bigint) {
    const result = values.map(value => value === null ? null : safe(() => round(value)));
    if (!balanced || issues.some(issue => issue !== null) || result.some(value => value === null)) return result;
    const delta = target - result.reduce<bigint>((sum, value) => sum + value!, 0n);
    const residuals = safe(() => values.map((value, index) => add(value!, [-result[index]!, 1n])));
    if (!residuals) return values.map(() => null);
    const order = values.map((_, i) => i).sort((a, b) => {
      const comparison = residuals[a][0] * residuals[b][1] - residuals[b][0] * residuals[a][1];
      if (comparison === 0n) return inputs[a].itemId < inputs[b].itemId ? -1 : 1;
      return (comparison > 0n) === (delta > 0n) ? -1 : 1;
    });
    const count = Number(delta < 0n ? -delta : delta);
    if (count > inputs.length) throw new Error("allocation overflow");
    for (const index of order.slice(0, count)) result[index]! += delta > 0n ? 1n : -1n;
    return result;
  }
  const roundedShares = allocate(shares, adjustments), roundedFinals = allocate(finals, total);
  const items = inputs.map((input, i) => {
    let issue = issues[i], displayedUnadjusted = unadjusted[i];
    if (issue === null) {
      if (roundedShares[i] === null || roundedFinals[i] === null) issue = "arithmeticRange";
      else {
        const reconciled = safe(() => round([roundedFinals[i]! - roundedShares[i]!, 1n]));
        if (reconciled === null) issue = "arithmeticRange"; else displayedUnadjusted = reconciled;
      }
    }
    if (issue === "arithmeticRange") { difference = null; balanced = false; }
    return { itemId: input.itemId, unadjustedMinorUnits: displayedUnadjusted?.toString() ?? null,
      adjustmentsMinorUnits: issue === null ? roundedShares[i]!.toString() : null,
      projectPriceMinorUnits: issue === null ? roundedFinals[i]!.toString() : null, issue };
  });
  return { differenceNumerator: difference?.[0].toString() ?? null,
    differenceDenominator: difference?.[1].toString() ?? null, isBalanced: balanced, isProvisional: !balanced,
    items };
}
