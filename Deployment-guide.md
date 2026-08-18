# Deployment Guide — Contractor Growth OS

### Written for someone who knows HTML/CSS/JS and nothing else yet

---

## First — What Is Everything? (Plain English)

Before touching any command, understand what each piece IS and WHY it exists.

**Your SvelteKit App**
This is your actual product — the website + the backend logic. Think of it as a restaurant. The frontend (pages users see) is the dining room. The backend (API routes) is the kitchen. Both are inside the same SvelteKit project.

**Supabase**
This is your database — where all your data lives (customers, jobs, invoices, etc.). Think of it as a giant spreadsheet locked in a secure room. Right now it lives on Supabase's servers in the cloud (free to start). Later you'll move it to your own server.

**Redis**
This is a super-fast memory board. Imagine your kitchen staff writing frequently-needed info on a whiteboard instead of walking to the filing room every time. Redis holds hot data (org settings, feature flags, lookup tables) in RAM so your app doesn't ask the database for the same thing thousands of times per minute.

**BullMQ**
This is a job queue — a to-do list for background tasks. When a user triggers "send invoice emails to 50 clients," BullMQ puts that task in a queue and processes it in the background without making the user wait. BullMQ uses Redis as its storage.

**Docker**
This is a lunchbox system. You pack your app + everything it needs into a sealed box (called a container). That box runs exactly the same way on any computer — your laptop, your VPS, anywhere. No "it works on my machine" problems.

**Docker Compose**
One file (`docker-compose.yml`) that says: "start ALL my containers together and connect them." One command and your entire app stack starts.

**Nginx** (say: "engine-x")
This is the reception desk of your server. When someone visits `yourapp.com`, Nginx receives the request and forwards it to your SvelteKit app running on port 3000. It also handles HTTPS (the padlock).

**VPS (Virtual Private Server)**
A computer in a data centre that belongs to you, always on, always connected to the internet. This is where everything lives in production. Think of it as renting a room in a secure building where your app sleeps 24/7.

---

## Your Journey — 3 Phases

```
Phase 1 (NOW)          Phase 2 (DEPLOY)         Phase 3 (LATER)
──────────────         ─────────────────         ───────────────
Your Laptop            Your VPS Server           Your VPS Server
 └─ SvelteKit   ──▶    └─ SvelteKit              └─ SvelteKit
                        └─ Redis                  └─ Redis
Supabase Cloud          └─ Nginx                  └─ Nginx
(remote, already        └─ Certbot (HTTPS)         └─ Supabase (local)
 working)
                       Supabase Cloud             (same VPS, no cloud)
                       (still remote, easy)
```

Phase 2 is what this guide covers fully. Phase 3 comes later when you're ready.

---

## Phase 2 — Deploy Your App to a VPS

### Step 1 — Get a VPS

Go to **Hetzner** (hetzner.com) — cheapest good quality servers.

Pick:

- Ubuntu 24.04 (operating system)
- CX22 plan (2 CPU, 4GB RAM) — good starting point, ~€4/month

When created, Hetzner gives you:

- An **IP address** (looks like `49.13.45.123`)
- A **root password** (or SSH key if you set one up)

Write these down.

---

### Step 2 — Connect to Your VPS

Your VPS is a computer with no screen. You control it by typing commands from your laptop through SSH.

On your laptop, open your terminal and type:

```bash
ssh root@49.13.45.123
```

Replace `49.13.45.123` with your actual VPS IP. Type your password when asked.

You are now "inside" your VPS. Every command you type from now runs on that server, not your laptop.

First thing — update the system:

```bash
apt update && apt upgrade -y
```

This is like doing Windows Update. Takes 1–2 minutes.

---

### Step 3 — Install Docker

Docker is the engine that runs your containers. Run these three commands one by one:

```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm get-docker.sh
```

