package main

import (
	"encoding/json"
	"fmt"
	"image/color"
	"log"
	"math"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"unicode"

	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/inpututil"
	etext "github.com/hajimehoshi/ebiten/v2/text/v2"
	"github.com/hajimehoshi/ebiten/v2/vector"
	"golang.org/x/image/font/basicfont"
)

const (
	screenW = 1500
	screenH = 800

	defaultAnimationFrames = 90
	panelX                 = 1110
	panelW                 = 360
)

var face = etext.NewGoXFace(basicfont.Face7x13)

// ---------- palette ----------

var (
	bgColor         = color.RGBA{0x14, 0x1a, 0x18, 0xff}
	inkColor        = color.RGBA{0xe9, 0xef, 0xe9, 0xff}
	greenColor      = color.RGBA{0x39, 0x7f, 0x56, 0xff}
	redColor        = color.RGBA{0x8a, 0x3f, 0x3e, 0xff}
	neutralColor    = color.RGBA{0x6b, 0x75, 0x6f, 0xff}
	goldColor       = color.RGBA{0xc9, 0xa9, 0x4a, 0xff}
	panelColor      = color.RGBA{0x1c, 0x24, 0x21, 0xee}
	buttonColor     = color.RGBA{0x2d, 0x39, 0x35, 0xff}
	buttonMuteColor = color.RGBA{0x24, 0x2a, 0x28, 0xff}
	accentColor     = color.RGBA{0x63, 0xc7, 0x7b, 0xff}
	editFillColor   = color.RGBA{0x1d, 0x29, 0x1f, 0xff}
	guideColor      = color.RGBA{0x78, 0xb5, 0xaa, 0x90}
)

type category int

const (
	catAsset category = iota
	catIncome
	catExpense
	catDebt
	catCore
	catDecision
	catGraveyard
)

var categoryFill = map[category]color.RGBA{
	catAsset:     {0x23, 0x43, 0x31, 0xff},
	catIncome:    {0x23, 0x43, 0x31, 0xff},
	catExpense:   {0x48, 0x2c, 0x2b, 0xff},
	catDebt:      {0x48, 0x2c, 0x2b, 0xff},
	catGraveyard: {0x48, 0x2c, 0x2b, 0xff},
	catCore:      {0x4d, 0x44, 0x27, 0xff},
	catDecision:  {0x27, 0x3a, 0x37, 0xff},
}

var categoryEdge = map[category]color.RGBA{
	catAsset:     greenColor,
	catIncome:    greenColor,
	catExpense:   redColor,
	catDebt:      redColor,
	catGraveyard: redColor,
	catCore:      goldColor,
	catDecision:  {0x78, 0xb5, 0xaa, 0xff},
}

// ---------- radial "money wheel" layout ----------

type node struct {
	id      string
	x, y, r float32
	label   string
	cat     category
}

var defaultNodes = map[string]node{
	"cashflow":     {"cashflow", 650, 398, 62, "CASHFLOW", catCore},
	"income":       {"income", 595, 198, 50, "TOTAL\nINCOME", catIncome},
	"needs":        {"needs", 430, 392, 48, "NEEDS", catExpense},
	"wants":        {"wants", 392, 540, 48, "WANTS", catExpense},
	"debt":         {"debt", 960, 338, 48, "DEBT", catDebt},
	"job-income":   {"job-income", 650, 62, 42, "JOB\nINCOME", catIncome},
	"assets":       {"assets", 120, 680, 46, "ASSETS", catAsset},
	"asset-return": {"asset-return", 245, 478, 40, "ASSET\nRETURN", catAsset},
	"return-split": {"return-split", 430, 145, 42, "RETURN\nSPLIT", catAsset},
	"decision":     {"decision", 465, 726, 50, "SPEND OR\nSAVE", catDecision},
	"graveyard":    {"graveyard", 965, 708, 50, "GRAVEYARD", catGraveyard},
}

var nodeOrder = []string{
	"job-income", "assets", "asset-return", "return-split", "income",
	"needs", "wants", "debt", "cashflow", "decision", "graveyard",
}

func cloneNodes() map[string]*node {
	out := make(map[string]*node, len(defaultNodes))
	for id, n := range defaultNodes {
		copy := n
		out[id] = &copy
	}
	return out
}

// ---------- edges ----------

type edgeKind int

const (
	kindLine edgeKind = iota
	kindCubic
)

type edge struct {
	kind           edgeKind
	p0, p1, p2, p3 [2]float32
	color          color.RGBA
	backedge       bool
}

type edgeSpec struct {
	kind               edgeKind
	sourceID, targetID string
	p0, p1, p2, p3     [2]float32
	color              color.RGBA
	backedge           bool
}

func pt(x, y float32) [2]float32 { return [2]float32{x, y} }

var edgeSpecs = map[string]edgeSpec{
	"job-income":         {kindLine, "job-income", "income", pt(640, 90), pt(640, 134), [2]float32{}, [2]float32{}, neutralColor, false},
	"asset-return":       {kindCubic, "assets", "asset-return", pt(146, 190), pt(190, 150), pt(220, 165), pt(224, 160), greenColor, false},
	"return-split":       {kindCubic, "asset-return", "return-split", pt(300, 148), pt(360, 130), pt(380, 128), pt(392, 130), greenColor, false},
	"withdraw-income":    {kindCubic, "return-split", "income", pt(468, 140), pt(560, 150), pt(600, 165), pt(612, 180), greenColor, false},
	"reinvest-assets":    {kindCubic, "return-split", "assets", pt(410, 110), pt(300, 40), pt(180, 60), pt(140, 165), greenColor, true},
	"income-cashflow":    {kindLine, "income", "cashflow", pt(640, 234), pt(640, 338), [2]float32{}, [2]float32{}, neutralColor, false},
	"needs-cashflow":     {kindCubic, "needs", "cashflow", pt(414, 366), pt(500, 400), pt(550, 380), pt(580, 380), redColor, false},
	"wants-cashflow":     {kindCubic, "wants", "cashflow", pt(384, 512), pt(480, 480), pt(540, 440), pt(582, 420), redColor, false},
	"debt-cashflow":      {kindCubic, "debt", "cashflow", pt(882, 356), pt(800, 380), pt(740, 380), pt(700, 380), redColor, true},
	"cashflow-graveyard": {kindCubic, "cashflow", "graveyard", pt(690, 440), pt(800, 560), pt(900, 640), pt(952, 668), redColor, false},
	"cashflow-debt":      {kindCubic, "cashflow", "debt", pt(684, 430), pt(770, 500), pt(860, 430), pt(878, 372), greenColor, false},
	"cashflow-decision":  {kindCubic, "cashflow", "decision", pt(618, 458), pt(600, 540), pt(590, 610), pt(584, 626), greenColor, false},
	"decision-spend":     {kindCubic, "decision", "graveyard", pt(626, 700), pt(760, 790), pt(900, 760), pt(954, 700), redColor, false},
	"decision-save":      {kindCubic, "decision", "assets", pt(530, 650), pt(320, 560), pt(120, 420), pt(108, 234), greenColor, true},
}

