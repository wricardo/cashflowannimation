import test from "node:test";
import assert from "node:assert/strict";
import { DEFAULT_SETTINGS, initialState, simulateMonth } from "./simulation.js";

const settings = (overrides = {}) => ({ ...DEFAULT_SETTINGS, ...overrides });

test("a positive return is split between withdrawal and reinvestment", () => {
  const result = simulateMonth(initialState(settings({ startingAssets: 120000, startingDebt: 0 })), settings({ startingAssets: 120000, startingDebt: 0, assetReturnAnnual: 12, withdrawRate: 25, jobIncome: 0, needs: 0, wants: 0, minimumDebtPayment: 0, spendRate: 100 }));
  assert.equal(result.last.assetReturn, 1200);
  assert.equal(result.last.withdrawnReturn, 300);
  assert.equal(result.last.reinvestedReturn, 900);
  assert.equal(result.assets, 120900);
});

test("minimum payment is capped at the debt balance after interest", () => {
  const config = settings({ startingDebt: 10000, debtInterestAnnual: 12, minimumDebtPayment: 20000, jobIncome: 0, needs: 0, wants: 0, startingAssets: 0 });
  const result = simulateMonth(initialState(config), config);
  assert.equal(result.last.debtInterest, 100);
  assert.equal(result.last.minimumPayment, 10100);
  assert.equal(result.debt, 10100);
});

test("a deficit is added to debt after interest and the minimum payment", () => {
  const config = settings({ startingDebt: 100000, debtInterestAnnual: 12, minimumDebtPayment: 10000, jobIncome: 0, needs: 20000, wants: 0, startingAssets: 0 });
  const result = simulateMonth(initialState(config), config);
  assert.equal(result.last.cashflow, -30000);
  assert.equal(result.last.deficit, 30000);
  assert.equal(result.debt, 121000);
});

test("a same-month debt payoff routes remaining surplus through spend and save", () => {
  const config = settings({ startingDebt: 10000, debtInterestAnnual: 0, minimumDebtPayment: 5000, jobIncome: 30000, needs: 0, wants: 0, startingAssets: 0, spendRate: 20 });
  const result = simulateMonth(initialState(config), config);
  assert.equal(result.last.debtPaydown, 5000);
  assert.equal(result.debt, 0);
  assert.equal(result.last.spend, 4000);
  assert.equal(result.last.save, 16000);
  assert.equal(result.assets, 16000);
});

test("a negative asset return reduces assets without creating withdrawal income", () => {
  const config = settings({ startingAssets: 120000, assetReturnAnnual: -12, withdrawRate: 30, startingDebt: 0, minimumDebtPayment: 0, jobIncome: 0, needs: 0, wants: 0 });
  const result = simulateMonth(initialState(config), config);
  assert.equal(result.last.assetReturn, -1200);
  assert.equal(result.last.withdrawnReturn, 0);
  assert.equal(result.assets, 118800);
});
