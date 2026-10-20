// Call only from node_repl with the initialized Computer Use `sky` client.
// Observes interactive windows; the coordinator separately owns the batch queue.
const linesOf = state => String(state?.accessibility?.tree ?? '').split('\n');

export function desktopReadiness(state) {
    const lines = linesOf(state);
    const ready = lines.some(line => /\bReady prompt\s*$/i.test(line));
    const inputAtPrompt = String(state?.accessibility?.document_text ?? '').trim() === '>>'
        || lines.some(line => /Command Window Value:\s*>>\s*$/.test(line));
    const busy = lines.some(line => /\bBusy prompt\s*$/i.test(line));
    return { ready, inputAtPrompt, busy, idle: ready && inputAtPrompt && !busy };
}

function demoReadiness(state) {
    const lines = linesOf(state);
    const buttons = lines.filter(line => /(?:кнопка|button)/i.test(line));
    const isDisabled = labels => {
        const matches = buttons.filter(line => new RegExp(`\\s(?:${labels})(?:\\s+ID:.*)?$`, 'i').test(line));
        return matches.length === 1 && /\(disabled\)/i.test(matches[0]);
    };
    const pauseDisabled = isDisabled('Пауза|Pause');
    const stopDisabled = isDisabled('Остановить|Stop');
    return { pauseDisabled, stopDisabled, idle: pauseDisabled && stopDisabled };
}

export async function inspectMatlabQueue(sky, { bringToFront = false } = {}) {
    const observedAtUtc = new Date().toISOString();
    if (bringToFront !== true) {
        return {
            status: 'not-observed', mode: 'background', observedAtUtc, uiAccessed: false,
            reason: 'Foreground inspection is opt-in; use coordinator-owned worker identity, completion reports and queue ownership for ordinary batch checks'
        };
    }
    const windows = await sky.list_windows();
    const matlab = windows.filter(window => /matlab\.exe/i.test(String(window.app)));
    const desktops = matlab.filter(window => window.title === 'MATLAB R2025b');
    if (desktops.length !== 1) {
        return { status: 'unknown', observedAtUtc, reason: 'Expected exactly one MATLAB desktop', desktopCount: desktops.length };
    }
    const desktop = await sky.get_window({ id: desktops[0].id, app: desktops[0].app });
    const observe = async window => {
        await sky.activate_window({ window });
        let state = await sky.get_window_state({ window, include_screenshot: true, include_text: true });
        // MATLAB's web accessibility tree can lag behind a successful activation.
        // Retry a frame-only observation once; never infer idle from the title.
        if (!state.accessibility?.document_text && linesOf(state).length < 25) {
            await new Promise(resolve => setTimeout(resolve, 750));
            state = await sky.get_window_state({ window, include_screenshot: true, include_text: true });
        }
        return state;
    };
    const first = desktopReadiness(await observe(desktop));
    if (!first.idle) {
        return { status: first.busy ? 'busy' : 'unknown', observedAtUtc, desktop: { window: desktop, ...first }, reason: 'Current Ready prompt and empty command input were not both confirmed' };
    }
    const demos = [];
    for (const candidate of matlab.filter(window => window.title === 'NB-IoT — локальный запуск')) {
        const window = await sky.get_window({ id: candidate.id, app: candidate.app });
        demos.push({ window, ...demoReadiness(await observe(window)) });
    }
    // Return with the desktop visible and check it again after observing demos.
    const final = desktopReadiness(await observe(desktop));
    const idle = final.idle && demos.every(demo => demo.idle);
    return {
        status: idle ? 'idle' : 'unknown', observedAtUtc,
        scope: 'interactive MATLAB windows; coordinator must separately verify no owned batch worker is active',
        desktop: { window: desktop, ...final }, demos,
        reason: idle ? 'Ready prompt and current >> input confirmed; demo Pause/Stop disabled' : 'Interactive readiness was not fully confirmed'
    };
}