func shifted(p [2]float32, dx, dy float32) [2]float32 {
	return [2]float32{p[0] + dx, p[1] + dy}
}

func edgeFor(spec edgeSpec, nodes map[string]*node) edge {
	srcDefault := defaultNodes[spec.sourceID]
	tgtDefault := defaultNodes[spec.targetID]
	src := nodes[spec.sourceID]
	tgt := nodes[spec.targetID]
	sdx, sdy := src.x-srcDefault.x, src.y-srcDefault.y
	tdx, tdy := tgt.x-tgtDefault.x, tgt.y-tgtDefault.y

	e := edge{kind: spec.kind, color: spec.color, backedge: spec.backedge}
	if spec.kind == kindLine {
		e.p0 = shifted(spec.p0, sdx, sdy)
		e.p1 = shifted(spec.p1, tdx, tdy)
		return e
	}
	e.p0 = shifted(spec.p0, sdx, sdy)
	e.p1 = shifted(spec.p1, sdx, sdy)
	e.p2 = shifted(spec.p2, tdx, tdy)
	e.p3 = shifted(spec.p3, tdx, tdy)
	return e
}

func bezierPoint(e edge, t float32) (float32, float32) {
	if e.kind == kindLine {
		return e.p0[0] + (e.p1[0]-e.p0[0])*t, e.p0[1] + (e.p1[1]-e.p0[1])*t
	}
	mt := 1 - t
	x := mt*mt*mt*e.p0[0] + 3*mt*mt*t*e.p1[0] + 3*mt*t*t*e.p2[0] + t*t*t*e.p3[0]
	y := mt*mt*mt*e.p0[1] + 3*mt*mt*t*e.p1[1] + 3*mt*t*t*e.p2[1] + t*t*t*e.p3[1]
	return x, y
}

// ---------- flow circle styling ----------

