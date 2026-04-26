/* =============================================
   AX_Farming — script.js
   ============================================= */

'use strict';

// =============================================
//  ESTADO
// =============================================

let currentPlantId = null;
let currentFertMax = 6;

// =============================================
//  ELEMENTOS
// =============================================

const overlay       = document.getElementById('overlay');
const plantMenu     = document.getElementById('plant-menu');
const confirmModal  = document.getElementById('confirm-modal');

const plantLabel    = document.getElementById('plant-label');
const stageBadge    = document.getElementById('stage-badge');

const growthBar     = document.getElementById('growth-bar');
const growthVal     = document.getElementById('growth-val');
const waterBar      = document.getElementById('water-bar');
const waterVal      = document.getElementById('water-val');
const fertPips      = document.getElementById('fert-pips');
const fertVal       = document.getElementById('fert-val');
const harvestAlert  = document.getElementById('harvest-alert');

const btnClose      = document.getElementById('btn-close');
const btnWater      = document.getElementById('btn-water');
const btnFertilize  = document.getElementById('btn-fertilize');
const btnHarvest    = document.getElementById('btn-harvest');
const btnDestroy    = document.getElementById('btn-destroy');
const confirmYes    = document.getElementById('confirm-yes');
const confirmNo     = document.getElementById('confirm-no');

// =============================================
//  HELPERS
// =============================================

function getStageName(stage) {
    const names = { 1: 'ETAPA 1 — BROTE', 2: 'ETAPA 2 — CRECIENDO', 3: 'ETAPA 3 — MADURA' };
    return names[stage] || 'ETAPA 1';
}

function buildFertPips(current, max) {
    fertPips.innerHTML = '';
    for (let i = 0; i < max; i++) {
        const pip = document.createElement('div');
        pip.className = 'fert-pip' + (i < current ? ' active' : '');
        fertPips.appendChild(pip);
    }
}

function formatTime(seconds) {
    if (seconds <= 0) return '00:00';
    const m = Math.floor(seconds / 60);
    const s = Math.floor(seconds % 60);
    return String(m).padStart(2, '0') + ':' + String(s).padStart(2, '0');
}

function updateStats(data) {
    const growth     = Math.round(data.growth || 0);
    const water      = Math.round(data.water  || 0);
    const fertilizer = data.fertilizer || 0;
    const stage      = data.stage || 1;
    const fertMax    = data.fertMax !== undefined ? data.fertMax : currentFertMax;
    const isDead     = data.is_dead || false;
    const timeMode   = data.timeMode || 'growth';
    const timeRem    = data.timeRemaining || 0;

    currentFertMax = fertMax;

    growthBar.style.width = growth + '%';
    growthVal.textContent = growth + '%';
    waterBar.style.width  = water + '%';
    waterVal.textContent  = water + '%';
    fertVal.textContent   = fertilizer + '/' + fertMax;
    buildFertPips(fertilizer, fertMax);
    stageBadge.textContent = getStageName(stage);

    // Tiempo
    const timeRow = document.getElementById('time-row');
    const timeIcon = document.getElementById('time-icon');
    const timeLabel = document.getElementById('time-label');
    const timeValue = document.getElementById('time-value');

    if (isDead) {
        timeRow.className = 'time-row time-dead';
        timeIcon.className = 'fas fa-skull time-icon-el';
        timeLabel.textContent = 'PLANTA MUERTA';
        timeValue.textContent = '';
        harvestAlert.classList.add('hidden');
        btnHarvest.disabled    = true;
        btnWater.disabled      = true;
        btnFertilize.disabled  = true;
    } else if (timeMode === 'rot') {
        timeRow.className = 'time-row time-rot';
        timeIcon.className = 'fas fa-hourglass-end time-icon-el';
        timeLabel.textContent = 'SE PUDRE EN';
        timeValue.textContent = formatTime(timeRem);
        harvestAlert.classList.remove('hidden');
        btnHarvest.disabled   = false;
        btnWater.disabled     = false;
        btnFertilize.disabled = (fertilizer >= fertMax);
    } else if (timeMode === 'death') {
        timeRow.className = 'time-row time-death';
        timeIcon.className = 'fas fa-droplet-slash time-icon-el';
        timeLabel.textContent = 'MUERE EN';
        timeValue.textContent = formatTime(timeRem);
        harvestAlert.classList.add('hidden');
        btnHarvest.disabled   = true;
        btnWater.disabled     = false;
        btnFertilize.disabled = true;
    } else {
        timeRow.className = 'time-row time-growth';
        timeIcon.className = 'fas fa-clock time-icon-el';
        timeLabel.textContent = 'MADURA EN';
        timeValue.textContent = formatTime(timeRem);
        harvestAlert.classList.add('hidden');
        btnHarvest.disabled   = (growth < 100);
        btnWater.disabled     = false;
        btnFertilize.disabled = (fertilizer >= fertMax);
    }
}

