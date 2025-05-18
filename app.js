/* ═══════════════════════════════════════════════
   Webcam Hardware Inspector — Application Logic
   ═══════════════════════════════════════════════ */

const $ = (id) => document.getElementById(id);

// ── DOM References ──────────────────────────────
const connectBtn    = $('connect-btn');
const retryBtn      = $('retry-btn');
const disconnectBtn = $('disconnect-btn');
const copyBtn       = $('copy-btn');
const hero          = $('hero');
const results       = $('results');
const footer        = $('footer');
const errorDisplay  = $('error-display');
const errorMessage  = $('error-message');
const video         = $('video-preview');

// ── State ───────────────────────────────────────
let stream  = null;
let allData = {};

// ── Event Listeners ─────────────────────────────
connectBtn.addEventListener('click', connect);
retryBtn.addEventListener('click', connect);
disconnectBtn.addEventListener('click', disconnect);
copyBtn.addEventListener('click', copyJSON);

// ═══════════════════════════════════════════════
//  Connection
// ═══════════════════════════════════════════════

async function connect() {
    connectBtn.classList.add('loading');
    errorDisplay.classList.add('hidden');

    try {
        // Request camera with highest possible resolution
        stream = await navigator.mediaDevices.getUserMedia({
            video: {
                width:  { ideal: 4096 },
                height: { ideal: 2160 },
                frameRate: { ideal: 60 }
            },
            audio: false
        });

        video.srcObject = stream;
        await video.play();

        // Transition UI
        hero.classList.add('connected');
        results.classList.remove('hidden');
        footer.classList.remove('hidden');

        // Gather everything
        await gatherAll();
    } catch (err) {
        showError(err);
    } finally {
        connectBtn.classList.remove('loading');
    }
}

function disconnect() {
    if (stream) {
        stream.getTracks().forEach(t => t.stop());
        stream = null;
    }
    video.srcObject = null;
    hero.classList.remove('connected');
    results.classList.add('hidden');
    footer.classList.add('hidden');
    allData = {};
}

function showError(err) {
    const msgs = {
        NotAllowedError:       'Camera permission was denied. Please allow camera access in your browser settings and try again.',
        NotFoundError:         'No camera device found. Please connect a webcam and try again.',
        NotReadableError:      'Camera is already in use by another application. Close it and try again.',
        OverconstrainedError:  `Camera constraint error on "${err.constraint}". Your camera may not support the requested settings.`,
        AbortError:            'Camera access was aborted. Please try again.',
        SecurityError:         'Camera access blocked by security policy. Ensure you\'re on HTTPS or localhost.',
    };
    const msg = msgs[err.name] || err.message || String(err);
    errorMessage.textContent = `${err.name}: ${msg}`;
    errorDisplay.classList.remove('hidden');
}

// ═══════════════════════════════════════════════
//  Data Gathering
// ═══════════════════════════════════════════════

async function gatherAll() {
    allData = {};
    const track = stream.getVideoTracks()[0];

    // Header info
    $('device-name').textContent = track.label || 'Unknown Camera';
    const s = track.getSettings();
    if (s.width && s.height) {
        $('res-badge').textContent = `${s.width}×${s.height}`;
    }

    // Gather all sections (order matters for UX)
    await displayDevices();
    displayCapabilities(track);
    displaySettings(track);
    await displayPhotoCapabilities(track);
    displaySupportedConstraints();
    displayStreamInfo(track);
    await probeResolutions();
    displayRawJSON();
}

// ═══════════════════════════════════════════════
//  1. Media Devices
// ═══════════════════════════════════════════════