The first command downloads the installer. The second runs it. The third deletes the installer file (you don't need it anymore).

Check it worked:

```bash
docker --version
```

You should see something like `Docker version 27.x.x`. Good.

---

### Step 4 — Install Nginx

Nginx is your reception desk. Install it:

```bash
apt install nginx certbot python3-certbot-nginx -y
```

Start it and make it auto-start when the server reboots:

```bash
systemctl enable nginx
systemctl start nginx
```

Check it works — open your browser and visit `http://49.13.45.123` (your IP). You should see an Nginx welcome page. That means Nginx is running.

---

### Step 5 — Prepare Your SvelteKit App

Back on your **laptop** (not the VPS), do these things:

**5a — Install the Node.js adapter**

Your SvelteKit app needs to know it will run as a real server (not just in dev mode). Install this:

```bash
npm install @sveltejs/adapter-node
```

**5b — Tell SvelteKit to use it**

Open `svelte.config.js` and change the adapter line:

```js
// Change this:
import adapter from '@sveltejs/adapter-auto';

// To this:
import adapter from '@sveltejs/adapter-node';
```

The rest of the file stays the same.

**5c — Create a Dockerfile**

A Dockerfile is a recipe that tells Docker how to package your app. Create a file called `Dockerfile` (no extension) in the root of your project:

```dockerfile
# Stage 1: Build the app
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Stage 2: Run the app (smaller final image)
FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/build ./build
COPY --from=builder /app/package*.json ./
RUN npm ci --omit=dev
EXPOSE 3000
ENV NODE_ENV=production
CMD ["node", "build/index.js"]
```

Think of this as two steps: first build your app, then package only the built result into a clean container.

**5d — Create a .dockerignore file**

Create `.dockerignore` in your project root. This tells Docker what NOT to pack (saves space and time):

```
node_modules
.svelte-kit
.env
.env.*
*.md
.git
```

---

### Step 6 — Create docker-compose.yml

This is the file that starts ALL your containers together. Create `docker-compose.yml` in your project root:

```yaml
services:
  app:
    build: .
    ports:
      - '3000:3000'
    env_file:
      - .env.production
    environment:
      NODE_ENV: production
      PORT: '3000'
    depends_on:
      - redis
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    command: >
      redis-server
      --maxmemory 512mb
      --maxmemory-policy volatile-lru
      --appendonly yes
    volumes:
      - redis_data:/data
    restart: unless-stopped

volumes:
  redis_data:
```

What this does:

- `app` — builds and runs your SvelteKit app on port 3000
- `redis` — starts Redis with 512MB limit and the right eviction policy
- `redis_data` — saves Redis data to disk so it survives restarts
- `depends_on` — Redis starts before your app (your app needs Redis ready)
- `restart: unless-stopped` — if a container crashes, Docker restarts it automatically

---

### Step 7 — Create Your Production .env File

Your app needs secret keys to talk to Supabase and other services. Create `.env.production` in your project root:

```env
# Supabase (get these from your Supabase project dashboard → Settings → API)
PUBLIC_SUPABASE_URL=https://your-project-ref.supabase.co
PUBLIC_SUPABASE_ANON_KEY=your-anon-key-here
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key-here
DATABASE_URL=postgresql://postgres.your-ref:[password]@aws-0-ap-southeast-1.pooler.supabase.com:6543/postgres

# Redis (the app and Redis talk inside Docker's private network)
REDIS_URL=redis://redis:6379

# App
NODE_ENV=production
PORT=3000
```

**Important about `REDIS_URL`:** Notice it says `redis://redis:6379` — `redis` here is the name of the Redis container from docker-compose.yml. Inside Docker, containers talk to each other by their service name, not by an IP address.

**NEVER commit `.env.production` to Git.** Add it to `.gitignore`:

```
.env.production
.env.local
.env
```

---

### Step 8 — Push Your Code to GitHub

On your laptop:

```bash
git add .
git commit -m "add docker setup"
git push origin main
```

---

### Step 9 — Get Your Code onto the VPS and Run It

Back in your VPS terminal:

**9a — Install Git on the VPS:**

```bash
apt install git -y
```

**9b — Clone your project:**

```bash
cd /var/www
git clone https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git app
cd app
```

Replace `YOUR_USERNAME` and `YOUR_REPO_NAME` with your actual GitHub info.

**9c — Add your production .env file:**

You cannot push `.env.production` to GitHub (it has secrets). Instead, create it directly on the server:

```bash
nano .env.production
```

This opens a text editor in the terminal. Paste your env variables (same content as Step 7). Then press `Ctrl+X`, then `Y`, then `Enter` to save.

**9d — Build and start everything:**

```bash
docker compose up -d --build
```

- `--build` — tells Docker to build your app image fresh
- `-d` — runs everything in the background (so your terminal is free)

This takes 2–5 minutes the first time. Docker is downloading, building, and starting.

**Check if it worked:**

```bash
docker compose ps
```

You should see both `app` and `redis` with status `running`.

Test your app is running:

```bash
curl http://localhost:3000
```

If you get HTML back, your app is running inside Docker.

---

### Step 10 — Point Nginx to Your App

Right now Nginx shows its welcome page. You need to tell it to forward traffic to your SvelteKit app.

Create a config file for your site:

```bash
nano /etc/nginx/sites-available/myapp
```

Paste this (replace `yourdomain.com` with your actual domain):

```nginx
server {
    listen 80;
    server_name yourdomain.com www.yourdomain.com;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Save with `Ctrl+X`, `Y`, `Enter`.

Now activate this config:

```bash
ln -s /etc/nginx/sites-available/myapp /etc/nginx/sites-enabled/
nginx -t
systemctl reload nginx
```

`nginx -t` tests your config for mistakes. If it says `syntax is ok`, proceed with reload.

---

### Step 11 — Point Your Domain to the VPS

Go to wherever you bought your domain (Namecheap, GoDaddy, Cloudflare, etc.) and add a DNS record:

```
Type: A
Name: @          (means the root domain)
Value: 49.13.45.123   (your VPS IP)
TTL: Auto

Type: A
Name: www
Value: 49.13.45.123
TTL: Auto
```

DNS changes take 1–60 minutes to spread. Test by visiting `http://yourdomain.com` — you should see your app.

---

### Step 12 — Get HTTPS (the Padlock)

Nobody trusts a site without HTTPS. Get a free SSL certificate:

```bash
certbot --nginx -d yourdomain.com -d www.yourdomain.com
```

Certbot asks for your email and asks you to agree to terms. Say yes. It automatically edits your Nginx config to enable HTTPS and sets up auto-renewal.

Visit `https://yourdomain.com` — you should see the padlock. You're live. 🎉

---

## Updating Your App (When You Change Code)

Every time you change code and want to push it live:

**On your laptop:**

```bash
git add .
git commit -m "describe what you changed"
git push origin main
```

**On your VPS:**

```bash
cd /var/www/app
git pull
docker compose up -d --build
```

That's it. Docker rebuilds only what changed. Usually takes 1–2 minutes.

---

## Useful Commands to Know

```bash
# See all running containers
docker compose ps

# See your app's logs (live)
docker compose logs -f app

# See Redis logs
docker compose logs -f redis

# Restart everything
docker compose restart

# Stop everything
docker compose down

# Stop and delete all data (CAREFUL — only if you want a clean slate)
docker compose down -v

# Check how much RAM/CPU each container uses
docker stats
```

---

## Common Problems

**"Site can't be reached" after deploying**

- Check DNS has propagated: `ping yourdomain.com` — does it show your VPS IP?
- Check Nginx is running: `systemctl status nginx`
- Check your app is running: `docker compose ps`

**App crashes on startup**

- Read the logs: `docker compose logs app`
- 99% of the time it's a missing or wrong env variable in `.env.production`

**"Cannot connect to Redis"**

- Check `REDIS_URL=redis://redis:6379` in your `.env.production` (lowercase `redis`, not `localhost`)
- Both containers must be in the same docker-compose.yml — they must be

**Running out of disk space**

- Old Docker images accumulate. Clean them up:
  ```bash
  docker system prune -f
  ```

---

## Phase 3 — Local Supabase (When You're Ready)

When you're ready to move away from Supabase Cloud and run your own database:

Install Supabase CLI on your VPS:

```bash
npx supabase login
npx supabase start
```

The CLI downloads and starts all the Supabase services automatically (database, auth, storage, API — all of it). You don't need to configure each piece yourself.

Then update your `SUPABASE_URL` in `.env.production` to point to your local Supabase instead of the cloud URL.

**Don't do this until your app is stable and working in Phase 2.** Running your own database means you are responsible for backups. Learn to walk before running.

---

## The Big Picture (One More Time)

```
User's Browser
      │
      ▼
  Nginx (port 80/443)   ← handles HTTPS, forwards requests
      │
      ▼
  SvelteKit App          ← your code runs here (port 3000)
  (Docker container)
      │              │
      ▼              ▼
  Supabase        Redis
  (database)      (fast memory cache + BullMQ jobs)
```

Everything in one server. One `docker compose up -d --build` to update everything. Done.
