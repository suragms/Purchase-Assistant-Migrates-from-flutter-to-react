// Port of Flutter calc_engine.dart — byte-exact derivation
import type {
  CalcLine,
  CalcRequest,
  CommissionLine,
  CalcTotals,
  PurchaseDraft,
  PurchaseDraftLine,
  PurchaseStrictBreakdown,
} from "../api/types";

function dec(x: number | null | undefined): number {
  return x ?? 0;
}

function clamp(value: number, max: number): number {
  const v = dec(value);
  return v > max ? max : v;
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

function round3(n: number): number {
  return Math.round(n * 1000) / 1000;
}

function round6(n: number): number {
  return Math.round(n * 1000000) / 1000000;
}

function isPositive(n: number): boolean {
  return n > 0;
}

// ------- Line helpers (mirrors TradeCalcLine methods) -------

/** Pre-discount base amount for one line (lineGrossBaseDecimal). */
export function lineGrossBase(li: CalcLine): number {
  const kpu = li.kgPerUnit;
  const pk = li.landingCostPerKg;
  if (kpu != null && pk != null && kpu > 0 && pk > 0) {
    return dec(li.qty) * kpu * pk;
  }
  return dec(li.qty) * dec(li.landingCost);
}

/** Taxable value after line discount (lineTaxableAfterLineDiscDecimal). */
export function lineTaxableAfterLineDisc(li: CalcLine): number {
  const base = lineGrossBase(li);
  const ld = li.discountPercent != null ? clamp(li.discountPercent, 100) : 0;
  return base - base * (ld / 100);
}

/** Pre-tax net amount for GST split (lineNetTaxableDecimal). */
export function lineNetTaxable(li: CalcLine, taxMode = "exclusive"): number {
  const afterDisc = lineTaxableAfterLineDisc(li);
  if (taxMode === "none" || taxMode === "exclusive") return afterDisc;
  const tax = li.taxPercent != null ? clamp(li.taxPercent, 1000) : 0;
  if (!isPositive(tax)) return afterDisc;
  const denom = 1 + tax / 100;
  return round6(afterDisc / denom);
}

/** Per-line amount after line discount and tax (lineMoneyDecimal). */
export function lineMoney(li: CalcLine, taxMode = "exclusive"): number {
  const afterDisc = lineTaxableAfterLineDisc(li);
  if (taxMode === "none") return afterDisc;
  const tax = li.taxPercent != null ? clamp(li.taxPercent, 1000) : 0;
  if (!isPositive(tax)) return afterDisc;
  if (taxMode === "inclusive") return afterDisc;
  return afterDisc + afterDisc * (tax / 100);
}

/** Per-line freight + delivered + billty (lineItemFreightChargesDecimal). */
export function lineItemFreightCharges(li: CalcLine): number {
  const ft = (li.freightType ?? "").trim().toLowerCase();
  const freightDec = ft === "separate" ? dec(li.freightValue) : 0;
  const delivered = dec(li.deliveredRate);
  const billty = dec(li.billtyRate);
  return freightDec + delivered + billty;
}

/** True if any line has item-level charges. */
function hasItemLevelCharges(lines: CalcLine[]): boolean {
  for (const li of lines) {
    if (li.freightValue != null || li.deliveredRate != null || li.billtyRate != null) return true;
  }
  return false;
}

// ------- Physical weight helpers -------

/** Physical mass in kg for one line (linePhysicalWeightKg). */
export function linePhysicalWeightKg(fields: {
  unit: string;
  qty: number;
  kgPerUnit?: number | null;
  boxMode?: string | null;
  itemsPerBox?: number | null;
  weightPerItem?: number | null;
  kgPerBox?: number | null;
  weightPerTin?: number | null;
}): number {
  const { unit, qty } = fields;
  if (qty <= 0) return 0;
  const rawU = unit.trim().toLowerCase();
  const u = rawU === "sack" ? "bag" : rawU;
  if (u === "kg") return qty;
  if (u === "bag") {
    const kpu = fields.kgPerUnit;
    if (kpu == null || kpu <= 0) return 0;
    return qty * kpu;
  }
  if (u === "box" || u === "tin") return 0;
  return 0;
}

/** Line weight kg driven by UnitType (classifierLineWeightKg). */
export function classifierLineWeightKg(fields: {
  type: "weightBag" | "singlePack" | "multiPackBox";
  qty: number;
  kgPerUnit?: number | null;
  kgFromName?: number | null;
  itemsPerBox?: number | null;
  weightPerItem?: number | null;
}): number {
  const { type, qty } = fields;
  if (qty <= 0) return 0;
  switch (type) {
    case "weightBag": {
      const k = fields.kgPerUnit;
      if (k == null || k <= 0) return 0;
      return qty * k;
    }
    case "singlePack": {
      if (fields.kgFromName != null && fields.kgFromName > 0) return qty * fields.kgFromName;
      return qty;
    }
    case "multiPackBox": {
      const ipb = fields.itemsPerBox;
      if (ipb == null || ipb <= 0) return 0;
      if (fields.weightPerItem != null && fields.weightPerItem > 0) return qty * ipb * fields.weightPerItem;
      return 0;
    }
  }
}

// ------- Commission helpers -------

/** Broker commission rupees (headerCommissionAddOnDecimal). */
export function headerCommissionAddOn(fields: {
  commissionMode: string;
  afterHeader: number;
  commissionPercent: number | null;
  commissionMoney: number | null;
  basisLines: CommissionLine[];
}): number {
  const mode = fields.commissionMode.trim().toLowerCase();
  if (mode === "" || mode === "percent") {
    const c = fields.commissionPercent != null ? clamp(fields.commissionPercent, 100) : 0;
    if (!isPositive(c)) return 0;
    return round2(fields.afterHeader * (c / 100));
  }
  const rate = fields.commissionMoney ?? 0;
  if (!isPositive(rate)) return 0;
  switch (mode) {
    case "flat_invoice":
      return round2(rate);
    case "flat_kg": {
      let kg = 0;
      for (const l of fields.basisLines) {
        const w = ledgerLineWeightKg({
          itemName: l.itemName,
          unit: l.unit,
          qty: l.qty,
          catalogDefaultUnit: l.catalogDefaultUnit,
          catalogDefaultKgPerBag: l.catalogDefaultKgPerBag,
          kgPerUnit: l.kgPerUnit,
          boxMode: l.boxMode,
          itemsPerBox: l.itemsPerBox,
          weightPerItem: l.weightPerItem,
          kgPerBox: l.kgPerBox,
          weightPerTin: l.weightPerTin,
        });
        kg += w;
      }
      if (!isPositive(kg)) return 0;
      return round2(rate * kg);
    }
    case "flat_bag": {
      let bags = 0;
      for (const l of fields.basisLines) {
        const u = l.unit.trim().toLowerCase();
        if (u === "bag" || u === "sack") bags += l.qty;
      }
      if (!isPositive(bags)) return 0;
      return round2(rate * bags);
    }
    case "flat_box": {
      let boxes = 0;
      for (const l of fields.basisLines) {
        const u = l.unit.trim().toLowerCase();
        if (u === "box") boxes += l.qty;
      }
      if (!isPositive(boxes)) return 0;
      return round2(rate * boxes);
    }
    case "flat_tin": {
      let tins = 0;
      for (const l of fields.basisLines) {
        const u = l.unit.trim().toLowerCase();
        if (u === "tin") tins += l.qty;
      }
      if (!isPositive(tins)) return 0;
      return round2(rate * tins);
    }
    default:
      return 0;
  }
}

// ------- Helper for kg in ledger / commission -------

/** Kg for a saved trade line (ledgerTradeLineWeightKg). */
export function ledgerLineWeightKg(fields: {
  itemName: string;
  unit: string;
  qty: number;
  catalogDefaultUnit?: string | null;
  catalogDefaultKgPerBag?: number | null;
  kgPerUnit?: number | null;
  boxMode?: string | null;
  itemsPerBox?: number | null;
  weightPerItem?: number | null;
  kgPerBox?: number | null;
  weightPerTin?: number | null;
}): number {
  const { unit, qty } = fields;
  if (qty <= 0) return 0;
  const ul = unit.trim().toLowerCase();
  if (ul === "box" || ul === "tin") return 0;
  // Simple classifier: bag-based heuristic
  const isBag = ul === "bag" || ul === "sack";
  const type: "weightBag" | "singlePack" | "multiPackBox" = isBag
    ? "weightBag"
    : ul === "box"
      ? "multiPackBox"
      : "singlePack";
  let kgName: number | null = null;
  if (type === "singlePack" && fields.catalogDefaultKgPerBag != null && fields.catalogDefaultKgPerBag > 0 && isBag) {
    kgName = fields.catalogDefaultKgPerBag;
  }
  let kg = classifierLineWeightKg({
    type,
    qty,
    kgPerUnit: fields.kgPerUnit,
    kgFromName: kgName,
    itemsPerBox: fields.itemsPerBox,
    weightPerItem: fields.weightPerItem,
  });
  if (fields.kgPerUnit != null && fields.kgPerUnit > 1e-9 && (ul === "bag" || ul === "box" || ul === "tin") && Math.abs(kg - qty) < 1e-6) {
    kg = 0;
  }
  if (kg <= 0) {
    kg = linePhysicalWeightKg({
      unit,
      qty,
      kgPerUnit: fields.kgPerUnit,
      boxMode: fields.boxMode,
      itemsPerBox: fields.itemsPerBox,
      weightPerItem: fields.weightPerItem,
      kgPerBox: fields.kgPerBox,
      weightPerTin: fields.weightPerTin,
    });
  }
  return kg;
}

// ------- Main totals computation -------

/**
 * computeTradeTotals — matches `computeTradeTotals` in calc_engine.dart.
 */
export function computeTradeTotals(req: CalcRequest): CalcTotals {
  let qtySum = 0;
  let amtSum = 0;
  const hasLineCharges = hasItemLevelCharges(req.lines);
  for (const li of req.lines) {
    qtySum += dec(li.qty);
    amtSum += lineMoney(li, req.lineTaxMode) + lineItemFreightCharges(li);
  }

  const headerDisc = req.headerDiscountPercent != null ? clamp(req.headerDiscountPercent, 100) : 0;
  let afterHeader = amtSum;
  if (isPositive(headerDisc)) {
    afterHeader = amtSum - amtSum * (headerDisc / 100);
  }
  amtSum = afterHeader;

  let freight = dec(req.freightAmount);
  if (req.freightType === "included") freight = 0;
  if (!hasLineCharges) amtSum += freight;

  amtSum += headerCommissionAddOn({
    commissionMode: req.commissionMode,
    afterHeader,
    commissionPercent: req.commissionPercent,
    commissionMoney: req.commissionMoney,
    basisLines: req.commissionBasisLines,
  });

  if (!hasLineCharges) {
    const billty = dec(req.billtyRate);
    const delivered = dec(req.deliveredRate);
    amtSum += billty + delivered;
  }

  return {
    qtySum: round3(qtySum),
    amountSum: round2(amtSum),
  };
}

// ------- Draft ↔ Calc mapping helpers -------

function lineToCalc(l: PurchaseDraftLine): CalcLine {
  return {
    qty: l.qty,
    landingCost: l.landingCost,
    kgPerUnit: l.kgPerUnit,
    landingCostPerKg: l.landingCostPerKg,
    taxPercent: l.taxPercent,
    discountPercent: l.lineDiscountPercent,
    freightType: l.freightType,
    freightValue: l.freightValue,
    deliveredRate: l.deliveredRate,
    billtyRate: l.billtyRate,
  };
}

function lineToCommissionBasis(l: PurchaseDraftLine): CommissionLine {
  return {
    itemName: l.itemName,
    unit: l.unit,
    qty: l.qty,
    kgPerUnit: l.kgPerUnit,
    catalogDefaultUnit: null,
    catalogDefaultKgPerBag: null,
    boxMode: l.boxMode,
    itemsPerBox: l.itemsPerBox,
    weightPerItem: l.weightPerItem,
    kgPerBox: l.kgPerBox,
    weightPerTin: l.weightPerTin,
  };
}

export function draftToCalcRequest(d: PurchaseDraft): CalcRequest {
  return {
    headerDiscountPercent: d.headerDiscountPercent,
    commissionPercent: d.commissionPercent,
    commissionMode: d.commissionMode,
    commissionMoney: d.commissionMoney,
    commissionBasisLines: d.lines.map(lineToCommissionBasis),
    freightAmount: d.freightAmount,
    freightType: d.freightType,
    billtyRate: d.billtyRate,
    deliveredRate: d.deliveredRate,
    lines: d.lines.map(lineToCalc),
    lineTaxMode: "exclusive",
  };
}

export function computePurchaseTotals(d: PurchaseDraft): CalcTotals {
  return computeTradeTotals(draftToCalcRequest(d));
}

// ------- Strict breakdown (mirrors purchase_draft_provider.dart strictFooterBreakdown) -------

function wizLineGross(li: CalcLine): number {
  return lineGrossBase(li);
}

function wizLineAfterLineDisc(li: CalcLine): number {
  const base = wizLineGross(li);
  const ld = li.discountPercent != null ? clamp(li.discountPercent, 100) : 0;
  return base * (1 - ld / 100);
}

function wizLineTaxAmount(li: CalcLine): number {
  const ad = wizLineAfterLineDisc(li);
  const tax = li.taxPercent != null ? clamp(li.taxPercent, 1000) : 0;
  return ad * (tax / 100);
}

export function strictFooterBreakdown(d: PurchaseDraft): PurchaseStrictBreakdown {
  let subtotalGross = 0;
  let lineDiscountTotal = 0;
  let taxTotal = 0;
  let linesTotal = 0;
  for (const line of d.lines) {
    const li = lineToCalc(line);
    const g = wizLineGross(li);
    const ad = wizLineAfterLineDisc(li);
    subtotalGross += g;
    lineDiscountTotal += g - ad;
    taxTotal += wizLineTaxAmount(li);
    linesTotal += lineMoney(li) + lineItemFreightCharges(li);
  }
  const headerDisc = d.headerDiscountPercent ?? 0;
  const hd = headerDisc > 100 ? 100 : headerDisc;
  const afterHeader = linesTotal * (1 - hd / 100);
  const headerDiscountAmt = linesTotal - afterHeader;
  const discountTotal = lineDiscountTotal + headerDiscountAmt;
  let freight = d.freightAmount ?? 0;
  if (d.freightType === "included") freight = 0;
  const commission = headerCommissionAddOn({
    commissionMode: d.commissionMode,
    afterHeader,
    commissionPercent: d.commissionPercent,
    commissionMoney: d.commissionMoney,
    basisLines: d.lines.map(lineToCommissionBasis),
  });
  const totals = computePurchaseTotals(d);
  return {
    subtotalGross: round2(subtotalGross),
    taxTotal: round2(taxTotal),
    discountTotal: round2(discountTotal),
    freight: round2(freight),
    commission: round2(commission),
    grand: totals.amountSum,
  };
}
