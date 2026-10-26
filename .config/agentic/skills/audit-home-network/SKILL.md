---
name: audit-home-network
description: >
  Audit of the user's own home network, computer, IoT devices, and router, ranked into a fix list. Use for "/audit-home-network", "audit my home network", "scan my wifi", "harden my network", "is my router secure", or the periodic network recheck after a move or router change.
---

# Audit Home Network

A report first, changes second. Every scan and read is read-only. A change to the Mac, the router, or a package install happens only after the user approves that one change. The router is never changed by the agent, it gives a list for the user to apply.

## Hard rules

- Own network only. Before any active scan, confirm in chat that the network is the user's own and that scanning is approved, per `security.md`. No approval means passive discovery only, the ARP table and the Bonjour browse from step 4.
- Scan only the user's own subnet, the interface from `route -n get default`, then its address and netmask from `ifconfig <interface>`, the route output alone gives only the gateway. Host discovery and service detection only, no exploit scripts, no brute force, no credential guessing.
- Never type, store, or repeat passwords. The user logs in to the router themselves, the agent reads the pages only. Never click Apply, Save, New, Delete, or Start WPS on the router.
- Privacy: no public IP, MAC address, serial number, SSID, Wi-Fi key, or device hostname goes into a file, memory, PR, or shared message. Report devices by role and port. The report stays in chat.
- Run single-purpose commands, no compound one-liners, no `nc`, `tcpdump`, tunnels, or `sed -i`. If a command is blocked or flagged, stop and ask.
- Never use `sudo` or ask for an admin password. A check that needs root, such as `profiles list`, `nmap -sU`, or an OS setting read that fails without admin, is reported as unchecked, or the user runs it with the `! <command>` prefix and pastes the output.
- Stop on a blocker, such as a missing tool, a Cloudflare challenge, or a login wall. Name it, wait, never bypass bot detection.
- Cost: tool output is small by design, scan results are read from the output file, not re-run.

## Platform

The skill may run from macOS, Linux, or Windows. Detect the OS first (`uname -s`, or `ver` on Windows) and use the matching command for each check, the macOS commands in step 2 name the check to do, translate them: disk encryption (`fdesetup`, `lsblk` with `cryptsetup`, `manage-bde`), firewall (`socketfilterfw`, `ufw status` or `nft list ruleset`, `Get-NetFirewallProfile`), listeners (`lsof -iTCP -sTCP:LISTEN -nP`, `ss -tlnp`, `Get-NetTCPConnection -State Listen`), updates, sharing and remote login services, startup items, DNS, and saved Wi-Fi networks. Package manager is `brew`, `apt`, `dnf`, `pacman`, or `winget`. A check with no equivalent on the OS is reported as unchecked, never guessed.

## Change safety

A change can cut the network or lock the user out. These rules apply to every change, on any OS, and override the speed of the audit:

- Ask for explicit permission for each change, naming what it does, what could break, and how to undo it. One approval covers one change, never a batch and never a later run.
- Before a change, check connectivity and note the way back: the current setting value, a router configuration backup the user exports, and a second way in, a phone on mobile data, so a broken network can be fixed.
- Do changes one at a time. After each, test connectivity (`ping` the router, then a public address, then a name lookup) and stop at the first failure, undo it, and report. Never chain changes.
- Changes that can cut connectivity or access, the Wi-Fi mode or key, SSID names, DHCP, DNS, the WAN or VLAN settings, the firewall, the router admin address, remote access, and anything on the device the agent runs from, are done by the user, with the exact steps and the undo written out. Never change the connection the session itself is using.
- Making a change in a graphical settings app or the router page through computer use or the browser needs the user's permission for that one change, and only where the agent's own rules allow changes to system or security settings, otherwise the user does it. Never enter passwords, never click Apply or Save on the router.
- The router has a factory reset and an ISP-managed configuration. Never touch reset, firmware upload, WAN, or TR-069 settings.
- If connectivity drops, stop, say what was last changed, and give the undo.

## 1. Previous run

Ask the user for the previous report if they kept one, and compare at the end: new devices, new open ports, and findings that stayed open. Nothing is stored by this skill. If the user wants a record, offer a sanitized summary, finding titles and device counts by role, with no address, MAC, SSID, hostname, or serial, for them to save. With no previous report, say it is the first run.

## 2. Operating system baseline (read-only)

One command each, in parallel:

- `fdesetup status`, FileVault on.
- `/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate` and `--getstealthmode`.
- `csrutil status`, `spctl --status`.
- `defaults read /Library/Preferences/com.apple.SoftwareUpdate`, automatic install on, and `RecommendedUpdates` lagging behind the installed version.
- `launchctl print system/com.openssh.sshd`, a "could not find service" answer means Remote Login is off.
- `lsof -iTCP -sTCP:LISTEN -nP`, flag listeners bound to `*` that are not needed, AirPlay Receiver on 5000 and 7000, `rapportd`, sync tools. Localhost listeners are fine.
- `ls /Library/LaunchAgents /Library/LaunchDaemons ~/Library/LaunchAgents`, flag helpers of apps no longer installed.
- `brew outdated`, `brew services list`.
- `sharing -l`, file sharing off unless needed, and screen sharing and remote management state, read from System Settings, Sharing with the user if no command shows it.
- `networksetup -listallhardwareports` gives the Wi-Fi service name and device, use them below, never assume `Wi-Fi` or `en0`.
- `scutil --dns` and `networksetup -getdnsservers <service>`, which resolver is used, and whether a VPN, `tailscale`, or encrypted DNS profile overrides the router's.
- `networksetup -getairportnetwork <device>` and the saved Wi-Fi list from `networksetup -listpreferredwirelessnetworks <device>`, flag open networks and old networks from places the user no longer visits. Never print Wi-Fi keys.
- `profiles list` needs root, so it is the user's to run, flag unknown configuration profiles. `tmutil destinationinfo`, backup exists and is encrypted.
- Ask before reading anything under `~/.ssh`, `~/.aws`, `~/.kube`.

## 3. External exposure

1. Get the public address with `curl -s https://api.ipify.org`. Keep it in the session only.
2. In Chrome, open Shodan and Censys host pages for it. Censys moved to `platform.censys.io/hosts/<address>`, the legacy host never finishes redirecting. Read the page text, close the tab.
3. Record every service they list and every CVE. No record on Shodan is good, not proof.
4. An open port with no port forward on the router is usually the ISP's TR-069 management port. Check that it is the router's WAN connection name before calling it ISP-managed.

## 4. LAN discovery

1. `which nmap`. If missing, ask before `brew install nmap`.
2. `nmap -sn <subnet>`, hosts that answer. Phones and sleeping devices often do not, compare with the ARP table and the router's client list.
3. `nmap -sV --top-ports 1000 <live hosts>` in the background, it takes several minutes on filtered hosts, read the output file when the task completes.
4. Classify every host as primary (laptop, phone, tablet), IoT (TV, speaker, camera, plug, printer, hub), or unknown. Flag telnet, SSH, SMB, RTSP on 554, UPnP, admin web pages on non-router hosts, and anything that returns a login page with a default-credential history.
5. A hostile pattern is only a finding when a concrete device shows it.
6. Add UDP and discovery checks on the live hosts. `nmap -sU --top-ports 20 --max-retries 1` covers SNMP 161, SSDP 1900, mDNS 5353, and TFTP 69, it needs root and is slow, so it is the user's to run. `dns-sd -B _services._dns-sd._udp` lists what devices advertise but never exits on its own, run it in the background, stop it after about 5 seconds, and read its output.
7. IPv6: `ifconfig <interface>` for a global IPv6 address. A device with a public IPv6 address and no router firewall is reachable from the internet even when IPv4 is closed, run the Shodan and Censys check for the IPv6 prefix too, and read the router's IPv6 firewall page in step 5.
8. Rogue and unknown devices: compare the client list from the router, the ARP table and the scan. A device the user cannot name is a finding, unknown until identified by role, vendor lookup of the MAC prefix only, never the full MAC.
9. Never test or guess default credentials. Report that a login page exists and that the user should check the device's manual and change defaults.

## 5. Router audit (read-only, through Chrome)

The user logs in themselves in the tab group the agent opened. A tab outside the group cannot be read, and a session in another tab group is not shared, so ask the user to log in to the page the agent opened. Do not close the last tab of the group before the router work is finished, the group disappears with it.

Pages may sit in frames and return no page text, use screenshots, with the zoom action for small text. Read, in order:

- Device information: model, software version, who controls firmware. An ISP-pushed firmware cannot be updated by the user.
- WAN: connection names, TR-069 is the ISP's channel.
- Wi-Fi per band: authentication mode (WPA3 or WPA2 AES, never WEP, WPA-TKIP, or open), SSIDs, broadcast, WPS enabled, connected device count, guest or multi-SSID support, channel.
- Forward rules: DMZ, IPv4 and IPv6 port mappings, port triggers. Any entry is a finding unless the user can name it.
- UPnP: enabled, and the mappings it created, with the internal host and port. Mappings from sync tools and VPN clients are unneeded exposure.
- Application: FTP server, media sharing, USB sharing, DDNS.
- System management: remote management, web access from WAN, default or ISP-known admin credentials, Telnet or SSH to the router, firewall level, DNS settings, DNS rebinding protection, DHCP range and reservations, and whether the admin interface answers on Wi-Fi.
- LAN: DHCP, which devices hold reservations, and IPv6 firewall and prefix delegation.
- Security: firewall level, MAC or URL filters, DoS protection, ALG toggles such as SIP, and ping from WAN.
- Wi-Fi extras: PMF (802.11w), WPA3 or transition mode, hidden SSID is not a control, key rotation interval, and a weak or default-looking key, ask the user, never read the key out.
- Logs: router logs for repeated failed logins, unknown devices, or reboots.
- Maintenance: remote diagnostics, automatic reboot, backup of the router configuration, and the ISP's management contact.

Huawei ISP routers keep these under Advanced, with System Information for status. Other vendors differ, read the menu, do not guess.

## 6. IoT isolation plan

Only when the router has a guest or multi-SSID option with client isolation.