async function displayDevices() {
    const devices = await navigator.mediaDevices.enumerateDevices();
    allData.devices = devices.map(d => ({
        kind:     d.kind,
        label:    d.label,
        deviceId: d.deviceId,
        groupId:  d.groupId
    }));

    const videoCount    = devices.filter(d => d.kind === 'videoinput').length;
    const audioInCount  = devices.filter(d => d.kind === 'audioinput').length;
    const audioOutCount = devices.filter(d => d.kind === 'audiooutput').length;

    $('dev-count').textContent = devices.length;
    $('device-count-label').textContent =
        `${videoCount} cam${videoCount !== 1 ? 's' : ''}, ` +
        `${audioInCount} mic${audioInCount !== 1 ? 's' : ''}, ` +
        `${audioOutCount} out${audioOutCount !== 1 ? 's' : ''}`;

    const container = $('devices-content');
    container.innerHTML = devices.map(d => {
        const typeClass = d.kind === 'videoinput' ? 'video'
                        : d.kind === 'audioinput' ? 'audio-in'
                        : 'audio-out';
        const typeLabel = d.kind === 'videoinput' ? '📷 Video Input'
                        : d.kind === 'audioinput' ? '🎤 Audio Input'
                        : '🔊 Audio Output';
        return `
            <div class="device-mini">
                <div class="dm-type ${typeClass}">${typeLabel}</div>
                <div class="dm-label">${d.label || 'Unnamed Device'}</div>
                <div class="dm-id">ID: ${d.deviceId || 'N/A'}</div>
                <div class="dm-id" style="margin-top:3px">Group: ${d.groupId || 'N/A'}</div>
            </div>`;
    }).join('');
}

// ═══════════════════════════════════════════════
//  2. Video Track Capabilities
// ═══════════════════════════════════════════════

function displayCapabilities(track) {
    const container = $('caps-content');

    if (!track.getCapabilities) {
        container.innerHTML = '<div class="no-data">getCapabilities() is not supported in this browser. Try Chrome or Edge.</div>';
        allData.capabilities = null;
        return;
    }

    const caps = track.getCapabilities();
    allData.capabilities = caps;

    // Organize by category
    const groups = {
        'Resolution & Frame Rate':  ['width', 'height', 'aspectRatio', 'frameRate'],
        'Camera Controls':          ['facingMode', 'resizeMode'],
        'Exposure & Light':         ['exposureMode', 'exposureCompensation', 'exposureTime', 'iso',
                                     'brightness', 'whiteBalanceMode', 'colorTemperature', 'torch'],
        'Focus':                    ['focusMode', 'focusDistance'],
        'Image Processing':         ['contrast', 'saturation', 'sharpness'],
        'Pan / Tilt / Zoom':        ['pan', 'tilt', 'zoom'],
        'Identifiers':              ['deviceId', 'groupId']
    };

    let html = '';
    const allGroupedKeys = new Set(Object.values(groups).flat());

    for (const [groupName, keys] of Object.entries(groups)) {
        const validKeys = keys.filter(k => caps[k] !== undefined);
        if (validKeys.length === 0) continue;

        html += `<div class="cap-group"><div class="cap-group-title">${groupName}</div>`;
        for (const key of validKeys) {
            html += renderCapability(key, caps[key]);
        }
        html += '</div>';
    }

    // Remaining ungrouped keys
    const remaining = Object.keys(caps).filter(k => !allGroupedKeys.has(k));
    if (remaining.length > 0) {
        html += '<div class="cap-group"><div class="cap-group-title">Other</div>';
        for (const key of remaining) {
            html += renderCapability(key, caps[key]);
        }
        html += '</div>';
    }

    container.innerHTML = html || '<div class="no-data">No capabilities reported by this device</div>';
}

