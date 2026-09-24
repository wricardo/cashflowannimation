export const DEFAULT_SETTINGS = Object.freeze({
  jobIncome: 500000,
  needs: 200000,
  wants: 80000,
  startingDebt: 1800000,
  debtInterestAnnual: 18,
  minimumDebtPayment: 40000,
  startingAssets: 1200000,
  assetReturnAnnual: 7,
  withdrawRate: 30,
  spendRate: 20,
});

export function initialState(settings = DEFAULT_SETTINGS) {
  return {
    month: 0,
    debt: settings.startingDebt,
    assets: settings.startingAssets,
    consumed: 0,
    last: null,
  };
}

const cents = (value) => Math.round(value);
const portion = (amount, percent) => cents(amount * (percent / 100));

export function simulateMonth(state, settings) {
  const openingAssets = state.assets;
  const openingDebt = state.debt;
  const assetReturn = cents(openingAssets * (settings.assetReturnAnnual / 100 / 12));
  const positiveReturn = Math.max(0, assetReturn);
  const withdrawnReturn = portion(positiveReturn, settings.withdrawRate);
  const reinvestedReturn = positiveReturn - withdrawnReturn;
  const totalIncome = settings.jobIncome + withdrawnReturn;

  const debtInterest = cents(openingDebt * (settings.debtInterestAnnual / 100 / 12));
  const debtAfterInterest = openingDebt + debtInterest;
  const minimumPayment = Math.min(debtAfterInterest, settings.minimumDebtPayment);
  const debtAfterMinimum = debtAfterInterest - minimumPayment;
  const cashflow = totalIncome - settings.needs - settings.wants - minimumPayment;

  let debtPaydown = 0;
  let deficit = 0;
  let spend = 0;
  let save = 0;
  let closingDebt = debtAfterMinimum;

  if (cashflow < 0) {
    deficit = -cashflow;
    closingDebt += deficit;
  } else {
    debtPaydown = Math.min(cashflow, closingDebt);
    closingDebt -= debtPaydown;
    const remainingCash = cashflow - debtPaydown;
    if (closingDebt === 0) {
      spend = portion(remainingCash, settings.spendRate);
      save = remainingCash - spend;
    }
  }

  const closingAssets = Math.max(
    0,
    openingAssets + (assetReturn < 0 ? assetReturn : reinvestedReturn) + save,
  );
  const consumedThisMonth = settings.needs + settings.wants + spend;

  const last = {
    openingAssets,
    openingDebt,
    assetReturn,
    withdrawnReturn,
    reinvestedReturn,
    totalIncome,
    debtInterest,
    minimumPayment,
    cashflow,
    debtPaydown,
    deficit,
    spend,
    save,
    consumedThisMonth,
    closingAssets,
    closingDebt,
  };

  return {
    month: state.month + 1,
    debt: closingDebt,
    assets: closingAssets,
    consumed: state.consumed + consumedThisMonth,
    last,
  };
}
