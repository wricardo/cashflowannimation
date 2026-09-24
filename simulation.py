"""Pure cashflow simulation engine, ported from simulation.js.

All money is stored as integer cents. Annual rates are converted to
monthly by dividing by 12. See readme.md "Implementation contract"
for the full monthly processing order.
"""

from dataclasses import dataclass, field
from typing import Optional


DEFAULT_SETTINGS = {
    "job_income": 500_000,
    "needs": 200_000,
    "wants": 80_000,
    "starting_debt": 1_800_000,
    "debt_interest_annual": 18,
    "minimum_debt_payment": 40_000,
    "starting_assets": 1_200_000,
    "asset_return_annual": 7,
    "withdraw_rate": 30,
    "spend_rate": 20,
}


@dataclass
class State:
    month: int
    debt: int
    assets: int
    consumed: int
    last: Optional[dict] = field(default=None)


def initial_state(settings: dict = DEFAULT_SETTINGS) -> State:
    return State(
        month=0,
        debt=settings["starting_debt"],
        assets=settings["starting_assets"],
        consumed=0,
        last=None,
    )


def _cents(value: float) -> int:
    return round(value)


def _portion(amount: int, percent: float) -> int:
    return _cents(amount * (percent / 100))


def simulate_month(state: State, settings: dict) -> State:
    opening_assets = state.assets
    opening_debt = state.debt

    asset_return = _cents(opening_assets * (settings["asset_return_annual"] / 100 / 12))
    positive_return = max(0, asset_return)
    withdrawn_return = _portion(positive_return, settings["withdraw_rate"])
    reinvested_return = positive_return - withdrawn_return
    total_income = settings["job_income"] + withdrawn_return

    debt_interest = _cents(opening_debt * (settings["debt_interest_annual"] / 100 / 12))
    debt_after_interest = opening_debt + debt_interest
    minimum_payment = min(debt_after_interest, settings["minimum_debt_payment"])
    debt_after_minimum = debt_after_interest - minimum_payment
    cashflow = total_income - settings["needs"] - settings["wants"] - minimum_payment

    debt_paydown = 0
    deficit = 0
    spend = 0
    save = 0
    closing_debt = debt_after_minimum

    if cashflow < 0:
        deficit = -cashflow
        closing_debt += deficit
    else:
        debt_paydown = min(cashflow, closing_debt)
        closing_debt -= debt_paydown
        remaining_cash = cashflow - debt_paydown
        if closing_debt == 0:
            spend = _portion(remaining_cash, settings["spend_rate"])
            save = remaining_cash - spend

    closing_assets = max(
        0,
        opening_assets + (asset_return if asset_return < 0 else reinvested_return) + save,
    )
    consumed_this_month = settings["needs"] + settings["wants"] + spend

    last = {
        "opening_assets": opening_assets,
        "opening_debt": opening_debt,
        "asset_return": asset_return,
        "withdrawn_return": withdrawn_return,
        "reinvested_return": reinvested_return,
        "total_income": total_income,
        "debt_interest": debt_interest,
        "minimum_payment": minimum_payment,
        "cashflow": cashflow,
        "debt_paydown": debt_paydown,
        "deficit": deficit,
        "spend": spend,
        "save": save,
        "consumed_this_month": consumed_this_month,
        "closing_assets": closing_assets,
        "closing_debt": closing_debt,
    }

    return State(
        month=state.month + 1,
        debt=closing_debt,
        assets=closing_assets,
        consumed=state.consumed + consumed_this_month,
        last=last,
    )


def _money(cents: int) -> str:
    return f"${cents / 100:,.2f}"


def run(months: int = 12, settings: dict = DEFAULT_SETTINGS) -> None:
    state = initial_state(settings)
    header = f"{'Mo':>3} {'Income':>12} {'Cashflow':>12} {'Debt':>14} {'Assets':>14} {'Consumed':>14}"
    print(header)
    for _ in range(months):
        state = simulate_month(state, settings)
        last = state.last
        print(
            f"{state.month:>3} "
            f"{_money(last['total_income']):>12} "
            f"{_money(last['cashflow']):>12} "
            f"{_money(state.debt):>14} "
            f"{_money(state.assets):>14} "
            f"{_money(state.consumed):>14}"
        )


if __name__ == "__main__":
    run()
