# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Static, framework-free web app simulating monthly personal cashflow (income, expenses, debt, assets) as an animated SVG flow graph. No build step, no backend.

## Commands

```bash
npm test                        # run simulation unit tests (node --test)
python3 -m http.server 4173     # serve app, open http://127.0.0.1:4173
node --test simulation.test.js  # run just this file
```

## Architecture

- `simulation.js` — pure simulation engine, zero DOM dependency. `simulateMonth(state, settings)` takes the current `{month, debt, assets, consumed, last}` state and settings, returns the next state plus a `last` breakdown of every intermediate value (asset return, withdraw/reinvest split, debt interest, minimum payment, cashflow, paydown/deficit, spend/save). This separation (engine vs UI) is intentional and tested — keep all money math here, not in `app.js`.
- `app.js` — DOM/SVG layer. Reads/writes settings to `localStorage` (`cash-flow-animation-settings-v1`), drives Play/Pause/Step/Reset controls, and animates particles along SVG edges per `moveParticles`. Calls `simulateMonth` for both the committed step and a `preview()` (next month without committing).
- `index.html` / `styles.css` — SVG node/edge graph markup and styling.
- `simulation.test.js` — deterministic tests covering returns, debt interest, minimum-payment capping, deficits, debt payoff with same-month remainder, and allocation splits.

## Factorio mod (`factorio/`)

Playable Factorio 2.0 scenario mod: iron plate = $10 cash, copper plate = debt; the player routes money with belts.

```bash
npm run test:factorio      # plain-Lua tests (accounting + smoke test against tests/fake_factorio.lua)
npm run package:factorio   # builds factorio/dist/cashflow_<version>.zip
```

- `factorio/cashflow/script/accounting.lua` is the pure money-math module (the `simulation.js` equivalent). Keep game-API calls out of it.
- Mod code runs on Factorio's Lua 5.2; tests run on local Lua 5.4, so don't use 5.3+ syntax (`//`, `<const>`).
- Factorio isn't installed on the dev machine. In-game testing follows `factorio/TESTING.md` on another machine.

## Domain rules (see readme.md "Implementation contract" for full detail)

- All money is stored as integer cents internally; only converted to currency strings for display.
- Annual rates (debt interest, asset return) are converted to monthly by dividing by 12.
- Monthly processing order is fixed: asset return → withdraw/reinvest split → total income → debt interest → minimum payment (capped at balance) → cashflow → deficit-adds-to-debt or paydown-then-spend/save. Do not reorder this without checking `readme.md`'s contract and updating tests.
- Assets/debt are floored at zero; asset withdrawals never touch principal (v1 has no asset sale).
- Money added to assets in a month starts earning returns only the following month (uses opening balance each month).
