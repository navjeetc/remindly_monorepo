// Voice Reminders - Session-based authentication version
class VoiceRemindersApp {
    constructor() {
        this.reminders = [];
        this.settings = this.loadSettings();
        this.announcedReminders = this.loadAnnouncedList();
        this.synth = window.speechSynthesis;
        this.checkInterval = null;
        this.speechInitialized = false;
        this.voiceUnlockPrompted = false;
        this.voiceUnlocked = this.hasPriorUserActivation();
        this.voiceUnlockListener = null;
        // Only surface the 🔊 prompt once speech has actually been refused, so
        // desktop users who never hit the limit don't see a control they don't need.
        this.voiceBlocked = false;
        this.voiceUnlockInFlight = null;
        // Reminders whose speech was refused, kept as id -> text so they can be
        // spoken once voice unlocks. Separate from announcedReminders, which is
        // persisted to localStorage and also gates the browser notification.
        //
        // Persisted too: announcedReminders is written the moment a reminder is
        // announced, so if this queue were in-memory only, a reload before the
        // user unlocks would lose the text while the id stays marked announced —
        // the reminder would never speak again. Starting every browser locked
        // makes that reachable outside iOS, so it has to survive a reload.
        this.pendingVoiceAnnouncements = this.loadPendingVoiceAnnouncements();
        // Whether this.reminders reflects a completed fetch. Replay needs it to
        // tell "already acknowledged" from "not fetched yet" — those look
        // identical in an empty array, and treating the second as the first
        // would discard the queue.
        this.remindersLoaded = false;
        this.replayInFlight = false;
    }

    init() {
        this.setupEventListeners();
        this.initializeSpeech();
        this.loadReminders();
        this.startPeriodicCheck();
        this.updateStatus('online');
        this.maybeShowVoiceUnlockPrompt();
        this.setupVoiceUnlockListeners();
    }
    
    initializeSpeech() {
        // Simple initialization - just mark as ready
        if (this.synth) {
            this.speechInitialized = true;
            console.log('✅ Speech synthesis initialized');
        }
    }

    setupEventListeners() {
        console.log('Setting up event listeners...');
        
        // Test Audio button
        const testAudioBtn = document.getElementById('testAudioBtn');
        console.log('Test Audio button found:', !!testAudioBtn);
        if (testAudioBtn) {
            testAudioBtn.addEventListener('click', () => {
                console.log('🔊 Test Audio button clicked!');
                this.speak('This is a test of the voice announcement system. If you can hear this, audio is working correctly.');
            });
        }
        
        // Refresh button
        const refreshBtn = document.getElementById('refreshBtn');
        if (refreshBtn) {
            refreshBtn.addEventListener('click', () => this.loadReminders());
        }
        
        // Clear Announced button
        const clearAnnouncedBtn = document.getElementById('clearAnnouncedBtn');
        if (clearAnnouncedBtn) {
            clearAnnouncedBtn.addEventListener('click', () => {
                this.announcedReminders.clear();
                this.saveAnnouncedList();
                console.log('✅ Cleared announced reminders list');
                alert('Announced reminders list cleared! Reminders will now announce again.');
                this.loadReminders();
            });
        }
        
        // Settings (optional - only if elements exist)
        const settingsBtn = document.getElementById('settingsBtn');
        if (settingsBtn) {
            settingsBtn.addEventListener('click', () => this.openSettings());
        }
        
        const closeSettings = document.getElementById('closeSettings');
        if (closeSettings) {
            closeSettings.addEventListener('click', () => this.closeSettings());
        }
        
        const saveSettings = document.getElementById('saveSettings');
        if (saveSettings) {
            saveSettings.addEventListener('click', () => this.saveSettings());
        }
        
        const resetSettings = document.getElementById('resetSettings');
        if (resetSettings) {
            resetSettings.addEventListener('click', () => this.resetSettings());
        }
        
        const clearAnnounced = document.getElementById('clearAnnounced');
        if (clearAnnounced) {
            clearAnnounced.addEventListener('click', () => this.clearAnnouncedList());
        }
        
        const testVoiceBtn = document.getElementById('testVoiceBtn');
        if (testVoiceBtn) {
            testVoiceBtn.addEventListener('click', () => this.testVoice());
        }
        
        const requestNotificationBtn = document.getElementById('requestNotificationBtn');
        if (requestNotificationBtn) {
            requestNotificationBtn.addEventListener('click', () => this.requestNotificationPermission());
        }

        const enableVoiceBtn = document.getElementById('enableVoiceBtn');
        if (enableVoiceBtn) {
            enableVoiceBtn.addEventListener('click', () => this.handleVoiceUnlock());
        }

        // Voice settings sliders (optional)
        const voiceRate = document.getElementById('voiceRate');
        if (voiceRate) {
            voiceRate.addEventListener('input', (e) => {
                const rateValue = document.getElementById('voiceRateValue');
                if (rateValue) rateValue.textContent = e.target.value;
            });
        }
        
        const voiceVolume = document.getElementById('voiceVolume');
        if (voiceVolume) {
            voiceVolume.addEventListener('input', (e) => {
                const volumeValue = document.getElementById('voiceVolumeValue');
                if (volumeValue) volumeValue.textContent = e.target.value;
            });
        }
    }