func clamp(v, lo, hi float64) float64 {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

func clampFloat32(v, lo, hi float32) float32 {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

func mixColor(a, b color.RGBA, t float64) color.RGBA {
	t = clamp(t, 0, 1)
	mix := func(x, y byte) byte {
		return byte(math.Round(float64(x) + (float64(y)-float64(x))*t))
	}
	return color.RGBA{mix(a.R, b.R), mix(a.G, b.G), mix(a.B, b.B), 0xff}
}

func flowCircleColor(edgeID string, amountCents int) color.RGBA {
	dollars := math.Abs(float64(amountCents)) / 100
	light := accentColor
	dark := color.RGBA{0x0d, 0x3b, 0x1d, 0xff}
	if edgeSpecs[edgeID].color == redColor {
		light = color.RGBA{0xd9, 0x6c, 0x68, 0xff}
		dark = color.RGBA{0x4e, 0x16, 0x15, 0xff}
	}
	if dollars <= 0 {
		return light
	}
	minDollar := 0.01
	maxDollar := 100000.0
	normalized := (math.Log10(math.Max(dollars, minDollar)) - math.Log10(minDollar)) /
		(math.Log10(maxDollar) - math.Log10(minDollar))
	return mixColor(light, dark, normalized)
}

func flowCircleRadius(amountCents int) float32 {
	dollars := math.Abs(float64(amountCents)) / 100
	if dollars <= 0 {
		return 22
	}
	steps := clamp((math.Log10(math.Max(dollars, 0.01))-math.Log10(0.01))/7, 0, 1)
	return float32(22 + steps*12)
}

func compactMoney(cents int) string {
	neg := cents < 0
	value := math.Abs(float64(cents)) / 100
	var s string
	switch {
	case value >= 1_000_000:
		s = fmt.Sprintf("$%.1fm", value/1_000_000)
	case value >= 1_000:
		s = fmt.Sprintf("$%.1fk", value/1_000)
	case value >= 100:
		s = fmt.Sprintf("$%.0f", value)
	case value >= 10:
		s = fmt.Sprintf("$%.1f", value)
	default:
		s = fmt.Sprintf("$%.2f", value)
	}
	s = strings.ReplaceAll(s, ".0k", "k")
	s = strings.ReplaceAll(s, ".0m", "m")
	if neg {
		return "-" + s
	}
	return s
}

func money(cents int) string {
	neg := cents < 0
	if neg {
		cents = -cents
	}
	s := fmt.Sprintf("$%d", cents/100)
	if neg {
		return "-" + s
	}
	return s
}

// ---------- ui ----------

type rect struct {
	x, y, w, h float32
}

func (r rect) contains(x, y float32) bool {
	return x >= r.x && x <= r.x+r.w && y >= r.y && y <= r.y+r.h
}

type uiButton struct {
	id      string
	label   string
	bounds  rect
	enabled bool
}

type settingMeta struct {
	key       string
	label     string
	format    func(Settings) string
	editValue func(Settings) string
	parse     func(*Settings, string) error
	adjust    func(*Settings, int)
}

type settingControl struct {
	meta   settingMeta
	minus  rect
	plus   rect
	value  rect
	rowBox rect
}

var settingMetas = []settingMeta{
	{
		key:   "animation-speed",
		label: "Animation speed",
	},
	{
		key:       "job-income",
		label:     "Job income",
		format:    func(s Settings) string { return money(s.JobIncome) },
		editValue: func(s Settings) string { return fmt.Sprintf("%.2f", float64(s.JobIncome)/100) },
		parse: func(s *Settings, raw string) error {
			v, err := parseMoneyInput(raw)
			if err != nil {
				return err
			}
			s.JobIncome = v
			return nil
		},
		adjust: func(s *Settings, d int) { s.JobIncome = max(0, s.JobIncome+d*10_000) },
	},
	{
		key:       "needs",
		label:     "Needs",
		format:    func(s Settings) string { return money(s.Needs) },
		editValue: func(s Settings) string { return fmt.Sprintf("%.2f", float64(s.Needs)/100) },
		parse: func(s *Settings, raw string) error {
			v, err := parseMoneyInput(raw)
			if err != nil {
				return err
			}
			s.Needs = v
			return nil
		},
		adjust: func(s *Settings, d int) { s.Needs = max(0, s.Needs+d*5_000) },
	},
	{
		key:       "wants",
		label:     "Wants",
		format:    func(s Settings) string { return money(s.Wants) },
		editValue: func(s Settings) string { return fmt.Sprintf("%.2f", float64(s.Wants)/100) },
		parse: func(s *Settings, raw string) error {
			v, err := parseMoneyInput(raw)
			if err != nil {
				return err
			}
			s.Wants = v
			return nil
		},
		adjust: func(s *Settings, d int) { s.Wants = max(0, s.Wants+d*5_000) },
	},
	{
		key:       "starting-debt",
		label:     "Starting debt",
		format:    func(s Settings) string { return money(s.StartingDebt) },
		editValue: func(s Settings) string { return fmt.Sprintf("%.2f", float64(s.StartingDebt)/100) },
		parse: func(s *Settings, raw string) error {
			v, err := parseMoneyInput(raw)
			if err != nil {
				return err
			}
			s.StartingDebt = v
			return nil
		},
		adjust: func(s *Settings, d int) { s.StartingDebt = max(0, s.StartingDebt+d*10_000) },
	},
	{
		key:       "debt-interest",
		label:     "Debt APR",
		format:    func(s Settings) string { return fmt.Sprintf("%.1f%%", s.DebtInterestAnnual) },
		editValue: func(s Settings) string { return fmt.Sprintf("%.1f", s.DebtInterestAnnual) },
		parse: func(s *Settings, raw string) error {
			v, err := parsePercentInput(raw)
			if err != nil {
				return err
			}
			if v > 100 {
				return fmt.Errorf("Debt APR must be between 0 and 100")
			}
			s.DebtInterestAnnual = v
			return nil
		},
		adjust: func(s *Settings, d int) { s.DebtInterestAnnual = clamp(s.DebtInterestAnnual+float64(d), 0, 100) },
	},
	{
		key:       "minimum-payment",
		label:     "Min debt payment",
		format:    func(s Settings) string { return money(s.MinimumDebtPayment) },
		editValue: func(s Settings) string { return fmt.Sprintf("%.2f", float64(s.MinimumDebtPayment)/100) },
		parse: func(s *Settings, raw string) error {
			v, err := parseMoneyInput(raw)
			if err != nil {
				return err
			}
			s.MinimumDebtPayment = v
			return nil
		},
		adjust: func(s *Settings, d int) { s.MinimumDebtPayment = max(0, s.MinimumDebtPayment+d*5_000) },
	},
	{
		key:       "starting-assets",
		label:     "Starting assets",
		format:    func(s Settings) string { return money(s.StartingAssets) },
		editValue: func(s Settings) string { return fmt.Sprintf("%.2f", float64(s.StartingAssets)/100) },
		parse: func(s *Settings, raw string) error {
			v, err := parseMoneyInput(raw)
			if err != nil {
				return err
			}
			s.StartingAssets = v
			return nil
		},
		adjust: func(s *Settings, d int) { s.StartingAssets = max(0, s.StartingAssets+d*10_000) },
	},
	{
		key:       "asset-return",
		label:     "Asset return",
		format:    func(s Settings) string { return fmt.Sprintf("%.1f%%", s.AssetReturnAnnual) },
		editValue: func(s Settings) string { return fmt.Sprintf("%.1f", s.AssetReturnAnnual) },
		parse: func(s *Settings, raw string) error {
			v, err := parsePercentInput(raw)
			if err != nil {
				return err
			}
			if v > 100 {
				return fmt.Errorf("Asset return must be between 0 and 100")
			}
			s.AssetReturnAnnual = v
			return nil
		},
		adjust: func(s *Settings, d int) { s.AssetReturnAnnual = clamp(s.AssetReturnAnnual+float64(d)*0.5, 0, 100) },
	},
	{
		key:       "withdraw-rate",
		label:     "Withdraw rate",
		format:    func(s Settings) string { return fmt.Sprintf("%.0f%%", s.WithdrawRate) },
		editValue: func(s Settings) string { return fmt.Sprintf("%.0f", s.WithdrawRate) },
		parse: func(s *Settings, raw string) error {
			v, err := parsePercentInput(raw)
			if err != nil {
				return err
			}
			if v > 100 {
				return fmt.Errorf("Withdraw rate must be between 0 and 100")
			}
			s.WithdrawRate = v
			return nil
		},
		adjust: func(s *Settings, d int) { s.WithdrawRate = clamp(s.WithdrawRate+float64(d)*5, 0, 100) },
	},
	{
		key:       "spend-rate",
		label:     "Spend rate",
		format:    func(s Settings) string { return fmt.Sprintf("%.0f%%", s.SpendRate) },
		editValue: func(s Settings) string { return fmt.Sprintf("%.0f", s.SpendRate) },
		parse: func(s *Settings, raw string) error {
			v, err := parsePercentInput(raw)
			if err != nil {
				return err
			}
			if v > 100 {
				return fmt.Errorf("Spend rate must be between 0 and 100")
			}
			s.SpendRate = v
			return nil
		},
		adjust: func(s *Settings, d int) { s.SpendRate = clamp(s.SpendRate+float64(d)*5, 0, 100) },
	},
}

func parseMoneyInput(raw string) (int, error) {
	s := strings.TrimSpace(strings.ToLower(raw))
	s = strings.ReplaceAll(s, ",", "")
	s = strings.TrimPrefix(s, "$")
	if s == "" {
		return 0, fmt.Errorf("enter a dollar amount")
	}
	multiplier := 1.0
	if strings.HasSuffix(s, "k") {
		multiplier = 1_000
		s = strings.TrimSuffix(s, "k")
	} else if strings.HasSuffix(s, "m") {
		multiplier = 1_000_000
		s = strings.TrimSuffix(s, "m")
	}
	v, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return 0, fmt.Errorf("invalid money value")
	}
	if v < 0 {
		return 0, fmt.Errorf("value must be non-negative")
	}
	return int(math.Round(v * multiplier * 100)), nil
}

func parsePercentInput(raw string) (float64, error) {
	s := strings.TrimSpace(strings.ToLower(raw))
	s = strings.TrimSuffix(s, "%")
	if s == "" {
		return 0, fmt.Errorf("enter a percent value")
	}
	v, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return 0, fmt.Errorf("invalid percent value")
	}
	if v < 0 {
		return 0, fmt.Errorf("value must be non-negative")
	}
	return v, nil
}

