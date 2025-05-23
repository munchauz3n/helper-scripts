# Helper scripts

## `arch-linux-installer.sh`
As the name suggests this is a Bash script for easier installation of Arch Linux.
It supports console and graphical environments, multiple display managers, etc. and will guide the user through the installation process via dialog boxes (whiptail).

This script is meant to be executed from live environment:
```bash
curl -o arch-linux-installer.sh https://raw.githubusercontent.com/munchauz3n/helper-scripts/refs/heads/main/arch-linux-installer.sh
chmod +x ./arch-linux-installer.sh && sudo ./arch-linux-installer.sh
```

### Dual boot Arch with Windows 10/11
To dual-boot with Windows on same disk, Arch should follow the same firmware boot mode and partitioning combination used by the Windows installation.  
The **Arch** installation script creates an installation in **UEFI/GPT** so the **Windows** installation **must use the same**.

#### UEFI Secure Boot
Arch Linux install media does not support **Secure Boot** yet so it **must be disabled** from BIOS before installation.

#### Windows before Arch
This is the recommended way to set up a Linux/Windows dual booting system. The Windows installation will create the EFI system partition which can be used by your Linux boot loader.  
When installing Windows from scratch, do note that the EFI System partition created by Windows Setup will be too small for most use cases.

- Select your installation target and make sure it has no partitions.
- Click New and then the Apply buttons. The Windows installer will then generate the expected partitions (allocating nearly everything to its primary partition) and just 100MB to the EFI.
- Use the UI to delete the `System`, `MSR`, and `Primary` partitions. Leave the Recovery partition (if present) alone.
- Press `Shift+F10` to open the Command Prompt.
- Type `diskpart.exe` and press `Enter` to open the disk partitioning tool.
- Type `list disk` and press `Enter` to list your disks. Find the one you intend to modify and note its disk number.
- Type `select disk <disk-number>` with the disk number to modify.
- Type `create partition efi size=size` with the desired size of the ESP in Mebibytes (MiB), and press Enter. See the note at EFI system partition#Create the partition for the recommended sizes.
- Type `format quick fs=fat32 label=System` and press `Enter` to format the ESP
- Type `exit` and press `Enter` to exit the disk partitioning tool and then type `exit` followed by `Enter` again.

Once Windows is installed, you can resize the primary partition down within Windows and then reboot and use the helper script to install Arch by choosing the Windows EFI partition when asked to "Pick EFI partition".

#### Arch before Windows
Even though the recommended way to set up a Linux/Windows dual booting system is to first install Windows, it can be done the other way around.
Have some unpartitioned disk space, or create and resize partitions for Windows from within the Linux installation, before launching the Windows installation. Windows will use the already existing EFI system partition.

- **Launch windows installation.**
- **Watch to let it use only the intended partition, but otherwise let it do its work as if there is no Linux installation.**
- **After Windows installation is done fix the ability to load Linux at start up.**  
  In a Windows command-line shell with administrator privileges:
  ```cmd
  bcdedit /set "{bootmgr}" path "\EFI\GRUB\grubx64.efi
  ```

#### Fast startup and hibernation
> [!CAUTION]
> Data loss can occur if Windows hibernates and you dual boot into Arch and make changes to files on a filesystem (such as NTFS) that can be read and written to by Windows and Linux, and that has been mounted by Windows.
>
> Vice-versa is also true so the **safest option is to disable both** fast startup and hibernation.

- **Disable Fast Startup and disable hibernation**:  
  In a Windows command-line shell with administrator privileges:
  ```cmd
  powercfg /H off
  ```
  Make sure to disable the setting and then shut down Windows, before installing Linux. Rebooting is not sufficient.