    async loadReminders() {
        try {
            this.updateStatus('loading');
            const response = await fetch('/voice_reminders/today', {
                credentials: 'include' // Important for session cookies
            });
            
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            
            const data = await response.json();
            this.reminders = data;
            this.remindersLoaded = true;
            this.renderReminders();
            this.updateStats();
            this.announceNewReminders();
            this.updateStatus('online');

            // Retry a replay that was deferred because reminder state was unknown
            // when the user unlocked. The periodic poll calls through here, so a
            // deferred queue is picked up on the next cycle rather than stranded.
            if (this.voiceUnlocked && this.pendingVoiceAnnouncements.size > 0) {
                this.replayPendingVoiceAnnouncements();
            }
        } catch (error) {
            console.error('Error loading reminders:', error);
            this.updateStatus('offline');
            this.showError('Failed to load reminders');
        }
    }

    renderReminders() {
        const container = document.getElementById('remindersList');
        const emptyState = document.getElementById('emptyState');
        
        if (this.reminders.length === 0) {
            container.style.display = 'none';
            emptyState.style.display = 'block';
            return;
        }
        
        container.style.display = 'block';
        emptyState.style.display = 'none';
        
        container.innerHTML = this.reminders.map(reminder => this.renderReminderCard(reminder)).join('');
        
        // Add event listeners to action buttons
        this.reminders.forEach(reminder => {
            const ackBtn = document.getElementById(`ack-${reminder.id}`);
            const snoozeBtn = document.getElementById(`snooze-${reminder.id}`);
            const skipBtn = document.getElementById(`skip-${reminder.id}`);
            
            if (ackBtn) ackBtn.addEventListener('click', () => this.acknowledgeReminder(reminder.id));
            if (snoozeBtn) snoozeBtn.addEventListener('click', () => this.snoozeReminder(reminder.id));
            if (skipBtn) skipBtn.addEventListener('click', () => this.skipReminder(reminder.id));
        });
    }