- Move list: which devices go on the IoT or guest SSID, which stay on the main network. Primary devices stay on the main network.
- Breakage notes: casting and AirPlay from the main network to an isolated TV, printers, HomeKit and Matter hubs, and local control apps. Give the workaround for each, a mDNS reflector, a second SSID with a bridge, or leaving that device on the main network.
- A router with no guest or isolation option is a finding, the plan is blocked until it is replaced.
- Per IoT device checklist, ask the user, never test: firmware update source and last update, default admin password changed, cloud account with a unique password and two-factor, unneeded features off (UPnP, remote access, telnet, microphone, camera sharing), and vendor still shipping updates. A camera or hub with no updates goes on the isolated network or is retired.
- Cameras and baby monitors get the strictest list: no internet inbound, local recording where possible, and a separate account from the user's main email.
- Smart TVs and streamers: turn off automatic content recognition and ad tracking in settings, they phone home constantly.
- Voice assistants and hubs stay on the main network only when casting or local control requires it, and the reason goes in the report.
- Printers: disable WPS and remote print by email, update firmware, restrict the web admin page.
- Work devices from an employer stay on the main or a dedicated network, never mixed with IoT, and the report states that the employer's own management is out of scope.

## 7. Account and habit checks (ask, never access)

Short questions, one answer each, the agent opens no account:

- Router admin password is unique, not the label on the device, and not reused anywhere.
- Wi-Fi key is a long passphrase, changed since it was shared with guests or contractors.
- Password manager in use, two-factor on the email, Apple ID, and ISP account.
- ISP account email and phone are the user's own, recovery contacts are current.
- Backups: Time Machine or another encrypted backup, restore tested in the last year.
- VPN or `tailscale` needed for remote access, never a router port forward.
- Router configuration backed up after a change.

## 8. Report

Plain words, no emoji, no bold, no decorative dividers. Severity as serious, minor, or nitpick. Include:

- Good: what already holds.
- Serious, minor, nitpick: finding, evidence, smallest fix, who applies it (agent after approval, or user on the router).
- Compared with the last run: new, closed, and still open.
- FLAGGED block for anything adjacent, unchecked, or ISP-controlled.

## 9. Fix

The audit does not stop at the report. Every finding gets a concrete fix, then the fixes are made as far as the rules allow, then verified.

1. Pair each finding with its smallest fix, the exact command or the exact router page and field, and who applies it.
2. Ask once which fixes to make, as a numbered list, serious first. One approval covers only the items the user names.
3. The agent applies what it may, each after approval: package upgrades (`brew upgrade <name>`), stopping or removing an unneeded `brew services` entry, unloading a launch agent of an app no longer installed and moving its file to a backup folder, never deleting it, and app-level settings such as `syncthing` NAT traversal and global discovery.
4. Changes to operating system security or system settings (firewall, sharing, remote login, receivers, DNS, profiles, update policy) and every router setting follow Change safety, and are never made at all where the agent's own rules forbid them, even when asked. Give the exact command or the click path and ask the user to run it, for a command suggest the `! <command>` prefix so it runs in the session. The router change list is ordered, serious first, with the page, the field, and the target value.
5. Never ask for or enter a password, and never click Apply or Save on the router.
6. After each fix, re-run the matching check from its step and show the output. A router fix is verified by re-reading the same page once the user says it is done, then repeat the exposure check and LAN scan after any router change.
7. A finding the user declines, or that only the ISP can change, stays in the report as open with the reason.

## 10. Router replacement criteria

Recommend replacing the router only when one holds, and say which one:

- No automatic firmware updates, or firmware is end of life.
- No guest network or client isolation, with IoT devices present.
- No WPA3.
- ISP lock on settings the user needs, such as UPnP, port forwarding, or remote management.

Before recommending any replacement, check that the ISP allows it, some providers do not:

- Find the connection type from the router pages, GPON or fibre ONT, DSL, cable, or Ethernet handoff, and whether the router is a combined ONT and router, as with an `HG8145V5` style unit.
- Search the ISP's own support pages and terms for third-party or own-router support, bridge or modem mode, and whether login details such as PPPoE, VLAN ID, or TR-069 are given to customers. Cite the page, never guess.
- A combined ONT and router usually cannot be replaced, only put in bridge mode or placed behind the new router in double NAT. A new router then plugs into its Ethernet port, with the ISP unit kept.
- Check that voice, TV, and IPTV services depend on the ISP unit, they may break behind a new router.
- If the ISP forbids it, locks the VLAN or login, or support is unclear, say so, keep the ISP unit, and recommend the second router behind it, or ask the ISP, with the question to ask written out. Never advise a step that breaks the ISP's support or contract without saying so.
- The decision is the user's, with the ISP's answer cited in the report.

Name current options neutrally, such as Eero, Ubiquiti, or a router running a maintained open firmware, with the reason. Re-run this skill after the change, expect the TR-069 finding to disappear when the ISP router goes into bridge mode.

## 11. Close out

- Close every tab the audit opened.
- Remind the user to log out of the router admin page.
- Remove the temporary scan output files from the scratchpad if they hold addresses.
