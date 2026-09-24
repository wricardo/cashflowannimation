import { DEFAULT_SETTINGS, initialState, simulateMonth } from "./simulation.js";

const STORAGE_KEY = "cash-flow-animation-settings-v1";
const $ = (selector) => document.querySelector(selector);
const svg = $("#factory");
const particles = $("#particles");
const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
let settings = loadSettings();
let state = initialState(settings);
let playing = false;
let animation = null;

const money = (cents) => new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 }).format(cents / 100);
const signedMoney = (cents) => `${cents < 0 ? "−" : ""}${money(Math.abs(cents))}`;

function loadSettings() {
  try { return { ...DEFAULT_SETTINGS, ...JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}") }; }
  catch { return { ...DEFAULT_SETTINGS }; }
}

function saveSettings() { localStorage.setItem(STORAGE_KEY, JSON.stringify(settings)); }

function updateInputs() {
  document.querySelectorAll("[data-key]").forEach((input) => {
    const key = input.dataset.key;
    input.value = key.endsWith("Annual") || key.endsWith("Rate") ? settings[key] : settings[key] / 100;
  });
}

function wireInputs() {
  $("#settings-form").addEventListener("input", (event) => {
    const input = event.target;
    if (!input.dataset.key) return;
    const key = input.dataset.key;
    const value = Math.max(Number(input.min || (key === "assetReturnAnnual" ? -Infinity : 0)), Number(input.value) || 0);
    settings[key] = key.endsWith("Annual") || key.endsWith("Rate") ? value : Math.round(value * 100);
    saveSettings();
  });
}

function updateUI() {
  const last = state.last || preview();
  $("#month").textContent = state.month;
  $("#total-income").textContent = money(last.totalIncome);
  $("#cashflow").textContent = signedMoney(last.cashflow);
  $("#debt-balance").textContent = money(state.debt);
  $("#asset-balance").textContent = money(state.assets);
  $("#consumed").textContent = money(state.consumed);
  $("#assets-node").textContent = money(state.assets);
  $("#asset-return-node").textContent = signedMoney(last.assetReturn);
  $("#return-split-node").textContent = `${money(last.withdrawnReturn)} / ${money(last.reinvestedReturn)}`;
  $("#job-income-node").textContent = money(settings.jobIncome);
  $("#income-node").textContent = money(last.totalIncome);
  $("#needs-node").textContent = money(settings.needs);
  $("#wants-node").textContent = money(settings.wants);
  $("#cashflow-node").textContent = signedMoney(last.cashflow);
  $("#paydown-node").textContent = last.cashflow > 0 ? money(last.debtPaydown || last.save + last.spend) : "DEFICIT";
  $("#debt-node").textContent = money(state.debt);
  $("#minimum-node").textContent = money(last.minimumPayment);
  $("#decision-node").textContent = `${money(last.spend)} / ${money(last.save)}`;
  $("#graveyard-node").textContent = money(state.consumed);
  $("#cashflow").style.color = last.cashflow < 0 ? "var(--red)" : "var(--green)";
}

function preview() { return simulateMonth(state, settings).last; }

function moveParticles(next) {
  particles.replaceChildren();
  if (reduceMotion) return Promise.resolve();
  const flows = [
    { id: "job-income", amount: next.last.totalIncome },
    { id: "asset-return", amount: next.last.assetReturn, signed: true },
    { id: "return-split", amount: Math.max(0, next.last.assetReturn) },
    { id: "withdraw-income", amount: next.last.withdrawnReturn },
    { id: "reinvest-assets", amount: next.last.reinvestedReturn },
    { id: "income-cashflow", amount: next.last.totalIncome },
    { id: "needs-cashflow", amount: settings.needs },
    { id: "wants-cashflow", amount: settings.wants },
    { id: "debt-cashflow", amount: next.last.debtInterest + next.last.minimumPayment },
    { id: "cashflow-graveyard", amount: next.last.consumedThisMonth },
    { id: "cashflow-check", amount: Math.max(0, next.last.cashflow) },
    { id: "check-debt", amount: next.last.debtPaydown },
    { id: "check-decision", amount: next.last.save + next.last.spend },
    { id: "decision-spend", amount: next.last.spend },
    { id: "decision-save", amount: next.last.save },
  ];
  const duration = 900 / Number($("#speed").value);
  const moving = flows
    .filter(({ amount }) => amount !== 0)
    .map((flow) => ({ ...flow, path: $(`#${flow.id}`) }));
  moving.forEach(({ amount, signed }) => {
    const pallet = document.createElementNS("http://www.w3.org/2000/svg", "g");
    const label = signed ? signedMoney(amount) : money(amount);
    const width = Math.max(54, label.length * 10 + 16);
    pallet.setAttribute("class", `money-pallet ${amount < 0 ? "loss" : ""}`);
    const body = document.createElementNS("http://www.w3.org/2000/svg", "rect");
    body.setAttribute("x", -width / 2); body.setAttribute("y", -13);
    body.setAttribute("width", width); body.setAttribute("height", 26); body.setAttribute("rx", 4);
    const text = document.createElementNS("http://www.w3.org/2000/svg", "text");
    text.setAttribute("text-anchor", "middle"); text.setAttribute("dominant-baseline", "middle");
    text.textContent = label;
    pallet.append(body, text);
    particles.append(pallet);
  });
  return new Promise((resolve) => {
    const started = performance.now();
    function frame(now) {
      const progress = Math.min(1, (now - started) / duration);
      [...particles.children].forEach((pallet, index) => {
        const item = moving[index];
        const length = item.path.getTotalLength();
        const point = item.path.getPointAtLength(progress * length);
        pallet.setAttribute("transform", `translate(${point.x} ${point.y})`);
      });
      if (progress < 1 && playing !== "stopped") animation = requestAnimationFrame(frame);
      else { particles.replaceChildren(); resolve(); }
    }
    animation = requestAnimationFrame(frame);
  });
}

async function advance() {
  if (playing === "stopped") return;
  const next = simulateMonth(state, settings);
  $("#status").textContent = `Moving month ${next.month} through the factory…`;
  setDisabled(true);
  await moveParticles(next);
  if (playing === "stopped") { setDisabled(false); return; }
  state = next;
  updateUI();
  $("#status").textContent = `Month ${state.month} complete.`;
  setDisabled(false);
}

function setDisabled(disabled) { ["#play", "#step", "#reset", "#reset-defaults"].forEach((id) => { $(id).disabled = disabled; }); }

async function play() {
  if (playing) return;
  playing = true;
  $("#play").textContent = "▶ Playing";
  while (playing === true) await advance();
  $("#play").textContent = "▶ Play";
}

$("#play").addEventListener("click", play);
$("#pause").addEventListener("click", () => { playing = "stopped"; $("#status").textContent = "Playback paused."; });
$("#step").addEventListener("click", async () => { if (!playing) { playing = true; await advance(); playing = false; } });
$("#reset").addEventListener("click", () => { playing = "stopped"; state = initialState(settings); updateUI(); $("#status").textContent = "Simulation reset with current controls."; });
$("#reset-defaults").addEventListener("click", () => { playing = "stopped"; settings = { ...DEFAULT_SETTINGS }; localStorage.removeItem(STORAGE_KEY); state = initialState(settings); updateInputs(); updateUI(); $("#status").textContent = "Default scenario restored."; });

wireInputs();
updateInputs();
updateUI();
