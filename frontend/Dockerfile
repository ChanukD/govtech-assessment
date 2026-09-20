# Build the bundle, then serve it from nginx. The runtime image contains no Node and
# no source - only static files and a web server.

FROM node:22-alpine AS build

WORKDIR /srv/app

# Copied before the source so the dependency layer is reused whenever only
# application code changes. `npm ci` installs exactly the lockfile, not a fresh solve.
COPY package.json package-lock.json ./
RUN npm ci

COPY tsconfig*.json vite.config.ts index.html ./
COPY src ./src

RUN npm run build

FROM nginx:1.27-alpine AS runtime

# nginx's default config serves a welcome page and knows nothing about SPA routing or
# the API; this replaces it entirely.
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /srv/app/dist /usr/share/nginx/html

EXPOSE 80