// =============================================
//  ABRIR / CERRAR MENÚ
// =============================================

function openMenu(data) {
    currentPlantId = data.plantId;

    plantLabel.textContent = (data.label || 'PLANTA').toUpperCase();

    updateStats({
        growth:     data.growth,
        water:      data.water,
        fertilizer: data.fertilizer,
        fertMax:    data.fertMax,
        stage:      data.stage,
    });

    overlay.classList.remove('hidden');
    plantMenu.classList.remove('hidden');

    // Forzar reflow para que la transición funcione
    void plantMenu.offsetWidth;
    plantMenu.classList.add('open');
    plantMenu.classList.remove('closing');
}

function closeMenu(callback) {
    plantMenu.classList.add('closing');
    plantMenu.classList.remove('open');

    setTimeout(() => {
        plantMenu.classList.add('hidden');
        overlay.classList.add('hidden');
        plantMenu.classList.remove('closing');
        currentPlantId = null;
        if (callback) callback();
    }, 220);
}

// =============================================
//  MODAL CONFIRMAR DESTRUIR
// =============================================

function openConfirm() {
    confirmModal.classList.remove('hidden');
}

function closeConfirm() {
    confirmModal.classList.add('hidden');
}

// =============================================
//  ENVIAR ACCIÓN AL CLIENTE LUA
// =============================================

function sendAction(action, extra) {
    const payload = Object.assign({ type: action, plantId: currentPlantId }, extra || {});
    fetch('https://AX_Farming/' + action, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify(payload),
    });
}

function sendClose() {
    fetch('https://AX_Farming/closeMenu', {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({}),
    });
}

// =============================================
//  EVENTOS DE BOTONES
// =============================================

btnClose.addEventListener('click', () => {
    closeMenu(() => sendClose());
});

overlay.addEventListener('click', () => {
    closeMenu(() => sendClose());
});

btnWater.addEventListener('click', () => {
    if (!currentPlantId) return;
    const pid = currentPlantId;
    closeMenu(() => {
        fetch('https://AX_Farming/waterPlant', {
            method:  'POST',
            headers: { 'Content-Type': 'application/json' },
            body:    JSON.stringify({ plantId: pid }),
        });
    });
});

btnFertilize.addEventListener('click', () => {
    if (!currentPlantId || btnFertilize.disabled) return;
    const pid = currentPlantId;
    closeMenu(() => {
        fetch('https://AX_Farming/fertilizePlant', {
            method:  'POST',
            headers: { 'Content-Type': 'application/json' },
            body:    JSON.stringify({ plantId: pid }),
        });
    });
});

btnHarvest.addEventListener('click', () => {
    if (!currentPlantId || btnHarvest.disabled) return;
    const pid = currentPlantId;
    closeMenu(() => {
        fetch('https://AX_Farming/harvestPlant', {
            method:  'POST',
            headers: { 'Content-Type': 'application/json' },
            body:    JSON.stringify({ plantId: pid }),
        });
    });
});

btnDestroy.addEventListener('click', () => {
    if (!currentPlantId) return;
    openConfirm();
});

confirmYes.addEventListener('click', () => {
    closeConfirm();
    const pid = currentPlantId;
    closeMenu(() => {
        fetch('https://AX_Farming/destroyPlantMenu', {
            method:  'POST',
            headers: { 'Content-Type': 'application/json' },
            body:    JSON.stringify({ plantId: pid }),
        });
    });
});

confirmNo.addEventListener('click', () => {
    closeConfirm();
});

// =============================================
//  MENSAJES DESDE LUA
// =============================================

window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data || !data.type) return;

    switch (data.type) {

        case 'open':
            openMenu(data);
            break;

        case 'close':
            if (!plantMenu.classList.contains('hidden')) {
                closeMenu();
            }
            break;

        case 'updatePlant':
            if (currentPlantId !== null) {
                updateStats({
                    growth:     data.growth,
                    water:      data.water,
                    fertilizer: data.fertilizer,
                    stage:      data.stage,
                    fertMax:    currentFertMax,
                });
            }
            break;
    }
});