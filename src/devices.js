// Stable runtime bindings for the five existing, immutable Blender anchors.
// Only built-in simulation commands are executable; no metadata supplies code.
export const DEVICES = Object.freeze({
  'INTERACT_AdminPC': {label:'관제 / 분석 PC', tool:'admin', zone:'관제석 · SOC CONTROL'},
  'INTERACT_ServerRack': {label:'자료 서버', tool:'terminal', zone:'서버실 · SERVER ROOM'},
  'INTERACT_Router': {label:'네트워크 방화벽', tool:'settings', zone:'네트워크 실습 · NETWORK PRACTICE'},
  'INTERACT_FileCabinet': {label:'승인 원본 보관함', tool:'files', zone:'자료 보관 구역'},
  'INTERACT_Whiteboard': {label:'실습 안내', tool:'brief', zone:'실습 구역 · SECURITY TRAINING'},
});
const BINDINGS = {
  tutorial: {'INTERACT_AdminPC':['help','inspect approval']},
  services: {'INTERACT_ServerRack':['scan club-server','inspect club-server 443','inspect club-server 8080']},
  login: {'INTERACT_AdminPC':['inspect login']},
  integrity: {'INTERACT_FileCabinet':['inspect baseline'], 'INTERACT_AdminPC':['hash files']},
};
export function deviceCommands(mission, device) {return BINDINGS[mission]?.[device] ?? [];}
export function requiredDevices(mission) {return Object.keys(BINDINGS[mission] ?? {});}
export function revisitDevice(mission) {return {services:'INTERACT_ServerRack',login:'INTERACT_AdminPC',integrity:'INTERACT_AdminPC'}[mission]??null;}
export function deviceTask(mission,device) {
  if(!deviceCommands(mission,device).length)return '조사 위치 안내';
  if(mission==='tutorial')return '조사 승인서 확인';
  if(mission==='services')return '서비스 상태 조사';
  if(mission==='login')return '로그인 기록 조사';
  return device==='INTERACT_FileCabinet'?'승인 원본 기준 조사':'파일 해시 비교';
}
export function deviceTool(mission,device) {
  const tool=DEVICES[device]?.tool;
  if(tool==='admin')return mission==='tutorial'?{tab:'terminal',label:'조사 노트 · 터미널'}:mission==='integrity'?{tab:'files',label:'파일 비교'}:{tab:'settings',label:'정책 설정'};
  return {tab:tool,label:{terminal:'터미널',settings:'접근 정책',files:'파일 비교',brief:'조사 안내'}[tool]??'상세 도구'};
}
