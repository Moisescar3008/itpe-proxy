# 📁 Estructura de archivos para Apps Script con SSL

```
appscript-proxy/
├── Dockerfile
├── docker-compose.yml
├── setup-ssl.sh
└── conf.d/
    └── reverse-proxy.conf
```

## 🚀 Pasos de instalación

### 1. Crear directorio y archivos
```bash
mkdir appscript-proxy
cd appscript-proxy
```

### 2. Crear los archivos
- Copia el contenido de cada artefacto en su archivo correspondiente
- Crea la carpeta `conf.d/`

### 3. Personalizar configuración
Edita `conf.d/reverse-proxy.conf` y cambia:
- `tu-appscript.xpert-ia.com.mx` → tu dominio real
- `TU_SCRIPT_ID` → el ID de tu Google Apps Script

### 4. Hacer ejecutable el script
```bash
chmod +x setup-ssl.sh
```

### 5. Ejecutar configuración completa
```bash
./setup-ssl.sh tu-dominio.xpert-ia.com.mx TU_SCRIPT_ID tu-email@ejemplo.com
```

## 📝 Configuración manual (alternativa)

Si prefieres hacerlo paso a paso:

```bash
# 1. Detener nginx si existe
docker stop nginx_proxy 2>/dev/null

# 2. Obtener certificado
sudo certbot certonly --standalone -d tu-dominio.xpert-ia.com.mx

# 3. Construir y ejecutar
docker-compose up --build -d

# 4. Configurar cron (solo primera vez)
sudo crontab -e
# Agregar: 0 3 * * * certbot renew --pre-hook "docker stop nginx_proxy" --post-hook "docker start nginx_proxy"
```

## 🔧 Comandos útiles

```bash
# Ver logs
docker-compose logs -f

# Reiniciar
docker-compose restart

# Ver estado SSL
curl -I https://tu-dominio.com

# Ver certificados
sudo certbot certificates

# Renovar manualmente
sudo certbot renew --pre-hook "docker stop nginx_proxy" --post-hook "docker start nginx_proxy"
```

## ⚠️ Notas importantes

1. **DNS**: Asegúrate de que tu dominio apunte a tu servidor
2. **Firewall**: Puertos 80 y 443 deben estar abiertos
3. **Apps Script**: Debe estar publicado como "Web app" con acceso público
4. **Dominio**: Cambia todos los `tu-appscript.xpert-ia.com.mx` por tu dominio real
5. **Script ID**: Lo encuentras en la URL de tu Apps Script