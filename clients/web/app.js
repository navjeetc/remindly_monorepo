// ============================================================================
// Remindly Web Client - Voice Reminder Announcements
// ============================================================================

class RemindlyApp {
    constructor() {
        // Determine default API base URL based on environment
        const defaultApiUrl = this.getDefaultApiUrl();
        this.apiBaseUrl = localStorage.getItem('apiBaseUrl') || defaultApiUrl;
        this.authToken = localStorage.getItem('authToken');
        this.reminders = [];
        this.announcedReminders = new Set(); // Track which reminders have been announced
        this.checkInterval = null;
        this.settings = this.loadSettings();
        this.voiceUnlockPrompted = false;
        this.voiceUnlocked = this.hasPriorUserActivation();
        this.voiceUnlockListener = null;
        // Only surface the 🔊 prompt once speech has actually been refused, so
        // desktop users who never hit the limit don't see a control they don't need.
        this.voiceBlocked = false;
        this.voiceUnlockInFlight = null;
        this.debugEnabled = localStorage.getItem('debug') === 'true';

        this.init();
    }

    // Verbose tracing, off by default. Enable from the console with:
    //   localStorage.setItem('debug', 'true'); location.reload();
    // Errors always log regardless — see console.error calls throughout.
    debug(...args) {
        if (this.debugEnabled) console.log(...args);
    }

    getDefaultApiUrl() {
        // In production, use the current domain
        // In development (localhost), use localhost:5000
        const isLocalhost = window.location.hostname === 'localhost' || 
                           window.location.hostname === '127.0.0.1' ||
                           window.location.hostname === '';
        
        if (isLocalhost) {
            return 'http://localhost:5000';
        } else {
            // Use current domain with https
            return `${window.location.protocol}//${window.location.host}`;
        }
    }

    // ========================================================================
    // Initialization
    // ========================================================================

    init() {
        this.setupEventListeners();
        this.loadSettings();
        this.checkAuthentication();
        this.checkForMagicLinkToken();
        this.hideDevFeaturesInProduction();
        this.fetchAndDisplayVersion();
        this.maybeShowVoiceUnlockPrompt();
        this.setupVoiceUnlockListeners();
        
        // Check for Web Speech API support
        if (!('speechSynthesis' in window)) {
            this.showMessage('Warning: Your browser does not support voice announcements', 'warning');
        }
    }

    hideDevFeaturesInProduction() {
        // Hide dev login if not on localhost
        const isLocalhost = window.location.hostname === 'localhost' || 
                           window.location.hostname === '127.0.0.1' ||
                           window.location.hostname === '';
        
        if (!isLocalhost) {
            const devModeText = document.querySelector('.dev-mode-text');
            const devLoginBtn = document.getElementById('devLoginBtn');
            const devHr = document.querySelector('#loginSection hr');
            
            if (devModeText) devModeText.style.display = 'none';
            if (devLoginBtn) devLoginBtn.style.display = 'none';
            if (devHr) devHr.style.display = 'none';
        }
    }

    setupEventListeners() {
        // Login
        document.getElementById('loginForm').addEventListener('submit', (e) => this.handleLogin(e));
        document.getElementById('devLoginBtn').addEventListener('click', () => this.handleDevLogin());
        document.getElementById('logoutBtn').addEventListener('click', () => this.handleLogout());

        // Settings
        document.getElementById('settingsBtn').addEventListener('click', () => this.openSettings());
        document.getElementById('closeSettings').addEventListener('click', () => this.closeSettings());
        document.getElementById('saveSettings').addEventListener('click', () => this.saveSettings());
        document.getElementById('resetSettings').addEventListener('click', () => this.resetSettings());
        document.getElementById('testVoiceBtn').addEventListener('click', () => this.testVoice());
        document.getElementById('enableVoiceBtn').addEventListener('click', () => this.handleVoiceUnlock());
        document.getElementById('requestNotificationBtn').addEventListener('click', () => this.requestNotificationPermission());

        // Refresh
        document.getElementById('refreshBtn').addEventListener('click', () => this.refreshReminders());

        // Clear announced list
        document.getElementById('clearAnnounced').addEventListener('click', () => {
            this.announcedReminders.clear();
            this.debug('🔄 Cleared announced reminders list');
            this.showMessage('Announced list cleared', 'success');
        });

        // Settings sliders
        document.getElementById('voiceRate').addEventListener('input', (e) => {
            document.getElementById('voiceRateValue').textContent = e.target.value;
        });
        document.getElementById('voiceVolume').addEventListener('input', (e) => {
            document.getElementById('voiceVolumeValue').textContent = e.target.value;
        });

        // Close modal on outside click
        document.getElementById('settingsModal').addEventListener('click', (e) => {
            if (e.target.id === 'settingsModal') {
                this.closeSettings();
            }
        });
    }

