# KalyNow Web — React + Vite (nginx)
#
# Serves the compiled SPA via nginx on port 80.
# Traefik routes kalynow.mg (root) → this service.
#
# Build image:  docker build -t kalynow/web:local ./kalyNow-web
# Deploy (local): nomad job run -var-file=environments/local/nomad.vars jobs/web.nomad.hcl
# Deploy (prod):  nomad job run -var-file=environments/prod/nomad.vars  jobs/web.nomad.hcl

variable "datacenter" {
  type    = string
  default = "dc1"
}

variable "web_count" {
  type    = number
  default = 1
}

variable "web_image" {
  type    = string
  default = "kalynow/web:local"
}

variable "web_cpu" {
  type    = number
  default = 100
}

variable "web_memory" {
  type    = number
  default = 64
}

variable "domain" {
  type    = string
  default = "kalynow.mg"
}

variable "force_pull" {
  type    = bool
  default = false
}

job "web" {
  datacenters = [var.datacenter]
  type        = "service"

  group "web" {
    count = var.web_count

    network {
      port "http" {}
    }

    task "web" {
      driver = "docker"

      # nginx listens on port 80 by default; rewrite it to the dynamic Nomad port
      template {
        destination = "local/nginx-port.conf"
        change_mode = "restart"
        data        = <<EOF
# Override listen port to the Nomad-allocated dynamic port
server {
    listen {{ env "NOMAD_PORT_http" }};
    server_name _;

    root /usr/share/nginx/html;
    index index.html;

    gzip on;
    gzip_types text/plain text/css application/json application/javascript
               text/xml application/xml application/xml+rss text/javascript
               image/svg+xml;
    gzip_min_length 1024;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff2?|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /health {
        access_log off;
        return 200 "ok\n";
        add_header Content-Type text/plain;
    }
}
EOF
      }

      # Mount the rendered nginx config into the container
      config {
        image        = var.web_image
        ports        = ["http"]
        network_mode = "host"
        force_pull   = var.force_pull

        volumes = [
          "local/nginx-port.conf:/etc/nginx/conf.d/default.conf",
        ]
      }

      resources {
        cpu    = var.web_cpu
        memory = var.web_memory
      }

      service {
        name = "web"
        port = "http"

        tags = [
          "traefik.enable=true",

          # Default catch-all: Host(domain) on HTTP — lowest priority so
          # all /api/* routers (higher priority) take precedence.
          "traefik.http.routers.web.rule=Host(`${var.domain}`)",
          "traefik.http.routers.web.entrypoints=web,websecure",
          "traefik.http.routers.web.priority=1",
        ]

        check {
          type     = "http"
          path     = "/health"
          port     = "http"
          interval = "10s"
          timeout  = "3s"
        }
      }
    }
  }
}