    renderReminderCard(reminder) {
        // Parse the time and display in local timezone
        const scheduledDate = new Date(reminder.scheduled_at);
        const time = scheduledDate.toLocaleTimeString('en-US', { 
            hour: 'numeric', 
            minute: '2-digit',
            hour12: true
        });
        
        const isCompleted = reminder.acknowledged_at;
        const bgColor = isCompleted ? 'bg-green-50' : 'bg-yellow-50';
        const borderColor = isCompleted ? 'border-green-300' : 'border-yellow-300';
        
        return `
            <div class="p-6 rounded-xl border-4 ${borderColor} ${bgColor} shadow-lg">
                <div class="flex justify-between items-start mb-4">
                    <h3 class="text-3xl font-bold text-gray-900">${reminder.title}</h3>
                    <span class="text-2xl font-semibold text-gray-700 bg-white px-4 py-2 rounded-lg">${time}</span>
                </div>
                ${reminder.description ? `<p class="text-xl text-gray-700 mb-4">${reminder.description}</p>` : ''}
                <div class="flex items-center gap-4">
                    ${!isCompleted ? `
                        <button id="ack-${reminder.id}" class="flex-1 inline-flex items-center justify-center px-6 py-4 border-2 border-transparent shadow-lg text-xl font-bold rounded-xl text-white bg-green-600 hover:bg-green-700 focus:ring-4 focus:ring-green-300" title="Mark as done">
                            ✓ Done
                        </button>
                        <button id="snooze-${reminder.id}" class="flex-1 inline-flex items-center justify-center px-6 py-4 border-2 border-gray-400 shadow-lg text-xl font-bold rounded-xl text-gray-800 bg-white hover:bg-gray-100 focus:ring-4 focus:ring-gray-300" title="Snooze for 10 minutes">
                            ⏰ Snooze
                        </button>
                    ` : `
                        <span class="inline-flex items-center px-6 py-4 text-2xl font-bold text-green-700">
                            ✓ Completed
                        </span>
                    `}
                </div>
            </div>
        `;
    }

    updateStats() {
        const total = this.reminders.length;
        const pending = this.reminders.filter(r => !r.acknowledged_at).length;
        const completed = total - pending;
        
        // Only update elements that exist (simplified view only has pendingCount)
        const pendingEl = document.getElementById('pendingCount');
        if (pendingEl) pendingEl.textContent = pending;
        
        const totalEl = document.getElementById('totalCount');
        if (totalEl) totalEl.textContent = total;
        
        const completedEl = document.getElementById('completedCount');
        if (completedEl) completedEl.textContent = completed;
    }

    playReminder(reminder) {
        if (!this.settings.voiceEnabled) {
            alert('Voice announcements are disabled. Enable them in settings.');
            return;
        }
        
        // Only announce the title, not the notes
        const text = `Reminder: ${reminder.title}`;
        this.speak(text);
    }

    // reminderId lets a blocked announcement be replayed once the user unlocks;
    // without it a refused announcement is lost for good, because
    // announcedReminders has already been written to localStorage.
    speak(text, reminderId = null) {
        if (!this.synth) return;
        if (!this.voiceUnlocked) {
            console.log('❌ Voice locked - waiting for unlock gesture');
            this.onVoiceBlocked(reminderId, text);
            return;
        }

        const utterance = new SpeechSynthesisUtterance(text);
        utterance.rate = parseFloat(this.settings.voiceRate);
        utterance.volume = parseFloat(this.settings.voiceVolume);

        utterance.onerror = (e) => {
            console.error('❌ Speech error:', e.error);
            // The browser refused for lack of a user gesture. Re-lock so the next
            // touch or click re-arms voice, and queue this reminder for replay.
            if (e.error === 'not-allowed') {
                this.voiceUnlocked = false;
                this.onVoiceBlocked(reminderId, text);
            }
        };

        // Chrome/Chromium workaround: Cancel everything and wait
        this.synth.cancel();
        
        setTimeout(() => {
            // Resume before speaking (Chrome workaround)
            this.synth.resume();
            
            // Speak the utterance
            this.synth.speak(utterance);
            
            // Resume again after speak (Chrome workaround)
            setTimeout(() => {
                this.synth.resume();
            }, 100);
        }, 500); // Longer delay for Chrome
    }

    async acknowledgeReminder(reminderId) {
        try {
            console.log('Acknowledging reminder:', reminderId);
            const response = await fetch('/acknowledgements', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
                },
                credentials: 'include',
                body: JSON.stringify({
                    occurrence_id: reminderId,
                    kind: 'taken'
                })
            });
            
