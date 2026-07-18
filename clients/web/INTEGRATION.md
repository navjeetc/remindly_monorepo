# Web Client Integration with Rails

The web client is now integrated into the Rails application and can be accessed at `/client`.

## Access URLs

### Development
- **Web Client**: http://localhost:5000/client
- **Rails Dashboard**: http://localhost:5000/dashboard
- **API Endpoints**: http://localhost:5000/reminders/today

### Production
- **Web Client**: https://your-domain.com/client
- **Rails Dashboard**: https://your-domain.com/dashboard
- **API Endpoints**: https://your-domain.com/api/*

## How It Works

### File Structure
```
backend/
├── public/
│   └── client/              # Web client files (copied from clients/web/)
│       ├── index.html       # Main HTML
│       ├── app.js           # JavaScript application
│       ├── styles.css       # Styles
│       └── *.md             # Documentation
└── config/
    └── routes.rb            # Route: get "client" -> /client/index.html
```

### Routing
- Rails serves static files from `public/` automatically
- Route `/client` redirects to `/client/index.html`
- All other client files (JS, CSS) loaded from `/client/`

### API Integration
- Web client makes API calls to same domain
- No CORS issues (same origin)
- Uses JWT authentication (already configured)

## Deployment

### Option A: Deploy Together (Simple)
Deploy Rails app normally - web client is included in `public/client/`

```bash
# The web client is already in public/client/
# Just deploy Rails as usual
git push heroku main
```

### Option B: Deploy Separately (Recommended for Scale)

**Web Client** (CDN - Fast & Cheap):
```bash
# Deploy to Netlify/Vercel
cd clients/web
# Configure API URL to point to Rails server
# Deploy to CDN
```

**Rails API** (Server):
```bash
# Deploy Rails to Heroku/AWS
git push heroku main
```

## Updating the Web Client

When you make changes to the standalone web client:

```bash
# Copy updated files to Rails public directory
cd backend
cp -r ../clients/web/* public/client/
git add public/client/
git commit -m "Update web client"
```

Or use a rake task (see below).

## Rake Task for Syncing

Create `lib/tasks/client.rake`:

```ruby
namespace :client do
  desc "Sync web client from clients/web to public/client"
  task :sync do
    puts "Syncing web client..."
    FileUtils.cp_r(
      Dir.glob("../clients/web/*"),
      "public/client/",
      verbose: true
    )
    puts "✅ Web client synced!"
  end
end
```

Usage:
```bash
rails client:sync
```

## Benefits of This Approach

✅ **Single Server in Development**: One `rails server` runs everything
✅ **Flexible Deployment**: Can deploy together or separately
✅ **No CORS Issues**: Same origin in development
✅ **Easy Testing**: Access both UIs from same server
✅ **Production Ready**: Works in both simple and scaled deployments

## URLs Summary

| Component | Development | Production |
|-----------|-------------|------------|
| Web Client | http://localhost:5000/client | https://your-domain.com/client |
| Rails Dashboard | http://localhost:5000/dashboard | https://your-domain.com/dashboard |
| API | http://localhost:5000/reminders/today | https://your-domain.com/reminders/today |

## Testing

1. Start Rails server:
   ```bash
   cd backend
   rails server -p 5000
   ```

2. Open web client:
   ```
   http://localhost:5000/client
   ```

3. Test voice announcements in Safari (recommended)

4. Create test reminders:
   ```bash
   rails runner create_test_reminders.rb
   ```

## Notes

- Web client files in `public/client/` are served as static files
- No Rails views or controllers needed for the client
- Client uses same API endpoints as SwiftUI app
- Authentication works the same (JWT tokens)
- Standalone version still available in `clients/web/` for development