func parseSpeedInput(raw string) (float64, error) {
	s := strings.TrimSpace(strings.ToLower(raw))
	s = strings.TrimSuffix(s, "x")
	if s == "" {
		return 0, fmt.Errorf("enter a speed like 1.0")
	}
	v, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return 0, fmt.Errorf("invalid speed value")
	}
	if v <= 0 {
		return 0, fmt.Errorf("speed must be greater than 0")
	}
	return v, nil
}

// ---------- persistence ----------

type persistedNode struct {
	X float32 `json:"x"`
	Y float32 `json:"y"`
}

type persistedState struct {
	Settings        Settings                 `json:"settings"`
	Nodes           map[string]persistedNode `json:"nodes"`
	AnimationFrames int                      `json:"animationFrames"`
}

func persistPath() string {
	dir, err := os.UserConfigDir()
	if err != nil || dir == "" {
		return "cashflowanimation-game.json"
	}
	dir = filepath.Join(dir, "cashflowanimation")
	_ = os.MkdirAll(dir, 0o755)
	return filepath.Join(dir, "game-ui.json")
}

// ---------- game ----------

type activeFlow struct {
	edgeID string
	amount int
	color  color.RGBA
	radius float32
	start  float64
	end    float64
}

type Game struct {
	settings        Settings
	state           State
	next            State
	nodes           map[string]*node
	flows           []activeFlow
	frame           int
	animationFrames int
	playing         bool
	stepAnimating   bool
	stepTargetFrame int
	stepCommitMonth bool

	draggingNode string
	dragOffsetX  float32
	dragOffsetY  float32
	showSnapX    bool
	showSnapY    bool
	snapX        float32
	snapY        float32

	activeSetting string
	editBuffer    string

	status       string
	statusFrames int
}

func NewGame() *Game {
	g := &Game{
		settings:        DefaultSettings,
		nodes:           cloneNodes(),
		animationFrames: defaultAnimationFrames,
		playing:         true,
	}
	g.resetSimulation()
	if err := g.loadPersistedState(); err != nil && !os.IsNotExist(err) {
		g.setStatus("load failed: " + err.Error())
	} else if err == nil {
		g.setStatus("loaded saved UI state")
	}
	return g
}

func (g *Game) resetSimulation() {
	g.state = InitialState(g.settings)
	g.startMonth()
}

func (g *Game) displayState() State {
	if g.frame > 0 {
		return g.next
	}
	return g.state
}

func (g *Game) setStatus(msg string) {
	g.status = msg
	g.statusFrames = 240
}

func (g *Game) autoSave(message string) {
	if err := g.savePersistedState(); err != nil {
		g.setStatus("auto-save failed: " + err.Error())
		return
	}
	if message != "" {
		g.setStatus(message + " • auto-saved")
	}
}

func (g *Game) animationSpeed() float64 {
	frames := g.animationFrames
	if frames <= 0 {
		frames = defaultAnimationFrames
	}
	return float64(defaultAnimationFrames) / float64(frames)
}

func (g *Game) setAnimationFrames(frames int) {
	if frames < 15 {
		frames = 15
	}
	if frames > 240 {
		frames = 240
	}
	g.animationFrames = frames
	if g.frame >= g.animationFrames {
		g.frame = g.animationFrames - 1
	}
	if g.frame < 0 {
		g.frame = 0
	}
}

func (g *Game) setAnimationSpeed(speed float64) {
	frames := int(math.Round(float64(defaultAnimationFrames) / speed))
	g.setAnimationFrames(frames)
}

func (g *Game) adjustAnimationSpeed(dir int) {
	g.setAnimationFrames(g.animationFrames - dir*10)
}

func (g *Game) startMonth() {
	g.next = SimulateMonth(g.state, g.settings)
	g.flows = nil
	g.stepAnimating = false
	g.stepTargetFrame = 0
	g.stepCommitMonth = false
	for _, f := range flowsFor(g.next.Last, g.settings) {
		if f.amount == 0 {
			continue
		}
		start, end := flowWindow(f.edgeID)
		g.flows = append(g.flows, activeFlow{
			edgeID: f.edgeID,
			amount: f.amount,
			color:  flowCircleColor(f.edgeID, f.amount),
			radius: flowCircleRadius(f.amount),
			start:  start,
			end:    end,
		})
	}
	g.frame = 0
}

func (g *Game) commitMonth() {
	g.state = g.next
	g.flows = nil
}

type flowAmt struct {
	edgeID string
	amount int
}

func flowsFor(last MonthResult, s Settings) []flowAmt {
	abs := func(v int) int {
		if v < 0 {
			return -v
		}
		return v
	}
	max0 := func(v int) int {
		if v < 0 {
			return 0
		}
		return v
	}
	return []flowAmt{
		{"job-income", s.JobIncome},
		{"asset-return", abs(last.AssetReturn)},
		{"return-split", max0(last.AssetReturn)},
		{"withdraw-income", last.WithdrawnReturn},
		{"reinvest-assets", last.ReinvestedReturn},
		{"needs-cashflow", s.Needs},
		{"wants-cashflow", s.Wants},
		{"debt-cashflow", last.DebtInterest},
		{"income-cashflow", last.TotalIncome},
		{"cashflow-graveyard", s.Needs + s.Wants},
		{"cashflow-debt", last.MinimumPayment + last.DebtPaydown},
		{"cashflow-decision", last.Save + last.Spend},
		{"decision-spend", last.Spend},
		{"decision-save", last.Save},
	}
}

func flowWindow(edgeID string) (float64, float64) {
	switch edgeID {
	case "asset-return":
		return 0.00, 0.14
	case "return-split":
		return 0.08, 0.20
	case "job-income", "withdraw-income", "reinvest-assets":
		return 0.20, 0.38
	case "needs-cashflow":
		return 0.38, 0.50
	case "wants-cashflow":
		return 0.42, 0.54
	case "debt-cashflow":
		return 0.46, 0.58
	case "income-cashflow":
		return 0.50, 0.64
	case "cashflow-graveyard":
		return 0.66, 0.78
	case "cashflow-debt", "cashflow-decision":
		return 0.80, 0.90
	case "decision-spend", "decision-save":
		return 0.90, 1.00
	default:
		return 0.00, 1.00
	}
}

