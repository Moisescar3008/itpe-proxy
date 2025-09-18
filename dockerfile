FROM nginx:alpine

# Copiar configuración
COPY conf.d/ /etc/nginx/conf.d/

# Crear directorio para certificados SSL
RUN mkdir -p /etc/letsencrypt

# Exponer puertos
EXPOSE 80 443

# Comando por defecto
CMD ["nginx", "-g", "daemon off;"]