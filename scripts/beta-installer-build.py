"""Package the verified beta EXE without changing its baked identity."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

from release_version import build_version, channel, parts, tag


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--iscc', required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    version = build_version(root / 'godot')
    exe = root / ('prototype-dist/' + tag(version) + '.exe')
    expected = exe.with_suffix('.sha256').read_text().strip()
    digest = hashlib.sha256(exe.read_bytes()).hexdigest()
    if expected != digest + '  ' + exe.name:
        raise ValueError('Beta installer input differs from the verified EXE')
    metadata = json.loads((exe.parent / 'build_info.json').read_text())
    sha = subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
    if (metadata.get('app_id') != 'security-lab-beta' or metadata.get('channel') != channel(version)
            or metadata.get('version') != version or metadata.get('commit') != sha):
        raise ValueError('Verified EXE identity differs from this beta source')
    if not re.fullmatch(r'[0-9a-f]{64}', metadata.get('compat', '')):
        raise ValueError('The verified EXE carries no game-data compat key')
    pack = exe.with_name('SecurityLabContent.pck')
    pack_digest = hashlib.sha256(pack.read_bytes()).hexdigest()
    if pack.with_suffix('.sha256').read_text().strip() != pack_digest + '  ' + pack.name:
        raise ValueError('The game-data pack differs from its verified checksum')
    payload = exe.parent / 'payload'
    payload.mkdir(exist_ok=True)
    shutil.copyfile(exe,payload/'SecurityLab.exe')
    (payload/'build_info.json').write_text(json.dumps(metadata))
    (payload/'securitylab.install.json').write_text(json.dumps({'app_id':'security-lab-beta','channel':channel(version),'install_layout':1}))
    shutil.copyfile(root/'godot/LICENSES.txt',payload/'LICENSES.txt')
    subprocess.run([args.iscc,'/Qp','/DSourceDirectory='+str(payload),'/DOutputDirectory='+str(exe.parent),
                    '/DChannel='+channel(version),'/DAppVersion='+metadata['version'],'/DBinaryVersion='+'.'.join(map(str, parts(version))),
                    str(root/'installer/SecurityLabBeta.iss')],check=True)
    installer=exe.parent/'SecurityLabSetup.exe'
    manifest={key:metadata[key] for key in ['schema','app_id','platform','install_layout','channel','version','commit']}
    manifest.update({'installer_url':'https://github.com/nu4ddi4/security-lab-game/releases/download/'+tag(version)+'/SecurityLabSetup.exe',
                     'size':installer.stat().st_size,'sha256':hashlib.sha256(installer.read_bytes()).hexdigest(),'exe_sha256':digest})
    # Installed executables with the same compat key can take just the data pack.
    manifest.update({'compat':metadata['compat'],
                     'content_url':'https://github.com/nu4ddi4/security-lab-game/releases/download/'+tag(version)+'/SecurityLabContent.pck',
                     'content_size':pack.stat().st_size,'content_sha256':pack_digest})
    (exe.parent/'update.json').write_text(json.dumps(manifest,indent=2))
    installer.with_suffix('.sha256').write_text(manifest['sha256']+'  '+installer.name+'\n')
    # The beta product uses a separate manifest and installer; Native publication is untouched.
    print('BETA_INSTALLER',json.dumps({'version':version,'commit':sha,'sha256':manifest['sha256']}))


if __name__=='__main__': main()
