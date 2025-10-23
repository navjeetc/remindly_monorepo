# Deployment Guide - Web Client Integration

## Summary

The web client has been integrated into the Rails application and is ready for production deployment.

## What Was Integrated

- **Web Client** with voice announcements
- Accessible at `/client` URL
- Served from `backend/public/client/`
- No separate deployment needed

## Production URLs

After deployment, the web client will be available at:

```
http://remindly.anakahsoft.com/client
```

Other URLs remain unchanged:
- **Caregiver Dashboard**: `http://remindly.anakahsoft.com/dashboard`
- **API**: `http://remindly.anakahsoft.com/reminders/today`
- **Login**: `http://remindly.anakahsoft.com/login`

## Deployment Steps

### 1. Push to GitHub (if not done)

```bash
git push origin feature/integrate-web-client-into-rails
```

### 2. Merge to Main

Create PR and merge, or merge locally:

```bash
git checkout main
git merge feature/integrate-web-client-into-rails
git push origin main
```

### 3. Deploy to Production

Use your existing deployment process. For example:

```bash
# If using Heroku
git push heroku main

# If using Kamal or other deployment tool
# Use your standard deployment command
```

### 4. Verify Deployment

After deployment, test:

1. **Visit**: `http://remindly.anakahsoft.com/client`
2. **Check**: Page loads with styling
3. **Login**: Click "Quick Dev Login"
4. **Test**: Create reminders and test voice announcements

## Files Deployed

The following files are included in the deployment:

```
backend/
├── public/
│   └── client/              # Web client (automatically deployed)
│       ├── index.html
│       ├── app.js
│       ├── styles.css
│       └── *.md (docs)
├── config/
│   └── routes.rb            # Route: /client -> /client/index.html
└── lib/
    └── tasks/
        └── client.rake      # Rake task for syncing
```

## Testing in Production

### Quick Test

```bash
# 1. Check if web client is accessible
curl -I http://remindly.anakahsoft.com/client

# Should return: HTTP/1.1 302 Found (redirect)

# 2. Check if index.html loads
curl -I http://remindly.anakahsoft.com/client/index.html

# Should return: HTTP/1.1 200 OK
```

### Full Test

1. Open Safari (recommended browser)
2. Go to: `http://remindly.anakahsoft.com/client`
3. Click "Quick Dev Login"
4. Create test reminders using Rails console:
   ```bash
   rails runner create_test_reminders.rb
   ```
5. Wait for voice announcements

## Browser Recommendations for Users

**macOS:**
- 🏆 **Safari** - Best experience (native voices)
- ✅ **Firefox** - Works well (robotic voice)
- ⚠️ **Chrome** - Not recommended (unreliable)

## Troubleshooting

### CSS Not Loading

If styling doesn't load:
1. Check that files exist in `public/client/`
2. Hard refresh browser (Cmd+Shift+R)
3. Check browser console for 404 errors

### Voice Not Working

1. Ensure user is using Safari on macOS
2. Check macOS System Settings → Accessibility → Spoken Content
3. Enable "Speak selection"
4. Test voice in Settings panel

### 404 on /client

1. Verify route exists in `config/routes.rb`
2. Check that `public/client/index.html` exists
3. Restart Rails server

## Updating the Web Client

If you make changes to the standalone web client (`clients/web/`):

```bash
# Sync changes to Rails public directory
cd backend
rails client:sync

# Commit and deploy
git add public/client/
git commit -m "Update web client"
git push origin main
# Deploy to production
```

## Rollback

If you need to rollback:

```bash
# Remove the web client
git revert <commit-hash>
git push origin main
# Deploy
```

Or manually:
```bash
# Remove files
rm -rf backend/public/client/

# Remove route from config/routes.rb
# Line: get "client", to: redirect("/client/index.html", status: 302)

# Commit and deploy
```

## Support

- **Documentation**: `backend/public/client/README.md`
- **Integration Guide**: `backend/public/client/INTEGRATION.md`
- **Quick Start**: `backend/public/client/QUICKSTART.md`

## Success Criteria

✅ Web client accessible at `/client`
✅ Styling loads correctly
✅ Authentication works
✅ Voice announcements work in Safari
✅ Browser notifications appear
✅ All actions work (Taken, Snooze, Skip)
✅ No CORS errors
✅ Caregiver dashboard still works at `/dashboard`

---

**Ready for Production Deployment!** 🚀

Branch: `feature/integrate-web-client-into-rails`
Commit: `602a8bc`
Date: October 21, 2025
