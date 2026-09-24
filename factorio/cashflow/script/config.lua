local M = {}

function M.read()
  local g = settings.global
  return {
    job_income = g["cf-job-income"].value,
    needs = g["cf-needs"].value,
    wants = g["cf-wants"].value,
    starting_debt = g["cf-starting-debt"].value,
    debt_apr = g["cf-debt-apr"].value,
    starting_assets = g["cf-starting-assets"].value,
    asset_return = g["cf-asset-return"].value,
    game_speed = g["cf-game-speed"].value,
  }
end

return M
