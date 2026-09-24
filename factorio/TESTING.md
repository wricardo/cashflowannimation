# Cashflow Factory — in-game test checklist

Target: Factorio 2.0.x (tested against 2.0.77). Base game only; Space Age can be on or off.

## Install

1. On the dev machine: `npm run package:factorio` → `factorio/dist/cashflow_0.1.0.zip`.
2. Copy the zip (don't unzip) into the mods folder:
   - Windows: `%APPDATA%\Factorio\mods\`
   - macOS: `~/Library/Application Support/factorio/mods/`
   - Linux: `~/.factorio/mods/`
3. Start Factorio → Mods → make sure **Cashflow Factory** is enabled → restart if asked.

If the game refuses to load, the error names the file and line. Send that text back.

## Play the scenario

Main menu → **Play → Scenarios → Cashflow Factory** (listed under the `cashflow` mod).

| # | Do | Expect |
|---|---|---|
| 1 | Start the scenario | Dark lab floor. Five stations with floating labels: PAYCHECK, NEEDS, WANTS, DEBT, VAULT. Gray `IN >` / `OUT >` markers. Panel on the left says Month 0 PAUSED. Inventory has 400 belts, 50 undergrounds, 50 splitters, 1 Cashflow meter. |
| 2 | Try to mine or rotate a station belt or splitter | Not possible. |
| 3 | Press **Start** without building anything, wait 1 minute | Month 1. Debt jumps by $2,800 unpaid expenses plus $270 interest (to $21,070). Chat is quiet; `factorio-current.log` has a `[cashflow] month=1` line. PAYCHECK idle cash climbs because its belt is blocked. |
| 4 | Belt PAYCHECK `OUT >` into NEEDS `IN >` | NEEDS label climbs to $2,000 / $2,000. After that, plates come out of NEEDS `OUT >`. |
| 5 | Chain NEEDS `OUT >` → WANTS `IN >` → WANTS `OUT >` → DEBT `IN >` | WANTS fills to $800. The rest goes into DEBT. The DEBT label drops by $10 per plate. Open the debt ledger chest: copper count = debt / 10. |
| 6 | Leave the DEBT `OUT >` unconnected | The pass-through stub fills up and stays full. That's fine: surplus beyond the debt payoff has nowhere to go. |
| 7 | Place the **Cashflow meter** belt somewhere on a belt line | A METER label appears and counts dollars passing this month. |
| 8 | Belt something into VAULT `IN >` | VAULT label goes up by $10 per plate. The next month, return plates come out of VAULT `OUT >` ($70 at $12,000). |
| 9 | Loop VAULT `OUT >` back into VAULT `IN >` | Reinvesting: the vault grows by its own return every month. |
| 10 | Pick up plates from a belt by hand (F) | They disappear from your inventory with the message "Cash only moves on belts". |
| 11 | Settings → Mod settings → Map → Game speed = 10 | A month now lasts about 6 seconds. |
| 12 | To get to a win quickly: new game with Starting debt 0, Starting assets 480000, then feed Needs and Wants | After the first month: "Financial independence!" and a **Quit job** button. Pressing it stops the paycheck. |

## What to send back when something is off

- The step number and what you saw.
- `factorio-current.log` (next to the mods folder). Each month writes one line:
  `[cashflow] month=… debt=… assets=… paycheck=… needs=x/y wants=x/y deficit=… interest=… return=… carry=… paid=… deposit=… idle=…` (money values in cents).

## Known uncertainties, verify first

- The splitter sends plates to the drain side first, and sends everything to the pass-through when the drain stub is full (step 4).
- Station belts join up (splitter input, drain and pass-through stubs line up). If a stub looks disconnected, send a screenshot.
- The meter counts (step 7). It uses `LuaTransportLine.get_detailed_contents`; if the label stays at $0 while plates pass, that API behaves differently than expected.
- Hand pickup is caught (step 10).
