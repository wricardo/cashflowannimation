"""Animated cashflow flow-graph: left-to-right pipeline, Bloons-TD-style
money balloons (colored circles by denomination) instead of $ labels.

Same simulation engine (simulation.py) and same per-edge flow amounts
as app.js's moveParticles(). Node amounts commit once a month's
balloons finish traveling.

Run: python3 animate.py
"""

import colorsys

import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch
from matplotlib.animation import FuncAnimation

from simulation import DEFAULT_SETTINGS, initial_state, simulate_month

GREEN = "#397f56"
RED = "#8a3f3e"
NEUTRAL = "#6b756f"
INK = "#e9efe9"

CATEGORY_COLORS = {
    "asset": ("#234331", GREEN),
    "income": ("#234331", GREEN),
    "expense": ("#482c2b", RED),
    "debt": ("#482c2b", RED),
    "graveyard": ("#482c2b", RED),
    "core": ("#4d4427", "#c9a94a"),
    "decision": ("#273a37", "#78b5aa"),
}

# Balloon denominations (whole dollars), Bloons-TD-inspired colors, radius (pts)
DENOMS = [
    (100000, "rainbow", 15),
    (50000, "#f2f2f2", 13),
    (1000, "#ff8c32", 12),
    (100, "#e33dc0", 10),
    (50, "#e3d13d", 9),
    (10, "#3de35c", 8),
    (5, "#3d7fe3", 7),
    (1, "#e6194b", 6),
]
MAX_BALLOONS_PER_FLOW = 24

# id, col(x), y, w, h, label, category  -- left-to-right pipeline
COLS = [90, 330, 570, 810, 1050, 1290, 1530, 1770]
NODES = [
    ("job-income", COLS[0], 80, 150, 92, "JOB INCOME", "income"),
    ("assets", COLS[0], 380, 150, 92, "ASSETS", "asset"),
    ("needs", COLS[0], 560, 150, 92, "EXPENSE NEEDS", "expense"),
    ("wants", COLS[0], 700, 150, 92, "EXPENSE WANTS", "expense"),
    ("asset-return", COLS[1], 200, 170, 92, "ASSET RETURN", "asset"),
    ("return-split", COLS[2], 200, 170, 92, "RETURN SPLIT", "asset"),
    ("income", COLS[3], 280, 160, 92, "TOTAL INCOME", "income"),
    ("cashflow", COLS[4], 460, 170, 110, "CASHFLOW", "core"),
    ("paydown", COLS[5], 460, 200, 92, "DEBT PAYDOWN\nCHECK", "decision"),
    ("debt", COLS[6], 300, 150, 92, "DEBT", "debt"),
    ("decision", COLS[6], 680, 200, 92, "SPEND OR\nSAVE", "decision"),
    ("graveyard", COLS[7], 460, 175, 92, "SPEND\nGRAVEYARD", "graveyard"),
]

# id -> ("line", p0, p1, color, backedge) | ("cubic", p0, p1, p2, p3, color, backedge)
EDGES = {
    "job-income": ("cubic", (240, 126), (500, 126), (600, 280), (810, 326), NEUTRAL, False),
    "asset-return": ("cubic", (240, 420), (300, 300), (400, 246), (500, 246), GREEN, False),
    "return-split": ("line", (670, 246), (810, 246), GREEN, False),
    "withdraw-income": ("cubic", (980, 246), (1050, 246), (1050, 326), (890, 326), GREEN, False),
    "reinvest-assets": ("cubic", (810, 220), (600, -40), (300, -40), (165, 380), GREEN, True),
    "income-cashflow": ("cubic", (890, 372), (940, 460), (960, 500), (1050, 505), NEUTRAL, False),
    "needs-cashflow": ("cubic", (240, 600), (600, 600), (800, 540), (1050, 515), RED, False),
    "wants-cashflow": ("cubic", (240, 740), (600, 740), (850, 600), (1050, 525), RED, False),
    "debt-cashflow": ("cubic", (1530, 340), (1500, 850), (1200, 850), (1090, 515), RED, True),
    "cashflow-graveyard": ("cubic", (1130, 545), (1300, 620), (1500, 550), (1770, 505), RED, False),
    "cashflow-check": ("line", (1140, 515), (1290, 506), GREEN, False),
    "check-debt": ("cubic", (1440, 490), (1480, 420), (1500, 380), (1530, 346), GREEN, False),
    "check-decision": ("cubic", (1440, 526), (1480, 600), (1500, 650), (1530, 700), GREEN, False),
    "decision-spend": ("cubic", (1680, 690), (1740, 600), (1770, 550), (1770, 506), RED, False),
    "decision-save": ("cubic", (1530, 720), (900, 880), (300, 880), (165, 426), GREEN, True),
}