    // ========================================================================
    // Authentication
    // ========================================================================

    checkAuthentication() {
        if (this.authToken) {
            this.showMainContent();
            this.startReminderChecking();
        } else {
            this.showLoginSection();
        }
    }

    async checkForMagicLinkToken() {
        const urlParams = new URLSearchParams(window.location.search);
        const signedToken = urlParams.get('token');
        
        this.debug('🔑 Checking for magic link token...');
        this.debug('   URL:', window.location.href);
        this.debug('   Token found:', signedToken ? 'YES' : 'NO');
        
        if (signedToken) {
            this.debug('✅ Signed token found, exchanging for JWT...');
            
            try {
                // Exchange the signed token for a JWT token
                // Use POST to avoid exposing token in URL/logs
                const response = await fetch(`${this.apiBaseUrl}/magic/verify`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({ token: signedToken })
                });
                
                if (response.ok) {
                    const jwtToken = await response.text();
                    this.debug('✅ JWT token received');
                    
                    this.authToken = jwtToken;
                    localStorage.setItem('authToken', jwtToken);
                    window.history.replaceState({}, document.title, window.location.pathname);
                    this.showMainContent();
                    this.startReminderChecking();
                } else {
                    console.error('❌ Failed to verify token:', response.status);
                    this.showLoginMessage('Invalid or expired magic link', 'error');
                    window.history.replaceState({}, document.title, window.location.pathname);
                }
            } catch (error) {
                console.error('❌ Error verifying token:', error);
                this.showLoginMessage('Network error. Please try again.', 'error');
                window.history.replaceState({}, document.title, window.location.pathname);
            }
        } else {
            this.debug('❌ No token in URL');
        }
    }

    async handleLogin(e) {
        e.preventDefault();
        const email = document.getElementById('emailInput').value;
        
        try {
            // Add client=web parameter to get /client/ magic links
            const response = await fetch(`${this.apiBaseUrl}/magic/request?email=${encodeURIComponent(email)}&client=web`);
            const data = await response.json();
            
            if (response.ok) {
                this.showLoginMessage('Magic link sent! Check your email.', 'success');
            } else {
                this.showLoginMessage(data.error || 'Failed to send magic link', 'error');
            }
        } catch (error) {
            this.showLoginMessage('Network error. Please try again.', 'error');
        }
    }

    async handleDevLogin() {
        try {
            // Use a default dev email for quick login
            const devEmail = 'dev@remindly.local';
            const response = await fetch(`${this.apiBaseUrl}/magic/dev_exchange?email=${encodeURIComponent(devEmail)}`);
            const data = await response.text(); // Backend returns plain text token
            
            if (response.ok && data) {
                this.authToken = data;
                localStorage.setItem('authToken', data);
                this.showMainContent();
                this.startReminderChecking();
            } else {
                this.showLoginMessage('Dev login failed', 'error');
            }
        } catch (error) {
            this.showLoginMessage('Network error. Please try again.', 'error');
        }
    }

    handleLogout() {
        this.authToken = null;
        localStorage.removeItem('authToken');
        this.stopReminderChecking();
        this.showLoginSection();
    }

    showLoginSection() {
        document.getElementById('loginSection').style.display = 'flex';
        document.getElementById('mainContent').style.display = 'none';
    }

    showMainContent() {
        document.getElementById('loginSection').style.display = 'none';
        document.getElementById('mainContent').style.display = 'block';
        this.refreshReminders();
    }

    showLoginMessage(message, type) {
        const messageEl = document.getElementById('loginMessage');
        messageEl.textContent = message;
        messageEl.className = `message ${type}`;
        messageEl.style.display = 'block';
    }

    // ========================================================================
    // Settings Management
    // ========================================================================

    loadSettings() {
        const defaults = {
            voiceEnabled: true,
            voiceRate: 0.4,
            voiceVolume: 1.0,
            notificationsEnabled: true,
            notificationSound: true,
            checkInterval: 10,
            gracePeriod: 30, // seconds before scheduled time to announce
            quietHoursEnabled: false,
            quietHoursStart: '22:00',
            quietHoursEnd: '07:00',
            apiBaseUrl: this.apiBaseUrl // Use already initialized value from constructor
        };

        const saved = localStorage.getItem('remindlySettings');
        this.settings = saved ? { ...defaults, ...JSON.parse(saved) } : defaults;
        return this.settings;
    }

    saveSettings() {
        this.settings = {
            voiceEnabled: document.getElementById('voiceEnabled').checked,
            voiceRate: parseFloat(document.getElementById('voiceRate').value),
            voiceVolume: parseFloat(document.getElementById('voiceVolume').value),
            notificationsEnabled: document.getElementById('notificationsEnabled').checked,
            notificationSound: document.getElementById('notificationSound').checked,
            checkInterval: parseInt(document.getElementById('checkInterval').value),
            quietHoursEnabled: document.getElementById('quietHoursEnabled').checked,
            quietHoursStart: document.getElementById('quietHoursStart').value,
            quietHoursEnd: document.getElementById('quietHoursEnd').value,
            apiBaseUrl: document.getElementById('apiBaseUrl').value
        };

        localStorage.setItem('remindlySettings', JSON.stringify(this.settings));
        this.apiBaseUrl = this.settings.apiBaseUrl;
        localStorage.setItem('apiBaseUrl', this.apiBaseUrl);
        
        this.closeSettings();
        this.showMessage('Settings saved!', 'success');
        
        // Restart reminder checking with new interval
        this.stopReminderChecking();
        this.startReminderChecking();
    }

    resetSettings() {
        localStorage.removeItem('remindlySettings');
        this.loadSettings();
        this.populateSettingsForm();
        this.showMessage('Settings reset to defaults', 'success');
    }

    openSettings() {
        this.populateSettingsForm();
        document.getElementById('settingsModal').style.display = 'flex';
    }

    closeSettings() {
        document.getElementById('settingsModal').style.display = 'none';
    }

    populateSettingsForm() {
        document.getElementById('voiceEnabled').checked = this.settings.voiceEnabled;
        document.getElementById('voiceRate').value = this.settings.voiceRate;
        document.getElementById('voiceRateValue').textContent = this.settings.voiceRate;
        document.getElementById('voiceVolume').value = this.settings.voiceVolume;
        document.getElementById('voiceVolumeValue').textContent = this.settings.voiceVolume;
        document.getElementById('notificationsEnabled').checked = this.settings.notificationsEnabled;
        document.getElementById('notificationSound').checked = this.settings.notificationSound;
        document.getElementById('checkInterval').value = this.settings.checkInterval;
        document.getElementById('quietHoursEnabled').checked = this.settings.quietHoursEnabled;
        document.getElementById('quietHoursStart').value = this.settings.quietHoursStart;
        document.getElementById('quietHoursEnd').value = this.settings.quietHoursEnd;
        document.getElementById('apiBaseUrl').value = this.settings.apiBaseUrl;
    }

    // ========================================================================
    // Voice Announcements (Web Speech API)
    // ========================================================================

    // reminderId lets a blocked announcement be un-marked so it retries once the
    // user unlocks; without it a refused announcement is lost for good.
    speak(text, reminderId = null) {
        this.debug('🔊 speak() called with:', text);
        this.debug('   voiceEnabled:', this.settings.voiceEnabled);
        this.debug('   speechSynthesis available:', 'speechSynthesis' in window);
        this.debug('   inQuietHours:', this.isInQuietHours());
        
        if (!this.settings.voiceEnabled) {
            this.debug('❌ Voice disabled in settings');
            return;
        }
        if (!('speechSynthesis' in window)) {
            this.debug('❌ speechSynthesis not available');
            return;
        }
        if (this.isInQuietHours()) {
            this.debug('❌ In quiet hours');
            return;
        }
        if (!this.voiceUnlocked) {
            this.debug('❌ Voice locked - waiting for unlock gesture');
            this.onVoiceBlocked(reminderId);
            return;
        }

        const utterance = new SpeechSynthesisUtterance(text);
        utterance.lang = 'en-US';
        utterance.rate = this.settings.voiceRate;
        utterance.volume = this.settings.voiceVolume;
        
        // Try to use a specific voice (helps with some browsers)
        const voices = window.speechSynthesis.getVoices();
        if (voices.length > 0) {
            // Prefer English voices
            const englishVoice = voices.find(v => v.lang.startsWith('en')) || voices[0];
            utterance.voice = englishVoice;
            this.debug('Using voice:', englishVoice.name);
        }
        
        this.debug('✅ Speaking:', text);
        this.debug('   rate:', utterance.rate, 'volume:', utterance.volume);
        
        utterance.onstart = () => {
            this.debug('🎤 Speech started');
        };
        utterance.onend = () => {
            this.debug('🎤 Speech ended');
        };
        utterance.onerror = (e) => {
            console.error('❌ Speech error:', e);
            console.error('Error details:', {
                error: e.error,
                charIndex: e.charIndex,
                elapsedTime: e.elapsedTime
            });
            // The browser refused for lack of a user gesture. Re-lock so the next
            // touch or click re-arms voice, and let this reminder announce again.
            if (e.error === 'not-allowed') {
                this.voiceUnlocked = false;
                this.onVoiceBlocked(reminderId);
            }
        };
        
        try {
            // Chrome workaround: Cancel everything and wait
            this.debug('🔄 Resetting speech synthesis...');
            window.speechSynthesis.cancel();
            
            // Wait longer for Chrome to fully reset
            setTimeout(() => {
                this.debug('📢 Calling speechSynthesis.speak()...');
                
                // Add a resume() call - sometimes needed in Chrome
                window.speechSynthesis.resume();
                
                window.speechSynthesis.speak(utterance);
                
                // Chrome workaround: Call resume again after speak
                setTimeout(() => {
                    window.speechSynthesis.resume();
                    this.debug('🔍 Speaking status:', window.speechSynthesis.speaking);
                    this.debug('🔍 Pending status:', window.speechSynthesis.pending);
                }, 100);
            }, 500); // Longer delay for Chrome
        } catch (error) {
            console.error('❌ Exception calling speak():', error);
        }
    }

    async handleVoiceUnlock({ silent = false } = {}) {
        if (this.voiceUnlocked) {
            if (!silent) this.showMessage('Voice already enabled', 'success');
            this.maybeShowVoiceUnlockPrompt();
            return true;
        }
        if (!('speechSynthesis' in window)) {
            if (!silent) this.showMessage('Voice synthesis not available on this device', 'error');
            return false;
        }
        // One tap fires both touchend and click, and the 🔊 button adds a third
        // handler. Each attempt calls speechSynthesis.cancel(), so a later one
        // aborts an earlier one and reports failure while the first was working.
        // Share a single in-flight attempt instead.
        if (this.voiceUnlockInFlight) {
            return this.voiceUnlockInFlight;
        }

        this.voiceUnlockInFlight = (async () => {
            try {
                await this.performVoiceUnlockSequence();
                this.voiceUnlocked = true;
                this.voiceUnlockPrompted = false;
                this.voiceBlocked = false;
                if (!silent) this.showMessage('Voice announcements enabled', 'success');
                this.removeVoiceUnlockListeners();
            } catch (error) {
                console.error('❌ Failed to unlock voice:', error);
                if (!silent) this.showMessage('Unable to enable voice. Please try again.', 'error');
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
                window.speechSynthesis.cancel();
                window.speechSynthesis.speak(utterance);
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

    // Speech was refused for lack of a gesture. Re-arm the unlock listeners, show
    // the 🔊 fallback, and drop the reminder from the announced set so the next
    // poll re-announces it once voice is available.
    onVoiceBlocked(reminderId = null) {
        this.voiceBlocked = true;
        if (reminderId !== null) this.announcedReminders.delete(reminderId);
        this.setupVoiceUnlockListeners();
        this.maybeShowVoiceUnlockPrompt();
        if (!this.voiceUnlockPrompted) {
            this.showMessage('Tap anywhere to enable voice announcements', 'warning');
            this.voiceUnlockPrompted = true;
        }
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

    testVoice() {
        this.debug('🎤 ========================================');
        this.debug('🎤 TEST VOICE BUTTON CLICKED');
        this.debug('🎤 ========================================');
        
        // Check if speech synthesis is available
        if (!('speechSynthesis' in window)) {
            console.error('❌ speechSynthesis not available in this browser');
            alert('Speech synthesis is not supported in this browser');
            return;
        }
        
        this.debug('✅ speechSynthesis is available');
        this.debug('Current state:', {
            speaking: window.speechSynthesis.speaking,
            pending: window.speechSynthesis.pending,
            paused: window.speechSynthesis.paused
        });
        
        // Try to get voices first (sometimes needed to initialize)
        const voices = window.speechSynthesis.getVoices();
        this.debug('Available voices:', voices.length);
        
        if (voices.length > 0) {
            this.debug('First 5 voices:');
            voices.slice(0, 5).forEach((v, i) => {
                this.debug(`  ${i}: ${v.name} (${v.lang})`);
            });
        }
        
        // On some browsers, we need to wait for voices to load
        if (voices.length === 0) {
            this.debug('⏳ No voices available yet, waiting for voiceschanged event...');
            window.speechSynthesis.onvoiceschanged = () => {
                const newVoices = window.speechSynthesis.getVoices();
                this.debug('✅ Voices loaded:', newVoices.length);
                this.speak('This is a test of the voice announcement system');
            };
        } else {
            this.debug('🔊 Calling speak() with test message...');
            this.speak('This is a test of the voice announcement system');
        }
    }

    // ========================================================================
    // Browser Notifications
    // ========================================================================

    async requestNotificationPermission() {
        if (!('Notification' in window)) {
            this.showMessage('Browser notifications are not supported', 'error');
            return;
        }

        const permission = await Notification.requestPermission();
        if (permission === 'granted') {
            this.showMessage('Notification permission granted!', 'success');
        } else {
            this.showMessage('Notification permission denied', 'error');
        }
    }

    showNotification(reminder) {
        if (!this.settings.notificationsEnabled) return;
        if (!('Notification' in window)) return;
        if (Notification.permission !== 'granted') return;
        if (this.isInQuietHours()) return;

        const title = `⏰ REMINDER: ${reminder.reminder.title}`;
        const body = reminder.reminder.notes || `Time for your ${reminder.reminder.category || 'reminder'}`;

        const notification = new Notification(title, {
            body: body,
            icon: '🔔',
            badge: '🔔',
            tag: `reminder-${reminder.id}`,
            requireInteraction: true,
            silent: false, // Play system sound
            data: { reminderId: reminder.id }
        });

        notification.onclick = () => {
            window.focus();
            notification.close();
            this.scrollToReminder(reminder.id);
        };
        
        // Also show an alert for critical reminders
        if (this.settings.voiceEnabled) {
            // Since voice doesn't work, show a prominent alert
            this.showMessage(`🔔 ${reminder.reminder.title}`, 'info');
        }
    }

    // ========================================================================
    // Quiet Hours
    // ========================================================================

    isInQuietHours() {
        if (!this.settings.quietHoursEnabled) return false;

        const now = new Date();
        const currentHour = now.getHours();
        const currentMinute = now.getMinutes();
        const currentTime = currentHour + (currentMinute / 60);

        const [startHour, startMinute] = this.settings.quietHoursStart.split(':').map(Number);
        const [endHour, endMinute] = this.settings.quietHoursEnd.split(':').map(Number);
        const startTime = startHour + (startMinute / 60);
        const endTime = endHour + (endMinute / 60);

        if (startTime < endTime) {
            return currentTime >= startTime && currentTime < endTime;
        } else {
            return currentTime >= startTime || currentTime < endTime;
        }
    }

    // ========================================================================
    // Reminder Management
    // ========================================================================

    async fetchUserProfile() {
        if (!this.authToken) return;

        try {
            const response = await fetch(`${this.apiBaseUrl}/reminders/profile`, {
                headers: {
                    'Authorization': `Bearer ${this.authToken}`,
                    'Content-Type': 'application/json'
                }
            });

            if (response.ok) {
                const user = await response.json();
                const userName = user.display_name || user.name || user.email;
                const userNameEl = document.getElementById('userName');
                userNameEl.textContent = `Welcome, ${userName}`;
                userNameEl.style.display = 'block';
            }
        } catch (error) {
            console.error('Error fetching user profile:', error);
        }
    }

    async refreshReminders() {
        if (!this.authToken) return;

        try {
            this.updateStatusIndicator('loading');
            
            // Fetch user profile on first load
            if (!this.userProfileFetched) {
                this.fetchUserProfile();
                this.userProfileFetched = true;
            }
            
            const response = await fetch(`${this.apiBaseUrl}/reminders/today`, {
                headers: {
                    'Authorization': `Bearer ${this.authToken}`,
                    'Content-Type': 'application/json'
                }
            });

            if (response.ok) {
                const newReminders = await response.json();
                this.debug('📥 Received reminders:', newReminders);
                
                // Clear announced reminders if the list has changed (new IDs)
                const newIds = new Set(newReminders.map(r => r.id));
                const oldIds = new Set(this.reminders.map(r => r.id));
                const idsChanged = newReminders.length !== this.reminders.length || 
                                  ![...newIds].every(id => oldIds.has(id));
                
                if (idsChanged) {
                    this.debug('🔄 Reminder list changed, clearing announced set');
                    this.announcedReminders.clear();
                }
                
                this.reminders = newReminders;
                
                if (this.reminders.length > 0) {
                    this.debug('📅 First reminder sample:', this.reminders[0]);
                }
                this.renderReminders();
                this.updateStats();
                this.checkDueReminders();
                this.updateStatusIndicator('online');
            } else if (response.status === 401) {
                this.handleLogout();
            } else {
                this.updateStatusIndicator('error');
                this.showMessage('Failed to load reminders', 'error');
            }
        } catch (error) {
            console.error('Error fetching reminders:', error);
            this.updateStatusIndicator('offline');
            this.showMessage('Network error. Please check your connection.', 'error');
        }
    }

    renderReminders() {
        const container = document.getElementById('remindersList');
        const emptyState = document.getElementById('emptyState');

        if (this.reminders.length === 0) {
            container.innerHTML = '';
            emptyState.style.display = 'block';
            return;
        }

        emptyState.style.display = 'none';
        container.innerHTML = this.reminders.map(reminder => this.createReminderCard(reminder)).join('');

        // Add event listeners to action buttons
        this.reminders.forEach(reminder => {
            const card = document.getElementById(`reminder-${reminder.id}`);
            if (card) {
                card.querySelector('.btn-taken')?.addEventListener('click', () => this.acknowledgeReminder(reminder.id, 'taken'));
                card.querySelector('.btn-skip')?.addEventListener('click', () => this.acknowledgeReminder(reminder.id, 'skip'));
                card.querySelector('.btn-snooze')?.addEventListener('click', () => this.snoozeReminder(reminder.id));
            }
        });
    }

    createReminderCard(reminder) {
        // Handle both camelCase and snake_case from API
        const scheduledAt = reminder.scheduledAt || reminder.scheduled_at;
        const scheduledTime = new Date(scheduledAt);
        const now = new Date();
        const isPast = scheduledTime < now;
        const isCompleted = reminder.status !== 'pending';
        
        // Check if date is valid
        if (isNaN(scheduledTime.getTime())) {
            console.error('Invalid date for reminder:', reminder);
            return ''; // Skip invalid reminders
        }
        
        const timeStr = scheduledTime.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
        
        const statusClass = isCompleted ? 'completed' : (isPast ? 'overdue' : 'upcoming');
        const statusEmoji = isCompleted ? '✓' : (isPast ? '⚠️' : '⏰');

        return `
            <div id="reminder-${reminder.id}" class="reminder-card ${statusClass}">
                <div class="reminder-header">
                    <div class="reminder-time">
                        <span class="status-emoji">${statusEmoji}</span>
                        <span>${timeStr}</span>
                    </div>
                    ${reminder.reminder.category ? `<span class="reminder-category">${reminder.reminder.category}</span>` : ''}
                </div>
                <div class="reminder-title">${reminder.reminder.title}</div>
                ${reminder.reminder.notes ? `<div class="reminder-notes">${reminder.reminder.notes}</div>` : ''}
                ${!isCompleted ? `
                    <div class="reminder-actions">
                        <button class="btn-action btn-taken">✓ Taken</button>
                        <button class="btn-action btn-snooze">⏰ Snooze</button>
                        <button class="btn-action btn-skip">✗ Skip</button>
                    </div>
                ` : `
                    <div class="reminder-status">${reminder.status === 'acknowledged' ? 'Completed' : 'Skipped'}</div>
                `}
            </div>
        `;
    }

    updateStats() {
        const total = this.reminders.length;
        const pending = this.reminders.filter(r => r.status === 'pending').length;
        const completed = this.reminders.filter(r => r.status === 'acknowledged').length;

        document.getElementById('totalCount').textContent = total;
        document.getElementById('pendingCount').textContent = pending;
        document.getElementById('completedCount').textContent = completed;
    }

    // ========================================================================
    // Due Reminder Detection & Announcement
    // ========================================================================

    checkDueReminders() {
        const now = new Date();
        const gracePeriod = this.settings.gracePeriod * 1000; // Convert seconds to milliseconds
        
        this.debug('⏰ checkDueReminders() - Checking', this.reminders.length, 'reminders');

        this.reminders.forEach(reminder => {
            const scheduledAt = reminder.scheduledAt || reminder.scheduled_at;
            const scheduledTime = new Date(scheduledAt);
            const timeDiff = scheduledTime - now;
            const minutesUntil = (timeDiff / 1000 / 60).toFixed(1);

            this.debug(`  📋 ${reminder.reminder.title}: status=${reminder.status}, announced=${this.announcedReminders.has(reminder.id)}, due in ${minutesUntil}m`);

            if (reminder.status !== 'pending') {
                this.debug('     ⏭️  Skipping - not pending');
                return;
            }
            if (this.announcedReminders.has(reminder.id)) {
                this.debug('     ⏭️  Skipping - already announced');
                return;
            }

            // Skip if invalid date
            if (isNaN(scheduledTime.getTime())) {
                console.error('❌ Invalid scheduled_at for reminder:', reminder);
                return;
            }

            // Announce if reminder is due (within grace period BEFORE scheduled time)
            // Only announce if it's coming up, not if it's already past
            if (timeDiff <= gracePeriod && timeDiff >= 0) {
                // Announcing is a real state change and happens once per reminder,
                // so it stays visible without the debug flag.
                console.log(`🔔 Announcing: ${reminder.reminder.title} (due in ${minutesUntil}m)`);
                this.announceReminder(reminder);
            } else if (timeDiff < 0) {
                this.debug(`     ⏭️  Skipping - already ${Math.abs(minutesUntil)}m overdue`);
            } else {
                this.debug(`     ⏳ Not yet due (${minutesUntil}m until due)`);
            }
        });
    }

    announceReminder(reminder) {
        this.debug('🔔 Announcing reminder:', reminder.reminder.title);
        
        // Mark as announced
        this.announcedReminders.add(reminder.id);

        // Voice announcement
        this.speak(reminder.reminder.title, reminder.id);

        // Browser notification
        this.showNotification(reminder);

        // Highlight the reminder card
        this.highlightReminder(reminder.id);
    }

    highlightReminder(reminderId) {
        const card = document.getElementById(`reminder-${reminderId}`);
        if (card) {
            card.classList.add('announcing');
            setTimeout(() => {
                card.classList.remove('announcing');
            }, 3000);
        }
    }

    scrollToReminder(reminderId) {
        const card = document.getElementById(`reminder-${reminderId}`);
        if (card) {
            card.scrollIntoView({ behavior: 'smooth', block: 'center' });
            this.highlightReminder(reminderId);
        }
    }

    // ========================================================================
    // Reminder Actions
    // ========================================================================

    async acknowledgeReminder(occurrenceId, kind) {
        try {
            const response = await fetch(`${this.apiBaseUrl}/acknowledgements`, {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${this.authToken}`,
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    occurrence_id: occurrenceId,
                    kind: kind
                })
            });

            if (response.ok) {
                this.showMessage(`Reminder ${kind === 'taken' ? 'completed' : 'skipped'}!`, 'success');
                await this.refreshReminders();
            } else {
                this.showMessage('Failed to update reminder', 'error');
            }
        } catch (error) {
            console.error('Error acknowledging reminder:', error);
            this.showMessage('Network error', 'error');
        }
    }

    async snoozeReminder(occurrenceId) {
        try {
            const response = await fetch(`${this.apiBaseUrl}/acknowledgements/snooze`, {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${this.authToken}`,
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    occurrence_id: occurrenceId,
                    minutes: 10
                })
            });

            if (response.ok) {
                this.showMessage('Reminder snoozed for 10 minutes', 'success');
                await this.refreshReminders();
            } else {
                this.showMessage('Failed to snooze reminder', 'error');
            }
        } catch (error) {
            console.error('Error snoozing reminder:', error);
            this.showMessage('Network error', 'error');
        }
    }

    // ========================================================================
    // Periodic Checking
    // ========================================================================

    startReminderChecking() {
        // Initial check
        this.refreshReminders();

        // Set up periodic checking
        const intervalMs = this.settings.checkInterval * 1000;
        this.checkInterval = setInterval(() => {
            this.refreshReminders();
        }, intervalMs);

        this.debug(`✅ Started reminder checking every ${this.settings.checkInterval} seconds`);
    }

    stopReminderChecking() {
        if (this.checkInterval) {
            clearInterval(this.checkInterval);
            this.checkInterval = null;
            this.debug('🛑 Stopped reminder checking');
        }
    }

    // ========================================================================
    // UI Helpers
    // ========================================================================

    updateStatusIndicator(status) {
        const indicator = document.getElementById('statusIndicator');
        indicator.className = `status-indicator ${status}`;
        
        const titles = {
            online: 'Connected',
            offline: 'Offline',
            loading: 'Loading...',
            error: 'Error'
        };
        indicator.title = titles[status] || status;
    }

    showMessage(message, type = 'info') {
        // Create toast notification
        const toast = document.createElement('div');
        toast.className = `toast toast-${type}`;
        toast.textContent = message;
        document.body.appendChild(toast);

        setTimeout(() => {
            toast.classList.add('show');
        }, 100);

        setTimeout(() => {
            toast.classList.remove('show');
            setTimeout(() => toast.remove(), 300);
        }, 3000);
    }

    // ========================================================================
    // Version Management
    // ========================================================================

    async fetchAndDisplayVersion() {
        try {
            const response = await fetch(`${this.apiBaseUrl}/version`);
            if (response.ok) {
                const data = await response.json();
                const versionElement = document.getElementById('appVersion');
                if (versionElement && data.version) {
                    versionElement.textContent = `v${data.version}`;
                }
            }
        } catch (error) {
            console.error('Failed to fetch version:', error);
            // Keep the placeholder "v..." if fetch fails
        }
    }
}

// ============================================================================
// Initialize App
// ============================================================================

document.addEventListener('DOMContentLoaded', () => {
    window.remindlyApp = new RemindlyApp();
});
