// ============================================================
//  AX_Farming | script.js
// ============================================================

'use strict';

// ─── DOM ─────────────────────────────────────────────────────
const hudEl      = document.getElementById('farming-hud');
const hudPanel   = document.querySelector('.hud-panel');
const plantLabel = document.getElementById('plant-label');
const stateBadge = document.getElementById('state-badge');
const stateLabel = document.getElementById('state-label');
const stateIcon  = document.getElementById('state-icon');

const barGrowth  = document.getElementById('bar-growth');
const barWater   = document.getElementById('bar-water');
const barFert    = document.getElementById('bar-fert');
const barHealth  = document.getElementById('bar-health');

const valGrowth  = document.getElementById('val-growth');
const valWater   = document.getElementById('val-water');
const valFert    = document.getElementById('val-fert');
const valHealth  = document.getElementById('val-health');

const btnClose   = document.getElementById('btn-close');
const btnWater   = document.getElementById('btn-water');
const btnFert    = document.getElementById('btn-fert');
const btnHarvest = document.getElementById('btn-harvest');
const btnRemove  = document.getElementById('btn-remove');
const toastEl    = document.getElementById('hud-toast');
const hudTimer   = document.getElementById('hud-timer');
const timerLabel = document.getElementById('timer-label');
const timerValue = document.getElementById('timer-value');

// ─── ESTADO LOCAL ────────────────────────────────────────────
let currentPlant   = null;
let timerInterval  = null;
// Cuándo (Date.now()) se abrió el HUD, para compensar el tiempo transcurrido localmente
let timerOpenedAt  = 0;
// Valores del servidor al abrir/actualizar
let timerGrowSnapshot = 0;  // growTimer en segundos (creciendo)
let timerRotSnapshot  = 0;  // rotTimer  en segundos (pudrición)
let timerGrowthPct    = 0;  // growth % al momento del snapshot

// ─── ESTADOS ─────────────────────────────────────────────────
const STATE_CONFIG = {
    growing: { label: 'Creciendo',          cls: 'state-growing', icon: 'fa-solid fa-arrow-up'              },
    ready:   { label: 'Lista para cosechar', cls: 'state-ready',   icon: 'fa-solid fa-check'                 },
    wilting: { label: 'Marchitando',         cls: 'state-wilting', icon: 'fa-solid fa-triangle-exclamation'  },
    rotten:  { label: 'Podrida',             cls: 'state-rotten',  icon: 'fa-solid fa-skull'                 },
    dead:    { label: 'Muerta',              cls: 'state-dead',    icon: 'fa-solid fa-xmark'                 },
};

// ─── HELPERS ─────────────────────────────────────────────────
function setBar(barEl, valEl, value) {
    const pct = Math.min(100, Math.max(0, Math.round(value)));
    barEl.style.width  = pct + '%';
    valEl.textContent  = pct + '%';
    pct < 25 ? barEl.classList.add('low') : barEl.classList.remove('low');
}

function pad(n) { return String(Math.floor(n)).padStart(2, '0'); }

function formatSecs(totalSeconds) {
    const s = Math.max(0, Math.floor(totalSeconds));
    const m = Math.floor(s / 60);
    const r = s % 60;
    return `${pad(m)}:${pad(r)}`;
}

// ─── TIMER ───────────────────────────────────────────────────
// growTime en config es en MINUTOS — lo convertimos a segundos para la cuenta regresiva.
// El servidor envía growTimer (segundos transcurridos) y rotTimer (segundos transcurridos en pudrición).
// El cliente compensa el tiempo que pasa entre snapshots sumando (Date.now() - timerOpenedAt).

const ROT_TIMER_MAX_SECS = 30 * 60; // 30 min — debe coincidir con Config.RotTimer

function stopTimer() {
    if (timerInterval) { clearInterval(timerInterval); timerInterval = null; }
    timerValue.textContent = '--:--';
    hudTimer.className     = 'hud-timer';
    timerLabel.textContent = 'TIEMPO';
}

function startTimer(plant) {
    stopTimer();

    const state = plant.state || 'growing';
    if (state === 'dead') return;

    // Snapshot del servidor
    timerGrowSnapshot = (plant.growTimer  || 0);   // segundos transcurridos creciendo
    timerRotSnapshot  = (plant.rotTimer   || 0);   // segundos transcurridos pudriendo
    timerGrowthPct    = (plant.growth     || 0);
    timerOpenedAt     = Date.now();

    // growTime del plant (minutos) enviado desde Lua via Config.Plants[plantType].growTime
    const growTimeSecs = (plant.growTimeSecs || 600); // default 10 min si no llega

    function tick() {
        const localElapsed = (Date.now() - timerOpenedAt) / 1000; // segundos desde que se abrió

        if (timerGrowthPct < 100) {
            // ── CUENTA REGRESIVA DE CRECIMIENTO ──────────────────
            const totalElapsed = timerGrowSnapshot + localElapsed;
            const remaining    = Math.max(0, growTimeSecs - totalElapsed);

            hudTimer.className     = 'hud-timer timer-growing';
            timerLabel.textContent = 'MADURA EN';
            timerValue.textContent = formatSecs(remaining);
        } else {
            // ── CUENTA REGRESIVA DE DESCOMPOSICIÓN ───────────────
            const totalRot    = timerRotSnapshot + localElapsed;
            const remaining   = Math.max(0, ROT_TIMER_MAX_SECS - totalRot);
            const isUrgent    = remaining < 300; // menos de 5 minutos

            hudTimer.className     = 'hud-timer timer-rot' + (isUrgent ? ' urgent' : '');
            timerLabel.textContent = 'CADUCA EN';
            timerValue.textContent = formatSecs(remaining);
        }
    }

    tick();
    timerInterval = setInterval(tick, 1000);
}

