-- Top-left tile of each station. Every station flows east.
return {
  surface = "cashflow",
  spawn = { x = -30, y = 0 },
  stations = {
    { key = "paycheck", kind = "source", x = -44, y = -10 },
    { key = "needs", kind = "drain", x = -18, y = -10 },
    { key = "wants", kind = "drain", x = 6, y = -10 },
    { key = "debt", kind = "drain", x = -18, y = 12, landmark = "cf-ledger" },
    { key = "vault", kind = "vault", x = 6, y = 12 },
  },
}
