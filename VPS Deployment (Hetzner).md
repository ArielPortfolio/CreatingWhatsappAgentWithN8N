# Deploy Your n8n Workflow to Hetzner VPS - Windows Guide

## Quick Overview

This guide is for users who **already have**:
- ✅ An n8n workflow JSON file
- ✅ Experience using n8n
- ✅ A Windows computer

You'll learn how to:
1. Deploy a production-ready n8n instance on Hetzner Cloud
2. Import your existing workflow
3. Set up WhatsApp integration with Evolution API
4. Secure everything with SSL
5. Keep it running 24/7

**Time estimate**: 45-60 minutes  
**Cost**: €4.90/month (Hetzner CX21) + domain (optional, ~$10-15/year)

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Phase 1: Deploy Hetzner Server](#phase-1-deploy-hetzner-server)
3. [Phase 2: Windows Setup & SSH](#phase-2-windows-setup--ssh)
4. [Phase 3: Server Security & Docker](#phase-3-server-security--docker)
5. [Phase 4: Deploy n8n & Evolution API](#phase-4-deploy-n8n--evolution-api)
6. [Phase 5: Domain & SSL Setup](#phase-5-domain--ssl-setup)
7. [Phase 6: Import Your Workflow](#phase-6-import-your-workflow)
8. [Phase 7: WhatsApp Connection](#phase-7-whatsapp-connection)
9. [Phase 8: Monitoring & Backups](#phase-8-monitoring--backups)
10. [Quick Reference](#quick-reference)
11. [Troubleshooting](#troubleshooting)
12. [Appendix: Shortcuts & Templates](#appendix-shortcuts--templates)

---

## Prerequisites

### What You Need

**Required:**
- Windows 10/11 computer
- Your n8n workflow JSON file (downloaded and ready)
- Hetzner account with payment method
- 1 hour of time

**Recommended:**
- A domain name (for SSL and webhooks)
  - If you don't have one: Get one from Namecheap, GoDaddy, or Cloudflare (~$10-15/year)
- Basic command line familiarity (we'll guide you through everything)

**Optional:**
- WinSCP (for easy file transfers)

---

## Phase 1: Deploy Hetzner Server

### Step 1: Create Hetzner Account

1. Go to https://www.hetzner.com/cloud
2. Click **"Sign Up"** and complete registration
3. Verify your email
4. Add payment method (credit card or PayPal)

### Step 2: Create Project & Server

1. **Create Project**:
   - Click **"New Project"**
   - Name: `n8n-production` (or whatever you prefer)

2. **Add Server**:
   - Click **"Add Server"**
   
3. **Configure Server**:
   - **Location**: Choose closest to you
     - Europe: Nuremberg or Helsinki
     - US: Ashburn
   
   - **Image**: Ubuntu 22.04 LTS
   
   - **Type**: 
     - **Recommended**: CX21 (2 vCPU, 4GB RAM) - €4.90/month
     - If heavy AI usage: CX31 (2 vCPU, 8GB RAM) - €8.90/month
   
   - **Networking**: Keep defaults
   
   - **SSH Keys**: Skip (we'll set up from Windows)
   
   - **Firewalls**: Click **"Create Firewall"**
     - Name: `n8n-firewall`
     - **Inbound Rules** (click Add Rule for each):
       - Protocol: TCP, Port: 22 (SSH), Source: Any IPv4, Any IPv6
       - Protocol: TCP, Port: 80 (HTTP), Source: Any IPv4, Any IPv6
       - Protocol: TCP, Port: 443 (HTTPS), Source: Any IPv4, Any IPv6
     - **Outbound**: Allow all (default)
   
   - **Backups**: ✅ Enable (adds 20%, worth it!)
   
   - **Name**: `n8n-prod-1`

4. Click **"Create & Buy Now"**

### Step 3: Save Server Credentials

⚠️ **Important**: Hetzner will email you the root password. Save it somewhere secure!

Also note your **server IP address** (shown in the Hetzner console).

---

## Phase 2: Windows Setup & SSH

### Step 4: Install Windows Terminal

1. Open **Microsoft Store**
2. Search for **"Windows Terminal"**
3. Click **"Get"** to install
4. Pin to taskbar for easy access

> **Alternative**: You can use PowerShell, but Windows Terminal is much better.

### Step 5: Generate SSH Keys

Open Windows Terminal and run:

```powershell
# Create .ssh directory
mkdir $HOME\.ssh -ErrorAction SilentlyContinue

# Generate SSH key
ssh-keygen -t ed25519 -C "your_email@example.com"
```

**Prompts**:
- **File location**: Press Enter (accept default)
- **Passphrase**: 
  - Enter a strong passphrase (recommended) OR
  - Press Enter twice for no passphrase

### Step 6: View Your Public Key

```powershell
Get-Content $HOME\.ssh\id_ed25519.pub
```

**Copy the entire output** (starts with `ssh-ed25519...`). You'll need it soon.

### Step 7: First Connection to Server

Connect using the root password from Hetzner's email:

```powershell
ssh root@YOUR_SERVER_IP
```

- Type `yes` when asked about the fingerprint
- Paste the root password (right-click to paste)

You're in! 🎉

---

## Phase 3: Server Security & Docker

### Step 8: Update System

```bash
apt update && apt upgrade -y
```

Wait for updates to complete (2-5 minutes).

### Step 9: Create Non-Root User

```bash
# Create user
adduser n8n
```

**Prompts**:
- **Password**: Enter a strong password
- **Full Name**: Press Enter (or enter your name)
- **Other info**: Press Enter through all
- **Confirm**: Type `Y`

```bash
# Give sudo permissions
usermod -aG sudo n8n
```

### Step 10: Add Your SSH Key

```bash
# Create SSH directory for new user
mkdir -p /home/n8n/.ssh
chmod 700 /home/n8n/.ssh

# Open authorized_keys file
nano /home/n8n/.ssh/authorized_keys
```

**Now**:
1. Open a **NEW** Windows Terminal tab (Ctrl+Shift+T)
2. Run: `Get-Content $HOME\.ssh\id_ed25519.pub`
3. Copy the output
4. Go back to your server tab
5. **Right-click to paste** the SSH key
6. Press **Ctrl+X**, then **Y**, then **Enter** to save

```bash
# Set correct permissions
chmod 600 /home/n8n/.ssh/authorized_keys
chown -R n8n:n8n /home/n8n/.ssh
```

### Step 11: Test SSH Key Login

Open a **NEW** Windows Terminal tab:

```powershell
ssh n8n@YOUR_SERVER_IP
```

If you set a passphrase, enter it. You should connect without the server password! 

✅ If it works, close the root connection and use only the `n8n` user from now on.

### Step 12: Secure SSH

```bash
sudo nano /etc/ssh/sshd_config
```

**Find and change** (use Ctrl+W to search):
- `PermitRootLogin` → change to `PermitRootLogin no`
- `PasswordAuthentication` → change to `PasswordAuthentication no`

**Save**: Ctrl+X, Y, Enter

```bash
# Restart SSH
sudo systemctl restart sshd
```

### Step 13: Enable Firewall

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

Type `y` and press Enter.

### Step 14: Install Docker

Copy and paste these commands **one at a time**:

```bash
# Install prerequisites
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common

# Add Docker GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io

# Add user to docker group
sudo usermod -aG docker ${USER}

# Apply group changes
newgrp docker
```

### Step 15: Install Docker Compose

```bash
sudo apt install -y docker-compose-plugin

# Verify
docker compose version
```

You should see version output like `v2.x.x`.

---

## Phase 4: Deploy n8n & Evolution API

### Step 16: Create Project Directory

```bash
mkdir -p ~/.n8n
cd ~/.n8n
```

### Step 17: Generate Encryption Key

```bash
openssl rand -base64 32
```

**Copy the output** - you'll need it in the next step.

### Step 18: Create Environment File

```bash
nano .env
```

**Paste this** and **replace** the placeholder values:

```env
# Domain Configuration
# Replace with YOUR actual domain
N8N_HOST=n8n.yourdomain.com
N8N_PROTOCOL=https
WEBHOOK_URL=https://n8n.yourdomain.com/

# Timezone
# Find yours at: https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
GENERIC_TIMEZONE=Asia/Jerusalem

# n8n Login Credentials - CHANGE THESE!
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=YourSecurePassword123!

# Encryption Key - paste the key from Step 17
N8N_ENCRYPTION_KEY=paste_your_generated_key_here

# Evolution API Key - make up a strong key
EVOLUTION_API_KEY=Evol_SecureKey_2024_XyZ789!
```

**Important replacements**:
- `n8n.yourdomain.com` → your actual domain
- `Asia/Jerusalem` → your timezone
- `YourSecurePassword123!` → strong password for n8n
- `paste_your_generated_key_here` → the key from Step 17
- `Evol_SecureKey_2024_XyZ789!` → make up a strong API key

**Save**: Ctrl+X, Y, Enter

### Step 19: Create Docker Compose File

```bash
nano docker-compose.yml
```

**Paste this entire configuration**:

```yaml
version: '3.8'

services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      - N8N_HOST=${N8N_HOST}
      - N8N_PORT=5678
      - N8N_PROTOCOL=${N8N_PROTOCOL}
      - WEBHOOK_URL=${WEBHOOK_URL}
      - GENERIC_TIMEZONE=${GENERIC_TIMEZONE}
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_BASIC_AUTH_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_BASIC_AUTH_PASSWORD}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
    volumes:
      - ./n8n_data:/home/node/.n8n
      - ./local_files:/files
    networks:
      - n8n-network

  evolution-api:
    image: atendai/evolution-api:latest
    container_name: evolution-api
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      - SERVER_URL=https://whatsapp.yourdomain.com
      - AUTHENTICATION_API_KEY=${EVOLUTION_API_KEY}
    volumes:
      - ./evolution_data:/evolution/instances
      - ./evolution_store:/evolution/store
    networks:
      - n8n-network

networks:
  n8n-network:
    driver: bridge
```

**Save**: Ctrl+X, Y, Enter

### Step 20: Start Services

```bash
docker compose up -d
```

This will download Docker images (takes 2-3 minutes first time).

**Verify it's running**:

```bash
docker compose ps
```

You should see both `n8n` and `evolution-api` with status "Up".

**Check logs** (optional):

```bash
docker compose logs -f n8n
```

Press Ctrl+C to exit logs.

---

## Phase 5: Domain & SSL Setup

### Step 21: Configure DNS Records

Go to your domain registrar (Namecheap, GoDaddy, Cloudflare, etc.):

1. Find **DNS Management** or **DNS Settings**

2. Add **A Record** for n8n:
   - **Type**: A
   - **Name/Host**: `n8n`
   - **Value/Points to**: Your Hetzner server IP
   - **TTL**: 300 or Automatic

3. Add **A Record** for WhatsApp:
   - **Type**: A
   - **Name/Host**: `whatsapp`
   - **Value/Points to**: Your Hetzner server IP
   - **TTL**: 300 or Automatic

4. **Wait 5-10 minutes** for DNS to propagate

**Test from Windows Terminal**:

```powershell
ping n8n.yourdomain.com
```

You should see your server IP in the response.

### Step 22: Install Nginx

```bash
sudo apt install -y nginx
```

### Step 23: Configure Nginx for n8n

```bash
sudo nano /etc/nginx/sites-available/n8n
```

**Paste this** (replace `n8n.yourdomain.com` with your domain):

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name n8n.yourdomain.com;

    location / {
        proxy_pass http://localhost:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**Save**: Ctrl+X, Y, Enter

```bash
# Enable site
sudo ln -s /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/

# Test configuration
sudo nginx -t

# Restart Nginx
sudo systemctl restart nginx
```

### Step 24: Configure Nginx for WhatsApp

```bash
sudo nano /etc/nginx/sites-available/whatsapp
```

**Paste this** (replace `whatsapp.yourdomain.com` with your domain):

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name whatsapp.yourdomain.com;

    location / {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**Save**: Ctrl+X, Y, Enter

```bash
# Enable site
sudo ln -s /etc/nginx/sites-available/whatsapp /etc/nginx/sites-enabled/

# Test and restart
sudo nginx -t
sudo systemctl restart nginx
```

### Step 25: Install SSL Certificates

```bash
# Install Certbot
sudo apt install -y certbot python3-certbot-nginx

# Get SSL for n8n
sudo certbot --nginx -d n8n.yourdomain.com
```

**Follow prompts**:
1. Enter your email
2. Type `Y` to agree to terms
3. Type `Y` or `N` for newsletter (your choice)
4. Choose `2` to redirect HTTP to HTTPS

```bash
# Get SSL for WhatsApp
sudo certbot --nginx -d whatsapp.yourdomain.com
```

Follow the same prompts.

**Test auto-renewal**:

```bash
sudo certbot renew --dry-run
```

You should see "Congratulations, all simulated renewals succeeded".

---

## Phase 6: Import Your Workflow

### Step 26: Access n8n

On your **Windows computer**:

1. Open your web browser
2. Go to: `https://n8n.yourdomain.com`
3. Log in with credentials from your `.env` file:
   - Username: (your `N8N_BASIC_AUTH_USER`)
   - Password: (your `N8N_BASIC_AUTH_PASSWORD`)

🎉 **You're in n8n!**

### Step 27: Import Your Workflow JSON

**Option A: Direct Import (Easiest)**

1. In n8n, click **"Add workflow"** (top right)
2. Click the **three dots** menu (⋮) next to the workflow name
3. Select **"Import from File"**
4. Click **"Select file to import"**
5. Browse to your workflow JSON file
6. Click **"Import"**

**Option B: Copy-Paste Import**

1. Open your workflow JSON file in Notepad or VS Code
2. Copy the entire contents (Ctrl+A, Ctrl+C)
3. In n8n, click **"Add workflow"**
4. Click the **three dots** menu (⋮)
5. Select **"Import from File"**
6. Click **"Or paste JSON"**
7. Paste your JSON (Ctrl+V)
8. Click **"Import"**

### Step 28: Update Credentials

After importing, you'll likely need to reconnect credentials:

1. Click on nodes with warning icons (⚠️)
2. For each node:
   - Click **"Create New Credential"** or select existing
   - Enter your API keys/credentials
   - Click **"Save"**

**Common credentials you might need**:
- OpenAI API key
- Anthropic API key (for Claude)
- Gmail OAuth
- Google Drive OAuth
- Any other services your workflow uses

### Step 29: Update Webhook URLs

If your workflow has webhooks:

1. Click on webhook nodes
2. Update the **Production URL** to use your domain:
   - Old: `http://localhost:5678/webhook/...`
   - New: `https://n8n.yourdomain.com/webhook/...`
3. Copy the new webhook URL for later use

### Step 30: Test & Activate

1. Click **"Execute Workflow"** to test
2. Check for any errors
3. Fix any issues
4. Click **"Active"** toggle (top right) to enable the workflow
5. Click **"Save"**

---

## Phase 7: WhatsApp Connection

### Step 31: Access Evolution API Manager

In your browser, go to:

```
https://whatsapp.yourdomain.com/manager
```

### Step 32: Create WhatsApp Instance

1. Click **"Create Instance"**
2. **Instance Name**: `my-assistant` (or whatever you prefer)
3. You'll see a QR code

### Step 33: Connect Your Phone

On your **smartphone**:

1. Open **WhatsApp**
2. Tap **three dots** (⋮) or **Settings**
3. Tap **"Linked Devices"**
4. Tap **"Link a Device"**
5. **Scan the QR code** on your computer screen
6. Wait for **"Connected"** status

### Step 34: Configure Webhook in n8n

Back in your n8n workflow:

1. Add or find your **Webhook** node
2. Set the **Path**: `/whatsapp` (or custom path)
3. Copy the **Production Webhook URL**

Example: `https://n8n.yourdomain.com/webhook/whatsapp`

### Step 35: Test WhatsApp Integration

Send a test message to your WhatsApp number. Your workflow should trigger!

**If it doesn't work**:
- Check n8n execution logs
- Verify webhook is active
- Check Evolution API logs: `docker compose logs evolution-api`

---

## Phase 8: Monitoring & Backups

### Step 36: Create Monitoring Script

```bash
nano ~/monitor.sh
```

**Paste**:

```bash
#!/bin/bash
echo "=== Docker Status ==="
docker compose -f ~/.n8n/docker-compose.yml ps

echo -e "\n=== Disk Usage ==="
df -h | grep -E 'Filesystem|/dev/sda'

echo -e "\n=== Memory Usage ==="
free -h

echo -e "\n=== n8n Logs (last 20 lines) ==="
docker compose -f ~/.n8n/docker-compose.yml logs --tail=20 n8n

echo -e "\n=== Evolution API Logs (last 10 lines) ==="
docker compose -f ~/.n8n/docker-compose.yml logs --tail=10 evolution-api
```

**Save**: Ctrl+X, Y, Enter

```bash
chmod +x ~/monitor.sh
```

**Run anytime**:

```bash
~/monitor.sh
```

### Step 37: Create Backup Script

```bash
mkdir ~/backups
nano ~/backup.sh
```

**Paste**:

```bash
#!/bin/bash
BACKUP_DIR=~/backups
DATE=$(date +%Y%m%d_%H%M%S)

# Stop services
cd ~/.n8n
docker compose down

# Create backup
tar -czf $BACKUP_DIR/n8n_backup_$DATE.tar.gz ~/.n8n

# Restart services
docker compose up -d

# Keep only last 7 backups
ls -t $BACKUP_DIR/n8n_backup_*.tar.gz | tail -n +8 | xargs -r rm

echo "Backup completed: n8n_backup_$DATE.tar.gz"
```

**Save**: Ctrl+X, Y, Enter

```bash
chmod +x ~/backup.sh
```

### Step 38: Schedule Automatic Backups

```bash
crontab -e
```

Choose **nano** (usually option 1)

**Add this line at the bottom**:

```
0 2 * * 0 ~/backup.sh >> ~/backup.log 2>&1
```

This runs backups every **Sunday at 2 AM**.

**Save**: Ctrl+X, Y, Enter

### Step 39: Manual Backup (Run Now)

```bash
~/backup.sh
```

### Step 40: Download Backup to Windows

**Option A - Install WinSCP** (recommended):

1. Download from: https://winscp.net/eng/download.php
2. Install (accept defaults)
3. Open WinSCP
4. **New Site**:
   - File protocol: SCP
   - Host name: Your server IP
   - Port: 22
   - User name: n8n
   - Password: (leave blank - we use SSH key)
5. Click **"Advanced"** → **"SSH"** → **"Authentication"**
6. Browse to: `C:\Users\YourUsername\.ssh\id_ed25519`
7. Click OK → Save → Login
8. Navigate to `/home/n8n/backups` on right side
9. Drag backup file to left side (Windows)

**Option B - Command line**:

In Windows Terminal (PowerShell):

```powershell
scp n8n@YOUR_SERVER_IP:~/backups/n8n_backup_*.tar.gz C:\Users\YourUsername\Downloads\
```

---

## Quick Reference

### Server Connection

```powershell
# Connect to server
ssh n8n@YOUR_SERVER_IP
```

### Access URLs

- **n8n**: `https://n8n.yourdomain.com`
- **WhatsApp Manager**: `https://whatsapp.yourdomain.com/manager`

### Common Commands

```bash
# Go to n8n directory
cd ~/.n8n

# View logs
docker compose logs -f n8n
docker compose logs -f evolution-api

# Restart services
docker compose restart

# Stop services
docker compose down

# Start services
docker compose up -d

# Update n8n
docker compose pull
docker compose up -d

# Check status
docker compose ps

# Monitor server
~/monitor.sh

# Manual backup
~/backup.sh
```

### Server Maintenance

```bash
# Check disk space
df -h

# Check memory
free -h

# Check Docker stats
docker stats

# View SSL certificates
sudo certbot certificates

# Renew SSL manually
sudo certbot renew

# Restart Nginx
sudo systemctl restart nginx
```

---

## Troubleshooting

### Can't Access n8n in Browser

**Check DNS**:

```powershell
# From Windows Terminal
nslookup n8n.yourdomain.com
```

Should return your server IP.

**Check services**:

```bash
# On server
docker compose ps
sudo systemctl status nginx
```

**Check firewall**:

```bash
sudo ufw status
```

### Workflow Not Triggering

**Check activation**:
- Is the workflow toggle "Active"?
- Are webhook nodes properly configured?

**Check logs**:

```bash
docker compose logs -f n8n
```

**Check executions**:
- In n8n UI, click "Executions" tab
- Look for errors

### WhatsApp Not Connected

**Check Evolution API**:

```bash
docker compose logs -f evolution-api
```

**Re-scan QR**:
- Go to `https://whatsapp.yourdomain.com/manager`
- Delete instance and create new one
- Scan QR code again

### Out of Disk Space

```bash
# Check space
df -h

# Clean Docker
docker system prune -a

# Remove old backups
rm ~/backups/old_backup_*.tar.gz
```

### SSL Certificate Issues

```bash
# Check certificates
sudo certbot certificates

# Renew manually
sudo certbot renew --force-renewal

# Restart Nginx
sudo systemctl restart nginx
```

### Server Running Slow

**Check resources**:

```bash
htop  # (install with: sudo apt install htop)
docker stats
```

**Upgrade server**:
1. Go to Hetzner Cloud Console
2. Select your server
3. Click "Resize"
4. Choose larger plan (CX31, CX41, etc.)

---

## Appendix: Shortcuts & Templates

### A1. Pre-configured VPS Templates

#### Hetzner n8n Marketplace Image

**Unfortunately**, Hetzner does not currently offer a marketplace image for n8n. However, you can use community-created scripts:

**n8n Quick Install Script** (use at your own risk):

```bash
# After connecting to fresh Ubuntu server
curl -o- https://raw.githubusercontent.com/n8n-io/n8n-hosting/master/docker-compose/with-traefik/install.sh | bash
```

Source: https://github.com/n8n-io/n8n-hosting

#### DigitalOcean 1-Click n8n

DigitalOcean offers a 1-click n8n installation:

1. Go to: https://marketplace.digitalocean.com/apps/n8n
2. Click "Create n8n Droplet"
3. Choose plan (minimum $12/month for 2GB RAM)
4. Select region
5. Click "Create Droplet"
6. SSH into droplet and follow setup wizard

**Pros**: Faster setup, pre-configured  
**Cons**: More expensive than Hetzner, less control

#### Render.com n8n Template

Free tier available with limitations:

1. Go to: https://render.com
2. Click "New +" → "Blueprint"
3. Connect GitHub
4. Use n8n template from: https://github.com/n8n-io/n8n-render
5. Configure environment variables
6. Deploy

**Pros**: Free tier available  
**Cons**: Free tier sleeps after inactivity, limited resources

---

### A2. n8n Workflow Templates

#### WhatsApp AI Assistant Templates

**Option 1: n8n Community Templates**

Browse official templates:
- https://n8n.io/workflows

Search for:
- "WhatsApp AI"
- "Personal Assistant"
- "AI Chatbot"

**Popular WhatsApp Templates**:

1. **WhatsApp Business Automation**
   - Link: https://n8n.io/workflows/1234 (example)
   - Features: Auto-replies, customer support, FAQ bot

2. **AI-Powered Personal Assistant**
   - Search: "AI Assistant OpenAI WhatsApp"
   - Features: Task management, reminders, Q&A

3. **Multi-Platform Chatbot**
   - Search: "Multi-channel AI bot"
   - Features: WhatsApp, Telegram, Slack integration

**How to Use Templates**:

1. Go to n8n.io/workflows
2. Browse or search
3. Click template you want
4. Click "Copy to Clipboard" or "Download"
5. In your n8n instance:
   - Click "Add workflow"
   - Click "⋮" → "Import from File"
   - Paste or upload JSON
   - Configure credentials

#### Option 2: GitHub Community Workflows

**Popular repositories**:

1. **n8n-workflows** by digital-boss
   - https://github.com/digital-boss/n8n-workflows
   - Contains various automation examples

2. **n8n-workflow-template-repo**
   - https://github.com/n8n-io/n8n-workflow-template-repo
   - Official n8n examples

**How to use**:
1. Browse repository
2. Download `.json` workflow files
3. Import into your n8n instance

#### Option 3: Build from Scratch (Basic Template)

Here's a basic WhatsApp AI Assistant structure:

**Nodes**:
1. **Webhook Trigger** - Receive WhatsApp messages
2. **Function** - Extract message text and sender
3. **OpenAI/Claude** - Generate AI response
4. **HTTP Request** - Send reply via Evolution API

**Quick Start JSON** (basic template):

```json
{
  "name": "WhatsApp AI Assistant",
  "nodes": [
    {
      "parameters": {
        "path": "whatsapp",
        "responseMode": "responseNode"
      },
      "name": "Webhook",
      "type": "n8n-nodes-base.webhook",
      "position": [250, 300]
    },
    {
      "parameters": {
        "functionCode": "return [\n  {\n    json: {\n      message: $input.item.json.data?.message?.conversation || '',\n      from: $input.item.json.data?.key?.remoteJid || ''\n    }\n  }\n];"
      },
      "name": "Extract Message",
      "type": "n8n-nodes-base.function",
      "position": [450, 300]
    }
  ]
}
```

This is a starting point - customize based on your needs!

---

### A3. Evolution API Alternatives

If Evolution API doesn't work for you:

#### 1. Twilio (Official WhatsApp Business API)

**Pros**: Official, reliable, compliant  
**Cons**: Requires business verification, costs money

Setup:
1. Sign up: https://www.twilio.com/whatsapp
2. Get WhatsApp Business API access
3. Use Twilio node in n8n

#### 2. Baileys (Open Source)

**Pros**: Free, no business verification  
**Cons**: Unofficial, might violate WhatsApp TOS

Install via community node:
```bash
cd ~/.n8n/n8n_data
npm install n8n-nodes-baileys
```

#### 3. WA Web.js

**Pros**: Popular, well-maintained  
**Cons**: Requires custom integration

GitHub: https://github.com/pedroslopez/whatsapp-web.js

---

### A4. Quick Migration Checklist

If moving from another n8n instance:

- [ ] Export all workflows as JSON
- [ ] Document all credentials (API keys, OAuth tokens)
- [ ] Export environment variables
- [ ] Note any custom nodes installed
- [ ] Backup workflow execution data (if needed)
- [ ] List all webhook URLs for updating
- [ ] Document any custom code/functions
- [ ] Export any files used in workflows

---

### A5. Useful Resources

**Official Documentation**:
- n8n Docs: https://docs.n8n.io
- n8n Community: https://community.n8n.io
- Evolution API Docs: https://doc.evolution-api.com

**Video Tutorials**:
- n8n YouTube: https://www.youtube.com/c/n8n-io
- Search: "n8n WhatsApp automation"

**Community Support**:
- n8n Discord: https://discord.gg/n8n
- Reddit: r/n8n
- GitHub Discussions: https://github.com/n8n-io/n8n/discussions

**Hetzner Support**:
- Docs: https://docs.hetzner.com
- Community: https://community.hetzner.com

---

### A6. Cost Optimization Tips

**Save Money**:

1. **Start Small**: Use CX21 (€4.90/month), upgrade if needed
2. **Use Hetzner**: Cheaper than DigitalOcean/AWS
3. **Shared Domain**: Use subdomain on existing domain
4. **Free SSL**: Let's Encrypt is free forever
5. **Efficient Workflows**: Optimize to reduce execution time
6. **Monitor Usage**: Check resource usage weekly
7. **Disable Unused Workflows**: Save CPU/RAM

**Typical Monthly Costs**:
- Hetzner CX21: €4.90
- Domain (yearly): ~€10-15 (€0.83-1.25/month)
- Backups (20%): €0.98
- **Total**: ~€6-7/month

Compare to n8n Cloud Pro: $50/month

**Savings**: ~85% cheaper! 💰

---

## Final Checklist

Before you're done, verify:

- ✅ Server deployed and secured
- ✅ SSH key authentication working
- ✅ Docker and Docker Compose installed
- ✅ n8n accessible via HTTPS
- ✅ Workflow imported successfully
- ✅ All credentials reconnected
- ✅ WhatsApp connected (if using)
- ✅ Workflow active and tested
- ✅ SSL certificates installed
- ✅ Backups configured
- ✅ Monitoring script created
- ✅ Firewall enabled

---

## Next Steps

1. **Test thoroughly**: Run your workflow multiple times
2. **Monitor**: Check logs daily for first week
3. **Optimize**: Improve workflow based on usage
4. **Expand**: Add more integrations (Gmail, Drive, etc.)
5. **Secure**: Regularly update server packages
6. **Scale**: Upgrade server if needed

---

## Support

Need help?

- **n8n Issues**: https://community.n8n.io
- **Hetzner Issues**: https://community.hetzner.com
- **Evolution API Issues**: https://github.com/EvolutionAPI/evolution-api

---

**Congratulations!** 🎉

Your n8n workflow is now running 24/7 on a production VPS!

---

*Last Updated: April 2026*  
*Guide Version: 2.0*