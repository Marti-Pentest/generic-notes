## BloodHound — Recolección de Datos

BloodHound necesita datos del dominio para construir el grafo de ataque. Existen varias formas de recolectarlos según el acceso disponible.

---

### Desde dentro de la máquina (recomendado)

Subir y ejecutar `SharpHound.exe` directamente en la máquina comprometida. Descargar el archivo `.zip` generado e importarlo en BloodHound.

> 💡 SharpHound tiene mayor visibilidad del dominio cuando se ejecuta desde dentro — es el método preferido siempre que sea posible.

---

### Desde fuera de la máquina

Si no hay acceso a la máquina o se quiere recolectar datos desde un usuario externo:

```shell
# BloodHound Community Edition
bloodhound-ce-python -c All -ns <ip> -d <dominio> --zip -u <usuario> -p <contraseña>

# BloodHound edición legacy
bloodhound-python -c All -ns <ip> -d <dominio> --zip -u <usuario> -p <contraseña>

# Via Netexec
nxc ldap <ip> -u <usuario> -p <contraseña> --bloodhound --collection All -d <dominio> --dns-server <ip_dc>
```

---

### Alternativa — RustHound

Herramienta alternativa escrita en Rust, compatible con BloodHound CE:
https://github.com/g0h4n/RustHound-CE

---

### Criterio de elección

| Situación | Método recomendado |
| --------- | ------------------ |
| Acceso a una máquina del dominio | SharpHound.exe desde dentro |
| Sin acceso a máquina del dominio | bloodhound-ce-python o netexec |
| Múltiples usuarios disponibles | Usar el que tenga mayor visibilidad del dominio |

> 💡 Si se tienen varios usuarios disponibles, priorizar el que tenga más permisos o visibilidad sobre los recursos del dominio — la calidad del grafo de BloodHound depende directamente de los permisos del usuario con el que se recolecta.