- **Disable Fast Startup and enable hibernation**:  
  - Windows and Linux must use separate EFI system partitions (ESP). **There can only be one ESP per drive**, the ESP used for Linux must be located on a separate drive than the ESP used for Windows.
    In this case Windows and Linux can still be installed on the same drive in different partitions, if you place the ESP used by Linux on another drive than the Linux root partition.
  - A filesystem mounted by Windows while Windows is hibernated **can not read-write mount** any filesystem in Linux.
- **Enable Fast Startup and enable hibernation**:  
  The same considerations apply as in case above but since Windows can not be shut down fully, only hibernated, you can never read-write mount any filesystem that was mounted by Windows while Windows is hibernated.

#### Time standard
It is recommended to configure Windows to use UTC, rather than Linux to use localtime. (Windows by default uses localtime).  
In a Windows command-line shell with administrator privileges:  
```cmd
reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /d 1 /t REG_DWORD /f
```

#### How to re-create the GRUB boot entry
In case BIOS update resets the EFI bootloader the GRUB boot entry needs to be re-created.

- From Windows command-line shell with administrator privileges:  
  ```cmd
  bcdedit /set "{bootmgr}" path "\EFI\GRUB\grubx64.efi"
  ```
- From Linux live environment:  
  ```bash
  efibootmgr --create --disk /dev/nvme0n1 --part 4 --label 'Arch' --loader '\EFI\GRUB\grubx64.efi'
  ```

#### Links
[Dual boot Arch with Windows](https://wiki.archlinux.org/title/Dual_boot_with_Windows)

## `bluetooth-dualboot-sync-keys.sh`
When dual-booting Windows and Linux, bluetooth devices may have to be re-paired at each OS switch. This is due to both OSes having different sets of Bluetooth pairing keys. Things are further complicated as some devices generate new MAC address each time they are paired.

This script helps transfer pairing keys from from one OS to the other by guiding the user through the synchronization process via dialog boxes (whiptail), keeping devices paired across both systems.

The synchronization can be done in both direction (`Linux To Windows` and `Windows To Linux`) depending on which OS the device was last paired (**user configures this setting**).
- At `Windows To Linux` keys and additional information are extracted from the Windows bluetooth registry and imported to the Bluetooth configuration directory of the device on Linux.
- At `Linux To Windows` keys and additional information are extracted from Bluetooth configuration directory of the device on Linux and imported into the Windows Bluetooth keys registry

> [!CAUTION]
> Even though synchronization can be done in both directions it is **recommended** to first pair the devices on Linux, then on Windows and after that run the script to transfer the keys from Windows To Linux.
>
> After pairing devices on Windows and switching back to Linux do not turn on the devices until their keys are synchronized. Some devices will try reset themselves.

```bash
curl -o bluetooth-dualboot-sync-keys.sh https://raw.githubusercontent.com/munchauz3n/helper-scripts/refs/heads/main/bluetooth-dualboot-sync-keys.sh
chmod +x ./bluetooth-dualboot-sync-keys.sh && sudo ./bluetooth-dualboot-sync-keys.sh
```

#### Links
[Bluetooth DualBoot Pairing](https://wiki.archlinux.org/title/Bluetooth#Dual_boot_pairing)

## `bluetooth-suspend-rules.sh`
Small bash script for enabling or disabling bluetooth controler autosuspend and peripherials wakeup from suspend udev rules.

On most motherboards the bluetooth controller is a USB device. The default timeout before a USB device goes to idle is 2000 ms.
Once bluetooth goes to idle it is not easy to wake it up as the connected bluetooth peripherials will not work. So it's better to disable autosuspend for the Bluetooth USB device to avoid unnecessary frustrations.

To allow bluetooth peripherials (keyboards, mice, etc.) to wakeup the system from suspend also make sure that wake from USB is not disabled in BIOS.

```bash
curl -o bluetooth-suspend-rules.sh https://raw.githubusercontent.com/munchauz3n/helper-scripts/refs/heads/main/bluetooth-suspend-rules.sh
chmod +x ./bluetooth-suspend-rules.sh && sudo ./bluetooth-suspend-rules.sh
```
