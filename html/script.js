// ============================================================
//  AX_Farming | script.js
// ============================================================
'use strict';

// ── DOM ──────────────────────────────────────────────────────
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

// ── ESTADO ───────────────────────────────────────────────────
let currentPlant = null;

// ── TIMER ────────────────────────────────────────────────────
// Guardamos los datos del servidor en variables globales del timer.
// El setInterval corre SIEMPRE mientras el HUD está abierto.
// Al recibir datos nuevos del servidor solo actualizamos las variables —
// el intervalo NO se reinicia, por lo que el contador no salta.

const ROT_MAX_SECS  = 30 * 60;   // debe coincidir con Config.RotTimer (en minutos)

let timerInterval   = null;
let tGrowElapsed    = 0;   // growTimer del servidor (segs transcurridos creciendo)
let tRotElapsed     = 0;   // rotTimer del servidor (segs transcurridos pudriendo)
let tGrowthPct      = 0;   // growth% del servidor
let tGrowMax        = 600; // growTimeSecs del servidor
let tRefAt          = 0;   // Date.now() cuando se recibió el último dato del servidor

function pad2(n) { return String(Math.max(0,Math.floor(n))).padStart(2,'0'); }
function fmtSecs(s) {
    s = Math.max(0, Math.floor(s));
    return pad2(Math.floor(s/60)) + ':' + pad2(s%60);
}

function timerTick() {
    // segundos transcurridos en el cliente desde el último sync del servidor
    const clientDelta = (Date.now() - tRefAt) / 1000;

    if (tGrowthPct < 100) {
        // Cuenta regresiva de crecimiento
        const elapsed   = tGrowElapsed + clientDelta;
        const remaining = Math.max(0, tGrowMax - elapsed);
        hudTimer.className     = 'hud-timer timer-growing';
        timerLabel.textContent = 'MADURA EN';
        timerValue.textContent = fmtSecs(remaining);
    } else {
        // Cuenta regresiva de descomposición
        const elapsed   = tRotElapsed + clientDelta;
        const remaining = Math.max(0, ROT_MAX_SECS - elapsed);
        hudTimer.className     = 'hud-timer timer-rot' + (remaining < 300 ? ' urgent' : '');
        timerLabel.textContent = 'CADUCA EN';
        timerValue.textContent = fmtSecs(remaining);
    }
}

// Actualizar datos del servidor SIN reiniciar el intervalo
function syncTimerData(plant) {
    tGrowElapsed = plant.growTimer    || 0;
    tRotElapsed  = plant.rotTimer     || 0;
    tGrowthPct   = plant.growth       || 0;
    tGrowMax     = plant.growTimeSecs || 600;
    tRefAt       = Date.now();
    // Si el interval ya corre no hacemos nada más — el tick usará los datos nuevos
}

function startTimer(plant) {
    syncTimerData(plant);
    if (!timerInterval) {
        timerInterval = setInterval(timerTick, 1000);
    }
    timerTick(); // tick inmediato para no esperar 1 segundo
}

function stopTimer() {
    if (timerInterval) { clearInterval(timerInterval); timerInterval = null; }
    timerValue.textContent = '--:--';
    timerLabel.textContent = 'TIEMPO';
    hudTimer.className     = 'hud-timer';
}

// ── ESTADOS ──────────────────────────────────────────────────
const STATES = {
    growing: { label:'Creciendo',          cls:'state-growing', icon:'fa-solid fa-arrow-up'             },
    ready:   { label:'Lista para cosechar', cls:'state-ready',   icon:'fa-solid fa-check'                },
    wilting: { label:'Marchitando',         cls:'state-wilting', icon:'fa-solid fa-triangle-exclamation' },
    rotten:  { label:'Podrida',             cls:'state-rotten',  icon:'fa-solid fa-skull'                },
    dead:    { label:'Muerta',              cls:'state-dead',    icon:'fa-solid fa-xmark'                },
};

// ── RENDER ───────────────────────────────────────────────────
function setBar(barEl, valEl, v) {
    const p = Math.min(100, Math.max(0, Math.round(v)));
    barEl.style.width = p + '%';
    valEl.textContent = p + '%';
    p < 25 ? barEl.classList.add('low') : barEl.classList.remove('low');
}

function renderPlant(plant) {
    if (!plant) return;
    currentPlant = plant;

    plantLabel.textContent = (plant.label || plant.plantType || 'PLANTA').toUpperCase();

    const state = plant.state || 'growing';
    const sc    = STATES[state] || STATES.growing;
    stateBadge.className   = 'state-badge ' + sc.cls;
    stateLabel.textContent = sc.label.toUpperCase();
    stateIcon.className    = sc.icon + ' state-icon-dot';

    setBar(barGrowth, valGrowth, plant.growth     || 0);
    setBar(barWater,  valWater,  plant.water       || 0);
    setBar(barFert,   valFert,   plant.fertilizer  || 0);
    setBar(barHealth, valHealth, plant.health      || 0);

    // Timer: syncTimerData actualiza variables, el tick recalcula en el próximo ciclo
    // Si el interval no está corriendo (HUD cerrado) lo iniciamos
    if (state !== 'dead') {
        startTimer(plant);   // startTimer es seguro llamarlo múltiples veces
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

// ── ABRIR / CERRAR ───────────────────────────────────────────
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
    }).catch(() => {});
}

// ── MENSAJE DESDE LUA ────────────────────────────────────────
window.addEventListener('message', function(e) {
    const d = e.data;
    if (!d || !d.action) return;
    switch (d.action) {
        case 'openHUD':
            openHUD(d.plant);
            break;
        case 'updatePlant':
            if (d.plant) {
                // Solo actualizar datos — no tocar visibilidad ni reiniciar timer
                renderPlant(d.plant);
            }
            break;
        case 'closeHUD':
            hudEl.classList.remove('hud-visible');
            hudEl.classList.add('hud-hidden');
            currentPlant = null;
            stopTimer();
            break;
    }
});

// ── ENVIAR ACCIÓN ────────────────────────────────────────────
function sendAction(action) {
    if (!currentPlant) return;
    fetch('https://AX_Farming/' + action, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ plantId: currentPlant.id }),
    }).catch(() => {});
}

// ── BOTONES ──────────────────────────────────────────────────
btnClose.addEventListener('click', closeHUD);

btnWater.addEventListener('click', function() {
    if (!btnWater.disabled) sendAction('waterPlant');
});
btnFert.addEventListener('click', function() {
    if (!btnFert.disabled) sendAction('fertilizePlant');
});
btnHarvest.addEventListener('click', function() {
    if (!btnHarvest.disabled) sendAction('harvestPlant');
});
btnRemove.addEventListener('click', function() {
    if (!btnRemove.disabled) sendAction('removePlant');
});

// ── ESC cierra ───────────────────────────────────────────────
document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape' && hudEl.classList.contains('hud-visible')) {
        closeHUD();
    }
});

// ── Click fuera del panel cierra ─────────────────────────────
hudEl.addEventListener('click', function(e) {
    // Solo cerrar si el click fue en el overlay, no dentro del panel
    if (!hudPanel.contains(e.target)) {
        closeHUD();
    }
});