// Development-only export of authored definitions; no JavaScript runs in Godot.
import fs from 'node:fs';
import {MISSIONS, ORIGINAL_FILES, TAMPERED_BUDGET, COMMON_PASSWORDS, NORMAL_PASSWORD} from '../src/missions.js';
import {DEVICES, requiredDevices, revisitDevice, deviceCommands} from '../src/devices.js';
const missions=MISSIONS.map(m=>({...m,required_devices:requiredDevices(m.id),revisit_device:revisitDevice(m.id),device_commands:Object.fromEntries(requiredDevices(m.id).map(id=>[id,deviceCommands(m.id,id)]))}));
fs.mkdirSync('godot/resources',{recursive:true});
fs.writeFileSync('godot/resources/definitions.json',JSON.stringify({baseline:'v0.7.0',missions,devices:DEVICES,original_files:ORIGINAL_FILES,tampered_budget:TAMPERED_BUDGET,common_passwords:COMMON_PASSWORDS,normal_password:NORMAL_PASSWORD},null,2)+'\n');
