# Scheduling Integration - Testing Guide

## Testing Status: Ready ✅

The UI is fully functional and ready to test! Here's how to test it:

---

## Option 1: Test Without Real API Keys (Recommended First)

You can test the entire UI flow **without** connecting to Acuity Scheduling:

### What You Can Test:
- ✅ Navigation to integrations page
- ✅ UI layout and design
- ✅ Form validation
- ✅ Empty states
- ✅ Task list filtering

### Steps:

1. **Start the Rails server:**
   ```bash
   cd backend
   rails server
   ```

2. **Log in to the dashboard:**
   - Go to `http://localhost:3000`
   - Use dev login or magic link

3. **Navigate to a senior's dashboard:**
   - Click on a senior from your dashboard
   - You should see a new "Scheduling Integrations" button

4. **Visit the integrations page:**
   - Click "Scheduling Integrations"
   - You'll see the provider cards (Acuity active, Calendly coming soon)

5. **Try the connection form:**
   - Click "Connect Acuity"
   - Fill in dummy credentials (e.g., User ID: "test123", API Key: "dummy")
   - Submit the form
   - **Expected:** Form will submit but credential verification will fail with an error message

6. **Test task filtering:**
   - Go to "View Tasks"
   - Look for the new "Source" filter dropdown
   - Try filtering by "Manual" (should show all existing tasks)

---

## Option 2: Test With Real Acuity API Keys

To test the full integration including actual appointment syncing:

### Prerequisites:

1. **Acuity Scheduling Account**
   - Sign up at https://acuityscheduling.com
   - They offer a free trial (no credit card required for 7 days)

2. **Get Your API Credentials:**
   - Log in to Acuity
   - Go to **Business Settings** → **Integrations** → **API**
   - Copy your **User ID** and **API Key**

### Steps:

1. **Start the server** (if not already running):
   ```bash
   cd backend
   rails server
   ```

2. **Navigate to integrations:**
   - Dashboard → Select a senior → "Scheduling Integrations"

3. **Connect your Acuity account:**
   - Click "Connect Acuity"
   - Enter your real User ID and API Key
   - Enable "automatic syncing" (optional)
   - Click "Connect & Verify"
   - **Expected:** Success message and redirect to integrations list

4. **Sync appointments:**
   - Click "Sync Now" on your integration
   - **Expected:** Appointments from Acuity appear as tasks

5. **View synced tasks:**
   - Go to "View Tasks"
   - You should see appointments with a purple "🔗 Acuity" badge
   - Filter by "Source: Acuity" to see only synced appointments

6. **View integration details:**
   - Click "View" on your integration
   - See last sync time, status, and recent appointments
   - Click "View in Acuity" to open appointments in Acuity

---

## What to Test

### UI/UX Testing:
- [ ] Navigation flows smoothly
- [ ] Forms are clear and easy to use
- [ ] Error messages are helpful
- [ ] Success messages appear
- [ ] Buttons and links work
- [ ] Responsive design (try different window sizes)
- [ ] Status indicators update correctly

### Functionality Testing:
- [ ] Can connect an integration
- [ ] Credential verification works
- [ ] Manual sync button works
- [ ] Tasks are created from appointments
- [ ] Task filtering by source works
- [ ] External appointment badges appear
- [ ] Links to Acuity work
- [ ] Can disconnect integration
- [ ] Tasks remain after disconnecting

### Edge Cases:
- [ ] Invalid credentials show error
- [ ] Empty integrations list shows helpful message
- [ ] No appointments shows empty state
- [ ] Multiple integrations can coexist
- [ ] Sync errors are handled gracefully

---

## Console Testing (Alternative)

If you want to test the backend logic without the UI:

```bash
cd backend
rails console
```

### Create a test integration:
```ruby
# Find or create users
caregiver = User.find_or_create_by!(email: 'caregiver@test.com') do |u|
  u.role = :caregiver
end

senior = User.find_or_create_by!(email: 'senior@test.com') do |u|
  u.role = :senior
end

# Create integration (with dummy credentials)
integration = SchedulingIntegration.create!(
  user: caregiver,
  senior: senior,
  provider: :acuity,
  provider_user_id: "12345",
  api_key: "test_key",
  status: :active
)

# Check if it's healthy
integration.healthy?
# => false (because credentials are fake)

# Try to verify credentials (will fail with fake credentials)
provider = Scheduling::ProviderFactory.create(integration)
provider.verify_credentials
# => false

# If you have real credentials, you can test sync:
# sync = Scheduling::SyncService.new(integration)
# results = sync.sync_appointments
```

---

## Known Limitations (Expected Behavior)

1. **No real-time sync** - Must click "Sync Now" manually (webhooks not implemented yet)
2. **One-way sync only** - Appointments sync FROM Acuity TO Remindly (not the reverse)
3. **Calendly not implemented** - Only Acuity works currently
4. **No encryption in test** - Credentials stored as plain text in test environment (encrypted in production)

---

## Troubleshooting

### "Missing Active Record encryption credential" error
**Solution:** This is expected in test environment. The code handles it gracefully.

### "undefined method `scheduling_integrations`" error
**Solution:** Run migrations:
```bash
cd backend
rails db:migrate
```

### "Routing error" when clicking links
**Solution:** Make sure you're on the `feature/scheduling-integration` branch:
```bash
git branch --show-current
# Should show: feature/scheduling-integration
```

### Credential verification fails with real credentials
**Possible causes:**
- API key is incorrect (check for typos)
- User ID is incorrect
- Acuity account is not active
- Network/firewall blocking API requests

**Debug:**
```ruby
# In rails console
integration = SchedulingIntegration.last
provider = Scheduling::AcuityProvider.new(integration)
provider.verify_credentials
# Check Rails logs for detailed error messages
```

---

## Next Steps After Testing

### If testing goes well:
1. Merge the feature branch to main
2. Deploy to production
3. Document for end users
4. Consider Phase 3 (Webhooks) for real-time sync

### If issues found:
1. Document the issue
2. Check Rails logs: `tail -f backend/log/development.log`
3. Report bugs with steps to reproduce

---

## API Keys - Do You Need Them?

**Short answer:** No, not for basic UI testing!

**For full testing:** Yes, but Acuity offers a free trial:
- Sign up at https://acuityscheduling.com
- 7-day free trial (no credit card required)
- Get API credentials immediately
- Can create test appointments to sync

**For production:** Yes, users will need their own Acuity accounts.

---

## Security Notes

- ✅ Credentials are encrypted in production (Rails 8 encryption)
- ✅ Each user has their own credentials (no shared API keys)
- ✅ Credentials are not exposed in UI
- ✅ API calls use HTTPS
- ✅ Webhook secrets for future webhook implementation

---

## Questions?

- Check `PHASE_1_SCHEDULING_SUMMARY.md` for architecture details
- Check `SCHEDULING_INTEGRATION_PLAN.md` for full feature plan
- Check `SCHEDULING_INTEGRATION_OPTIONAL.md` for optional feature details
- Check Rails logs for debugging: `tail -f backend/log/development.log`