function renderCapability(key, val) {
    if (val === undefined || val === null) return '';

    // Range (min/max object)
    if (typeof val === 'object' && !Array.isArray(val) && val.min !== undefined && val.max !== undefined) {
        const step = val.step ? ` (step: ${val.step})` : '';
        const maxRef = getMaxReference(key);
        const pct = maxRef > 0 ? Math.min(100, (val.max / maxRef) * 100) : 50;
        return `
            <div class="range-display">
                <div class="range-label">
                    <span class="rk">${fmtKey(key)}</span>
                    <span class="rv">${val.min} — ${val.max}${step}</span>
                </div>
                <div class="range-bar-wrap">
                    <div class="range-bar" style="width:${pct}%"></div>
                </div>
            </div>`;
    }

    // Array
    if (Array.isArray(val)) {
        return `
            <div class="data-row">
                <span class="data-key">${fmtKey(key)}</span>
                <span class="data-val purple">${val.length > 0 ? val.join(', ') : '(empty)'}</span>
            </div>`;
    }

    // Boolean
    if (typeof val === 'boolean') {
        return `
            <div class="data-row">
                <span class="data-key">${fmtKey(key)}</span>
                <span class="data-val ${val ? 'green' : 'orange'}">${val ? '✓ Yes' : '✗ No'}</span>
            </div>`;
    }

    // String / Number
    return `
        <div class="data-row">
            <span class="data-key">${fmtKey(key)}</span>
            <span class="data-val cyan">${truncate(String(val), 60)}</span>
        </div>`;
}

function getMaxReference(key) {
    return ({
        width: 7680, height: 4320, frameRate: 240, aspectRatio: 3,
        brightness: 255, contrast: 255, saturation: 255, sharpness: 255,
        zoom: 10, pan: 360, tilt: 180, exposureCompensation: 10,
        exposureTime: 10000, iso: 6400, colorTemperature: 10000,
        focusDistance: 1000
    })[key] || 1000;
}

// ═══════════════════════════════════════════════
//  3. Current Track Settings
// ═══════════════════════════════════════════════

function displaySettings(track) {
    const settings = track.getSettings();
    allData.settings = settings;

    const container = $('settings-content');
    let html = '';

    for (const [key, val] of Object.entries(settings)) {
        let cls = 'cyan';
        let display = val;

        if (typeof val === 'boolean') {
            cls = val ? 'green' : 'orange';
            display = val ? '✓ Yes' : '✗ No';
        } else if (typeof val === 'string') {
            cls = 'purple';
        }

        html += `
            <div class="data-row">
                <span class="data-key">${fmtKey(key)}</span>
                <span class="data-val ${cls}">${truncate(String(display), 60)}</span>
            </div>`;
    }

    container.innerHTML = html || '<div class="no-data">No settings available</div>';
}

// ═══════════════════════════════════════════════
//  4. ImageCapture / Photo Capabilities
// ═══════════════════════════════════════════════