FRAMES_PER_MONTH = 60
TOTAL_MONTHS = 24


def money(c):
    return f"${c / 100:,.0f}"


def signed_money(c):
    return f"-{money(abs(c))}" if c < 0 else money(c)


def point_at(edge_id, t):
    spec = EDGES[edge_id]
    kind, pts = spec[0], spec[1:-2]
    if kind == "line":
        (x0, y0), (x1, y1) = pts
        return x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = pts
    mt = 1 - t
    x = mt**3 * x0 + 3 * mt**2 * t * x1 + 3 * mt * t**2 * x2 + t**3 * x3
    y = mt**3 * y0 + 3 * mt**2 * t * y1 + 3 * mt * t**2 * y2 + t**3 * y3
    return x, y


def flows_for(last, settings):
    return [
        ("job-income", settings["job_income"]),
        ("asset-return", abs(last["asset_return"])),
        ("return-split", max(0, last["asset_return"])),
        ("withdraw-income", last["withdrawn_return"]),
        ("reinvest-assets", last["reinvested_return"]),
        ("income-cashflow", last["total_income"]),
        ("needs-cashflow", settings["needs"]),
        ("wants-cashflow", settings["wants"]),
        ("debt-cashflow", last["debt_interest"] + last["minimum_payment"]),
        ("cashflow-graveyard", last["consumed_this_month"]),
        ("cashflow-check", max(0, last["cashflow"])),
        ("check-debt", last["debt_paydown"]),
        ("check-decision", last["save"] + last["spend"]),
        ("decision-spend", last["spend"]),
        ("decision-save", last["save"]),
    ]


def denominate(amount_cents):
    """Break a dollar amount into balloons (denom, color, radius), largest first."""
    dollars = abs(amount_cents) // 100
    balloons = []
    for denom, color, radius in DENOMS:
        while dollars >= denom and len(balloons) < MAX_BALLOONS_PER_FLOW:
            balloons.append((denom, color, radius))
            dollars -= denom
    return balloons


def rainbow_rgb(t):
    h = t % 1.0
    return colorsys.hsv_to_rgb(h, 0.85, 0.95)


