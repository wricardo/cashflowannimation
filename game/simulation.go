package main

// Cents-based cashflow simulation, ported from ../simulation.js.

type Settings struct {
	JobIncome          int
	Needs              int
	Wants              int
	StartingDebt       int
	DebtInterestAnnual float64
	MinimumDebtPayment int
	StartingAssets     int
	AssetReturnAnnual  float64
	WithdrawRate       float64
	SpendRate          float64
}

var DefaultSettings = Settings{
	JobIncome:          500_000,
	Needs:              200_000,
	Wants:              80_000,
	StartingDebt:       1_800_000,
	DebtInterestAnnual: 18,
	MinimumDebtPayment: 40_000,
	StartingAssets:     1_200_000,
	AssetReturnAnnual:  7,
	WithdrawRate:       30,
	SpendRate:          20,
}

type MonthResult struct {
	OpeningAssets, OpeningDebt                     int
	AssetReturn, WithdrawnReturn, ReinvestedReturn int
	TotalIncome                                    int
	DebtInterest, MinimumPayment                   int
	Cashflow                                       int
	DebtPaydown, Deficit, Spend, Save              int
	ConsumedThisMonth                              int
	ClosingAssets, ClosingDebt                     int
}

type State struct {
	Month    int
	Debt     int
	Assets   int
	Consumed int
	Last     MonthResult
}

func InitialState(s Settings) State {
	return State{Month: 0, Debt: s.StartingDebt, Assets: s.StartingAssets}
}

func round(v float64) int {
	if v >= 0 {
		return int(v + 0.5)
	}
	return -int(-v + 0.5)
}

func portion(amount int, percent float64) int {
	return round(float64(amount) * (percent / 100))
}

func SimulateMonth(state State, s Settings) State {
	openingAssets := state.Assets
	openingDebt := state.Debt

	assetReturn := round(float64(openingAssets) * (s.AssetReturnAnnual / 100 / 12))
	positiveReturn := max(0, assetReturn)
	withdrawnReturn := portion(positiveReturn, s.WithdrawRate)
	reinvestedReturn := positiveReturn - withdrawnReturn
	totalIncome := s.JobIncome + withdrawnReturn

	debtInterest := round(float64(openingDebt) * (s.DebtInterestAnnual / 100 / 12))
	debtAfterInterest := openingDebt + debtInterest
	minimumPayment := min(debtAfterInterest, s.MinimumDebtPayment)
	debtAfterMinimum := debtAfterInterest - minimumPayment
	cashflow := totalIncome - s.Needs - s.Wants - minimumPayment

	debtPaydown, deficit, spend, save := 0, 0, 0, 0
	closingDebt := debtAfterMinimum

	if cashflow < 0 {
		deficit = -cashflow
		closingDebt += deficit
	} else {
		debtPaydown = min(cashflow, closingDebt)
		closingDebt -= debtPaydown
		remainingCash := cashflow - debtPaydown
		if closingDebt == 0 {
			spend = portion(remainingCash, s.SpendRate)
			save = remainingCash - spend
		}
	}

	assetDelta := reinvestedReturn
	if assetReturn < 0 {
		assetDelta = assetReturn
	}
	closingAssets := max(0, openingAssets+assetDelta+save)
	consumedThisMonth := s.Needs + s.Wants + spend

	last := MonthResult{
		OpeningAssets: openingAssets, OpeningDebt: openingDebt,
		AssetReturn: assetReturn, WithdrawnReturn: withdrawnReturn, ReinvestedReturn: reinvestedReturn,
		TotalIncome:  totalIncome,
		DebtInterest: debtInterest, MinimumPayment: minimumPayment,
		Cashflow:    cashflow,
		DebtPaydown: debtPaydown, Deficit: deficit, Spend: spend, Save: save,
		ConsumedThisMonth: consumedThisMonth,
		ClosingAssets:     closingAssets, ClosingDebt: closingDebt,
	}

	return State{
		Month:    state.Month + 1,
		Debt:     closingDebt,
		Assets:   closingAssets,
		Consumed: state.Consumed + consumedThisMonth,
		Last:     last,
	}
}
