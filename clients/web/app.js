// ============================================================================
// Remindly Web Client - Voice Reminder Announcements
// ============================================================================

class RemindlyApp {
    constructor() {
        this.apiBaseUrl = localStorage.getItem('apiBaseUrl') || 'http://localhost:3000';
        this.authToken = localStorage.getItem('authToken');
        this.reminders = [];
        this.announcedReminders = new Set(); // Track which reminders have been announced
        this.checkInterval = null;
        this.settings = this.loadSettings();
        
        this.init();
    }

    // ========================================================================
    // Initialization
    // ========================================================================

    init() {
        this.setupEventListeners();
        this.loadSettings();
        this.checkAuthentication();
        this.checkForMagicLinkToken();
        
        // Check for Web Speech API support
        if (!('speechSynthesis' in window)) {
            this.showMessage('Warning: Your browser does not support voice announcements', 'warning');
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
        document.getElementById('requestNotificationBtn').addEventListener('click', () => this.requestNotificationPermission());

        // Refresh
        document.getElementById('refreshBtn').addEventListener('click', () => this.refreshReminders());

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

    checkForMagicLinkToken() {
        const urlParams = new URLSearchParams(window.location.search);
        const token = urlParams.get('token');
        
        if (token) {
            this.authToken = token;
            localStorage.setItem('authToken', token);
            window.history.replaceState({}, document.title, window.location.pathname);
            this.showMainContent();
            this.startReminderChecking();
        }
    }

    async handleLogin(e) {
        e.preventDefault();
        const email = document.getElementById('emailInput').value;
        
        try {
            const response = await fetch(`${this.apiBaseUrl}/magic/request?email=${encodeURIComponent(email)}`);
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
            const response = await fetch(`${this.apiBaseUrl}/magic/dev_exchange`);
            const data = await response.json();
            
            if (response.ok && data.token) {
                this.authToken = data.token;
                localStorage.setItem('authToken', data.token);
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
            quietHoursEnabled: false,
            quietHoursStart: '22:00',
            quietHoursEnd: '07:00',
            apiBaseUrl: 'http://localhost:3000'
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

    speak(text) {
        if (!this.settings.voiceEnabled) return;
        if (!('speechSynthesis' in window)) return;
        if (this.isInQuietHours()) return;

        // Cancel any ongoing speech
        window.speechSynthesis.cancel();

        const utterance = new SpeechSynthesisUtterance(text);
        utterance.lang = 'en-US';
        utterance.rate = this.settings.voiceRate;
        utterance.volume = this.settings.voiceVolume;
        
        window.speechSynthesis.speak(utterance);
    }

    testVoice() {
        this.speak('This is a test of the voice announcement system');
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

        const title = reminder.reminder.title;
        const body = reminder.reminder.notes || `Time for your ${reminder.reminder.category || 'reminder'}`;

        const notification = new Notification(title, {
            body: body,
            icon: '🔔',
            badge: '🔔',
            tag: `reminder-${reminder.id}`,
            requireInteraction: true,
            data: { reminderId: reminder.id }
        });

        notification.onclick = () => {
            window.focus();
            notification.close();
            this.scrollToReminder(reminder.id);
        };
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

    async refreshReminders() {
        if (!this.authToken) return;

        try {
            this.updateStatusIndicator('loading');
            
            const response = await fetch(`${this.apiBaseUrl}/reminders/today`, {
                headers: {
                    'Authorization': `Bearer ${this.authToken}`,
                    'Content-Type': 'application/json'
                }
            });

            if (response.ok) {
                this.reminders = await response.json();
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
        const scheduledTime = new Date(reminder.scheduledAt);
        const now = new Date();
        const isPast = scheduledTime < now;
        const isCompleted = reminder.status !== 'pending';
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
                    <div class="reminder-status">${reminder.status === 'taken' ? 'Completed' : 'Skipped'}</div>
                `}
            </div>
        `;
    }

    updateStats() {
        const total = this.reminders.length;
        const pending = this.reminders.filter(r => r.status === 'pending').length;
        const completed = this.reminders.filter(r => r.status === 'taken').length;

        document.getElementById('totalCount').textContent = total;
        document.getElementById('pendingCount').textContent = pending;
        document.getElementById('completedCount').textContent = completed;
    }

    // ========================================================================
    // Due Reminder Detection & Announcement
    // ========================================================================

    checkDueReminders() {
        const now = new Date();
        const gracePeriod = 5 * 60 * 1000; // 5 minutes in milliseconds

        this.reminders.forEach(reminder => {
            if (reminder.status !== 'pending') return;
            if (this.announcedReminders.has(reminder.id)) return;

            const scheduledTime = new Date(reminder.scheduledAt);
            const timeDiff = scheduledTime - now;

            // Announce if reminder is due (within grace period or past due)
            if (timeDiff <= gracePeriod && timeDiff > -gracePeriod) {
                this.announceReminder(reminder);
            }
        });
    }

    announceReminder(reminder) {
        console.log('🔔 Announcing reminder:', reminder.reminder.title);
        
        // Mark as announced
        this.announcedReminders.add(reminder.id);

        // Voice announcement
        this.speak(reminder.reminder.title);

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

        console.log(`✅ Started reminder checking every ${this.settings.checkInterval} seconds`);
    }

    stopReminderChecking() {
        if (this.checkInterval) {
            clearInterval(this.checkInterval);
            this.checkInterval = null;
            console.log('🛑 Stopped reminder checking');
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
}

// ============================================================================
// Initialize App
// ============================================================================

document.addEventListener('DOMContentLoaded', () => {
    window.remindlyApp = new RemindlyApp();
});