            console.log('Acknowledge response:', response.status);
            if (response.ok) {
                console.log('Reloading reminders...');
                await this.loadReminders();
                console.log('Reminders reloaded');
            } else {
                console.error('Failed to acknowledge reminder:', response.status);
            }
        } catch (error) {
            console.error('Error acknowledging reminder:', error);
        }
    }

    async snoozeReminder(reminderId) {
        try {
            const response = await fetch('/acknowledgements/snooze', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
                },
                credentials: 'include',
                body: JSON.stringify({
                    occurrence_id: reminderId,
                    minutes: 10
                })
            });
            
            if (response.ok) {
                await this.loadReminders();
            } else {
                console.error('Failed to snooze reminder:', response.status);
            }
        } catch (error) {
            console.error('Error snoozing reminder:', error);
        }
    }
    
    skipReminder(reminderId) {
        // Add to announced list so it won't be announced again
        this.announcedReminders.add(reminderId);
        this.saveAnnouncedList();
        
        // Remove from display
        this.reminders = this.reminders.filter(r => r.id !== reminderId);
        this.renderReminders();
        this.updateStats();
    }

    announceNewReminders() {
        console.log('🔊 Checking for announcements...');
        console.log('  Voice enabled:', this.settings.voiceEnabled);
        
        if (!this.settings.voiceEnabled) {
            console.log('  ❌ Voice disabled, skipping announcements');
            return;
        }
        
        const now = new Date();
        console.log('  Current time:', now.toLocaleTimeString());
        console.log('  Total reminders:', this.reminders.length);
        console.log('  Already announced:', Array.from(this.announcedReminders));
        
        // Only announce reminders whose scheduled time has passed
        const dueReminders = this.reminders.filter(r => {
            const scheduledTime = new Date(r.scheduled_at);
            const isDue = scheduledTime <= now;
            const isAcknowledged = r.acknowledged_at;
            const wasAnnounced = this.announcedReminders.has(r.id);
            
            console.log(`  Reminder ${r.id} (${r.title}):`, {
                scheduled_at_raw: r.scheduled_at,
                scheduledTime: scheduledTime.toString(),
                scheduledTime_ms: scheduledTime.getTime(),
                now_ms: now.getTime(),
                diff_seconds: (now.getTime() - scheduledTime.getTime()) / 1000,
                isDue,
                isAcknowledged,
                wasAnnounced
            });
            
            return !isAcknowledged && !wasAnnounced && isDue;
        });
        
        console.log('  Due reminders to announce:', dueReminders.length);
        
        dueReminders.forEach(reminder => {
            if (this.shouldAnnounce()) {
                console.log('  📢 Announcing:', reminder.title);
                // Only announce the title
                const text = `Reminder: ${reminder.title}`;
                this.speak(text, reminder.id);
                this.announcedReminders.add(reminder.id);
                this.saveAnnouncedList();
                
                if (this.settings.notificationsEnabled) {
                    this.showNotification(reminder);
                }
            }
        });
    }

    shouldAnnounce() {
        if (!this.settings.quietHoursEnabled) return true;
        
        const now = new Date();
        const currentTime = now.getHours() * 60 + now.getMinutes();
        
        const [startHour, startMin] = this.settings.quietHoursStart.split(':').map(Number);
        const [endHour, endMin] = this.settings.quietHoursEnd.split(':').map(Number);
        
        const startTime = startHour * 60 + startMin;
        const endTime = endHour * 60 + endMin;
        
        if (startTime < endTime) {
            return currentTime < startTime || currentTime >= endTime;
        } else {
            return currentTime >= endTime && currentTime < startTime;
        }
    }

    showNotification(reminder) {
        if ('Notification' in window && Notification.permission === 'granted') {
            new Notification('Remindly', {
                body: `${reminder.title}\n${reminder.description || ''}`,
                icon: '/icon.png'
            });
        }
    }

    startPeriodicCheck() {
        const interval = (this.settings.checkInterval || 10) * 1000;
        this.checkInterval = setInterval(() => this.loadReminders(), interval);
    }

    updateStatus(status) {
        const indicator = document.getElementById('statusIndicator');
        if (indicator) {
            indicator.className = `status-indicator ${status}`;
        }
    }

    showError(message) {
        // Could add a toast notification here
        console.error(message);
    }

    // Settings methods
    openSettings() {
        const settingsModal = document.getElementById('settingsModal');
        if (settingsModal) {
            settingsModal.style.display = 'flex';
            this.loadSettingsToUI();
        } else {
            this.showError("Settings modal element not found.");
        }
    }

    async handleVoiceUnlock({ silent = false } = {}) {
        if (this.voiceUnlocked) {
            if (!silent) this.showBanner('Voice is already enabled', { autoHideMs: 3000 });
            this.maybeShowVoiceUnlockPrompt();
            return true;
        }
        if (!this.synth) {
            if (!silent) this.showBanner('Voice is not available on this device');
            return false;
        }
        // One tap fires both touchend and click, and the 🔊 button adds a third
        // handler. Each attempt calls synth.cancel(), so a later one aborts an
        // earlier one and reports failure while the first was working. Share a
        // single in-flight attempt instead.
        if (this.voiceUnlockInFlight) {
            return this.voiceUnlockInFlight;
        }

        this.voiceUnlockInFlight = (async () => {
            try {
                await this.performVoiceUnlockSequence();
                this.voiceUnlocked = true;
                this.voiceUnlockPrompted = false;
                this.voiceBlocked = false;
                this.hideBanner();
                if (!silent) this.showBanner('Voice announcements enabled', { autoHideMs: 3000 });
                this.removeVoiceUnlockListeners();
                this.replayPendingVoiceAnnouncements();
            } catch (error) {
                console.error('❌ Failed to unlock voice:', error);
                if (!silent) this.showBanner('Could not enable voice — tap anywhere to try again');
                this.setupVoiceUnlockListeners();
            } finally {
                this.voiceUnlockInFlight = null;
            }
            this.maybeShowVoiceUnlockPrompt();
            return this.voiceUnlocked;
        })();

        return this.voiceUnlockInFlight;
    }

    performVoiceUnlockSequence() {
        return new Promise((resolve, reject) => {
            try {
                const utterance = new SpeechSynthesisUtterance('Voice enabled');
                utterance.volume = 0.01;
                utterance.rate = 0.5;
                let settled = false;
                const finish = () => {
                    if (!settled) {
                        settled = true;
                        resolve();
                    }
                };
                utterance.onend = finish;
                utterance.onerror = (event) => {
                    if (!settled) {
                        settled = true;
                        reject(event.error || event);
                    }
                };
                this.synth.cancel();
                this.synth.speak(utterance);
                setTimeout(finish, 750);
            } catch (error) {
                reject(error);
            }
        });
    }

    maybeShowVoiceUnlockPrompt() {
        const button = document.getElementById('enableVoiceBtn');
        if (!button) return;
        // iOS always needs the button up front. Elsewhere it only appears once
        // speech has actually been refused, so it isn't UI noise for everyone else.
        const needsPrompt = !this.voiceUnlocked && (this.isIOSDevice() || this.voiceBlocked);
        button.style.display = needsPrompt ? 'inline-flex' : 'none';
    }

    // Every modern browser gates speechSynthesis behind a user gesture, not just
    // iOS — Chrome's autoplay policy rejects speak() with 'not-allowed' on a page
    // the user has never interacted with. A senior's browser left open on a desk,
    // or reopened after a restart and not touched, hits exactly that. So voice
    // starts locked everywhere and `voiceUnlocked` is the single gate.
    //
    // A gesture that already happened is enough for desktop browsers, so those
    // sessions unlock invisibly. iOS is stricter: it wants speech initiated from
    // the gesture itself, so it always runs the explicit unlock sequence.
    hasPriorUserActivation() {
        if (this.isIOSDevice()) return false;
        return navigator.userActivation?.hasBeenActive === true;
    }

    // Speech was refused for lack of a gesture. Re-arm the unlock listeners, show
    // the 🔊 fallback, and queue the announcement for replay.
    //
    // The reminder is queued rather than removed from announcedReminders: that set
    // is persisted to localStorage and also gates the browser notification, so
    // clearing it would re-fire the notification on every poll and survive a
    // reload as if the reminder had never been announced.
    onVoiceBlocked(reminderId = null, text = null) {
        this.voiceBlocked = true;
        if (reminderId !== null && text) {
            this.pendingVoiceAnnouncements.set(reminderId, text);
            this.savePendingVoiceAnnouncements();
        }
        this.setupVoiceUnlockListeners();
        this.maybeShowVoiceUnlockPrompt();
        if (!this.voiceUnlockPrompted) {
            this.showBanner('Tap anywhere to enable voice announcements');
            this.voiceUnlockPrompted = true;
        }
    }

    // Speak anything refused while voice was locked, driven by the unlock rather
    // than the polling loop — announcedReminders already contains these, so the
    // loop will never revisit them.
    async replayPendingVoiceAnnouncements() {
        if (this.pendingVoiceAnnouncements.size === 0) return;
        // Guards the whole drain, not just the fetch. The snapshot and clear below
        // happen to be synchronous today, so concurrent callers cannot currently
        // duplicate speech — but that is an unstated invariant, and inserting an
        // await between them would silently reintroduce the race. loadReminders()
        // also calls back into this method on success, which this covers.
        if (this.replayInFlight) return;
        this.replayInFlight = true;

        try {
            // The queue is only safe to drain once reminder state is known. On a
            // fresh page the unlock tap routinely lands before the first fetch
            // returns, and an empty this.reminders would make every entry look "no
            // longer pending" — discarding it permanently, since announcedReminders
            // blocks any re-announcement. Wait for the fetch, and keep the queue if
            // it fails.
            if (!this.remindersLoaded) {
                await this.loadReminders();
                if (!this.remindersLoaded) {
                    console.log('⏸️  Deferring replay — reminders not loaded yet');
                    return;
                }
            }

            const pending = [...this.pendingVoiceAnnouncements.entries()];
            this.pendingVoiceAnnouncements.clear();
            this.savePendingVoiceAnnouncements();

            pending.forEach(([reminderId, text]) => {
                // Skip anything acknowledged or snoozed while voice was locked — a
                // senior who already took their medication shouldn't be told to.
                //
                // An absent reminder counts as no longer pending:
                // today_reminders_json returns only pending occurrences, so acting
                // on one removes it from this.reminders entirely. Requiring
                // `current` to exist would speak it anyway — and the usual case is
                // the worst one, since the tap on Done is often the same gesture
                // that unlocks voice.
                const current = this.reminders.find(r => r.id === reminderId);
                if (!current || current.acknowledged_at) {
                    console.log(`⏭️  Not replaying ${reminderId} — no longer pending`);
                    return;
                }
                console.log(`🔁 Replaying blocked announcement: ${text}`);
                this.speak(text, reminderId);
            });
        } finally {
            this.replayInFlight = false;
        }
    }

    // Non-blocking notice. alert() would itself need dismissing before anything
    // else could happen, which is the opposite of what a senior needs here.
    //
    // role=status + aria-live announces it to a screen reader, which matters
    // rather a lot when the message is "voice is not working". An existing banner
    // is updated in place rather than ignored, so a later message is not lost
    // behind an earlier one.
    showBanner(message, { autoHideMs = null } = {}) {
        let banner = document.getElementById('voiceUnlockBanner');

        if (!banner) {
            banner = document.createElement('div');
            banner.id = 'voiceUnlockBanner';
            banner.setAttribute('role', 'status');
            banner.setAttribute('aria-live', 'assertive');
            banner.style.cssText = 'position:fixed;top:0;left:0;right:0;z-index:9999;' +
                'background:#facc15;color:#1f2937;font-size:1.25rem;font-weight:700;' +
                'text-align:center;padding:1rem;box-shadow:0 2px 8px rgba(0,0,0,.2)';
            document.body.appendChild(banner);
        }

        banner.textContent = message;

        if (this.bannerTimeout) {
            clearTimeout(this.bannerTimeout);
            this.bannerTimeout = null;
        }
        if (autoHideMs) {
            this.bannerTimeout = setTimeout(() => this.hideBanner(), autoHideMs);
        }
    }

    hideBanner() {
        if (this.bannerTimeout) {
            clearTimeout(this.bannerTimeout);
            this.bannerTimeout = null;
        }
        document.getElementById('voiceUnlockBanner')?.remove();
    }

    isIOSDevice() {
        const platform = navigator.platform || '';
        const userAgent = navigator.userAgent || navigator.vendor || window.opera || '';
        const iPadOS13Up = navigator.maxTouchPoints && navigator.maxTouchPoints > 2 && /MacIntel/.test(platform);
        const iOSDevice = /iPad|iPhone|iPod/.test(userAgent);
        return iOSDevice || iPadOS13Up;
    }

    setupVoiceUnlockListeners() {
        if (this.voiceUnlocked) {
            this.removeVoiceUnlockListeners();
            return;
        }
        if (this.voiceUnlockListener) return;

        const handler = () => {
            if (this.voiceUnlocked) {
                this.removeVoiceUnlockListeners();
                return;
            }
            this.handleVoiceUnlock({ silent: true });
        };

        this.voiceUnlockListener = handler;
        ['touchend', 'click'].forEach(evt => document.addEventListener(evt, handler, { passive: true }));
    }

    removeVoiceUnlockListeners() {
        if (!this.voiceUnlockListener) return;
        ['touchend', 'click'].forEach(evt => document.removeEventListener(evt, this.voiceUnlockListener));
        this.voiceUnlockListener = null;
    }

    closeSettings() {
        const settingsModal = document.getElementById('settingsModal');
        if (settingsModal) {
            settingsModal.style.display = 'none';
        }
    }

    loadSettingsToUI() {
        const voiceEnabled = document.getElementById('voiceEnabled');
        if (voiceEnabled) voiceEnabled.checked = this.settings.voiceEnabled;
        
        const voiceRate = document.getElementById('voiceRate');
        if (voiceRate) voiceRate.value = this.settings.voiceRate;
        
        const voiceRateValue = document.getElementById('voiceRateValue');
        if (voiceRateValue) voiceRateValue.textContent = this.settings.voiceRate;
        
        const voiceVolume = document.getElementById('voiceVolume');
        if (voiceVolume) voiceVolume.value = this.settings.voiceVolume;
        
        const voiceVolumeValue = document.getElementById('voiceVolumeValue');
        if (voiceVolumeValue) voiceVolumeValue.textContent = this.settings.voiceVolume;
        
        const notificationsEnabled = document.getElementById('notificationsEnabled');
        if (notificationsEnabled) notificationsEnabled.checked = this.settings.notificationsEnabled;
        
        const notificationSound = document.getElementById('notificationSound');
        if (notificationSound) notificationSound.checked = this.settings.notificationSound;
        
        const checkInterval = document.getElementById('checkInterval');
        if (checkInterval) checkInterval.value = this.settings.checkInterval;
        
        const quietHoursEnabled = document.getElementById('quietHoursEnabled');
        if (quietHoursEnabled) quietHoursEnabled.checked = this.settings.quietHoursEnabled;
        
        const quietHoursStart = document.getElementById('quietHoursStart');
        if (quietHoursStart) quietHoursStart.value = this.settings.quietHoursStart;
        
        const quietHoursEnd = document.getElementById('quietHoursEnd');
        if (quietHoursEnd) quietHoursEnd.value = this.settings.quietHoursEnd;
    }

    saveSettings() {
        const voiceEnabled = document.getElementById('voiceEnabled');
        const voiceRate = document.getElementById('voiceRate');
        const voiceVolume = document.getElementById('voiceVolume');
        const notificationsEnabled = document.getElementById('notificationsEnabled');
        const notificationSound = document.getElementById('notificationSound');
        const checkInterval = document.getElementById('checkInterval');
        const quietHoursEnabled = document.getElementById('quietHoursEnabled');
        const quietHoursStart = document.getElementById('quietHoursStart');
        const quietHoursEnd = document.getElementById('quietHoursEnd');
        
        // Only save if elements exist
        if (voiceEnabled && voiceRate && voiceVolume && notificationsEnabled && 
            notificationSound && checkInterval && quietHoursEnabled && 
            quietHoursStart && quietHoursEnd) {
            
            this.settings = {
                voiceEnabled: voiceEnabled.checked,
                voiceRate: voiceRate.value,
                voiceVolume: voiceVolume.value,
                notificationsEnabled: notificationsEnabled.checked,
                notificationSound: notificationSound.checked,
                checkInterval: parseInt(checkInterval.value),
                quietHoursEnabled: quietHoursEnabled.checked,
                quietHoursStart: quietHoursStart.value,
                quietHoursEnd: quietHoursEnd.value
            };
            
            localStorage.setItem('voiceRemindersSettings', JSON.stringify(this.settings));
            this.closeSettings();
        } else {
            this.showError('Settings form elements not found.');
        }
        
        // Restart periodic check with new interval
        clearInterval(this.checkInterval);
        this.startPeriodicCheck();
    }

    resetSettings() {
        localStorage.removeItem('voiceRemindersSettings');
        this.settings = this.getDefaultSettings();
        this.loadSettingsToUI();
    }

    loadSettings() {
        const saved = localStorage.getItem('voiceRemindersSettings');
        return saved ? JSON.parse(saved) : this.getDefaultSettings();
    }

    getDefaultSettings() {
        return {
            voiceEnabled: true,
            voiceRate: 0.4,
            voiceVolume: 1.0,
            notificationsEnabled: true,
            notificationSound: true,
            checkInterval: 10,
            quietHoursEnabled: false,
            quietHoursStart: '22:00',
            quietHoursEnd: '07:00'
        };
    }

    testVoice() {
        this.speak('This is a test of the voice announcement system.');
    }

    requestNotificationPermission() {
        if ('Notification' in window) {
            Notification.requestPermission().then(permission => {
                if (permission === 'granted') {
                    alert('Notifications enabled!');
                }
            });
        }
    }

    clearAnnouncedList() {
        this.announcedReminders.clear();
        this.saveAnnouncedList();
        alert('Announced reminders list cleared!');
    }

    loadAnnouncedList() {
        const stored = localStorage.getItem('voiceReminders_announced');
        return stored ? new Set(JSON.parse(stored)) : new Set();
    }

    saveAnnouncedList() {
        localStorage.setItem('voiceReminders_announced', JSON.stringify([...this.announcedReminders]));
    }

    // Kept alongside announcedReminders so the two survive a reload together.
    // Storing only the announced ids would leave a reminder marked delivered with
    // no text to replay, which is silent permanent loss.
    loadPendingVoiceAnnouncements() {
        try {
            const raw = localStorage.getItem('voiceReminders_pendingVoice');
            return new Map(raw ? JSON.parse(raw) : []);
        } catch (error) {
            console.error('Could not read pending voice announcements:', error);
            return new Map();
        }
    }

    savePendingVoiceAnnouncements() {
        try {
            localStorage.setItem(
                'voiceReminders_pendingVoice',
                JSON.stringify([...this.pendingVoiceAnnouncements])
            );
        } catch (error) {
            console.error('Could not save pending voice announcements:', error);
        }
    }
}

// Initialize app when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    window.voiceApp = new VoiceRemindersApp();
    window.voiceApp.init();
});