// ─── RENDER ──────────────────────────────────────────────────
function renderPlant(plant) {
    if (!plant) return;
    currentPlant = plant;

    // Título: usar label del servidor (enviado desde Config.Plants[plantType].label)
    plantLabel.textContent = (plant.label || plant.plantType || 'PLANTA').toUpperCase();

    const state = plant.state || 'growing';
    const cfg   = STATE_CONFIG[state] || STATE_CONFIG.growing;

    stateBadge.className   = 'state-badge ' + cfg.cls;
    stateLabel.textContent = cfg.label.toUpperCase();
    stateIcon.className    = cfg.icon + ' state-icon-dot';

    setBar(barGrowth, valGrowth, plant.growth      || 0);
    setBar(barWater,  valWater,  plant.water        || 0);
    setBar(barFert,   valFert,   plant.fertilizer   || 0);
    setBar(barHealth, valHealth, plant.health       || 0);

    // Reiniciar timer con datos frescos del servidor
    // (startTimer usa timerOpenedAt = Date.now() así no se desincroniza)
    if (state !== 'dead') {
        startTimer(plant);
    } else {
        stopTimer();
    }

    const canCare    = state !== 'dead' && state !== 'rotten';
    const canHarvest = state === 'ready' || state === 'wilting' || state === 'rotten';

    btnWater.disabled   = !canCare;
    btnFert.disabled    = !canCare;
    btnHarvest.disabled = !canHarvest;
    btnRemove.disabled  = false;
}

// ─── ABRIR / CERRAR HUD ──────────────────────────────────────
function openHUD(plant) {
    renderPlant(plant);
    hudEl.classList.remove('hud-hidden');
    hudEl.classList.add('hud-visible');
}

function closeHUD() {
    hudEl.classList.remove('hud-visible');
    hudEl.classList.add('hud-hidden');
    currentPlant = null;
    stopTimer();
    fetch('https://AX_Farming/closeHUD', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({}),
    });
}

// ─── TOAST ───────────────────────────────────────────────────
let toastTimer = null;
function showToast(msg, type) {
    toastEl.textContent = msg;
    toastEl.className   = 'hud-toast toast-visible' + (type ? ' toast-' + type : '');
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toastEl.classList.remove('toast-visible'), 2500);
}

// ─── LISTENER NUI ────────────────────────────────────────────
window.addEventListener('message', function(e) {
    const d = e.data;
    if (!d || !d.action) return;
    switch (d.action) {
        case 'openHUD':
            openHUD(d.plant);
            break;
        case 'updatePlant':
            // Actualizar datos y reiniciar timer con snapshot fresco
            if (d.plant) renderPlant(d.plant);
            break;
        case 'closeHUD':
            hudEl.classList.remove('hud-visible');
            hudEl.classList.add('hud-hidden');
            currentPlant = null;
            stopTimer();
            break;
    }
});

// ─── ENVIAR ACCIÓN AL LUA ────────────────────────────────────
function sendAction(action) {
    if (!currentPlant) return;
    fetch('https://AX_Farming/' + action, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ plantId: currentPlant.id }),
    });
}

// ─── BOTONES ─────────────────────────────────────────────────
btnClose.addEventListener('click',   () => closeHUD());
btnWater.addEventListener('click',   () => { if (!btnWater.disabled)   sendAction('waterPlant');    });
btnFert.addEventListener('click',    () => { if (!btnFert.disabled)    sendAction('fertilizePlant'); });
btnHarvest.addEventListener('click', () => { if (!btnHarvest.disabled) sendAction('harvestPlant');  });
btnRemove.addEventListener('click',  () => { if (!btnRemove.disabled)  sendAction('removePlant');   });

// ─── ESC para cerrar ─────────────────────────────────────────
document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape' && hudEl.classList.contains('hud-visible')) {
        closeHUD();
    }
});

// ─── Click fuera del panel para cerrar ───────────────────────
hudEl.addEventListener('click', function(e) {
    if (!hudPanel.contains(e.target)) {
        closeHUD();
    }
});