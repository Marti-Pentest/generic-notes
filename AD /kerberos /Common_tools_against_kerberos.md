## Herramientas con NTLM deshabilitado

Cuando una máquina tiene la autenticación NTLM deshabilitada, es necesario autenticarse via Kerberos. El paso común en todos los casos es **sincronizar el reloj** con el servidor Kerberos antes de cualquier operación:

```shell
sudo rdate -n <ip_servidor_kerberos>
```

> 💡 Kerberos rechaza tickets con una diferencia horaria superior a 5 minutos — la sincronización del reloj es obligatoria, no opcional.

---

## Netexec

Usar el nombre de máquina en formato `MAQUINA.dominio` en lugar de la IP, y añadir el flag `-k`:

```shell
nxc smb <maquina>.<dominio> -u '<usuario>' -p '<contraseña>' -k
```

---

## Evil-WinRM

### 1. Sincronizar el reloj

```shell
sudo rdate -n <ip_servidor_kerberos>
```

### 2. Configurar `/etc/krb5.conf`

```ini
[libdefaults]
        default_realm = <DOMINIO>

[realms]
        <DOMINIO> = {
                kdc = <maquina>.<dominio>
                kdc = <ip>
                default_domain = <dominio>
        }
```

### 3. Obtener un ticket TGT

```shell
getTGT.py <dominio>/<usuario>:<contraseña> -dc-ip <ip>
```

### 4. Exportar el ticket al entorno

```shell
export KRB5CCNAME=<archivo_ticket>
```

### 5. Conectar

```shell
evil-winrm -i <maquina>.<dominio> -r <dominio>

# Ejemplo
evil-winrm -i DC01.megacorp.htb -r megacorp.htb
```

---

## Herramientas de Impacket

Las herramientas de la suite Impacket (`psexec`, `wmiexec`, `smbclient`, `mssqlclient`, etc.) comparten el mismo formato de autenticación:

```shell
# Con contraseña
<herramienta> <dominio>/<usuario>:'<contraseña>'@<ip>

# Con hash (Pass-the-Hash)
<herramienta> <dominio>/<usuario>:@<ip> -hashes '<hash_LM_opcional>:<hash_NT>'
```

> 💡 En ZSH es **obligatorio** usar comillas simples `'` para contraseñas que contengan caracteres especiales — sin ellas el shell interpreta los símbolos antes de pasarlos al comando.

### Con autenticación Kerberos (NTLM deshabilitado)

Impacket gestiona los tickets automáticamente. Solo requiere sincronización de reloj, el flag `-k` y usar el nombre de máquina en lugar de la IP:

```shell
# Sincronizar reloj
sudo rdate -n <ip_servidor_kerberos>

# Con contraseña
<herramienta> <dominio>/<usuario>:'<contraseña>'@<maquina>.<dominio> -k

# Con hash
<herramienta> <dominio>/<usuario>:@<maquina>.<dominio> -hashes '<hash_LM>:<hash_NT>' -k
```

Ejemplos reales:

```shell
# Kali (prefijo impacket-)
impacket-wmiexec megacorp.com/john.smith:'Superpass123!'@DC01.megacorp.com -k

# Ubuntu / Linux estándar
wmiexec.py megacorp.com/john.smith:'Superpass123!'@DC01.megacorp.com -k
```
