#!/bin/bash

# Script de configuración completa para Apps Script con SSL
# Preconfigurado para: autom.itpe.mx
# Uso: ./setup-ssl.sh

DOMAIN=autom.itpe.mx
SCRIPT_ID=AKfycby_O2-_j5OjfAvUeHfzOonGGqNTeXy0ilpgB68CjUw5c2fnk8cgHi7b7zVxWYdy0dkO
EMAIL=moises.carrillo@itpe.mx
NGINX_CONTAINER="nginx_proxy"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${BLUE}🔧 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

if [ -z "$DOMAIN" ] || [ -z "$SCRIPT_ID" ] || [ -z "$EMAIL" ]; then
    print_error "Faltan parámetros"
    echo "Uso: ./setup-ssl.sh"
    echo ""
    echo "El script está preconfigurado con:"
    echo "  • Dominio: autom.itpe.mx"
    echo "  • Script ID: AKfycby_O2-_j5OjfAvUeHfzOonGGqNTeXy0ilpgB68CjUw5c2fnk8cgHi7b7zVxWYdy0dkO"
    echo "  • Email: moises.carrillo@itpe.mx"
    echo ""
    echo "Para usar otros valores, edita las variables al inicio del script."
    exit 1
fi

echo ""
echo "🚀 CONFIGURACIÓN APPS SCRIPT CON SSL"
echo "====================================="
echo "Dominio: $DOMAIN"
echo "Script ID: $SCRIPT_ID"
echo "Email: $EMAIL"
echo ""

# Verificar si Docker está corriendo
if ! docker info > /dev/null 2>&1; then
    print_error "Docker no está corriendo. Inicia Docker primero."
    exit 1
fi

# Paso 1: Crear estructura de directorios
print_step "Creando estructura de directorios..."
mkdir -p conf.d
print_success "Directorios creados"

# Paso 2: Crear/actualizar configuración nginx
print_step "Actualizando configuración nginx..."
sed -i "s/TU_SCRIPT_ID/AKfycby_O2-_j5OjfAvUeHfzOonGGqNTeXy0ilpgB68CjUw5c2fnk8cgHi7b7zVxWYdy0dkO/g" conf.d/reverse-proxy.conf
sed -i "s/tu-appscript\.com\.mx/$DOMAIN/g" conf.d/reverse-proxy.conf
print_success "Configuración nginx actualizada"

# Paso 3: IMPORTANTE - Detener cualquier servicio que use puerto 80/443
print_step "Deteniendo servicios que puedan interferir..."
# Detener nginx si está corriendo
if docker ps | grep -q $NGINX_CONTAINER; then
    print_warning "Deteniendo contenedor nginx existente..."
    docker stop $NGINX_CONTAINER
    docker rm $NGINX_CONTAINER 2>/dev/null || true
fi

# Detener docker-compose si está corriendo
docker-compose down 2>/dev/null || true

# Verificar que los puertos estén libres
if netstat -tuln | grep -q ":80 "; then
    print_warning "Puerto 80 ocupado. Intentando liberar..."
    sudo fuser -k 80/tcp 2>/dev/null || true
fi

if netstat -tuln | grep -q ":443 "; then
    print_warning "Puerto 443 ocupado. Intentando liberar..."
    sudo fuser -k 443/tcp 2>/dev/null || true
fi

print_success "Puertos liberados"

# Paso 4: PRIMERO - Solicitar certificado SSL (certbot necesita puerto 80 libre)
print_step "Solicitando certificado SSL para $DOMAIN..."
print_warning "Certbot necesita el puerto 80 libre para validar el dominio"

# Verificar que el dominio apunte al servidor
print_step "Verificando que $DOMAIN apunte a este servidor..."
SERVER_IP=$(curl -s ifconfig.me)
DOMAIN_IP=$(dig +short $DOMAIN | tail -n1)

if [ "$SERVER_IP" != "$DOMAIN_IP" ]; then
    print_warning "El dominio $DOMAIN ($DOMAIN_IP) no apunta a este servidor ($SERVER_IP)"
    echo "¿Deseas continuar de todas formas? (y/N)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        print_error "Configuración cancelada"
        exit 1
    fi
fi

# Solicitar certificado con certbot standalone
sudo certbot certonly \
    --standalone \
    --preferred-challenges http \
    -d $DOMAIN \
    --email $EMAIL \
    --agree-tos \
    --non-interactive \
    --force-renewal

if [ $? -eq 0 ]; then
    print_success "Certificado SSL obtenido correctamente"
    
    # Verificar que los archivos de certificado existen
    if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/$DOMAIN/privkey.pem" ]; then
        print_success "Archivos de certificado verificados"
        ls -la /etc/letsencrypt/live/$DOMAIN/
    else
        print_error "Archivos de certificado no encontrados"
        exit 1
    fi
