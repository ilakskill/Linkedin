// ==UserScript==
// @name         OpenAI Restore (Suite: Auto + List)
// @namespace    http://tampermonkey.net/
// @version      8.3
// @description  Restore ALL chats OR restore from a custom ID list
// @author       ilakskill
// @match        https://chatgpt.com/*
// @grant        none
// @run-at       document-start
// ==/UserScript==

(function() {
    'use strict';

    let capturedToken = null;
    const originalFetch = window.fetch;
    const DELAY_MS = 100; // Speed control (lower = faster, higher = safer)

    // --- 1. Deep Interceptor ---
    window.fetch = async function(...args) {
        const [resource, config] = args;
        let token = null;

        if (config && config.headers) {
            token = getHeader(config.headers, 'Authorization');
        }
        if (!token && resource instanceof Request) {
            try { token = resource.headers.get('Authorization'); } catch (e) {}
        }

        if (token && token.toLowerCase().startsWith('bearer') && !capturedToken) {
            capturedToken = token;
            console.log('%c[Deep Capture] Token Found!', 'color: #0f0; font-weight: bold;');
            updateUI(true);
        }

        return originalFetch.apply(this, args);
    };

    function getHeader(headers, key) {
        if (!headers) return null;
        if (headers instanceof Headers) return headers.get(key);
        const match = Object.keys(headers).find(k => k.toLowerCase() === key.toLowerCase());
        return match ? headers[match] : null;
    }

    const sleep = ms => new Promise(r => setTimeout(r, ms));

    // --- 2. Feature: Restore ALL ---
    async function startBulkRestore() {
        const btn = document.getElementById('deep-restore-btn');
        if (!confirm('Start restoring ALL archived chats?')) return;

        if (btn) {
            btn.disabled = true;
            btn.innerText = 'Scanning...';
        }

        try {
            let offset = 0;
            let allItems = [];
            let keepFetching = true;

            // Fetch Loop
            while (keepFetching) {
                const url = `https://chatgpt.com/backend-api/conversations?offset=${offset}&limit=50&order=updated&is_archived=true`;
                const res = await originalFetch(url, {
                    method: 'GET',
                    headers: { 'Authorization': capturedToken }
                });

                const data = await res.json();
                if (data.items && data.items.length > 0) {
                    allItems = [...allItems, ...data.items];
                    offset += data.items.length;
                    if (btn) btn.innerText = `Found ${allItems.length}...`;
                } else {
                    keepFetching = false;
                }
                await sleep(100);
            }

            if (allItems.length === 0) {
                alert('No archived chats found.');
                if (btn) btn.disabled = false;
                updateUI(true);
                return;
            }

            // Restore Loop
            let success = 0;
            for (let i = 0; i < allItems.length; i++) {
                if (btn) btn.innerText = `Restoring ${i + 1}/${allItems.length}`;
                const ok = await restoreSingleID(allItems[i].id);
                if (ok) success++;
                await sleep(DELAY_MS);
            }

            alert(`Complete! Restored ${success} conversations.`);
            location.reload();

        } catch (err) {
            alert('Error: ' + err.message);
            if (btn) btn.disabled = false;
        }
    }

    // --- 3. Feature: Restore ID List ---
    async function processIdList(rawInput) {
        // Clean input: finds anything looking like a UUID
        const ids = rawInput.split(/[^a-zA-Z0-9-]+/).filter(x => x.length > 20);

        if (ids.length === 0) {
            alert('No valid IDs found.');
            return;
        }

        if (!confirm(`Found ${ids.length} unique IDs. Restore them?`)) return;

        const statusDiv = document.getElementById('restore-status-text');
        let success = 0;

        for (let i = 0; i < ids.length; i++) {
            if(statusDiv) statusDiv.innerText = `Restoring ${i + 1}/${ids.length}: ${ids[i]}`;

            const ok = await restoreSingleID(ids[i]);
            if (ok) success++;
            await sleep(DELAY_MS);
        }

        alert(`Done! Restored ${success} out of ${ids.length} IDs.`);
        location.reload();
    }

    // --- Helper: Restore Single ---
    async function restoreSingleID(id) {
        const res = await originalFetch(`https://chatgpt.com/backend-api/conversation/${id}`, {
            method: 'PATCH',
            headers: {
                'Authorization': capturedToken,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ is_archived: false })
        });
        return res.ok;
    }

    // --- 4. Slash Command Listener ---
    function setupSlashListener() {
        document.addEventListener('keydown', (e) => {
            const target = e.target;
            // Target the main chat input
            if (target.id === 'prompt-textarea' && e.key === 'Enter' && !e.shiftKey) {
                const text = target.value.trim();

                if (text.startsWith('/')) {
                    const cmd = text.split(' ')[0].toLowerCase();
                    let handled = false;

                    if (cmd === '/restore') {
                        handled = true;
                        startBulkRestore();
                    } else if (cmd === '/restore-list') {
                        handled = true;
                        showInputModal();
                    } else if (cmd === '/token') {
                        handled = true;
                        alert(capturedToken ? 'Token Captured: YES' : 'Token Captured: NO (Click a chat to capture)');
                    } else if (cmd === '/restore-help') {
                        handled = true;
                        alert('Commands:\n/restore - Restore all archived chats\n/restore-list - Restore specific IDs\n/token - Check auth status');
                    }

                    if (handled) {
                        e.preventDefault();
                        e.stopPropagation();
                        // Clear input safely
                        target.value = '';
                        target.style.height = 'auto'; // Reset height
                    }
                }
            }
        }, true); // Capture phase to prevent other listeners
    }

    // --- 5. UI Functions ---
    function injectStyles() {
        const id = 'oai-restore-styles';
        if (document.getElementById(id)) return;
        const style = document.createElement('style');
        style.id = id;
        style.textContent = `
            .oai-widget {
                position: fixed; bottom: 20px; right: 20px; z-index: 99999;
                font-family: 'Söhne', 'Segoe UI', Roboto, sans-serif;
                display: flex; flex-direction: column; align-items: flex-end; gap: 8px;
            }
            .oai-panel {
                background: #202123; border: 1px solid #4d4d4f; border-radius: 8px;
                padding: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.5);
                display: flex; flex-direction: column; gap: 10px; min-width: 200px;
                transition: opacity 0.2s, transform 0.2s;
            }
            .oai-panel.hidden { opacity: 0; pointer-events: none; transform: translateY(10px); display: none; }
            
            .oai-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px; }
            .oai-title { color: #ececf1; font-weight: bold; font-size: 14px; }
            .oai-status { width: 8px; height: 8px; border-radius: 50%; background: #ef4444; }
            .oai-status.ready { background: #10a37f; box-shadow: 0 0 8px rgba(16,163,127,0.4); }
            
            .oai-btn {
                background: #343541; border: 1px solid #565869; color: #ececf1;
                padding: 8px 12px; border-radius: 4px; cursor: pointer; font-size: 12px;
                transition: all 0.2s; text-align: center;
            }
            .oai-btn:hover { background: #40414f; }
            .oai-btn:disabled { opacity: 0.6; cursor: not-allowed; }
            .oai-btn-primary { background: #10a37f; border-color: #10a37f; color: white; }
            .oai-btn-primary:hover { background: #1a7f64; }
            
            .oai-toggle {
                width: 32px; height: 32px; border-radius: 50%; background: #343541;
                border: 1px solid #565869; color: #ececf1; cursor: pointer;
                display: flex; align-items: center; justify-content: center;
            }
            .oai-toggle:hover { background: #40414f; }
            
            /* Modal Styles */
            .oai-modal-overlay {
                position: fixed; top: 0; left: 0; right: 0; bottom: 0;
                background: rgba(0,0,0,0.7); backdrop-filter: blur(2px);
                z-index: 100000; display: flex; align-items: center; justify-content: center;
            }
            .oai-modal {
                background: #202123; border: 1px solid #4d4d4f; border-radius: 8px;
                padding: 20px; width: 400px; max-width: 90%;
                box-shadow: 0 10px 25px rgba(0,0,0,0.5); color: #ececf1;
            }
            .oai-modal h3 { margin: 0 0 10px; font-size: 16px; }
            .oai-modal textarea {
                width: 100%; height: 100px; background: #343541; border: 1px solid #565869;
                color: #ececf1; padding: 8px; border-radius: 4px; resize: vertical; margin-bottom: 10px;
                font-family: monospace; font-size: 11px;
            }
            .oai-modal-actions { display: flex; justify-content: flex-end; gap: 8px; }
        `;
        document.head.appendChild(style);
    }

    function showInputModal() {
        if (document.getElementById('oai-input-modal')) return;
        injectStyles();

        const overlay = document.createElement('div');
        overlay.id = 'oai-input-modal';
        overlay.className = 'oai-modal-overlay';
        
        overlay.innerHTML = `
            <div class="oai-modal">
                <h3>Restore Specific IDs</h3>
                <p style="font-size: 12px; color: #acacbe; margin-bottom: 8px;">Paste IDs (JSON, comma-sep, or newlines):</p>
                <textarea id="id-input-area" placeholder="e.g. 5f4d3..."></textarea>
                <div id="restore-status-text" style="font-size: 11px; color: #10a37f; min-height: 15px; margin-bottom: 8px;"></div>
                <div class="oai-modal-actions">
                    <button class="oai-btn" id="modal-cancel">Cancel</button>
                    <button class="oai-btn oai-btn-primary" id="modal-run">Start Restore</button>
                </div>
            </div>
        `;
        document.body.appendChild(overlay);

        document.getElementById('modal-cancel').onclick = () => overlay.remove();
        document.getElementById('modal-run').onclick = async () => {
            const input = document.getElementById('id-input-area').value;
            await processIdList(input);
            overlay.remove();
        };
    }

    function updateUI(hasToken) {
        const btnAll = document.getElementById('deep-restore-btn');
        const statusDot = document.getElementById('oai-status-dot');
        const widget = document.getElementById('oai-widget');
        
        if (!widget && !btnAll) return;

        if (hasToken) {
            if (btnAll) {
                btnAll.innerHTML = `
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="vertical-align: text-bottom; margin-right: 4px;"><path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/></svg>
            Restore ALL Archived
            `;
                btnAll.disabled = false;
                btnAll.classList.add('oai-btn-primary');
            }
            if (statusDot) statusDot.classList.add('ready');
        } else {
            if (btnAll) {
                btnAll.innerText = 'Waiting for Token...';
                btnAll.disabled = true;
                btnAll.classList.remove('oai-btn-primary');
            }
            if (statusDot) statusDot.classList.remove('ready');
        }
    }

    function createUI() {
        if (document.getElementById('oai-widget')) return;
        injectStyles();

        const widget = document.createElement('div');
        widget.id = 'oai-widget';
        widget.className = 'oai-widget';
        
        // Minimized Toggle
        const toggle = document.createElement('div');
        toggle.className = 'oai-toggle';
        toggle.innerHTML = `<svg width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path d="M6 18L18 6M6 6l12 12"/></svg>`; // Open icon (X) because panel starts open
        toggle.title = "Toggle Restore Tools";
        
        // Panel
        const panel = document.createElement('div');
        panel.id = 'oai-panel';
        panel.className = 'oai-panel';
        
        panel.innerHTML = `
            <div class="oai-header">
                <span class="oai-title">Restore Tools</span>
                <div id="oai-status-dot" class="oai-status" title="Red: No Token, Green: Ready"></div>
            </div>
            <button id="deep-restore-btn" class="oai-btn" disabled>Waiting for Token...</button>
            <button id="oai-btn-restore-list" class="oai-btn">Restore from ID List</button>
        `;

        // Toggle Logic
        toggle.onclick = () => {
             if (panel.classList.contains('hidden')) {
                 panel.classList.remove('hidden');
                 toggle.innerHTML = `<svg width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path d="M6 18L18 6M6 6l12 12"/></svg>`;
             } else {
                 panel.classList.add('hidden');
                 toggle.innerHTML = `<svg width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path d="M12 5v14M5 12h14"/></svg>`; // Hamburger
             }
        };
        
        // Assemble
        widget.appendChild(panel);
        widget.appendChild(toggle);
        document.body.appendChild(widget);

        // Bind Events
        const btnRestore = document.getElementById('deep-restore-btn');
        if(btnRestore) btnRestore.onclick = startBulkRestore;
        
        const btnList = document.getElementById('oai-btn-restore-list');
        if(btnList) btnList.onclick = showInputModal;

        // Check for existing token
        if (capturedToken) updateUI(true);
    }

    // Init
    setupSlashListener();
    const observer = new MutationObserver(() => {
        if (document.body && !document.getElementById('oai-widget')) {
            createUI();
            observer.disconnect();
        }
    });
    observer.observe(document.documentElement, { childList: true });

    console.log('OpenAI Restore v8.3: UI & Commands Loaded');

})();
