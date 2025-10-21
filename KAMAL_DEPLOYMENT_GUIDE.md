# Kamal Deployment Guide for Remindly Backend

## Prerequisites

### 1. DigitalOcean VPS Setup
- [ ] Create a DigitalOcean Droplet (Ubuntu 22.04 LTS recommended)
- [ ] Minimum: 2GB RAM, 1 vCPU, 50GB SSD
- [ ] Note the IP address
- [ ] Set up SSH key access

### 2. Domain Configuration
- [ ] Point your domain (e.g., `api.remindly.com`) to your VPS IP
- [ ] Wait for DNS propagation (can take up to 48 hours)

### 3. Docker Registry
Choose one:
- **Docker Hub** (easiest): Create account at hub.docker.com
- **GitHub Container Registry** (free for public repos)
- **DigitalOcean Container Registry** (paid)

### 4. Rails Credentials
Generate production master key:
```bash
cd backend
EDITOR=nano rails credentials:edit --environment production
```
This creates `config/credentials/production.key` - **KEEP THIS SECRET!**

## Setup Steps

### Step 1: Install Kamal Locally
```bash
cd backend
bundle install
```

### Step 2: Configure Kamal

Edit `backend/config/deploy.yml`:

```yaml
service: remindly-backend
image: YOUR_DOCKERHUB_USERNAME/remindly-backend

servers:
  web:
    - YOUR_VPS_IP_ADDRESS

proxy:
  ssl: true
  host: api.remindly.com  # Your domain

registry:
  username: YOUR_DOCKERHUB_USERNAME
  password:
    - KAMAL_REGISTRY_PASSWORD

env:
  secret:
    - RAILS_MASTER_KEY
  clear:
    RAILS_ENV: production
    RAILS_LOG_LEVEL: info
```

### Step 3: Create Secrets File

Create `backend/.kamal/secrets`:

```bash
mkdir -p backend/.kamal
touch backend/.kamal/secrets
chmod 600 backend/.kamal/secrets
```

Add to `.kamal/secrets`:
```bash
KAMAL_REGISTRY_PASSWORD=your_dockerhub_token_or_password
RAILS_MASTER_KEY=your_production_master_key_from_step_4
```

**IMPORTANT:** Add `.kamal/secrets` to `.gitignore`!

### Step 4: Prepare VPS

SSH into your VPS and install Docker:
```bash
ssh root@YOUR_VPS_IP

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Verify
docker --version
```

### Step 5: Initial Deployment

From your local machine:

```bash
cd backend

# Setup (first time only)
kamal setup

# This will:
# - Install Kamal on the server
# - Set up Docker
# - Configure Traefik proxy
# - Deploy your app
# - Set up SSL with Let's Encrypt
```

### Step 6: Verify Deployment

```bash
# Check app status
kamal app details

# View logs
kamal app logs

# Access Rails console
kamal app exec -i "bin/rails console"
```

Visit `https://api.remindly.com` to verify!

## Common Commands

```bash
# Deploy updates
kamal deploy

# Rollback to previous version
kamal rollback

# View logs
kamal app logs -f

# Rails console
kamal app exec -i "bin/rails console"

# Run migrations
kamal app exec "bin/rails db:migrate"

# Restart app
kamal app restart

# SSH into container
kamal app exec -i bash

# View app details
kamal app details

# Remove everything (DANGEROUS!)
kamal remove
```

## Database Setup

Since you're using SQLite, the database is stored in a Docker volume. For production, consider:

### Option 1: Keep SQLite (Simple, Good for MVP)
Current setup uses a persistent volume - data persists across deployments.

### Option 2: Migrate to PostgreSQL (Recommended for Production)

1. Add PostgreSQL accessory to `deploy.yml`:
```yaml
accessories:
  db:
    image: postgres:16
    host: YOUR_VPS_IP
    port: "127.0.0.1:5432:5432"
    env:
      clear:
        POSTGRES_DB: remindly_production
      secret:
        - POSTGRES_PASSWORD
    directories:
      - data:/var/lib/postgresql/data
```

2. Add to `.kamal/secrets`:
```bash
POSTGRES_PASSWORD=your_secure_password
```

3. Update `config/database.yml`:
```yaml
production:
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  database: remindly_production
  username: postgres
  password: <%= ENV['POSTGRES_PASSWORD'] %>
  host: <%= ENV['DB_HOST'] || 'remindly-backend-db' %>
```

4. Add to `deploy.yml` env:
```yaml
env:
  clear:
    DB_HOST: remindly-backend-db
  secret:
    - POSTGRES_PASSWORD
```

## Troubleshooting

### SSL Certificate Issues
```bash
# Check Traefik logs
kamal traefik logs

# Restart Traefik
kamal traefik restart
```

### App Won't Start
```bash
# Check logs
kamal app logs --tail 100

# Common issues:
# - Missing RAILS_MASTER_KEY
# - Database connection issues
# - Port conflicts
```

### Database Issues
```bash
# Access database console
kamal app exec -i "bin/rails dbconsole"

# Run migrations
kamal app exec "bin/rails db:migrate"

# Reset database (DANGEROUS!)
kamal app exec "bin/rails db:reset"
```

### Can't Connect to Registry
```bash
# Test Docker Hub login locally
docker login -u YOUR_USERNAME

# Verify KAMAL_REGISTRY_PASSWORD is correct in .kamal/secrets
```

## Security Checklist

- [ ] Use SSH keys (not passwords) for VPS access
- [ ] Keep `.kamal/secrets` out of git
- [ ] Use strong RAILS_MASTER_KEY
- [ ] Enable firewall on VPS (allow ports 22, 80, 443)
- [ ] Regularly update VPS packages
- [ ] Use Docker Hub access tokens (not password)
- [ ] Set up automated backups for database

## Monitoring

### Basic Health Check
```bash
# Check if app is responding
curl https://api.remindly.com/health

# Check container status
kamal app details
```

### Set Up Uptime Monitoring
Consider using:
- UptimeRobot (free)
- Pingdom
- StatusCake

## Backup Strategy

### SQLite Backup
```bash
# Create backup
kamal app exec "sqlite3 /rails/db/production.sqlite3 '.backup /rails/storage/backup.db'"

# Download backup
scp root@YOUR_VPS_IP:/path/to/volume/backup.db ./backups/
```

### PostgreSQL Backup
```bash
# Create backup
kamal accessory exec db "pg_dump -U postgres remindly_production > /var/lib/postgresql/data/backup.sql"
```

## Cost Estimate (DigitalOcean)

- **Basic Droplet**: $12/month (2GB RAM, 1 vCPU, 50GB SSD)
- **Better Performance**: $24/month (4GB RAM, 2 vCPU, 80GB SSD)
- **Domain**: ~$12/year (from any registrar)
- **Total**: ~$13-25/month

## Next Steps

1. Complete the prerequisites checklist
2. Update `config/deploy.yml` with your actual values
3. Create `.kamal/secrets` file
4. Run `kamal setup`
5. Deploy with `kamal deploy`
6. Set up monitoring and backups

## Support

- Kamal Docs: https://kamal-deploy.org
- Kamal GitHub: https://github.com/basecamp/kamal
- Rails Deployment Guide: https://guides.rubyonrails.org/deployment.html