func stepBoundaries() []float64 {
	return []float64{0.20, 0.38, 0.66, 0.80, 0.90, 1.00}
}

func stageLabel(progress float64) string {
	switch {
	case progress < 0.20:
		return "1/6 assets → return split"
	case progress < 0.38:
		return "2/6 split → income + job"
	case progress < 0.66:
		return "3/6 into cashflow"
	case progress < 0.80:
		return "4/6 cashflow result"
	case progress < 0.90:
		return "5/6 debt payoff + routing"
	default:
		return "6/6 final allocation"
	}
}

func isShiftPressed() bool {
	return ebiten.IsKeyPressed(ebiten.KeyShiftLeft) || ebiten.IsKeyPressed(ebiten.KeyShiftRight)
}

func controlPressed() bool {
	return ebiten.IsKeyPressed(ebiten.KeyControlLeft) || ebiten.IsKeyPressed(ebiten.KeyControlRight)
}

func (g *Game) controlButtons() []uiButton {
	labels := []struct {
		id, label string
		enabled   bool
	}{
		{"play", ternary(g.playing, "Pause", "Play"), true},
		{"step", "Step", !g.playing && !g.stepAnimating},
		{"reset", "Reset", true},
		{"save", "Save", true},
		{"load", "Load", true},
	}
	buttons := make([]uiButton, 0, len(labels))
	for i, item := range labels {
		buttons = append(buttons, uiButton{
			id:      item.id,
			label:   item.label,
			enabled: item.enabled,
			bounds: rect{
				x: panelX + 16 + float32(i%2)*170,
				y: 106 + float32(i/2)*42,
				w: 150,
				h: 32,
			},
		})
	}
	return buttons
}

func ternary(ok bool, a, b string) string {
	if ok {
		return a
	}
	return b
}

func (g *Game) settingControls() []settingControl {
	controls := make([]settingControl, 0, len(settingMetas))
	baseY := float32(242)
	for i, meta := range settingMetas {
		y := baseY + float32(i)*40
		controls = append(controls, settingControl{
			meta:   meta,
			rowBox: rect{x: panelX + 14, y: y - 4, w: panelW - 28, h: 36},
			minus:  rect{x: panelX + 210, y: y, w: 34, h: 24},
			value:  rect{x: panelX + 250, y: y, w: 118, h: 24},
			plus:   rect{x: panelX + 372, y: y, w: 34, h: 24},
		})
	}
	return controls
}

func (g *Game) findSettingMeta(key string) (settingMeta, bool) {
	for _, meta := range settingMetas {
		if meta.key == key {
			return meta, true
		}
	}
	return settingMeta{}, false
}

func (g *Game) hoveredSettingControl(mx, my float32) (settingControl, bool) {
	for _, control := range g.settingControls() {
		if control.rowBox.contains(mx, my) || control.minus.contains(mx, my) || control.plus.contains(mx, my) || control.value.contains(mx, my) {
			return control, true
		}
	}
	return settingControl{}, false
}

func (g *Game) beginSettingEdit(meta settingMeta) {
	g.activeSetting = meta.key
	if meta.key == "animation-speed" {
		g.editBuffer = fmt.Sprintf("%.1f", g.animationSpeed())
	} else {
		g.editBuffer = meta.editValue(g.settings)
	}
	g.setStatus(meta.label + " editing")
}

func (g *Game) cancelSettingEdit() {
	if g.activeSetting == "" {
		return
	}
	g.activeSetting = ""
	g.editBuffer = ""
	g.setStatus("edit canceled")
}

func (g *Game) commitSettingEdit() bool {
	if g.activeSetting == "" {
		return true
	}
	meta, ok := g.findSettingMeta(g.activeSetting)
	if !ok {
		g.activeSetting = ""
		g.editBuffer = ""
		return true
	}
	if meta.key == "animation-speed" {
		v, err := parseSpeedInput(g.editBuffer)
		if err != nil {
			g.setStatus(meta.label + ": " + err.Error())
			return false
		}
		g.setAnimationSpeed(v)
		g.activeSetting = ""
		g.editBuffer = ""
		g.autoSave(meta.label + " updated")
		return true
	}
	if err := meta.parse(&g.settings, g.editBuffer); err != nil {
		g.setStatus(meta.label + ": " + err.Error())
		return false
	}
	g.activeSetting = ""
	g.editBuffer = ""
	g.resetSimulation()
	g.autoSave(meta.label + " updated")
	return true
}

func (g *Game) currentProgress() float64 {
	denom := math.Max(1, float64(g.animationFrames-1))
	return float64(g.frame) / denom
}

func (g *Game) advanceStepAnimation() {
	if g.playing || g.stepAnimating {
		return
	}
	progress := g.currentProgress()
	for _, boundary := range stepBoundaries() {
		if progress+1e-6 < boundary {
			g.stepTargetFrame = int(math.Ceil(boundary * math.Max(1, float64(g.animationFrames-1))))
			if g.stepTargetFrame <= g.frame {
				g.stepTargetFrame = g.frame + 1
			}
			maxFrame := max(0, g.animationFrames-1)
			if g.stepTargetFrame > maxFrame {
				g.stepTargetFrame = maxFrame
			}
			g.stepAnimating = true
			g.stepCommitMonth = boundary >= 1.0
			g.setStatus("stepping " + stageLabel(progress))
			return
		}
	}
	g.commitMonth()
	g.startMonth()
	g.setStatus("advanced to next month")
}

func (g *Game) handleButton(id string) {
	switch id {
	case "play":
		g.playing = !g.playing
		g.stepAnimating = false
		g.stepCommitMonth = false
		g.setStatus(ternary(g.playing, "playing", "paused"))
	case "step":
		g.advanceStepAnimation()
	case "reset":
		g.resetSimulation()
		g.autoSave("simulation reset")
	case "save":
		if err := g.savePersistedState(); err != nil {
			g.setStatus("save failed: " + err.Error())
		} else {
			g.setStatus("saved settings + layout")
		}
	case "load":
		if err := g.loadPersistedState(); err != nil {
			g.setStatus("load failed: " + err.Error())
		} else {
			g.setStatus("loaded settings + layout")
		}
	}
}

