# VERWENDE DAS OFFIZIELLE NGINX-ALPINE-IMAGE ALS BASIS
FROM nginx:alpine

# INSTALLIERE DIE NÖTIGEN ABHÄNGIGKEITEN
# libmaxminddb (für GeoIP) und git/build-essentials
RUN apk add --no-cache \
    alpine-sdk \
    automake \
    autoconf \
    libtool \
    pcre-dev \
    pcre2-dev \
    zlib-dev \
    openssl-dev \
    linux-headers \
    libmaxminddb \
    libmaxminddb-dev \
    git \
    curl \
    flex \
    bison \
    g++ \
    make

# LADE DIE QUELLEN FÜR DEN NGINX-CONNECTOR
# Dies ist das "Bindeglied" zwischen NGINX und ModSecurity
WORKDIR /usr/src
RUN git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git

# LADE DIE QUELLEN FÜR MODSECURITY v3
RUN git clone --depth 1 -b v3/master https://github.com/SpiderLabs/ModSecurity.git

# --- KOMPILIERE MODSECURITY ---
WORKDIR /usr/src/ModSecurity
RUN git submodule init
RUN git submodule update
RUN ./build.sh
RUN ./configure --enable-standalone-module --disable-mlogc
RUN make && make install

# --- LADE DIE NGINX-QUELLEN (exakt die Version, die im Basis-Image ist) ---
WORKDIR /usr/src
# Finde die NGINX-Version aus dem Basis-Image und lade den Quellcode
RUN NGINX_VERSION=$(nginx -v 2>&1 | sed 's/nginx version: nginx\///') && \
    curl -L http://nginx.org/download/nginx-$NGINX_VERSION.tar.gz | tar zxf -

# --- KOMPILIERE NGINX NEU, MIT UNSEREM MODSECURITY-MODUL ---
WORKDIR /usr/src/nginx-$NGINX_VERSION
# Konfiguriere NGINX mit denselben Flags wie das Original + ModSecurity
RUN ./configure \
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/run/nginx.lock \
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
    --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
    --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
    --user=nginx \
    --group=nginx \
    --with-compat \
    --with-file-aio \
    --with-threads \
    --with-http_addition_module \
    --with-http_auth_request_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_mp4_module \
    --with-http_random_index_module \
    --with-http_realip_module \
    --with-http_secure_link_module \
    --with-http_slice_module \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_sub_module \
    --with-http_v2_module \
    --with-mail \
    --with-mail_ssl_module \
    --with-stream \
    --with-stream_realip_module \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-cc-opt='-Os -fomit-frame-pointer -g' \
    --with-ld-opt='-Wl,--as-needed,-O1,--sort-common' \
    # HIER IST DIE MAGIE: Wir fügen unser Modul hinzu
    --add-dynamic-module=/usr/src/ModSecurity-nginx

RUN make modules
# Kopiere das neue Modul an den richtigen Ort
RUN cp objs/ngx_http_modsecurity_module.so /usr/lib/nginx/modules/

# --- LADE DAS OWASP CORE RULE SET (CRS) ---
RUN git clone --depth 1 https://github.com/coreruleset/coreruleset.git /usr/share/modsecurity-crs
# Bereite die CRS-Konfigurationsdatei vor
RUN cp /usr/share/modsecurity-crs/crs-setup.conf.example /usr/share/modsecurity-crs/crs-setup.conf
# Entferne die Example-Regel 20 (Blockiert /admin)
RUN rm /usr/share/modsecurity-crs/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf.example

# --- Aufräumen ---
# Entferne Build-Abhängigkeiten und Quellcode, um das Image klein zu halten
RUN apk del alpine-sdk automake autoconf libtool pcre-dev zlib-dev linux-headers libmaxminddb-dev git curl flex bison g++ make
RUN rm -rf /usr/src/*

# NGINX muss unser Modul laden
# Wir fügen einen Befehl am Anfang der /etc/nginx/nginx.conf ein
RUN sed -i '1s/^/load_module \/usr\/lib\/nginx\/modules\/ngx_http_modsecurity_module.so;\n/' /etc/nginx/nginx.conf