async function displayPhotoCapabilities(track) {
    const container = $('photo-content');

    if (typeof ImageCapture === 'undefined') {
        container.innerHTML = '<div class="no-data">ImageCapture API is not supported in this browser. Use Chrome or Edge for full hardware details.</div>';
        allData.photoCapabilities = null;
        return;
    }

    try {
        const ic = new ImageCapture(track);

        // Photo Capabilities
        let html = '';
        try {
            const photoCaps = await ic.getPhotoCapabilities();
            allData.photoCapabilities = {};

            html += '<div class="cap-group"><div class="cap-group-title">Photo Capabilities</div>';

            // Extract all properties from the prototype
            const proto = Object.getPrototypeOf(photoCaps);
            const propNames = Object.getOwnPropertyNames(proto).filter(n => n !== 'constructor');

            for (const name of propNames) {
                try {
                    const val = photoCaps[name];
                    if (val !== undefined) {
                        allData.photoCapabilities[name] = val;
                        html += renderCapability(name, val);
                    }
                } catch (e) { /* skip inaccessible props */ }
            }

            // Also check direct properties
            for (const [key, val] of Object.entries(photoCaps)) {
                if (!allData.photoCapabilities[key] && val !== undefined) {
                    allData.photoCapabilities[key] = val;
                    html += renderCapability(key, val);
                }
            }
            html += '</div>';
        } catch (e) {
            html += `<div class="no-data">getPhotoCapabilities() error: ${e.message}</div>`;
        }

        // Photo Settings
        try {
            const photoSettings = await ic.getPhotoSettings();
            allData.photoSettings = photoSettings;

            html += '<div class="cap-group"><div class="cap-group-title">Current Photo Settings</div>';
            for (const [key, val] of Object.entries(photoSettings)) {
                html += renderCapability(key, val);
            }
            html += '</div>';
        } catch (e) {
            html += `<div class="no-data">getPhotoSettings() error: ${e.message}</div>`;
        }

        // Advanced camera controls from track capabilities
        if (track.getCapabilities) {
            const trackCaps = track.getCapabilities();
            const advancedProps = [
                'brightness', 'colorTemperature', 'contrast',
                'exposureCompensation', 'exposureMode', 'exposureTime',
                'focusDistance', 'focusMode', 'iso',
                'pan', 'saturation', 'sharpness',
                'tilt', 'torch', 'whiteBalanceMode', 'zoom'
            ];

            const available = advancedProps.filter(p => trackCaps[p] !== undefined);
            if (available.length > 0) {
                html += '<div class="cap-group"><div class="cap-group-title">Advanced Camera Controls (via Track)</div>';
                for (const prop of available) {
                    html += renderCapability(prop, trackCaps[prop]);
                }
                html += '</div>';
            }
        }

        container.innerHTML = html || '<div class="no-data">No photo capabilities reported</div>';

    } catch (err) {
        container.innerHTML = `<div class="no-data">ImageCapture error: ${err.message}</div>`;
        allData.photoCapabilities = { error: err.message };
    }
}

// ═══════════════════════════════════════════════
//  5. Supported Constraints
// ═══════════════════════════════════════════════

function displaySupportedConstraints() {
    const supported = navigator.mediaDevices.getSupportedConstraints();
    allData.supportedConstraints = supported;

    const container = $('supported-content');
    const entries = Object.entries(supported);
    const yes = entries.filter(([, v]) => v);
    const no  = entries.filter(([, v]) => !v);

    let html = '<div class="constraint-grid">';
    for (const [key] of yes) {
        html += `<div class="constraint-chip supported">✓ ${fmtKey(key)}</div>`;
    }
    for (const [key] of no) {
        html += `<div class="constraint-chip unsupported">✗ ${fmtKey(key)}</div>`;
    }
    html += '</div>';

    html += `<div style="margin-top:14px;font-size:0.78rem;color:var(--text3)">
        ${yes.length} supported · ${no.length} unsupported · ${entries.length} total constraints checked
    </div>`;

    container.innerHTML = html;
}

// ═══════════════════════════════════════════════
//  6. Stream & Track Info
// ═══════════════════════════════════════════════

function displayStreamInfo(track) {
    const info = {
        'Stream ID':      stream.id,
        'Stream Active':  stream.active,
        'Track ID':       track.id,
        'Track Label':    track.label,
        'Track Kind':     track.kind,
        'Track Enabled':  track.enabled,
        'Track Muted':    track.muted,
        'Ready State':    track.readyState,
        'Content Hint':   track.contentHint || '(none)',
        'Video Tracks':   stream.getVideoTracks().length,
        'Audio Tracks':   stream.getAudioTracks().length,
    };

    allData.streamInfo = info;

    const container = $('stream-content');
    let html = '';

    for (const [key, val] of Object.entries(info)) {
        let cls = 'cyan';
        let display = val;
        if (typeof val === 'boolean') {
            cls = val ? 'green' : 'orange';
            display = val ? '✓ Yes' : '✗ No';
        }
        html += `
            <div class="data-row">
                <span class="data-key">${key}</span>
                <span class="data-val ${cls}">${display}</span>
            </div>`;
    }

    container.innerHTML = html;
}

