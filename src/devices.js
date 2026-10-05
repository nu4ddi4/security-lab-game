// Stable runtime bindings for the five existing, immutable Blender anchors.
// Only built-in simulation commands are executable; no metadata supplies code.
export const DEVICES = Object.freeze({
  'INTERACT_AdminPC': {label:'관제 / 분석 PC', tool:'admin'},
  'INTERACT_ServerRack': {label:'자료 서버', tool:'terminal'},
  'INTERACT_Router': {label:'네트워크 방화벽', tool:'settings'},
  'INTERACT_FileCabinet': {label:'승인 원본 보관함', tool:'files'},
  'INTERACT_Whiteboard': {label:'실습 안내', tool:'brief'},
});
const BINDINGS = {
  tutorial: {'INTERACT_AdminPC':['help','inspect approval']},
  services: {'INTERACT_ServerRack':['scan club-server','inspect club-server 443','inspect club-server 8080']},
  login: {'INTERACT_AdminPC':['inspect login']},
  integrity: {'INTERACT_FileCabinet':['inspect baseline'], 'INTERACT_AdminPC':['hash files']},
};
export function deviceCommands(mission, device) {return BINDINGS[mission]?.[device] ?? [];}
export function requiredDevices(mission) {return Object.keys(BINDINGS[mission] ?? {});}
export function revisitDevice(mission) {return mission==='services'?'INTERACT_ServerRack':mission==='tutorial'?null:'INTERACT_AdminPC';}
export function deviceTask(mission,device) {
  if(deviceCommands(mission,device).length) return mission==='integrity'&&device==='INTERACT_FileCabinet'?'승인 원본 기준 조사':'장비 상태 조사 / 재확인';
  if(device==='INTERACT_Router')return '방어 설정은 F · 네트워크 장비';
  return '현재 사건의 조사 위치 안내';
}