func (g *Game) applySetting(meta settingMeta, dir int) {
	mult := 1
	if isShiftPressed() {
		mult = 5
	}
	if meta.key == "animation-speed" {
		g.adjustAnimationSpeed(dir * mult)
		g.autoSave(meta.label + " updated")
		return
	}
	meta.adjust(&g.settings, dir*mult)
	g.resetSimulation()
	g.autoSave(meta.label + " updated")
}

func (g *Game) tryStartDrag(mx, my float32) bool {
	for i := len(nodeOrder) - 1; i >= 0; i-- {
		n := g.nodes[nodeOrder[i]]
		dx, dy := mx-n.x, my-n.y
		if dx*dx+dy*dy <= n.r*n.r {
			g.draggingNode = n.id
			g.dragOffsetX = dx
			g.dragOffsetY = dy
			return true
		}
	}
	return false
}

func absf(v float32) float32 {
	if v < 0 {
		return -v
	}
	return v
}

func roundToGrid(v, grid float32) float32 {
	return float32(math.Round(float64(v/grid))) * grid
}

func (g *Game) snapNodePosition(id string, x, y float32) (float32, float32) {
	g.showSnapX = false
	g.showSnapY = false

	const alignThreshold = float32(12)
	const gridThreshold = float32(6)

	bestXDelta := float32(1e9)
	bestYDelta := float32(1e9)
	for otherID, other := range g.nodes {
		if otherID == id {
			continue
		}
		if d := absf(x - other.x); d < alignThreshold && d < bestXDelta {
			bestXDelta = d
			x = other.x
			g.showSnapX = true
			g.snapX = other.x
		}
		if d := absf(y - other.y); d < alignThreshold && d < bestYDelta {
			bestYDelta = d
			y = other.y
			g.showSnapY = true
			g.snapY = other.y
		}
	}

	if !g.showSnapX {
		gx := roundToGrid(x, 20)
		if absf(x-gx) <= gridThreshold {
			x = gx
			g.showSnapX = true
			g.snapX = gx
		}
	}
	if !g.showSnapY {
		gy := roundToGrid(y, 20)
		if absf(y-gy) <= gridThreshold {
			y = gy
			g.showSnapY = true
			g.snapY = gy
		}
	}

	return x, y
}

func (g *Game) updateDrag(mx, my float32) {
	if g.draggingNode == "" {
		g.showSnapX = false
		g.showSnapY = false
		return
	}
	n := g.nodes[g.draggingNode]
	x := clampFloat32(mx-g.dragOffsetX, n.r, float32(panelX)-24)
	y := clampFloat32(my-g.dragOffsetY, 36, screenH-36)
	n.x, n.y = g.snapNodePosition(g.draggingNode, x, y)
}

