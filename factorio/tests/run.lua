local here = (arg and arg[0] or ""):match("(.*/)") or "./"
package.path = here .. "../cashflow/?.lua;" .. here .. "?.lua;" .. package.path

local files = { "accounting_test", "smoke_test" }
local passed, failed = 0, 0

for _, file in ipairs(files) do
  local tests = require(file)
  local names = {}
  for name in pairs(tests) do
    names[#names + 1] = name
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local ok, err = pcall(tests[name])
    if ok then
      passed = passed + 1
    else
      failed = failed + 1
      print("FAIL " .. file .. " :: " .. name .. "\n  " .. tostring(err))
    end
  end
end

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
