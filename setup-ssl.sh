#!/bin/bash

# Script de configuración completa para Apps Script con SSL
# Uso: ./setup-ssl.sh tu-appscript.xpert-ia.com.mx TU_SCRIPT_ID tu-email@ejemplo.com

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
    echo "Uso: ./setup-ssl.sh tu-appscript.xpert-ia.com.mx TU_SCRIPT_ID tu-email@ejemplo.com"
    echo ""
    echo "Ejemplo:"
    echo "./setup-ssl.sh miapp.xpert-ia.com.mx 1BxKtQh8vQ9vBcD2EfG3HiJ4KlM5NoPqR7sT8uV9wX0yZ email@ejemplo.com"
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
sed -i "s/TU_SCRIPT_ID/$SCRIPT_ID/g" conf.d/reverse-proxy.conf
sed -i "s/tu-appscript\.xpert-ia\.com\.mx/$DOMAIN/g" conf.d/reverse-proxy.conf
print_success "Configuración nginx actualizada"

# Paso 3: Detener nginx si está corriendo
if docker ps | grep -q $NGINX_CONTAINER; then
    print_step "Deteniendo contenedor nginx..."
    docker stop $NGINX_CONTAINER
    print_success "Contenedor detenido"
fi

# Paso 4: Solicitar certificado SSL
print_step "Solicitando certificado SSL para $DOMAIN..."
sudo certbot certonly --standalone -d $DOMAIN --email $EMAIL --agree-tos --non-interactive

if [ $? -eq 0 ]; then
    print_success "Certificado SSL obtenido correctamente"
else
    print_error "Error al obtener certificado SSL"
    print_warning "Verifica que:"
    echo "  • El dominio $DOMAIN apunte a este servidor"
    echo "  • Los puertos 80 y 443 estén disponibles"
    echo "  • No haya firewall bloqueando estos puertos"
    exit 1
fi

# Paso 5: Construir y iniciar contenedor
print_step "Construyendo y iniciando contenedor nginx..."
docker-compose down 2>/dev/null
docker-compose up --build -d

if [ $? -eq 0 ]; then
    print_success "Contenedor nginx iniciado correctamente"
else
    print_error "Error al iniciar contenedor nginx"
    exit 1
fi

# Paso 6: Configurar cron para renovación automática
if ! sudo crontab -l 2>/dev/null | grep -q "certbot renew"; then
    print_step "Configurando renovación automática..."
    (sudo crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --pre-hook \"docker stop $NGINX_CONTAINER\" --post-hook \"docker start $NGINX_CONTAINER\" --quiet") | sudo crontab -
    print_success "Renovación automática configurada (diariamente a las 3 AM)"
else
    print_warning "Renovación automática ya está configurada"
fi

# Paso 7: Verificación
print_step "Verificando configuración..."
sleep 5

# Verificar que nginx esté corriendo
if docker ps | grep -q $NGINX_CONTAINER; then
    print_success "Nginx está corriendo correctamente"
else
    print_error "Nginx no está corriendo"
    echo "Ejecuta 'docker-compose logs' para ver los errores"
    exit 1
fi

# Verificar certificado SSL
if curl -s -I https://$DOMAIN > /dev/null 2>&1; then
    print_success "SSL está funcionando correctamente"
else
    print_warning "No se pudo verificar SSL automáticamente"
fi

echo ""
echo "🎉 ¡CONFIGURACIÓN COMPLETADA!"
echo "=============================="
echo ""
echo "🌐 Tu Apps Script está disponible en: https://$DOMAIN"
echo "🔐 SSL configurado y funcionando"
echo "🔄 Renovación automática configurada"
echo ""
echo "📋 Comandos útiles:"
echo "  • Ver logs: docker-compose logs -f"
echo "  • Reiniciar: docker-compose restart"
echo "  • Detener: docker-compose down"
echo "  • Ver certificados: sudo certbot certificates"
echo ""
echo "🧪 Prueba tu configuración:"
echo "  curl -I https://$DOMAIN"
echo ""