func (g *Game) savePersistedState() error {
	p := persistedState{Settings: g.settings, Nodes: map[string]persistedNode{}, AnimationFrames: g.animationFrames}
	for id, n := range g.nodes {
		p.Nodes[id] = persistedNode{X: n.x, Y: n.y}
	}
	data, err := json.MarshalIndent(p, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(persistPath(), data, 0o644)
}

func (g *Game) loadPersistedState() error {
	data, err := os.ReadFile(persistPath())
	if err != nil {
		return err
	}
	var p persistedState
	if err := json.Unmarshal(data, &p); err != nil {
		return err
	}
	g.settings = p.Settings
	g.setAnimationFrames(p.AnimationFrames)
	if p.AnimationFrames == 0 {
		g.setAnimationFrames(defaultAnimationFrames)
	}
	g.nodes = cloneNodes()
	for id, pos := range p.Nodes {
		if n := g.nodes[id]; n != nil {
			n.x = pos.X
			n.y = pos.Y
		}
	}
	g.activeSetting = ""
	g.editBuffer = ""
	g.showSnapX = false
	g.showSnapY = false
	g.resetSimulation()
	return nil
}

func allowedInputRune(r rune) bool {
	return unicode.IsDigit(r) || strings.ContainsRune(".$,%kKmM", r)
}

func trimLastRune(s string) string {
	runes := []rune(s)
	if len(runes) == 0 {
		return s
	}
	return string(runes[:len(runes)-1])
}

func (g *Game) handleTextEditing() {
	if g.activeSetting == "" {
		return
	}
	for _, r := range ebiten.AppendInputChars(nil) {
		if allowedInputRune(r) {
			g.editBuffer += string(r)
		}
	}
	if inpututil.IsKeyJustPressed(ebiten.KeyBackspace) {
		g.editBuffer = trimLastRune(g.editBuffer)
	}
	if inpututil.IsKeyJustPressed(ebiten.KeyEnter) || inpututil.IsKeyJustPressed(ebiten.KeyNumpadEnter) {
		g.commitSettingEdit()
	}
	if inpututil.IsKeyJustPressed(ebiten.KeyEscape) {
		g.cancelSettingEdit()
	}
}

func (g *Game) Update() error {
	mx, my := ebiten.CursorPosition()
	mouseX, mouseY := float32(mx), float32(my)

	g.handleTextEditing()

	if inpututil.IsKeyJustPressed(ebiten.KeySpace) && g.activeSetting == "" {
		g.playing = !g.playing
		g.stepAnimating = false
		g.stepCommitMonth = false
		g.setStatus(ternary(g.playing, "playing", "paused"))
	}
	if inpututil.IsKeyJustPressed(ebiten.KeyR) {
		if g.commitSettingEdit() {
			g.resetSimulation()
			g.autoSave("simulation reset")
		}
	}
	if inpututil.IsKeyJustPressed(ebiten.KeyS) && controlPressed() {
		if !g.commitSettingEdit() {
			return nil
		}
		if err := g.savePersistedState(); err != nil {
			g.setStatus("save failed: " + err.Error())
		} else {
			g.setStatus("saved settings + layout")
		}
	}

	if g.activeSetting == "" && g.draggingNode == "" {
		_, wheelY := ebiten.Wheel()
		if wheelY != 0 {
			if control, ok := g.hoveredSettingControl(mouseX, mouseY); ok {
				dir := -1
				if wheelY > 0 {
					dir = 1
				}
				g.applySetting(control.meta, dir)
				return nil
			}
		}
	}

	if inpututil.IsMouseButtonJustPressed(ebiten.MouseButtonLeft) {
		if g.activeSetting != "" {
			clickedActive := false
			for _, control := range g.settingControls() {
				if control.meta.key == g.activeSetting && control.value.contains(mouseX, mouseY) {
					clickedActive = true
					break
				}
			}
			if !clickedActive && !g.commitSettingEdit() {
				return nil
			}
		}

		for _, button := range g.controlButtons() {
			if button.enabled && button.bounds.contains(mouseX, mouseY) {
				g.handleButton(button.id)
				return nil
			}
		}
		for _, control := range g.settingControls() {
			if control.minus.contains(mouseX, mouseY) {
				g.applySetting(control.meta, -1)
				return nil
			}
			if control.plus.contains(mouseX, mouseY) {
				g.applySetting(control.meta, 1)
				return nil
			}
			if control.value.contains(mouseX, mouseY) {
				g.beginSettingEdit(control.meta)
				return nil
			}
		}
		g.tryStartDrag(mouseX, mouseY)
	}

	if ebiten.IsMouseButtonPressed(ebiten.MouseButtonLeft) {
		g.updateDrag(mouseX, mouseY)
	} else if g.draggingNode == "" {
		g.showSnapX = false
		g.showSnapY = false
	}
	if inpututil.IsMouseButtonJustReleased(ebiten.MouseButtonLeft) && g.draggingNode != "" {
		g.draggingNode = ""
		g.showSnapX = false
		g.showSnapY = false
		g.autoSave("node moved")
	}

	if g.statusFrames > 0 {
		g.statusFrames--
	}

	if g.playing {
		g.frame++
		if g.frame >= g.animationFrames {
			g.commitMonth()
			g.startMonth()
		}
		return nil
	}

	if g.stepAnimating {
		g.frame++
		if g.frame >= g.stepTargetFrame {
			g.frame = g.stepTargetFrame
			g.stepAnimating = false
			if g.stepCommitMonth {
				g.commitMonth()
				g.startMonth()
				g.setStatus("advanced to next month")
			} else {
				g.setStatus("step complete")
			}
		}
	}
	return nil
}

func (g *Game) Draw(screen *ebiten.Image) {
	screen.Fill(bgColor)

	for _, spec := range edgeSpecs {
		e := edgeFor(spec, g.nodes)
		steps := 24
		var prevX, prevY float32
		for i := 0; i <= steps; i++ {
			t := float32(i) / float32(steps)
			x, y := bezierPoint(e, t)
			if i > 0 {
				w := float32(3)
				a := e.color
				a.A = 90
				if e.backedge {
					a.A = 55
				}
				if i%2 == 0 || !e.backedge {
					vector.StrokeLine(screen, prevX, prevY, x, y, w, a, true)
				}
			}
			prevX, prevY = x, y
		}
	}

	if g.showSnapX {
		vector.StrokeLine(screen, g.snapX, 20, g.snapX, screenH-20, 1.5, guideColor, true)
	}
	if g.showSnapY {
		vector.StrokeLine(screen, 20, g.snapY, float32(panelX)-12, g.snapY, 1.5, guideColor, true)
	}

	denom := math.Max(1, float64(g.animationFrames-1))
	t := float64(g.frame) / denom
	for i, flow := range g.flows {
		if t < flow.start || t > flow.end {
			continue
		}
		localT := (t - flow.start) / math.Max(1e-6, flow.end-flow.start)
		e := edgeFor(edgeSpecs[flow.edgeID], g.nodes)
		x, y := bezierPoint(e, float32(localT))
		bob := 3 * math.Sin(float64(g.frame)*0.3+float64(i)*1.4)
		cy := y + float32(bob)
		vector.DrawFilledCircle(screen, x, cy, flow.radius, flow.color, true)
		vector.StrokeCircle(screen, x, cy, flow.radius, 1.5, color.RGBA{0x11, 0x11, 0x11, 0xff}, true)
		drawCenteredText(screen, compactMoney(flow.amount), x, cy, color.RGBA{0xf6, 0xfb, 0xf6, 0xff})
	}

	for _, id := range nodeOrder {
		n := g.nodes[id]
		fill := categoryFill[n.cat]
		edgeC := categoryEdge[n.cat]
		if id == g.draggingNode {
			edgeC = accentColor
		}
		labelY := n.y - 8
		amountY := n.y + 10
		if strings.Contains(n.label, "\n") {
			labelY = n.y - 14
			amountY = n.y + 18
		}
		vector.DrawFilledCircle(screen, n.x, n.y, n.r, fill, true)
		vector.StrokeCircle(screen, n.x, n.y, n.r, 2.5, edgeC, true)
		drawCenteredText(screen, n.label, n.x, labelY, inkColor)
		drawCenteredText(screen, g.nodeAmount(id), n.x, amountY, color.RGBA{0xf4, 0xef, 0xe2, 0xff})
	}

	st := g.displayState()
	drawCenteredText(screen, fmt.Sprintf("MONTH %d", st.Month), 180, 32, inkColor)
	drawCenteredText(screen, stageLabel(t), 180, 54, accentColor)
	drawCenteredText(screen, "ordered flow: assets → return split → split + job income → cashflow → result → debt payoff + routing → final", 560, screenH-24, neutralColor)

	g.drawControlPanel(screen)
}

func (g *Game) drawControlPanel(screen *ebiten.Image) {
	vector.DrawFilledRect(screen, panelX, 20, panelW, 760, panelColor, true)
	vector.StrokeRect(screen, panelX, 20, panelW, 760, 2, neutralColor, true)

	drawCenteredText(screen, "INTERACTIVE CONTROLS", panelX+panelW/2, 34, inkColor)

	for _, button := range g.controlButtons() {
		fill := buttonColor
		border := accentColor
		text := inkColor
		if !button.enabled {
			fill = buttonMuteColor
			border = neutralColor
			text = neutralColor
		}
		vector.DrawFilledRect(screen, button.bounds.x, button.bounds.y, button.bounds.w, button.bounds.h, fill, true)
		vector.StrokeRect(screen, button.bounds.x, button.bounds.y, button.bounds.w, button.bounds.h, 1.5, border, true)
		drawCenteredText(screen, button.label, button.bounds.x+button.bounds.w/2, button.bounds.y+button.bounds.h/2, text)
	}

	legendX, legendY := float32(panelX)+18, float32(72)
	vector.DrawFilledCircle(screen, legendX+10, legendY+4, 10, accentColor, true)
	vector.DrawFilledCircle(screen, legendX+10, legendY+28, 10, color.RGBA{0xd9, 0x6c, 0x68, 0xff}, true)
	drawText(screen, "green = positive flow", legendX+28, legendY-2, inkColor)
	drawText(screen, "red = negative flow", legendX+28, legendY+16, inkColor)
	drawText(screen, "bigger amounts get darker", legendX+28, legendY+34, inkColor)

	drawText(screen, "Simulation settings", panelX+18, 224, inkColor)
	for _, control := range g.settingControls() {
		vector.DrawFilledRect(screen, control.rowBox.x, control.rowBox.y, control.rowBox.w, control.rowBox.h, color.RGBA{0x1a, 0x20, 0x1e, 0xff}, true)
		vector.StrokeRect(screen, control.rowBox.x, control.rowBox.y, control.rowBox.w, control.rowBox.h, 1, color.RGBA{0x2f, 0x39, 0x35, 0xff}, true)
		drawText(screen, control.meta.label, panelX+22, control.rowBox.y+14, inkColor)
		g.drawSmallButton(screen, control.minus, "-")
		g.drawValueBox(screen, control)
		g.drawSmallButton(screen, control.plus, "+")
	}

	drawText(screen, "Shortcuts", panelX+18, 694, inkColor)
	drawText(screen, "SPACE play/pause", panelX+18, 716, neutralColor)
	drawText(screen, "R reset", panelX+18, 734, neutralColor)
	drawText(screen, "Ctrl+S save now", panelX+18, 752, neutralColor)
	drawText(screen, "Click value to type • Esc cancel", panelX+18, 770, neutralColor)

	status := g.status
	statusColor := neutralColor
	if status == "" || g.statusFrames == 0 {
		status = "status: ready"
	} else {
		statusColor = accentColor
	}
	drawText(screen, status, panelX+18, 786, statusColor)
}

func (g *Game) drawSmallButton(screen *ebiten.Image, box rect, label string) {
	vector.DrawFilledRect(screen, box.x, box.y, box.w, box.h, buttonColor, true)
	vector.StrokeRect(screen, box.x, box.y, box.w, box.h, 1.5, accentColor, true)
	drawCenteredText(screen, label, box.x+box.w/2, box.y+box.h/2, inkColor)
}

func (g *Game) drawValueBox(screen *ebiten.Image, control settingControl) {
	fill := color.RGBA{0x16, 0x1d, 0x1a, 0xff}
	border := neutralColor
	value := ""
	if control.meta.key == "animation-speed" {
		value = fmt.Sprintf("%.1fx", g.animationSpeed())
	} else {
		value = control.meta.format(g.settings)
	}
	if g.activeSetting == control.meta.key {
		fill = editFillColor
		border = accentColor
		cursor := ""
		if (g.frame/15)%2 == 0 || !g.playing {
			cursor = "|"
		}
		value = g.editBuffer + cursor
	}
	vector.DrawFilledRect(screen, control.value.x, control.value.y, control.value.w, control.value.h, fill, true)
	vector.StrokeRect(screen, control.value.x, control.value.y, control.value.w, control.value.h, 1.5, border, true)
	drawCenteredText(screen, value, control.value.x+control.value.w/2, control.value.y+control.value.h/2, inkColor)
}

func drawText(screen *ebiten.Image, s string, x, y float32, c color.Color) {
	op := &etext.DrawOptions{}
	op.GeoM.Translate(float64(x), float64(y))
	op.ColorScale.ScaleWithColor(c)
	etext.Draw(screen, s, face, op)
}

func drawCenteredText(screen *ebiten.Image, s string, cx, cy float32, c color.Color) {
	lines := strings.Split(s, "\n")
	lineHeight := 14.0
	totalHeight := lineHeight * float64(len(lines))
	startY := float64(cy) - totalHeight/2
	for i, line := range lines {
		w, _ := etext.Measure(line, face, 14)
		op := &etext.DrawOptions{}
		op.GeoM.Translate(float64(cx)-w/2, startY+float64(i)*lineHeight)
		op.ColorScale.ScaleWithColor(c)
		etext.Draw(screen, line, face, op)
	}
}

func (g *Game) nodeAmount(id string) string {
	progress := g.currentProgress()
	last := g.next.Last
	openingAssets := g.state.Assets
	openingDebt := g.state.Debt
	openingConsumed := g.state.Consumed

	pair := func(a, b int) string {
		return money(a) + "/" + money(b)
	}

	switch id {
	case "assets":
		assetAfterReturn := openingAssets
		if last.AssetReturn < 0 {
			assetAfterReturn = max(0, openingAssets+last.AssetReturn)
		}
		assetAfterReinvest := assetAfterReturn
		if last.AssetReturn >= 0 {
			assetAfterReinvest = openingAssets + last.ReinvestedReturn
		}
		if progress < 0.20 {
			return money(openingAssets)
		}
		if progress < 0.38 {
			return money(assetAfterReturn)
		}
		if progress < 1.0 {
			return money(assetAfterReinvest)
		}
		return money(g.next.Assets)
	case "asset-return":
		if progress < 0.20 {
			return money(0)
		}
		return money(last.AssetReturn)
	case "return-split":
		if progress < 0.20 {
			return pair(0, 0)
		}
		return pair(last.WithdrawnReturn, last.ReinvestedReturn)
	case "job-income":
		return money(g.settings.JobIncome)
	case "income":
		if progress < 0.38 {
			return money(0)
		}
		return money(last.TotalIncome)
	case "needs":
		return money(g.settings.Needs)
	case "wants":
		return money(g.settings.Wants)
	case "cashflow":
		if progress < 0.66 {
			return money(0)
		}
		return money(last.Cashflow)
	case "debt":
		debtAfterInterest := openingDebt + last.DebtInterest
		if progress < 0.66 {
			return money(openingDebt)
		}
		if progress < 0.90 {
			return money(debtAfterInterest)
		}
		return money(g.next.Debt)
	case "decision":
		if progress < 0.90 {
			return pair(0, 0)
		}
		return pair(last.Spend, last.Save)
	case "graveyard":
		baseConsumed := openingConsumed + g.settings.Needs + g.settings.Wants
		if progress < 0.80 {
			return money(openingConsumed)
		}
		if progress < 1.0 {
			return money(baseConsumed)
		}
		return money(openingConsumed + last.ConsumedThisMonth)
	}
	return ""
}

func (g *Game) Layout(outsideWidth, outsideHeight int) (int, int) {
	return screenW, screenH
}

func main() {
	ebiten.SetWindowSize(screenW, screenH)
	ebiten.SetWindowTitle("Cash Flow Animation")
	if err := ebiten.RunGame(NewGame()); err != nil {
		log.Fatal(err)
	}
}
