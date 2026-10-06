# Security Lab Native auto update

Development branch: `feature/native-auto-update`, created from latest
`godot-port` at `d9c573d`. Neither main nor godot-port is a development target.

The design was reviewed against [codingcircle UpdateManager](https://github.com/gamparda/codingcircle/blob/main/scripts/UpdateManager.gd), its Windows security tests and Inno installer. This is a separate single-player implementation: no Cat War multiplayer gate, ports, dedicated server or Android updater.

## Channels and files

| Channel | Default automatic check/download | Manifest release tag | Version |
|---|---|---|---|
| stable | ON | native-channel-stable | 0.7.1 |
| beta | OFF | native-channel-beta | 0.7.1-beta.1 |
| dev | OFF | native-channel-dev | 0.7.1-dev.1 |

Each channel reads only
`https://github.com/nu4ddi4/security-lab-game/releases/download/native-channel-CHANNEL/update.json`.
The manifest identifies app, platform, channel, version, full commit, install
layout, installer byte count, installer SHA-256 and resulting EXE SHA-256.
The installer URL must name the same channel and version:
`native-CHANNEL-vVERSION/SecurityLabSetup.exe`. Mismatched channels, older/equal
versions, arbitrary hosts, userinfo, fragments and malformed fields are rejected.
GitHub asset redirects are followed explicitly through its HTTPS asset hosts.

`godot/resources/build_info.json` is baked into the PCK and also installed next
to SecurityLab.exe. Both identities must match. The source build is dev/OFF;
the package builder creates stable/ON or beta/dev/OFF metadata before exporting
and restores source files afterwards. Never reuse an EXE with another build_info.
Preferences are also channel-specific; enabling stable never opts beta/dev in.

- Runtime: `godot/scripts/update_policy.gd`, `update_manager.gd`.
- Worker: `godot/resources/native_update_helper.ps1`.
- Installer: `installer/SecurityLab.iss`, `scripts/godot-update-build.ps1`.
- Publisher: `.github/workflows/native-update.yml`, `scripts/godot-update-release.py`.

The installer uses user privileges, a channel-specific directory under
`%LOCALAPPDATA%\Programs\SecurityLab-CHANNEL` and a separate uninstall identity.
The original Godot user-data name and save format remain unchanged. Channels
share existing progress; they do not share installation directories.

## Download, installation and recovery

Startup check and download run asynchronously. A ready update installs on normal
exit, or through Settings → save and install. The automatic-check checkbox opts
out persistently. An offline or rejected update leaves the game usable.

1. Download to an unpredictable private `user://updates/TOKEN` directory; verify
   exact size and SHA-256. Before installation, recheck identity/hash and save
   progress successfully. Save failure keeps the game open.
2. Extract the fixed worker and write a data-only transaction. Launch the system
   Windows PowerShell directly, without cmd interpolation, PATH lookup or a shell
   generated from manifest data. It rejects UNC, ADS, ambiguous paths, junctions,
   wrong channels, another running instance and wrong parent executable.
3. The worker holds the installer against writes/deletion, verifies it, then
   acknowledges readiness. Only then does the game exit. The worker waits for
   that exact process to finish; it does not kill the running game.
4. Back up and hash every installed file, both progress files and this channel's
   HKCU uninstall entry. Reverify immediately before executing silent Inno setup.
5. Validate the resulting EXE hash and build identity, then relaunch with updates
   temporarily disabled. Startup acknowledges the nonce/version/PID only after
   the real game has initialized and the saved progress decodes successfully.
6. Remove the installation backup only after health acknowledgement and a short
   live-process check. Nonzero installer exit, wrong output or failed startup
   restores the full installation, progress and uninstall registry, then launches
   the old game with updates disabled. Restore failure preserves backup/journal
   and reports `recovery_required`, without deleting them.

Logs, transaction and result JSON remain under the token directory. Power loss,
forced termination of the worker, failed restore/disk problems may require manual
recovery from that journal/backup. No claim of power-loss atomicity is made.

## Flags and local verification

Use Godot's `--` separator, for example:

```powershell
SecurityLab.exe -- --force-update-check
SecurityLab.exe -- --disable-updates
SecurityLab.exe -- --force-update-check --allow-local-update-url --update-url=http://127.0.0.1:8080/dev/update.json
```

`--disable-updates` overrides force. Local tests accept only literal localhost or
127.0.0.1 with a valid port and the current channel path. The setup must come from
the same loopback origin at `/CHANNEL/SecurityLabSetup.exe`. Normal builds never
accept HTTP. First install SecurityLabSetup.exe to establish a managed identity;
the existing unmanaged portable EXE is not silently converted.

```powershell
python scripts/ci-godot-test.py --godot <Godot-4.7.2-console>
./tests/native/security_windows_updater.ps1 -Iscc <Inno-6-ISCC.exe>
python scripts/godot-update-network-test.py --godot <Godot-4.7.2-console>
./scripts/godot-update-build.ps1 -Godot <Godot-4.7.2-console> -Iscc <ISCC.exe> -Channel dev -Version 0.7.1-dev.1
```

Local checks: 452 existing native assertions; 90 updater policy assertions;
47 Windows checks using real Inno fixtures (including install/startup rollback,
quoted Korean/metacharacter paths, file pinning, saves, junctions and a second
instance); 13 real HTTPRequest scenarios on loopback, including save failure,
blocked redirects, helper launch and save-aware health acknowledgement. Tests
use isolated fixture installs/progress, not the player's real installation.
These fixtures are distinct from the full-game mission play verification.

## CI and publication

Existing scoped Test and native Windows EXE exports remain. New updater policy
checks are added to the fast native job. The dedicated Native update package job
builds SecurityLabSetup.exe, update.json and build_info.json and exercises the
Windows/loopback tests. Feature-branch pushes and default manual runs produce
artifacts only. They do not publish to any live channel.
CI uses pinned Inno 6.7.3 after SHA-256 and publisher verification, rather than
the runner's unrelated compiler installation.

Publication requires the original repository, godot-port or a `native-CHANNEL-vVERSION`
tag, and a commit contained in godot-port. A successful package precedes publish.
Version releases are not overwritten; per-channel publication is serialized and
refuses older/equal channel versions. The immutable versioned installer is
published before updating that channel's manifest. Native releases use
`--latest=false`, preserving the web release channel. To activate live channels,
merge this feature and explicitly publish one verified version per channel.

## Limits before production

- No signing certificate is configured. SHA-256 plus fixed HTTPS GitHub origins
  protects delivery integrity, not a compromised maintainer/account or a hostile
  process already running as the same Windows user. Authenticode signing remains
  a production distribution decision.
- Startup health is a short initialization/save-compatibility check, not a
  guarantee of long-session stability. Download resume and automatic recovery
  after power loss are not implemented.
- Inno is per-user; admin-owned/manual installs are not a supported migration.
- The previous engine shutdown resource warnings remain outside this feature.

References: [Godot HTTPRequest](https://docs.godotengine.org/en/stable/classes/class_httprequest.html), [Inno user privileges](https://jrsoftware.org/ishelp/topic_setup_privilegesrequired.htm).
