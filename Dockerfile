# Production image for the SvelteKit app (docs/production-readiness-plan.md P9B).
# Built once in CI and deployed by digest; the server never builds. It holds no secrets: server secrets arrive as
# runtime environment variables, and the only values baked in are the browser-safe PUBLIC_* ones passed as build args.

FROM node:22-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
ARG PUBLIC_SUPABASE_URL
ARG PUBLIC_SUPABASE_PUBLISHABLE_KEY
ARG PUBLIC_MAPBOX_TOKEN=
ENV PUBLIC_SUPABASE_URL=$PUBLIC_SUPABASE_URL \
    PUBLIC_SUPABASE_PUBLISHABLE_KEY=$PUBLIC_SUPABASE_PUBLISHABLE_KEY \
    PUBLIC_MAPBOX_TOKEN=$PUBLIC_MAPBOX_TOKEN
RUN npm run build
RUN npm prune --omit=dev

FROM node:22-bookworm-slim AS runtime
ENV NODE_ENV=production PORT=3000 HOST=0.0.0.0
WORKDIR /app
COPY --from=build --chown=node:node /app/build ./build
COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/package.json ./package.json
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+process.env.PORT+'/api/health').then(r=>process.exit(r.ok?0:1),()=>process.exit(1))"
CMD ["node", "build"]