// ═══════════════════════════════════════════════
//  7. Resolution Probe
// ═══════════════════════════════════════════════

async function probeResolutions() {
    const container = $('resolutions-content');
    const probeTag  = $('res-probe-tag');

    // Show loading
    container.innerHTML =
        '<div class="shimmer"></div>'.repeat(3) +
        '<div class="shimmer" style="width:60%"></div>';

    const resolutions = [
        [320, 240],   [352, 288],   [424, 240],   [480, 360],
        [640, 360],   [640, 480],   [800, 448],   [800, 600],
        [848, 480],   [960, 540],   [960, 720],   [1024, 576],
        [1024, 768],  [1280, 720],  [1280, 960],  [1280, 1024],
        [1440, 1080], [1600, 896],  [1600, 900],  [1600, 1200],
        [1920, 1080], [1920, 1440], [2048, 1536], [2560, 1440],
        [2560, 1920], [3200, 1800], [3840, 2160], [4096, 2160],
        [5120, 2880], [7680, 4320]
    ];

    const track    = stream.getVideoTracks()[0];
    const deviceId = track.getSettings().deviceId;
    const results  = [];

    for (let i = 0; i < resolutions.length; i++) {
        const [w, h] = resolutions[i];
        probeTag.textContent = `Testing ${i + 1}/${resolutions.length}...`;

        try {
            const testStream = await navigator.mediaDevices.getUserMedia({
                video: {
                    deviceId:  { exact: deviceId },
                    width:     { exact: w },
                    height:    { exact: h }
                }
            });

            const ts = testStream.getVideoTracks()[0].getSettings();
            const match = ts.width === w && ts.height === h;
            results.push({ w, h, actualW: ts.width, actualH: ts.height, match, supported: true });
            testStream.getTracks().forEach(t => t.stop());
        } catch (e) {
            results.push({ w, h, match: false, supported: false });
        }
    }

    allData.resolutionProbe = results;
    probeTag.textContent = 'Complete';

    const matched = results.filter(r => r.match);

    let html = `<div class="res-summary">${matched.length} of ${resolutions.length} resolutions confirmed as natively supported</div>`;
    html += '<div class="res-grid">';

    for (const r of results) {
        const cls   = r.match ? 'ok' : 'fail';
        const label = `${r.w}×${r.h}`;
        html += `
            <div class="res-item ${cls}">
                <span class="res-dot"></span>
                <span>${label}</span>
            </div>`;
    }

    html += '</div>';
    container.innerHTML = html;

    // Update raw JSON after probing
    displayRawJSON();
}

// ═══════════════════════════════════════════════
//  8. Raw JSON Export
// ═══════════════════════════════════════════════

function displayRawJSON() {
    $('raw-json').textContent = JSON.stringify(allData, null, 2);
}

async function copyJSON() {
    const text = JSON.stringify(allData, null, 2);
    try {
        await navigator.clipboard.writeText(text);
    } catch {
        // Fallback for non-HTTPS
        const ta = document.createElement('textarea');
        ta.value = text;
        ta.style.position = 'fixed';
        ta.style.left = '-9999px';
        document.body.appendChild(ta);
        ta.select();
        document.execCommand('copy');
        document.body.removeChild(ta);
    }
    copyBtn.textContent = '✓ Copied!';
    copyBtn.classList.add('copied');
    setTimeout(() => {
        copyBtn.textContent = '📋 Copy';
        copyBtn.classList.remove('copied');
    }, 2000);
}

// ═══════════════════════════════════════════════
//  Helpers
// ═══════════════════════════════════════════════

function fmtKey(key) {
    return key
        .replace(/([A-Z])/g, ' $1')
        .replace(/^./, s => s.toUpperCase())
        .replace(/([a-z])(\d)/g, '$1 $2')
        .trim();
}

function truncate(str, len) {
    return str.length > len ? str.slice(0, len) + '…' : str;
}