else
    print_error "Error al obtener certificado SSL"
    print_warning "Verifica que:"
    echo "  • El dominio $DOMAIN apunte a este servidor ($SERVER_IP)"
    echo "  • Los puertos 80 y 443 estén disponibles"
    echo "  • No haya firewall bloqueando estos puertos"
    echo "  • El DNS haya propagado (puede tardar hasta 48 horas)"
    echo ""
    echo "Comandos de diagnóstico:"
    echo "  dig $DOMAIN"
    echo "  nslookup $DOMAIN"
    echo "  curl -I http://$DOMAIN"
    exit 1
fi

# Paso 5: DESPUÉS - Construir y iniciar el proxy reverso
print_step "Construyendo y iniciando contenedor nginx con SSL..."

# Dar un momento para que certbot libere completamente los puertos
sleep 3

# Iniciar docker-compose
docker-compose up --build -d

if [ $? -eq 0 ]; then
    print_success "Contenedor nginx iniciado correctamente"
else
    print_error "Error al iniciar contenedor nginx"
    echo "Revisando logs..."
    docker-compose logs
    exit 1
fi

# Paso 6: Configurar cron para renovación automática
if ! sudo crontab -l 2>/dev/null | grep -q "certbot renew"; then
    print_step "Configurando renovación automática..."
    # Script de renovación que detiene nginx temporalmente
    RENEWAL_SCRIPT="#!/bin/bash
# Detener nginx temporalmente
docker-compose down
# Renovar certificados
certbot renew --standalone --quiet
# Reiniciar nginx
docker-compose up -d
"
    echo "$RENEWAL_SCRIPT" | sudo tee /usr/local/bin/renew-certs.sh > /dev/null
    sudo chmod +x /usr/local/bin/renew-certs.sh
    
    # Agregar cron job
    (sudo crontab -l 2>/dev/null; echo "0 3 * * 0 /usr/local/bin/renew-certs.sh") | sudo crontab -
    print_success "Renovación automática configurada (semanalmente los domingos a las 3 AM)"
else
    print_warning "Renovación automática ya está configurada"
fi

# Paso 7: Verificación completa
print_step "Verificando configuración..."
sleep 10

# Verificar que nginx esté corriendo
if docker ps | grep -q $NGINX_CONTAINER; then
    print_success "Nginx está corriendo correctamente"
else
    print_error "Nginx no está corriendo"
    echo "Logs del contenedor:"
    docker-compose logs
    exit 1
fi

# Verificar respuesta HTTP
print_step "Verificando respuesta HTTP..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://$DOMAIN)
if [ "$HTTP_STATUS" = "301" ] || [ "$HTTP_STATUS" = "302" ]; then
    print_success "Redirección HTTP a HTTPS funcionando (HTTP $HTTP_STATUS)"
else
    print_warning "Respuesta HTTP inesperada: $HTTP_STATUS"
fi

# Verificar certificado SSL
print_step "Verificando certificado SSL..."
if curl -s -I https://$DOMAIN > /dev/null 2>&1; then
    print_success "SSL está funcionando correctamente"
    
    # Mostrar información del certificado
    SSL_EXPIRY=$(echo | openssl s_client -servername $DOMAIN -connect $DOMAIN:443 2>/dev/null | openssl x509 -noout -dates | grep notAfter | cut -d= -f2)
    print_success "Certificado expira: $SSL_EXPIRY"
else
    print_warning "No se pudo verificar SSL automáticamente"
    echo "Prueba manualmente: curl -I https://$DOMAIN"
fi

# Verificar que el Apps Script responda
print_step "Verificando conectividad con Apps Script..."
APPS_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" https://$DOMAIN)
if [ "$APPS_RESPONSE" = "200" ] || [ "$APPS_RESPONSE" = "302" ]; then
    print_success "Apps Script respondiendo correctamente (HTTP $APPS_RESPONSE)"
else
    print_warning "Apps Script respuesta: HTTP $APPS_RESPONSE"
    echo "Esto puede ser normal si el script requiere parámetros específicos"
fi

echo ""
echo "🎉 ¡CONFIGURACIÓN COMPLETADA!"
echo "=============================="
echo ""
echo "🌐 Tu Apps Script está disponible en: https://$DOMAIN"
echo "🔒 SSL configurado y funcionando"
echo "🔄 Renovación automática configurada"
echo "📅 Próxima verificación de renovación: Domingo 3:00 AM"
echo ""
echo "📋 Comandos útiles:"
echo "  • Ver logs: docker-compose logs -f"
echo "  • Reiniciar: docker-compose restart"
echo "  • Detener: docker-compose down"
echo "  • Ver certificados: sudo certbot certificates"
echo "  • Renovar manualmente: sudo /usr/local/bin/renew-certs.sh"
echo ""
echo "🧪 Prueba tu configuración:"
echo "  curl -I https://$DOMAIN"
echo "  curl -I http://$DOMAIN  # Debe redirigir a HTTPS"
echo ""
echo "🔍 Diagnóstico SSL:"
echo "  openssl s_client -servername $DOMAIN -connect $DOMAIN:443"
echo ""