def main():
    settings = dict(DEFAULT_SETTINGS)
    state = initial_state(settings)

    fig, ax = plt.subplots(figsize=(15, 8.5))
    fig.patch.set_facecolor("#1b2422")
    ax.set_facecolor("#1b2422")
    ax.set_xlim(-40, 1960)
    ax.set_ylim(-100, 920)
    ax.invert_yaxis()
    ax.axis("off")

    for edge_id, spec in EDGES.items():
        color, backedge = spec[-2], spec[-1]
        pts = [point_at(edge_id, t / 30) for t in range(31)]
        xs, ys = zip(*pts)
        ax.plot(xs, ys, color=color, linewidth=4 if not backedge else 3,
                 alpha=0.35 if not backedge else 0.22,
                 linestyle="-" if not backedge else "--",
                 solid_capstyle="round", zorder=1)

    amount_texts = {}
    for node_id, x, y, w, h, label, category in NODES:
        fill, edge = CATEGORY_COLORS[category]
        box = FancyBboxPatch(
            (x, y), w, h,
            boxstyle="round,pad=0,rounding_size=10",
            linewidth=2, edgecolor=edge, facecolor=fill, zorder=2,
        )
        ax.add_patch(box)
        ax.text(x + w / 2, y + h * 0.32, label, ha="center", va="center",
                 color=INK, fontsize=8.5, fontweight="bold", zorder=3)
        amount_texts[node_id] = ax.text(
            x + w / 2, y + h * 0.72, "$0", ha="center", va="center",
            color="#f4efe2", fontsize=9.5, family="monospace", zorder=3,
        )

    month_title = ax.text(960, -70, "Month 0", ha="center", va="top",
                           color=INK, fontsize=16, fontweight="bold")

    # legend
    legend_x, legend_y = 1620, -95
    ax.text(legend_x, legend_y - 10, "BALLOON VALUE", color=INK, fontsize=8,
             fontweight="bold", ha="left")
    for i, (denom, color, radius) in enumerate(DENOMS):
        cx, cy = legend_x + (i % 4) * 75, legend_y + 25 + (i // 4) * 30
        c = rainbow_rgb(0) if color == "rainbow" else color
        ax.scatter([cx], [cy], s=radius * 8, c=[c], edgecolors="#111", linewidths=1, zorder=6)
        ax.text(cx + 12, cy, f"${denom:,}", color=INK, fontsize=6.5, va="center", ha="left")

    def render_static(last):
        amount_texts["assets"].set_text(money(state.assets))
        amount_texts["asset-return"].set_text(signed_money(last["asset_return"]))
        amount_texts["return-split"].set_text(
            f"{money(last['withdrawn_return'])} / {money(last['reinvested_return'])}"
        )
        amount_texts["job-income"].set_text(money(settings["job_income"]))
        amount_texts["income"].set_text(money(last["total_income"]))
        amount_texts["needs"].set_text(money(settings["needs"]))
        amount_texts["wants"].set_text(money(settings["wants"]))
        amount_texts["cashflow"].set_text(signed_money(last["cashflow"]))
        amount_texts["cashflow"].set_color("#ef8a7e" if last["cashflow"] < 0 else "#79d694")
        amount_texts["paydown"].set_text(
            money(last["debt_paydown"]) if last["cashflow"] > 0 else "DEFICIT"
        )
        amount_texts["debt"].set_text(money(state.debt))
        amount_texts["decision"].set_text(f"{money(last['spend'])} / {money(last['save'])}")
        amount_texts["graveyard"].set_text(money(state.consumed))

    render_static(state.last or simulate_month(state, settings).last)

    pending = {"next": None, "flows": []}
    scatters = []

    def clear_scatters():
        for s in scatters:
            s.remove()
        scatters.clear()

    def start_month():
        nonlocal state
        pending["next"] = simulate_month(state, settings)
        clear_scatters()
        pending["flows"] = []
        for edge_id, amount in flows_for(pending["next"].last, settings):
            if amount == 0:
                continue
            balloons = denominate(amount)
            if not balloons:
                continue
            n = len(balloons)
            delays = [min(0.7, i * (0.7 / max(n, 1))) for i in range(n)]
            sizes = [r * 9 for _, _, r in balloons]
            base_colors = [c for _, c, _ in balloons]
            sc = ax.scatter(
                [0] * n, [0] * n, s=sizes, c="#888", edgecolors="#111",
                linewidths=1, zorder=5,
            )
            scatters.append(sc)
            pending["flows"].append(
                {"edge": edge_id, "delays": delays, "colors": base_colors, "scatter": sc}
            )

    def commit_month():
        nonlocal state
        state = pending["next"]
        month_title.set_text(f"Month {state.month}")
        render_static(state.last)
        clear_scatters()

    def update(frame):
        _, local = divmod(frame, FRAMES_PER_MONTH)
        if local == 0:
            start_month()
        t_global = local / (FRAMES_PER_MONTH - 1)
        for flow in pending["flows"]:
            xs, ys, colors = [], [], []
            for i, (delay, color) in enumerate(zip(flow["delays"], flow["colors"])):
                raw = t_global - delay
                t_i = 0.0 if raw < 0 else min(1.0, raw / max(1e-6, 1 - delay))
                x, y = point_at(flow["edge"], t_i)
                bob = 5 * ((frame * 0.35 + i * 1.7) % 6.283)
                y += 4 * ((bob % 3.14) - 1.57) / 1.57
                xs.append(x)
                ys.append(y)
                colors.append(rainbow_rgb(frame * 0.02 + i * 0.1) if color == "rainbow" else color)
            flow["scatter"].set_offsets(list(zip(xs, ys)))
            flow["scatter"].set_facecolor(colors)
        if local == FRAMES_PER_MONTH - 1:
            commit_month()
        return list(amount_texts.values()) + scatters + [month_title]

    anim = FuncAnimation(
        fig, update, frames=TOTAL_MONTHS * FRAMES_PER_MONTH,
        interval=20, blit=False, repeat=True,
    )
    plt.tight_layout()
    return fig, anim


if __name__ == "__main__":
    fig, anim = main()
    plt.show()
